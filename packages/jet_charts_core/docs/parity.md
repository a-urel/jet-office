# Parity with Excel

How `layoutChart` (milestones J2 and J4) compares with Excel for Mac, the
oracle, and every place it differs on purpose. The rule of the package: on
screen, no overlap beats matching Excel, and a bad input gives a defined picture
rather than a throw. Each difference below says which of the two it serves, or
why else it exists. The axis scale's own evidence is in `axis-scaling.md`, the
theme's in `excel-checks.md`.

## Kinds

| Kind | J2 | Against Excel |
|---|---|---|
| Column, clustered, stacked, percent stacked | Laid out | Scale checked on the owner's full run (L, W, M, G, F, C rows); default look from `chart_defaults.xlsx` |
| Bar, the same groupings | Laid out | Scale checked on the full run (B and G rows) |
| Line, the same groupings | Laid out | Scale checked (M16, M18); default line and marker from `chart_defaults.xlsx` |
| Area, the same groupings | Laid out | Scale checked (M17, M19, G03, G06, G09, G12) |
| Pie | Laid out (J4) | Matched by E1 (`excel-checks.md`, "J4 values"): first slice at 12 o'clock, clockwise; one colour per category in palette order; a 1.5 pt outline in the background colour (Excel's white `lt1`); legend lists the categories at the bottom. Pending the owner's look: a negative value drawn as its absolute value |
| Donut | Laid out (J4) | Estimate, not checked in Excel (pending E1): hole 75 % (`Chart.holeSizePercent`); the first series is the innermost ring; centre text is this library's own |
| Sparkline | Laid out (J4) | Estimate, not checked in Excel (pending E1/E2): 0.75 pt line, no axes, title, legend or text; Excel's sparkline is a cell feature, not a chart (`x14`), so the file side is the owner's gallery only |
| Scatter | Laid out (J4) | Matched by E1 (chart 4): markers only, no lines; both axis lines `BFBFBF` (`ChartTheme.scatterAxisLine`); grid lines on both axes when the chart sets `categoryAxis.gridLines`, as Excel's default has (the model leaves it off). Estimate: both axes automatic by `autoValueScale`; each series has its own x column |
| Combination (per-series kind) | Laid out (J4) | Matched by E1 (chart 5) for columns then a line: the columns' gap 150 and no overlap (`combinationGapWidthPercent`), the line without markers (`combinationLineMarkers` off). Estimate: areas before columns, primary-axis series before secondary ones within a kind |
| Secondary value axis | Laid out (J4) for column, line, area and combination charts | Estimate, not checked in Excel (pending E1): on the right, no grid lines; a bar chart has none |
| Smooth lines | Laid out (J4), a line series' `smooth`; an area series' `smooth` curves its top on screen only (below) | Estimate, not checked in Excel (pending E1/E2): a Catmull-Rom spline through the points; Excel's smoothing is not documented |
| Unsupported (a file's chart this model does not know) | Placeholder: the title and `unsupportedName` | Excel draws it; this package cannot |

## Elements

| Element | Matches Excel | Differs (see below) |
|---|---|---|
| Value axis scale: minimum, maximum | Every row of both owner runs but `F05` | `F05` (fixed minimum equal to fixed maximum) |
| Value axis major unit | Every row of the full run but `F05`, through `excelMaxIntervals` at Excel's plot length and font | Coarser when tick labels would touch; thinned at a fixed unit |
| Value tick labels | Font, size, colour; number format | Coarsening and thinning |
| Category labels | Level, then skipped at most every second (Excel's spacing never exceeded 2 in the C rows); long labels stay level, wrapped onto lines at spaces (matched in the owner's J3 gallery check, `column_long_labels`: five labels on two lines each, the value axis 0 to 160 by 20) | Placed in a band under the plot; wrapped onto at most three lines, then turned and cut by this package's own order |
| Grid lines | Value grid on, category grid off, 0.75 pt `D9D9D9` | None |
| Axis lines | Category axis line, 0.75 pt `D9D9D9`, no value axis line | Same in the Office theme; other themes draw a value axis line unless `valueAxisLine` is false |
| Bars | Gap width 219 and overlap -27 for clustered columns, 182 and 0 for clustered bars, 150 and 100 for stacked kinds; no outline | Same (`ChartTheme.gapWidthPercentOf`, `overlapPercentOf`); gap and overlap clamped to Excel's ranges |
| Lines and markers | 2.25 pt, a circle marker of 5 pt with a 0.75 pt outline on every point (matched in the owner's J3 gallery check, `line_gap`) | Dense lines carry no markers, this library's choice; Excel's behaviour on dense lines was not checked (see below). The layout gives no cap or join; `jet_charts_flutter` draws lines and outlines with round caps and joins, and other backends choose. Markers are drawn whole on the plot's edge (their clip is the plot grown by their reach) and above every series' line; whether Excel draws a series' markers under the next series' line was not checked |
| Areas | On tick marks (`c:crossBetween midCat`, as this library writes an area chart): the first category at the plot's left, the last at its right, a lone one in the middle; category labels centred on those positions, the category grid lines through them (matched in the owner's J3 gallery check, `area_stacked`, which found the space this package left at both ends) | The first and last labels reach past the plot's ends, within the chart; the frame shrinks the plot for them and lowers the labels clear of the lowest value tick label. A tooltip's category band reaches halfway to each neighbour |
| Title | 14 pt `595959` Aptos Narrow | Shown only when the chart has one; no default title |
| Legend | 9 pt text; a line series' symbol is a line with a marker (matched in the owner's J3 gallery check, `line_gap`) | Shown unless hidden, even for one series; dropped whole when a side legend does not fit; the legend line's length, 16 pt, is this library's estimate |
| Data labels | 9 pt `404040` text; a clustered column or bar label outside its bar's end, above the plot's top when the bar nearly reaches the axis' maximum (matched in the owner's J3 gallery check, `column_data_labels`, where Excel shows 18 above its bar on an axis to 20) | Never overlap text, the legend or another mark; inside a bar only when it fits there, in the light or dark of the label colour and the background, whichever reads on the bar or area fill; an area label at the plot's edge moved inward; hidden when no place is left |
| Axis titles | Shown when set | Use the axis label style |
| Chart area | White background, 0.75 pt `D9D9D9` border | Same in the Office theme; other themes have no border unless `border` is set |
| Areas, J4 | Fill and no line (`areaOpacity` 1, `areaLine` off) | `areaOpacity` below 1 and `areaLine` are this library's own look for an app (Monépro's trend tiles); the file writes them as `a:alpha` and the series `a:ln` (estimate, not checked in Excel) |
| Data labels of a pie or donut | Value, percent or both (`showValue`, `showPercent`) | `minShare` is screen only; placement is this package's own rule (below); the leader line is Excel's `A6A6A6` (`ChartTheme.leaderLine`) at 0.75 pt (E1, chart 7); in the Office theme the labels are `404040` on every slice, as Excel's (below) |

