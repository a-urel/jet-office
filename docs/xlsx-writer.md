# XLSX writer

What phase 1 builds and the rules it holds to. The writer's shape comes from
[`0001`](decisions/0001-port-a-file-engine-from-quds.md) and
[`0002`](decisions/0002-two-xlsx-paths-stream-and-model.md). The phase-1 scope,
output shape and diagnostics are
[`0003`](decisions/0003-phase-1-scope-output-and-diagnostics.md). The draft API
lives in a git-ignored working document under `docs/superpowers/`. This page
keeps what has to outlive it.

Until phase 1 ships, this page describes the target. Once a rule below has a
test, its row names that test.

## Rules the writer enforces

Data problems become warnings and the file still opens. Programmer errors
throw. This follows `jet_print`'s "render, don't crash, report diagnostics"
habit.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Sheet name with `[ ] : * ? / \`, longer than 31, or empty | sanitized, warning `sheetNameChanged` | Excel refuses the file otherwise | `test/xlsx/sheet_name_test.dart` |
| `_xHHHH_` in a sheet name (such as `_x0041_`) | kept in the name; written escaped as `_x005F_x0041_`, like cell text, so Excel and LibreOffice show the name as given. The 31-unit limit and uniqueness use the original name | both read ST_Xstring escapes in sheet names | `test/xlsx/workbook_parts_test.dart`, `test/xlsx/xlsx_writer_test.dart` |
| Duplicate sheet name (case-insensitive, Turkish and German letters and the Kelvin sign included) | suffixed ` (2)`, warning `sheetNameDuplicated` | same | `test/xlsx/sheet_name_test.dart` |
| Control character U+0000–U+001F other than tab, LF, CR, or a lone UTF-16 surrogate | removed, warning `invalidCharactersRemoved` | XML 1.0 forbids it | `test/xml/xml_escape_test.dart`, `test/xlsx/cell_encoder_test.dart` |
| Text longer than 32,767 characters (UTF-16 code units) | truncated without splitting a surrogate pair, warning `textTruncated` | Excel's cell limit | `test/xlsx/cell_encoder_test.dart` |
| `_xHHHH_` in formula text (such as `="_x0041_"`) | written escaped in `<f>` as `"_x005F_x0041_"`, like cell text, so Excel shows the formula as given. LibreOffice does not decode inside `<f>` and shows `_x005F_x0041_`. The 8,192-unit limit uses the original text (decision 0005) | Excel decodes ST_Xstring escapes in `<f>` and writes this form itself | `test/xml/xml_escape_test.dart`, `test/xlsx/cell_encoder_test.dart`, `test/fixtures/fixtures_test.dart` |
| A formula's cached string longer than 32,767 characters | truncated like text, warning `textTruncated` | same | `test/xlsx/cell_encoder_test.dart` |
| `int` beyond 2^53, also as a formula's cached value | written, warning `intPrecisionLost`. On the web a whole `double` beyond 2^53 is indistinguishable from an `int`, so it warns too | Excel stores every number as a double, so it may round the value | `test/xlsx/cell_encoder_int_test.dart` |
| Date before 1900-01-01 or after 9999-12-31, however far (`XlsxDate(300000, 1, 1)` too) | ISO 8601 text with a sign for negative years and at least four year digits, warning `dateOutsideExcelRange` | Excel has no date serial for it | `test/xlsx/cell_encoder_test.dart`, `test/xlsx/date_serial_test.dart` |
| Column, row and cell styles on one cell | merged: cell over row over column, field by field; a field set back to its default (`XlsxFont(bold: false)`, `XlsxNumFmt.general`) wins over a lower layer. The date format (14/22) is added only when the merged number format is `null`. Identical layer triples share one cell format | a layer that says nothing inherits; one that says something decides | `test/xlsx/cell_encoder_test.dart` |
| `XlsxCell(null, style: s)` with a non-null `s` | an empty styled cell `<c r="C5" s="n"/>`, written by the encoder, with the merged style (column, row, cell); nothing when that resolves to the default format 0. A bare `null` or `XlsxCell(null)` writes no cell. A row whose only cells are styled empties is written; an invalid style throws and records nothing, not even the row element (ruling R11) | a border or fill must reach a cell that holds nothing, such as the empty end of a totals row | `test/xlsx/cell_encoder_test.dart`, `test/xlsx/xlsx_writer_test.dart`, `test/fixtures/fixtures_test.dart` |
| Date in a number format that shows no date | written with that format, warning `dateInNonDateFormat`. A custom code shows a date when it has one of `d m y h s` outside quotes, `\` escapes, the character after `_` or `*`, `[...]` sections, `General`, `AM/PM` and `A/P` (any case), so `AM/PM` alone and `0_d` show no date | the caller chose the format, but the cell shows a bare serial | `test/xlsx/cell_encoder_test.dart`, `test/xlsx/number_format_test.dart` |
| Row 1,048,577 or column 16,385 | `XlsxLimitError` | the caller decides whether to split into sheets | `test/xlsx/xlsx_writer_test.dart` |
| More than 65,490 unique cell formats | `XlsxLimitError` | Excel's limit | `test/xlsx/style_registry_test.dart` |
| More than 512 unique fonts (the default font counts as one) | `XlsxLimitError('fonts', 512)`, nothing registered | Excel's limit per workbook | `test/xlsx/style_registry_test.dart` |
| Styles that look the same but are spelled differently (`XlsxFont()` and Calibri 11, a hex and an rgb color, a `none` pattern and no fill, a border side that draws no line and no side, a diagonal side without `diagonalUp` or `diagonalDown` (written as an empty `<diagonal/>`) and no diagonal, General alignment or an explicit General and nothing) | one cell format: fonts, fills and borders are deduplicated by the XML they write, cell formats by their parts | keeps the file small and the 65,490 limit far away | `test/xlsx/style_registry_test.dart`, `test/xlsx/border_test.dart` |
| More than 200 distinct custom number format codes | `XlsxLimitError('number formats', 200)`, nothing registered | Excel's lowest limit across language versions (200–250) | `test/xlsx/style_registry_test.dart` |
| An invalid `XlsxNumFmt.number`, `percent` or `money` argument: decimals outside 0–30, or a symbol with `"` or characters XML forbids | `ArgumentError` at once | a programmer's choice; Excel would refuse the format | `test/xlsx/number_format_test.dart` |
| `NaN` / infinity | `ArgumentError` | no valid XML number exists | `test/xlsx/cell_encoder_test.dart` |
| `XlsxDecimal` text that is not plain digits | `ArgumentError` | see [Money](#money) | `test/xlsx/values_test.dart`, `test/xlsx/cell_encoder_test.dart` |
| Formula text empty after its one leading `=` | `ArgumentError` naming the cell and sheet | Excel refuses an empty formula | `test/xlsx/cell_encoder_test.dart`, `test/xlsx/xlsx_checker_test.dart` |
| Formula text longer than 8,192 characters (UTF-16 code units) | `ArgumentError` naming the cell and sheet | Excel's formula limit | `test/xlsx/cell_encoder_test.dart`, `test/xlsx/xlsx_checker_test.dart` |
| Invalid number format: a built-in id outside 0–163, or a custom code that is empty or holds characters XML forbids | `ArgumentError` | Excel refuses the style otherwise | `test/xlsx/style_registry_test.dart`, `test/xlsx/cell_encoder_test.dart` |
| Alignment indent outside 0–250, or text rotation outside 0–180 other than 255 | `ArgumentError` naming the field | ECMA-376 limits; Excel refuses the style otherwise | `test/xlsx/alignment_test.dart`, `test/xlsx/style_registry_test.dart` |
| An invalid style part: a font name that is empty, longer than 31 or not XML-clean, a font size outside 1–409, a family outside 0–14 or a charset outside 0–255; a color out of range (theme 0–11, tint −1–1, indexed 0–65, RGB 0–FFFFFF); a gradient with fewer than two stops, stop positions outside 0–1 or decreasing, a non-finite degree or an edge outside 0–1 | `ArgumentError` naming the field when the style is first used, nothing registered | a programmer's choice; Excel refuses the style otherwise | `test/xlsx/style_registry_test.dart`, `test/xlsx/font_test.dart`, `test/xlsx/fill_test.dart`, `test/xlsx/color_test.dart`, `test/xlsx/border_test.dart` |
| Characters XML forbids in a document property or in formula text | `ArgumentError` | the caller built the text; silently dropping characters would change a formula's meaning | `test/xlsx/properties_test.dart`, `test/xlsx/xlsx_writer_test.dart`, `test/xlsx/cell_encoder_test.dart` |
| A formula's cached value that is not `null`, `num`, `String` or `bool` | `ArgumentError` | a cached value is a programmer's choice | `test/xlsx/cell_encoder_test.dart` |
| An `XlsxDate` that does not exist, such as 30 February | `ArgumentError` naming the cell and sheet | no serial or text can stand for it | `test/xlsx/date_serial_test.dart`, `test/xlsx/cell_encoder_test.dart` |
| `addSheet` at a position outside 0 to the number of sheets | `RangeError` | | `test/xlsx/xlsx_writer_test.dart` |
| `setActiveSheet` with a sheet of another writer | `ArgumentError` | | `test/xlsx/xlsx_writer_test.dart` |
| `setActiveSheet` with a hidden or very hidden sheet | `ArgumentError`, the earlier active sheet stays | Excel cannot open on a hidden tab | `test/xlsx/xlsx_writer_test.dart` |
| No `setActiveSheet` and the first tab hidden | the first visible tab in tab order is active | Excel cannot open on a hidden tab | `test/xlsx/xlsx_writer_test.dart` |
| `close()` when every sheet is hidden | `StateError` before any workbook-level part is written; the writer is neither failed nor closed, so a visible sheet can be added and `close()` called again | Excel refuses a workbook without a visible sheet | `test/xlsx/xlsx_writer_test.dart` |
| A cell value of an unsupported type | `ArgumentError` | a value is a programmer's choice, so guessing would hide the bug | `test/xlsx/cell_encoder_test.dart` |
| An `XlsxCell` holding another `XlsxCell` | `ArgumentError` | a cell has one value and one style | `test/xlsx/cell_encoder_test.dart` |
| A header setting (`columns`, `defaultSizes`, `view`, `freeze`, `split`, `tabColor`, `outlineSummary`) after the first `row` or `blankRow`, or on a finished sheet | `StateError` naming the sheet and the setting, nothing recorded; a second call before the first row replaces the first | the header is written before the rows (forward-only writer, 0002) | `test/xlsx/xlsx_writer_test.dart` |
| Column width outside 0–255, row height outside 0–409 (row, blank row or default), outline level outside 0–7 | `ArgumentError` naming the field (`columns[1].width`, `height`, `rowHeight`, `outlineLevel`, …), nothing recorded | Excel's limits (`XlsxLimits`); a programmer's choice | `test/xlsx/xlsx_writer_test.dart`, `test/xlsx/worksheet_parts_test.dart` |
| More than 16,384 entries in `columns` | `XlsxLimitError('columns', 16384)`, nothing recorded | Excel's column limit | `test/xlsx/xlsx_writer_test.dart` |
| An invalid column style, or one that hits a limit, after valid ones | an invalid style throws `ArgumentError` named `columns[i].style`, with the value and message of the style field at fault; a limit throws `XlsxLimitError` like a cell style; none of the list's styles is registered | atomic failure; the name says which column | `test/xlsx/xlsx_writer_test.dart`, `test/xlsx/style_registry_test.dart` |
| A row or blank row with only attributes (height, hidden, outline level, collapsed) | a `<row>` element is still written; `sheetFormatPr/@outlineLevelRow` is the deepest row level written, `@outlineLevelCol` the deepest column level | the attributes would be lost otherwise | `test/xlsx/xlsx_writer_test.dart` |
| Equal adjacent columns; a column that sets nothing | joined into one `<col>`; not written | keeps the part small | `test/xlsx/worksheet_parts_test.dart` |
| Zoom outside 10–400, frozen rows outside 0–1,048,575, frozen columns outside 0–16,383, a split offset that is negative, NaN or infinite or whose twips (`offset * 20`, rounded) exceed 2^31 − 1 (ruling R12), or a tab color out of range | `ArgumentError` naming the field (`zoom`, `rows`, `columns`, `x`, `y`, `color`) at the call, nothing recorded | Excel's limits (`XlsxLimits`); a programmer's choice. `xSplit`/`ySplit` are 32-bit, and a larger offset used to pass the call and then fail `close()`, with VM and web output differing above about 4.6e17 | `test/xlsx/xlsx_writer_test.dart`, `test/xlsx/sheet_view_test.dart` |
| A cell reference whose row has leading zeros (`A01`, `A0000001`) in `XlsxRange.parse` | `ArgumentError` | Excel writes no leading zeros; accepting them would give one cell two spellings | `test/xlsx/range_test.dart` |
| `freeze` or `split` with 0 on both axes | no `pane` and no `selection` written | a header count computed from data may be 0; that is not a bug | `test/xlsx/worksheet_parts_test.dart`, `test/xlsx/xlsx_writer_test.dart` |
| `freeze(rows: n)` only | the active pane is `bottomLeft` (columns only: `topRight`, both: `bottomRight`); Quds wrote `bottomRight` | the active pane must be one the splits leave | `test/xlsx/xlsx_writer_test.dart`, `test/xlsx/xlsx_checker_test.dart` (rule 19) |
| `merge` of a single cell, a range outside the sheet or with its first corner after its last, or one that overlaps an earlier merge | `ArgumentError`; the overlap message names both ranges; nothing recorded, the earlier merges stay. Quds accepted overlapping merges | Excel refuses a file with overlapping merges | `test/xlsx/xlsx_writer_test.dart`, `test/xlsx/xlsx_checker_test.dart` (rule 20) |
| `autoFilter` on a range outside the sheet or with its first corner after its last | `ArgumentError`, the earlier filter stays; a second valid call replaces the first. Quds wrote any filter string unchecked | Excel refuses an invalid filter range | `test/xlsx/xlsx_writer_test.dart`, `test/xlsx/xlsx_checker_test.dart` (rule 21) |
| `merge` or `autoFilter` after the sheet is finished (the next `addSheet`, `close()`) | `StateError`, nothing written; both are allowed after rows | trailer settings are written when the sheet finishes (0002) | `test/xlsx/xlsx_writer_test.dart` |
| A sheet with an auto filter | the workbook gets a hidden `_xlnm._FilterDatabase` defined name, `localSheetId` the final tab index (resolved at `close()`), text `'<name>'!<absoluteRef>` with the name always quoted and `'` doubled. The text is a formula and goes through `escapeFormulaText`, the helper `<f>` uses too, which escapes `_xHHHH_` like cell text and then escapes XML, so the sheet `D_x0041_` reads `'D_x005F_x0041_'!$A$1:$B$1`, spelled like its `<sheet name>` `D_x005F_x0041_` (decision 0005, which supersedes ruling R10) | Excel keeps the filter's range in that name and decodes `_xHHHH_` in it: an unescaped `'_x0041_'!$A$1` is read as a sheet `A`, which Excel turns into an external link when it saves (M2 Excel check) | `test/xml/xml_escape_test.dart`, `test/xlsx/workbook_parts_test.dart`, `test/xlsx/xlsx_writer_test.dart`, `test/fixtures/fixtures_test.dart` |
| A defined name that is empty, longer than 255 characters, does not start with a letter, `_` or `\`, holds a character other than letters, digits, `_`, `.` or `\`, starts with `_xlnm.` (any case), is `R`, `C`, `r` or `c`, or reads as a cell reference (`A1`, `XFD1048576`) or as R1C1 (`R1C1`, `RC`) | `ArgumentError` naming `name`, nothing recorded. `XFE1` and `A1B` are valid | Excel refuses such a name, or reads it as a reference | `test/xlsx/defined_name_test.dart` |
| A defined name's formula that is empty after its one leading `=`, longer than 8,192 characters or holds characters XML forbids; a comment longer than 255 characters or holding such characters | `ArgumentError` naming `formula` or `comment`, nothing recorded. The stripped formula is written through `escapeFormulaText`, the name and comment through `escapeXstring` | one shared check, `checkFormulaText`; same limits as `<f>` | `test/xlsx/formula_text_test.dart`, `test/xlsx/defined_name_test.dart` |
| A defined name twice in one scope (workbook, or one sheet), ignoring case as sheet names do | `ArgumentError` naming both spellings; the first stays. The same name in the workbook and on a sheet, or on two sheets, is allowed | Excel refuses duplicates within a scope | `test/xlsx/defined_name_test.dart`, `test/xlsx/xlsx_checker_test.dart` |
| `printArea` with no range, or a range outside the sheet or with its first corner after its last; `printTitles` with a row span outside 0–1,048,575 or a column span outside 0–16,383, or a span whose first is after its last | `ArgumentError` naming `ranges[i]`, `rows` or `columns`; the earlier setting stays. A later valid call replaces the earlier one; `printTitles()` with neither argument clears the titles | a programmer's choice; Excel refuses the name otherwise | `test/xlsx/defined_name_test.dart` |
| A print area or print titles | `_xlnm.Print_Area` / `_xlnm.Print_Titles`, scoped by `localSheetId` (the final tab index), absolute and always quoted: `'O''Brien'!$A$1:$D$20,'O''Brien'!$F$1:$G$5`, and columns before rows, `'S'!$A:$B,'S'!$1:$1`. Quds wrote relative, unquoted titles | Excel reads only absolute, quoted references for sheet names that need it; quoting always is safe | `test/xlsx/defined_name_test.dart`, `test/xlsx/xlsx_checker_test.dart`, `test/fixtures/fixtures_test.dart` |
| `definedNames` order | workbook names in definition order, then per tab in tab order `_xlnm._FilterDatabase`, `_xlnm.Print_Area`, `_xlnm.Print_Titles`, then that sheet's names | deterministic output | `test/xlsx/defined_name_test.dart` |
| `defineName`, `printArea` or `printTitles` on a finished sheet; `defineName` of the writer after `close()` | `StateError`, nothing recorded. The writer's `defineName` is allowed until `close()` | trailer settings are written when the sheet finishes | `test/xlsx/defined_name_test.dart` |
| A hyperlink with an empty address (`XlsxHyperlink.url('')`), an address of more than 2,079 characters (counted after percent-encoding), an empty location, a tooltip of more than 255 characters, or any of address, location, text or tooltip holding characters XML forbids | `ArgumentError` naming `address`, `location`, `text` or `tooltip`, raised by `row` before the cell is encoded: nothing of the cell is written or recorded, the cells before it stay, the row counts. The link's text is checked even though plain cell text is only repaired and warned about, because it is also written to the `display` attribute | a programmer's choice; Excel refuses or truncates such a link | `test/xlsx/hyperlink_test.dart` |
| The 65,531st hyperlink of a sheet | `XlsxLimitError('hyperlinks', 65530)` before its cell is written; the row still counts | Excel's limit per worksheet | `test/xlsx/hyperlink_limit_test.dart`, `test/xlsx/xlsx_checker_test.dart` (rule 22) |
| A hyperlink cell's font | the font `XlsxFont(color: XlsxColor.theme(10), underline: XlsxUnderline.single)` is the lowest layer, merged beneath the column, row and cell fonts: a field any of them sets wins (a bold column gives bold, blue, underlined; a red cell font stays red; `underline: XlsxUnderline.none` removes the line). One resolution per column, as for other cells | Excel shows a link in the theme's hyperlink color, underlined, and a styled link must not lose that or force it | `test/xlsx/hyperlink_test.dart` |
| A URL given to `XlsxHyperlink.url` | percent-encoded with `encodeUriText`: uppercase `%XX` of the UTF-8 bytes for every character outside `A–Z a–z 0–9` and ``- . _ ~ : / ? # [ ] @ ! $ & ' ( ) * + , ; = %``, so a space becomes `%20` and an existing `%20` stays. The cell shows the URL as given. A `mailto:` subject is encoded as a URI component, so `Q&A` is `Q%26A` | the relationship target must be a valid URI | `test/xlsx/hyperlink_test.dart` |
| Hyperlinks to one address | share one relationship in `xl/worksheets/_rels/sheet{n}.xml.rels`, ids `rId1`, `rId2`, ... in first-use order, `TargetMode="External"`; the part exists only when a sheet has an external link. An internal link (`location`) has no relationship. `location`, `tooltip` and `display` go through `escapeXstring` | deterministic output; Excel decodes `_xHHHH_` in these attributes | `test/xlsx/hyperlink_test.dart`, `test/xlsx/xlsx_checker_test.dart` (rule 22), `test/fixtures/fixtures_test.dart` |
| `close()` with no sheets | `StateError` | a workbook needs at least one sheet | `test/xlsx/xlsx_writer_test.dart` |
| `close()` twice, or a row after `close()` | `StateError` | | `test/xlsx/xlsx_writer_test.dart` |

## What the writer supports

Milestones M1 and M2 of phase 1. Later milestones extend this list.

**M1, foundation**

- Cell values: text, numbers, booleans, dates, decimals, empty cells and
  formulas with an optional cached value.
- Sheets: sanitized, unique names, tab order, the active sheet.
- Workbook document properties.
- Streaming output: rows go to the file as written, shared strings last.
- Warnings for data problems, in English, German and Turkish.

**M2, styling and layout**

- Styles: fonts, pattern and gradient fills, borders, alignment, cell
  protection and number formats, as value types merged in the order column,
  row, cell.
- Columns and rows: widths, heights, hidden, outline levels and collapsed
  groups, default sizes, the outline summary position.
- Sheet views: zoom, gridlines, headings, zeros, right to left, freeze and
  split panes, tab colors, hidden and very hidden sheets.
- Merged cells and the auto filter with its `_xlnm._FilterDatabase` name.

## Money

Monépro holds amounts in `Decimal` from `package:decimal`. On 2026-10-24 its
client used `decimal ^3.2.6` in 360 files, and its amount fields were 419
`Decimal` against 42 `double`.

- **`XlsxDecimal` takes a `String`.** Monépro writes
  `XlsxDecimal(amount.toString())`. `Decimal.toString()` always prints plain
  digits, `-?\d+(\.\d+)?`, with no exponent and no grouping. The encoder
  writes those digits into `<v>` verbatim, so `0.1` stays `0.1` and no
  `double` round trip happens on the Dart side.
- **`jet_office` does not depend on `package:decimal`.** `archive` stays the
  only runtime dependency (0001), and `jet_print` would otherwise inherit
  `decimal`. Accepting `Decimal` directly would need a new decision record.
- **Anything but plain digits throws.** `XlsxDecimal('1.234,56')`,
  `XlsxDecimal('1e3')` and `XlsxDecimal('')` raise an `ArgumentError`, because
  the caller built the string.
- **A `double` column passes a `double`.** The encoder writes it as a number
  and rejects `NaN` and infinity.
- **Excel keeps 15 significant digits.** It reads every number as an IEEE
  double. Money fits easily. `XlsxDecimal` prevents a second rounding in Dart,
  not Excel's own. A value beyond the `double` range (about 1.8e308) is
  still written verbatim and Excel rounds it.

## Port map

Each file below names its Quds source path and commit in its library doc
comment (AGENTS.md). Quds paths are relative to
`../quds_office_suite/packages/quds_office_engine/lib/src/`, at commit
`15c5d29`.

| jet_office file (`lib/src/`) | Ported from Quds | Changes |
|---|---|---|
| `xml/xml_escape.dart` | `xml/xml_reader.dart` → `encodeXmlText`, `encodeXmlAttribute` | strips forbidden control characters, reports them |
| `xml/xml_writer.dart` | `xml/xml_writer.dart` | writes to any `StringSink`, so a sheet streams into a `Utf8Buffer`; text and attributes go through the scrub-checked escapers |
| `xml/utf8_buffer.dart` | — (new) | stores written text as UTF-8 bytes in chunks, not one string; `takeChunks` hands them out unjoined |
| `xml/xml_number.dart` | — (new) | `formatXmlDouble`: attribute numbers print the same on the VM and in the browser |
| `opc/content_types.dart`, `opc/relationships.dart` | `opc/content_types.dart`, `opc/relationships.dart` (write side) | write-only in phase 1, no crypto; relationships can be external (hyperlinks) |
| `opc/ooxml.dart` | `xml/namespaces.dart` → `OfficeNamespaces`; `opc/content_types.dart` → `OfficeContentTypes` | only the namespaces, relationship types and content types a spreadsheet uses |
| `zip/archive_adapter.dart` | — (new) | the only file that imports `package:archive`; `addChunks` adds an entry from a list of chunks, copying them once into one buffer for the encoder |
| `xlsx/cell_encoder.dart` | `builders/xlsx_io.dart` → `_sheetXml` cell branch | the one encoder from 0002: dates, decimals, formulas, NaN; a hyperlink's text with the hyperlink font beneath the merged font |
| `xlsx/style_registry.dart` | `builders/xlsx_io.dart` → `style` with its `_Font`, `_Fill` and `_Xf` dedupe, `_numFmtId`, `_stylesXml` | value-typed `XlsxStyle` with the full vocabulary; fonts, fills and borders deduplicated by their rendered XML and cell formats by their parts; every part validated; atomic registration; font, number format and cell format limits |
| `xlsx/style.dart` | — (new) | `XlsxStyle` with six optional parts and `merge`; Quds' `style` takes loose parameters |
| `xlsx/xlsx_writer.dart` | `builders/xlsx_io.dart` → `XlsxWorkbookBuilder.addSheet`, `build` | one sheet open at a time, finished by the next `addSheet` or `close()`; tab order apart from creation order, the active sheet, shared strings and styles written last, sheet visibility |
| `xlsx/sheet_writer.dart` | `builders/xlsx_io.dart` → `XlsxSheetBuilder` row loop, `colWidth` and row heights, `_sheetXml` | `XlsxSheetWriter` and its implementation `WorksheetWriter`: streams rows; columns, default sizes and row attributes, header settings frozen at the first row; view, panes, tab color and outline summary; merged ranges (no overlaps) and the auto filter, validated, as trailer settings; hyperlink cells validated before they are encoded and recorded after, written as `hyperlinks` plus the sheet's relationships part |
| `xlsx/workbook_context.dart` | — (new) | `WorkbookContext`: the encoder, shared strings, styles, warnings, ZIP and failure state a sheet writer shares with its workbook writer |
| `xlsx/worksheet_parts.dart` | `builders/xlsx_io.dart` → `_sheetXml` frame, its `<cols>` and `ht` writing, `merge` and `autoFilterRef` | header and trailer rendered at finish and handed to the ZIP with the row chunks, which `addChunks` copies once into one buffer; widths, heights and outline levels checked; equal columns joined; `sheetFormatPr` with default sizes and outline levels; `sheetPr` (tab color, outline summary position); `sheetView` with panes; `autoFilter` and `mergeCells` in the trailer from validated ranges, overlap detection; `hyperlinks` in the trailer, `worksheetRelationshipsXml` and `worksheetRelsPartName` |
| `xlsx/sheet_view.dart` | `builders/xlsx_io.dart` → `freezeRows`, `freezeCols`, `rightToLeft` | the pane's active part follows the split; `selection`; zoom, gridlines, headings, zeros and formula display; split panes; sheet visibility |
| `xlsx/column.dart` | — (new; Quds' `colWidth` takes a width and a span) | `XlsxColumn` with width, style, hidden, outline level and collapsed |
| `xlsx/workbook_parts.dart` | `builders/xlsx_io.dart` → package, relationship and `workbook.xml` steps of `XlsxWorkbookBuilder.build` | tab order apart from creation order, active tab (never a hidden one), sheet `state`, `calcPr`, the `_xlnm._FilterDatabase` defined names |
| `xlsx/formula_text.dart` | — (new; Quds built references by concatenation) | `checkFormulaText` and `quotedSheetRef`, the shared checks for formula-typed text and sheet references |
| `xlsx/defined_name.dart` | — (new; Quds wrote only print titles, relative and unquoted) | `XlsxDefinedName` and the name, comment, formula and uniqueness checks |
| `xlsx/hyperlink.dart` | — (new; Quds wrote a URL as plain text) | `XlsxHyperlink` with its four factories, `encodeUriText` and the link checks |
| `xlsx/sheet_name.dart` | `builders/office_markup.dart` → `sheetName` | case-insensitive uniqueness |
| `xlsx/cell_ref.dart` | `builders/office_markup.dart` → `colName` | top-level; an index outside the sheet throws `RangeError`; `cellRef` and `parseCellRef` are new |
| `xlsx/color.dart` | `sheet/styles/sml_styles.dart` → `SmlStyleSheet.normalizeRgb` | the idea only: invalid input throws instead of returning `''`; theme, indexed and auto colors added |
| `xlsx/font.dart` | — (new; Quds' private `_Font` in `builders/xlsx_io.dart` was thinner) | public `XlsxFont` with every `CT_Font` property, nullable fields and `merge`; validated at registration |
| `xlsx/fill.dart` | — (new; Quds' private `_Fill` in `builders/xlsx_io.dart` held one solid color) | public `XlsxFill` (all 19 patterns, linear and path gradients) replacing a single solid color; validated at registration |
| `xlsx/border.dart` | — (new; Quds' private `_Border` in `builders/xlsx_io.dart` was thinner) | public `XlsxBorder` with all seven sides, diagonal flags and 13 line styles, side-wise `merge`; validated at registration |
| `xlsx/alignment.dart` | — (new; Quds kept alignment as loose fields of its private `_Xf`, with no protection) | public `XlsxAlignment` and `XlsxProtection` with nullable fields and `merge`; all-default values write nothing; validated at registration |
| `xlsx/range.dart` | — (new) | `XlsxRange`; Quds keeps ranges as strings |
| `xlsx/properties.dart` | `office/office_document_properties.dart` | only a workbook's fields, dates only when given, text checked for forbidden characters |
| `xlsx/xlsx_table.dart` | — (new) | |
| `xlsx/shared_strings.dart` | `sheet/shared_strings.dart` | written last, `count`/`uniqueCount` checked |
| `xlsx/validation.dart`, `xlsx/conditional_format.dart`, `xlsx/table_part.dart`, `xlsx/sheet_protection.dart` | `sheet/serial/sheet_serial.dart` (data validation, conditional formats, defined names, table part, sheet protection) | element writers take the public value types (M3, M4); cell protection is `XlsxProtection` in `alignment.dart` |
| `xlsx/drawing.dart` | `sheet/serial/sheet_drawing_io.dart`; `builders/xlsx_io.dart` → `addPicture` | PNG and JPEG, one-cell and two-cell anchors (M4) |

Out of phase 1: see [`0003`](decisions/0003-phase-1-scope-output-and-diagnostics.md).
