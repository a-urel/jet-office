# Working in jet_charts_flutter

`jet_charts_flutter` is the Flutter backend of the jet_ chart family: it
measures and draws what `packages/jet_charts_core` lays out, and will hold the
`CustomPainter` renderer, the widget and interaction (milestone J3). It reads
and writes no file format. The records of the design are the repository root's
`docs/decisions/0014-chart-phase-and-drawingml-layer.md` and
`docs/decisions/0016-jet-charts-flutter-in-the-workspace.md`.

Milestone J3 is under way. The package exports `FlutterTextMeasurer`,
`paintChartPrimitives`, `ChartLayoutPainter`, and the widget `JetChart` with
`JetChartStateBuilder`, `JetChartErrorBuilder` and `JetChartStrings` (its
loading, empty and error texts and its screen reader description, in English,
Turkish and German), and `JetChartHit`, what `JetChart.onHover` and
`JetChart.onTap` report (hover, touch and the tooltip box:
`lib/src/interaction.dart`, `lib/src/tooltip_view.dart`, tested in
`test/interaction_test.dart`). A change of the chart at the same size moves
its marks over `JetChart.animationDuration` (`lerpChartPrimitives`,
`lib/src/animation.dart`, tested in `test/animation_test.dart`); hover and
taps use the new layout throughout. The rest of J3 adds to this file.

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
and paint recording for dashboard charts and two large series. It records
figures and fails on nothing; the gate does not run it. Run it with
`flutter test benchmark`; how to run it in Chrome and the recorded figures are
in `docs/benchmark.md`.

## The quality gate

Run from this package's folder, `packages/jet_charts_flutter`, except the first
two, which the repository's gate also runs from its root. A clean checkout must
pass all four:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
flutter test
flutter test --platform chrome --exclude-tags golden
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
