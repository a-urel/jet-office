/// The data of a chart: [ChartData] and [ChartSeries].
library;

import '../theme/chart_color.dart';
import 'chart_kind.dart';
import 'equality.dart';

/// A list of values and, when they came from cells, where.
///
/// The values are always present, even when [reference] is: a file stores the
/// cached values beside the reference, and a chart draws the values.
final class ChartData<T extends Object> {
  /// Creates data from a copy of [values].
  ///
  /// An entry may be `null` (an empty cell), and a `double` may be `NaN` or
  /// infinite; the model carries them as read. [reference] is the formula
  /// text of the range (`c:f`), such as `Sheet1!$B$2:$B$9`.
  ChartData({required List<T?> values, this.reference})
    : values = List<T?>.unmodifiable(values);

  /// The values, in order. The list cannot be modified.
  final List<T?> values;

  /// The range the values were read from, or `null` when they are literal.
  final String? reference;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartData<T> copyWith({List<T?>? values, String? reference}) {
    return ChartData<T>(
      values: values ?? this.values,
      reference: reference ?? this.reference,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartData<Object> &&
        reference == other.reference &&
        listValueEquals(values, other.values);
  }

  @override
  int get hashCode => Object.hash(reference, listValueHash(values));

  @override
  String toString() => 'ChartData($values, reference: $reference)';
}

/// One series of a chart: a name, the categories and the values.
final class ChartSeries {
  /// Creates a series.
  ///
  /// [categories] hold `String`, `num` or `DateTime` entries. Their number
  /// and the number of [values] may differ. The categories are re-wrapped as
  /// an exact `ChartData<Object>` (values copied), so a `ChartData<String>`
  /// passed here does not make `categories.copyWith` throw by covariance.
  ///
  /// [color] is the series' own colour and [colorKey] names a colour of
  /// `ChartTheme.semantic`; `ChartTheme.colorOf` resolves them.
  ChartSeries({
    required this.name,
    required ChartData<Object> categories,
    required this.values,
    this.kind,
    this.axis = ChartAxisBinding.primary,
    this.formatCode,
    this.color,
    this.colorKey,
    this.smooth = false,
    List<ChartColor?> pointColors = const <ChartColor?>[],
  }) : pointColors = List<ChartColor?>.unmodifiable(pointColors),
       categories = ChartData<Object>(
         values: List<Object?>.of(categories.values),
         reference: categories.reference,
       );

  /// The series name, as a list of one entry.
  final ChartData<String> name;

  /// The category of each value.
  final ChartData<Object> categories;

  /// The value of each category.
  final ChartData<double> values;

  /// The kind this series is drawn as in a combination chart, or `null` to
  /// follow the chart.
  ///
  /// A combination chart draws [ChartKind.column], [ChartKind.line] and
  /// [ChartKind.area] series as such; a `null` kind, or any other, is drawn
  /// as a column. Other charts ignore it, but for a sparkline's area.
  final ChartKind? kind;

  /// The value axis the series is measured on.
  ///
  /// Column, line, area and combination charts measure a series bound to
  /// [ChartAxisBinding.secondary] on a second value axis on the plot's
  /// right, when some series is bound to the primary one; with none, every
  /// series is measured on the primary axis. A bar chart, as every other
  /// kind, measures every series on the primary axis.
  final ChartAxisBinding axis;

  /// The number format of the values, as the text Excel stores, or `null`.
  final String? formatCode;

  /// The colour of this series, or `null` to take it from the theme.
  final ChartColor? color;

  /// The name of a `ChartTheme.semantic` colour, or `null`.
  final String? colorKey;

  /// Whether the line is drawn as a curve (Excel's `c:smooth`).
  ///
  /// Used by line, combination line and scatter series; other kinds ignore
  /// it.
  final bool smooth;

  /// The colour of each point by index, `null` for automatic (Excel's
  /// `c:dPt`). The list cannot be modified.
  ///
  /// Used for a pie or donut slice, a bar and a marker. Beyond the end of
  /// the list a point's colour is automatic.
  final List<ChartColor?> pointColors;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartSeries copyWith({
    ChartData<String>? name,
    ChartData<Object>? categories,
    ChartData<double>? values,
    ChartKind? kind,
    ChartAxisBinding? axis,
    String? formatCode,
    ChartColor? color,
    String? colorKey,
    bool? smooth,
    List<ChartColor?>? pointColors,
  }) {
    return ChartSeries(
      name: name ?? this.name,
      categories: categories ?? this.categories,
      values: values ?? this.values,
      kind: kind ?? this.kind,
      axis: axis ?? this.axis,
      formatCode: formatCode ?? this.formatCode,
      color: color ?? this.color,
      colorKey: colorKey ?? this.colorKey,
      smooth: smooth ?? this.smooth,
      pointColors: pointColors ?? this.pointColors,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartSeries &&
        name == other.name &&
        categories == other.categories &&
        values == other.values &&
        kind == other.kind &&
        axis == other.axis &&
        formatCode == other.formatCode &&
        color == other.color &&
        colorKey == other.colorKey &&
        smooth == other.smooth &&
        listValueEquals(pointColors, other.pointColors);
  }

  @override
  int get hashCode => Object.hash(
    name,
    categories,
    values,
    kind,
    axis,
    formatCode,
    color,
    colorKey,
    smooth,
    listValueHash(pointColors),
  );

  @override
  String toString() => 'ChartSeries($name, $kind, $axis)';
}
