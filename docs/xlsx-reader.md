# XLSX reader

`XlsxReader` reads an XLSX file from bytes: the sheet list, then each sheet's
rows of typed cells, lazily and synchronously. It builds no model. Decision
[`0007`](decisions/0007-phase-2-reader-scope-and-untrusted-input.md) sets the
scope and why the file is treated as untrusted input.

This page covers milestones R1, the foundation, and R2, the types: styles and
number formats, dates and durations, `inlineStr`, error values, formula groups
and merges, with `double` and `int` access on `XlsxDecimal`. R3 (files from
other producers, hostile files) and R4 (benchmark and release readiness) add
their own sections as they land.

```dart
final XlsxReader reader = XlsxReader(bytes);
for (final XlsxReadRow row in reader.rows('Prices')) {
  print(row.cells.map((XlsxReadCell c) => c.value));
}
```

A value is a `String`, an `XlsxDecimal`, a `bool`, a `DateTime`, a `Duration`,
an `XlsxErrorValue` or `null`. A number whose number format shows a date is a
UTC `DateTime`, one whose format shows only a time is a `Duration`; a number
that cannot be either stays an `XlsxDecimal`, with a warning. Each cell also
carries its number format (`numberFormatId`, `numberFormat`, `isDate`) and, for
a shared, array or data-table formula, its `formulaGroup`. A sheet's merged
ranges come from `merges(name)` and `mergesAt(index)`. An `XlsxDecimal` keeps
the file's digits; `toDouble()` and `toIntOrNull()` convert on request.

## Rules the reader enforces

A file the reader cannot read at all throws an `XlsxReadException` with a
`reason`. A cell or sheet it cannot read exactly is a warning, and the cell's
value is `null`. Nothing is dropped silently. A programmer error (a limit
below 1, an unknown sheet name or index) throws `ArgumentError` or
`RangeError`.

