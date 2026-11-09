# jet_charts_flutter

The Flutter backend of the jet_ chart family. It measures and draws what
`jet_charts_core` lays out, so a chart on screen shows the same data, axes and
colours as the same chart exported to XLSX or DOCX by `jet_office`.

It depends on `flutter`, `jet_charts_core` and `jet_core` only, and uses
Flutter's widgets layer, not Material or Cupertino, so an app's own design
system decides the rest.

## Status

Milestone J3 is under way. The package exports `FlutterTextMeasurer`, the
`TextMeasurer` that measures with the `TextPainter` the renderer paints with.
The renderer, the widget and interaction follow.

The package is a member of the repository's pub workspace (decisions 0013 and
0016 in the repository root's `docs/decisions/`).
