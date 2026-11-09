# 0016 — jet_charts_flutter is a member of the workspace

**Status:** Accepted — 2026-11-09

Adds to [`0013`](0013-one-repository-workspace.md), which put the chart
packages under `packages/` and asked `jet_charts_flutter` to try the workspace
first, and to [`0014`](0014-chart-phase-and-drawingml-layer.md), which created
`jet_charts_flutter` when J3 starts. It supersedes nothing.

## Context

Milestone J3 needs a Flutter package: the renderer, the widget, a text measurer
that uses `TextPainter`, and interaction. `0013` warned that a workspace has one
resolution, so a Flutter package in it brings Flutter's pinned versions to every
package, and said that if the pins hurt, the package stays in this repository
but outside the workspace.

The owner had it tried on 2026-11-09 with Flutter 3.47.9 (Dart 3.13.7):

- `packages/jet_charts_flutter` added to the root's `workspace:` list resolves
  with `flutter pub get` at the root.
- The root's `dart analyze --fatal-infos` and tests pass.
- Flutter's pins hold `test` at 1.31.1 (1.33 is the latest), which every
  package's `test: ^1.26.0` accepts. No other constraint of the workspace had to
  change.

The pins do not hurt, so the owner chose to keep the package in the workspace.

## Decision

**`packages/jet_charts_flutter` is a member of the root workspace, with
`resolution: workspace`, like `jet_core` and `jet_charts_core`.**

- **Dependencies.** Its runtime dependencies are `flutter`, `jet_charts_core`
  and `jet_core`, the last two by path. Its `lib/` uses Flutter's widgets layer
  and `dart:ui`, never `material.dart` or `cupertino.dart` (Monépro has its own
  design system) and never `dart:io` or `dart:html`. Its architecture tests
  enforce both.
- **The gate.** Its tests need Flutter's engine, so they run with
  `flutter test` and `flutter test --platform chrome`, from the package's
  folder, and join the root gate and CI. `dart format` and `dart analyze` at the
  root already see it.
- **Golden images run on macOS only.** Their pixels differ by platform. Golden
  tests carry the tag `golden`: the local gate on macOS runs them, and CI and
  the Chrome leg skip them with `--exclude-tags golden`. Layout correctness on
  every platform is proved by `jet_charts_core`'s text goldens.

## Consequences

- **Resolving the workspace needs Flutter's SDK.** `dart pub get` at the root,
  or in any package of it, fails with a Dart SDK that has no Flutter, because
  one member depends on `flutter`. The local gate uses Flutter's `dart`, and CI
  sets up Flutter 3.47.9 (`subosito/flutter-action`) in place of
  `dart-lang/setup-dart`. Every job that resolves the workspace moves.
- **Flutter's pins reach every package.** A later Flutter that pins a package
  below what a member needs is a reason to revisit this record; the way out is
  still `0013`'s, a package in this repository outside the workspace.
- **The boundaries of `0014` stand.** `jet_charts_core` and `jet_office` never
  import Flutter and never depend on `jet_charts_flutter`; their own guards
  keep that, and a shared resolution does not loosen them.
- Raising the Flutter version is a change of CI and of this repository's
  `AGENTS.md`, checked by the full gate.
