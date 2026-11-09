# Parity with Excel

How `layoutChart` (milestone J2) compares with Excel for Mac, the oracle, and
every place it differs on purpose. The rule of the package: on screen, no
overlap beats matching Excel, and a bad input gives a defined picture rather
than a throw. Each difference below says which of the two it serves, or why
else it exists. The axis scale's own evidence is in `axis-scaling.md`, the
theme's in `excel-checks.md`.

## Kinds

| Kind | J2 | Against Excel |
|---|---|---|
| Column, clustered, stacked, percent stacked | Laid out | Scale checked on the owner's full run (L, W, M, G, F, C rows); default look from `chart_defaults.xlsx` |
| Bar, the same groupings | Laid out | Scale checked on the full run (B and G rows) |
| Line, the same groupings | Laid out | Scale checked (M16, M18); default line and marker from `chart_defaults.xlsx` |
| Area, the same groupings | Laid out | Scale checked (M17, M19, G03, G06, G09, G12) |
| Pie, donut, scatter, sparkline, combination | Placeholder: the title and the kind's name | Not drawn until a later milestone |
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
| Bars | Gap width 219, overlap -27, no outline (Excel's clustered column default) | Gap and overlap clamped to Excel's ranges; the same gap and overlap for every bar kind and grouping (see below) |
| Lines and markers | 2.25 pt, a circle marker of 5 pt with a 0.75 pt outline on every point (matched in the owner's J3 gallery check, `line_gap`) | The layout gives no cap or join; `jet_charts_flutter` draws lines and outlines with round caps and joins, and other backends choose |
| Areas | On tick marks (`c:crossBetween midCat`, as this library writes an area chart): the first category at the plot's left, the last at its right, a lone one in the middle; category labels centred on those positions, the category grid lines through them (matched in the owner's J3 gallery check, `area_stacked`, which found the space this package left at both ends) | The first and last labels reach past the plot's ends, within the chart; the frame shrinks the plot for them and lowers the labels clear of the lowest value tick label. A tooltip's category band reaches halfway to each neighbour |
| Title | 14 pt `595959` Aptos Narrow | Shown only when the chart has one; no default title |
| Legend | 9 pt text; a line series' symbol is a line with a marker (matched in the owner's J3 gallery check, `line_gap`) | Shown unless hidden, even for one series; dropped whole when a side legend does not fit; the legend line's length, 16 pt, is this library's estimate |
| Data labels | 9 pt text; a clustered column or bar label outside its bar's end, above the plot's top when the bar nearly reaches the axis' maximum (matched in the owner's J3 gallery check, `column_data_labels`, where Excel shows 18 above its bar on an axis to 20) | Never overlap text, the legend or another mark; inside a bar only when it fits there, white on a dark bar; hidden when no place is left |
| Axis titles | Shown when set | Use the axis label style |
| Chart area | White background, 0.75 pt `D9D9D9` border | Same in the Office theme; other themes have no border unless `border` is set |

## Deliberate differences

### Bars

- **One gap width and overlap for every bar kind.** The core uses the
  theme's one gap width (219) and overlap (-27) for clustered, stacked and
  percent stacked columns and bars alike. Only the clustered column's values
  are verified (`chart_defaults.xlsx`). Excel's insert defaults for the others
  are believed, unconfirmed, to be a gap of 182 and no overlap for clustered
  (horizontal) bars and a gap of 150 and an overlap of 100 for the stacked
  kinds (the gallery workbook writes these from memory). The owner's gallery check against
  Excel for Mac (`packages/jet_charts_flutter/example/TALIMATLAR.md`) settles
  it; if confirmed, a gap and an overlap per kind in the theme is J4.

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
  by negative bars and chose to keep them under the plot.
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
  halfway between its point and the area's base. A label with no place is
  hidden and listed.
- **They never overlap other text or the legend**, keeping `minTextGap` from
  other text, and **never lie on a mark other than their own**: `findOverlaps`
  reports text over a bar, a marker (by the square around it), a line (each
  segment at its stroke width) or an area, except a data label on its own bar
  or its own series' area. Whether Excel lets a label cover another mark was
  not measured; this package hides such a label instead, so a label crowded
  by a taller neighbouring bar, a steep line of its own series or the band
  above a thin stacked area goes. Grid lines and axis lines do not count.
- **Outside end may leave the plot** into the chart's area (inside its
  padding), clear of the title, the legend and the axis labels, as Excel's
  label of a bar near the axis' maximum sits above the plot. Line and area
  labels and labels inside a bar stay inside the plot.
- **Inside a bar, readable.** A label inside a bar lies wholly inside the
  bar's visible part (else it is not placed there) and is white (`FFFFFF`)
  when the bar's colour has a WCAG relative luminance below 0.5, else the
  theme's data label colour. The rule is this package's, not measured from
  Excel, after the owner's J3 gallery check, where 18 was unreadable dark
  grey on dark blue.

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
