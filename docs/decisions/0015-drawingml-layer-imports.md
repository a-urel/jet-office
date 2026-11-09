# 0015 — What the DrawingML layer may import

**Status:** Accepted — 2026-11-09

Supersedes one sentence of [`0014`](0014-chart-phase-and-drawingml-layer.md),
the one that lists the imports of `lib/src/drawingml/`. Nothing else in `0014`
changes, and `0014` is not edited.

## Context

`0014` says the DrawingML layer "imports only the OPC layer, `package:xml` and
`lib/src/common/`". Two things in that sentence do not fit C1. The chart code
must read and write the `jet_charts_core` model, so it has to import that
package, which `0014` itself made a dependency from C1. And `package:xml` is a
test-only dependency here: the XML code of this repository is its own, in
`lib/src/xml/`, and the layer already imports it.

## Decision

**`lib/src/drawingml/` imports only `dart:` libraries, its own files,
`../opc/`, `../xml/`, `../common/`, `package:jet_charts_core/jet_charts_core.dart`
and `package:jet_core/jet_core.dart`.** It never imports `lib/src/xlsx/`,
`lib/src/docx/`, the public barrel, `package:archive` or the `src/` of any
package. Its types keep the prefix `Drawing`.

- The guard in `test/architecture/layering_test.dart` is an allow-list over
  every import and export of the layer, not a list of forbidden layers, so a
  new import has to be named here first.
- No file under `lib/` reaches into the `src/` of `jet_core` or
  `jet_charts_core`; their barrels are the only way in.
- `jet_charts_core` joins `archive` and `jet_core` as a runtime dependency of
  `jet_office`, as `0014` decided; the guard in
  `test/architecture/dependencies_test.dart` lists all three.

## Consequences

- A chart file under `lib/src/drawingml/` can use the chart model and the
  number format engine, and nothing of the two format layers.
- A layer import that is not in the list fails the architecture tests.
