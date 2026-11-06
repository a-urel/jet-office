# Number format engine

`XlsxNumberFormatter` shows a cell value as Excel for Mac does: it applies the
cell's number format code and returns an `XlsxFormattedValue`. It reads no
file and draws nothing; a viewer (or an importer that wants display text)
calls it with a value and the `numberFormatId` and `numberFormat` the reader
gives. Decision [`0008`](decisions/0008-number-format-engine.md) sets the
scope; the design is
[`superpowers/specs/2026-10-29-number-format-engine-design.md`](superpowers/specs/2026-10-29-number-format-engine-design.md)
(git-ignored, so not repository history).

This page covers milestones N1 to N3. N1 is numbers: sections and
conditions, fixed point, grouping and scaling, scientific, fractions,
`General`, text, and the limits that make a hostile code harmless. N2 is
dates, times and locales: date and time tokens, elapsed time, AM/PM, the
1900 and 1904 date systems, `DateTime` and `Duration` values, locale tags
and system formats, and the `de-DE` and `tr-TR` locales with their built-in
codes. N3 is the oracle and release readiness: workbooks the owner opens in
Excel for Mac, a test that compares the formatter with Excel's CSVs of
them ("Excel as the oracle"), a LibreOffice second opinion, the N2
deferred minors settled ("Recorded, not changed") and a benchmark
("Speed"). The owner's runs in `en-US`, `de-DE` and `tr-TR` settled the
Unknowns ("Settled by Excel") and the owner checklist below.

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
  `XlsxErrorValue` or `null`. `numberFormat` wins over `numberFormatId`,
  except for the built-in ids that follow the locale (see "Locales").
  `generalWidth` (default 11) is how many characters `General` may use.
- `formatCell(cell)`: `format` of an `XlsxReadCell`'s value and number format.
- `XlsxFormattedValue`: `text` (each padding as one space, each fill left
  out), `parts` (`XlsxFormatText`, `XlsxFormatPadding`, `XlsxFormatFill`, for
  a viewer that lays the cell out), `color`, `overflow` (Excel shows `#`
  whatever the width) and `warning`.
- `XlsxNumberFormatter({locale, date1904})`: the locale (default `enUS`)
  and the workbook's date system (`XlsxReader.date1904`).
- `XlsxFormatLocale`: separators, names, words and built-in codes. `enUS`,
  `deDE` and `trTR` ship; a caller can build another with the public
  constructor.

`format` never throws for any code and any supported value. A value of
another type, or a `generalWidth` below 1, is a programmer error and throws
`ArgumentError`.

### Speed

