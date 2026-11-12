/// The series of a scatter group read back: their x values as categories
/// and their colour from the marker.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_reader.dart`, kept apart only to keep that file readable:
/// these are members of its reader, through a private extension.
///
/// The group's two value axes are read as any chart's category and value
/// axes, the first (Excel's x axis, at the bottom) as the category axis.
part of 'chart_reader.dart';

extension _ScatterReading on _ChartReader {
  /// A series of a scatter chart: as a line's (its `c:xVal` as categories,
  /// its `c:yVal` as values, a point colour from its marker), but its colour
  /// is its marker's fill, as its line has none (Excel's markers only,
  /// `chart_reference_j4.xlsx` chart 4), and reads as automatic when it is
  /// the one the writer derives for its [index].
  ChartSeries _readScatterSeries(_Node node, int index) {
    final ChartSeries series = _readSeries(node, index, lines: true);
    final ChartColor? color = _seriesColor(
      node.child('marker')?.child('spPr'),
      index,
      lines: false,
    );
    return ChartSeries(
      name: series.name,
      categories: series.categories,
      values: series.values,
      formatCode: series.formatCode,
      color: color,
      smooth: series.smooth,
      pointColors: series.pointColors,
    );
  }
}
