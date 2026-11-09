# Working in jet_charts_core

`jet_charts_core` is the pure-Dart core of the jet_ chart family: the chart
model, the theme, axis scales, layout and drawing primitives. It draws nothing,
reads and writes no file format, and has no Flutter. Backends draw what it
lays out; `jet_office` writes and reads the model as a chart in XLSX and DOCX.
The record of the design is the repository root's
`docs/decisions/0014-chart-phase-and-drawingml-layer.md`.

Milestones J1, J2 and J3 are done, and the owner's full axis oracle run is
recorded (`docs/axis-scaling.md`, "Findings"). The package exports the model,
the theme, the drawing primitives and the text measurer (J1), the value scale
(`autoValueScale`), the layout (`layoutChart`) and the overlap check
(`findOverlaps`) (J2). J3 added element ids and `hitTestLayout`,
`ChartLayout.categoryBands`, the tooltip (`chartTooltipAt`, `chartTooltipFor`,
`ChartTooltipStyle`), `summarizeChart`, and the Office border and no value axis
line; the renderer is `jet_charts_flutter`.

## The packages

This repository is a pub workspace (decision 0013). The chart family:

| Package | Holds | Depends on |
|---|---|---|
| `jet_core` | number format engine, locale, what else two families share | pure Dart only |
| `jet_charts_core` | model, theme, scales, layout, primitives | `jet_core` |
| `jet_charts_flutter` | `CustomPainter` renderer, widget, text measurer, interaction | core, Flutter |
| `jet_office` (repository root) | `c:chartSpace` read and write, host adapters for XLSX, DOCX | `jet_core`, `jet_charts_core` (from C1, decision 0014) |
| `jet_print` (later) | PDF painter, its own measurer | core |

`jet_office` depends on this package from C1: its DrawingML layer writes and
reads `c:chartSpace` for a `Chart` (`docs/drawingml-charts.md` at the root).
C1 is done except the owner's reference workbook and Excel check; C2 and C3
add the XLSX and DOCX hosts. `lumMod` and `lumOff` on scheme colours are in
`ChartColor` (done in C1).

`jet_charts_core` must not depend on `jet_office`, or the two form a cycle.
What both need goes in `jet_core`. `jet_charts_flutter` is
`packages/jet_charts_flutter` (decision 0016), with its own `AGENTS.md`.

## The quality gate

