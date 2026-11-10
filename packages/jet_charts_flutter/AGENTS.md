# Working in jet_charts_flutter

`jet_charts_flutter` is the Flutter backend of the jet_ chart family: it
measures and draws what `packages/jet_charts_core` lays out, and holds the
`CustomPainter` renderer, the widget and interaction (milestone J3, done). It
reads and writes no file format. The records of the design are the
repository root's `docs/decisions/0014-chart-phase-and-drawingml-layer.md`
and `docs/decisions/0016-jet-charts-flutter-in-the-workspace.md`.

Milestone J3 is done, and J4 is done but its Excel check (E1 and E2, owner's:
`packages/jet_charts_core/docs/excel-checks.md`, "J4 values"). The package
exports `FlutterTextMeasurer`,
`paintChartPrimitives`, `ChartLayoutPainter`, and the widget `JetChart` with
`JetChartStateBuilder`, `JetChartErrorBuilder` and `JetChartStrings` (its
loading, empty and error texts and its screen reader description, in English,
Turkish and German), and `JetChartHit`, what `JetChart.onHover` and
`JetChart.onTap` report (hover, touch and the tooltip box:
`lib/src/interaction.dart`, `lib/src/tooltip_view.dart`, tested in
`test/interaction_test.dart`). A change of the chart at the same size moves
its marks over `JetChart.animationDuration` (`lerpChartPrimitives`,
`lib/src/animation.dart`, tested in `test/animation_test.dart`); hover and
taps use the new layout throughout. A tap on the chart is left to the parent
(a dashboard tile) unless `onTap` is set; only a change of the chart animates,
a change of theme, locale or scale snaps, and reduced motion turns animation
off. Under `IntrinsicHeight` or `IntrinsicWidth` the widget answers by its
size rule (`JetChart`, "Size"). The default loading look repeats without
end, so a test must not `pumpAndSettle` while a chart loads; the tooltip box
is a live region and a screen reader announces each change of it. The chart
takes the keyboard's focus (`JetChart.focusable`, `focusNode`), walks its
points with the arrows, Home and End (a column or bar chart its bars, a pie
or donut its first series' slices, a scatter chart its markers, and a line,
area or combination chart or a sparkline its category bands, markers or
not), and gives a screen reader node per
category, slice or scatter point, up to `JetChartStrings.maxPointNodes`
(`lib/src/chart_semantics.dart`, tested in `test/accessibility_test.dart`);
a test of the keyboard runs in a `WidgetsApp` under an autofocused
`FocusScope`, as nothing holds the focus there without a navigator.

J4 added the painting of pies, donuts (arcs), sparklines, scatter and
combination charts and of translucent fills (`PathPrimitive.fillOpacity`), the
animation of arcs and opacity, keyboard and screen reader points of the new
kinds, the strings, the gallery's J4 charts, `JetChart.tooltipLines` (an
app's own lines under a tooltip's rows, in the box and the screen reader
nodes; `lib/src/interaction.dart`) and `docs/app-themes.md` (how an app builds
its themes; its code is `test/app_themes_doc_test.dart`).

## Open for J5, C2 and C3

- The owner's J3 gallery check against Excel for Mac is done and recorded
  (`packages/jet_charts_core/docs/excel-checks.md`, "Milestone checks"); its
  differences are fixed, but `column_negative` (kept). Series 7 and later
  follow Excel's colour cycle (`colors1.xml`), and the gallery workbook writes
  Excel's colour and style parts and every series' colour; the owner's
  re-check matched series 7 and 8. A later check's result goes there with
  the owner, never without. The gallery has no screenshot of the running app: the
  machine that built it could not record the screen.
- Whether a sandboxed macOS app sees Aptos Narrow (the gallery's header says
  which font it got); until known, goldens use Roboto.
- Tooltip box spacing and border constants are in `lib/src/tooltip_view.dart`,
  not in `ChartTooltipStyle`.
- A rect or path with `strokeWidth: 0` paints a hairline in Flutter; an arc
  with 0 draws no stroke. The core never emits 0, a theme could.
- Large series cost: about 250 ms (VM) and 520 ms (Chrome) for a 10,000-point
  line, about 100 and 190 ms for 3,650 categories of two series, almost all in
  the core's layout; the line has no markers, as its category step is under
  `markerSize` plus 2 pt, and records in about 0.4 ms (VM) and 4 ms (Chrome)
  (`docs/benchmark.md`).
