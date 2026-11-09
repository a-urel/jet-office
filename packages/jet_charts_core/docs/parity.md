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
| Category labels | Level, then skipped at most every second (Excel's spacing never exceeded 2 in the C rows) | Placed in a band under the plot; turned and cut by this package's own order |
| Grid lines | Value grid on, category grid off, 0.75 pt `D9D9D9` | None |
| Axis lines | Category axis line, 0.75 pt `D9D9D9`, no value axis line | Same in the Office theme; other themes draw a value axis line unless `valueAxisLine` is false |
| Bars | Gap width 219 and overlap -27 for clustered columns, 182 and 0 for clustered bars, 150 and 100 for stacked kinds; no outline | Same (`ChartTheme.gapWidthPercentOf`, `overlapPercentOf`); gap and overlap clamped to Excel's ranges |
| Lines and markers | 2.25 pt, circle markers of 5 pt | The layout gives no cap, join or marker outline; `jet_charts_flutter` draws lines and outlines with round caps and joins, and other backends choose |
| Title | 14 pt `595959` Aptos Narrow | Shown only when the chart has one; no default title |
| Legend | 9 pt text | Shown unless hidden, even for one series; dropped whole when a side legend does not fit |
| Data labels | 9 pt `404040` text | Never overlap or leave the plot |
| Axis titles | Shown when set | Use the axis label style |
| Chart area | White background, 0.75 pt `D9D9D9` border | Same in the Office theme; other themes have no border unless `border` is set |

## Deliberate differences

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
  the plot, so negative values never push them into the bars.
- **Turned labels sit `labelGap` below the plot** and move down to clear value
  label 0 where they would meet it.
- **The order of tries is this package's**: level labels showing every label,
  then every second; then turned 45 degrees for every first, second and third;
  then turned 90 degrees, skipping as needed, cut with `…`. Excel's label
  spacing in the C rows (2 at 180 pt wide, 1 at 360 and 720, for 3, 12 and 30
  characters) is why level labels skip at most every second; how Excel turns
  or wraps was not measured.

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

- **They never overlap other text or leave the plot**, keeping `minTextGap`
  from other text; a label with no place is hidden and listed.
- **They are not checked against marks**: a label may lie over another
  series' line or bar.
- Inside-end and centre labels can straddle a short bar's edge.

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
