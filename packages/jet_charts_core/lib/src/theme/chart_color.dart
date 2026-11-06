/// Colours and text styles of a chart theme.
library;

/// A slot of a file's colour theme, named as DrawingML names them.
///
/// A [ChartColor] bound to a slot is exported as `schemeClr`, so the chart
/// follows the theme of the file that holds it.
enum ChartSchemeColor {
  /// The first dark colour, normally text.
  dark1,

  /// The first light colour, normally the background.
  light1,

  /// The second dark colour.
  dark2,

  /// The second light colour.
  light2,

  /// The first accent colour.
  accent1,

  /// The second accent colour.
  accent2,

  /// The third accent colour.
  accent3,

  /// The fourth accent colour.
  accent4,

  /// The fifth accent colour.
  accent5,

  /// The sixth accent colour.
  accent6,
}

/// How a theme's colours are exported to a file.
enum ChartExportColors {
  /// Every colour is written as a fixed RGB value, so the chart opens as it
  /// looks on screen and touches nothing else in the file.
  fixed,

  /// A colour bound to a [ChartSchemeColor] is written as a reference to the
  /// file's theme, so the chart follows that theme.
  fileTheme,
}

/// An opaque colour: an RGB value, optionally bound to a theme slot.
final class ChartColor {
  const ChartColor._(this.rgb, this.slot);

  /// A fixed colour of [rgb], the red, green and blue channels as
  /// `0xRRGGBB`.
  ///
  /// Throws an [ArgumentError] when [rgb] is outside `0` to `0xFFFFFF`.
  factory ChartColor.rgb(int rgb) {
    _check(rgb);
    return ChartColor._(rgb, null);
  }

  /// A colour bound to [slot] of the file's theme, drawn as [rgb] until a file
  /// theme says otherwise.
  ///
  /// Throws an [ArgumentError] when [rgb] is outside `0` to `0xFFFFFF`.
  factory ChartColor.scheme(ChartSchemeColor slot, {required int rgb}) {
    _check(rgb);
    return ChartColor._(rgb, slot);
  }

  static void _check(int rgb) {
    if (rgb < 0 || rgb > 0xFFFFFF) {
      throw ArgumentError.value(rgb, 'rgb', 'must be within 0 to 0xFFFFFF');
    }
  }

  /// The colour as `0xRRGGBB`, the value to draw with.
  final int rgb;

  /// The theme slot the colour is bound to, or `null` for a fixed colour.
  final ChartSchemeColor? slot;

  @override
  bool operator ==(Object other) {
    return other is ChartColor && rgb == other.rgb && slot == other.slot;
  }

  @override
  int get hashCode => Object.hash(rgb, slot);

  @override
  String toString() {
    final String hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    return slot == null
        ? 'ChartColor($hex)'
        : 'ChartColor($hex, ${slot!.name})';
  }
}

/// The font, size and colour of a piece of chart text.
final class ChartTextStyle {
  /// Creates a text style.
  const ChartTextStyle({
    required this.fontFamily,
    required this.size,
    required this.color,
    this.bold = false,
  });

  /// The font family's name.
  final String fontFamily;

  /// The size in points.
  final double size;

  /// The text colour.
  final ChartColor color;

  /// Whether the text is bold.
  final bool bold;

  /// A copy with the given fields replaced.
  ChartTextStyle copyWith({
    String? fontFamily,
    double? size,
    ChartColor? color,
    bool? bold,
  }) {
    return ChartTextStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      size: size ?? this.size,
      color: color ?? this.color,
      bold: bold ?? this.bold,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartTextStyle &&
        fontFamily == other.fontFamily &&
        size == other.size &&
        color == other.color &&
        bold == other.bold;
  }

  @override
  int get hashCode => Object.hash(fontFamily, size, color, bold);

  @override
  String toString() =>
      'ChartTextStyle($fontFamily, $size, $color, bold: $bold)';
}
