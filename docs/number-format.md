# Number format engine

`XlsxNumberFormatter` shows a cell value as Excel for Mac does: it applies the
cell's number format code and returns an `XlsxFormattedValue`. It reads no
file and draws nothing; a viewer (or an importer that wants display text)
calls it with a value and the `numberFormatId` and `numberFormat` the reader
gives. Decision [`0008`](decisions/0008-number-format-engine.md) sets the
scope; the design is
[`superpowers/specs/2026-10-29-number-format-engine-design.md`](superpowers/specs/2026-10-29-number-format-engine-design.md)
(git-ignored, so not repository history).

This page covers milestone N1, numbers: sections and conditions, fixed point,
grouping and scaling, scientific, fractions, `General`, text, and the limits
that make a hostile code harmless. Dates and times, the `de-DE` and `tr-TR`
locales and the oracle come in N2 and N3. Rows marked "until N2" are interim
and N2 deletes or rewrites exactly those tests.

## API

```dart
final XlsxNumberFormatter formatter = XlsxNumberFormatter();
final XlsxFormattedValue shown = formatter.format(
  XlsxDecimal('-1234.5'),
  numberFormat: '#,##0.00;(#,##0.00)',
);
print(shown.text); // (1,234.50)
```

- `format(value, {numberFormatId, numberFormat, generalWidth})`: `value` is an
  `XlsxDecimal`, a `num`, a `DateTime`, a `Duration`, a `String`, a `bool`, an
  `XlsxErrorValue` or `null`. `numberFormat` wins over `numberFormatId`.
  `generalWidth` (default 11) is how many characters `General` may use.
- `formatCell(cell)`: `format` of an `XlsxReadCell`'s value and number format.
- `XlsxFormattedValue`: `text` (each padding as one space, each fill left
  out), `parts` (`XlsxFormatText`, `XlsxFormatPadding`, `XlsxFormatFill`, for
  a viewer that lays the cell out), `color`, `overflow` (Excel shows `#`
  whatever the width) and `warning`.
- `XlsxFormatLocale`: separators and words. Only `enUS` ships in N1; a
  caller can build another with the public constructor.

`format` never throws for any code and any supported value. A value of
another type, or a `generalWidth` below 1, is a programmer error and throws
`ArgumentError`.

## Rules the engine enforces

### Codes, sections and the limits

| Rule | Behaviour | Why | Test |
|---|---|---|---|
| Code resolution | `numberFormat` wins over the id; id 0 is `General`; a built-in id uses the built-in table; any other id without a code is `General` with `unresolvedNumberFormat` | the reader gives a code only for custom ids | `test/xlsx/format/formatter_test.dart` |
| Invalid code | an unterminated quote or bracket, more than four sections, more than two conditions or a code over 255 UTF-16 units shows the value as `General` with `numberFormatInvalid` | Excel refuses such a code; the parser still returns what it scanned, so the reader's classifier works on any code | `test/xlsx/format/formatter_test.dart`, `test/xlsx/format/format_code_test.dart` |
| Output bound | a result over 1,000 characters is replaced by `General` with `numberFormatInvalid` | `0` followed by 254 `%` on `1E+308` would otherwise be thousands of characters | `test/xlsx/format/formatter_test.dart` |
| Bounded cache | at most 1,024 parsed codes, cleared when full | a file with 300,000 codes costs time, not memory | `test/xlsx/format/formatter_test.dart` |
| Any code, any value | `format` throws nothing; `text` is at most 1,000 characters; `parts` joined equal `text`. Seeds 1 to 4 (200 cases each) run in the gate, on the VM and in Chrome | a file's code is untrusted | `test/xlsx/format/fuzz_test.dart`, `tool/fuzz_formatter.dart` |
| Sections | `positive;negative;zero;text`; one section takes all numbers, two give positive and zero then negative, three give positive, negative, zero; an empty section shows nothing | ECMA-376, MS-OI29500 | `test/xlsx/format/section_choice_test.dart` |
| Conditions | `[=n] [<n] [<=n] [>n] [>=n] [<>n]` replace the implied rules; a value takes the first section whose condition holds; no section matching is `overflow` with text `#` | ECMA-376 | `test/xlsx/format/section_choice_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| Minus sign in sections | a value in an explicit negative section is shown as its absolute value; a two-section code with an unconditioned second section keeps the automatic minus only when the first condition is `=`, `>` or `>=` with a value of 0 or more | observed rule of numfmt and the research notes; unconfirmed, see Unknowns | `test/xlsx/format/section_choice_test.dart` |
| `@` as the only section | a number shows as `General` (a text-only single section) | SSF; unconfirmed | `test/xlsx/format/value_renderer_test.dart` |
| Text | a text value takes the fourth section or the section holding `@`, otherwise it is unchanged; text never takes a conditional section; `@` twice repeats the text | ECMA-376 | `test/xlsx/format/value_renderer_test.dart`, `test/xlsx/format/section_choice_test.dart` |
| Booleans, errors, empty | a boolean shows `TRUE`/`FALSE` and an error value its code, whatever the code; `null` is empty | Excel ignores the code for them | `test/xlsx/format/value_renderer_test.dart` |
| NaN and infinity | `#NUM!` | only a `num` can hold them | `test/xlsx/format/value_renderer_test.dart` |

