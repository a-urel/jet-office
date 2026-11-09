/// DrawingML's `lumMod` and `lumOff` on an RGB colour.
library;

/// [rgb] (`0xRRGGBB`) with its luminance multiplied by [lumMod] and then
/// [lumOff] added, as DrawingML's `lumMod` and `lumOff` do.
///
/// The colour is converted to hue, saturation and luminance (HSL), the new
/// luminance `L * lumMod + lumOff` is clamped to `0` to `1`, and the colour is
/// converted back with its hue and saturation, each channel rounded half up.
/// It is the same calculation as `applyDrawingLuminance` of `jet_office`
/// (`lib/src/drawingml/color.dart`), which this package cannot import; a
/// test at the repository's root checks that the two agree. [rgb] is
/// returned unchanged when [lumMod] is 1 and [lumOff] is 0.
int applyLuminance(int rgb, double lumMod, double lumOff) {
  if (lumMod == 1 && lumOff == 0) {
    return rgb;
  }
  final double r = ((rgb >> 16) & 0xFF) / 255;
  final double g = ((rgb >> 8) & 0xFF) / 255;
  final double b = (rgb & 0xFF) / 255;
  final double max = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final double min = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final double l = (max + min) / 2;
  double h = 0;
  double s = 0;
  final double d = max - min;
  if (d != 0) {
    s = l <= 0.5 ? d / (max + min) : d / (2 - max - min);
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  final double nl = (l * lumMod + lumOff).clamp(0.0, 1.0);
  double nr;
  double ng;
  double nb;
  if (s == 0) {
    nr = ng = nb = nl;
  } else {
    final double q = nl < 0.5 ? nl * (1 + s) : nl + s - nl * s;
    final double p = 2 * nl - q;
    nr = _hueToChannel(p, q, h + 1 / 3);
    ng = _hueToChannel(p, q, h);
    nb = _hueToChannel(p, q, h - 1 / 3);
  }
  return (_channel(nr) << 16) | (_channel(ng) << 8) | _channel(nb);
}

double _hueToChannel(double p, double q, double t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 1 / 2) return q;
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}

int _channel(double v) => (v * 255 + 0.5).floor().clamp(0, 255);