## Deliberate differences

### Lines

- **Dense lines carry no markers (this library's choice).** A line series gets
  a marker on every point only when its category step, the distance between
  neighbouring categories along the axis, is at least the theme's
  `markerSize` plus 2 pt (7 pt in the Office theme); on a denser line only a
  point with no neighbour keeps its marker. The markers would touch and hide
  the line, and 10,000 of them cost about 40 times the line's paint
  (`packages/jet_charts_flutter/docs/benchmark.md`). The legend keeps its
  marker, and the chart part this library writes says what the theme says,
  so Excel is left to choose for the same chart; its behaviour on dense lines
  was not checked (`marks_test.dart`, "markers only where they fit").

### Scale

- **`F05`: a fixed minimum equal to the fixed maximum.** Excel keeps both and
  reports an axis of no length (5 to 5 by 0.5). The rule ignores a fixed
  maximum not above the minimum and draws 5 to 11 by 1: an axis of no length
  cannot be drawn, so a defined picture wins. Listed as a known difference in
  `test/scale/axis_parity_test.dart`.
- **Tick labels never touch.** Excel lets value tick labels collide; the frame
  takes the next coarser unit until adjacent labels keep `minTextGap` apart.
  `excelMaxIntervals` comes from Excel's font metrics, not the backend's, so
  with a wider backend font the unit can come out coarser than Excel's.
- **A fixed unit is thinned, not coarsened.** It cannot change, so only every
  k-th tick label is drawn, from the first, for the smallest k that fits;
  every grid line stays. Excel draws them all and lets them collide.
- **A percent axis shows shares.** On a percent stacked axis the `0%` format
  wins over a series' own format code, so a series with a percent code of its
  own loses its decimals there.
- **Bar charts above 10 intervals.** The rule takes at most 10 on both axes;
  the full run bounds bar charts by 12 only, so a very long bar axis may be
  one unit coarser than Excel's. Unverified.
- **Data a few parts in `1e14` apart near huge values** can top the axis by a
  float error; the marks are clipped to the plot (deferred to J3).

### Category labels

- **In a band under the plot.** Excel puts them "next to axis", at the value
  axis' crossing; this package puts them in a band under (or, for bars, beside)
  the plot, so negative values never push them into the bars. The owner's
  gallery check (J3, `column_negative`, 2026-11-09) saw Excel's labels covered
  by negative bars and chose to keep them under the plot. After the J4
  gallery check (2026-11-10) the owner chose the same for the files: the
  DrawingML writer and the gallery workbook write a category axis' labels
  `low` (`c:tickLblPos`) when a value is negative or the value axis starts
  below zero, so Excel draws them under the plot too; `nextTo` otherwise.
- **Turned labels sit `labelGap` below the plot** and move down to clear value
  label 0 where they would meet it.
- **The order of tries is this package's**: level labels showing every label;
  level labels showing every label, each wrapped at spaces onto at most three
  lines no wider than its slot (the distance between ticks less `minTextGap`);
  level labels showing every second; then turned 45 degrees for every first,
  second and third; then turned 90 degrees, skipping as needed, cut with `…`.
  Excel's label spacing in the C rows (2 at 180 pt wide, 1 at 360 and 720, for
  3, 12 and 30 characters) is why level labels skip at most every second. The
  owner's J3 gallery check (`column_long_labels`, 360 by 216) saw Excel keep
  five long labels level on two lines rather than turn them; where Excel
  breaks a line, how many lines it allows and when it turns instead were not
  measured. A word wider than its slot cannot wrap, so such labels turn. Each
  line takes as many words as fit, so a line may break elsewhere than Excel's
  (in Roboto, "Northern / region, first half" where Excel shows "Northern
  region, / first half"). On tick marks (an area chart) a wrapped try that
  lacks room past the axis' ends asks the frame for it only when the labels
  would still keep apart on the shortened axis.

### Text that does not fit

- **Degradation.** Content that does not fit is taken away in a fixed order
  (data labels, legend, axis titles, title, category labels, value labels),
  each step only when it can relieve what does not fit; Excel shrinks the plot
  and lets text overlap. Data labels take no room, so "data labels first" is
  nominal: they go one by one where they find no place, and on a tiny tile
  partly placed labels can outlive the legend.
- **A side legend is dropped whole** when its entries do not fit beside the
  plot; Excel would wrap or cut entries.
- **Hidden labels are listed.** Every text taken away is in
  `ChartLayout.hidden`, with its full text, for a tooltip.

### Data labels

- **Order of places.** A clustered column or bar label tries outside its
  bar's end, then inside it; a stacked one only the middle of its bar. Line
  labels try above, below, right and left of the point; an area label sits
  halfway between its point and the area's base, moved inward no further than
  needed where that leaves the plot, as the first and last points of an area
  sit on the plot's edges (this package's rule; where Excel puts those two
  labels was not measured). A label with no place is hidden and listed.