- The gallery's chart list duplicates the core's test gallery (an app's `lib/`
  cannot import another package's test support): same names, drift is
  possible. The measurer fuzz generator is a copy too (`fuzz_copy_test.dart`).
- Minor and deferred: element ids are parsed again on every pointer event
  (the layout is hit tested once per event); the layout cache is dropped when
  a state look shows; the Chrome benchmark run copies the file into `test/` by
  hand.
- Each `JetChart` owns a `FlutterTextMeasurer` whose cache holds up to 2048
  painters; consider one shared measurer per text scaler, and measure a
  dashboard's memory.
- The Office chart border is the grid line colour, `dark1` with `lumMod`
  0.15 and `lumOff` 0.85 (`D9D9D9`), bound to the file theme; the tooltip's
  border is the theme's own (`ChartTooltipStyle.border`): the Office theme sets
  `D9D9D9`, and another theme (`ChartTheme.fromColors` sets its grid line
  colour) sets its own.
- J4: the Excel values of the new kinds are estimates until the owner's E1
  and E2 (the core's `AGENTS.md`, "Open for J5, C2 and C3", lists what else is
  open: other scatter styles, a bar chart's secondary axis, rounded corners,
  gradients, writing the kinds in DrawingML).
- Minor and deferred from J4: `JetChart._onFocusChange` calls `setState`
  every time, and the focus tests need two pumps; no tests for a leader line
  hidden before the end of an animation or for `fillOpacity` kept in the lerp;
  a `NaN` `fillOpacity` would throw in `_fill` (the core never emits one); the
  dark golden charts copy the light ones' data; some doc lines in
  `animation.dart` and `primitive_painter.dart` are over 80 columns; the
  Flutter copy of the fuzz generator has no commit hash in its provenance;
  the gallery's pie, doughnut and combination charts use the column chart's
  colour and style parts in the Excel workbook, the sparkline column width is
  approximate (`x14` sparklines are cell features, so `sparkline_area` shows
  as a line in Excel) and the page's palette is not Monépro's own.

## The gallery app

`example/` is the app `jet_charts_gallery` (macOS) for the owner's side-by-side
check against Excel for Mac, with `example/tool/write_excel_gallery.dart`,
which writes the same charts as Excel's own default charts; its README says
what it holds and `example/TALIMATLAR.md` holds the owner's steps. It is a
workspace member of its own, with `archive` as a dependency; this package's
`lib/` and guard tests do not cover it. Its tests run with
`(cd example && flutter test)`.

## Golden images

`test/chart_goldens_test.dart` paints the charts of `test/support/charts.dart`
(copies of the charts of the same names in
`packages/jet_charts_core/test/support/gallery.dart`) into
`test/goldens/<name>.png`, with `ChartTheme.office` set to the family `Roboto`
(`test/fonts/`, Apache 2.0, loaded by `test/support/fonts.dart` with
`dart:io`, so the file is `@TestOn('vm')`). `test/jet_chart_golden_test.dart`
paints `JetChart`'s default loading, empty and error looks the same way, and
`column_clustered` with the tooltip of `series/1/bar/2` open
(`jet_chart_tooltip.png`). After
a deliberate change, run `flutter test --update-goldens --tags golden` and look
at every image: no text overlaps, the chart border shows, no value axis line,
lines with round caps.

## Fuzzing

`test/measurer_fuzz_test.dart` runs the core's layout fuzz (seeds 1 to 4, 100
cases each) with `FlutterTextMeasurer` in the default font, on the VM and in
Chrome; `test/measurer_fuzz_roboto_test.dart` runs the same cases in Roboto
(VM only). Besides the core's check, each text's rectangle must be its
painter's size within 0.01, and painting must throw nothing. The generator is
`test/support/chart_fuzz.dart`, a copy of the core's
`test/layout/support/chart_fuzz.dart` (Flutter's browser tests compile only
files under `test/`); `test/fuzz_copy_test.dart` fails when the two differ, so
copy it again, with its provenance comment, after the core's changes. A failure
is a layout or measurer defect: pin it as a unit test in the owning test file
with the input minimized, then fix it.

## Benchmark

`benchmark/chart_benchmark_test.dart` times layout (cold and warm text cache)
and paint recording for dashboard charts, two large series, a 10,000-point
scatter chart and a pie of 60 slices. It records
figures and fails on nothing; the gate does not run it. Run it with
`flutter test benchmark`; how to run it in Chrome and the recorded figures are
in `docs/benchmark.md`.

## The quality gate

Run from this package's folder, `packages/jet_charts_flutter`, except the first
two, which the repository's gate also runs from its root. A clean checkout must
pass all five:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
flutter test
flutter test --platform chrome --exclude-tags golden
(cd example && flutter test)
```

The tests need Flutter's engine (`TextPainter`), so they run with
`flutter test`, not `dart test`. Golden image tests carry the tag `golden`
(`dart_test.yaml`). Their pixels differ by platform, so they run on macOS only:
the local `flutter test` runs them, and CI (`--exclude-tags golden`) and the
Chrome leg skip them (decision 0016). The Chrome leg runs every test that is not
marked `@TestOn('vm')` in a browser. It needs a local Chrome.

Never report work as done without running these and reading the output.

## Hard rules

- **Flutter's widgets layer, web-safe.** Nothing under `lib/` imports a
  `dart:` library other than `dart:ui`, `dart:math`, `dart:async` and
  `dart:collection`, or `package:flutter/material.dart` or
  `package:flutter/cupertino.dart` (Monépro has its own design system).
  `dart:io` and `dart:html` never. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **Runtime dependencies are `flutter`, `jet_charts_core` and `jet_core`.**
  `pubspec.yaml`'s `dependencies:` is exactly those, and nothing under `lib/`
  imports a `package:` other than them and this package. Enforced by
  `test/architecture/dependencies_test.dart`.
- **The public API is exactly what `lib/jet_charts_flutter.dart` exports**,
  each export with a `show` list. Everything under `lib/src/` is private.
  Enforced by `test/architecture/public_api_test.dart`.
- **Nothing depends on this package** but apps: `jet_charts_core` and
  `jet_office` never import Flutter (decision 0014).
- **Measure and paint alike.** What the renderer draws, it draws with the
  `TextPainter` that `FlutterTextMeasurer` measured, so layout's widths are the
  drawn ones even when Flutter falls back from a missing font.
- **Tests come first.** Write the failing test, watch it fail, then implement.
- **Decisions live in the repository root's `docs/decisions/`.** An accepted
  record is never edited; write a new one that supersedes it.
- Follow the surrounding code: explicit types, `final class`, dartdoc on every
  public member, plain sentences.
