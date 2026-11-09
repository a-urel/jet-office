# jet_charts_flutter

The Flutter backend of the jet_ chart family. It measures and draws what
`jet_charts_core` lays out, so a chart on screen shows the same data, axes and
colours as the same chart exported to XLSX or DOCX by `jet_office`.

It depends on `flutter`, `jet_charts_core` and `jet_core` only, and uses
Flutter's widgets layer, not Material or Cupertino, so an app's own design
system decides the rest.

## Status

Milestone J3 is done. The package exports `FlutterTextMeasurer` (the
`TextMeasurer` that measures with the `TextPainter` the renderer paints with),
`paintChartPrimitives` and `ChartLayoutPainter`, and the widget `JetChart`:
loading, empty and error states in English, Turkish and German, a screen
reader description, hover and touch tooltips (`onHover`, `onTap`), light
animation of marks when the data changes, and reduced motion. `example/` is a
gallery app for comparing the charts with Excel for Mac.

The package is a member of the repository's pub workspace (decisions 0013 and
0016 in the repository root's `docs/decisions/`).
