# Changelog

## 0.1.0-dev.1 (unreleased)

Phase 1: the XLSX writer. Not published yet.

### M1, foundation

- `XlsxWriter` (in memory) and `XlsxStreamWriter` (to a sink), with the same
  calls and the same bytes.
- Cell values: text, numbers, booleans, `DateTime`, `XlsxDate`,
  `XlsxDecimal`, empty cells and `XlsxFormula` with a cached value.
- Sheets with sanitized, unique names, tab order and the active sheet.
- Document properties.
- Warnings for data the writer repairs, in English, German and Turkish.

### M2, styling and layout

- Fonts, pattern and gradient fills, borders, alignment, protection and
  number formats, merged in the order column, row, cell.
- Column widths, row heights, hidden rows and columns, outlines.
- Sheet views, freeze and split panes, tab colors, hidden sheets.
- Merged cells and the auto filter.

### M3, sheet and workbook features

- Defined names, print areas and print titles.
- Hyperlinks to web, e-mail, sheet and location targets.
- Data validation and conditional formatting (including data bars and icon
  sets).
- Page setup, headers and footers.
- Sheet and workbook protection.
- More document properties: manager, content status and custom properties.

### M4, objects

- Rich text cells, notes, PNG and JPEG pictures and tables with totals.

### M5, release

- `XlsxListExport`: a caption, a frozen header repeated on every printed
  page, an auto filter or an Excel table, and a totals row, in one call.
  A Count total is shown as a plain number, whatever the column format.
- A benchmark of 100,000 rows on the VM and in Chrome (`docs/benchmark.md`).
- The README, an example and this changelog.
- Phase 1 writes XLSX only. Reading and modifying files, and DOCX, are later
  phases.

### Changed since the M4 merge

- Style errors: a bad fill, border or alignment in a style is now named
  `fill.<field>`, `border.<field>` or `alignment.<field>`. It was the bare
  field (`foreground`, `left`, `indent`). A bad font in a row or cell style
  is named `font.<field>` (unchanged). Column styles name
  `columns[i].style.font.<field>`, `columns[i].style.fill.foreground` and so
  on (was `columns[i].style.<field>`). The name now says which part failed.
- Conditional format style errors: `rules[i].style.<field>` is now
  `rules[i].style.<part>.<field>`. For example `rules[0].style.foreground`
  became `rules[0].style.fill.foreground`, `rules[2].style.size` became
  `rules[2].style.font.size` and `rules[0].style.left` became
  `rules[0].style.border.left`. `rules[i].style.numFmt`, `.alignment` and
  `.protection` are unchanged.
- `XlsxListColumn.totals` is now `XlsxListColumn.totalsFunction`: the
  constructor parameter, the field, the `toString` label and the error name
  (`columns[i].totals` became `columns[i].totalsFunction`). `XlsxTableColumn`
  already used that name for the same enum.
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
