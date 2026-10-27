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

## M3

Open every M3 fixture in **desktop Excel** (Windows or macOS) with Turkish
regional settings. Excel for the web does not show print settings, protection
details or document properties, which is why M3 is checked on the desktop. As
for M1 and M2, first check that each file opens without a repair prompt.

### `m3_names`

Two sheets, `Data` and `O'Brien`.

- Formulas > Name Manager lists `TaxRate` (`0.18`, workbook scope) and `Local`
  (`=Data!$B$2`, scope `Data`). It also lists the two print names of
  `O'Brien`, `Print_Area` and `Print_Titles`, scoped to that sheet.
- `Data!A1` shows `18` (the formula `TaxRate*100`); the formula bar shows
  `=TaxRate*100`. B1 is `Tax percent`, A2 `Local`, B2 `5`.
- `O'Brien`, Page Layout > Print Titles (or Page Setup > Sheet): the print
  area is `$A$1:$B$4,$D$1:$D$3`, rows to repeat `$1:$1`, columns to repeat
  `$A:$A`. Print Preview prints the two ranges on separate pages, each with
  the repeated row and column.

### `m3_hyperlinks`

Two sheets, `Links` and `O'Brien`. Click each link in `Links` (Ctrl-click on
macOS if single clicks only select).

- A1 `https://example.com/a b` opens `https://example.com/a%20b` in the
  browser.
- B1 `sales@example.com` opens a new e-mail to that address with the subject
  `Q&A ç`; hovering shows the tooltip `Write to sales`.
- C1 `Bold link` goes to the cell `C3` on `O'Brien` (through the workbook
  name `Target`); it is bold, blue and underlined, because column C is bold.
- D1 `Red link` opens `https://example.com/red`; it is red and underlined.
- A2 `O'Brien` goes to `O'Brien!B2`; B2 `Target` goes to `O'Brien!C3`.
- The links without a style of their own (A1, B1, A2 and B2) are blue and
  underlined, the theme's hyperlink color (the rule "A hyperlink cell's font"
  in `docs/xlsx-writer.md`).

### `m3_validation`

One sheet, `Form`. Select each input cell in column B (all are empty), read
the prompt, open the drop-down if any, and type a bad value to read the
alert. Type the values: pasting into a cell replaces its validation with the
source's, so a pasted bad value is accepted without an alert and Data
Validation then shows `Any value`.

- B2: a drop-down of `Fish`, `say "hi"` and `R&D`, three items, the quotes and
  the ampersand shown as typed. Any other text is refused (stop alert).
- B3: a drop-down of `red`, `green`, `blue` (the range `D2:D4`).
- B4: whole number 1 to 10. Selecting it shows the prompt `Count`, `Enter a
  whole number from 1 to 10.`; `11` is refused with `Not allowed`, `Use 1 to
  10.`
- B5: decimal above 0; `-1` is refused with Excel's default alert.
- B6: date after 24.10.2026; `24.10.2026` is refused, `25.10.2026` accepted.
- B7: time before 12:00; `13:00` is refused, `11:30` accepted.
- B8: text of at most 5 characters; `abcdef` is refused.
- B9: custom `ISEVEN(B9)`; `3` shows the alert `Odd`, `The number is not
  even.` with Yes, No and Cancel (a warning, which lets the value stay if you
  click Yes); `4` is accepted without an alert.
- B10: any value is accepted, but selecting it shows the prompt `Note`,
  `Anything goes here.`

### `m3_conditional`

One sheet, `Scores`, 20 data rows under the header. Each column has its own
rule; check the colors against the column's numbers.

- A: names containing `an` (`Ana`, `Dana`, `Hanna`, `Rana`) in dark red text on
  pink.
- B (Maths): values of 70 or more in dark green on light green; values below
  40 are bold (the second rule on `B2:C21`), so a value can be both.
