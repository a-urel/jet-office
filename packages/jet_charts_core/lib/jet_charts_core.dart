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
/// Milestone J2 adds:
///
/// * the value scale: `autoValueScale` chooses an axis' minimum, maximum and
///   major unit as Excel for Mac does, from a `dataExtent` and the axis'
///   length, and returns a `ValueScale`;
/// * the layout: `layoutChart` turns a chart, a theme, a size and a
///   `TextMeasurer` into a `ChartLayout` of primitives, with the
///   `ChartHiddenLabel`s it left out. The scheme of the primitives' ids is
///   documented on `ChartLayout.primitives`;
/// * the overlap check: `findOverlaps` reports each `ChartOverlap`, of a
///   `ChartOverlapKind`, between texts and marks of a layout.
///
/// Milestone J3 adds the Flutter renderer, in `jet_charts_flutter`; this
/// package stays free of Flutter. For it, this package adds:
///
/// * the ids read back: `ChartElementId.parse` reads a primitive's id into
///   its `ChartElementKind`, `ChartAxisRole`, series, category and index;
/// * hit testing: `hitTestLayout` returns the primitives under a point,
///   topmost first;
/// * category bands: `ChartLayout.categoryBands`, each category's slice of
///   the plot;
/// * tooltips: `chartTooltipAt` and `chartTooltipFor` give the
///   `ChartTooltip`, of `ChartTooltipRow`s, at a point or for a primitive,
///   and every text of `ChartLayout.hidden` stays within reach of one;
///   `ChartTheme.tooltip` holds its look, a `ChartTooltipStyle`;
/// * a data summary: `summarizeChart` gives a `ChartSummary`, the chart's
///   data as text for a screen reader or a data table.
///
/// Milestone J4 adds, with their Excel values estimates until the owner's
/// check:
///
/// * pie, donut, sparkline, scatter and combination charts laid out by
///   `layoutChart`, a series' own `kind` and `axis`, and `Chart`'s
///   `secondaryValueAxis`;
/// * smooth lines (`ChartSeries.smooth`), point colours
///   (`ChartSeries.pointColors`), percent data labels (`ChartDataLabels`'s
///   `showValue`, `showPercent` and `minShare`), a donut's
///   `Chart.holeSizePercent` and `Chart.centerText`, and the translucent
///   fills of `PathPrimitive.fillOpacity`;
/// * theme values `areaOpacity`, `areaLine`, `sliceBorderWidth`, `centerText`
///   and `sparklineWidth`, and `ChartTheme.fromColors`, an app's theme from
///   its palette, font and colours;
/// * after the owner's E1 file, theme values `leaderLine`,
///   `combinationLineMarkers`, `combinationGapWidthPercent`,
///   `scatterAxisLine` and `sliceLabelContrast`, and
///   `ChartTheme.lineMarkersOf`.
library;

export 'src/interaction/element_id.dart'
    show ChartAxisRole, ChartElementId, ChartElementKind;
export 'src/interaction/hit_test.dart' show hitTestLayout;
export 'src/interaction/summary.dart' show ChartSummary, summarizeChart;
export 'src/interaction/tooltip.dart'
    show ChartTooltip, ChartTooltipRow, chartTooltipAt, chartTooltipFor;
export 'src/layout/chart_layout.dart'
    show ChartHiddenLabel, ChartLayout, layoutChart;
export 'src/layout/geometry.dart' show ChartPoint, ChartRect, ChartSize;
export 'src/layout/overlap.dart'
    show ChartOverlap, ChartOverlapKind, findOverlaps;
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
export 'src/scale/value_scale.dart' show ValueScale, autoValueScale, dataExtent;
export 'src/theme/chart_color.dart'
    show ChartColor, ChartExportColors, ChartSchemeColor, ChartTextStyle;
export 'src/theme/chart_spacing.dart' show ChartSpacing;
export 'src/theme/chart_theme.dart' show ChartTheme;
export 'src/theme/chart_tooltip_style.dart' show ChartTooltipStyle;