On an Apple M3 Pro, `formatCell` costs about 1.4 µs a cell on the VM and
2.3 µs in Chrome: a serial date about 2.2 and 1.6 times a number, a
`DateTime` about 3.8 and 3.7 times. The method and every figure are in
[`benchmark.md`, "Format figures"](benchmark.md#format-figures); they are
records, not thresholds.

## Rules the engine enforces

### Codes, sections and the limits

| Rule | Behaviour | Why | Test |
|---|---|---|---|
| Code resolution | `numberFormat` wins over the id, except for the ids that follow the locale ("Locales"); id 0 is `General`; a built-in id uses the built-in table; an id from 164 without a code is `General` with `unresolvedNumberFormat` | the reader gives a code only for custom ids | `test/xlsx/format/formatter_test.dart` |
| Invalid code | an unterminated quote or bracket (the parse is `truncated`), more than four sections, more than two conditions, two conditions in one section, a condition without a number, `[ColorN]` with N outside 1 to 56, a lowercase exponent `e+` or `e-`, a fixed fraction denominator of ten or more digits, `@` in more than one section, two locale tags `[$…-…]` in one section, or a code over 255 UTF-16 units shows the value as `General` with `numberFormatInvalid` | Excel refuses such a code: Excel for Mac repairs `u12-01`, `u12-03`, `u13-07`, `c19-01` and `c8b-01` to `General` on load and shows `u18-01` to `u18-03` and `c15c-01` as `General`; the parser still returns what it scanned, so the reader's classifier works on any code | `test/xlsx/format/formatter_test.dart`, `test/xlsx/format/format_code_test.dart` |
| Output bound | a result to which the code adds over 1,000 characters is replaced by `General` with `numberFormatInvalid`. For a number that is the whole result; for text it is the literals and each `@` after the first, checked before the text is built. A text shown unchanged (no text section, `General` or `@` alone) is never over the bound, however long | `0` followed by 254 `%` on `1E+308` would otherwise be thousands of characters, and `@` 255 times on a 1 MiB text 255 MiB | `test/xlsx/format/formatter_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| Code length | a code over 255 characters is `General` with `numberFormatInvalid` at once, neither parsed nor cached | a 1 MiB code would otherwise cost a token per character in the cache | `test/xlsx/format/formatter_test.dart` |
| Bounded cache | at most 1,024 parsed codes, cleared when full | a file with 300,000 codes costs time, not memory | `test/xlsx/format/formatter_test.dart` |
| Any code, any value | `format` throws nothing; `text` is at most 1,000 characters longer than a text value; `parts` joined equal `text`. Seeds 1 to 4 (200 cases each) run in the gate, on the VM and in Chrome | a file's code is untrusted | `test/xlsx/format/fuzz_test.dart`, `tool/fuzz_formatter.dart` |
| Sections | `positive;negative;zero;text`; one section takes all numbers, two give positive and zero then negative, three give positive, negative, zero; an empty section shows nothing | ECMA-376, MS-OI29500 | `test/xlsx/format/section_choice_test.dart` |
| Conditions | `[=n] [<n] [<=n] [>n] [>=n] [<>n]` replace the implied rules; a value takes the first section whose condition holds; no section matching is `overflow` with text `#` (`[>100]0;[<-100]0` on 50). A code whose only section has a condition is chosen as if `;General` followed it (`[>100]0` on 50 shows `50`) | ECMA-376; Excel for Mac, oracle `u03-03`, `u03-06` (Excel repairs `[>100]0` to `[>100]0;General` on load) | `test/xlsx/format/section_choice_test.dart`, `test/xlsx/format/value_renderer_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Minus sign in sections | a value in an explicit negative section is shown as its absolute value; an unconditioned second section never shows the automatic minus, also after a condition (`[>0]0;0` shows -5 as `5`); a conditioned section, first or second, shows it unless only negatives meet its condition (`[>10]0;[<5]0` shows -2 as `-2`); the `General` Excel adds after a lone conditional section keeps it (`[>100]0` shows -50.5 as `-50.5`) | Excel for Mac, oracle `u03-01`, `u03-04`, `u03-05` in tr-TR, en-US and de-DE; the conditioned second section and the `General` minus are assumed, unconfirmed by Excel | `test/xlsx/format/section_choice_test.dart` |
| `@` as the only section | a number shows as `General` (a text-only single section; `"Name: "@` on 5 shows `5`) | SSF; Excel for Mac, oracle `u19-01`, `u19-02` | `test/xlsx/format/value_renderer_test.dart` |
| Text | the text section is the last: the fourth, or with fewer sections the last one when it holds `@` and has no condition, never an earlier one (`"x"@;0` leaves text unchanged); without one text is unchanged; `@` twice in one section repeats the text | ECMA-376; Microsoft puts text last; Excel for Mac, oracle `u19-05`, `u19-07`; `"x"@;0` is SSF's rule, unconfirmed | `test/xlsx/format/value_renderer_test.dart`, `test/xlsx/format/section_choice_test.dart` |
| Numbers beside a text section | a text section of a two- or three-section code takes no number; numbers choose among the sections before it by the rules for that many: `0;@` shows -5 as `-5`, `0;-0;@` shows 0 with the first section, as `0;-0` would | Excel for Mac, oracle `u19-03`, `u19-04`, `u19-06` | `test/xlsx/format/section_choice_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| Booleans, errors, empty | a boolean shows the locale's `trueText`/`falseText` and an error value the locale's name for its code (as written when the locale has none), whatever the code; `null` is empty | Excel ignores the code for them: `0.00`, `General` and `"yes";"no";"zero";@` all show the region's word (oracle `c16-01` to `c16-06`) | `test/xlsx/format/value_renderer_test.dart` |
| NaN and infinity | `#NUM!` | only a `num` can hold them | `test/xlsx/format/value_renderer_test.dart` |

### Numbers

| Rule | Behaviour | Why | Test |
|---|---|---|---|
| Excel's number | a value is parsed with `double.parse` and written with 15 significant digits; the only `double` use besides the fraction approximation | Excel stores a double and shows 15 digits, so `0.30000000000000004` shows `0.3` | `test/xlsx/format/excel_number_test.dart` |
| Subnormal numbers | a `double` below 2.2250738585072014E-308 in magnitude is zero (`1E-320` shows `0` in `General`, `-1E-320` shows `0.00E+00`) | Excel has no denormals | `test/xlsx/format/excel_number_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Rounding | scaling and rounding happen on that digit string, half away from zero, never with `toStringAsFixed` | `2.675` with `0.00` shows `2.68` as in Excel (oracle `u01-01` to `u01-08`), on the VM and in JavaScript alike | `test/xlsx/format/excel_number_test.dart`, `test/xlsx/format/number_renderer_test.dart` |
| Digit placeholders | `0` pads with a zero, `#` shows nothing, `?` a space; the first `.` is the decimal point | ECMA-376 | `test/xlsx/format/number_renderer_test.dart` |
| Grouping and scaling | `,` between placeholders groups, after the last placeholder it divides by 1000 each; `%` multiplies by 100 each; separators come from the locale | ECMA-376, MS | `test/xlsx/format/number_renderer_test.dart` |
| Literals, padding, fill | `"..."`, `\x` and the unquoted literal characters are copied; `_x` becomes `XlsxFormatPadding`, `*x` an `XlsxFormatFill` | a viewer needs the width of `_)` and the fill | `test/xlsx/format/number_renderer_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| Negative zero | a value whose rounded digits are all zero shows no minus; it keeps the section its sign chose (`#,##0;(#,##0)` on -0.4 shows `(0)`) | Excel for Mac, oracle `u02-01` to `u02-03` | `test/xlsx/format/number_renderer_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Scientific | `E+` and `E-` (a lowercase `e` makes the code invalid). With one integer placeholder the mantissa is kept between 1 and 10; with two or more the exponent is a multiple of their count and the integer part is zero-padded to `0` placeholders (`000.0E+0` on 12345 shows `012.3E+3`; `##0.0E+0` is engineering). A zero shows one `0` in the integer part (`#.##E+0` shows `0.E+0`); `.00E+00` keeps a mantissa below 1 (`.50E+00`). `%` and `,` do not scale in a scientific code | SSF, numfmt; Excel for Mac, oracle `u12-01` to `u12-06` | `test/xlsx/format/number_renderer_test.dart`, `test/xlsx/format/format_code_test.dart` |
| Fractions | `# ?/?`, `# ??/??`, fixed denominators such as `?/8` of at most nine digits. The fraction is the last continued-fraction convergent whose denominator fits the placeholders, not the best approximation (`# ??/??` on 3.14159 shows `3  1/7 `; so `# ?/?` on 0.1 shows `0    `, as SSF does, where the best approximation is `1/9`: unconfirmed by Excel); the numerator is right-aligned and the denominator left-aligned in the width of `?`, and a `0` placeholder zero-pads the denominator (`# 00/00` on 1.5 shows `1 01/02`). A blank fraction with no `?` and no fixed denominator drops the literals before it (`# #/#` on 2 shows `2`); a zero shown in full drops a whole part of `#` and its literals (`# 0/0` on 0 shows `0/1`) | MS-OI29500, SSF; Excel for Mac, oracle `u13-01` to `u13-09` | `test/xlsx/format/number_renderer_test.dart` |
| `General` | an integer that fits `generalWidth` (11) in full; otherwise fixed or scientific notation, whichever shows more significant digits within the width, a tie fixed (`0.00001` stays fixed, `0.000012345678` is scientific), trailing zeros dropped. A minus shown takes one of the width's characters (`-0.3333333` beside `0.33333333` at width 10). A section holding `General` and literals adds the literals | ECMA-376 §18.8.30; Excel for Mac at width 10, oracle `u14-01` to `u14-06` (by eye) | `test/xlsx/format/general_test.dart` |
| Locale separators | the decimal point and the group separator come from `XlsxFormatLocale`, not from the code | the code in a file is invariant | `test/xlsx/format/format_locale_test.dart`, `test/xlsx/format/number_renderer_test.dart`, `test/xlsx/format/general_test.dart` |
| Built-in table | ids 0 to 49 map to the ECMA-376 codes; ids 5 to 8, 14 to 22 and 37 to 44 use the locale's table instead ("Locales") | the reader passes the invariant code | `test/xlsx/format/format_locale_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Color | `[Red]` and the other names are `XlsxColor.rgb`; `[ColorN]` is the indexed color N + 7 | the viewer resolves indexed colors with the workbook's palette | `test/xlsx/format/formatter_test.dart` |

### Dates and times

A section is a date or time section when it holds a date or time token
(`y m d h s`, elapsed `[h] [m] [s]`, `AM/PM`, `A/P`, `e`, `b`, `g` or a
system format). The value is a serial: whole days since the epoch, the time
of day as the fraction. No `double` arithmetic touches it: a serial goes
through Excel's 15 significant digits and the time is rounded on those
digits, so the VM and a browser show the same.

| Rule | Behaviour | Why | Test |
|---|---|---|---|
| Rounding and truncation | the time is rounded to the second, or to the fraction of a second shown (`.0` to `.000`), then truncated: `h:mm` on 10:29:40 shows `10:29`, on 10:29:59.6 `10:30`. The carry runs through the hours into the day (`yyyy-mm-dd h:mm:ss` on 46323.99999999 shows `2026-10-29 0:00:00`; `[h]:mm:ss` on 0.99999999 `24:00:00`) | Excel for Mac, oracle `c9-01` to `c9-12`, `c9b-01`; the design's rounding to the smallest unit shown was wrong | `test/xlsx/format/excel_date_test.dart`, `test/xlsx/format/date_renderer_test.dart` |
| Fractional seconds | `.` and one to three `0` after a time token; the point shows as the locale's decimal separator (`ss,00` in de-DE). Four or more `0`, or `.` followed by `#` or `?`, make the code invalid; a quoted or escaped dot, or a dot between date tokens, is a literal | Excel accepts at most three digits; with several fraction tokens the time is rounded to the widest and each shows its leading digits (`ss.0 ss.00` shows `59.4 59.45`, `ss.0.0` `59.5.5`); Excel for Mac, oracle `c15b-02`, `c15c-01`, `c15d-01`, `c15e-01`, `c15-02`, `c15-03` | `test/xlsx/format/format_code_test.dart`, `test/xlsx/format/date_renderer_test.dart` |
| Mixed sections | a date section holding `General`, a digit placeholder (outside fractional seconds), an exponent or a fraction slash is invalid (`General` with `numberFormatInvalid`); `,` and `%` there are literals (`mmmm d, yyyy`). A date section beside a number section is fine | design §6.4 | `test/xlsx/format/format_code_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Negative values | in the 1900 system any negative value in a date or time section is `overflow` (`#`), also in an explicit negative section (`0;h:mm` on -0.5). In the 1904 system a negative value shows a `-` and the absolute value's text in any date or time section (`h:mm` on -0.25 shows `-6:00`, `yyyy-mm-dd` on -1 `-1904-01-02`, `e h` on -0.25 `-1904 6`), the minus before a leading literal, fill or padding (`_(h:mm` shows `- 6:00`), also when the value rounds to zero (`h:mm:ss` on -0.000001 shows `-0:00:00`) | Excel for Mac, oracle `c10-01` to `c10-07`, `c10b-01` | `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| Range | a serial up to 9999-12-31 23:59:59 (2958465 in the 1900 system, 2957003 in the 1904 system); the check runs after rounding, so 2958465.999999999 is `overflow`, also in an elapsed section | Excel's last date | `test/xlsx/format/excel_date_test.dart`, `test/xlsx/format/date_renderer_test.dart` |
| Serial 0 and the phantom leap day | in the 1900 system serial 0 is `1900-01-00`, 60 is `1900-02-29`, 61 is `1900-03-01`; the weekday is `(serial + 6) % 7` from Sunday, so 0 is a Saturday and 1 a Sunday. In the 1904 system 0 is Friday 1904-01-01 and every weekday is real | Lotus 1-2-3's leap year bug, which Excel keeps; Excel for Mac, oracle `c11-01` to `c11-06` | `test/xlsx/format/excel_date_test.dart`, `test/xlsx/format/date_renderer_test.dart` |
| Month or minute | `m` and `mm` are minutes after `h` or before `s`, else the month; `mmm` and longer are always the month (`h:mmm` on 0.5 shows `12:Jan`) | ECMA-376; Excel for Mac, oracle `c15-01`; one shared rule with the reader's classifier | `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/format_kind_test.dart` |
| Token lengths | `y`/`yy` two-digit year, `yyy` and longer four; `m`/`mm` month number, `mmm` abbreviation, `mmmm` and six or more the full name, `mmmmm` the first letter; `d`/`dd` day, `ddd` abbreviation, `dddd` and longer the full name; `h`/`m`/`s` longer than two show two digits; elapsed `[hhh]` pads to three; `e`/`ee` four-digit year; `b`/`bb` the Gregorian year in two digits, `bbb` and longer in four (no Buddhist +543); `g` nothing | SSF and numfmt; Excel for Mac, oracle `c15a-01` to `c15a-07`, `c4c-01` (Excel repairs `y` to `yy`, `yyy` and `yyyyy` to `yyyy` and `mmmmmm` to `mmmm` on load, with the same text) | `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/format_code_test.dart` |
| Date separator | a bare `/` in a date or time section shows the locale's `dateSeparator` (`dd/mm/yyyy` is `28.10.2026` in de-DE and tr-TR, `28/10/2026` in en-US); an escaped `\/` or a quoted `"/"` stays `/` | Excel for Mac, oracle `c15b-01` | `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/format_code_test.dart` |
| Elapsed time | `[h]`, `[m]`, `[s]` count whole hours, minutes or seconds from serial 0; minutes and seconds after an elapsed token are modulo 60 | ECMA-376 | `test/xlsx/format/date_renderer_test.dart` |
| AM/PM | `AM/PM` in any case shows `AM` and `PM` unless the section has a language tag or a system format; then the `am`/`pm` of the names' locale (the tag's, else the renderer's) (`[$-41F]h:mm AM/PM` shows `1:30 ÖS`). `A/P` shows `A`/`P` in the case written (`A/p` after noon shows `p`). Either makes `h` a 12-hour clock (0 shows 12) | Excel for Mac shows an untagged `AM/PM` in English in all three regions but tr-TR's id 18 as `1:30 ÖS`, oracle `c5-01` to `c5-08`, `c6-05`, `c6-06` | `test/xlsx/format/date_renderer_test.dart` |
| `DateTime` | its wall-clock fields, `isUtc` ignored, milliseconds and microseconds kept, in the formatter's date system; a time before the first serial is a negative serial; a year above 9999 or below 1 becomes a stand-in serial (the system's maximum + 1, or -1), so a date code shows `#` and a number code shows that stand-in, not the real serial | as the writer's `date_serial.dart` | `test/xlsx/format/excel_date_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| `Duration` | its length in days as a serial (a `Duration` of 100,000 days or more either way counts whole days only, the time of day dropped, to stay exact in JavaScript); a negative one overflows in the 1900 system and shows a minus in a 1904 date or time section | `[h]:mm` is how a sheet shows a duration | `test/xlsx/format/excel_date_test.dart`, `test/xlsx/format/value_renderer_test.dart` |
| Overflow keeps the section | a date section that overflows still reports its section (its color) and its warning | the section was chosen; a CSV shows no color, so unconfirmed | `test/xlsx/format/value_renderer_test.dart` |

