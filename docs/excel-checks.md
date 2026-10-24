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
- D1 is 23:59:59.999 on 24.10.2026. It shows `24.10.2026 23:59`, on the same
  day; the built-in date-time format has no seconds. With a custom format
  that shows seconds it shows `23:59:59`. If Excel shows 25.10.2026 00:00
  instead, record it: Excel rounded the milliseconds up.
- E1 `1850-06-15T00:00:00.000`, left-aligned text: a date before 1900 has
  no Excel serial.
- F1 `46.319,00`: a date written with the number format `#,##0.00`, so it
  shows the serial.

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
