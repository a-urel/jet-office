# Changelog

## 0.1.0-dev.2

- Set up the package: `jet_core` as the only dependency, architecture
  guards, quality gate.
- J1: the chart model, the theme (with the Office theme), the drawing
  primitives and geometry, and the text measurer, all exported by
  `package:jet_charts_core/jet_charts_core.dart` with explicit `show` lists.
  The first Excel axis oracle is committed; its results await the owner's run.
  Scales and layout follow in J2.
- `ChartData.==` compares `ChartData` of any type argument symmetrically.
