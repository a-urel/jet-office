# Excel checks

What Excel for Mac has settled for `jet_charts_core`, and what it has not. The
axis oracle has its own page (`axis-scaling.md`).

## Office theme values

`ChartTheme.office` holds these. Excel writes none of the defaults into a file
it did not save, so each is confirmed from a chart Excel made:
`test/fixtures/owner/axis_full/chart_defaults.xlsx`, a default clustered column
chart and a default line chart with markers of one series, added through
Office.js `charts.add` (not the Insert ribbon) and saved unedited, Excel for Mac
16.114.4, `tr-TR`, 2026-11-08. "chart1" is the column chart's part, "chart2"
the line chart's; the workbook theme is Excel's default (Office, Aptos).

| Value | Status | Source |
|---|---|---|
| Accents 1 to 6, `dk`/`lt` colours | Verified | `Office Theme.thmx`, Excel for Mac 16.114.4; the workbook's `theme1.xml` has the same |
| Line width 2.25 pt | Verified | chart2 series `a:ln w="28575" cap="rnd"` |
| Marker size 5 | Verified | chart2 `c:marker`: `c:symbol` `circle`, `c:size` 5 |
| A marker on every line point (`lineMarkers` on) | Verified | chart2 `c:lineChart` `c:marker` 1 and the series' `c:marker` circle; the owner's J3 gallery check shows a circle on every point |
| Marker outline 0.75 pt of the series colour | Verified | chart2 series `c:marker` `c:spPr` `a:ln w="9525"` of the series colour |
| Gap width 219 | Verified | chart1 `c:gapWidth` 219 |
| Overlap -27 | Verified | chart1 `c:overlap` -27; `ChartSpacing.overlapPercent` |
| Font Aptos Narrow | Verified | every `a:defRPr` names `+mn-lt`, the theme's minor font, which is `Aptos Narrow` in the workbook theme |
| Title size 14 pt | Verified | title `a:defRPr sz="1400"`, both charts |
| Axis label size 9 pt | Verified | both axes' `a:defRPr sz="900"`, both charts |
| Legend and data label size 9 pt | Unconfirmed | Neither chart has a legend or data labels; recalled, no source |
| Text colour `595959` | Verified | title and axis labels `tx1` with `lumMod` 65000, `lumOff` 35000; `tx1` is `dk1`, black: 0.35 of 255 is `59`; the Office theme binds it to `dark1` with `lumMod` 0.65 and `lumOff` 0.35 |
| Line colour `D9D9D9` | Verified | gridlines, category axis line and chart border `tx1` with `lumMod` 15000, `lumOff` 85000: 0.85 of 255 is `D9`; the Office theme binds it to `dark1` with `lumMod` 0.15 and `lumOff` 0.85 |
| Grid and axis line width 0.75 pt | Verified | gridlines and category axis line `a:ln w="9525"` |
| Background `FFFFFF` | Verified | chart area `bg1`, which is `lt1`, white |
| Value gridlines on | Verified | `c:valAx` has `c:majorGridlines`; `c:catAx` has none |
| Tick length 0 (no ticks) | Verified | both axes `c:majorTickMark` and `c:minorTickMark` `none` |
| Legend at the bottom | Unconfirmed | A one-series default chart has no legend; recalled, no source |
| Spacing: padding 8, title gap 6, legend gap 6 pt | Unconfirmed | Excel lays the chart out itself (`c:layout` empty); no source |
| Spacing: legend symbol 7, legend item gap 12 pt | Unconfirmed | No source |
| A line series' legend symbol: a line with a marker in its middle | Seen | The owner's J3 gallery check (2026-11-09, `line_gap`); Excel writes no legend symbol |
| Spacing: legend line 16 pt (`legendLineSymbol`) | Estimate | Seen in the owner's gallery check, value this library's estimate from the screenshot |
| Spacing: label gap 4, minimum text gap 2 pt | Unconfirmed | No source |

What the file states that is not simply a theme value (`docs/parity.md` lists
each as a difference). The value axis line and the chart border are theme
values now (`ChartTheme.valueAxisLine`, `border`, `borderWidth`; the Office
theme has no value axis line and a 0.75 pt `D9D9D9` border), and stay listed
as what the file confirmed:

- A chart of one series shows a title (`c:autoTitleDeleted` 0, Excel's text
  "Grafik Başlığı") and no legend.
- The value axis has no line (`c:valAx` `a:ln` `a:noFill`); the category axis
  has one.