- **They never overlap other text or the legend**, keeping `minTextGap` from
  other text, and **never lie on a mark other than their own**: `findOverlaps`
  reports text over a bar, a marker (by the square around it) or a line
  (each segment at its stroke width), except a data label on its own bar.
  Whether Excel lets a label cover another bar or line was not measured; this
  package hides such a label instead, so a label crowded by a taller
  neighbouring bar or a steep line of its own series goes. Area fills, grid
  lines and axis lines do not count: labels are painted over every mark, and
  Excel draws data labels over area fills.
- **Outside end may leave the plot** into the chart's area (inside its
  padding), clear of the title, the legend and the axis labels, as Excel's
  label of a bar near the axis' maximum sits above the plot. Line and area
  labels and labels inside a bar stay inside the plot.
- **Inside a bar, readable.** A label inside a bar lies wholly inside the
  bar's visible part (else it is not placed there) and takes the lighter of
  the theme's data label colour and its background when the bar's colour (its
  point colour, if it has one) has a WCAG relative luminance below 0.5, else
  the darker, unless that one reads below 3:1 against the bar and the other
  reads better (`insideLabelStyle`). In the Office theme that is white
  (`FFFFFF`) on a dark bar and the data label colour on a light one; in a dark
  app theme the background on a light bar. Slices follow the same rule. The
  rule is this package's, not measured from Excel, after the owner's J3
  gallery check, where 18 was unreadable dark grey on dark blue.
- **On an area, readable.** An area label follows the same rule on the fill
  under it: its own series' in a stacked chart, else the topmost area painted
  under the label's centre (the last series whose area holds it), its own
  when none does. This package's rule, not measured from Excel.

### Look

- **Axis titles use the axis label style**: the theme has no axis title
  style. Excel's default axis title is larger and not yet measured.
- **Gap width and overlap are clamped** to Excel's ranges (0 to 500, -100 to
  100), so a theme outside them draws as its nearest bound.
- **No default title or legend rule.** Excel's default chart of one series
  shows a title ("Grafik Başlığı" in `tr-TR`) and no legend; this package
  shows the chart's own title when it has one, and the legend unless the
  chart hides it. Which to show is the caller's (`jet_office` reads it from
  the file).
- **Clamping and stacked lines.** A value's position is clamped to the plot
  slightly differently from where its mark is, and stacked lines take the
  extent of the stacked sums; neither has been compared with Excel, and
  neither breaks the overlap guarantee (deferred to J3).

