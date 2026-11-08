# Working in jet_charts_core

`jet_charts_core` is the pure-Dart core of the jet_ chart family: the chart
model, the theme, axis scales, layout and drawing primitives. It draws nothing,
reads and writes no file format, and has no Flutter. Backends draw what it
lays out; `jet_office` writes and reads the model as a chart in XLSX and DOCX.
The record of the design is the repository root's
`docs/decisions/0014-chart-phase-and-drawingml-layer.md`.

Milestone J1 is done, and the axis oracle's owner run is recorded
(`docs/axis-scaling.md`, "Findings"): the package exports the model, the theme, the drawing primitives and the text
measurer. Scales and layout are J2.

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
  code is the part `tool/src/axis_oracle_full.dart`. `test/axis_oracle_test.dart`
  checks it as it checks the first; the first oracle's files stay as committed.

`docs/excel-checks.md` lists the Office theme values Excel's default charts
confirmed and those still unconfirmed; `docs/parity.md` compares layout with
Excel and lists every deliberate difference.

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

## Open for J2 and C1

- A series has no colour or semantic key, so `ChartTheme.semantic` has no
  consumer and a file's series fill has nowhere to go.
- The theme has colours but no line widths or dash for grid and axis, and no
  spacing, tooltip or legend look. The design spec asks for them; the spec is
  not tracked.
- A scheme colour cannot carry `lumMod` or `lumOff`, so text, grid, and series
  7 and up are fixed RGB even in the Office theme.
- `ArcPrimitive` has no `strokeWidth`.
- `TextPrimitive` must define what `rect` means under rotation before the
  overlap check.
- `ChartData<String>` used as `categories` can throw on `copyWith` with
  `Object?` values, by covariance.

## Reference

Consumers: Monépro's dashboards first, then `jet_print` and `jet_office`.
`jet_charts_core` knows none of them.
