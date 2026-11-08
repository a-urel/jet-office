# Changelog

## 0.1.0-dev.3

- J2: `autoValueScale`, `ValueScale` and `dataExtent`, the value axis as Excel
  for Mac chooses it, fitted on the owner's full axis oracle.
- J2: `layoutChart`, `ChartLayout` and `ChartHiddenLabel`: column, bar, line
  and area charts of every grouping laid out as drawing primitives, with
  titles, legend, data labels, and category labels that turn, skip or cut.
- J2: `findOverlaps`, `ChartOverlap` and `ChartOverlapKind`.
- A layout fuzz test and `tool/fuzz_layout.dart`, golden layouts, an SVG
  gallery (`tool/write_gallery.dart`) and `docs/parity.md`.
- Fixed the dartdoc of `excelMaxIntervals` for a font size of 0 on a vertical
  axis.

## 0.1.0-dev.2

- Set up the package: `jet_core` as the only dependency, architecture
  guards, quality gate.
- J1: the chart model, the theme (with the Office theme), the drawing
  primitives and geometry, and the text measurer, all exported by
  `package:jet_charts_core/jet_charts_core.dart` with explicit `show` lists.
  The first Excel axis oracle is committed; its results await the owner's run.
  Scales and layout follow in J2.
- `ChartData.==` compares `ChartData` of any type argument symmetrically.
