/// The chart core of the jet_ packages: a chart model, a theme, axis scales,
/// layout and drawing primitives, in pure Dart.
///
/// It draws nothing itself. A backend (a Flutter painter, a PDF writer) draws
/// the primitives the layout produces, and `jet_office` writes the model as a
/// chart in an XLSX or DOCX file. The package depends on `jet_core` only.
///
/// Milestone J1 holds:
///
/// * the chart model: `Chart`, `ChartSeries`, `ChartData`, `ChartAxis`, the
///   title, legend and data label parts, and the kind and grouping enums;
/// * the theme: `ChartTheme`, `ChartColor` and its scheme colours, text
///   styles and export colours, with the Office theme as a built-in;
/// * the drawing primitives (`ChartPrimitive` and its rectangle, path, arc,
///   text and clip kinds) and the geometry they use;
/// * the `TextMeasurer` a backend supplies, and a `FixedWidthTextMeasurer`
///   for tests.
///
/// Milestone J2 adds the axis scales and the layout that turns a chart, a
/// theme and a size into primitives.
library;

export 'src/layout/geometry.dart' show ChartPoint, ChartRect, ChartSize;
export 'src/layout/primitives.dart'
    show
        ArcPrimitive,
        ChartPrimitive,
        ClipPrimitive,
        PathPrimitive,
        RectPrimitive,
        TextPrimitive;
export 'src/layout/text_measurer.dart'
    show FixedWidthTextMeasurer, TextMeasurer;
export 'src/model/chart.dart' show Chart;
export 'src/model/chart_axis.dart' show ChartAxis;
export 'src/model/chart_kind.dart'
    show ChartAxisBinding, ChartGrouping, ChartKind, ChartLegendPosition;
export 'src/model/chart_parts.dart'
    show ChartDataLabels, ChartLegend, ChartTitle;
export 'src/model/chart_series.dart' show ChartData, ChartSeries;
export 'src/scale/value_scale.dart'
    show ValueScale, autoValueScale, dataExtent, provisionalMaxIntervals;
export 'src/theme/chart_color.dart'
    show ChartColor, ChartExportColors, ChartSchemeColor, ChartTextStyle;
export 'src/theme/chart_spacing.dart' show ChartSpacing;
export 'src/theme/chart_theme.dart' show ChartTheme;