### The file and the package

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A limit in `XlsxReadLimits` below 1 | `ArgumentError` naming the field, when the reader opens | a zero limit is a bug in the caller | `test/xlsx/read/read_limits_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| Default limits | `maxEntries` 10,000; `maxEntryBytes` 256 MiB; `maxTotalBytes` 1 GiB; `maxCompressionRatio` 1,000; `maxSharedStrings` 2,000,000; `maxDepth` 256; `maxTextLength` 1,048,576 characters; `maxSheets` 10,000; `maxCellFormats` 1,000,000 (R2) | a 100,000 by 12 sheet is about 50 MB of XML, so 256 MiB leaves four times that; Excel itself is far from 10,000 sheets or a million cell formats | `test/xlsx/read/read_limits_test.dart` |
| Bytes that are not a ZIP | `notZip`; a file that starts like a ZIP but has a missing or damaged directory is `corruptZip` | tell a wrong upload from a damaged one | `test/zip/zip_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| More entries than `maxEntries` (directories count) | `limitExceeded` naming `maxEntries`, before anything is inflated | the central directory is read first | `test/zip/zip_reader_test.dart` |
| An entry declaring more than `maxEntryBytes`, or declared sizes adding up to more than `maxTotalBytes` | `limitExceeded` naming the limit, before anything is inflated | ZIP bomb | `test/zip/zip_reader_test.dart` |
| An entry declaring more than 1 MiB at a ratio above `maxCompressionRatio` | `limitExceeded` naming `maxCompressionRatio`. Smaller entries skip the check | a small part may compress very well without being a threat | `test/zip/zip_reader_test.dart` |
| A declared size beyond 2^63 (Zip64, read as negative) | `corruptZip` | a negative size would pass every limit and lower the total | `test/zip/zip_reader_test.dart` |
| An entry inflating past its declared size, or to fewer bytes | `corruptZip`; inflation stops as soon as the declared size is passed | a lying declaration cannot inflate past a size that was checked | `test/zip/zip_reader_test.dart` |
| An entry whose CRC-32 does not match | `corruptZip` | `package:archive` 4.5.2 does not check it | `test/zip/zip_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| An entry using a method other than stored or deflate, or broken deflate data | `corruptZip` | only those two exist in XLSX | `test/zip/zip_reader_test.dart` |
| Two entries with the same name once case and slash direction are ignored | `corruptZip` | two parts with one name make the file ambiguous | `test/zip/zip_reader_test.dart` |
| An entry flagged as encrypted | `encrypted` | the reader has no password | `test/zip/zip_reader_test.dart` |
| An OLE compound file holding the UTF-16LE name `EncryptedPackage` | `encrypted` | a password protected Office file is an OLE container | `test/zip/zip_reader_test.dart` |
| Any other OLE compound file | `legacyXls` | the binary `.xls` format | `test/zip/zip_reader_test.dart` |
| A Strict OOXML workbook (`purl.oclc.org` relationship type, or a workbook or worksheet root in the Strict SpreadsheetML namespace, as when the workbook is found through its content type) | `unsupportedFormat` with a message to save as Excel Workbook; for a worksheet, when its rows are read, naming its part | Strict uses other namespaces; reading it as empty would be silent | `test/xlsx/read/package_reader_test.dart`, `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| A binary `.xlsb` workbook (its content type) | `unsupportedFormat` | not XML | `test/xlsx/read/package_reader_test.dart` |
| No workbook part, or a workbook part whose root is not a SpreadsheetML `<workbook>` | `missingWorkbook` (naming the part in the second case) | nothing to read; a wrong root must not read as zero sheets | `test/xlsx/read/package_reader_test.dart`, `test/xlsx/read/workbook_reader_test.dart` |
| Finding the workbook | through the root relationship, wherever the part lives; the content type override (`.xlsx`, macro-enabled and template workbooks) is the fallback when that is missing or points at nothing | real producers do not always write `xl/workbook.xml` | `test/xlsx/read/package_reader_test.dart` |
| Resolving a relationship target | against the source part, with `.` and `..` applied; a leading `/` is the package root; `\` is read as `/`; a target missing from the ZIP is retried percent-decoded, and an invalid percent-encoding keeps the literal name. External targets are left out | names a real producer writes | `test/xlsx/read/package_reader_test.dart` |
| Looking up a part | by name without regard to case or slash direction, and without a leading `/` | Windows tools write `\` and mixed case | `test/zip/zip_reader_test.dart`, `test/xlsx/read/package_reader_test.dart` |

### XML

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A `<!DOCTYPE` | `malformedXml` naming the part; no entity or external subset is ever read | entity expansion and external entities | `test/xml/xml_pull_reader_test.dart`, `test/xlsx/read/package_reader_test.dart` |
| Nesting deeper than `maxDepth` (empty elements count) | `limitExceeded` naming `maxDepth` and the part | stack and memory | `test/xml/xml_pull_reader_test.dart`, `test/xlsx/read/package_reader_test.dart` |
| UTF-16, a declared encoding other than UTF-8 (any case), or invalid UTF-8 | `malformedXml`. A UTF-8 BOM is skipped, and a declaration without an encoding is UTF-8 | the writer and Excel both write UTF-8 | `test/xml/xml_pull_reader_test.dart` |
| An unknown entity, a malformed numeric reference, `&#0;`, a surrogate or a code point above U+10FFFF | `malformedXml`, also when it surfaces late while reading a value | decoding strictly never invents text | `test/xml/xml_pull_reader_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| A truncated document (open tag, open attribute or open element at the end) | `malformedXml`, never a short read | a cut file must not look complete | `test/xml/xml_pull_reader_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| Input quoted in an exception message (an element name, an entity body, a declared encoding) | at most 32 UTF-16 code units, a surrogate pair never split, then `…`; control characters, line and paragraph separators and bidi controls (U+2028, U+2029, U+061C, U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069) become U+FFFD. The part is in `part`, not repeated in `message`; `part` itself is cut to 256 UTF-16 code units plus `…` and cleaned the same way, so it is for display and may differ from the ZIP entry name | a hostile file must not make a message as large as itself, or spread it over lines of a log | `test/xml/xml_pull_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| Mutated or random documents | only `XmlParseException`, never a `RangeError` or `FormatException` | the typed exception is the contract | `test/xml/xml_pull_reader_test.dart` |
| A literal CR or CRLF in the source | read as LF, in text, CDATA and attribute values | XML 1.0 line-end normalization | `test/xml/xml_pull_reader_test.dart` |
| CR written as `&#13;` | kept as CR, so the writer's escaping round-trips | the writer writes CR as a reference | `test/xml/xml_pull_reader_test.dart`, `test/xml/xml_escape_test.dart` |
| `_xHHHH_` in cell text, formula text or a sheet name | decoded to the character; `_x005F_` gives `_`; an escaped surrogate pair is joined and a lone one is kept | the exact reverse of the writer's `escapeXstring` | `test/xml/xml_escape_test.dart` |
| Elements with a namespace prefix, or the same names in another namespace | elements match by local name and the SpreadsheetML namespace, so prefixed producers read and foreign elements are ignored | producers choose their prefixes | `test/xlsx/read/sheet_reader_test.dart`, `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/shared_strings_reader_test.dart` |

