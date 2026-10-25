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
- One row per pattern type, each with a blue foreground and a yellow
  background: `solid` shows plain blue (the foreground only), every other
  pattern draws blue marks on yellow, and `none` shows no fill.
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
  with its label (`integer`, `decimal2`, `thousands`, `thousands2`,
  `scientific`, `fraction`, `time`, `elapsedTime`, `text`, the grouped,
  red-negative, percent and money variants with `₺`, `$` first and `€`). A
  date in a format that shows no date (all but `time` and `elapsedTime`)
  shows the serial 46319 formatted by that format, not a date, so it looks
  different in each: `percent` shows `4631900%` and `scientific`
  `4,63E+04`, for example. That is expected.

### `m2_columns_rows`

Two sheets, `Layout` and `Defaults`.

- `Layout` row 1: the column widths are 5, 12, 40 and 255 characters (the
  last is as wide as Excel allows); column E is hidden (the header jumps from
  D to F); columns F, G and H carry an outline bar above the headings
  (F level 1, G and H level 2).
- Row 2 is 30 points tall, row 3 only 5 points. Row 4 is hidden, with no
  outline bar, and rows 5 to 7 are hidden too, so the row numbers jump from
  3 to 8.
- Rows 5 to 7 are hidden detail rows: rows 5 and 6 at outline level 2, row 7
  at level 1. Row 8, `total (collapsed)`, shows a plus sign. Expand it and
  record what Excel shows: rows 5 and 6 are stored hidden at level 2 and
  row 7 is not marked collapsed, so the inner group may open with the
  outer one or stay closed behind its own plus sign at row 7.
- `Defaults`: the default row height is 18 points and the default column
  width 11 characters, on every row and column of the sheet.

### `m2_style_precedence`

One sheet, `Precedence`, with a money column B (`€`) and a date column C
(`yyyy-mm-dd`) set on the columns.

- Row 1, `Item`, `Amount`, `Date`, is bold in all three cells.
- Rows 2 and 3: B shows `1.200,50 €`-style money (`€` with two decimals) and
  C shows `2026-10-24`.
- Row 4, `Date in money`: B holds a date, so it shows the serial 46319 in
  the money format (`46.319,00 €`), and C shows `2026-10-24`.
- Row 5, `Total`: a thin top border runs across all of A5:C5. C5 holds no
  value; it is an empty cell written only to carry the row's border. B5
  shows `1.245,75 €` in italic (the cell style adds to the row style and the
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
  sheet. There must be no repair prompt. Excel's Name Manager (Formulas >
  Name Manager) does not list hidden names, so it should show no name for
  it; a working filter is what shows the name was read. Record anything
  the Name Manager does list.
- `Plain` has no filter and no merges.

### `m2_formula_xstring`

Two sheets, `Probe` and `_x0041_`. On `Probe`, A1 holds the formula
`="_x0041_"` and A2 the text `_x0041_`.

- A2 must read `_x0041_`, as typed.
- A1 must read `_x0041_`, and the formula bar `="_x0041_"`. The file stores
  the formula as `"_x005F_x0041_"`, escaped like cell text, because Excel
  decodes `_xHHHH_` inside `<f>` (decision 0005). `A` there is a writer bug.
- The second tab reads `_x0041_`, as typed. Row 1 (`Key`, `Value`) carries
  the filter dropdown arrows, and filtering rows 2 and 3 works. Its hidden
  `_xlnm._FilterDatabase` name stores `'_x005F_x0041_'!$A$1:$B$3`, escaped
  like the formula. The filter must work, there must be no repair prompt,
  and the Name Manager must show no name with a broken (`#REF!`) reference;
  the hidden name itself is not listed there. Save a copy and open its
  `xl/workbook.xml`: the name must still point at the sheet `_x0041_`, and
  the copy must have no `xl/externalLinks/` part.

### Open question

