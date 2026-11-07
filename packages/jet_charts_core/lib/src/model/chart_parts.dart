/// The title, legend and data labels of a chart.
library;

import 'chart_kind.dart';

/// The title of a chart.
final class ChartTitle {
  /// Creates a title with [text].
  const ChartTitle({required this.text});

  /// The title's text.
  final String text;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartTitle copyWith({String? text}) => ChartTitle(text: text ?? this.text);

  @override
  bool operator ==(Object other) => other is ChartTitle && text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ChartTitle($text)';
}

/// The legend of a chart.
final class ChartLegend {
  /// Creates a legend, at the bottom and shown unless told otherwise.
  const ChartLegend({
    this.position = ChartLegendPosition.bottom,
    this.visible = true,
  });

  /// Where the legend sits.
  final ChartLegendPosition position;

  /// Whether the legend is drawn.
  final bool visible;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartLegend copyWith({ChartLegendPosition? position, bool? visible}) {
    return ChartLegend(
      position: position ?? this.position,
      visible: visible ?? this.visible,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartLegend &&
        position == other.position &&
        visible == other.visible;
  }

  @override
  int get hashCode => Object.hash(position, visible);

  @override
  String toString() => 'ChartLegend($position, visible: $visible)';
}

/// The value labels drawn on the data points of a chart.
final class ChartDataLabels {
  /// Creates data labels, hidden unless told otherwise.
  const ChartDataLabels({this.visible = false, this.formatCode});

  /// Whether the labels are drawn.
  final bool visible;

  /// The number format of the labels, as the text Excel stores, or `null` to
  /// follow the data.
  final String? formatCode;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartDataLabels copyWith({bool? visible, String? formatCode}) {
    return ChartDataLabels(
      visible: visible ?? this.visible,
      formatCode: formatCode ?? this.formatCode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartDataLabels &&
        visible == other.visible &&
        formatCode == other.formatCode;
  }

  @override
  int get hashCode => Object.hash(visible, formatCode);

  @override
  String toString() => 'ChartDataLabels(visible: $visible, $formatCode)';
}
