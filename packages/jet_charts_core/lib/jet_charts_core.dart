/// The chart core of the jet_ packages: a chart model, a theme, axis scales,
/// layout and drawing primitives, in pure Dart.
///
/// It draws nothing itself. A backend (a Flutter painter, a PDF writer) draws
/// the primitives the layout produces, and `jet_office` writes the model as a
/// chart in an XLSX or DOCX file. The package depends on `jet_core` only.
///
/// The theme and primitives are added by the milestone J1 tasks that follow.
library;

export 'src/model/chart.dart' show Chart;
export 'src/model/chart_axis.dart' show ChartAxis;
export 'src/model/chart_kind.dart'
    show ChartAxisBinding, ChartGrouping, ChartKind, ChartLegendPosition;
export 'src/model/chart_parts.dart'
    show ChartDataLabels, ChartLegend, ChartTitle;
export 'src/model/chart_series.dart' show ChartData, ChartSeries;