Whether Excel treats a sheet named with the Kelvin sign (U+212A, which looks
like K) as equal to one named with the Latin letter K (U+004B). The writer's
duplicate check maps the Turkish `İ` and `ı` and the German `ß` before it
compares upper case, and at M2 did not fold the Kelvin sign.

Answered in the M2 check on 2026-10-25, by hand in Excel for the web: in a
workbook with a sheet named `K`, renaming another sheet to the Kelvin sign
was refused because the name is already in use. Excel treats the two as
equal, so `sheetNameKey` in `lib/src/xlsx/sheet_name.dart` now maps the
Kelvin sign to K (see "Open issues", closed by fbaa999).

## Open issues

Problems a check found that the owner deferred. Each names the milestone that
must close it. A closed issue stays here, marked closed, with the commit that
closed it.

### Sub-second times show the wrong minute (open, M5)

Found in the M1 check on 2026-10-24, `m1_dates` D1. The owner accepted M1 with
this issue open.

`dateTimeSerial` in `lib/src/xlsx/date_serial.dart` puts the milliseconds and
microseconds of a `DateTime` into the serial's fraction. D1 stores
`46319.999999988424`, which is 23:59:59.999 on 24.10.2026. Excel keeps that
value, since `=D1<DATE(2026,10,25)` gives `TRUE`, but it rounds the value to
the second when it shows it. So D1 never shows `23:59`. Excel for the web
showed `24.10.2026 00:00` with Turkish regional settings and `10/25/2026 0:00`
with US ones, and `=DAY(D1)` gave 24 and 25 on the same file. Any time less
than half a second before a full minute probably shows the next minute. Only
near midnight does the date change too.

Options, to be decided at M5 before release:

- Truncate a `DateTime` to whole seconds before computing its serial. Excel
  then shows the expected minute and day. The sub-second part is lost, but
  Excel cannot show it anyway.
- Keep the precision and add a warning for a `DateTime` with a sub-second
  part.

Either way the fix changes the M1 date fixture and its expected value in
`test/fixtures/m1_fixtures.dart`, starts with a failing regression test, and
adds a line to "Rules the writer enforces" in `docs/xlsx-writer.md`.

### Some document properties not checked in Excel (open, M3)

Found in the M1 check on 2026-10-24, `m1_properties`. Excel for the web shows
no document properties. GridCraft, which is not Excel, showed Title,
Subject, Author, Company, Keywords and Description as expected. Category,
Last modified by and the created and modified times are not checked in Excel.
M3 adds the rest of the document properties, so its Excel check covers all of
them in desktop Excel.

### Excel decodes `_xHHHH_` in formulas (closed, fbaa999)

Found in the M2 check on 2026-10-25, `m2_formula_xstring`. The owner accepted
M2 with this issue open; it needed a ruling before the fix.

Closed by fbaa999: decision 0005 supersedes R10, and `escapeFormulaText`
escapes `_x` as `_x005F_x` in formulas and defined names, like cell text.
The account below is what the M2 check found before the fix.

`Probe!A1` stores `<f>"_x0041_"</f>`, unescaped, because `escapeFormulaText`
in `lib/src/xml/xml_escape.dart` does XML escaping only (ruling R10 in
`docs/xlsx-writer.md`, the auto filter row). Excel for the web shows `A` in
A1 and `="A"` in the formula bar, so Excel decodes `_xHHHH_` inside `<f>`,
unlike LibreOffice. R10's premise does not hold for Excel: a formula that
contains `_xHHHH_` text changes meaning.

Excel decodes defined names too. The `_x0041_` sheet's hidden
`_xlnm._FilterDatabase` name stores `'_x0041_'!$A$1:$B$3` unescaped. There
was no repair prompt, the filter works and the Name Manager lists nothing,
because the filter's range is also in the sheet's `<autoFilter ref>`. But
when the owner saved a copy from Excel for the web, the name came back as
`[1]A!$A$1:$B$3`, with a new `xl/externalLinks/externalLink1.xml` pointing
at an external workbook `A`: Excel read the name as a sheet `A`, found none,
and turned the reference into a link to another file. The owner did not
touch the name, so the damage happens on load.