### Locales

| Rule | Behaviour | Why | Test |
|---|---|---|---|
| Renderer locale | `XlsxNumberFormatter(locale: ...)` gives the separators, names, AM/PM, booleans, error names and built-in codes | the code in a file is invariant; the region is Excel's | `test/xlsx/format/format_locale_test.dart`, `test/xlsx/format/formatter_test.dart` |
| Built-in ids by locale | ids 5 to 8, 14 to 22 and 37 to 44 without a code, or with the ECMA-376 code (`mm-dd-yy` for 14, as the reader gives it), use the locale's `builtinCodes`; any other code is used as written (a file's `yyyy-mm-dd` for id 14 shows `2030-10-29` on a 1904 serial 46323) | Excel shows a built-in id in the region's form and a file's own code as written; Excel for Mac, oracle `c6-01` to `c6-09`, `c7-01` to `c7-24`, `c20-01`, `c20-02` | `test/xlsx/format/formatter_test.dart` |
| Locale-dependent ids | ids 27 to 31, 36 and 50 to 58 without a code show as the locale's id 14, ids 32 to 35 as its id 21, ids 23 to 26 and 59 to 163 as `General`, each with `numberFormatLocaleDependent`; from 164 `General` with `unresolvedNumberFormat` their code differs by region and version and a file should carry it | ruling of the plan | `test/xlsx/format/formatter_test.dart` |
| Locale tags | in a date section the low 16 bits of `[$-xxx]` choose names and AM/PM: the renderer's locale when they equal its `lcid` (so a caller's locale with `0x407` wins over the shipped de-DE), else a shipped locale, else the renderer's locale with `numberFormatUnsupported`. Language 0 selects nothing and warns nothing; the first non-zero language decides. Separators always come from the renderer's locale. In a number section the language is ignored (`[$€-40C]#,##0.00` does not warn and shows `€1.234,50` in de-DE) | the tag names the language of the names: `[$-407]` and `[$-41F]` show German and Turkish names in every region; Excel for Mac, oracle `c18-01`, `c18-03`, `c18-04`. Excel shows `[$-40C]mmmm` in French (`octobre`, `c18-02`); no French names ship, a known difference | `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/number_renderer_test.dart` |
| Calendar and numeral bits | bits 16 to 23 (calendar) other than 0 or 1 warn `numberFormatUnsupported` in a date section; bits 24 to 31 (numeral system) other than 0 or 1 warn in any section | the engine renders only the Gregorian calendar and Western digits | `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/number_renderer_test.dart` |
| System formats | `[$-F800]` and `[$-F400]` (any upper bits) and `[$-x-sysdate]`, `[$-x-systime]` replace the whole section with the first section of the locale's `longDateCode` or `longTimeCode`, keeping the section's color and condition; the first system token wins; a currency on the tag is dropped (`[$USD-F800]`). A language tag as well (`[$-407][$-F800]`) is a second locale tag and makes the code invalid. Tags and brackets inside a long date or time code are neither applied nor reported | design §5.5, "ignoring the rest of the section"; Excel for Mac, oracle `c8-01` to `c8-03`, `c8b-01`; locale codes are trusted data | `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/formatter_test.dart`, `test/xlsx/format/format_code_test.dart` |
| Calendars and numerals | `B1` and `[B1]` are Gregorian and show nothing; `B2`, `[B2]`, `[DBNum1]` to `[DBNum4]`, `[NatNumN]` and any other bracket the parser does not interpret show nothing and warn `numberFormatUnsupported`. The `r` of design §5.4 is not implemented: it stays a literal `r` without a warning | `r` occurs only in zh-TW codes, and telling a bare `r` from `\r` needs a token for every literal | `test/xlsx/format/format_code_test.dart`, `test/xlsx/format/date_renderer_test.dart`, `test/xlsx/format/number_renderer_test.dart` |
| Text sections | a text section never warns `numberFormatUnsupported` (`[DBNum1]@` on text shows the text) | calendars and numerals change digits and dates, not text; unconfirmed | `test/xlsx/format/value_renderer_test.dart` |
| One warning | a result carries one warning: `numberFormatInvalid` first, then the resolution warnings (`unresolvedNumberFormat`, `numberFormatLocaleDependent`), then `numberFormatUnsupported` | ruling of the plan; the first problem is the one worth reporting | `test/xlsx/format/formatter_test.dart` |
| New error codes | `#SPILL!` and `#CALC!` show the locale's name: `#ÜBERLAUF!` and `#CALC!` (untranslated) in de-DE, `#TAŞMA!` and `#HESAPLA!` in tr-TR; an error code not in a locale's table shows as written | Excel for Mac, oracle `c17-01`, `c17-02` (by eye) | `test/xlsx/format/value_renderer_test.dart` |