### Workbook and shared strings

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Sheet list | `sheets` in workbook order with name (`_xHHHH_` decoded), index and visibility (`hidden`, `veryHidden`, else visible) | the sheet's identity | `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| More `<sheet>` entries than `maxSheets` | `limitExceeded` naming `maxSheets` and the workbook part, at one more than the limit, before that sheet is kept | each listed sheet costs memory and a warning even without a part, and a few MB of workbook XML can list millions | `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| A workbook with no `<sheet>` | no sheets, not an invented `Sheet1` | nothing silent | `test/xlsx/read/workbook_reader_test.dart` |
| A `<sheet>` whose relationship or part is missing | still listed; its rows are empty and `sheetPartMissing` is recorded on that sheet when the reader opens and again each time its rows are asked for | dropping it would hide a sheet | `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| `<phoneticPr>` and `<rPh>` in a shared string | skipped. A string is its direct `<t>` plus the `<t>` of every `<r>`, in order, each `_xHHHH_` decoded on its own before joining, so an escape split across two runs stays literal | the phonetic text is not what the cell shows; Quds appended it. The writer escapes, and Excel decodes, per run | `test/xlsx/read/shared_strings_reader_test.dart`, `test/xlsx/read/fixture_round_trip_test.dart` |
| An empty `<si/>` | `''` | the index must keep its place | `test/xlsx/read/shared_strings_reader_test.dart` |
| More than `maxSharedStrings` items | `limitExceeded` naming `maxSharedStrings`, at one more than the limit | memory | `test/xlsx/read/shared_strings_reader_test.dart` |
| A shared string longer than `maxTextLength` after decoding | `limitExceeded` naming `maxTextLength` | memory | `test/xlsx/read/shared_strings_reader_test.dart` |
| A workbook with no shared-strings relationship or part | no table; each `t="s"` cell is `sharedStringInvalid` | an exception would lose the other cells | `test/xlsx/read/xlsx_reader_test.dart` |

### Cells

`decodeCell` in `lib/src/xlsx/read/cell_decoder.dart` is the one place that
reads a cell's or a formula's `t` attribute (decision 0007, enforced by
`test/architecture/cell_decoder_test.dart`). The walker passes it the cell's
number format, resolved from the styles table (next section). The first
matching case wins.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `<f>` without `<v>` or `<is>` | value `null`, `formulaWithoutValue`; the formula text is still returned. Inline text counts as the formula's value, so `<f>` with `<is>` and no `<v>` has no warning | the file saved no result; the formula is data; an inline string is a result | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| A formula with a value | both are returned; the formula is as written in the file, only `_xHHHH_` decoded (SpreadsheetML stores no leading `=`, and the reader neither strips nor adds one) | the cached result is what the file shows | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| A shared-formula follower (`<f t="shared" si="0"/>`, no text of its own) | `formula` is `null`, `value` is its cached result, and `formulaGroup` names the shared formula (kind, range, not the master); no warning when the master defined `si` earlier. See "Formula groups" | the text lives on the master's cell | `test/xlsx/read/sheet_reader_test.dart` |
| `t` absent or `n` | an `XlsxDecimal`; text that is not a number is `numberInvalid` | numbers keep the file's digits, never a `double` | `test/xlsx/read/cell_decoder_test.dart` |
| A number without an exponent | the digits as written (`1234.50` and `007` stay); a leading `+` and a trailing `.` are dropped and `.5` becomes `0.5` | exact digits | `test/xlsx/read/cell_decoder_test.dart` |
| A number with an exponent | the point moves; the written significant digits stay (`1.50E1` is `15.0`); the integer part loses leading zeros | `XlsxDecimal` has no exponent | `test/xlsx/read/cell_decoder_test.dart` |
| An exponent beyond 400 in magnitude, such as `1E999999999` | `numberInvalid`, never a long string; the result is at most the mantissa plus 400 characters | a hostile exponent must not allocate | `test/xlsx/read/cell_decoder_test.dart` |
| A zero with a sign | loses the sign (`-0` is `0`, `-0.0` is `0.0`); other negatives keep it | there is no negative zero in a price | `test/xlsx/read/cell_decoder_test.dart` |
| A very long run of digits | matched in linear time | no regular-expression blow-up | `test/xlsx/read/cell_decoder_test.dart` |
| `t="s"` | the shared string at that index; an index that is not a non-negative integer, is out of range, or has no table is `sharedStringInvalid` | nothing silent | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| `t="b"` | `0` is `false`, `1` is `true`, anything else is `booleanInvalid` | | `test/xlsx/read/cell_decoder_test.dart` |
| `t="str"` | the `<v>` text `_xHHHH_` decoded; `''` when absent | a formula's cached text | `test/xlsx/read/cell_decoder_test.dart` |
| `t="e"` | an `XlsxErrorValue` of the `<v>` text, decoded and trimmed: a classic code (`#N/A`, `#DIV/0!` and the other five) is its constant, any other (`#SPILL!`) is kept as written. A missing or empty code is `errorValueInvalid`, value `null` | an error is a value of the sheet, not text | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/read_cell_test.dart` |
| `t="inlineStr"` | the `<is>` text: its direct `<t>` plus the `<t>` of every `<r>`, in order, each `_xHHHH_` decoded on its own, phonetic runs skipped, a whitespace-only `<t>` kept. Without `<is>` the `<v>` text, decoded, with no warning; with neither, `''`. The `<is>` wins over a `<v>`. An `<is>` past `maxTextLength` is `limitExceeded` | the same rule as a shared string; lenient on a cell the schema does not allow | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| `t="d"` | the ISO 8601 text, trimmed, as a UTC `DateTime`. Accepted: `YYYY-MM-DD` with an optional `Thh:mm[:ss[.f+]]`, then an optional `Z` or `±hh:mm`/`±hhmm`, years 0001 to 9999; an offset is subtracted and the result is wall-clock UTC. An offset is accepted only after a time, so `2026-10-28Z` is refused. A result that the rounding of the fraction or the offset moves outside 0001-01-01T00:00:00.000Z to 9999-12-31T23:59:59.999Z (`0001-01-01T00:00+01:00`, `9999-12-31T23:59:59.9995`) is refused too. Anything else, a time alone included, is `dateTextInvalid`, value `null` | ISO text has no serial to map; a time-only `t="d"` has no date to build | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/serial_dates_test.dart` |
| An unknown `t` | `cellTypeUnsupported`, value `null` | nothing is guessed | `test/xlsx/read/cell_decoder_test.dart` |
| A `<v>` or `<f>` longer than `maxTextLength` | `limitExceeded` naming `maxTextLength` and the cell | memory | `test/xlsx/read/sheet_reader_test.dart` |
| An `<is>` when `t` is not `inlineStr` | `cellTypeUnsupported`; its text is not read | the text would be dropped otherwise | `test/xlsx/read/sheet_reader_test.dart` |
| A repeated `<v>`, `<f>` or `<is>` in one `<c>` | the last is kept, `cellDuplicated` | the file contradicts itself | `test/xlsx/read/sheet_reader_test.dart` |
| Several content warnings on one cell | one, in this order: an `<is>` the type does not announce, a repeated child, then the decoder's own: `formulaWithoutValue`, the type's value failure (`numberInvalid`, `sharedStringInvalid`, `booleanInvalid`, `errorValueInvalid`, `dateTextInvalid`, `cellTypeUnsupported`), `styleInvalid`, `unresolvedNumberFormat`, then `phantomLeapDay` or `serialOutOfRange`. A formula group warning is in addition, being about the formula | one warning per cell for its contents; a second problem on the same cell is not counted | `test/xlsx/read/sheet_reader_test.dart`, `test/xlsx/read/cell_decoder_test.dart` |
| A `<c>` with no `<v>`, `<f>` or `<is>` | not data: no cell | styled blanks are not values | `test/xlsx/read/sheet_reader_test.dart` |

### Styles and number formats

Opening reads `xl/styles.xml` (`lib/src/xlsx/read/styles_reader.dart`), so a
bad styles part fails the open. A cell's format is the `numFmtId` of the
`cellXfs` entry its `s` points to. `applyNumberFormat` and `xfId` are ignored.
Only a numeric cell (`t` absent or `n`) is changed by its format.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| No styles relationship or part | every cell is `General`, no warning | a valid variant of the format | `test/xlsx/read/xlsx_reader_test.dart` |
| A malformed styles part, or a Strict root | `malformedXml` or `unsupportedFormat` from the open. A root that is not a SpreadsheetML `<styleSheet>` is an empty table | styles are part of the workbook, and a half-read table would mis-type cells | `test/xlsx/read/xlsx_reader_test.dart`, `test/xlsx/read/styles_reader_test.dart` |
| More than `maxCellFormats` `<numFmt>` entries, or `<xf>` entries of `<cellXfs>` (each counted on its own) | `limitExceeded` naming `maxCellFormats` | every `<xf>` costs a table slot | `test/xlsx/read/styles_reader_test.dart`, `test/xlsx/read/read_limits_test.dart` |
| A `formatCode` longer than `maxTextLength` after decoding | `limitExceeded` naming `maxTextLength` | memory | `test/xlsx/read/styles_reader_test.dart` |
| `<xf>` of `<cellStyleXfs>`, foreign elements, prefixed elements | `<cellStyleXfs>` entries do not count, foreign ones are skipped, prefixed ones read | only `<cellXfs>` indexes cells; producers choose prefixes | `test/xlsx/read/styles_reader_test.dart` |
| A repeated `<numFmts>` or `<cellXfs>` | only the first of each is read; cells pointing past the first table are `styleInvalid` | a second group would reset the `maxCellFormats` budget and shift style indexes | `test/xlsx/read/styles_reader_test.dart` |
| The code of an id | the file's `<numFmt>` for any id, even a built-in; of two with one id the later wins; else the invariant built-in table (ids 0 to 22 and 37 to 49); else none. `cellXfs` before `numFmts` still resolves | the file is what the author saw; Excel does the same | `test/xlsx/read/styles_reader_test.dart` |
| An id of 164 or more that the file does not define, or a locale-dependent built-in id (23 to 36, 50 to 163) | no code. A number cell in it stays an `XlsxDecimal` with `unresolvedNumberFormat`, `detail` the id in decimal; a sheet keeps at most ten ids as their own warnings, and every later id joins one `unresolvedNumberFormat` with `detail` null, whose message names no id. A string, boolean, error or date cell in it has no warning | the code depends on the locale and a guess would be wrong; only a number could have been a date. Quds mapped 164 to `"$"#,##0.00`, a defect fixed with a test first. The cap keeps a styles part of 300,000 distinct undefined ids from making 300,000 warnings | `test/xlsx/read/styles_reader_test.dart`, `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/sheet_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart`, `test/xlsx/warning_collector_test.dart` |
| An `<xf>` without `numFmtId` | id 0, `General` | the schema default | `test/xlsx/read/styles_reader_test.dart` |
| A `<numFmt>` whose id is not a non-negative integer or has no `formatCode`, or one with more than 9 significant digits | ignored. An `<xf>` with an unreadable `numFmtId`, or one over 9 digits, is a broken format | `int.tryParse` differs between the VM and the web past 19 digits; Excel ids are far below 10^9 | `test/xlsx/read/styles_reader_test.dart` |
| An `s` that is not a non-negative integer of at most 9 digits, or is past `cellXfs`, or any `s` but `0` with no styles part | a broken format: the cell reads as `General` and a number cell gets `styleInvalid`. A string, boolean or error cell is unchanged and has no warning, because its data is intact | an unused broken style affects no data, so it is reported on the cells that use it and only when it could have changed the value | `test/xlsx/read/styles_reader_test.dart`, `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| `XlsxReadCell.numberFormatId`, `numberFormat`, `isDate` | the id, the code (`null` when none) and whether the format shows a date or a time. Which of the two is told by the value: `DateTime` or `Duration`. `isDate` describes the format, not the value: a string cell in a date format has it true, and a `t="d"` cell in `General` has it false with a `DateTime` value | one flag, as phase 1's `isDateFormat` | `test/xlsx/read/sheet_reader_test.dart`, `test/xlsx/read/read_cell_test.dart` |
| A code is a date, a time or a number | per section (`classifyFormatCode`, `lib/src/xlsx/read/format_kind.dart`): sections are split at `;` outside quotes, `\`, `_`, `*` and brackets, and only the first three count. A section holding `@` is neutral, and so is one with no date or time token that is `General` or has no digit placeholder (`0`, `#`, `?` outside literals): an empty one, `[Red]` alone and a literal-only one like `"-"`; the code is a date or a time when at least one section is not neutral and all that are agree, and a number otherwise (`dd/mm/yyyy;@`, `yyyy-mm-dd;"-"` and `dd.mm.yyyy;;"-"` are dates, `yyyy-mm-dd;h:mm` and `0;"-"` numbers, and a code of neutral sections only, such as `"abc"`, a number). `m` is minutes after `h` or before `s`, a month otherwise, and `[m]`, `[h]`, `[s]` are elapsed time. An unterminated quote or bracket ends the code there | the first three sections are the ones that format a positive, negative and zero number; a code mixing a date and a time section is not one kind | `test/xlsx/read/format_kind_test.dart` |