### Numbers

| Rule | Behaviour | Why | Test |
|---|---|---|---|
| Excel's number | a value is parsed with `double.parse` and written with 15 significant digits; the only `double` use besides the fraction approximation | Excel stores a double and shows 15 digits, so `0.30000000000000004` shows `0.3` | `test/xlsx/format/excel_number_test.dart` |
| Rounding | scaling and rounding happen on that digit string, half away from zero, never with `toStringAsFixed` | `2.675` with `0.00` shows `2.68` as in Excel, on the VM and in JavaScript alike | `test/xlsx/format/excel_number_test.dart`, `test/xlsx/format/number_renderer_test.dart` |
| Digit placeholders | `0` pads with a zero, `#` shows nothing, `?` a space; the first `.` is the decimal point | ECMA-376 | `test/xlsx/format/number_renderer_test.dart` |
| Grouping and scaling | `,` between placeholders groups, after the last placeholder it divides by 1000 each; `%` multiplies by 100 each; separators come from the locale | ECMA-376, MS | `test/xlsx/format/number_renderer_test.dart` |
| Literals, padding, fill | `"..."`, `\x` and the unquoted literal characters are copied; `_x` becomes `XlsxFormatPadding`, `*x` an `XlsxFormatFill` | a viewer needs the width of `_)` and the fill | `test/xlsx/format/number_renderer_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| Negative zero | a value whose rounded digits are all zero shows no minus and takes the sign-free path | ruling of the plan; unconfirmed | `test/xlsx/format/number_renderer_test.dart` |
| Scientific | `E+`, `E-` (and `e+`, `e-`), the mantissa kept between 1 and 10, engineering mantissas for `##0.0E+0`; `%` and `,` do not scale in a scientific code | SSF, numfmt | `test/xlsx/format/number_renderer_test.dart` |
| Fractions | `# ?/?`, `# ??/??`, fixed denominators such as `?/8`; best approximation by continued fractions within the denominator's digits; denominators are right-padded with spaces | MS-OI29500, SSF | `test/xlsx/format/number_renderer_test.dart` |
| `General` | integers below 10^11 in full; otherwise fixed with the most digits that fit `generalWidth` (11), trailing zeros dropped; otherwise scientific. A section holding `General` and literals adds the literals | ECMA-376 §18.8.30; the algorithm is SSF's and numfmt's | `test/xlsx/format/general_test.dart` |
| Locale separators | the decimal point and the group separator come from `XlsxFormatLocale`, not from the code | the code in a file is invariant | `test/xlsx/format/format_locale_test.dart`, `test/xlsx/format/number_renderer_test.dart`, `test/xlsx/format/general_test.dart` |
| Built-in table | ids 0 to 49 map to the ECMA-376 codes; the `enUS` locale's table for ids 5 to 8, 14 to 22 and 37 to 44 comes from LibreOffice's import table | the reader passes the invariant code | `test/xlsx/format/format_locale_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Color | `[Red]` and the other names are `XlsxColor.rgb`; `[ColorN]` is the indexed color N + 7 | the viewer resolves indexed colors with the workbook's palette | `test/xlsx/format/formatter_test.dart` |

### Interim rules, until N2

| Rule | Behaviour | Why | Test |
|---|---|---|---|
| Date and time sections (until N2) | a number in a date or time section shows as `General` | the date renderer is N2 | `test/xlsx/format/value_renderer_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Negative number in a date section (until N2) | shows `-General`; Excel shows `#` | N2 sets `overflow` there | `test/xlsx/format/value_renderer_test.dart` |
| `DateTime` and `Duration` (until N2) | `toIso8601String()` and `Duration.toString()` | N2 maps them back to serials | `test/xlsx/format/value_renderer_test.dart` |
| Brackets `[DBNum1]`, `[B2]` and similar (until N2) | read as empty literals; no `numberFormatUnsupported` yet | the code is added in N2 | `test/xlsx/format/format_code_test.dart` |
| Locales (until N2) | only `enUS`; booleans and errors use English words; no `numberFormatLocaleDependent` | `de-DE` and `tr-TR` come in N2 | `test/xlsx/format/format_locale_test.dart` |