The three shipped locales, in short. All three have `verified` true: the
owner's run of 2026-10-30 checked them against Excel for Mac 16.114.1
("Excel as the oracle"). Full month and day names come from CLDR;
abbreviations are CLDR's stand-alone abbreviated forms without dots, as
Excel shows them (`c4-01` to `c4-38`). The built-in codes are those whose
text Excel shows on -1234.5, 1234.5 and 46323.5625 (`c6`, `c7`); where
LibreOffice's import table disagreed, Excel's text won. What a CSV cannot
show stays assumed, and each locale's dartdoc names it: the `[Red]` of
ids 6, 8, 38 and 40; the fill and the zero and text sections of 41 to 44
(written in Excel's accounting style); whether de-DE's 18 and 19 show
their `AM`/`PM` by a tag (de-DE's words are the English ones, so the text
is the same); the error names other than `#SPILL!` and `#CALC!`, which no
case shows; and the names of a language no shipped locale serves (French,
`c18-02`). The table lists each `builtinCodes` entry in full, as
`test/xlsx/format/format_locale_test.dart` asserts it.

| | `enUS` | `deDE` | `trTR` |
|---|---|---|---|
| Decimal, group | `.` `,` | `,` `.` | `,` `.` |
| Date separator | `/` | `.` | `.` |
| AM, PM (by a tag) | `AM` `PM` | `AM` `PM` | `ÖÖ` `ÖS` |
| True, false | `TRUE` `FALSE` | `WAHR` `FALSCH` | `DOĞRU` `YANLIŞ` |
| Errors | as written | `#WERT!`, `#BEZUG!`, `#ZAHL!`, `#NV`, `#ÜBERLAUF!`; others as written (`#CALC!` too) | `#BOŞ!`, `#SAYI/0!`, `#DEĞER!`, `#BAŞV!`, `#AD?`, `#SAYI!`, `#YOK`, `#TAŞMA!`, `#HESAPLA!` |
| Month, day abbreviations | `Jan` `Sun` | `Jan Feb Mär` …, `So Mo Di` … | `Oca Şub Mar` …, `Paz Pzt Sal` … |
| Id 14, id 22 | `m/d/yy`, `m/d/yy h:mm` | `dd.mm.yy`, `dd.mm.yy hh:mm` | `dd.mm.yyyy`, `dd.mm.yyyy hh:mm` |
| Id 15 to 17 | `d-mmm-yy`, `d-mmm`, `mmm-yy` | `dd. mmm yy`, `dd. mmm`, `mmm yy` | `dd.mmm.yy`, `dd.mmm`, `mmm.yy` |
| Id 18, 19 | `h:mm AM/PM`, `h:mm:ss AM/PM` | `h:mm AM/PM`, `h:mm:ss AM/PM` | `[$-41F]h:mm AM/PM`, `[$-41F]h:mm:ss AM/PM` |
| Id 20, 21 | `h:mm`, `h:mm:ss` | `hh:mm`, `hh:mm:ss` | `hh:mm`, `hh:mm:ss` |
| Id 5 | `$#,##0_);($#,##0)` | `#,##0 "€";-#,##0 "€"` | `"₺"#,##0;-"₺"#,##0` |
| Id 6 | `$#,##0_);[Red]($#,##0)` | `#,##0 "€";[Red]-#,##0 "€"` | `"₺"#,##0;[Red]-"₺"#,##0` |
| Id 7 | `$#,##0.00_);($#,##0.00)` | `#,##0.00 "€";-#,##0.00 "€"` | `"₺"#,##0.00;-"₺"#,##0.00` |
| Id 8 | `$#,##0.00_);[Red]($#,##0.00)` | `#,##0.00 "€";[Red]-#,##0.00 "€"` | `"₺"#,##0.00;[Red]-"₺"#,##0.00` |
| Id 37 | `#,##0_);(#,##0)` | `#,##0;-#,##0` | `#,##0;-#,##0` |
| Id 38 | `#,##0_);[Red](#,##0)` | `#,##0;[Red]-#,##0` | `#,##0;[Red]-#,##0` |
| Id 39 | `#,##0.00_);(#,##0.00)` | `#,##0.00;-#,##0.00` | `#,##0.00;-#,##0.00` |
| Id 40 | `#,##0.00_);[Red](#,##0.00)` | `#,##0.00;[Red]-#,##0.00` | `#,##0.00;[Red]-#,##0.00` |
| Id 41 | `_(* #,##0_);_(* (#,##0);_(* "-"_);_(@_)` | `_-* #,##0_-;-* #,##0_-;_-* "-"_-;_-@_-` | `_-* #,##0_-;-* #,##0_-;_-* "-"_-;_-@_-` |
| Id 42 | `_($* #,##0_);_($* (#,##0);_($* "-"_);_(@_)` | `_-* #,##0 "€"_-;-* #,##0 "€"_-;_-* "-" "€"_-;_-@_-` | `_-"₺"* #,##0_-;-"₺"* #,##0_-;_-"₺"* "-"_-;_-@_-` |
| Id 43 | `_(* #,##0.00_);_(* (#,##0.00);_(* "-"??_);_(@_)` | `_-* #,##0.00_-;-* #,##0.00_-;_-* "-"??_-;_-@_-` | `_-* #,##0.00_-;-* #,##0.00_-;_-* "-"??_-;_-@_-` |
| Id 44 | `_($* #,##0.00_);_($* (#,##0.00);_($* "-"??_);_(@_)` | `_-* #,##0.00 "€"_-;-* #,##0.00 "€"_-;_-* "-"?? "€"_-;_-@_-` | `_-"₺"* #,##0.00_-;-"₺"* #,##0.00_-;_-"₺"* "-"??_-;_-@_-` |
| Long date (`[$-F800]`) | `dddd, mmmm d, yyyy` | `dddd, d. mmmm yyyy` | `d mmmm yyyy dddd` |
| Long time (`[$-F400]`) | `h:mm:ss AM/PM` | `hh:mm:ss` | `hh:mm:ss` |
| `lcid` | `0x409` | `0x407` | `0x41F` |
| `verified` | true | true | true |

## Settled by Excel

No Microsoft source confirmed these; the owner's Excel for Mac runs in
`en-US`, `de-DE` and `tr-TR` settled them, and a rule changed with a test
where Excel disagreed. The list is §10 of the design. Each item gives
Excel's answer (the same in all three regions unless it says so), its
oracle cases and the unit test that pins it;
`test/xlsx/format/oracle_test.dart` compares every case as well. The test
of a checklist item carries an `Owner Excel check C<n>` comment.

1. Rounding is half away from zero on the decimal digits: `2.675`,
   `1.005`, `0.285` with `0.00` show `2.68`, `1.01`, `0.29`; `-2.5` with `0`
   shows `-3` (`u01-01` to `u01-08`;
   `test/xlsx/format/excel_number_test.dart`,
   `test/xlsx/format/number_renderer_test.dart`).
2. Negative zero shows no minus but keeps its section: `-0.4` with `0`
   shows `0`, `-0.001` with `0.00` `0.00`, `-0.4` with `#,##0;(#,##0)`
   `(0)` (`u02-01` to `u02-03`; `test/xlsx/format/formatter_test.dart`).
3. Conditions: `[<0]"neg "0;"other "0` on -5 shows `neg 5`, and the second
   section never shows the minus (`[>0]0;0` on -5 shows `5`); `[>100]0`
   alone on 50 shows `50`, as Excel repairs it to `[>100]0;General`;
   `[>100]0;[<-100]0` on 50 is `#` (`u03-01` to `u03-06`;
   `test/xlsx/format/section_choice_test.dart`,
   `test/xlsx/format/formatter_test.dart`).
4. Month and day names: CLDR's, abbreviations without dots (`Mär`, `Mo`;
   `Mar`, `Pzt`); `mmmmm` is the first letter (`M`) (C4a, C4b, C4c;
   `c4-01` to `c4-38`, `c4c-01`;
   `test/xlsx/format/date_renderer_test.dart`).