The same copy shows what Excel writes itself. After the owner typed
`="_x0041_"` into `Probe!A1` by hand (it then showed `_x0041_`), Excel saved
`<f>"_x005F_x0041_"</f>` with the cached value `_x005F_x0041_`. Excel
escapes `_x` in `<f>` as `_x005F_x`, exactly as in cell text, and the sheet
name as `_x005f_x0041_`.

So R10 is wrong for Excel, for formulas and defined names alike: both must
escape `_x` as `_x005F_x`, like cell text and sheet names. The ruling must
still confirm this and check LibreOffice, which CI showed does not decode
`<f>` and would then show `_x005F_x0041_`. The fix changes
`m2_formula_xstring` and its expected values in
`test/fixtures/m2_fixtures.dart`, starts with a failing regression test, and
updates R10's row in `docs/xlsx-writer.md`.

### Kelvin sign and K clash as sheet names (closed, fbaa999)

Found in the M2 check on 2026-10-25, answering the "Open question" above.
Closed by fbaa999, which maps the Kelvin sign to K in `sheetNameKey`. The
account below is what the M2 check found before the fix.
Excel refuses a sheet named with the Kelvin sign (U+212A) when a sheet `K`
exists. `sheetNameKey` in `lib/src/xlsx/sheet_name.dart` does not fold the
Kelvin sign, so the writer can produce two sheet names that Excel treats as
the same. What Excel does when it opens such a file (repair or refusal) is
not checked. The fix folds the Kelvin sign in `sheetNameKey`, starts with a
failing regression test, and corrects its doc comment, which calls the case
too rare to map.

### Some M2 settings not checked in desktop Excel (open, M3)

Found in the M2 check on 2026-10-25. Excel for the web does not show these,
although each is written as the checklist expects:

- `m2_styles`: the diagonal borders (rows 47 and 48), the row growing to fit
  `wrap text` (row 62 has no `ht`, so Excel sizes it), `reading order RTL`
  (row 67 stays left-aligned), and `locked false` and `hidden true` (the
  Protection tab was not reached).
- `m2_views`: the `View` sheet's 85 % zoom (stored `zoomScale="85"`; the web
  stays at 100 %) and the `Split` sheet's split (stored
  `<pane xSplit="2400" ySplit="1200"/>`; Excel for the web has no split).

M3's Excel check covers them in desktop Excel, with the document properties.

## Results

