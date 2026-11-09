/// DrawingML colours of a chart: `a:schemeClr` and `a:srgbClr` written from a
/// [ChartColor], and `a:srgbClr`, `a:schemeClr` and `a:sysClr` read back.
///
/// Not ported from Quds; written for jet_office.
///
/// A colour bound to a theme slot is written as `a:schemeClr` with the names
/// Excel uses in charts (`tx1`, `bg1`, `tx2`, `bg2`, `accent1` to `accent6`)
/// and Excel's `a:lumMod` and `a:lumOff`, when the colours follow the file's
/// theme; otherwise it is written as `a:srgbClr` of the colour it draws. A
/// colour read back is the slot it names, drawn as the file theme's colour
/// (or the Office theme's) with the luminance applied as Office applies it.
///
/// This layer imports `opc`, `xml`, `common`, `jet_charts_core` and `jet_core`
/// only, never `xlsx` or `docx` (decisions 0014 and 0015).
library;

import 'package:jet_charts_core/jet_charts_core.dart';

import '../common/theme_colors.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';

/// The DrawingML main namespace, the one of the `a:` prefix.
const String drawingMainNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/main';

/// The colour of each slot in the Office theme of Office 2023 and later, as
/// `0xRRGGBB`: `dk1` black, `lt1` white, `dk2` `0E2841`, `lt2` `E8E8E8` and
/// the six accents of `ChartTheme.office`.
///
/// A scheme colour read without a file theme, or whose slot the file theme
/// lacks, is drawn from this map.
const Map<ChartSchemeColor, int> drawingOfficeSchemeRgb =
    <ChartSchemeColor, int>{
      ChartSchemeColor.dark1: 0x000000,
      ChartSchemeColor.light1: 0xFFFFFF,
      ChartSchemeColor.dark2: 0x0E2841,
      ChartSchemeColor.light2: 0xE8E8E8,
      ChartSchemeColor.accent1: 0x156082,
      ChartSchemeColor.accent2: 0xE97132,
      ChartSchemeColor.accent3: 0x196B24,
      ChartSchemeColor.accent4: 0x0F9ED5,
      ChartSchemeColor.accent5: 0xA02B93,
      ChartSchemeColor.accent6: 0x4EA72E,
    };

/// The `val` of `a:schemeClr` Excel writes in a chart for each slot.
const Map<ChartSchemeColor, String> _writtenName = <ChartSchemeColor, String>{
  ChartSchemeColor.dark1: 'tx1',
  ChartSchemeColor.light1: 'bg1',
  ChartSchemeColor.dark2: 'tx2',
  ChartSchemeColor.light2: 'bg2',
  ChartSchemeColor.accent1: 'accent1',
  ChartSchemeColor.accent2: 'accent2',
  ChartSchemeColor.accent3: 'accent3',
  ChartSchemeColor.accent4: 'accent4',
  ChartSchemeColor.accent5: 'accent5',
  ChartSchemeColor.accent6: 'accent6',
};

/// The slot each `a:schemeClr` `val` read names: the chart names and the
/// theme's own (`dk1` and the rest).
const Map<String, ChartSchemeColor> _readSlot = <String, ChartSchemeColor>{
  'tx1': ChartSchemeColor.dark1,
  'dk1': ChartSchemeColor.dark1,
  'bg1': ChartSchemeColor.light1,
  'lt1': ChartSchemeColor.light1,
  'tx2': ChartSchemeColor.dark2,
  'dk2': ChartSchemeColor.dark2,
  'bg2': ChartSchemeColor.light2,
  'lt2': ChartSchemeColor.light2,
  'accent1': ChartSchemeColor.accent1,
  'accent2': ChartSchemeColor.accent2,
  'accent3': ChartSchemeColor.accent3,
  'accent4': ChartSchemeColor.accent4,
  'accent5': ChartSchemeColor.accent5,
  'accent6': ChartSchemeColor.accent6,
};

