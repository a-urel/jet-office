/// Measuring text, which layout needs and only a backend can do truly.
library;

import '../theme/chart_color.dart';
import 'geometry.dart';

/// Tells layout how large a piece of text is.
///
/// Flutter measures with `TextPainter` and a PDF writer with its font metrics.
abstract interface class TextMeasurer {
  /// The size [text] takes when drawn in [style].
  ///
  /// The result is finite and not negative. An empty string is zero wide and
  /// one line high.
  ChartSize measure(String text, ChartTextStyle style);
}

/// A measurer where every character is as wide as every other.
///
/// For tests only: it gives layout the same numbers on every platform, which
/// is what a golden test needs. Final layout never uses it, because estimated
/// widths are not real ones.
///
/// Text splits into lines on `\n` only. The width is the longest line's rune
/// count times the style's size times [charWidthFactor]; the height is the
/// line count times the size times [lineHeightFactor].
final class FixedWidthTextMeasurer implements TextMeasurer {
  /// Creates a measurer with the given factors of the font size.
  const FixedWidthTextMeasurer({
    this.charWidthFactor = 0.6,
    this.lineHeightFactor = 1.2,
  });

  /// The width of a character as a multiple of the font size.
  final double charWidthFactor;

  /// The height of a line as a multiple of the font size.
  final double lineHeightFactor;

  @override
  ChartSize measure(String text, ChartTextStyle style) {
    final List<String> lines = text.split('\n');
    int longest = 0;
    for (final String line in lines) {
      final int length = line.runes.length;
      if (length > longest) {
        longest = length;
      }
    }
    return ChartSize(
      longest * style.size * charWidthFactor,
      lines.length * style.size * lineHeightFactor,
    );
  }
}