### Dates and durations

A date or time format on a numeric cell maps its serial exactly, from the
digits of the `XlsxDecimal` and never through a `double`
(`lib/src/xlsx/read/serial_dates.dart`). The `DateTime` is `DateTime.utc` built
from wall-clock fields, whatever the machine's time zone.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A serial in a date format | a UTC `DateTime`, rounded to the nearest millisecond with the fraction read from its first 30 digits; a rounding that reaches 24:00 rolls into the next day (`45000.99999999999` is 2023-03-16 00:00); an exact half millisecond rounds up | a `double` loses the millisecond; rounding is exact to within 1e-22 ms | `test/xlsx/read/serial_dates_test.dart` ("rounding reaches 24:00 and rolls into the next day", "an exact half millisecond rounds up"), `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` (dates, times and durations written by `XlsxWriter`) |
| A serial in a time format | a `Duration` of that many days, to the nearest millisecond | a time alone is not a date | `test/xlsx/read/serial_dates_test.dart`, `test/xlsx/read/cell_decoder_test.dart` |
| A duration of 100,000 days or more in magnitude | `serialOutOfRange`, the number stays an `XlsxDecimal` | Dart's web `Duration` is exact only below 2^53 microseconds, about 104,000 days | `test/xlsx/read/serial_dates_test.dart`, `test/xlsx/read/cell_decoder_test.dart` |
| A negative serial in a date format | `serialOutOfRange`, the number stays an `XlsxDecimal`; judged by the sign of the digits, before rounding | no date lies before the epoch | `test/xlsx/read/serial_dates_test.dart`, `test/xlsx/read/cell_decoder_test.dart` |
| A serial past 9999-12-31 (2,958,465 in the 1900 system, 2,957,003 in 1904), or with more than 9 integer digits | `serialOutOfRange`; the integer part is checked before any arithmetic, leading zeros skipped, so a hostile file cannot make it large | `DateTime` and the web's integers stop there | `test/xlsx/read/serial_dates_test.dart` |
| Serial 60 in the 1900 system | `phantomLeapDay`, the number stays an `XlsxDecimal`; also when a fraction rounds into it | 29 February 1900 never existed | `test/xlsx/read/serial_dates_test.dart`, `test/xlsx/read/cell_decoder_test.dart` |
| The 1904 date system | the workbook's `date1904` moves every date; `XlsxReader.date1904` tells which | the epoch differs | `test/xlsx/read/serial_dates_test.dart`, `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| A date serial with a very long fraction | finishes in bounded time; digits past the 30th are not read | a hostile file | `test/xlsx/read/serial_dates_test.dart` |
| A serial with leading zeros in its integer part | read as the number it is (zeros skipped before the digit-count check) | `normalizeNumber` keeps `007` | `test/xlsx/read/serial_dates_test.dart` |
| A `General` number, or any non-date number | an `XlsxDecimal` with the file's digits | the reader does not guess dates | `test/xlsx/read/cell_decoder_test.dart` |
| A string, boolean or error cell in a date format | unchanged | the format applies to numbers only | `test/xlsx/read/sheet_reader_test.dart` |
| `XlsxDecimal.toDouble()` and `toIntOrNull()` | `toDouble()` parses the digits; `toIntOrNull()` is `null` for a fraction, for a value past 2^53 - 1 and for digits too long to parse, and never throws | a caller who wants a number asks for it, and it is the same on the web | `test/xlsx/values_test.dart` |

