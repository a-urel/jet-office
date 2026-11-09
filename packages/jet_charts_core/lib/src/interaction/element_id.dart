/// The public reading of the ids layout gives its primitives: a
/// [ChartElementId] names what a primitive is a part of.
///
/// The scheme is stated on `ChartLayout.primitives` and written by
/// `lib/src/layout/chart_ids.dart`; [ChartElementId.parse] is its exact
/// inverse. The three change together.
library;

import '../layout/chart_ids.dart' as ids;

/// What kind of chart element an id names.
enum ChartElementKind {
  /// The chart's background rectangle, `background`.
  background,

  /// The chart title, `title`.
  title,

  /// The legend's rectangle, `legend`.
  legend,

  /// The symbol of a series' legend entry, `legend/<s>/symbol`, or the
  /// marker on a line series' legend line, `legend/<s>/marker`.
  legendSymbol,

  /// The text of a series' legend entry, `legend/<s>/text`.
  legendText,

  /// The plot area's rectangle, `plot`.
  plot,

  /// The clip that holds the series marks, `plot/clip`.
  plotClip,

  /// The text of a kind the layout does not draw, `placeholder`.
  placeholder,

  /// An axis line, `axis/<a>/line`.
  axisLine,

  /// An axis label, `axis/<a>/label/<i>`: a value axis' tick label or a
  /// category axis' category label.
  axisLabel,

  /// An axis title, `axis/<a>/title`.
  axisTitle,

  /// A grid line, `grid/<a>/<i>`.
  gridLine,

  /// A column or bar, `series/<s>/bar/<c>`.
  bar,

  /// A run of a series' line, `series/<s>/line/<run>`.
  line,

  /// A marker, `series/<s>/marker/<c>`.
  marker,

  /// A series' area, `series/<s>/area`.
  area,

  /// A data label, `label/<s>/<c>`.
  dataLabel,
}

/// Which axis an id names.
enum ChartAxisRole {
  /// The value axis, `value` in an id.
  value,

  /// The category axis, `category` in an id.
  category,
}

/// An id of a primitive of a `ChartLayout`, read into its parts.
///
/// Only [parse] makes one, so every instance holds an id of the scheme that
/// `ChartLayout.primitives` describes. Two are equal when their ids are.
final class ChartElementId {
  const ChartElementId._(
    this.id,
    this.kind, {
    this.axis,
    this.series,
    this.category,
    this.index,
  });

  /// The id as the layout wrote it.
  final String id;

  /// What the id names.
  final ChartElementKind kind;

  /// The axis of an axis line, label or title, or a grid line; `null` for
  /// every other kind.
  final ChartAxisRole? axis;

  /// The series of a legend entry, a mark or a data label; `null` for every
  /// other kind.
  final int? series;

  /// The category of a bar, a marker, a data label or a category axis label;
  /// `null` for every other kind. For a category axis label it equals
  /// [index].
  final int? category;

  /// The index of an axis label (a value axis' tick from its minimum, a
  /// category axis' category), a grid line or a line run; `null` for every
  /// other kind.
  final int? index;

  /// Reads [id] into its parts, or returns `null` when it is not an id of the
  /// scheme that `ChartLayout.primitives` describes.
  ///
  /// This is the exact inverse of that scheme (written by
  /// `lib/src/layout/chart_ids.dart`): every id the layout gives parses, and
  /// any other string does not. An index is a decimal number of digits only,
  /// as the layout writes it: no sign, no leading zero (except `0` itself),
  /// and no number too large to write back the same. An unknown part, a
  /// missing or an extra one gives `null`.
  static ChartElementId? parse(String id) {
    final List<String> parts = id.split('/');
    switch (parts) {
      case [ids.background]:
        return ChartElementId._(id, ChartElementKind.background);
      case [ids.title]:
        return ChartElementId._(id, ChartElementKind.title);
      case [ids.legend]:
        return ChartElementId._(id, ChartElementKind.legend);
      case [ids.plot]:
        return ChartElementId._(id, ChartElementKind.plot);
      case [ids.placeholder]:
        return ChartElementId._(id, ChartElementKind.placeholder);
      case [ids.plot, 'clip']:
        return ChartElementId._(id, ChartElementKind.plotClip);
      case ['legend', final String s, final String part]:
        final int? series = _index(s);
        final ChartElementKind? kind = switch (part) {
          'symbol' || 'marker' => ChartElementKind.legendSymbol,
          'text' => ChartElementKind.legendText,
          _ => null,
        };
        return series == null || kind == null
            ? null
            : ChartElementId._(id, kind, series: series);
      case ['axis', final String a, 'line']:
        final ChartAxisRole? axis = _axis(a);
        return axis == null
            ? null
            : ChartElementId._(id, ChartElementKind.axisLine, axis: axis);
      case ['axis', final String a, 'title']:
        final ChartAxisRole? axis = _axis(a);
        return axis == null
            ? null
            : ChartElementId._(id, ChartElementKind.axisTitle, axis: axis);
      case ['axis', final String a, 'label', final String i]:
        final ChartAxisRole? axis = _axis(a);
        final int? index = _index(i);
        return axis == null || index == null
            ? null
            : ChartElementId._(
                id,
                ChartElementKind.axisLabel,
                axis: axis,
                index: index,
                category: axis == ChartAxisRole.category ? index : null,
              );
      case ['grid', final String a, final String i]:
        final ChartAxisRole? axis = _axis(a);
        final int? index = _index(i);
        return axis == null || index == null
            ? null
            : ChartElementId._(
                id,
                ChartElementKind.gridLine,
                axis: axis,
                index: index,
              );
      case ['series', final String s, 'area']:
        final int? series = _index(s);
        return series == null
            ? null
            : ChartElementId._(id, ChartElementKind.area, series: series);
      case ['series', final String s, final String mark, final String i]:
        final int? series = _index(s);
        final int? n = _index(i);
        if (series == null || n == null) {
          return null;
        }
        return switch (mark) {
          'bar' => ChartElementId._(
            id,
            ChartElementKind.bar,
            series: series,
            category: n,
          ),
          'marker' => ChartElementId._(
            id,
            ChartElementKind.marker,
            series: series,
            category: n,
          ),
          'line' => ChartElementId._(
            id,
            ChartElementKind.line,
            series: series,
            index: n,
          ),
          _ => null,
        };
      case ['label', final String s, final String c]:
        final int? series = _index(s);
        final int? category = _index(c);
        return series == null || category == null
            ? null
            : ChartElementId._(
                id,
                ChartElementKind.dataLabel,
                series: series,
                category: category,
              );
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ChartElementId &&
      id == other.id &&
      kind == other.kind &&
      axis == other.axis &&
      series == other.series &&
      category == other.category &&
      index == other.index;

  @override
  int get hashCode => Object.hash(id, kind, axis, series, category, index);

  @override
  String toString() => 'ChartElementId($id)';
}

/// The axis named [part] in an id, or `null`.
ChartAxisRole? _axis(String part) => switch (part) {
  ids.valueAxis => ChartAxisRole.value,
  ids.categoryAxis => ChartAxisRole.category,
  _ => null,
};

/// The index [part] writes, or `null` unless it is the layout's own writing
/// of a number: decimal digits, no leading zero, and written back the same
/// (a number too large for an `int`, or on the web for a double's exact
/// range, is not).
int? _index(String part) {
  if (!_digits.hasMatch(part)) {
    return null;
  }
  final int? value = int.tryParse(part);
  return value != null && '$value' == part ? value : null;
}

final RegExp _digits = RegExp(r'^(0|[1-9][0-9]*)$');
