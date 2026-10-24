# Excel checks

CI validates every fixture with the Open XML SDK and compares LibreOffice's
reading of it with the expected values (AGENTS.md, "Validation"). Neither is
Excel, so the owner opens each milestone's fixtures in Excel as well. A
milestone is done only when no fixture shows a repair prompt or a wrong value
([`0003`](decisions/0003-phase-1-scope-output-and-diagnostics.md)).

Write the fixtures with:

```bash
dart run tool/write_fixtures.dart build/fixtures
```

Then open each `build/fixtures/<name>.xlsx` in Excel. For every file, first
check that Excel opens it without the "We found a problem with some content"
repair prompt. The values below assume Turkish regional settings; other
locales show the same dates and numbers in their own order and separators.

## M1

### `m1_values`

One sheet, `Values`. Row 1 holds the column labels, row 2 the values.

- A2 `42`, B2 `3,14159`, C2 `-0,25`, all right-aligned numbers.
- D2 `TRUE`, E2 `FALSE` (`DOĞRU`, `YANLIŞ` in Turkish Excel), booleans, not
  text.
- F2 `plain text`, left-aligned.
- G2 `1234,5`: the `XlsxDecimal('1234.50')`, a number in the General format.
- H2 `24.10.2026`, a date. I2 `24.10.2026 13:45`, a date and time.
- J2 `1.234,50`: `1234.5` in the custom format `#,##0.00`.
- K2 is empty.
- L2 `9,0072E+15`; the formula bar shows `9007199254740990` (2^53 at
  Excel's 15 digits).

### `m1_dirty_text`

One sheet, `Text`, values in A1:A11. Use `=LEN(...)` in column B to count
characters.

- A1 `abcd`, A2 `xy`, A3 `pq`: the control characters and lone surrogates
  are gone, with no empty boxes or question marks.
- A4 is 32,767 `a`s: `=LEN(A4)` gives `32767`.
- A5 is 32,766 `a`s: `=LEN(A5)` gives `32766`, and the text ends in `a`, not
  half an emoji.
- A6 `  padded  ` keeps its two leading and two trailing spaces:
  `=LEN(A6)` gives `10`.
- A7 `Şube Müdürü`, A8 `Straße`, A9 an emoji, ` emoji `, then a man and a
  woman joined by a zero-width joiner (one family glyph or two people,
  depending on the font).
- A10 `_x0041_` and A11 `a_x00e9_b`, exactly as typed: not `A` and not
  `aéb`. The file stores them as `_x005F_x0041_` and `a_x005F_x00e9_b`,
  because Excel decodes `_xHHHH_` in cell text.

### `m1_sheets`

Fourteen sheets. Each sheet's A1 says `asked: ` and the name the caller
asked for.

- Tab order: `Başlangıç`, `Özet`, `a_b`, `A_B (2)`, `ŞUBE`, `şube (2)`,
  `LİSTE`, `liste (2)`, `STRASSE`, `straße (2)`, `Sheet10`, `History (2)`,
  `this name is far longer than al`, `_x0041_`.
- `Başlangıç` is first although it was added last (inserted at position 0).
- The active sheet, open on load, is `şube (2)`.
- `Sheet10`'s A1 is `asked: ` with nothing after it (the empty name).
- `History (2)`'s A1 is `asked: History` (Excel reserves `History`).
- The last tab's name is stored as `_x005F_x0041_`, escaped like cell text.
  Excel's tab must read `_x0041_` literally, not `A`. Its A1 shows
  `asked: _x0041_`.

### `m1_formulas`

One sheet, `Formulas`. Click each cell to see its formula in the formula bar.

- A1 `2` from `=SUM(1,1)`.
- B1 `hello` from `=CONCATENATE("hel","lo")`.
- C1 `TRUE` (`DOĞRU`) from `=AND(TRUE,TRUE)`.
- D1 `3` from `=1+2`. The file stores no result for it, so Excel computes it
  on open. Excel may ask to save changes on close; that is expected.

### `m1_empty`

Four sheets: `Empty`, `Nulls`, `Blank`, `EmptyString`.

- `Empty` has no cells.
- `Nulls`: A1 is empty, A2 is `x`.
- `Blank`: A1 `a`, row 2 empty, B3 `b`.
- `EmptyString`: A1 looks empty but holds an empty text, so
  `=ISBLANK(EmptyString!A1)` on another sheet gives `FALSE` and
  `=LEN(EmptyString!A1)` gives `0`.

### `m1_properties`

One sheet, `Props`, with `properties` in A1. Check File > Info > Properties
(Windows) or File > Properties (macOS):

- Title `Quarterly report`, Subject `Sales`, Author `Ahmet Urel`,
  Tags/Keywords `sales; q3`, Comments `A test workbook`, Category `Reports`,
  Company `Jetronik`, Last modified by `jet_office`.
- Created 24.10.2026 08:30 UTC and modified 24.10.2026 09:45:30 UTC, shown in
  local time (11:30 and 12:45 in Türkiye).

### `m1_dates`

One sheet, `Dates`, values in A1:F1.

- A1 `28.02.1900` (serial 59) and B1 `01.03.1900` (serial 61): Excel's
  fictitious 29.02.1900 sits between them.
- C1 `24.10.2026 00:00`.
- D1 is 23:59:59.999 on 24.10.2026, stored as serial 46319.99999998842.
  Excel should show `24.10.2026 23:59` on the built-in date-time format (no
  seconds): the same day, the time cut to the minute and not rounded up to
  00:00 on the 25th. With a custom format that shows seconds it should show
  `23:59:59`. Record what it actually shows if it differs.
- E1 `1850-06-15T00:00:00.000`, left-aligned text: a date before 1900 has
  no Excel serial.
- F1 `46.319,00`: a date written with the number format `#,##0.00`, so it
  shows the serial.

## M2

Open every fixture with Turkish regional settings. The numbers below follow
them (decimal comma, dot for thousands).

### `m2_styles`

One sheet, `Styles`: one row per style, the sample or value in column A and
its label in column B. Read each row against its label.

- Fonts: bold, italic, each underline kind (`single`, `doubleLine`, and the two
  accounting kinds), strike, superscript, subscript, size 18, Arial.
- The `font theme 4 tint 0.4` row: the package has no theme part, so Excel
  uses its default Office theme. Theme color 4 is accent 1, so the text
  should be a lightened blue (Office's `4472C4` at 40 % tint). Record the
  color you see; a black or missing color means Excel ignored the theme.
- One row per pattern type, in blue on yellow; a `none` pattern shows no fill.
- Two gradient rows: `gradient linear 90` (yellow to blue, top to bottom or
  the reverse) and `gradient path` (from the centre outwards).
- One row per border style, all four sides in blue; then a diagonal border
  going up and one going down.
- Horizontal alignment (general, left, center, right, fill, justify,
  centerContinuous, distributed) and vertical alignment (top, center, bottom,
  justify, distributed). `wrap text` wraps onto several lines and Excel
  makes the row taller. `indent 3` indents the left-aligned text; `rotation
  45` slants it; `vertical text` stacks the letters; `shrink to fit` shrinks
  it into the column; `reading order RTL` shows it right to left.
- `locked false` and `hidden true` look the same as the others; check them in
  Format Cells > Protection (unlocked, hidden).
- Number formats, each on `1234,5` and on 24.10.2026. Compare each shown text
  with its label (`integer`, `decimal2`, `thousands`, `scientific`,
  `fraction`, `time`, `elapsedTime`, `text`, the grouped, red-negative,
  percent and money variants with `₺`, `$` first and `€`). A date in a
  format that shows no date (all but `time` and `elapsedTime`) shows its
  serial `46319` in that format; that is expected.

### `m2_columns_rows`

Two sheets, `Layout` and `Defaults`.

- `Layout` row 1: the column widths are 5, 12, 40 and 255 characters (the
  last is as wide as Excel allows); column E is hidden (the header jumps from
  D to F); columns F, G and H carry an outline bar above the headings
  (F level 1, G and H level 2).
- Row 2 is 30 points tall, row 3 only 5 points. Row 4 is hidden (the numbers
  jump from 3 to 5, with no outline bar).
- Rows 5 to 7 are hidden detail rows: rows 5 and 6 at outline level 2, row 7
  at level 1. Row 8, `total (collapsed)`, shows a plus sign, and expanding
  it shows rows 5 to 7, with the inner group (rows 5 and 6) open.
- `Defaults`: the default row height is 18 points and the default column
  width 11 characters, on every row and column of the sheet.

### `m2_style_precedence`

One sheet, `Precedence`, with a money column B (`€`) and a date column C
(`yyyy-mm-dd`) set on the columns.

- Row 1, `Item`, `Amount`, `Date`, is bold in all three cells.
- Rows 2 and 3: B shows `1.200,50 €`-style money (`€` with two decimals) and
  C shows `2026-10-24`.
- Row 4, `Date in money`: B holds a date, so it shows the serial `46319` in
  the money format, and C shows `2026-10-24`.
- Row 5, `Total`: a thin top border on all of A5:C5, and B5 shows
  `1.245,75 €` in italic (the cell style adds to the row style and the
  column's money format).

### `m2_views`

Seven sheets; two are hidden. Excel must open on the `View` sheet. No tab
should look "grouped": the file sets the active tab but not `tabSelected`, so
Excel selects the active tab only; if the title bar says `[Group]`, record it.

- `Frozen`: row 1 and column A stay put while the other cells scroll (the
  header and the `Row` column).
- `Split`: a split, not a freeze: two panes with a movable divider, about 120
  points from the left and 60 from the top.
- `View`: zoom 85 %, no gridlines, no row and column headings, and the `0` in
  B1 is not shown (the sheet hides zeros); the tab is red.
- `RTL`: the sheet runs right to left (column A at the right edge); the
  Arabic and Hebrew text reads correctly.
- `Outline`: rows 2 and 3 group under row 1, which sits above them (the
  plus/minus sign is at row 1, not below row 3).
- `Hidden` appears in the Unhide dialog (right-click a tab > Unhide).
  `VeryHidden` does not appear there; it shows only in the VBA editor.

### `m2_merges_filter`

Two sheets, `Bob's Data` and `Plain`.

- `Bob's Data`: A1:D1 is merged, `Quarterly report` bold, 14 points,
  centered. B3:C4 is merged and shows `A merged block of text`.
- Row 6 (`Id`, `Name`, `Qty`, `Price`) carries the filter dropdown arrows,
  and filtering the list (for example `Qty`) works on rows 7 to 20.
- The workbook holds a hidden defined name `_xlnm._FilterDatabase` for that
  sheet. There must be no repair prompt. The Name Manager (Formulas > Name
  Manager) may list it as `_FilterDatabase`; record what it shows.
- `Plain` has no filter and no merges.

### `m2_formula_xstring`

One sheet, `Probe`. A1 holds the formula `="_x0041_"` and A2 the text
`_x0041_`.

- A2 must read `_x0041_`, as typed.
- Write down what A1 shows: `_x0041_` or `A`. The answer settles whether
  readers decode `_xHHHH_` inside `<f>`; the file stores the formula as
  given, not escaped. If it shows `A`, record that and ask for a ruling;
  do not change the encoder.

### Open question

Whether Excel treats a sheet named with the Kelvin sign (U+212A, which
looks like K) as equal to one named with the Latin letter K (U+004B) is unverified. The writer's duplicate check
folds case with Turkish and German rules but has no fixture for it. Settle
it when convenient and record the answer here.

## Results

| Date | Excel version and platform | Fixture | Result | Notes |
|---|---|---|---|---|
