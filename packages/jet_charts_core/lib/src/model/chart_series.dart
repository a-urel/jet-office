/// The data of a chart: [ChartData] and [ChartSeries].
library;

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
    return other is ChartData &&
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
  /// and the number of [values] may differ.
  const ChartSeries({
    required this.name,
    required this.categories,
    required this.values,
    this.kind,
    this.axis = ChartAxisBinding.primary,
    this.formatCode,
  });

  /// The series name, as a list of one entry.
  final ChartData<String> name;

  /// The category of each value.
  final ChartData<Object> categories;

  /// The value of each category.
  final ChartData<double> values;

  /// The kind this series is drawn as in a combination chart, or `null` to
  /// follow the chart.
  final ChartKind? kind;

  /// The value axis the series is measured on.
  final ChartAxisBinding axis;

  /// The number format of the values, as the text Excel stores, or `null`.
  final String? formatCode;

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
  }) {
    return ChartSeries(
      name: name ?? this.name,
      categories: categories ?? this.categories,
      values: values ?? this.values,
      kind: kind ?? this.kind,
      axis: axis ?? this.axis,
      formatCode: formatCode ?? this.formatCode,
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
        formatCode == other.formatCode;
  }

  @override
  int get hashCode =>
      Object.hash(name, categories, values, kind, axis, formatCode);

  @override
  String toString() => 'ChartSeries($name, $kind, $axis)';
}