Run from this package's folder, `packages/jet_charts_core`, except the first
two, which the repository's gate also runs from its root. A clean checkout
must pass all four:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart test -p chrome
```

The Chrome leg runs every test that is not marked `@TestOn('vm')` in a
browser, which proves the library is web-safe at run time and not only by its
imports. It needs a local Chrome.

Never report work as done without running these and reading the output.

## The Excel oracle

Excel's automatic axis is read from Excel for Mac, not LibreOffice, and only the
owner's run counts as a result. The results are committed under
`test/fixtures/owner/axis/`; the README there describes them, `TALIMATLAR.md`
is the owner's steps, and `docs/axis-scaling.md` holds the question and the
findings.

- `test/axis_oracle_test.dart` (in the gate, VM only) checks each region's CSV
  against the case list; a region without a manifest entry prints `unverified`
  and passes. Never edit a committed CSV or `manifest.json` there without the
  owner.
- `tool/write_axis_oracle.dart <dir>` writes the workbook from `cases.json`, with
  a small writer in `tool/src/axis_oracle.dart`, using `archive` (a dev
  dependency): this package may not depend on `jet_office`. The Open XML SDK must
  report no error on it (`dotnet run --project tool/ooxml_validate -- <dir>` from
  the repository root).
- `tool/axis_oracle/run_excel.applescript <workbook> <csv>` reads the axes from
  Excel.
- `tool/analyze_axis_oracle.dart [folder]` prints what differs across height and
  font, and the answer.
- The full oracle (J2, case list version 2) lives in `test/fixtures/owner/axis_full/`
  with its own README and `TALIMATLAR.md`: `write_axis_oracle.dart --full`, the
  script's third argument `full`, and `analyze_axis_oracle.dart --full`. Its
  code is the part `tool/src/axis_oracle_full.dart`. The script's `full`
  argument runs it; Excel may refuse to open the workbook through its
  dictionary, and the script then falls back to `open -a 'Microsoft Excel'`. `test/axis_oracle_test.dart`
  checks it as it checks the first; the first oracle's files stay as committed.

`docs/excel-checks.md` lists the Office theme values Excel's default charts
confirmed and those still unconfirmed; `docs/parity.md` compares layout with
Excel and lists every deliberate difference.

## The scale

`autoValueScale` (`lib/src/scale/value_scale.dart`) is Excel's rule for the
value axis: the minimum and maximum from the data extent (`dataExtent`), the
major unit from the axis length, through `excelMaxIntervals` (rounded down,
kept between 1 and 10). The rule was fitted on, and is tested against, the
owner's oracle runs in `test/fixtures/owner/` (`axis_oracle_test.dart`); a
change to it must keep every verified region passing. `docs/axis-scaling.md`
states the rule and the findings.

## The layout

`layoutChart` (`lib/src/layout/`) turns a chart, a theme, a size and a
`TextMeasurer` into a `ChartLayout`: `primitives` in paint order and `hidden`,
the labels it left out (`ChartHiddenLabel`). Column, bar, line and area charts
of every grouping are laid out; the frame comes first (`frame.dart`), the axes
and category labels (`axis_layout.dart`), marks, data labels, legend.

- Collision rules: category labels wrap at spaces (level, at most three
  lines), turn (0, -45, -90 degrees), skip every `N`th or are cut with an
  ellipsis; a legend that does not fit shrinks to fewer entries or moves;
  data labels give way to text, the legend, bars, markers and lines other
  than their own bar (not to area fills), and each other (a column or bar
  label outside its bar's end may leave the plot, one inside a bar must fit
  in it and is white on a dark bar), and those that cannot be placed go to
  `hidden` (`degradation.dart` orders what goes first). A line marks every
  point only when its category step is at least `markerSize` plus 2 pt, else
  only its lone points (`lineMarkersFit`; Excel marks them all, `parity.md`).
  `findOverlaps` must find nothing in any layout.
- Ids: every primitive has an id (`chart_ids.dart`), stable across layouts of
  the same chart, for hit testing and tests. The scheme is documented in
  `ChartLayout.primitives`; `ChartElementId` parses it and `hitTestLayout`
  finds the element at a point (a closed path is hit on its outline and
  stroke as well as its fill).
- `findOverlaps` (`overlap.dart`) reports texts that overlap each other, the
  legend, the chart's edge or a bar, marker or line other than a data
  label's own bar (`ChartOverlapKind.textMark`; area fills do not count), as
  `ChartOverlap`s of a `ChartOverlapKind`. It is the fuzz test's check and
  may be used by backends.
- Goldens: `test/layout/golden_test.dart` compares the layout of each chart in
  `test/support/gallery.dart` with `test/goldens/*.txt`. After an intended
  change, rewrite them and review the diff:
  `UPDATE_GOLDENS=1 dart test test/layout/golden_test.dart`.
- Gallery: `dart run tool/write_gallery.dart build/gallery` writes
  `gallery.html`, every gallery chart as inline SVG, to look at in a browser.
- `docs/parity.md` compares the layout with Excel and lists every deliberate
  difference; change it with the layout.

## Fuzzing

`test/layout/fuzz_test.dart` lays out seeded random charts
(`test/layout/support/chart_fuzz.dart`: every kind, 0 to 12 series, 0 to 60
text, number or date categories, `NaN`, infinite and huge values, long titles
and line breaks in text, fixed bounds with a fixed major unit down to `5e-324`
or one to ignore, format codes on axes, series and data labels, tiny to large
sizes) and requires of each that `layoutChart` throws nothing,
every number is finite, `findOverlaps` finds nothing and every primitive lies
inside the size (marks inside a clip are checked for finiteness only). The gate
runs seeds 1 to 4 with 100 cases each, the same cases on the VM and in Chrome
(a fingerprint test proves it); longer runs by hand:

```bash
dart run tool/fuzz_layout.dart --seeds 1-200 --cases 1000
```

It prints each failure as `seed <s> case <i>: <problem>` and the chart, and
exits 1 on any, 2 on unusable arguments. A failure is a layout defect: pin it
as a unit test in the owning `test/layout/*_test.dart` with the input minimized
by hand, then fix it.

## Hard rules

- **Pure Dart, web-safe.** Nothing under `lib/` imports `dart:io`, `dart:ui`,
  `dart:html` or any Flutter library. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **One runtime dependency, `jet_core`.** `pubspec.yaml`'s `dependencies:` is
  exactly `jet_core` and nothing under `lib/` imports a `package:` other than
  `package:jet_charts_core/` and `package:jet_core/`. Enforced by
  `test/architecture/dependencies_test.dart`. `archive`, `xml`, `test` and
  `lints` are dev dependencies for tests and tools only.
- **The public API is exactly what `lib/jet_charts_core.dart` exports.**
  Everything under `lib/src/` is private.
- **No import of `jet_office`.** Format codes are strings; this package knows
  no file format.
- **Tests come first.** Write the failing test, watch it fail, then implement.
- **Decisions live in the repository root's `docs/decisions/`.** An accepted
  record is never edited; write a new one that supersedes it.
- **Excel is the oracle** for axis ranges and number formats, as for the rest
  of the repository. Never edit the owner's oracle results, and never invent
  an oracle value.
- Follow the surrounding code: explicit types, dartdoc on every public member,
  plain sentences.

## Open for J4 and C1

- Pies, donut, sparkline, scatter, combination charts, per-series kind and
  the secondary axis (J4).
- Excel's time-scale date axis (owner decision O2; dates are categories).
- The en-US and de-DE oracle regions are unverified; so are fonts other than
  8, 10 and 18, and plot margins.
- The owner's J3 gallery check against Excel for Mac (decision O3) is done
  and recorded (`docs/excel-checks.md`, "Milestone checks"); its differences
  are fixed, but `column_negative` (kept, `docs/parity.md`). Still
  unconfirmed: Excel's gap width for clustered bars (182) and stacked ones
  (150, 100), written from memory in the gallery workbook (the check saw no
  difference there, but read no file); what Excel's colour cycle does past
  its nine variations (series 55 on); the spacing constants in
  `docs/excel-checks.md`. Series 7 and later follow Excel's colour cycle,
  `colors1.xml` of `chart_defaults.xlsx` (`ChartTheme.seriesColor`); the
  owner's re-check of `column_eight_series` is pending.
- Whether a sandboxed macOS app sees Aptos Narrow (Flutter side).
- The tooltip box's spacing constants are not in `ChartTooltipStyle`, and
  `chartTooltipAt` resolves the chart again on each call (a caller that has
  hit tested passes `hits`, so the layout is not hit tested twice).
- Category labels: level labels wrap onto at most three lines before they
  turn (the owner's J3 gallery check, `column_long_labels`); where Excel breaks
  a line, how many lines it allows and when it turns instead are unknown.
- Layout cost on large series: a 10,000-point line about 250 ms on the VM and
  520 ms in Chrome, 3,650 categories of two series about 100 and 190 ms
  (`packages/jet_charts_flutter/docs/benchmark.md`). Data-label placement
  checks each place only against the texts, labels and marks filed in the
  cells of a 32 pt grid its box covers (`BoxGrid`), and within a mark only
  against the shapes whose boxes can reach it (a line's segments, sorted by
  box and found by binary search); a 10,000-point line with data labels lays
  out in about 255 ms on the VM, and `data_labels_test.dart` (VM only) fails
  it above 1.5 s.
- Known deferred defects: the value-position functions disagree beyond 2x the
  span (`valuePosition` clamps to [0, 1], marks to [-1, 2]); the stacked line
  or area extent with mixed signs is wider than needed; a side legend is
  dropped whole for one long name; near-equal huge values (relative spread
  about 1e-14) can put the data top above the axis; the "data labels first"
  degradation is nominal.
- Bars use one gap width (219) and overlap (-27) for every kind, verified for
  clustered columns only; Excel's insert defaults are believed (unconfirmed)
  to be gap 182 and no overlap for clustered (horizontal) bars, gap 150 and
  overlap 100 for stacked kinds
  (`docs/parity.md`, "Bars"). The owner's gallery check saw no difference but
  read no file; an Excel-saved file settles it, and a gap and overlap per
  kind in the theme is J4 if confirmed.
- Minor: `public_api_test` asserts the exact formatted export text.
- Known difference F05 (fixed minimum = fixed maximum) in `docs/parity.md`.

## Reference

Consumers: Monépro's dashboards first, then `jet_print` and `jet_office`.
`jet_charts_core` knows none of them.