/// The theme part's name of each slot, the key of `ThemeColors.argbOf`.
const Map<ChartSchemeColor, String> _themeName = <ChartSchemeColor, String>{
  ChartSchemeColor.dark1: 'dk1',
  ChartSchemeColor.light1: 'lt1',
  ChartSchemeColor.dark2: 'dk2',
  ChartSchemeColor.light2: 'lt2',
  ChartSchemeColor.accent1: 'accent1',
  ChartSchemeColor.accent2: 'accent2',
  ChartSchemeColor.accent3: 'accent3',
  ChartSchemeColor.accent4: 'accent4',
  ChartSchemeColor.accent5: 'accent5',
  ChartSchemeColor.accent6: 'accent6',
};

final RegExp _hex6 = RegExp(r'^[0-9A-Fa-f]{6}$');
final RegExp _digits = RegExp(r'^[0-9]{1,6}$');

/// Writes [color] as a DrawingML colour element.
///
/// With [ChartExportColors.fileTheme] and a colour bound to a slot it is
/// `a:schemeClr` of the slot's chart name (`tx1`, `bg1`, `tx2`, `bg2`,
/// `accent1` to `accent6`), with an `a:lumMod` child when `lumMod` is not 1
/// and an `a:lumOff` child when `lumOff` is not 0, each of
/// `(fraction * 100000).round()`. Otherwise it is `a:srgbClr` of the colour's
/// `rgb` as six upper-case hexadecimal digits.
///
/// With an [alpha] (an opacity within 0 and 1, `null` for opaque) the element
/// holds an `a:alpha` child of `(alpha * 100000).round()`, after any
/// luminance children.
void writeDrawingColor(
  XmlWriter w,
  ChartColor color,
  ChartExportColors mode, {
  double? alpha,
}) {
  final ChartSchemeColor? slot = color.slot;
  final String? alphaValue = alpha == null
      ? null
      : (alpha * 100000).round().toString();
  if (mode != ChartExportColors.fileTheme || slot == null) {
    if (alphaValue == null) {
      w.empty('a:srgbClr', <String, String>{'val': _hex(color.rgb)});
    } else {
      w.start('a:srgbClr');
      w.attribute('val', _hex(color.rgb));
      w.empty('a:alpha', <String, String>{'val': alphaValue});
      w.end();
    }
    return;
  }
  w.start('a:schemeClr');
  w.attribute('val', _writtenName[slot]!);
  if (color.lumMod != 1) {
    w.empty('a:lumMod', <String, String>{
      'val': (color.lumMod * 100000).round().toString(),
    });
  }
  if (color.lumOff != 0) {
    w.empty('a:lumOff', <String, String>{
      'val': (color.lumOff * 100000).round().toString(),
    });
  }
  if (alphaValue != null) {
    w.empty('a:alpha', <String, String>{'val': alphaValue});
  }
  w.end();
}

String _hex(int rgb) => rgb.toRadixString(16).padLeft(6, '0').toUpperCase();

