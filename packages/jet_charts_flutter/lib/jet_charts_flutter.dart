/// The Flutter backend of the jet_ chart family.
///
/// It measures and draws what `jet_charts_core` lays out: it exports
/// `FlutterTextMeasurer`, the `TextMeasurer` that measures with the
/// `TextPainter` the renderer paints with, `paintChartPrimitives`, which
/// paints a layout's primitives on a canvas, and `ChartLayoutPainter`, the
/// `CustomPainter` that does so.
library;

export 'src/chart_layout_painter.dart' show ChartLayoutPainter;
export 'src/primitive_painter.dart' show paintChartPrimitives;
export 'src/text_measurer.dart' show FlutterTextMeasurer;
