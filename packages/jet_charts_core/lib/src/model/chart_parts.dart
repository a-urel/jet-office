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
  ///
  /// [showValue] and [showPercent] choose what a visible label says; with
  /// both `false` no label is drawn even when [visible].
  ///
  /// [minShare] must be finite and within 0 to 1. This constructor is const
  /// and cannot check it; [copyWith] and the `Chart` constructor throw an
  /// [ArgumentError] for any other value.
  const ChartDataLabels({
    this.visible = false,
    this.formatCode,
    this.showValue = true,
    this.showPercent = false,
    this.minShare = 0,
  });

  /// Whether the labels are drawn.
  final bool visible;

  /// The number format of the labels, as the text Excel stores, or `null` to
  /// follow the data.
  final String? formatCode;

  /// Whether a label shows the value.
  final bool showValue;

  /// Whether a label shows the share of the whole as a percent.
  ///
  /// Used by pie and donut charts only, as Excel allows it only there.
  final bool showPercent;

  /// The least share of the whole, a fraction from 0 to 1, that a pie or
  /// donut slice must have to get a label.
  ///
  /// A slice below it gets no label at all (it is not listed as hidden; its
  /// tooltip still shows the value). Other kinds ignore it. It is not an
  /// Excel option but a choice for the screen, so a file does not carry it.
  final double minShare;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value. Throws an [ArgumentError] for a [minShare] that is not
  /// finite or not within 0 to 1.
  ChartDataLabels copyWith({
    bool? visible,
    String? formatCode,
    bool? showValue,
    bool? showPercent,
    double? minShare,
  }) {
    if (minShare != null) {
      checkMinShare(minShare);
    }
    return ChartDataLabels(
      visible: visible ?? this.visible,
      formatCode: formatCode ?? this.formatCode,
      showValue: showValue ?? this.showValue,
      showPercent: showPercent ?? this.showPercent,
      minShare: minShare ?? this.minShare,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartDataLabels &&
        visible == other.visible &&
        formatCode == other.formatCode &&
        showValue == other.showValue &&
        showPercent == other.showPercent &&
        minShare == other.minShare;
  }

  @override
  int get hashCode =>
      Object.hash(visible, formatCode, showValue, showPercent, minShare);

  @override
  String toString() =>
      'ChartDataLabels(visible: $visible, $formatCode, '
      'showValue: $showValue, showPercent: $showPercent, '
      'minShare: $minShare)';
}

/// Throws an [ArgumentError] unless [minShare], a `ChartDataLabels.minShare`,
/// is finite and within 0 to 1.
void checkMinShare(double minShare) {
  if (!minShare.isFinite || minShare < 0 || minShare > 1) {
    throw ArgumentError.value(
      minShare,
      'minShare',
      'must be finite and within 0 to 1',
    );
  }
}