/// Reads the colour element [r] stands on and consumes it, leaving [r] on its
/// end event.
///
/// `a:srgbClr` gives a fixed colour of its `val`, and `a:sysClr` one of its
/// `lastClr`. `a:schemeClr` gives a colour bound to the slot it names (`tx1`
/// and `dk1` alike name the first dark slot), drawn as the slot's colour in
/// [theme], or in [drawingOfficeSchemeRgb] when [theme] is `null` or lacks
/// it. `a:lumMod` and `a:lumOff` children are applied with
/// [applyDrawingLuminance]; a scheme colour also keeps them, a fixed one keeps
/// only the result. A fixed colour with `a:lumMod` or `a:lumOff` therefore
/// writes back as a plain `a:srgbClr` of that result, so a part holding one is
/// not reproduced by the writer (and is not offered as typed).
///
/// An `a:alpha` child (within `0` to `100000`) is read and dropped when
/// [allowAlpha], as a colour is opaque; the chart reader sets it, and the typed
/// form is then checked by writing it again.
///
/// Returns `null` for any other element (which is skipped), for a slot or a
/// value it cannot read, for a `lumMod` or `lumOff` outside `0` to `100000`,
/// and for any other modifier (`alpha` unless [allowAlpha], `shade`, `tint`
/// and the rest). Never
/// throws except an [XmlParseException] from [r].
ChartColor? readDrawingColor(
  XmlPullReader r, {
  ThemeColors? theme,
  bool allowAlpha = false,
}) {
  if (r.eventType != XmlEventType.startElement) {
    return null;
  }
  final String name = r.localName;
  if (r.namespaceUri != drawingMainNamespace ||
      (name != 'srgbClr' && name != 'schemeClr' && name != 'sysClr')) {
    r.skip();
    return null;
  }
  final String? value = r.getAttribute(name == 'sysClr' ? 'lastClr' : 'val');
  final _Luminance? luminance = _readModifiers(r, allowAlpha);
  if (value == null || luminance == null) {
    return null;
  }
  if (name != 'schemeClr') {
    if (!_hex6.hasMatch(value)) {
      return null;
    }
    final int rgb = int.parse(value, radix: 16);
    return ChartColor.rgb(
      applyDrawingLuminance(rgb, luminance.lumMod, luminance.lumOff),
    );
  }
  final ChartSchemeColor? slot = _readSlot[value];
  if (slot == null) {
    return null;
  }
  final int? argb = theme?.argbOf(_themeName[slot]!);
  final int base = argb == null
      ? drawingOfficeSchemeRgb[slot]!
      : argb & 0xFFFFFF;
  return ChartColor.scheme(
    slot,
    rgb: applyDrawingLuminance(base, luminance.lumMod, luminance.lumOff),
    lumMod: luminance.lumMod,
    lumOff: luminance.lumOff,
  );
}

final class _Luminance {
  const _Luminance(this.lumMod, this.lumOff);

  final double lumMod;
  final double lumOff;
}

/// Reads the children of the colour element [r] stands on through its end;
/// `null` when a child is not `a:lumMod` or `a:lumOff` with a readable value.
_Luminance? _readModifiers(XmlPullReader r, bool allowAlpha) {
  if (r.isEmptyElement) {
    r.next();
    return const _Luminance(1, 0);
  }
  final int depth = r.depth;
  double lumMod = 1;
  double lumOff = 0;
  bool valid = true;
  while (r.nextTag()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) {
      break;
    }
    if (r.eventType != XmlEventType.startElement) {
      // Text inside a colour element is not DrawingML.
      valid = false;
      continue;
    }
    final String child = r.localName;
    final double? fraction =
        r.namespaceUri == drawingMainNamespace &&
            (child == 'lumMod' ||
                child == 'lumOff' ||
                (allowAlpha && child == 'alpha'))
        ? _fraction(r.getAttribute('val'))
        : null;
    if (fraction == null) {
      valid = false;
    } else if (child == 'lumMod') {
      lumMod = fraction;
    } else if (child == 'alpha') {
      // Read and dropped: a colour is opaque.
    } else {
      lumOff = fraction;
    }
    r.skip();
  }
  return valid ? _Luminance(lumMod, lumOff) : null;
}

/// [value], a DrawingML percentage in thousandths of a percent, as a
/// fraction; `null` unless it is an integer within `0` to `100000`.
double? _fraction(String? value) {
  if (value == null || !_digits.hasMatch(value)) {
    return null;
  }
  final int n = int.parse(value);
  return n > 100000 ? null : n / 100000;
}

/// [rgb] (`0xRRGGBB`) with its luminance multiplied by [lumMod] and then
/// [lumOff] added, as DrawingML's `lumMod` and `lumOff` do.
///
/// The colour is converted to hue, saturation and luminance (HSL), the new
/// luminance `L * lumMod + lumOff` is clamped to `0` to `1`, and the colour is
/// converted back with its hue and saturation, each channel rounded half up.
/// Black with `0.65` and `0.35` gives `595959`, and with `0.15` and `0.85`
/// gives `D9D9D9`, as Excel draws them. [rgb] is returned unchanged when
/// [lumMod] is 1 and [lumOff] is 0.
int applyDrawingLuminance(int rgb, double lumMod, double lumOff) {
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