### Formula groups

`lib/src/xlsx/read/formula_groups.dart` follows the shared, array and
data-table formulas through one pass over a sheet. Every cell of a group has an
equal `XlsxFormulaGroup` `kind` and `range`; only `isMaster` differs. An invalid
`<f>` defines nothing and the cell's value is always kept.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `<f t="shared">` with `ref` | the master: its `formula` is the text, its `formulaGroup` is `shared` with `isMaster`; every later `<f t="shared">` with the same `si` and no `ref` is a follower with `formula` `null` | the text is written once, on the master | `test/xlsx/read/formula_groups_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| An array or data-table master | covers its `ref`; a cell in the range without its own `<f>` is a follower of the group, `formulaGroup` set, `formula` `null`. An array master without `ref` covers itself | continuation cells carry values only | `test/xlsx/read/formula_groups_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| A data table without `ref`; a shared master whose `ref` is missing, not a cell range, or does not contain the master; an `si` that is not a non-negative integer | `formulaGroupInvalid`, no group | the file contradicts itself | `test/xlsx/read/formula_groups_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| A shared follower whose `si` no master defined earlier in the sheet, or whose cell is outside that master's `ref` | `formulaGroupInvalid`, no group, the value and the follower's own text kept | a follower before its master is read by no producer; one outside the range is not part of the group | `test/xlsx/read/formula_groups_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| A second shared master with the `si` of an earlier one | it replaces the first for the followers after it, without a warning | `si` is unique per sheet in a valid file | `test/xlsx/read/formula_groups_test.dart` |
| An array or data-table range that overlaps an active one | `formulaGroupInvalid`, no group; with rows out of order, a new range whose columns meet an active one is refused even when the rows do not meet | the active ranges are kept disjoint by column | `test/xlsx/read/formula_groups_test.dart` |
| A range the walk has passed | no longer conflicts | it covers no later cell | `test/xlsx/read/formula_groups_test.dart` |
| A cell with its own `<f>` inside an array or data-table range | `formulaGroupInvalid`, no group; a shared master there is not registered, so its followers warn too | the cell contradicts the range | `test/xlsx/read/sheet_reader_test.dart` |
| An unknown `<f t>` | a normal formula | nothing is guessed | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| Many active ranges | the covered-cell lookup is a binary search over a tree ordered by first column, so a file with many overlapping ranges cannot make the walk quadratic | hostile files | `test/xlsx/read/formula_groups_test.dart` |
| Groups across passes and sheets | each pass over a sheet starts with no groups; sheets do not share them, and the warning names its own sheet | `si` is per sheet | `test/xlsx/read/sheet_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| `formulaGroupInvalid` and a content warning on one cell | both are recorded | the first is about the formula, the second about the value | `test/xlsx/read/sheet_reader_test.dart` |

### Merges

`merges(name)` and `mergesAt(index)` are methods of `XlsxReader`, not a field
of `XlsxReadSheet`: they inflate and scan the sheet part in a pass of their own
(`lib/src/xlsx/read/merge_reader.dart`), which a value class should not hide in
a getter.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Reading merges | the `XlsxRange` of each `<mergeCell>` under `<mergeCells>`, in file order, wherever `<mergeCells>` stands relative to `<sheetData>`; the list is unmodifiable and cached per sheet | the first call costs a pass, later calls none | `test/xlsx/read/merge_reader_test.dart` |
| A prefixed or foreign element | prefixed ones read, foreign ones are ignored | producers choose their prefixes | `test/xlsx/read/merge_reader_test.dart` |
| A `ref` that is missing or not a cell range | skipped, one `mergeRangeInvalid` per sheet naming no cell | do not trust the reference | `test/xlsx/read/merge_reader_test.dart` |
| A sheet whose part is missing, a part that is not a `<worksheet>`, or an empty one | no merges, no warning of its own (a missing part is `sheetPartMissing`) | nothing to read | `test/xlsx/read/merge_reader_test.dart` |
| A Strict worksheet, or malformed XML | `unsupportedFormat` or `malformedXml`, naming the part. Nothing is cached, so a later call tries again | a transient failure is not frozen | `test/xlsx/read/merge_reader_test.dart` |
| A part that warns and then throws | no warning is added: the pass's warnings are added only after it succeeds, so a retry never counts them twice | a failed pass reports nothing but its exception | `test/xlsx/read/merge_reader_test.dart` |
| Reading `rows` after `merges` | the sheet's warnings are replaced except `mergeRangeInvalid`, which the merge pass owns | a rows pass does not see merges | `test/xlsx/read/merge_reader_test.dart` |
| An unknown sheet name, or an index out of range | `ArgumentError`, `RangeError` | programmer errors | `test/xlsx/read/merge_reader_test.dart` |
| Merges written by `XlsxWriter` | read back equal | the reader mirrors the writer | `test/xlsx/read/merge_reader_test.dart` |
| A `<mergeCell>` with child elements, or a second `<mergeCells>` | the `<mergeCell>`'s `ref` is read and its children skipped; every `<mergeCells>` child of the root is read, in file order | a producer may add extensions, and a damaged file may split the list | `test/xlsx/read/merge_reader_test.dart` |

### Rows and positions

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Which rows are yielded | a `<row>` with at least one cell with data, or a hidden one (`hidden` is `1` or `true`); its `cells` are in column order | sparse rows | `test/xlsx/read/sheet_reader_test.dart` |
| A row or cell without `r` | placed after the previous row or cell, no warning | the file allows it | `test/xlsx/read/sheet_reader_test.dart` |
| A cell `r` that does not parse or names another row | placed after the previous cell, keeps its value, `cellReferenceInvalid` | do not trust the reference | `test/xlsx/read/sheet_reader_test.dart` |
| A row `r` that is not a number | the row follows the previous one; `cellReferenceInvalid` on its first cell | same | `test/xlsx/read/sheet_reader_test.dart` |
| A row `r` with leading zeros | that row | it is a number | `test/xlsx/read/sheet_reader_test.dart` |
| A huge row `r` | never parsed to an `int`: more than 7 significant digits is past the last row (a cell `r` with more than 7 row digits is `cellReferenceInvalid`) | no overflow, no allocation | `test/xlsx/read/sheet_reader_test.dart` |
| A cell past column XFD, or in a row past 1,048,575 | skipped, `cellOutsideSheet` naming the `r` when it is 1 to 4 letters and 1 to 10 digits with optional `$` (upper-cased, `$` removed); otherwise the warning names no cell | reported, not silent | `test/xlsx/read/sheet_reader_test.dart` |
| A row whose index is not greater than the previous row's | still yielded, in file order; `rowOutOfOrder` naming its first cell with data (`A<row>` for a hidden row without data) | file order is the file's | `test/xlsx/read/sheet_reader_test.dart` |
| A second cell at the same column | replaces the first, `cellDuplicated` | the last wins | `test/xlsx/read/sheet_reader_test.dart` |
| Cells out of column order | appended, then the row is sorted once when it ends; a duplicate is still found as it arrives | a full row written right to left must not cost O(n²) | `test/xlsx/read/sheet_reader_test.dart` |
| A part that is not a `<worksheet>` in the SpreadsheetML namespace (a chartsheet, dialogsheet or macrosheet), or has no `<sheetData>` | no rows, no warning; a root in the Strict namespace is `unsupportedFormat` instead | nothing to read | `test/xlsx/read/sheet_reader_test.dart` |

### Warnings and laziness

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Warning shape | an `XlsxWarning` per sheet, code and `detail`: `count` of all affected cells, `cells` naming the first ten. `detail` is a `String?` parameter; only `unresolvedNumberFormat` uses it, for the format id, so two ids are two warnings. A sheet and code keep at most ten distinct details; an occurrence with an eleventh or later new detail joins the one warning of that code with `detail` null, so memory stays bounded. Every code has a message in `en`, `de` and `tr` | the phase 1 machinery, plus the parameter the message needs | `test/xlsx/warning_messages_test.dart`, `test/architecture/warning_messages_test.dart`, `test/xlsx/warning_collector_test.dart` |
| Warning keys | the reader keys warnings by sheet index, not name (`WarningCollector.add(..., key:)`), so two sheets with one name in a damaged file keep separate warnings; `rows(name)` and `merges(name)` take the first | a name is not an identity in a hostile file | `test/xlsx/warning_collector_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| Reading a sheet again | the sheet's warnings are replaced, never doubled, except `mergeRangeInvalid` (`removeSheet(key, keep:)`) | a second pass finds the same problems; the merge pass owns its own | `test/xlsx/read/xlsx_reader_test.dart`, `test/xlsx/warning_collector_test.dart`, `test/xlsx/read/merge_reader_test.dart` |
| A stale pass | each `rowsAt` iteration has a generation; once a newer pass of the sheet starts, the older iterator still yields rows but adds no warnings | the newer pass reports the same problems, and an old one must not add to them | `test/xlsx/read/xlsx_reader_test.dart` |
| Stopping a sheet early | the warnings found so far stay; another sheet reads normally | rows are parsed as they are taken | `test/xlsx/read/xlsx_reader_test.dart` |
| `warnings` | an unmodifiable live view that grows as rows are read | callers read it after iterating | `test/xlsx/read/xlsx_reader_test.dart` |
| Opening | reads the ZIP directory, `[Content_Types].xml`, the root and workbook relationships, the workbook part and the styles part only | a sheet may be large and never needed; styles decide every cell's type | `test/xlsx/read/xlsx_reader_test.dart` |
| A sheet's rows, and merges | its part is inflated when iteration starts (and again, once, for merges); shared strings are read once per reader, on first use, and a failure is retried by the next read | laziness | `test/xlsx/read/xlsx_reader_test.dart` |
| Every phase 1 fixture | read back equals what the writer stored: same sheets, text decoded, numbers digit for digit when written without an exponent, booleans as `1` and `0`; the only warning is `formulaWithoutValue`, one per formula cell without a result; dates, merges and formula groups match what the writer stored, and a number in a date or time format never reads back as an `XlsxDecimal`. The fixtures store a rich text's runs joined, so a separate round trip writes rich text with escapes split across runs and reads it back exactly | the reader mirrors the writer | `test/xlsx/read/fixture_round_trip_test.dart` |

