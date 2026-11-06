# Working in jet_charts_core

`jet_charts_core` is the pure-Dart core of the jet_ chart family: the chart
model, the theme, axis scales, layout and drawing primitives. It draws nothing,
reads and writes no file format, and has no Flutter. Backends draw what it
lays out; `jet_office` writes and reads the model as a chart in XLSX and DOCX.
The design is `docs/superpowers/specs/2026-11-04-jet-charts-design.md` in the
repository root (git-ignored working notes), and the record is the root's
`docs/decisions/0014-chart-phase-and-drawingml-layer.md`.

At this stage the package exports nothing; the milestone J1 tasks add the
model, theme, primitives and text measurer.

## The packages

This repository is a pub workspace (decision 0013). The chart family:

| Package | Holds | Depends on |
|---|---|---|
| `jet_core` | number format engine, locale, what else two families share | pure Dart only |
| `jet_charts_core` | model, theme, scales, layout, primitives | `jet_core` |
| `jet_charts_flutter` | `CustomPainter` renderer, widget, text measurer, interaction | core, Flutter |
| `jet_office` (repository root) | `c:chartSpace` read and write, host adapters for XLSX, DOCX | `jet_core`, `jet_charts_core` (from C1, decision 0014) |
| `jet_print` (later) | PDF painter, its own measurer | core |

`jet_charts_core` must not depend on `jet_office`, or the two form a cycle.
What both need goes in `jet_core`. `jet_charts_flutter` is not created yet.

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
owner runs it. The results are committed under `test/fixtures/owner/axis/`; the
README there describes them, `TALIMATLAR.md` is the owner's steps, and
`docs/axis-scaling.md` holds the question and the findings.

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

`docs/excel-checks.md` lists the Office theme values Excel has not confirmed.

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

## Reference

Consumers: Monépro's dashboards first, then `jet_print` and `jet_office`.
`jet_charts_core` knows none of them.
