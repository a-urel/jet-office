# XLSX reader

`XlsxReader` reads an XLSX file from bytes: the sheet list, then each sheet's
rows of typed cells, lazily and synchronously. It builds no model. Decision
[`0007`](decisions/0007-phase-2-reader-scope-and-untrusted-input.md) sets the
scope and why the file is treated as untrusted input.

This page covers milestone R1, the foundation. R2 (styles, number formats,
dates and durations, `inlineStr`, error values, formula groups, merges,
`double` and `int` access), R3 (files from other producers, hostile files) and
R4 (benchmark and release readiness) add their own sections as they land.

```dart
final XlsxReader reader = XlsxReader(bytes);
for (final XlsxReadRow row in reader.rows('Prices')) {
  print(row.cells.map((XlsxReadCell c) => c.value));
}
```

A value is a `String`, an `XlsxDecimal`, a `bool` or `null`. Until R2 a date
cell reads as its serial number, an `XlsxDecimal`.

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
| Default limits | `maxEntries` 10,000; `maxEntryBytes` 256 MiB; `maxTotalBytes` 1 GiB; `maxCompressionRatio` 1,000; `maxSharedStrings` 2,000,000; `maxDepth` 256; `maxTextLength` 1,048,576 characters | a 100,000 by 12 sheet is about 50 MB of XML, so 256 MiB leaves four times that | `test/xlsx/read/read_limits_test.dart` |
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
| A Strict OOXML workbook (`purl.oclc.org` relationship type) | `unsupportedFormat` with a message to save as Excel Workbook | Strict uses other namespaces | `test/xlsx/read/package_reader_test.dart` |
| A binary `.xlsb` workbook (its content type) | `unsupportedFormat` | not XML | `test/xlsx/read/package_reader_test.dart` |
| No workbook part | `missingWorkbook` | nothing to read | `test/xlsx/read/package_reader_test.dart` |
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
| Mutated or random documents | only `XmlParseException`, never a `RangeError` or `FormatException` | the typed exception is the contract | `test/xml/xml_pull_reader_test.dart` |
| A literal CR or CRLF in the source | read as LF, in text, CDATA and attribute values | XML 1.0 line-end normalization | `test/xml/xml_pull_reader_test.dart` |
| CR written as `&#13;` | kept as CR, so the writer's escaping round-trips | the writer writes CR as a reference | `test/xml/xml_pull_reader_test.dart`, `test/xml/xml_escape_test.dart` |
| `_xHHHH_` in cell text, formula text or a sheet name | decoded to the character; `_x005F_` gives `_`; an escaped surrogate pair is joined and a lone one is kept | the exact reverse of the writer's `escapeXstring` | `test/xml/xml_escape_test.dart` |
| Elements with a namespace prefix, or the same names in another namespace | elements match by local name and the SpreadsheetML namespace, so prefixed producers read and foreign elements are ignored | producers choose their prefixes | `test/xlsx/read/sheet_reader_test.dart`, `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/shared_strings_reader_test.dart` |

