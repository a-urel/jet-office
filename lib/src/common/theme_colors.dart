/// The colors of a DrawingML theme and Excel's tint, shared by every format.
///
/// A theme part (`a:theme`) names twelve colors: `dk1`, `lt1`, `dk2`, `lt2`,
/// `accent1` to `accent6`, `hlink` and `folHlink`. [ThemeColors] reads them
/// by those names; mapping a format's own color index to a name is the
/// format's job. [applyTint] lightens or darkens a color as Excel does.
///
/// Not ported from Quds; written for jet_office.
library;

import '../xml/xml_pull_reader.dart';

const String _drawingMl =
    'http://schemas.openxmlformats.org/drawingml/2006/main';

/// The colors of a theme's first color scheme, by slot name.
final class ThemeColors {
  ThemeColors._(this._colors);

  final Map<String, int> _colors;

  /// Reads the first `a:theme/a:themeElements/a:clrScheme` from [r].
  ///
  /// [r] is advanced to the first element if it has not started. Returns
  /// `null` when the root is not `a:theme` or has no color scheme; a slot
  /// that is neither `a:srgbClr` nor `a:sysClr` with `lastClr` is left out
  /// (see [argbOf]). Never throws except an [XmlParseException] from [r].
  static ThemeColors? read(XmlPullReader r) {
    while (r.eventType != XmlEventType.startElement) {
      if (!r.nextTag()) {
        return null;
      }
    }
    if (!_is(r, 'theme')) {
      return null;
    }
    final int rootDepth = r.depth;
    final Map<String, int> colors = <String, int>{};
    bool found = false;
    while (!found && r.nextTag()) {
      if (r.eventType == XmlEventType.endElement && r.depth < rootDepth) {
        break;
      }
      if (r.eventType != XmlEventType.startElement) {
        continue;
      }
      if (r.depth == rootDepth + 1 && _is(r, 'themeElements')) {
        final int elementsDepth = r.depth;
        while (r.nextTag()) {
          if (r.eventType == XmlEventType.endElement &&
              r.depth < elementsDepth) {
            break;
          }
          if (r.eventType != XmlEventType.startElement) {
            continue;
          }
          if (r.depth == elementsDepth + 1 && _is(r, 'clrScheme')) {
            _readScheme(r, colors);
            found = true;
            break;
          }
          r.skip();
        }
      } else {
        r.skip();
      }
    }
    return found ? ThemeColors._(colors) : null;
  }

  static bool _is(XmlPullReader r, String name) =>
      r.localName == name && r.namespaceUri == _drawingMl;

  static void _readScheme(XmlPullReader r, Map<String, int> out) {
    final int schemeDepth = r.depth;
    if (r.isEmptyElement) {
      return;
    }
    while (r.nextTag()) {
      if (r.eventType == XmlEventType.endElement && r.depth < schemeDepth) {
        return;
      }
      if (r.eventType != XmlEventType.startElement) {
        continue;
      }
      if (r.depth != schemeDepth + 1 || r.namespaceUri != _drawingMl) {
        r.skip();
        continue;
      }
      final String slot = r.localName;
      final int slotDepth = r.depth;
      int? argb;
      if (!r.isEmptyElement) {
        while (r.nextTag()) {
          if (r.eventType == XmlEventType.endElement && r.depth < slotDepth) {
            break;
          }
          if (r.eventType != XmlEventType.startElement) {
            continue;
          }
          if (argb == null && r.depth == slotDepth + 1) {
            if (_is(r, 'srgbClr')) {
              argb = _hex(r.getAttribute('val'));
            } else if (_is(r, 'sysClr')) {
              argb = _hex(r.getAttribute('lastClr'));
            }
          }
          r.skip();
        }
      }
      if (argb != null && !out.containsKey(slot)) {
        out[slot] = argb;
      }
    }
  }

  static int? _hex(String? s) {
    if (s == null || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(s)) {
      return null;
    }
    return 0xFF000000 + int.parse(s, radix: 16);
  }

