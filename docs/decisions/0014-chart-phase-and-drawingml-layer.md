# 0014 — The chart phase: jet_charts_core, and a DrawingML layer in jet_office

**Status:** Accepted — 2026-11-06

Adds to [`0009`](0009-phase-3-workbook-model.md) and
[`0010`](0010-phase-4-docx-document-model.md), which left native charts to a
later phase, and follows [`0012`](0012-jet-core-and-new-dependencies.md) and
[`0013`](0013-one-repository-workspace.md). It contradicts none of them.

## Context

Monépro's dashboards do not have the chart quality the owner is used to from
Office applications. A survey found no library that does Excel's automatic
axis range, Excel number format codes, collision-free labels or native chart
export to XLSX and DOCX: `fl_chart` has no combination chart, no secondary
axis and no legend, and Syncfusion is the closest to Excel but commercial,
with a free licence that has revenue, headcount and funding limits, and is not
open source. The owner chose to build a chart family of our own, so that a
chart on a screen and the same chart exported to a file show the same data,
axes and colours. The design is
`docs/superpowers/specs/2026-11-04-jet-charts-design.md`, git-ignored working
notes; this record keeps what must outlive them.

Status today: no chart code exists in `jet_office`. `packages/jet_charts_core`
is set up and exports nothing. `jet_office` has no drawing layer. A chart in
an opened file is a part this library keeps and does not read, and a chart is
a picture in a DOCX until the work below is done (`0010`).

## Decision

**There is a chart phase. Its core is a new package, `jet_charts_core`, under
`packages/`. `jet_office` gets a DrawingML layer and, from C1, writes and
reads charts with it.**

- **Milestones.** The J milestones build the chart family: J1 the core
  package (model, theme, drawing primitives, a text measurer interface, a
  first axis oracle run), J2 scales and layout with the collision rules, J3
  the Flutter renderer and widget, J4 the full set of kinds, J5 Monépro's
  charts moved. The C milestones are in `jet_office`: C1 the DrawingML layer
  and `c:chartSpace` read and write, C2 the XLSX host, C3 the DOCX host with
  an embedded workbook. C may start after J2.
- **Packages and boundaries.** `jet_core` holds what the families share and
  knows no file format. `jet_charts_core` is pure Dart and web-safe, depends
  on `jet_core` only, and holds the model, theme, scales, layout and
  primitives; it draws nothing. `jet_charts_flutter`, later, holds the
  `CustomPainter` renderer, the widget, the text measurer and interaction,
  and depends on the core and Flutter; `0013` says where it lives if
  Flutter's pins hurt the workspace. `jet_office` depends on `jet_core` and,
  from C1, on `jet_charts_core`, and never on `jet_charts_flutter`.
  `jet_charts_core` never depends on `jet_office`. Format codes are strings
  in the model.
- **Why not `fl_chart` or Syncfusion.** `fl_chart` lacks the combination
  chart, the secondary axis, the legend and label collision handling, and
  Monépro's workarounds for it are the source of several visible faults.
  Syncfusion is not open source and its free licence is bounded. Neither
  exports a chart to XLSX or DOCX.
- **Two anti-goals.** A chart fails if labels, lines or shapes overlap in
  unwanted ways, or if it differs clearly in look or behaviour from Office.
  Both are testable requirements: layout emits primitives, and a function
  over them reports intersecting text and text outside the chart.
- **Excel is the oracle**, as in `0008` and `0012`. Axis range and major
  unit are read from Excel by script; the owner commits the results, a test
  in the gate compares them, known differences are recorded with reasons,
  and Excel wins. Size and font are inputs to scaling until the first oracle
  run says they do not matter. On screen, no overlap beats matching Excel,
  and each such difference is recorded as deliberate; in an exported file,
  placement is Excel's.
- **The theme's export rule.** One `ChartTheme` travels to every output. The
  theme decides how colours are exported: the Office theme binds to the
  file's theme (`schemeClr`), and an app's theme defaults to fixed colours,
  which touch nothing else in the file and open as the chart looks on screen.
- **A DrawingML layer in `jet_office`.** It is `lib/src/drawingml/`, a
  layer shared by XLSX and DOCX that knows neither, as the OPC layer does. It
  imports only the OPC layer, `package:xml` and `lib/src/common/`, never
  anything under `lib/src/xlsx/` or `lib/src/docx/`, and its types carry the
  prefix `Drawing`. The first slice is `picture.dart`, the `pic` and `blip`
  elements (`DrawingPic`), written by the workbook model's picture work and
  shared with the DOCX milestone D5. The charts' `c:chartSpace` work (C1)
  builds on the same layer. A test will hold the layer's imports when it
  exists.
- **Opened charts are kept as bytes.** `c:chartSpace` is read and written,
  but a chart from an opened file is kept byte for byte, and is typed only if
  writing the typed form back reproduces it. Series references stay
  qualified as Excel writes them. This is the fidelity standard of `0009`
  and `0010`; a library that rebuilds a chart on save makes a chart from
  Excel come back simpler, and that is not accepted.
- **The dependency arrives with C1.** `0012` foresaw that `jet_office`'s
  runtime dependencies would grow by `jet_charts_core`. This record is the
  decision it asked for. `pubspec.yaml` and `test/architecture/dependencies_test.dart`
  of `jet_office` change when C1 lands, not now: today the list stays
  `archive` and `jet_core`.

## Consequences

- `packages/jet_charts_core` is in the workspace and in CI (its tests on the
  VM and in Chrome), with the same gate as `jet_core`. Its guard tests keep it
  free of `dart:io`, `dart:ui`, `dart:html`, Flutter and any package but
  `jet_core`.
- The owner compares a fixed gallery, screen against Excel for Mac, per
  milestone, and records it in `docs/excel-checks.md`, as for the workbook
  model.
- `jet_charts_flutter` has no package yet; it is created when J3 starts.
- Nothing here changes `jet_office`'s behaviour today. A chart in a DOCX stays
  a picture, and a chart in an XLSX stays a kept part, until C2 and C3.
- PPTX, PDF output (`jet_print`), 3D charts and the Office 2016 `cx:` kinds
  are not decided here; a PPTX host would need its own record superseding
  part of `0001`.