5. AM/PM: an untagged `AM/PM` is `AM`/`PM` and `A/P` is `A`/`P` in every
   region; tr-TR's words need its tag (C5; `c5-01` to `c5-08`;
   `test/xlsx/format/date_renderer_test.dart`).
6. Built-ins 14 to 22: en-US and de-DE show a two-digit year in 14 and 22
   (`10/28/26`, `28.10.26`), tr-TR a four-digit one; tr-TR's 18 and 19 show
   `ÖS` (C6; `c6-01` to `c6-09`; `test/xlsx/format/formatter_test.dart`,
   `test/xlsx/format/format_locale_test.dart`).
7. Currency ids 5 to 8 and 37 to 44: tr-TR puts `₺` before the number
   with the minus first (`-₺1.235`); de-DE and tr-TR 37 to 40 have no
   padding (`-1.235`); 41 to 44 are Excel's accounting codes (C7; `c7-01`
   to `c7-24`; `test/xlsx/format/formatter_test.dart`,
   `test/xlsx/format/format_locale_test.dart`).
8. `[$-F800]` and `[$-F400]` show the region's long date and time
   (`Mittwoch, 28. Oktober 2026`, `28 Ekim 2026 Çarşamba`; `13:30:00` in
   de-DE and tr-TR); `[$-407][$-F800]` is invalid, shown as `General` (C8,
   C8b; `c8-01` to `c8-03`, `c8b-01`;
   `test/xlsx/format/date_renderer_test.dart`,
   `test/xlsx/format/format_code_test.dart`).
9. Time carry and truncation: `h:mm` on 10:29:40 shows `10:29`;
   0.99999999 shows `0:00`, `0:00:00` and `[h]:mm:ss` `24:00:00`; the carry
   reaches the date (`2026-10-29 0:00:00`) (C9, C9b; `c9-01` to `c9-12`,
   `c9b-01`; `test/xlsx/format/date_renderer_test.dart`).
10. Negative times in a 1904 workbook show a minus in any date or time
    section (`-6:00`, `-36:00`, `-1904-01-02`, `-1904 6`), also when they
    round to zero (`-0:00:00`), before a fill or padding (`-6:00`,
    `- 6:00`); `0;h:mm` on -0.5 in the 1900 system is `#` (C10, C10b;
    `c10-01` to `c10-07`, `c10b-01`;
    `test/xlsx/format/date_renderer_test.dart`,
    `test/xlsx/format/value_renderer_test.dart`).
