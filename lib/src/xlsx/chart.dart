/// Charts on a sheet: [XlsxChart], a chart to add and the typed form of a
/// listed one, and [XlsxSheetChart], what `XlsxSheet.charts` lists.
///
/// Not ported from Quds; written for jet_office (milestone C2).
///
/// A chart is a `jet_charts_core` [Chart] placed by an [XlsxAnchor]; the
/// part it lives in (`xl/charts/chartN.xml`) is the DrawingML layer's. A
/// chart read from a part carries the part's axis and series ids privately,
/// so writing its typed form again keeps them; the model reads them through
/// [xlsxChartIds], which `lib/jet_office.dart` does not export.
///
/// @docImport 'model/xlsx_sheet.dart';
library;

import 'package:jet_charts_core/jet_charts_core.dart';

import '../drawingml/chart/chart_space.dart';
import 'drawing.dart';

/// A chart on a sheet: what it shows, where it sits and what its part holds
/// beyond the chart.
///
/// Value equality over every field. The ids of a chart read from a part are
/// not a field and take no part in equality.
final class XlsxChart {
  /// A chart showing [chart] at [anchor].
  ///
  /// [name] is the frame's name (`cNvPr` `name`) and [description] its
  /// alternative text. [theme] is the theme the part is written in, the
  /// Office theme when `null`, whose colours bind to the file's theme.
  /// [language] is the part's language and the language of its text, such
  /// as `en-US` or `tr-TR`. [autoTitle] asks for Excel's automatic title
  /// (the series name) when [chart] has no title.
  XlsxChart(
    this.chart,
    this.anchor, {
    this.name,
    this.description,
    ChartTheme? theme,
    this.language = 'en-US',
    this.autoTitle = false,
  }) : theme = theme ?? ChartTheme.office,
       _ids = null;

  XlsxChart._read(
    this.chart,
    this.anchor, {
    required this.name,
    required this.description,
    required this.language,
    required this.autoTitle,
    required DrawingChartIds ids,
  }) : theme = ChartTheme.office,
       _ids = ids;

  /// What the chart shows.
  final Chart chart;

  /// Where the chart sits on the sheet, in pixels as a picture's anchor.
  final XlsxAnchor anchor;

  /// The frame's name, or `null` for the default.
  final String? name;

  /// The frame's alternative text, or `null`.
  final String? description;

  /// The theme the part is written in.
  final ChartTheme theme;

  /// The language of the part and of its text.
  final String language;

  /// Whether the part shows Excel's automatic title when [chart] has no
  /// title.
  final bool autoTitle;

  /// The ids of the part this chart was read from, or `null`.
  final DrawingChartIds? _ids;

  @override
  bool operator ==(Object other) =>
      other is XlsxChart &&
      chart == other.chart &&
      anchor == other.anchor &&
      name == other.name &&
      description == other.description &&
      theme == other.theme &&
      language == other.language &&
      autoTitle == other.autoTitle;

  @override
  int get hashCode =>
      Object.hash(chart, anchor, name, description, theme, language, autoTitle);

  @override
  String toString() =>
      'XlsxChart($chart, $anchor, name: $name, language: $language)';
}

/// The typed form of a chart read from a part: [space]'s chart, language,
/// automatic title and ids, at [anchor] with the frame's [name] and
/// [description], in the Office theme.
XlsxChart readXlsxChart(
  DrawingChartSpace space,
  XlsxAnchor anchor, {
  required String name,
  required String? description,
}) => XlsxChart._read(
  space.chart,
  anchor,
  name: name,
  description: description,
  language: space.language,
  autoTitle: space.autoTitle,
  ids: space.ids,
);

/// The ids of the part [chart] was read from, or `null` for a chart made
/// with [XlsxChart.new].
DrawingChartIds? xlsxChartIds(XlsxChart chart) => chart._ids;

/// A chart frame of a sheet's drawing, as `XlsxSheet.charts` lists it.
///
/// Value equality over every field.
final class XlsxSheetChart {
  /// A listed chart at [anchor], called [name], showing [view], typed as
  /// [typed].
  const XlsxSheetChart(
    this.anchor,
    this.name, {
    this.description,
    this.view,
    this.typed,
  });

  /// Where the chart sits on the sheet.
  final XlsxAnchor anchor;

  /// The frame's name (`cNvPr` `name`), empty when it has none.
  final String name;

  /// The frame's alternative text (`cNvPr` `descr`), or `null`.
  final String? description;

  /// What the part shows, or `null` when it cannot be read (it is not a
  /// chart, or it is larger than `XlsxReadLimits.maxChartPartBytes`).
  final Chart? view;

  /// The chart in typed form, or `null` unless writing it again gives the
  /// part as it is: a kind the library writes, read in the Office theme.
  final XlsxChart? typed;

  @override
  bool operator ==(Object other) =>
      other is XlsxSheetChart &&
      anchor == other.anchor &&
      name == other.name &&
      description == other.description &&
      view == other.view &&
      typed == other.typed;

  @override
  int get hashCode => Object.hash(anchor, name, description, view, typed);

  @override
  String toString() =>
      'XlsxSheetChart($anchor, $name, view: $view, typed: ${typed != null})';
}