## Unknowns

No Microsoft source confirms these; the owner's Excel for Mac settles them
and the rule changes with a test where Excel disagrees. The list is §10 of the
design, with what the code does today.

1. Rounding: `2.675`, `1.005`, `0.285` with `0.00`; `-2.5` with `0`.
2. Negative zero: `-0.4` with `0`, `-0.001` with `0.00`, `-0.4` with
   `#,##0;(#,##0)`.
3. Conditions: the minus in `[<0]"neg "0;"other "0` with -5 (the two-section rule above);
   `[>100]0` alone with 50 (`#` today).
4. Month and day names in `de-DE` and `tr-TR` (N2).
5. AM/PM in `tr-TR` and `de-DE` (N2).
6. Built-ins 15 to 22 in `de-DE` and `tr-TR` (N2).
7. `tr-TR` currency ids 5 to 8 and 37 to 44 (N2).
8. `[$-F800]` and `[$-F400]` per locale (N2).
9. Time carry past midnight (N2).
10. Negative times in a 1904 workbook (N2).
11. Serial 0 and the weekdays of serials 1 to 59 (N2).
12. Lowercase `e+`.
13. Fractions: `0.333` with `# ?/?`, `3.14159` with `# ??/??` (pinned as `3 14/99`),
    `0` with `# ?/?`.
14. `General` at the default width: `123456789012`, `1/3`, `-1/3`,
    `0.000012345678`, `12345.6789012`.
15. `y`, `yyy`, `yyyyy`; a literal `/` in `de-DE`; `ss.00` in `de-DE` (N2).
16. Booleans with a number format.
17. `#SPILL!` and `#CALC!` in `de` and `tr` (N2).
18. More than four sections or three conditions in a file.
19. `@` alone on a number (shows `General` today; `"Name: "@` on a number
    shows `General` without the literal).
20. A file's own `<numFmt>` for a built-in id (N2).

Further own rules the oracle should check, found while building N1:

- The `enUS` codes for ids 37 to 40 follow LibreOffice (`#,##0_);(#,##0)`),
  not ECMA (`#,##0 ;(#,##0)`).
- Commas: `0,.0`, a comma inside a fraction and `?` with grouping are own
  rules; only the whole part groups in a fraction. A literal `,` prints `,`,
  not the locale's group separator.
- Scientific: `.00E+00` keeps a mantissa below 1; `000.0E+0` is not
  engineering.
- Fractions: `?/?` on 2 shows `2/1`; `# ?/?` on 0 shows `0` and blanks; `# #/#`
  on 2 shows `2 `; a `0` placeholder stops the blanking of a zero fraction;
  `# 00/00` padding and the carry of a fixed denominator.
- `General`: a number with an exponent of -5 or less is always scientific
  (`0.00001` shows `1E-05`); widths other than 11 are unchecked, and a tiny
  width returns the shortest scientific form where Excel shows `#`.
- A subnormal `double` is rendered as is; Excel has no denormals.

## Fuzzing

`test/xlsx/format/fuzz_test.dart` formats seeded cases and requires no throw, a
`text` of at most 1,000 characters and `parts` that join to `text`. A case is
a corpus code (every built-in code, the `enUS` table, the number formats of
`allFixtures()` and the codes of the format tests) with up to three mutations
(insert, delete or duplicate a character of `0#?.,%E+-/@"\_*[];$` or a letter,
repeat a slice, splice two codes), and a value: a random `XlsxDecimal` of up to
30 digits (now and then up to 309, or a tiny one), a `double` of such digits,
NaN, infinity, a string, a boolean, an error, a `DateTime`, a `Duration` or
`null`, with a random `generalWidth`. The gate runs seeds 1 to 4 with 200
cases each, the same cases on the VM and in Chrome. For longer runs:

```bash
dart run tool/fuzz_formatter.dart --seeds 1-200 --cases 1000
```

It prints each failure as `seed <s> case <i>: <code> <value> width <w>:
<problem>` and exits 1 on any. A failure is a formatter defect: pin it as a
unit test in the owning `test/xlsx/format/*_test.dart` with the input
minimized by hand, then fix it. The owner manifest lists no file yet, so it
adds no codes.
