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
the line chart's; the workbook theme is Excel's default (Office, Aptos). The
owner's `chart_reference.xlsx` (the repository root's
`test/fixtures/owner/charts/`, 23 charts of two series made through Office.js,
Excel for Mac 16.0300, `tr-TR`, 2026-11-09) confirms the rows that name it.

| Value | Status | Source |
|---|---|---|
| Accents 1 to 6, `dk`/`lt` colours | Verified | `Office Theme.thmx`, Excel for Mac 16.114.4; the workbook's `theme1.xml` has the same |
| Line width 2.25 pt | Verified | chart2 series `a:ln w="28575" cap="rnd"` |
| Marker size 5 | Verified | chart2 `c:marker`: `c:symbol` `circle`, `c:size` 5 |
| Gap width 219 | Verified | chart1 `c:gapWidth` 219 |
| Gap width 150 for stacked and percent stacked bars and columns | Verified | `chart_reference.xlsx` charts 2, 3, 5 and 6 `c:gapWidth` 150, `c:overlap` 100; `ChartTheme.stackedGapWidthPercent` |
| Gap width 182 and overlap 0 for clustered bars | Verified | `chart_reference.xlsx` chart 4 `c:gapWidth` 182 and no `c:overlap` (the schema's default, 0); `ChartTheme.barGapWidthPercent`, `ChartSpacing.barOverlapPercent` |
| Overlap -27 | Verified | chart1 `c:overlap` -27; `ChartSpacing.overlapPercent` |
| Font Aptos Narrow | Verified | every `a:defRPr` names `+mn-lt`, the theme's minor font, which is `Aptos Narrow` in the workbook theme |
| Title size 14 pt | Verified | title `a:defRPr sz="1400"`, both charts |
| Axis label size 9 pt | Verified | both axes' `a:defRPr sz="900"`, both charts |
| Legend and data label size 9 pt | Verified | `chart_reference.xlsx`: every legend's `a:defRPr sz="900"`, and the data labels' of charts 20 and 21 |
| Data label colour `404040` | Verified | `chart_reference.xlsx` charts 20 and 21: `tx1` with `lumMod` 75000, `lumOff` 25000 (0.25 of 255 is `40`); the Office theme binds it to `dark1` with `lumMod` 0.75 and `lumOff` 0.25 |
| Text colour `595959` | Verified | title and axis labels `tx1` with `lumMod` 65000, `lumOff` 35000; `tx1` is `dk1`, black: 0.35 of 255 is `59`; the Office theme binds it to `dark1` with `lumMod` 0.65 and `lumOff` 0.35 |
| Line colour `D9D9D9` | Verified | gridlines, category axis line and chart border `tx1` with `lumMod` 15000, `lumOff` 85000: 0.85 of 255 is `D9`; the Office theme binds it to `dark1` with `lumMod` 0.15 and `lumOff` 0.85 |
| Grid and axis line width 0.75 pt | Verified | gridlines and category axis line `a:ln w="9525"` |
| Background `FFFFFF` | Verified | chart area `bg1`, which is `lt1`, white |
| Value gridlines on | Verified | `c:valAx` has `c:majorGridlines`; `c:catAx` has none |
| Tick length 0 (no ticks) | Verified | both axes `c:majorTickMark` and `c:minorTickMark` `none` |
| Legend at the bottom | Verified | `chart_reference.xlsx`: every chart of two series made unedited has `c:legendPos` `b` |
| Spacing: padding 8, title gap 6, legend gap 6 pt | Unconfirmed | Excel lays the chart out itself (`c:layout` empty); no source |
| Spacing: legend symbol 7, legend item gap 12 pt | Unconfirmed | No source |
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

Unconfirmed. `ChartTheme.seriesColor` derives colours past the sixth by lightening
and darkening the accents; the steps have not been compared with what Excel does
for a seventh series.

## Milestone checks

The owner records each milestone's check here.

| Milestone | Date | Excel | Result |
|---|---|---|---|
