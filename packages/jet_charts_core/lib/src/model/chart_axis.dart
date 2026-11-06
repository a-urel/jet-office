/// The axis of a chart.
library;

import 'equality.dart';

/// How one axis looks and which range it covers.
final class ChartAxis {
  /// Creates an axis. A `null` [min], [max] or [majorUnit] means automatic.
  const ChartAxis({
    this.title,
    this.min,
    this.max,
    this.majorUnit,
    this.formatCode,
    this.visible = true,
    this.gridLines = false,
  });

  /// The axis title, or `null` for none.
  final String? title;

  /// The lowest value shown, or `null` to choose it from the data.
  final double? min;

  /// The highest value shown, or `null` to choose it from the data.
  final double? max;

  /// The distance between two major ticks, or `null` to choose it.
  final double? majorUnit;

  /// The number format of the tick labels, as the text Excel stores, or
  /// `null` to follow the data.
  final String? formatCode;

  /// Whether the axis is drawn.
  final bool visible;

  /// Whether major grid lines are drawn.
  final bool gridLines;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartAxis copyWith({
    String? title,
    double? min,
    double? max,
    double? majorUnit,
    String? formatCode,
    bool? visible,
    bool? gridLines,
  }) {
    return ChartAxis(
      title: title ?? this.title,
      min: min ?? this.min,
      max: max ?? this.max,
      majorUnit: majorUnit ?? this.majorUnit,
      formatCode: formatCode ?? this.formatCode,
      visible: visible ?? this.visible,
      gridLines: gridLines ?? this.gridLines,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartAxis &&
        title == other.title &&
        valueEquals(min, other.min) &&
        valueEquals(max, other.max) &&
        valueEquals(majorUnit, other.majorUnit) &&
        formatCode == other.formatCode &&
        visible == other.visible &&
        gridLines == other.gridLines;
  }

  @override
  int get hashCode => Object.hash(
    title,
    valueHash(min),
    valueHash(max),
    valueHash(majorUnit),
    formatCode,
    visible,
    gridLines,
  );

  @override
  String toString() {
    return 'ChartAxis(title: $title, min: $min, max: $max, '
        'majorUnit: $majorUnit, formatCode: $formatCode, '
        'visible: $visible, gridLines: $gridLines)';
  }
}
