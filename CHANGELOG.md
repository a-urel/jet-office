# Changelog

## 0.1.0-dev.1 (unreleased)

Phase 1, the XLSX writer, and phase 2, the XLSX reader. Not published yet.

### Phase 2: the XLSX reader

#### R1, foundation

- `XlsxReader` reads an XLSX file from bytes: the sheet list
  (`XlsxReadSheet`, with its visibility) and the date system on opening,
  then each sheet's rows lazily, as `XlsxReadRow`s of `XlsxReadCell`s.
- Cell values: text (shared and inline), numbers as `XlsxDecimal` with the
  file's digits, booleans and formula text with its cached result.
- The file is untrusted input: ZIP entries are inflated within
  `XlsxReadLimits` (entry count and size, total size, compression ratio,
  shared strings, XML depth, text length, sheets) with CRC checks, and the
  XML parser refuses a `DOCTYPE` and anything but UTF-8.
- A file that cannot be read throws `XlsxReadException`, whose
  `XlsxReadFailure` says why (`notZip`, `corruptZip`, `encrypted`,
  `legacyXls`, `unsupportedFormat` for Strict OOXML and `.xlsb`,
  `missingWorkbook`, `malformedXml`, `limitExceeded`).
- A cell or sheet that cannot be read exactly is a warning in
  `XlsxReader.warnings`, with the writer's `XlsxWarning` type and messages
  in English, German and Turkish.
- Every phase 1 fixture reads back to what the writer stored.

#### R2, types

- Number formats and cell formats from the styles part: each cell carries
  `numberFormatId`, `numberFormat` and `isDate`.
- A number in a date format reads as a UTC `DateTime`, one in a time format
  as a `Duration`, in the 1900 and 1904 date systems; ISO dates (`t="d"`)
  and inline strings are read.
- Error values (`XlsxErrorValue`), shared, array and data-table formula
  groups (`XlsxFormulaGroup`) and merged ranges (`XlsxReader.merges`,
  `mergesAt`).
- `XlsxDecimal.toDouble()` and `XlsxDecimal.toIntOrNull()`.

#### R3, other producers and hostile files

- Packages shaped like those of LibreOffice, Google Sheets, the .NET Open
  XML SDK and an ERP export are read, and CI reads LibreOffice's re-save of
  every fixture against the expected values.
- A hostile-file test per limit and per kind of damage, and a seeded fuzz
  test that requires the reader to throw nothing but `XlsxReadException`.
- A harness for files saved by Excel and Google Sheets, with values the
  owner confirms; the files themselves are still pending.
- `XlsxReadException`'s constructor is no longer `const` (it was in R1):
  its `part` is shortened and cleaned for display.

#### R4, release

- A read benchmark of the 100,000-row workload and of the largest single
  sheet the default limits accept (`docs/benchmark.md`). Reading is slower
  than writing on the VM (2.7 s against 1.5 s on the machine measured).
- The public API review, the README's "Reading" section, the example's read
  back and this changelog.

#### Changed since the M5 merge

- `XlsxWarning` gains `detail`, the parameter of a code that has one (the
  number format id of `unresolvedNumberFormat`); warnings of one code on one
  sheet are kept apart by detail, up to ten details.
- `XlsxWarningCode` gains the reader's 18 codes, from `sheetPartMissing` to
  `mergeRangeInvalid`, each with a message in English, German and Turkish.
- A warning may name no cell: `sheetPartMissing` concerns a whole sheet and
  `mergeRangeInvalid` counts skipped ranges, not cells.
- `XlsxDecimal` gains `toDouble()` and `toIntOrNull()`.

### Phase 1: the XLSX writer

#### M1, foundation

- `XlsxWriter` (in memory) and `XlsxStreamWriter` (to a sink), with the same
  calls and the same bytes on one platform.
- Cell values: text, numbers, booleans, `DateTime`, `XlsxDate`,
  `XlsxDecimal`, empty cells and `XlsxFormula` with a cached value.
- Sheets with sanitized, unique names, tab order and the active sheet.
- Document properties.
- Warnings for data the writer repairs, in English, German and Turkish.

#### M2, styling and layout

- Fonts, pattern and gradient fills, borders, alignment, protection and
  number formats, merged in the order column, row, cell.
- Column widths, row heights, hidden rows and columns, outlines.
- Sheet views, freeze and split panes, tab colors, hidden sheets.
- Merged cells and the auto filter.

#### M3, sheet and workbook features

- Defined names, print areas and print titles.
- Hyperlinks to web, e-mail, sheet and location targets.
- Data validation and conditional formatting (including data bars and icon
  sets).
- Page setup, headers and footers.
- Sheet and workbook protection.
- More document properties: manager, content status and custom properties.

#### M4, objects

- Rich text cells, notes, PNG and JPEG pictures and tables with totals.

#### M5, release

- `XlsxListExport`: a caption, a frozen header repeated on every printed
  page, an auto filter or an Excel table, and a totals row, in one call.
  A Count total is shown as a plain number, whatever the column format.
- A benchmark of 100,000 rows on the VM and in Chrome (`docs/benchmark.md`).
- The README, an example and this changelog.
- Phase 1 writes XLSX only; phase 2 above adds the reader. Modifying files,
  and DOCX, are later phases.

#### Changed since the M4 merge

- Style errors: a bad fill, border or alignment in a style is now named
  `fill.<field>`, `border.<field>` or `alignment.<field>`. It was the bare
  field (`foreground`, `left`, `indent`). A bad font in a row or cell style
  is named `font.<field>` (`font.size`, `font.name`); on main it was the bare
  field (`size`, `name`). Column styles name
  `columns[i].style.font.<field>`, `columns[i].style.fill.foreground` and so
  on (was `columns[i].style.<field>`). The name now says which part failed.
- Conditional format style errors: `rules[i].style.<field>` is now
  `rules[i].style.<part>.<field>`. For example `rules[0].style.foreground`
  became `rules[0].style.fill.foreground`, `rules[2].style.size` became
  `rules[2].style.font.size` and `rules[0].style.left` became
  `rules[0].style.border.left`. `rules[i].style.numFmt`, `.alignment` and
  `.protection` are unchanged.
- A `DateTime` is cut to whole seconds, with no warning. Excel shows a serial
  rounded to the second, so 23:59:59.999 used to show as the next day. To keep
  milliseconds, write the serial as a `double` with an `ss.000` format.
- A finite `double` is written in its shortest form (5.0 as 5), the same on
  the VM and the web.
- A table without a header row is refused once its totals row is written, and
  huge picture offsets and sizes throw `ArgumentError`.
- A data bar without `negativeBorderColor` writes none, so Excel draws the
  negative border in the positive border color; the `XlsxDataBar` dartdoc
  says so.
