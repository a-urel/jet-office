# Working in jet_charts_flutter

`jet_charts_flutter` is the Flutter backend of the jet_ chart family: it
measures and draws what `packages/jet_charts_core` lays out, and will hold the
`CustomPainter` renderer, the widget and interaction (milestone J3). It reads
and writes no file format. The records of the design are the repository root's
`docs/decisions/0014-chart-phase-and-drawingml-layer.md` and
`docs/decisions/0016-jet-charts-flutter-in-the-workspace.md`.

Milestone J3 is under way. The package exports `FlutterTextMeasurer`; the rest
of J3 adds to this file.

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