- The chart area has a 0.75 pt `D9D9D9` border.
- Bars have no outline; a marker is filled with its series colour and has a
  0.75 pt outline of it; the series line has round caps.
- Axis labels are `tickLblPos` `nextTo`.

## Excel's palette past six colours

Seen in the owner's J3 gallery check (2026-11-09, `column_eight_series`): Excel
drew series 7 and 8 as a light grey-blue and a light salmon (about `8599A9` and
`ECA28B`, measured from the owner's screenshot), where `ChartTheme.seriesColor`
drew a dark navy and a brown. The owner's Excel-saved copy of that workbook,
`~/Documents/jet_charts_oracle/gallery_saved.xlsx` (the owner's file, not in
this repository), shows what the workbook had: its chart of
`column_eight_series` keeps series 7 and 8 without `c:spPr`, has
`c:style val="2"`, and the file has no colour-style part (`colorsN.xml`). Our
reading is that Excel then fell back to the legacy colour table of `c:style`
2, which would explain the light colours; Excel states no such rule. The
owner's re-check (2026-11-09, below) showed the colour-style part does not
change it: with `colors1.xml` and `style1.xml` beside the chart, Excel still
drew series 7 and 8 light.

What Excel gives a new chart was checked directly: the owner made a new
clustered column chart in Excel from the cells of `column_eight_series`
(A1:I5) and saw series 7 and 8 dark, as the app draws them; Claude for Excel,
asked by the owner, read their fills as `0D3A4E` and `994010`, the colours
`ChartTheme.seriesColor` gives. The gallery workbook therefore writes every
series' colour, series 7 and on with the cycle's `lumMod` and `lumOff`, as
Excel writes a new chart.

Excel's default is the colour cycle of its colour-style part, verified from
`chart_defaults.xlsx`, `xl/charts/colors1.xml` (`cs:colorStyle` `meth="cycle"`
`id="10"`): accents 1 to 6, then the same six varied once per pass by
`lumMod` 60000; `lumMod` 80000 and `lumOff` 20000; `lumMod` 80000; `lumMod`
60000 and `lumOff` 40000; `lumMod` 50000; `lumMod` 70000 and `lumOff` 30000;
`lumMod` 70000; `lumMod` 50000 and `lumOff` 50000. `ChartTheme.seriesColor`
follows it: series 7 is accent 1 at `lumMod` 0.6 (`0D3A4E`), series 8 accent
2 at `lumMod` 0.6 (`994010`), series 13 accent 1 at `lumMod` 0.8 and
`lumOff` 0.2 (`1F8EC0`). Only the list of variations is from Excel's file:
that Excel's series 13 and later use the variations in that order was not
checked, and neither was how Excel renders them. The file says nothing past
the ninth variation; this
library starts the cycle again there (series 55 is series 1's colour), which
is unconfirmed. The gallery workbook writes Excel's `colors1.xml` and
`style1.xml` (`style2.xml` for line charts) beside each chart, as Excel does.

## Milestone checks

The owner records each milestone's check here.

| Milestone | Date | Excel | Result |
|---|---|---|---|
| J3 (`jet_charts_flutter` gallery, `gallery.xlsx` after `acd75e7`) | 2026-11-09 | Excel for Mac, `tr-TR` (version not recorded) | Owner compared all 16 charts side by side. Differences: `line_gap`, Excel draws a circle marker on every point and a line-and-circle legend symbol, the app none and a square; `area_stacked`, the app leaves space left and right of the area, Excel draws it edge to edge; `column_negative`, Excel puts the category labels at the zero line, covered by negative bars, the app under the plot (kept, deliberate: `parity.md`); `column_eight_series`, the app's legend wraps to two lines (the app had no Aptos Narrow) and series 7 and 8 differ in colour (above); `column_long_labels`, Excel keeps the labels level and wraps them onto two lines, the app turns them and cuts them; `column_data_labels`, the label 18 does not show in the app. No other difference. Fixes follow in a later commit. |
| J3 re-check (`gallery.xlsx` after `6dc2dff`, the app on the same commit) | 2026-11-09 | Excel for Mac, `tr-TR` (version not recorded) | Owner compared the charts again. `line_gap`, `area_stacked`, `column_long_labels` and `column_data_labels` now match. `column_negative` keeps its deliberate difference. `column_eight_series`: the app's legend still wraps to two lines (no Aptos Narrow in the app); the gallery's series 7 and 8 still show light in Excel, but a new clustered column chart the owner made in Excel from the same cells shows them dark, the same colours as the app (`0D3A4E`, `994010`, read by Claude for Excel; above). |