### Workbook and shared strings

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Sheet list | `sheets` in workbook order with name (`_xHHHH_` decoded), index and visibility (`hidden`, `veryHidden`, else visible) | the sheet's identity | `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| A workbook with no `<sheet>` | no sheets, not an invented `Sheet1` | nothing silent | `test/xlsx/read/workbook_reader_test.dart` |
| A `<sheet>` whose relationship or part is missing | still listed; its rows are empty and `sheetPartMissing` is recorded on that sheet when the reader opens and again each time its rows are asked for | dropping it would hide a sheet | `test/xlsx/read/workbook_reader_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| `<phoneticPr>` and `<rPh>` in a shared string | skipped. A string is its direct `<t>` plus the `<t>` of every `<r>`, in order, each `_xHHHH_` decoded on its own before joining, so an escape split across two runs stays literal | the phonetic text is not what the cell shows; Quds appended it. The writer escapes, and Excel decodes, per run | `test/xlsx/read/shared_strings_reader_test.dart`, `test/xlsx/read/fixture_round_trip_test.dart` |
| An empty `<si/>` | `''` | the index must keep its place | `test/xlsx/read/shared_strings_reader_test.dart` |
| More than `maxSharedStrings` items | `limitExceeded` naming `maxSharedStrings`, at one more than the limit | memory | `test/xlsx/read/shared_strings_reader_test.dart` |
| A shared string longer than `maxTextLength` after decoding | `limitExceeded` naming `maxTextLength` | memory | `test/xlsx/read/shared_strings_reader_test.dart` |
| A workbook with no shared-strings relationship or part | no table; each `t="s"` cell is `sharedStringInvalid` | an exception would lose the other cells | `test/xlsx/read/xlsx_reader_test.dart` |

### Cells

`decodeCell` in `lib/src/xlsx/read/cell_decoder.dart` is the one place that
reads a cell's `t` attribute (decision 0007, enforced by
`test/architecture/cell_decoder_test.dart`). The first matching case wins.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `<f>` without `<v>` | value `null`, `formulaWithoutValue`; the formula text is still returned | the file saved no result; the formula is data | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| A formula with a value | both are returned; the formula is as written in the file, only `_xHHHH_` decoded (SpreadsheetML stores no leading `=`, and the reader neither strips nor adds one) | the cached result is what the file shows | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart`, `test/xlsx/read/sheet_reader_test.dart` |
| `t` absent or `n` | an `XlsxDecimal`; text that is not a number is `numberInvalid` | numbers keep the file's digits, never a `double` | `test/xlsx/read/cell_decoder_test.dart` |
| A number without an exponent | the digits as written (`1234.50` and `007` stay); a leading `+` and a trailing `.` are dropped and `.5` becomes `0.5` | exact digits | `test/xlsx/read/cell_decoder_test.dart` |
| A number with an exponent | the point moves; the written significant digits stay (`1.50E1` is `15.0`); the integer part loses leading zeros | `XlsxDecimal` has no exponent | `test/xlsx/read/cell_decoder_test.dart` |
| An exponent beyond 400 in magnitude, such as `1E999999999` | `numberInvalid`, never a long string; the result is at most the mantissa plus 400 characters | a hostile exponent must not allocate | `test/xlsx/read/cell_decoder_test.dart` |
| A zero with a sign | loses the sign (`-0` is `0`, `-0.0` is `0.0`); other negatives keep it | there is no negative zero in a price | `test/xlsx/read/cell_decoder_test.dart` |
| A very long run of digits | matched in linear time | no regular-expression blow-up | `test/xlsx/read/cell_decoder_test.dart` |
| `t="s"` | the shared string at that index; an index that is not a non-negative integer, is out of range, or has no table is `sharedStringInvalid` | nothing silent | `test/xlsx/read/cell_decoder_test.dart`, `test/xlsx/read/xlsx_reader_test.dart` |
| `t="b"` | `0` is `false`, `1` is `true`, anything else is `booleanInvalid` | | `test/xlsx/read/cell_decoder_test.dart` |
| `t="str"` | the `<v>` text `_xHHHH_` decoded; `''` when absent | a formula's cached text | `test/xlsx/read/cell_decoder_test.dart` |
| `t="inlineStr"`, `e`, `d` or an unknown `t` | `cellTypeUnsupported`, value `null` | R2 reads these | `test/xlsx/read/cell_decoder_test.dart` |
| A `<v>` or `<f>` longer than `maxTextLength` | `limitExceeded` naming `maxTextLength` and the cell | memory | `test/xlsx/read/sheet_reader_test.dart` |
| An `<is>` when `t` is not `inlineStr` | `cellTypeUnsupported`; its text is not read | the text would be dropped otherwise | `test/xlsx/read/sheet_reader_test.dart` |
| A repeated `<v>`, `<f>` or `<is>` in one `<c>` | the last is kept, `cellDuplicated` | the file contradicts itself | `test/xlsx/read/sheet_reader_test.dart` |
| Several content warnings on one cell | one: the `<is>` case, then a repeated child, then the decoder's | one warning per cell for its contents | `test/xlsx/read/sheet_reader_test.dart` |
| A `<c>` with no `<v>`, `<f>` or `<is>` | not data: no cell | styled blanks are not values | `test/xlsx/read/sheet_reader_test.dart` |

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
| A row whose index is not greater than the previous row's | still yielded, in file order; `rowOutOfOrder` naming its first cell | file order is the file's | `test/xlsx/read/sheet_reader_test.dart` |
| A second cell at the same column | replaces the first, `cellDuplicated` | the last wins | `test/xlsx/read/sheet_reader_test.dart` |
| A part that is not a `<worksheet>` in the SpreadsheetML namespace, or has no `<sheetData>` | no rows | nothing to read | `test/xlsx/read/sheet_reader_test.dart` |

