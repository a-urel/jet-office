/// The Flutter backend of the jet_ chart family.
///
/// It measures and draws what `jet_charts_core` lays out: it exports
/// `FlutterTextMeasurer`, the `TextMeasurer` that measures with the
/// `TextPainter` the renderer paints with, `paintChartPrimitives`, which
/// paints a layout's primitives on a canvas, and `ChartLayoutPainter`, the
/// `CustomPainter` that does so, and `JetChart`, the widget that lays a
/// chart out at its size and paints it, with its loading, empty and error
/// looks, its texts in `JetChartStrings`, a description for screen
/// readers, and hover, touch and a tooltip box, whose hits it reports as a
/// `JetChartHit`.
library;

export 'src/chart_layout_painter.dart' show ChartLayoutPainter;
export 'src/interaction.dart' show JetChartHit, JetChartTooltipLines;
export 'src/jet_chart.dart'
    show JetChart, JetChartErrorBuilder, JetChartStateBuilder;
export 'src/primitive_painter.dart' show paintChartPrimitives;
export 'src/strings.dart' show JetChartStrings;
export 'src/text_measurer.dart' show FlutterTextMeasurer;