11. Serial 0 is Saturday `1900-01-00`, 60 Wednesday `1900-02-29`; 1904
    serial 0 is Friday `1904-01-01` (C11; `c11-01` to `c11-06`;
    `test/xlsx/format/date_renderer_test.dart`).
12. Lowercase `e+` and `e-` are invalid: Excel repairs `0.00e+00` to
    `General` (`u12-01`, `u12-03`; `test/xlsx/format/format_code_test.dart`,
    `test/xlsx/format/formatter_test.dart`). `000.0E+0` on 12345 shows
    `012.3E+3`, `#.##E+0` on 0 `0.E+0`, `.00E+00` on 0.5 `.50E+00`
    (`u12-02`, `u12-04` to `u12-06`;
    `test/xlsx/format/number_renderer_test.dart`).
13. Fractions: `0.333` with `# ?/?` shows ` 1/3`; `3.14159` with `# ??/??`
    `3  1/7 `; `0` with `# ?/?` `0    `; `?/?` on 2 `2/1`; `# #/#` on 2
    `2`; `# 00/00` on 1.5 `1 01/02`; `# 0/0` on 0 `0/1`; `-1.25` with
    `# ?/?` `-1 1/4`; `?/9999999999` is invalid (`u13-01` to `u13-09`;
    `test/xlsx/format/number_renderer_test.dart`,
    `test/xlsx/format/format_code_test.dart`).
14. `General` at width 10: `123456789012` shows `1.2346E+11`, `1/3`
    `0.33333333`, `-1/3` `-0.3333333`, `0.000012345678` `1.2346E-05`,
    `12345.6789012` `12345.6789`, `0.00001` `0.00001` (`u14-01` to
    `u14-06`, by eye; `test/xlsx/format/general_test.dart`).
15. Token lengths: `y` shows `26`, `yyy` and `yyyyy` `2026`, `e` `2026`,
    `bb` `26` and `bbbb` `2026` (no +543), `mmmmmm` the full name (C15a;
    `c15a-01` to `c15a-07`). `dd/mm/yyyy` shows the region's date separator
    (`28.10.2026` in de-DE and tr-TR) and `hh:mm:ss.00` the decimal comma
    (`10:30:00,50`) (C15b; `c15b-01`, `c15b-02`). `h:mm:ss.0000` is
    invalid (C15c; `c15c-01`); `h:mm.0` shows `12:00.0` (C15d; `c15d-01`);
    `ss.0 ss.00` shows `59.4 59.45` (C15e; `c15e-01`)
    (`test/xlsx/format/date_renderer_test.dart`,
    `test/xlsx/format/format_code_test.dart`).
16. Booleans show the region's word whatever the code: `TRUE`, `WAHR`,
    `DOĞRU` with `0.00`, `General` and a four-section code (C16; `c16-01`
    to `c16-06`; `test/xlsx/format/value_renderer_test.dart`).
17. `#SPILL!` is `#ÜBERLAUF!` in de-DE and `#TAŞMA!` in tr-TR; `#CALC!`
    stays `#CALC!` in de-DE and is `#HESAPLA!` in tr-TR (C17; `c17-01`,
    `c17-02`, by eye; `test/xlsx/format/value_renderer_test.dart`).
18. Five sections, three conditions, or two conditions in one section
    are invalid, shown as `General` (`u18-01` to `u18-03`;
    `test/xlsx/format/format_code_test.dart`).
19. `@` alone on a number shows `General`, and `"Name: "@` on 5 shows `5`;
    `0;@` on -5 shows `-5`, on 5 `5`, on text the text; `0;-0;@` on 0 shows
    `0`; `@;@` is invalid (C19; `u19-01` to `u19-07`, `c19-01`;
    `test/xlsx/format/value_renderer_test.dart`,
    `test/xlsx/format/section_choice_test.dart`,
    `test/xlsx/format/format_code_test.dart`).
20. A file's own `<numFmt>` for a built-in id is used as written: id 14
    with `yyyy-mm-dd` shows `2030-10-29` on a 1904 serial 46323, id 4 with
    `0.000` shows `1234.500` (C20; `c20-01`, `c20-02`;
    `test/xlsx/format/formatter_test.dart`).
21. Locale tags: `[$-407]mmmm dddd` shows `Oktober Mittwoch` and
    `[$-41F]` `Ekim Çarşamba` in every region; `[$€-40C]#,##0.00` keeps the
    region's separators. Excel shows `[$-40C]mmmm` as `octobre`; no French
    names ship, so the engine shows the renderer's names with
    `numberFormatUnsupported`, a known difference (C18; `c18-01` to
    `c18-04`; `test/xlsx/format/date_renderer_test.dart`).

Own rules of N1 and N2, as the oracle found them:

- The `enUS` codes for ids 37 to 40 follow LibreOffice (`#,##0_);(#,##0)`),
  and Excel shows the same (`c7-09` to `c7-16`).
- Commas: `0,.0` scales (`1234.6`; Excel repairs it to `0.0,`), `#,##0,`
  scales and groups (`1,235`), and a quoted `","` prints `,`, not the
  locale's group separator (`own-01` to `own-04`). A comma inside a
  fraction and `?` with grouping stay own rules, unchecked; only the whole
  part groups in a fraction.
- The empty code `''` on a number shows nothing (`-` for a negative one),
  as an empty section does; unchecked.
- `General` at widths other than 10 and 11 is unchecked, and a tiny width
  returns the shortest scientific form where Excel shows `#`.
- A fixed denominator's carry and `# #/8` on 2 (`2 `) are unchecked.
- `[$USD-F800]` drops its currency (`c8-03`).
- Tags and brackets inside a locale's long date or time code are neither
  applied nor reported; unchecked, as the codes are the library's own.
- A date section that overflows keeps its color and warning, and a text
  section never warns `numberFormatUnsupported`; a CSV shows neither.
- `ss.0.0` gives two fractional second tokens (`59.5.5`; `c15-02`,
  `c15-03`).
- Mixed-case `A/p` shows the letter as written (`1:30 p`; `c5-07`,
  `c5-08`).

## Recorded, not changed

The minors N2's review deferred, settled in N3. None changed the library
then; the oracle later changed one row (the 1904 minus, below).

- The long date and long time codes of system formats are parsed into a
  cache of their own, bounded by count: at most 16 codes, cleared when
  full. Its bytes are bounded too: each code is a locale's own
  `longDateCode` or `longTimeCode`, trusted data, never a file's.
- A formatter knows the date system only from its constructor. Built
  without the reader's `date1904`, it reads every serial of a 1904 workbook
  in the 1900 system, and each date shows four years and a day early with
  no warning. The constructor's doc says to pass `XlsxReader.date1904`.
