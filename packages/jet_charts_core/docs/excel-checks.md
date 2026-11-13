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
| A marker on every line point (`lineMarkers` on) | Verified | chart2 `c:lineChart` `c:marker` 1 and the series' `c:marker` circle; the owner's J3 gallery check shows a circle on every point |
| Marker outline 0.75 pt of the series colour | Verified | chart2 series `c:marker` `c:spPr` `a:ln w="9525"` of the series colour |
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
| J4 E2 (`gallery.xlsx` after `561a863`, the app on the same commit) | 2026-11-10 | Microsoft Excel for Mac 16.114.4 (26110224), Microsoft 365, `tr-TR` | Owner compared the J4 charts side by side. `column_negative` and `combo_column_line`: Excel's category labels at the zero line, covered by negative bars; the owner prefers the app's, so the files now write them `low` (`d549e15`). `area_translucent`: Excel's areas opaque, without lines (expected: the workbook writes Excel's plain stacked area). `pie_basic`: the labels dark in Excel, white in the app (E1: Excel's are dark). `pie_small_slices`: Excel writes value and percent on one line, `3; 3%`, the app on two, and the leader lines differ. `donut_center`: no centre text in Excel (expected). `donut_two_series`: Excel shows the labels, overlapping; the app hides all eight. `sparkline_area`: a line in Excel (expected: Excel has no area sparkline). The combination charts' lines: markers in the app, none in Excel (E1: Excel's have none). |

## J4 values

Milestone J4 added the kinds below as this library's estimates. The owner's
E1 file (`chart_reference_j4.xlsx`, steps in
`test/fixtures/owner/charts/TALIMATLAR_J4.md`; read 2026-11-10, below) and E2
(the J4 gallery of `packages/jet_charts_flutter/example` side by side, its
`TALIMATLAR.md`; the Milestone checks table) say for each row what Excel
confirmed and what differs. A row still marked estimate or pending has not
been read from Excel; its result goes here from the owner only. The sources
are what this library chose. A row that differed is fixed: it says so and
names the value that now holds Excel's.

| Value | Status | Source |
|---|---|---|
| First slice starts at 12 o'clock and slices run clockwise | Confirmed by E1: Excel writes `c:firstSliceAng 0` (charts 1, 2, 3, 7) | This library's choice (the schema's `c:firstSliceAng` default is 0); the DrawingML writer writes it since C2 |
| Donut hole 75 % (`Chart.holeSizePercent`) | Confirmed by E1: `c:holeSize 75` (charts 2, 3) | This library's choice for a modern donut (the schema's `c:holeSize` default is 10); the DrawingML writer writes it since C2 |
| Slice outline in the background colour, 1.5 pt (`sliceBorderWidth`) | Differed (E1): Excel outlines each slice `lt1` (white), 1.5 pt (`a:ln w="19050"`, every `c:dPt`), where the app drew 0.75 pt; now Excel's (`sliceBorderWidth` 1.5 by default and in the Office theme) | E1 |
| A pie of one series varies colours by category, palette order | Confirmed by E1: `c:varyColors 1`, a `c:dPt` per slice of `accent1` to `accent4`; in a donut of two series each ring starts again at `accent1` | This library's choice, from the usual look of an Excel pie |
| Legend of a pie or donut at the bottom, one entry per category | Confirmed by E1: `c:legendPos b`; an automatic title (the series name, 14 pt) on every chart | Same rule as the other kinds (verified for them) |
| A negative slice drawn as its absolute value | Confirmed by the owner's screenshot of the E1 sheet (2026-11-10): in charts 1 and 3 Doğu's `-4` is a slice of about 9 % (4 of 43), its absolute value | This library's choice |
| The first donut series is the innermost ring | Confirmed by the screenshot: in chart 3 the inner ring is `Satış`, the first series (its Doğu slice short, 9 %), the outer `Adet` (Doğu 32 %) | This library's choice |
| Pie label leader line, 0.75 pt, `A6A6A6` (`ChartTheme.leaderLine`) | Differed (E1, chart 7): Excel's `c:leaderLines` is 0.75 pt `tx1` at `lumMod` 0.35 and `lumOff` 0.65 (`A6A6A6`), where the app used the axis line (`D9D9D9`); now Excel's (the Office theme's `leaderLine`; the gallery workbook writes the same `c:leaderLines`) | E1 |
| Pie and donut labels inside a slice at 0.6 of the radius (pie) or mid-ring (donut) | Differed in colour (E1, chart 7): Excel's labels are `bestFit`, 9 pt, `tx1` at `lumMod` 0.75 and `lumOff` 0.25 (`404040`) with no fill, as the gallery workbook writes, where the app drew a label inside a dark slice white; now Excel's in the Office theme (`ChartTheme.sliceLabelContrast` off; an app's theme keeps the contrast rule by default, `parity.md`). Where `bestFit` puts each label is Excel's own and not in the file | This library's choice |
| Scatter: both axes automatic by `autoValueScale`, grid lines and an axis line on both axes, markers only | Markers only confirmed (E1, chart 4: `c:scatterStyle lineMarker`, the series line `a:noFill` 3 pt, circle markers of 5). Differed: Excel draws grid lines on both axes and both axis lines (`tx1` at `lumMod` 0.25, `lumOff` 0.75, `BFBFBF`, 0.75 pt), both crossing `midCat`, the x axis without `c:numFmt`; now Excel's: the Office theme's `scatterAxisLine` draws both lines, the galleries set `categoryAxis.gridLines` (the model's default stays off), and the gallery workbook writes both axes so. The axis ranges stay this library's rule, pending a numeric scatter | The J2 rule (verified for value axes) used on the x axis; Excel's scatter styles are not read |
| Scatter: a text x value numbers the points 1, 2, 3 | Confirmed by the screenshot: chart 4 took the text `A2:A5` as its x values and draws the points at 1, 2, 3, 4 (x axis 0 to 4.5 by 0.5, vertical grid lines shown). A scatter of numeric x values: confirmed by E3 (below): two `c:valAx` crossing `midCat`, grid lines on both, `c:xVal/c:numRef`; Excel gives the x axis a linked `General` `c:numFmt` (now written for numbers and dates) | This library's choice, from the usual behaviour of Excel with text x values |
| Secondary value axis on the right, no grid lines | Confirmed by E3 (below): `c:axPos r`, no grid lines, no tick marks, `c:crosses max`, `c:crossBetween between`, labels `nextTo`, crossing a deleted `c:catAx`. Differed: Excel's deleted category axis has no tick marks and no `c:crosses`, where the writer wrote `out` and `autoZero` (not visible); now Excel's | This library's choice |
| Combination: columns, areas, then lines; primary before secondary within a kind | Confirmed for columns then a line (E1, chart 5). Differed: its columns have `c:gapWidth 150` and no overlap (not the clustered chart's 219 and -27), its line is 2.25 pt with no marker (`c:symbol none`), where the app drew markers and the clustered gap; now Excel's (`ChartTheme.combinationGapWidthPercent` 150 with overlap 0, `combinationLineMarkers` off; the gallery workbook writes gap 150 and no overlap) | This library's choice, from Excel's usual group order |
| Sparkline line 0.75 pt (`sparklineWidth`); area fill under it; a lone value a disc of diameter `2 * sparklineWidth` | Estimate, not checked in Excel; pending E1/E2 | This library's choice; Excel's sparkline is a cell feature (`x14`) |
| Smooth line: Catmull-Rom spline | The file confirms only `c:smooth 1` on the series (E1, chart 6; the line keeps its circle markers of 5 and 2.25 pt); the screenshot shows the curve passing through each marker with its lowest point at Güney's marker (95); whether it overshoots a peak is covered by the About box there: kontrol edilmedi (not checked) | Excel's smoothing is not documented |
| A smooth area series curves its top on screen and writes no `c:smooth` | Estimate, not checked in Excel; pending E1 | Excel's area has no `c:smooth` in the schema |
| Area `areaOpacity` as `a:alpha`; `areaLine` as the series line | Estimate, not checked in Excel; pending E1 | The DrawingML schema's alpha and `a:ln` |
| `c:dPt` for point colours (bar fill; line marker, written and drawn even with `lineMarkers` off) | Estimate, not checked in Excel; pending E1 | The schema's order; Excel's own file decides |
| `showValue: false` as `c:showVal 0`; `showPercent` written as 0 | Estimate, not checked in Excel; pending E1 | The schema |
| The gallery workbook's colour and style parts per kind | Differed (E1): Excel writes the colour style 10 everywhere, but the chart style 251 for a pie or donut, 240 for a scatter chart, 322 for the combination and 332 for the smooth line, where the workbook gave every kind but a line chart 201; now Excel's (the parts copied from the E1 file; its 332 equals the line chart part already written) | E1 |

### E1: what the owner's file holds

`chart_reference_j4.xlsx` (39,084 bytes, saved 2026-11-10, Microsoft Excel
for Mac 16.114.4 (26110224), Microsoft 365, `tr-TR`): the sheet `Veri` of
`TALIMATLAR_J4.md` (typed by the Claude Excel add-in, which left its task
pane parts in the file), and its seven charts added by the owner from the
Insert menu, read by Claude. Two charts differ from the steps: chart 4 (the
scatter) took `A2:A5` (text) as its x values and `Satış` and `Adet` as two
series, not `B2:C5` as one series; chart 5 is Excel's "Clustered Column -
Line" with both series on one axis, not the secondary axis variant. The
secondary axis and a numeric scatter stay unread. Every value above marked
E1 comes from this file; the rows still pending need the owner's eye on the
drawn chart, not the XML.

The owner's screenshot of the sheet (2026-11-10, charts 1 to 4 and part of
6) also shows the automatic titles: the series name (`Satış`) on a chart of
one series, `Grafik Başlığı` on a chart of two.

### E3: the secondary axis and a numeric scatter

J4 closed without it. The owner made the two charts of
`test/fixtures/owner/charts/TALIMATLAR_E3.md` by Excel's menus (2026-11-14,
Excel for Mac, `AppVersion` 16.0300; the file has Excel's `style` and
`colors` parts) on `Veri!A1:C5` and saved `chart_reference_e3.xlsx`, not
committed. Its XML was compared with what the DrawingML writer writes for
the same data (`combo_column_line` and `scatter_basic` of the C2 check's
`c2_dashboard.xlsx`):

- Chart 1, a column and line combination with the line on the secondary
  axis: the secondary value axis is the writer's (`r`, no tick marks, no
  grid lines, `crosses max`, `crossBetween between`, `nextTo`). Differed,
  not visible: Excel's deleted secondary `c:catAx` has `majorTickMark none`
  and no `c:crosses`, where the writer wrote `out` and `autoZero`; now
  Excel's. The primary category axis' labels are `nextTo` in Excel and `low`
  in the writer when a value is negative: kept, the owner's J3 and J4 rule.
  Excel's automatic title `Grafik Başlığı` is Excel's default; the writer
  deletes the title unless asked.
- Chart 2, a scatter of numeric x values (`B2:B5` against `C2:C5`, no
  headers): both axes `c:valAx` crossing `midCat`, grid lines on both,
  markers only, `c:xVal/c:numRef`, as the writer writes it. Differed, not
  visible: Excel gives the x axis `<c:numFmt formatCode="General"
  sourceLinked="1"/>`, which the writer left out; now written when the x
  values are numbers or dates (text x values keep none, chart 4 of
  `chart_reference_j4.xlsx`). One series without a name has no legend in
  Excel, the known rule.

Not exercised by E3, still not checked: an area group in a combination, a
scatter chart's data labels, a doughnut's label position.

### E2: the J4 gallery

The owner's side by side check of the J4 gallery (2026-11-10, the same
Excel) is in the Milestone checks table above.