| Date | Excel version and platform | Fixture | Result | Notes |
|---|---|---|---|---|
| 2026-10-24 | Microsoft 365, Excel for the web, build 16.0.20613.42304, Chrome on macOS | `m1_values` | ok | No repair prompt. All values as expected with Turkish formats, L2's formula bar included. |
| 2026-10-24 | Microsoft 365, Excel for the web, build 16.0.20613.42304, Chrome on macOS | `m1_dirty_text` | ok | No repair prompt. `LEN` gives 32767, 32766 and 10. A10 `_x0041_` and A11 `a_x00e9_b` show literally. |
| 2026-10-24 | Microsoft 365, Excel for the web, build 16.0.20613.42304, Chrome on macOS | `m1_sheets` | ok | No repair prompt. Tab order, active sheet `şube (2)` and every A1 as expected. The last tab reads `_x0041_` literally, so R22 holds in Excel. |
| 2026-10-24 | Microsoft 365, Excel for the web, build 16.0.20613.42304, Chrome on macOS | `m1_formulas` | ok | No repair prompt. A1:D1 values and formulas as expected. |
| 2026-10-24 | Microsoft 365, Excel for the web, build 16.0.20613.42304, Chrome on macOS | `m1_empty` | ok | No repair prompt. All four sheets as expected; `ISBLANK` gives `FALSE` and `LEN` gives 0 on `EmptyString!A1`. |
| 2026-10-24 | Microsoft 365, Excel for the web, build 16.0.20613.42304, Chrome on macOS | `m1_properties` | ok (kısmi) | No repair prompt, A1 as expected. Excel for the web shows no document properties. GridCraft (not Excel) showed Title, Subject, Author, Company, Keywords and Description as expected. Category, Last modified by and the two dates are not checked (see "Open issues", M3). |
| 2026-10-24 | Microsoft 365, Excel for the web, build 16.0.20613.42304, Chrome on macOS | `m1_dates` | sorun | No repair prompt. A1, B1, C1, E1 and F1 as expected. D1 (stored `46319.999999988424`, 23:59:59.999) never shows 23:59. With Turkish regional settings it shows `24.10.2026 00:00` and `=DAY(D1)` gives 24. With US regional settings, same file, it showed `10/25/2026 0:00` and `=DAY(D1)` gave 25. In both, the formula bar showed 24.10 at 00:00 and `=D1<DATE(2026,10,25)` gave `TRUE`. The stored value is right; Excel rounds it to the second for display (see "Open issues", M5). |
| 2026-10-25 | Microsoft 365, Excel for the web, build not recorded, Chrome on macOS | `m2_styles` | ok (kısmi) | No repair prompt. Fonts, the pattern fills, both gradients, the border styles (`thin` and `hair` checked at 200 %), alignments and every number format as labelled. `font theme 4 tint 0.4` shows a light blue, so Excel falls back to its Office theme. Diagonal borders, the `wrap text` row height, `reading order RTL` and the Protection settings are not shown in Excel for the web (see "Open issues", M3). |
| 2026-10-25 | Microsoft 365, Excel for the web, build not recorded, Chrome on macOS | `m2_columns_rows` | ok | No repair prompt. Widths 5, 12, 40 and 255, column E hidden, column outline F (level 1) and G:H (level 2), rows 2 and 3 at 30 and 5 points, rows 4 to 7 hidden. Expanding row 8 opened rows 5, 6 and 7 together; the inner group did not stay collapsed. Row 4 stays hidden. `Defaults` rows and columns are larger than the default. |
| 2026-10-25 | Microsoft 365, Excel for the web, build not recorded, Chrome on macOS | `m2_style_precedence` | ok | No repair prompt. Row 1 bold, B money with `€`, C `2026-10-24`, B4 `46.319,00 €`. The top border runs across A5:C5, B5 included, and B5 shows `1.245,75 €` in italic. |
| 2026-10-25 | Microsoft 365, Excel for the web, build not recorded, Chrome on macOS | `m2_views` | ok (kısmi) | No repair prompt. Opens on `View`, only that tab selected (no `[Group]`), tab red, no gridlines or headings, B1's `0` hidden. `Frozen`, `RTL` and `Outline` (button at row 1) as expected. Unhide lists `Hidden` only. The 85 % zoom and the `Split` panes are not shown in Excel for the web (see "Open issues", M3). |
| 2026-10-25 | Microsoft 365, Excel for the web, build not recorded, Chrome on macOS | `m2_merges_filter` | ok | No repair prompt. A1:D1 and B3:C4 merged, the title bold and centred. Filtering `Qty` works ("11 of 14 records found"). Name Manager lists nothing. `Plain` has no filter and no merges. |
| 2026-10-25 | Microsoft 365, Excel for the web, build not recorded, Chrome on macOS | `m2_formula_xstring` | sorun | No repair prompt. A2 and the second tab read `_x0041_`. A1 shows `A`, formula bar `="A"`: Excel decodes `_xHHHH_` in `<f>` (see "Open issues", M3). The `_x0041_` sheet's filter works and Name Manager lists nothing, but a copy saved from Excel turned the hidden filter name into an external link `[1]A!$A$1:$B$3`, so Excel decodes defined names too. |