### Warnings and laziness

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Warning shape | an `XlsxWarning` per sheet and code: `count` of all affected cells, `cells` naming the first ten. Every code has a message in `en`, `de` and `tr` | the phase 1 machinery | `test/xlsx/warning_messages_test.dart`, `test/architecture/warning_messages_test.dart` |
| Reading a sheet again | the sheet's warnings are replaced, never doubled | a second pass finds the same problems | `test/xlsx/read/xlsx_reader_test.dart` |
| Stopping a sheet early | the warnings found so far stay; another sheet reads normally | rows are parsed as they are taken | `test/xlsx/read/xlsx_reader_test.dart` |
| `warnings` | an unmodifiable live view that grows as rows are read | callers read it after iterating | `test/xlsx/read/xlsx_reader_test.dart` |
| Opening | reads the ZIP directory, `[Content_Types].xml`, the root and workbook relationships and the workbook part only | a sheet may be large and never needed | `test/xlsx/read/xlsx_reader_test.dart` |
| A sheet's rows | its part is inflated when iteration starts; shared strings are read once per reader, on first use, and a failure is retried by the next read | laziness | `test/xlsx/read/xlsx_reader_test.dart` |
| Every phase 1 fixture | read back equals what the writer stored: same sheets, text decoded, numbers digit for digit when written without an exponent, booleans as `1` and `0`; the only warning is `formulaWithoutValue`, one per formula cell without a result. The fixtures store a rich text's runs joined, so a separate round trip writes rich text with escapes split across runs and reads it back exactly | the reader mirrors the writer | `test/xlsx/read/fixture_round_trip_test.dart` |

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
| `xlsx/read/workbook_reader.dart` | `builders/xlsx_io.dart` → `XlsxGridReader._sheetList` | the workbook part is not hard-coded; no invented `Sheet1`; a sheet with a missing part is kept, not dropped; names are `_xHHHH_` decoded; `state` and `date1904` are read |
| `xlsx/read/shared_strings_reader.dart` | `builders/xlsx_io.dart` → `XlsxGridReader._sharedStrings`, `_readSi` | phonetic runs are skipped (Quds appended `<rPh>` text to the string); each `<t>` is `_xHHHH_` decoded on its own; only root `<si>` elements count; table size and string length are limited |
| `xlsx/read/sheet_reader.dart` | `builders/xlsx_io.dart` → `XlsxGridReader._sheetRows`, `_readText` | rows are yielded lazily as typed cells, not a dense grid of strings; positions are checked and problems warned (Quds trusted every `r`); text is limited |
| `xlsx/read/cell_decoder.dart`, `xlsx/read/xlsx_reader.dart`, `xlsx/read/read_limits.dart`, `xlsx/read/read_exception.dart` | — (new) | Quds decoded cells inline in `XlsxGridReader` and had no limits or typed exceptions |
| `zip/archive_adapter.dart` (`ZipReader`) | — (new) | bounded inflation, limits from the central directory, CRC and duplicate-name checks |
| `xml/xml_escape.dart` (`decodeXstring`) | — (new) | the reverse of `escapeXstring` |
