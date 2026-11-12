/// The typed form of a chart part: [DrawingChartSpace], a `jet_charts_core`
/// [Chart] with what a `c:chartSpace` part holds beyond it, and the names of
/// the part.
///
/// Not ported from Quds; written for jet_office.
///
/// Beyond the chart, the typed form carries the language of the part, the
/// axis ids (four with a secondary axis), each series' `c16:uniqueId` and
/// whether the chart shows Excel's automatic title (ruling R3 of C1). Everything else the writer writes is
/// fixed, as Excel for Mac writes it. A part read from a file is offered in
/// this form only when writing the form gives the part again.
///
/// This layer imports `opc`, `xml`, `common`, `jet_charts_core` and `jet_core`
/// only, never `xlsx` or `docx` (decisions 0014 and 0015).
library;

import 'package:jet_charts_core/jet_charts_core.dart';

/// The DrawingML chart namespace, the one of the `c:` prefix.
const String drawingChartNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/chart';

/// The content type of a chart part.
const String drawingChartContentType =
    'application/vnd.openxmlformats-officedocument.drawingml.chart+xml';

/// The type of the relationship from a drawing (or a document) to a chart
/// part.
const String drawingChartRelationshipType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart';

/// A `c16:uniqueId` value: a GUID in braces.
final RegExp _seriesId = RegExp(
  r'^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
  r'[0-9A-Fa-f]{12}\}$',
);

/// Whether [id] is a series id [DrawingChartIds] may hold: a GUID in braces,
/// such as `{00000000-8918-7940-9A01-4B67489FEBC8}`, in either case.
bool isDrawingChartSeriesId(String id) => _seriesId.hasMatch(id);

/// The ids a chart part gives its axes and series.
///
/// Excel picks the axis ids and the series' unique ids at random when it makes
/// a chart and keeps them when it saves; a part read back keeps the ones it
/// had. Value equality.
final class DrawingChartIds {
  /// Creates the ids. [series] is kept as given; it must not be modified
  /// afterwards.
  ///
  /// `series[i]` is the `c16:uniqueId` value of series `i`, with its braces
  /// (`{00000000-8918-7940-9A01-4B67489FEBC8}`); a series past the end of the
  /// list is written without a `c:extLst`.
  const DrawingChartIds({
    this.categoryAxis = 500000001,
    this.valueAxis = 500000002,
    this.secondaryCategoryAxis = 500000003,
    this.secondaryValueAxis = 500000004,
    this.series = const <String>[],
  });

  /// The `c:axId` of the category axis, or of a scatter chart's x axis.
  final int categoryAxis;

  /// The `c:axId` of the value axis, or of a scatter chart's y axis.
  final int valueAxis;

  /// The `c:axId` of the secondary category axis, written only for a chart
  /// with a secondary axis.
  final int secondaryCategoryAxis;

  /// The `c:axId` of the secondary value axis, written only for a chart with
  /// a secondary axis.
  final int secondaryValueAxis;

  /// The `c16:uniqueId` of each series, in series order.
  final List<String> series;

  @override
  bool operator ==(Object other) {
    if (other is! DrawingChartIds ||
        categoryAxis != other.categoryAxis ||
        valueAxis != other.valueAxis ||
        secondaryCategoryAxis != other.secondaryCategoryAxis ||
        secondaryValueAxis != other.secondaryValueAxis ||
        series.length != other.series.length) {
      return false;
    }
    for (int i = 0; i < series.length; i++) {
      if (series[i] != other.series[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    categoryAxis,
    valueAxis,
    secondaryCategoryAxis,
    secondaryValueAxis,
    Object.hashAll(series),
  );

  @override
  String toString() =>
      'DrawingChartIds($categoryAxis, $valueAxis, $secondaryCategoryAxis, '
      '$secondaryValueAxis, ${series.length} series)';
}

/// A chart part in typed form: the chart and what the part holds beyond it.
///
/// Value equality.
final class DrawingChartSpace {
  /// Creates the typed form of a part that shows [chart].
  ///
  /// [language] is the part's `c:lang` and the `lang` of its text, such as
  /// `en-US` or `tr-TR`. [autoTitle] asks for Excel's automatic title (a
  /// title without text, which Excel shows as the series name); it is ignored
  /// when [chart] has a title.
  DrawingChartSpace({
    required this.chart,
    this.language = 'en-US',
    this.ids = const DrawingChartIds(),
    this.autoTitle = false,
  });

  /// The chart the part shows.
  final Chart chart;

  /// The language of the part and of its text.
  final String language;

  /// The axis and series ids.
  final DrawingChartIds ids;

  /// Whether the part shows Excel's automatic title when [chart] has no
  /// title.
  final bool autoTitle;

  @override
  bool operator ==(Object other) =>
      other is DrawingChartSpace &&
      chart == other.chart &&
      language == other.language &&
      ids == other.ids &&
      autoTitle == other.autoTitle;

  @override
  int get hashCode => Object.hash(chart, language, ids, autoTitle);

  @override
  String toString() => 'DrawingChartSpace($chart, $language)';
}

/// A problem with a chart part's data that the writer or the reader got past.
///
/// Data problems are reported, never thrown; the hosts (an XLSX workbook, a
/// DOCX document) turn each into a warning of their own.
enum DrawingChartIssue {
  /// The part could not be read as a chart.
  unreadable,

  /// The part shows a kind of chart the model does not draw.
  unsupportedKind,

  /// A number in the part could not be read.
  badNumber,

  /// A value was `NaN` or infinite, and was left out.
  nonFiniteValue,

  /// Text held characters XML 1.0 forbids, and they were dropped.
  invalidCharacter,
}