## Inflation

R1 inflates with `package:archive`'s pure-Dart `Inflate`, written into a
stream that holds at most the entry's declared size. The archive's own
decoders may inflate a whole entry into a buffer first, which would defeat the
bound, and `decodeLimited` does not exist in the `archive` version the package
still supports (`^4.0.9`). The buffer starts at four times the compressed size
(at least 64 KiB) and doubles up to the declared size, so an entry that
declares much more than it holds does not reserve it all. A platform inflate
(`dart:io` or the browser's `DecompressionStream`) is a speed question for
R4's benchmark, not a correctness one.

## Port map

Each file names its Quds source path and commit in its library doc comment
(AGENTS.md). Quds paths are relative to
`../quds_office_suite/packages/quds_office_engine/lib/src/`, at commit
`15c5d29`. Files not listed here are new in jet_office.

| jet_office file (`lib/src/`) | Ported from Quds | What changed |
|---|---|---|
| `xml/xml_pull_reader.dart` | `xml/xml_reader.dart` → `XmlPullReader`, `XmlEventType`, `XmlParseException`, `decodeXmlEntities` | a `DOCTYPE` throws (Quds emitted a `dtd` event); depth is limited; `fromBytes` refuses UTF-16 and other encodings and reports invalid UTF-8 (Quds took a `String`); entity decoding is strict, so a bad numeric reference, `&#0;`, a surrogate or a code point above U+10FFFF is an `XmlParseException` (Quds let `FormatException` and `RangeError` escape); truncated documents throw; a literal CR is normalized but `&#13;` is kept |
| `xlsx/read/package_reader.dart` | `opc/content_types.dart` → `ContentTypes.parse`, `contentTypeFor`; `opc/relationships.dart` → `RelationshipCollection.parse`, `resolve` (read side) | opens the ZIP with limits; every ZIP and XML failure is an `XlsxReadException`; the workbook is found through the root relationship (Quds read `/xl/workbook.xml`); Strict and `.xlsb` are refused; targets are retried percent-decoded and backslashes are read as `/`; part names match without regard to case or slash direction |
| `xlsx/read/workbook_reader.dart` | `builders/xlsx_io.dart` → `XlsxGridReader._sheetList` | the workbook part is not hard-coded; its root must be a SpreadsheetML `<workbook>`; no invented `Sheet1`; a sheet with a missing part is kept, not dropped; names are `_xHHHH_` decoded; `state` and `date1904` are read; the number of sheets is limited; foreign elements are skipped |
| `xlsx/read/shared_strings_reader.dart` | `builders/xlsx_io.dart` → `XlsxGridReader._sharedStrings`, `_readSi` | phonetic runs are skipped (Quds appended `<rPh>` text to the string); each `<t>` is `_xHHHH_` decoded on its own; only root `<si>` elements count; table size and string length are limited |
| `xlsx/read/sheet_reader.dart` | `builders/xlsx_io.dart` → `XlsxGridReader._sheetRows`, `_readText` | rows are yielded lazily as typed cells, not a dense grid of strings; positions are checked and problems warned (Quds trusted every `r`); text is limited; a Strict root is refused |
| `xlsx/read/styles_reader.dart` | `sheet/styles/sml_styles.dart` → `SmlStyleSheet.parse`, the `numFmts` and `cellXfs` read side | only number formats and cell formats are read (no fonts, fills, alignment or theme colors); a bad `numFmtId` is ignored or makes a broken format instead of an `int.parse` throw; Quds' hard-coded built-in `164` is dropped; each format has a kind and one shared `CellFormat` per id; elements are matched by depth, local name and namespace under `<numFmts>` and `<cellXfs>` (Quds also counted `<xf>` of other parents); only the first of each group is read; the root must be a `<styleSheet>`; counts and code length are limited |
| `xlsx/read/merge_reader.dart` | `sheet/serial/sheet_serial.dart` → `mergeCell` branch of `readSheet`; `sheet/model/sml_workbook.dart` → `SmlMerge.parse` | no model, a merge is an `XlsxRange`; a missing or unparseable `ref` is skipped with `mergeRangeInvalid` instead of a throw; `<mergeCell>` is matched by depth, local name and namespace; `<sheetData>` is skipped unread; a Strict root is refused |
| `xlsx/read/cell_decoder.dart`, `xlsx/read/xlsx_reader.dart`, `xlsx/read/read_limits.dart`, `xlsx/read/read_exception.dart` | — (new) | Quds decoded cells inline in `XlsxGridReader` and had no limits or typed exceptions |
| `xlsx/read/read_cell.dart` (`XlsxReadCell`, `XlsxReadRow`, `XlsxErrorValue`, `XlsxFormulaGroup`) | — (new) | the values the reader hands out; Quds returned a dense grid of strings |
| `xlsx/read/format_kind.dart`, `xlsx/read/serial_dates.dart`, `xlsx/read/formula_groups.dart` | — (new) | Quds mapped no serials, classified no formats and kept only the text of each `<f>` |
| `zip/archive_adapter.dart` (`ZipReader`) | — (new) | bounded inflation, limits from the central directory, CRC and duplicate-name checks |
| `xml/xml_escape.dart` (`decodeXstring`) | — (new) | the reverse of `escapeXstring` |