- These rows are pinned by tests
  (`test/xlsx/format/date_renderer_test.dart`,
  `test/xlsx/format/value_renderer_test.dart`,
  `test/xlsx/format/format_code_test.dart`):
  - `DateTime` extremes: year -271820, year 1 and 1899-12-30 overflow in
    `yyyy-mm-dd`; the last millisecond of 9999 shows `.999`.
  - 1904 before the epoch: `-1` and `DateTime(1903, 12, 31)` show
    `-1904-01-02` in `yyyy-mm-dd`, as Excel shows `c10-03` (they
    overflowed before the oracle).
  - Fractional-second carry: `0.99999999999` with `h:mm:ss.00` shows
    `0:00:00.00`; `0.000694444` with `mm:ss.00` shows `01:00.00`.
  - A negative `Duration` of 100,000 days or more overflows in `[h]:mm`.
  - 1904 minus before a fill or padding: `-0.25` with `* h:mm` shows
    `-6:00`, with `_(h:mm` `- 6:00`.
  - `ss.0.0` is two fractional-second tokens (`59.5.5`).
  - Mixed-case `A/p` shows the letter as written (`1:30 p`).
  - No section matching (`[>100]0;[<-100]0` on 50) overflows without a
    color or a warning.
  - A bare `[]` shows the number and warns `numberFormatUnsupported`.
- Each shipped locale's `builtinCodes` is asserted as a whole map
  (`test/xlsx/format/format_locale_test.dart`), so the "Locales" table
  above and the code cannot drift apart unseen.

Excel confirmed the pinned rows it was asked: the fractional-second carry
(`c9-11`, `c9-12`), `ss.0.0` (`c15-02`, `c15-03`), mixed-case `A/p`
(`c5-07`, `c5-08`), no-section overflow (`u03-06`) and the 1904 minus
before fill or padding (`c10-06`, `c10-07`).

## Owner checklist (Excel for Mac)

How: in a new workbook, set macOS region (System Settings → General →
Language & Region) to the locale named, restart Excel, type the value into
A1 (as a plain number, so it is a serial), then Format Cells → Custom →
type the code. Report the text the cell shows (widen the column first). This
list is what N2's tests assumed. The oracle workbooks carry every item as
the cases its Status names ("Excel as the oracle"), run in all three
regions; every item is settled, and "Settled by Excel" gives each answer.

| # | Locale | Code | Value | Look at | N2 assumes | Status |
|---|---|---|---|---|---|---|
| C4a | de-DE | `mmm` / `ddd` | 46083 (Mon 2 Mar 2026) | abbreviation, dot or not | `Mär` / `Mo` | settled (cases `c4-01` to `c4-38`) |
| C4b | tr-TR | `mmm` / `ddd` | 46083 | abbreviation | `Mar` / `Pzt` | settled (cases `c4-01` to `c4-38`) |
| C4c | de-DE, tr-TR | `mmmmm` | 46083 | one letter | `M` | settled (cases `c4c-01`) |
| C5 | de-DE, tr-TR | `h:mm AM/PM` and `h:mm A/P` | 0.5625 | the marker | de `1:30 PM` / `1:30 P`; tr `1:30 ÖS` / `1:30 P` | settled (cases `c5-01` to `c5-08`) |
| C6 | de-DE, tr-TR | built-in ids 14–22 (Format Cells → Date/Time entries) | 46323.5625 | text | the locale tables above | settled (cases `c6-01` to `c6-09`) |
| C7 | de-DE, tr-TR | built-in ids 5–8, 37–44 (Currency/Accounting entries) | -1234.5 | symbol, place | the locale tables above (`€`, `₺`) | settled (cases `c7-01` to `c7-24`) |
| C8 | en-US, de-DE, tr-TR | `[$-F800]dddd, mmmm dd, yyyy` and `[$-F400]h:mm:ss AM/PM` | 46323.5625 | long date, long time | locale's `longDateCode` / `longTimeCode` | settled (cases `c8-01`, `c8-02`) |
| C8b | en-US | `[$-407][$-F800]` | 46323 | long date | the en-US long date code with German names | settled (cases `c8b-01`) |
| C9 | en-US | `h:mm` / `h:mm:ss` | 0.437268518518519 (10:29:40) and 0.99999999 | truncation, carry | `10:29`; `0:00` / `0:00:00` | settled (cases `c9-01` to `c9-09`) |
| C9b | en-US | `yyyy-mm-dd h:mm:ss` | 46323.99999999 | carry into the date | `2026-10-29 0:00:00` | settled (cases `c9b-01`) |
| C10 | en-US, 1904 workbook (Excel → Preferences → Calculation → Use 1904 date system) | `h:mm`, `[h]:mm`, `yyyy-mm-dd` | -0.25, -1.5, -1 | minus or `#` | `-6:00`, `-36:00`, `#` | settled (cases `c10-01` to `c10-07`) |
| C10b | en-US, 1900 | `0;h:mm` | -0.5 | `#` or `12:00` | `#` | settled (cases `c10b-01`) |
| C11 | en-US | `dddd yyyy-mm-dd` | 0, 1, 59, 60, 61 | weekday, day | `Saturday 1900-01-00`, `Sunday 1900-01-01`, `Tuesday 1900-02-28`, `Wednesday 1900-02-29`, `Thursday 1900-03-01` | settled (cases `c11-01` to `c11-05`) |
| C15a | en-US | `y`, `yyy`, `yyyyy`, `e`, `bb`, `bbbb`, `mmmmmm` | 46323 | year digits, month | `26`, `2026`, `2026`, `2026`, `69`, `2569`, `October` | settled (cases `c15a-01` to `c15a-07`) |
| C15b | de-DE | `dd/mm/yyyy` and `hh:mm:ss.00` | 46323.437505787 | `/` kept or `.`; decimal comma | `28/10/2026`; `10:30:00,50` | settled (cases `c15b-01`, `c15b-02`) |
| C15c | en-US | `h:mm:ss.0000` | 0.5 | accepted? | invalid → `General` | settled (cases `c15c-01`) |
| C15d | en-US | `h:mm.0` | 0.5 | fraction after minutes, not seconds | `12:00.0` | settled (cases `c15d-01`) |
| C15e | en-US | `ss.0 ss.00` | 0.000688078703704 (59.45 s) | rounding with several fraction tokens | `59.4 59.45` | settled (cases `c15e-01`) |
| C16 | de-DE | TRUE typed in a cell formatted `0.00` | TRUE | word | `WAHR` | settled (cases `c16-01` to `c16-06`) |
| C17 | de-DE, tr-TR | `=SEQUENCE(2)` blocked by a value below it; a `#CALC!` from `=FILTER(A1:A2;A1:A2>9)` | — | error name | as written: `#SPILL!`, `#CALC!` | settled (cases `c17-01`, `c17-02`) |
| C18 | en-US | `[$-407]mmmm dddd` and `[$-40C]mmmm` | 46323 | German names? French names? | `Oktober Mittwoch`; `October` + warning | settled (cases `c18-01` to `c18-04`; `c18-02` a known difference) |
| C19 | en-US | `@;@` | 5 | empty or `5` (parked from N1) | empty | settled (cases `c19-01`) |
| C20 | de-DE | file with `<numFmt numFmtId="14" formatCode="yyyy-mm-dd"/>` (N3 writes it) | 46323 | file code or locale built-in | `2026-10-28` | settled (cases `c20-01`) |

## Excel as the oracle