- C (Art): values above the column average green; below 40 bold.
- D (Music): the three highest values red.
- E (Sport): values at or below the average green.
- F (Team): `Red`, `Blue` and `Green` (all repeated) red; `Gold`, which occurs
  once, plain.
- G (Hours): a three-color scale, red for the lowest, yellow at the middle
  and green for the highest.
- H (Progress): blue gradient data bars, longer for larger values.
- I (Rating): three arrows (up, sideways, down) by value.

### `m3_conditional_x14`

One sheet, `Bars`, the values -50 to 50 in steps of 5 in all five columns.
These need Excel 2010 or later; check that none shows a repair prompt.

- A `Bar`: blue bars to the right of a middle axis for positive values, red
  bars to its left for negative ones, drawn from the middle of the cell, with
  a black dashed axis line between them. The rule's Negative Value and Axis
  settings show the red negative fill and a black axis at the cell midpoint.
- B `Solid`: solid green bars (no gradient) with a border; bars for negative
  values are filled too, in Excel's default red, with the green border, to
  the left of a black axis where zero falls (the cell's middle, as the
  values run from -50 to 50). The rule's Negative Value and Axis settings
  show the red fill and the black axis.
- C `Stars`, D `Triangles` and E `Boxes`: three stars, three triangles and
  five boxes by value. The default thresholds of 33 % and 67 % fall at -17
  and 17: -50 to -20 show an empty star and a red down triangle, -15 to 15 a
  half star and a yellow dash, 20 to 50 a full star and a green up
  triangle. The boxes fill from none (-50 to -35) to all four quarters (30
  to 50). Excel for the web and LibreOffice may not show these.

In Excel for Mac on 2026-10-26 the axis line did not show and B's negative
bars were green outlines with no fill: the file stored neither color, and
Excel showed both as white (see "Open issues", M4). The file now stores
Excel's defaults; the M4 Excel check is to confirm the look above.

### `m3_page_setup`

Two sheets, `Landscape` and `Scaled`. Check File > Print (Print Preview) and
Page Layout > Page Setup (File > Page Setup on macOS) for each. Excel for
Mac's Page Setup has no paper size; its Print dialog shows A4, which is also
what it shows for a sheet that stores none, so A4 is not told apart there.

- `Landscape`: landscape orientation, A4 paper, fit to 1 page wide (and
  automatic tall), page centered horizontally, gridlines printed.
- `Scaled`: 85 % scale, margins left and right 0.25 in, top and bottom 0.5 in,
  header and footer margins 0.2 in, first page number 3 (Page Setup > Page
  shows `3`), page order over, then down (Page Setup > Sheet).

### `m3_header_footer`

One sheet, `Report`, 60 rows. At the default scale it prints on two pages.
Page Setup > Header/Footer shows `Different odd and even pages` and
`Different first page` both ticked.

- Print Preview page 1 (the first page): header `Cover`, no footer.
- Page 2 (even): no header, footer `Report`, the sheet name.
- The odd-page texts do not print on pages 1 and 2. Primary check: Custom
  Header shows `R&&D` in the left section (the stored code, with the
  ampersand doubled; the printed page shows `R&D`, so this is not a bug) and
  the date code in the right section (`&[Date]` in Excel for Mac), and Custom
  Footer (odd pages) shows `Page &[Page] of &[Pages]`. Excel for Mac's
  Custom Header and Custom Footer have no tabs for the first, odd and even
  pages: while `Different first page` is ticked they show the first page's
  texts (`Cover` in the centre, an empty footer). Untick it, read them, then
  Cancel. The Header/Footer tab's own preview shows the odd header as it
  prints, `R&D` left and the date right.
- To see the odd texts printed, in Page Setup > Page set Adjust to (not Fit
  to) and raise it until Print Preview shows 3 pages: about 200 % on A4,
  where the pages hold rows 1 to 26, 27 to 52 and 53 to 60. Page 3 then
  shows the odd header (`R&D` left, the date right) and `Page 3 of 3`;
  discard the change afterwards.