### J4 kinds

An Excel value named here is "estimate, not checked in Excel" unless the
owner's E1 (`chart_reference_j4.xlsx`, `test/fixtures/owner/charts/
TALIMATLAR_J4.md`) or E2 (the J4 gallery side by side), recorded in
`excel-checks.md`, settled it; this page never states an Excel result the
owner has not given.

- **Pie labels inside a slice (E1, chart 7, 2026-11-10).** Excel writes a
  pie's labels dark (`404040`, `tx1` at `lumMod` 0.75 and `lumOff` 0.25)
  whatever the slice, and since E1 the Office theme does the same
  (`ChartTheme.sliceLabelContrast` off). An app's theme keeps the readable
  rule by default (`sliceLabelContrast` on, as `fromColors` has it): a label
  inside a dark slice takes the lighter of the label colour and the
  background, as a label inside a bar does.
- **Centre text of a donut.** Excel's doughnut has no such element, as far as
  this library knows (not checked in Excel; a text box over the chart does the
  same). `Chart.centerText` is drawn in the theme's `centerTextStyle` (the title
  style by default) when every corner of its box lies inside the hole's free
  circle (the hole less the slice outline) shrunk by `minTextGap`; else it is
  hidden and listed in `ChartLayout.hidden`. It is not written to a file.
- **Area translucency and an edge line.** `ChartTheme.areaOpacity` and
  `areaLine` are not Excel defaults (Excel's default area is opaque and has no
  line; not checked in Excel); the file writer can express both.
- **Outside label placement of a pie.** A label that does not fit in its slice
  is placed outside along the slice's middle angle, on the right when the angle
  is under 180 degrees, else on the left, pushed apart from the others; a label
  more than `labelGap` from its first place gets a leader line, and the label
  moves away from the pie until no part of the line enters it. A label that
  still meets a text or another slice or line is hidden and listed. A small
  slice's label can therefore be hidden where Excel shows it (the 3 % slice of
  `pie_small_slices` behind the 4 % one's leader line: no overlap; Excel would
  show both, not checked in Excel). `findOverlaps` leaves out a label's own
  leader line and own slice, as it does a bar label's own bar.
- **A donut has no outside labels.** A label that does not fit its ring is
  hidden; Excel's doughnut has none outside either (not checked in Excel).
- **`ChartDataLabels.minShare` is screen only.** A pie or donut slice whose
  share is under it has no label, for Monépro's "labels above 10 %"; a file has
  no such option, so the file shows every label. The value is validated by
  `copyWith` and the `Chart` constructor, not by the const constructor.
- **Data label format order.** A pie or donut label's text takes the labels'
  format code, else the series', else `General`, as a cartesian label does.
- **Scatter lines are not drawn.** Only markers: a scatter series has no
  connecting line, whatever the file's `c:scatterStyle`. Excel's other scatter
  styles (lines with and without markers, smooth) are open. The x values are the
  series' categories: numbers, or dates as Excel's serial; text numbers the
  points 1, 2, 3 (estimate, not checked in Excel; pending E1). The date axis is
  a value axis (no time scale).
- **A bar chart has no secondary axis.** A column, line, area or combination
  chart does; its series bound to the secondary axis are drawn after the primary
  ones of the same kind.
- **Combination category labels.** The category labels sit on tick marks only
  with an area series and no column series; lines alone sit between ticks, as in
  a line chart (this package's rule; Excel not checked, pending E1).
- **A gapped sparkline area.** The area of a sparkline series with gaps is one
  closed path per series that drops to the base at each gap (unique ids: an id
  identifies one primitive).
- **Sparklines always draw the background**, with no border, title or legend.
- **Smooth areas, screen only.** An area series with `smooth` set draws its
  fill's top and its edge line (`areaLine`) as the curve of a smooth line, and
  a stacked area sits on the curve of the one below it. Excel's area has no
  `c:smooth`, so a written chart's area is straight: the DrawingML writer
  writes nothing for it.
- **Point colours.** `ChartSeries.pointColors` colours single bars, line and
  scatter markers and slices; an entry `null` or past the end keeps the series
  colour. A bar's inside data label reads against its point colour, and the
  tooltip row of a point takes it. A line's point colour changes its marker
  only, and a point with a point colour keeps its marker even where the line
  marks no other point (`lineMarkers` off, or markers that do not fit), as the
  file then holds a lone marker there too (`c:dPt`; estimate, not checked in
  Excel). The legend keeps the series colour.
- **Overlap guarantee.** `findOverlaps` finds nothing in the J4 layouts, as in
  the others, and every hidden text of a pie, donut or sparkline stays reachable
  through a tooltip.