  /// The color of [slot] (`dk1`, `lt1`, `dk2`, `lt2`, `accent1`..`accent6`,
  /// `hlink`, `folHlink`) as `0xFFRRGGBB`, or `null` when the slot is absent,
  /// unknown, or not an `a:srgbClr` or `a:sysClr` with `lastClr`.
  int? argbOf(String slot) => _colors[slot];
}

// HLS scale of GDI's ColorRGBToHLS and ColorHLSToRGB.
const int _hlsMax = 240;

/// Applies Excel's [tint] (`-1..1`, ECMA-376 Part 1 section 18.8.19) to
/// [argb] on the HLS lightness and returns the result; alpha is kept and a
/// [tint] of 0 returns [argb].
///
/// The arithmetic is the integer HLS of GDI (`ColorRGBToHLS` and
/// `ColorHLSToRGB`, HLSMAX 240), with the new lightness floored and halves
/// rounded up elsewhere. That scale reproduces Excel's shades: Accent 1
/// `4472C4` with tint 0.7999816888943144 gives `D9E1F2`, 0.5999938962981048
/// `B4C6E7`, 0.3999755851924192 `8EA9DB`, -0.249977111117893 `305496` and
/// -0.499984740745262 `203764`; white with -0.1499984740745262 gives
/// `D9D9D9`. HLSMAX 255 does not (it is one step off in several channels).
int applyTint(int argb, double tint) {
  if (tint == 0) {
    return argb;
  }
  const int h = _hlsMax;
  final int alpha = argb ~/ 0x1000000;
  final int r = (argb ~/ 0x10000) % 256;
  final int g = (argb ~/ 0x100) % 256;
  final int b = argb % 256;
  final int mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final int mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final int sum = mx + mn;
  final int d = mx - mn;
  final int l = (sum * h + 255) ~/ 510;
  int hue = 0;
  int s = 0;
  if (d != 0) {
    s = l <= h ~/ 2
        ? (d * h + sum ~/ 2) ~/ sum
        : (d * h + (510 - sum) ~/ 2) ~/ (510 - sum);
    int delta(int c) => ((mx - c) * (h ~/ 6) + d ~/ 2) ~/ d;
    if (r == mx) {
      hue = delta(b) - delta(g);
    } else if (g == mx) {
      hue = h ~/ 3 + delta(r) - delta(b);
    } else {
      hue = 2 * h ~/ 3 + delta(g) - delta(r);
    }
    if (hue < 0) {
      hue += h;
    }
    if (hue > h) {
      hue -= h;
    }
  }
  final double lightened = tint < 0
      ? l * (1 + tint)
      : l * (1 - tint) + (h - h * (1 - tint));
  final int nl = lightened.floor().clamp(0, h);
  int channel(int m1, int m2, int hh) {
    if (hh < 0) {
      hh += h;
    }
    if (hh > h) {
      hh -= h;
    }
    int v;
    if (hh < h ~/ 6) {
      v = m1 + ((m2 - m1) * hh + h ~/ 12) ~/ (h ~/ 6);
    } else if (hh < h ~/ 2) {
      v = m2;
    } else if (hh < 2 * h ~/ 3) {
      v = m1 + ((m2 - m1) * (2 * h ~/ 3 - hh) + h ~/ 12) ~/ (h ~/ 6);
    } else {
      v = m1;
    }
    return (v * 255 + h ~/ 2) ~/ h;
  }

  int nr, ng, nb;
  if (s == 0) {
    nr = ng = nb = (nl * 255 + h ~/ 2) ~/ h;
  } else {
    final int m2 = nl <= h ~/ 2
        ? (nl * (h + s) + h ~/ 2) ~/ h
        : nl + s - (nl * s + h ~/ 2) ~/ h;
    final int m1 = 2 * nl - m2;
    nr = channel(m1, m2, hue + h ~/ 3);
    ng = channel(m1, m2, hue);
    nb = channel(m1, m2, hue - h ~/ 3);
  }
  int c8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
  return alpha * 0x1000000 + c8(nr) * 0x10000 + c8(ng) * 0x100 + c8(nb);
}