### `m3_protection`

One sheet, `Locked`, with `Locked label` in A1, `input` in B2 and a formula in
C3 that shows `2`.

- Review shows `Unprotect Sheet` and `Protect Workbook` active.
- Only B2 can be edited. Typing in A1 or C3 (or any other cell) gives the
  "protected cell" message.
- Selecting C3 shows `2` in the cell, and the formula bar is empty (the
  formula `1+1` is hidden).
- Home > Format > Column Width works, because the sheet allows formatting
  columns; Row Height is refused.
- Review > Unprotect Sheet asks for a password; `password` unprotects it.
- Right-clicking the tab shows Insert, Delete, Rename and Move or Copy greyed
  out, and the + button adds no sheet, until Review > Protect Workbook is
  switched off with the password `test`.

### `m3_properties`

One sheet, `Info`, with `Properties` and `set`. Check File > Info > Properties
> Advanced Properties (Windows) or File > Properties (macOS), on the Summary,
Statistics and Custom tabs.

- Title `Quarterly report`, Subject `Accounts`, Author `Ahmet Urel`, Manager
  `Ayse Yilmaz`, Company `Jetronik`, Category `Finance`, Keywords
  `report; accounts`, Comments `Fixture for the document properties`.
- Last saved by `Jet Office`. Status `Final` is checked under File > Info
  (it may not appear on the Advanced Properties tabs). Excel for Mac shows
  no Status: none of its File > Properties tabs (General, Summary,
  Statistics, Content, Custom) has the field (see "Open issues", M5).
- Created 24.10.2026 09:30 UTC and modified 25.10.2026 18:45:10 UTC, in
  local time (12:30 and 21:45:10 in Türkiye). Excel for Mac's Statistics
  tab shows the file's disk time as "Modified" instead, as for
  `m1_properties`.
- Custom: `Project` (text) `Atlas`, `Count` (number) `3`, `Ratio` (number)
  `0,5`, `Final` (yes or no) `Yes`, `Due` (date) 24.10.2026.

### Desktop re-checks of M1 and M2

The two open issues "Some document properties not checked in Excel" and "Some
M2 settings not checked in desktop Excel" close with these checks. When the
owner records them in "Results", mark both issues closed, with the date.

`m1_properties` (File > Info > Properties > Advanced Properties):

- Category `Reports`, Last modified by `jet_office`.
- Created 24.10.2026 08:30 UTC and modified 24.10.2026 09:45:30 UTC, in local
  time (11:30 and 12:45 in Türkiye). Excel for Mac (File > Properties >
  Statistics) shows the file's own disk time as "Modified" instead; checked
  on 2026-10-26 (see the closed open issue).

`m2_styles`:

- Rows 47 and 48: the diagonal borders, one going up and one going down.
- Row 62, `wrap text`: the row grows to fit the wrapped text (the file stores
  no height for it).
- Row 67, `reading order RTL`: the text reads right to left. Excel for Mac
  has no text direction setting under Format Cells > Alignment and shows the
  cell left-aligned, so this needs Excel for Windows (see "Open issues",
  M5).
- `locked false` and `hidden true`: Format Cells > Protection shows Locked
  cleared for the first and Hidden ticked for the second.

`m2_views`:

- `View`: the zoom is 85 % (the status bar's zoom slider).
- `Split`: two panes with a movable divider, about 120 points from the left
  and 60 from the top (View > Split is highlighted).

## M4

Open every M4 fixture in **desktop Excel** (the owner has Excel for Mac
16.114.1) with Turkish regional settings, and in Excel for the web where it
shows the object. As before, first check that each file opens without the
repair prompt. M4 also changed an M3 fixture, `m3_conditional`, so its column
H is re-checked below.

### `m4_rich_text`

One sheet, `Rich`, one cell per row in column A.

- A1 `Total: 42`: `Total: ` bold, `42` plain.
- A2 `Red italic and underlined`: `Red italic` italic and red, ` and
  underlined` underlined (single).
- A3 `x2`: the `2` is a superscript, so it reads x squared.
- A4 `Bold in Arial 14`: the cell is Arial 14, and the bold run is Arial 14
  bold too, the same size and face as ` in Arial 14` (Decision 3 of the M4
  plan). ` in Arial 14` is Arial 14, not Calibri 11: it is as large as
  `Bold` and larger than A5. Click into the cell: the formula bar shows the
  runs in Arial.
- A5 and A6 `Same text` look alike, in the same plain font.

### `m4_notes`

Three sheets, `Notes`, `Right` and `Bottom`. Notes are called comments in
older Excel; Excel for Mac 16.114.1 may call them notes or comments, so look
for the red triangle in the cell's corner.

- `Notes`: hovering B2 shows `Check this` with the author `Ahmet`; hovering C3
  shows a bold `Ahmet:` line, then `The total is checked.`; D4's note
  `Always shown` is shown without hovering, with the author `Ayse Yilmaz`.
  Review > Notes (or Comments) lists three notes.
- `Right`: A1 and B1 hold text; the note of `XFD1` (the last column) opens
  inside the window when you go to `XFD1` and hover it, not outside the sheet.
- `Bottom`: the same for the note of `A1048576` (the last row).
- No repair prompt on any of them.

### `m4_images`

Two sheets, `Pictures` and `Again`. Set the zoom to 100 %. The pictures are
tiny test images (a red-green gradient).

- `Pictures`: the PNG at B2 is 4 × 2 pixels (Format Picture > Size shows
  its size; at 100 % zoom it is a few screen pixels); the JPEG at
  E2 is 60 pixels wide, its height 100 pixels, aspect kept.
- The two-cell picture fills `B6:D10` exactly. Widen column C: it does not
  resize, but it moves when a column to its left is widened (`move`, the
  property "Move but don't size with cells").
- Right-click the picture over `B6:D10` > View Alt Text: it reads `The PNG
  over B6:D10`.
- `Again` shows the same PNG at A1, 4 × 2 pixels.

### `m4_tables`

Two sheets, `Sales` and `Plain`. Click inside each table; Table Design (or
Table) appears.

- `Sales` has the table `Sales` over A1:C5: style Medium 2 with banded rows, a
  header row `Region`, `Amount`, `Note` (C1 filled in by the writer) and a
  totals row, A5 `Total`, B5 `245,5`, C5 empty. Select B5: the formula bar
  shows `=SUBTOTAL(109,B2:B4)`, and Excel accepts it without repair. The
  totals drop-down of B5 shows Sum (Decision 2 of the M4 plan: an A1 range,
  not a structured reference).
- Beside it, `Costs` over E1:F3: style Light 9, header `Item`, `Cost`. The
  table has banded columns and keeps the default banded rows, so Table
  Design shows both Banded Rows and Banded Columns ticked.
- The filter buttons of both headers work: filter `Region` to `North`.
- Inserting a row inside `Sales` (right-click a data row > Insert > Table
  Rows Above) extends the table, and the totals formula follows.
- `Plain` has the table `Numbers` over A1:B2 with no header row and no style:
  the cells hold 1, 2 and 3, 4, and Table Design shows Header Row off. Its
  stored column names, `X` and `Y`, show when Header Row is turned on.
- Formulas > Name Manager lists `Sales`, `Costs` and `Numbers`.

### `m4_objects`

Two sheets, `All` and `More`. No repair prompt.

- `All`: A1 `Site A` and B1 `Site B` are links (to `https://example.com/a` and
  `/b`); C1 `Noted` has a note `Check C1` by `Ahmet`; the PNG shows at G2;
  the tables `Stock` (A3:B5) and `Prices` (D3:E5) show with their headers.
  Every one of these objects shows at the same time.
- `More`: A1 has a note `The second sheet`.

### Re-check of the data bars (an M4 open issue)

The M3 check found that Excel draws no negative fill and no axis for a data
bar that stores neither color (see "Open issues", M4). The writer now stores
Excel's defaults (`FFFF0000` for the negative fill, `FF000000` for the axis).
Open `m3_conditional_x14` and `m3_conditional` again:

- `m3_conditional_x14`, B `Solid`: the negative bars are red (filled, with
  the green border), left of a black axis.
- `m3_conditional_x14`, A `Bar` and B `Solid`: both columns show an axis line
  in the middle of the cell.
- `m3_conditional`, H `Progress`: it has a data bar with no colors of its
  own, which M4 changed (it now has an `x14:dataBar` with the default
  negative fill and axis). Look at the rule: Home > Conditional Formatting > Manage Rules > Edit Rule >
  Negative Value and Axis shows a red fill and a black axis, and the blue
  gradient bars look as before.
- A question for the owner: B `Solid` has a border and stores no
  `x14:negativeBorderColor`. Does Excel draw the negative bars' border red
  (its default) or not? Record what the Edit Formatting Rule dialog and the
  bars show. Answered on 2026-10-27: green, the positive border color (see
  "Results").

When the owner records it, mark "Data bars draw no negative fill or axis by
default" closed, with the date.

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

### Some document properties not checked in Excel (closed, 2026-10-26)

Closed on 2026-10-26 by the desktop check of `m1_properties` in Excel for
Mac 16.114.1 (see "Results"). File > Properties showed every core and app
field as expected: Summary had Title, Subject, Author, Company, Category
`Reports`, Keywords and Comments, and Statistics had Created 24.10.2026
11:30 (08:30 UTC) and Last saved by `jet_office`. Statistics' "Modified"
showed the time the file was written to disk (26.10.2026 04:36), not the
stored `dcterms:modified` (09:45:30 UTC): Excel for Mac reads that field
from the file system, so the stored value is checked by the tests, not by
Excel.

Found in the M1 check on 2026-10-24, `m1_properties`. Excel for the web shows
no document properties. GridCraft, which is not Excel, showed Title,
Subject, Author, Company, Keywords and Description as expected. Category,
Last modified by and the created and modified times are not checked in Excel.
M3 adds the rest of the document properties, so its Excel check covers all of
them in desktop Excel.

The M3 section's "Desktop re-checks of M1 and M2" covers `m1_properties`.

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

### Some M2 settings not checked in desktop Excel (closed, 2026-10-26)

Closed on 2026-10-26 by the desktop re-checks of `m2_styles` and `m2_views`
in Excel for Mac 16.114.1 (see "Results"). The diagonal borders, the row
grown to fit `wrap text`, the Protection tab of `locked false` and
`hidden true`, the 85 % zoom and the `Split` panes all show as expected.
`reading order RTL` cannot be checked there, as Excel for Mac has no text
direction setting; it moves to "Reading order and Status not checked in
Excel" below.

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

The M3 section's "Desktop re-checks of M1 and M2" covers `m2_styles` and
`m2_views`.

### Data bars draw no negative fill or axis by default (closed, 2026-10-27)

Closed on 2026-10-27 by the M4 re-check of `m3_conditional_x14` and
`m3_conditional` in Excel for Mac 16.114.1 (see "Results"). A and B show a
black dashed axis where zero falls, B's negative bars are filled red, and the
Edit Formatting Rule dialogs of B and of `m3_conditional`'s column H show a
red negative fill and a black axis. B's negative border is green, the
positive border color: the file stores no `x14:negativeBorderColor`, and
`negativeBarBorderColorSameAsPositive` defaults to true.

Found in the M3 check on 2026-10-26, `m3_conditional_x14`, in Excel for Mac
16.114.1. The owner deferred the fix to M4.

`_writeDataBar` in `lib/src/xlsx/conditional_format_x14.dart` writes
`x14:negativeFillColor` and `x14:axisColor` only when the rule has them. B
`Solid` has neither, and A `Bar` has no axis color. The `XlsxDataBar`
dartdoc says `null` means "Excel's" color, but Excel does not fall back to
its defaults: B's Edit Formatting Rule dialog shows the negative fill and
the axis color as white. So B's negative bars are green outlines with no
fill, and neither column shows an axis line, even at 200 %. A's negative
bars are red, because its rule sets `negativeFillColor`.

Excel writes both colors on every data bar it saves, its defaults being
`FFFF0000` for the negative fill and `FF000000` for the axis. The fix
writes those defaults when the rule has no color of its own (or changes the
dartdoc), starts with a failing regression test, and updates
`m3_conditional_x14`'s checklist entry if the expected look changes.

Fixed in 43a8471; open, awaiting the owner's M4 Excel check. M4 also changed
`m3_conditional`, whose column H data bar had no colors and now gets the same
defaults; the M4 check re-checks it.

### Reading order and Status not checked in Excel (open, M5)

Found in the M3 check on 2026-10-26, in Excel for Mac 16.114.1, which shows
neither:

- `m2_styles` row 67, `reading order RTL` (stored
  `<alignment readingOrder="2"/>`): Format Cells > Alignment has no text
  direction setting, and the cell shows left-aligned.
- `m3_properties` Status `Final` (stored `cp:contentStatus`): no tab of
  File > Properties has a Status field.

Both need Excel for Windows (Format Cells > Alignment > Text direction, and
File > Info). The owner chose to check them before release, at M5.

### Plain rich text runs lose the cell's font (closed, 9071bc3)

Closed by 420e543 (merged at 9071bc3) and the owner's re-check on
2026-10-27 in Excel for Mac 16.114.1 (see "Results"): A4's ` in Arial 14`
shows in Arial 14, the same size as `Bold`. The account below is what the
M4 check found before the fix.

Found in the M4 check on 2026-10-27, `m4_rich_text` A4, in Excel for Mac
16.114.1.

A4 is styled Arial 14 and holds a bold run `Bold` and a plain run
` in Arial 14`. The writer merges the cell's font into a run that has a font
of its own (Decision 3 of the M4 plan), so `Bold` is stored with
`<rPr><b/><sz val="14"/><rFont val="Arial"/></rPr>` and shows as Arial 14
bold. The plain run is stored with no `rPr`, and Excel draws a run without
`rPr` in the workbook's default font (Calibri 11, font 0), not in the cell's
font: ` in Arial 14` shows visibly smaller than `Bold`, as small as
A5's Calibri 11, and with the cursor in it, in edit mode, Home showed
Calibri 11 (a first try showed Arial 14 with Bold highlighted, which is
the bold run's font, so the ribbon did not follow the cursor then).
A1's `42` and A3's `x` have no `rPr` either, but their cells use the
default font, so nothing shows.

The fix writes an `rPr` with the cell's font for every run of a rich text
cell whose style has a font, plain runs included (or documents the
behaviour), starts with a failing regression test, and changes
`m4_rich_text` and its checklist entry if the stored runs change.

Fixed in 420e543; open, awaiting the owner's Excel re-check. A run without a
font now carries the cell's effective font, resolved, when that font is set
(` in Arial 14` is stored with `<rPr><sz val="14"/><rFont val="Arial"/></rPr>`);
in a cell without a font it still has no `rPr`, so A1, A3 and A5 are stored
as before and A5 still shares A6's string. Re-check `m4_rich_text` A4: ` in
Arial 14` is Arial 14, the same size as `Bold`.

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
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m1_properties` (desktop re-check) | ok | No repair prompt. File > Properties: Summary shows Title `Quarterly report`, Subject `Sales`, Author `Ahmet Urel`, Company `Jetronik`, Category `Reports`, Keywords `sales; q3`, Comments `A test workbook`. Statistics shows Created 24.10.2026 11:30 and Last saved by `jet_office`. "Modified" shows the file's disk time (26.10.2026 04:36), not the stored 09:45:30 UTC; Excel for Mac reads it from the file system. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_names` | ok | No repair prompt. Name Manager lists `Local` (`=Data!$B$2`, `Data`), `Print_Area` and `Print_Titles` (`O'Brien`) and `TaxRate` (`=0,18`, workbook). `Data!A1` shows `18`, formula bar `=TaxRate*100`; `Data` prints on one page. `O'Brien`'s Print Titles fields as expected; Print Preview shows 2 pages, row 1 and column A repeated on each. A first look showed `Data` on 2 pages with `O'Brien`'s print area; that was a copy left open in Excel from an earlier pass, and a clean reopen showed 1 page. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_hyperlinks` | ok | No repair prompt. All six items as expected, the `Write to sales` tooltip included. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_validation` | ok | No repair prompt. B2 to B10 as expected. In a first try B6 to B8 accepted bad values: the values had been pasted, which removed the cells' validation (Data Validation showed `Any value`). After a clean reopen B6 showed Date greater than 24.10.2026, B7 Time less than 12:00, B8 Text length at most 5, and typed bad values were refused. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_conditional` | ok | No repair prompt. Checked on a screenshot against the numbers: A `Ana`, `Dana`, `Hanna`, `Rana`; B 70 or more green, below 40 bold, B21's 40 plain; C above the average 47.5 green (C13's 47 plain); D 97, 94 and 87 red; E at or below 48.5 green; F all but `Gold` red; G red to yellow to green; H gradient blue bars; I arrows up for 4 and 5, sideways for 3, down for 1 and 2. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_conditional_x14` | sorun | No repair prompt. A: red bars left and blue bars right of the cell's middle, gradient, none at 0. Stars, triangles and boxes as expected at 200 % (half stars from -15 to 15). B: positive bars solid green with a border, but negative bars are green outlines with no fill, and no axis line shows in A or B: B's rule dialog shows the negative fill and axis color as white, because the file stores neither (see "Open issues", M4). |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_page_setup` | ok | No repair prompt. `Landscape`: landscape, fit to 1 page wide with tall empty, centred horizontally, gridlines. `Scaled`: portrait, 85 %, first page number 3, margins 0,25/0,5/0,2", over then down. Excel for Mac's Page Setup has no paper size and its Print dialog shows A4, as it does for a sheet that stores no paper size, so A4 is not told apart. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_header_footer` | ok | No repair prompt. Both checkboxes ticked. Print Preview: page 1 header `Cover`, no footer; page 2 footer `Report`, no header. Custom Header shows `Cover` while `Different first page` is ticked; with it unticked it shows `R&&D` left and `&[Date]` right, and Custom Footer `Page &[Page] of &[Pages]`. At about 200 % (rows 1-26, 27-52, 53-60) page 3 shows `R&D`, 26.10.2026 and `Page 3 of 3`. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_protection` | ok | No repair prompt. Review shows Unprotect Sheet and Protect Workbook; the tab shows a lock and + is greyed. Only B2 accepts input; C3 shows `2` with an empty formula bar. Format: Column Width enabled, Row Height, Rename Sheet and Move or Copy greyed. `password` unprotects the sheet and `test` the workbook. |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_properties` | ok (kısmi) | No repair prompt. Summary: all eight fields as expected. Statistics: Created 24.10.2026 12:30, Last saved by `Jet Office`; Modified shows the file's disk time (26.10.2026 04:36). Custom: `Project` Atlas (text), `Count` 3 and `Ratio` 0,5 (number), `Final` Yes (yes or no), `Due` 24.10.2026 (date). Status `Final` is not shown anywhere in Excel for Mac (see "Open issues", M5). |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m2_styles` (desktop re-check) | ok (kısmi) | No repair prompt. Rows 47 and 48 show the diagonals up and down; row 62 grows to four lines for `wrap text`; A68's Protection tab has Locked and Hidden cleared, A69's both ticked. Row 67's reading order cannot be checked: Excel for Mac has no text direction setting and shows the cell left-aligned (see "Open issues", M5). |
| 2026-10-26 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m2_views` (desktop re-check) | ok | No repair prompt. `View` opens at 85 % (status bar), without gridlines or headings, B1's `0` hidden. `Split` shows a real split, four panes, the dividers about 120 points from the left and 60 from the top. |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m4_rich_text` | sorun | No repair prompt. A1 `Total: ` bold and `42` plain; A2 `Red italic` red italic and ` and underlined` underlined; A3 `x` with a superscript `2`; A5 and A6 alike. A4: `Bold` is Arial 14 bold, but ` in Arial 14` shows in Calibri 11: it is as small as A5's Calibri 11, and Home showed Calibri 11 with the cursor in it in edit mode (a first try showed Arial 14 with Bold highlighted, so the ribbon did not follow the cursor then). A run without `rPr` takes the workbook's default font, not the cell's (see "Open issues", M5). |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m4_notes` | ok | No repair prompt. `Notes`: B2 `Check this` (status bar "commented by Ahmet"), C3 a bold `Ahmet:` line and `The total is checked.`, D4 `Always shown` shown without hovering (by `Ayse Yilmaz`); Show All Notes shows three. The notes of `XFD1` and `A1048576` open inside the window. |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m4_images` | ok | No repair prompt. Format Picture > Size: the JPEG at E2 is 0,63" × 1,04" (60 × 100 pixels), `Again`'s PNG at A1 0,04" × 0,02" (4 × 2 pixels); the PNG at B2 shows as a dot. The picture over B6:D10 fills it (2,71" × 1,1"), "Move but don't size with cells" is selected; widening C leaves its size, widening A moves it. Alt Text reads `The PNG over B6:D10`. Excel's "Original size" and Scale percentages are its own reading of the images' 72 dpi metadata (the JPEG shows 4500 % by 3750 %); the size shown is the stored one. |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m4_tables` | ok | No repair prompt. `Sales` Medium 2, banded rows, Header Row and Total Row ticked; B5 `245,5`, formula bar `=SUBTOTAL(109;B2:B4)`, its totals drop-down shows Sum (Decision 2 confirmed). `Costs` Light 9 with Banded Rows and Banded Columns ticked, as stored (the checklist said columns only; corrected). Filtering and inserting a table row worked, per the owner. `Numbers`: Header Row off, `X` and `Y` when turned on. Name Manager lists `Sales`, `Costs` and `Numbers`. |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m4_objects` | ok | No repair prompt. `All`: the links `Site A` and `Site B`, C1's note marker, the PNG at G2 and the tables `Stock` and `Prices` show together. `More`: A1 has a note. |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_conditional_x14` (M4 re-check) | ok | No repair prompt. A and B show a black dashed axis where zero falls; B's negative bars are filled red, left of it. B's Edit Formatting Rule: negative fill red, borders solid, positive and negative border green, axis color black. So Excel draws the negative border in the positive border color when no `x14:negativeBorderColor` is stored. Closes "Data bars draw no negative fill or axis by default". |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m3_conditional` (M4 re-check) | ok | No repair prompt. Column H's blue gradient bars as before; its Edit Formatting Rule shows negative fill red, borders none, axis color black. |
| 2026-10-27 | Microsoft 365, Excel for Mac 16.114.1 (26102031) | `m4_rich_text` (re-check after 420e543) | ok | No repair prompt. A4 `Bold in Arial 14`: ` in Arial 14` now shows in Arial 14, the same size as `Bold`, which stays bold; with the cursor in `Bold`, Home shows Arial 14 with Bold highlighted. A1, A2, A3, A5 and A6 as before. Closes "Plain rich text runs lose the cell's font". |