Excel for Mac decides what a code shows; the engine follows it.
The owner opens the oracle workbooks in Excel for Mac in each region and
saves what Excel shows as CSV. The case list, the workbooks and the owner's
run belong to the owner's process, described in
[`test/fixtures/owner/number_format/README.md`](../test/fixtures/owner/number_format/README.md):

- `cases.json`: every case, with its id, the checklist items and Unknown it
  settles, its workbook and date system, its value and its code or built-in
  id.
- `tool/write_format_oracle.dart` writes the workbooks from it:
  `format_oracle.xlsx` (1900), `format_oracle_1904.xlsx` (1904) and
  `format_oracle_invalid.xlsx` (codes Excel may refuse; `en-US` at least).
- `manifest.json`: one entry per region run, naming its CSVs and the eye
  texts, with the Excel and macOS versions and the owner's notes.
- `<workbook stem>.<region>.csv`: Excel's CSV, committed as Excel saved it.
  A committed CSV or manifest entry is never edited without the owner.

`test/xlsx/format/oracle_test.dart` (VM only: it reads files) compares
them, region by region (`en-US`, `de-DE`, `tr-TR`):

| Rule | Behaviour |
|---|---|
| No run | a region without a manifest entry is one passing test that prints `number format oracle: <region> unverified`; the gate stays green, and the locale stays `verified: false` |
| Manifest | the entry must name CSVs of real workbooks that exist, run the 1900 and 1904 workbooks (and `invalid` in `en-US`) and give eye text for exactly the eye-only cases of the workbooks it ran |
| Rows | a CSV row is matched to its case by the case id in column C, never by position; the CSV may hold no other case; a case with no row fails |
| Separator | read from the header row, `value`, `code`, `case`, `note`, which holds no code: `,` in `en-US`, `;` where the decimal separator is a comma. A leading BOM and CRLF are accepted |
| Formatting | each case with `XlsxNumberFormatter(locale:, date1904:)` of its region and date system; a built-in id as `numberFormatId`, with the workbook's own code for it as `numberFormat`, as the reader passes them; `General` at width 11 for a CSV case and 10 for an eye-only one (the oracle writer's column width) |
| Texts | exact, never trimmed (the trailing space of `_)` is part of what Excel shows), with two tolerances for what a CSV cannot show as the cell does: when ours overflows, any run of `#` matches; when ours has a fill, any count of the fill character stands for it, unless that character could be part of a number or is in the text next to it |
| Eye only | a case the CSV cannot show (`General` at the default column width, the newer error names) is compared with the manifest's eye text; a manual formula is formatted as its error, in the region's name for it. Without eye text it is skipped as by eye |
| Known differences | `knownDifferences` in the test maps `<case id> <region>` to the reason Excel and the engine differ (the ruling); such a case is skipped with that reason. A key that names no case or region, or a reason left empty, fails, so the map cannot go stale. It holds `c18-02` in each region (`[$-40C]mmmm` is `octobre` in Excel; no French names ship) |

Excel wins. A mismatch changes the rule: the unit test in the owning
`test/xlsx/format/*_test.dart` gets Excel's text first (for a checklist
item, its `Owner Excel check C<n>` test), then the engine is fixed. Only
a difference that cannot be fixed now goes in `knownDifferences`. When
every case of a region matches or is recorded, its locale is set
`verified: true`, with a test.

### The run

The owner ran all three workbooks in Excel for Mac 16.114.1 on macOS 27.2,
on 2026-10-30, in three regions: `en-US`, `de-DE` and `tr-TR`, each with
Excel's own language set to match (`manifest.json` has the details). Every
case matches in every region except `c18-02`, a known difference; the
rulings that followed are in "Settled by Excel" and the rule tables above.
`enUS`, `deDE` and `trTR` are `verified: true`.

Excel repairs some codes when it opens the main workbook (titled
"Repaired" without a dialog, the same in all three regions), so what a
cell shows is the repaired code's text:

- to `General`: `[$-407][$-F800]…` (`c8b-01`), `0.00e+00` and `0.00e-00`
  (`u12-01`, `u12-03`), `?/9999999999` (`u13-07`) and `@;@` (`c19-01`).
  The engine marks each invalid, so it shows `General` too.
- to another code with the same text: `[>100]0` to `[>100]0;General`
  (`u03-03`), `y` to `yy` (`c15a-01`), `yyy` and `yyyyy` to `yyyy`
  (`c15a-02`, `c15a-03`), `mmmmmm` to `mmmm` (`c15a-07`) and `0,.0` to
  `0.0,` (`own-01`). The engine reads the code as written and shows the
  same text.

The 1904 workbook opens without repair. The invalid workbook's cells
(`c15c-01`, `u18-01` to `u18-03`) all show `General`.

### LibreOffice, a second opinion

```bash
dart run tool/write_format_oracle.dart build/format_oracle
LC_ALL=C.UTF-8 soffice --headless \
  --convert-to 'csv:Text - txt - csv (StarCalc):44,34,UTF8,1,,0,false,true,true,false,false,1' \
  --outdir build/format_oracle build/format_oracle/*.xlsx
dart run tool/compare_format_libreoffice.dart build/format_oracle
```

`tool/compare_format_libreoffice.dart` compares the same cases with
LibreOffice's text "as shown" (filter token 9 `true`; its doc comment
explains the options) and prints each difference. `--locale` picks the
region (`en-US` by default). It reports and never fails: it exits 0 with
any number of differences, 2 only on unusable input, and CI runs it with
`continue-on-error`. LibreOffice is not Excel: a difference is a question
for the owner's run, never a reason to change a rule.

## Fuzzing

`test/xlsx/format/fuzz_test.dart` formats seeded cases and requires no
throw, a `text` at most 1,000 characters longer than a text value and
`parts` that join to `text`. A case is a corpus code (every built-in code;
the built-in, long date and long time codes of `enUS`, `deDE` and `trTR`;
the number formats of `allFixtures()`; the codes of the format tests and of
the owner checklist; `dddd` 60 times) with up to three mutations (insert,
delete or duplicate a character of `0#?.,%E+-/@"\_*[];$` or a letter,
repeat a slice, splice two codes), and a value: a random `XlsxDecimal` of up
to 30 digits (now and then up to 309, or a tiny one), a `double` of such
digits, a date serial from 0 to 3,000,000 (now and then negative, or with a
fraction of nines that rounds up), NaN, infinity, a string, a boolean, an
error, a `DateTime` from year 1 to 10,000, a `Duration` of up to 100,000,000
days either way, or `null`, with a random `generalWidth`. Each case picks
one of the three shipped locales and a date system. The gate runs seeds 1
to 4 with 200 cases each, the same cases on the VM and in Chrome: numbers
come from digit strings, `DateTime` and `Duration` from integer fields. For
longer runs:

```bash
dart run tool/fuzz_formatter.dart --seeds 1-200 --cases 1000
```

It prints each failure as
`seed <s> case <i>: <code> <value> width <w> <locale> <system>: <problem>`
and exits 1 on any. A failure is a formatter defect: pin it as a
unit test in the owning `test/xlsx/format/*_test.dart` with the input
minimized by hand, then fix it. The owner manifest lists no file yet, so it
adds no codes.
