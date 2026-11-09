/// The look of a chart's tooltip.
library;

import 'chart_color.dart';

/// The look of the box a backend shows a tooltip in: its fill, its border,
/// its text and the space between the text and the border.
///
/// The core only describes the look; a backend draws the box.
final class ChartTooltipStyle {
  /// Creates a tooltip style.
  ///
  /// Throws an [ArgumentError] when [padding] is negative or not finite.
  ChartTooltipStyle({
    required this.background,
    required this.border,
    required this.text,
    required this.padding,
  }) {
    if (!padding.isFinite || padding < 0) {
      throw ArgumentError.value(
        padding,
        'padding',
        'must be finite and not negative',
      );
    }
  }

  /// The colour that fills the box.
  final ChartColor background;

  /// The colour of the box's border.
  final ChartColor border;

  /// The text of the title and the rows.
  final ChartTextStyle text;

  /// The space between the text and the border on every side, in points.
  final double padding;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value. Throws an [ArgumentError] as the constructor does.
  ChartTooltipStyle copyWith({
    ChartColor? background,
    ChartColor? border,
    ChartTextStyle? text,
    double? padding,
  }) {
    return ChartTooltipStyle(
      background: background ?? this.background,
      border: border ?? this.border,
      text: text ?? this.text,
      padding: padding ?? this.padding,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartTooltipStyle &&
        background == other.background &&
        border == other.border &&
        text == other.text &&
        padding == other.padding;
  }

  @override
  int get hashCode => Object.hash(background, border, text, padding);

  @override
  String toString() =>
      'ChartTooltipStyle($background, $border, $text, padding: $padding)';
}
