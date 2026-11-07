/// Reads the style elements of a styles part into the value types.
///
/// Not ported from Quds; written for jet_office. Each function is the reverse
/// of a writer function: [readColor] of `writeColorAttributes`, [readFont] of
/// `writeFontXml`, [readFill] of `writeFillXml`, [readBorder] of
/// `writeBorderXml` and [readXf] of `alignmentXml` and `protectionXml` (the
/// `<xf>` itself is the registry's); [readDifferentialStyle] is the reverse
/// of `writeDifferentialStyleXml`.
///
/// Every function reads the element the reader is on, leaves the reader on
/// that element's end event and never throws for a value in the file. A value
/// the types cannot hold (a size of `abc`, a pattern called `zigzag`, a theme
/// colour 99) becomes the default, null or the unset field, with a `problem`
/// in English that says what was wrong.
///
/// A result is *exact* when the writer's own element for the value would be
/// the element that was read: no attribute or child the types do not hold,
/// no repeated or misplaced child, and every value spelled as the writer
/// spells it (`<b/>`, not `<b val="1"/>`; `11`, not `11.0`; `FF1F4E79`, not
/// `ff1f4e79`; no default written out). An entry that is not exact is still
/// read into the value, but must be kept as written to be saved unchanged.
/// Exactness is decided here, in `lib/`, by those rules; the tests prove it
/// against the semantic XML comparer.
library;

import 'package:jet_core/jet_core.dart' show builtinNumberFormatCode;

import '../../opc/ooxml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_number.dart';
import '../../xml/xml_pull_reader.dart';
import '../alignment.dart';
import '../border.dart';
import '../color.dart';
import '../differential_style.dart';
import '../fill.dart';
import '../font.dart';
import '../number_format.dart';
import '../read/styles_reader.dart' show readStyleId;
import '../style.dart';

/// A value read from a style element: `exact` says that writing `value` back
/// gives the element that was read, and `problem` describes a value in the
/// element that could not be read, or is `null`.
typedef ReadStyleValue<T> = ({T value, bool exact, String? problem});

/// What a read has found so far.
final class _Acc {
  bool exact = true;
  String? problem;

  void inexact() => exact = false;

  void bad(String message) {
    exact = false;
    problem ??= message;
  }

  /// Takes over the outcome of a nested read.
  void absorb(ReadStyleValue<Object?> nested) {
    exact = exact && nested.exact;
    problem ??= nested.problem;
  }

  ReadStyleValue<T> result<T>(T value) =>
      (value: value, exact: exact, problem: problem);
}

String? _attr(XmlPullReader r, String name) =>
    r.getAttribute(name, namespaceUri: '');

/// Marks the element inexact for each attribute of the current start element
/// that is not an unprefixed name in [known] (namespace declarations are not
/// attributes).
void _checkAttributes(XmlPullReader r, _Acc acc, Set<String> known) {
  for (var i = 0; i < r.attributeCount; i++) {
    final String name = r.attributeQualifiedName(i);
    if (name == 'xmlns' || name.startsWith('xmlns:')) continue;
    if (r.attributePrefix(i).isEmpty && known.contains(name)) continue;
    acc.inexact();
  }
}

/// Reads the children of the element the reader is on up to its end. [onChild]
/// gets each SpreadsheetML child (the reader on its start) and returns
/// whether it knows the child, having then consumed it to its end; any other
/// child is skipped and makes the element inexact, as does text.
void _eachChild(XmlPullReader r, _Acc acc, bool Function() onChild) {
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) return;
    if (r.eventType == XmlEventType.startElement) {
      if (r.namespaceUri == Ns.main && onChild()) continue;
      acc.inexact();
      r.skip();
    } else if (r.eventType == XmlEventType.characters && !r.isWhitespace) {
      acc.inexact();
    } else if (r.eventType == XmlEventType.cdata) {
      acc.inexact();
    }
  }
}

/// Finishes an element that has no children: anything inside makes it
/// inexact; leaves the reader on its end.
void _finishLeaf(XmlPullReader r, _Acc acc) {
  if (!r.isEmptyElement) acc.inexact();
  r.skip();
}

/// The `val` of the leaf element the reader is on, which is consumed.
String? _valOnly(XmlPullReader r, _Acc acc) {
  _checkAttributes(r, acc, const <String>{'val'});
  final String? val = _attr(r, 'val');
  _finishLeaf(r, acc);
  return val;
}

bool? _parseBool(String raw) => switch (raw) {
  '1' || 'true' => true,
  '0' || 'false' => false,
  _ => null,
};

int? _int(String raw, _Acc acc, String what) {
  final int? v = int.tryParse(raw);
  if (v == null) {
    acc.bad('$what "$raw" is not a whole number.');
    return null;
  }
  if ('$v' != raw) acc.inexact();
  return v;
}

double? _double(String raw, _Acc acc, String what) {
  final double? v = double.tryParse(raw);
  if (v == null || !v.isFinite) {
    acc.bad('$what "$raw" is not a finite number.');
    return null;
  }
  if (formatXmlDouble(v) != raw) acc.inexact();
  return v;
}

Map<String, T> _names<T extends Enum>(
  List<T> values, [
  Map<String, T> others = const <String, Never>{},
]) => <String, T>{for (final T v in values) v.name: v, ...others};

/// Runs [validate], which throws [ArgumentError] for a value outside the
/// writer's limits, and records that as a problem.
bool _valid(_Acc acc, void Function() validate) {
  try {
    validate();
    return true;
  } on ArgumentError catch (e) {
    acc.bad('${e.message}');
    return false;
  }
}

// -- Colours -----------------------------------------------------------------

final RegExp _hex8 = RegExp(r'^[0-9A-Fa-f]{8}$');
final RegExp _hex6 = RegExp(r'^[0-9A-Fa-f]{6}$');

/// Reads a `CT_Color` element: `rgb`, `theme` with `tint`, `indexed` or
/// `auto`. The value is `null` when the element names no colour, or names one
/// the writer would refuse (a theme index above 11, a tint outside `-1..1`
/// or not finite, a palette index above 65), which is also a `problem`. With
/// [tooltipText], index 81 is `null` without a problem: Excel's system colour
/// of a note's text, which the writer's palette does not hold.
ReadStyleValue<XlsxColor?> readColor(
  XmlPullReader r, {
  bool tooltipText = false,
}) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{
    'rgb',
    'theme',
    'tint',
    'indexed',
    'auto',
  });
  final String? rgb = _attr(r, 'rgb');
  final String? theme = _attr(r, 'theme');
  final String? tint = _attr(r, 'tint');
  final String? indexed = _attr(r, 'indexed');
  final String? auto = _attr(r, 'auto');
  _finishLeaf(r, acc);
  if (<String?>[rgb, theme, indexed, auto].nonNulls.length > 1) acc.inexact();

  XlsxColor? color;
  if (rgb != null) {
    if (_hex8.hasMatch(rgb)) {
      color = XlsxColor.argb(int.parse(rgb, radix: 16));
      if (rgb != rgb.toUpperCase()) acc.inexact();
    } else if (_hex6.hasMatch(rgb)) {
      color = XlsxColor.rgb(int.parse(rgb, radix: 16));
      acc.inexact();
    } else {
      acc.bad('The color rgb "$rgb" is not 8 hex digits.');
    }
    if (tint != null) acc.inexact();
  } else if (theme != null) {
    final int? index = _int(theme, acc, 'The color theme');
    double? t = 0;
    if (tint != null) {
      t = _double(tint, acc, 'The color tint');
      if (t == 0) acc.inexact();
    }
    if (index != null && t != null) {
      color = XlsxColor.theme(index, tint: t);
    }
  } else if (indexed != null) {
    final int? index = _int(indexed, acc, 'The color indexed');
    if (tooltipText && index == 81) {
      acc.inexact();
    } else if (index != null) {
      color = XlsxColor.indexed(index);
    }
    if (tint != null) acc.inexact();
  } else if (auto != null) {
    switch (_parseBool(auto)) {
      case true:
        color = XlsxColor.auto;
        if (auto != '1') acc.inexact();
      case false:
        acc.inexact();
      case null:
        acc.bad('The color auto "$auto" is not a boolean.');
    }
    if (tint != null) acc.inexact();
  } else {
    acc.inexact();
  }
  if (color != null && !_valid(acc, () => validateColor(color!, 'color'))) {
    color = null;
  }
  return acc.result<XlsxColor?>(color);
}

// -- Fonts -------------------------------------------------------------------

/// The position of each `CT_Font` child in the order the writer writes them.
const Map<String, int> _fontOrder = <String, int>{
  'b': 0,
  'i': 1,
  'strike': 2,
  'condense': 3,
  'extend': 4,
  'outline': 5,
  'shadow': 6,
  'u': 7,
  'vertAlign': 8,
  'sz': 9,
  'color': 10,
  'name': 11,
  'family': 12,
  'charset': 13,
  'scheme': 14,
};

final Map<String, XlsxUnderline> _underlines = _names(
  XlsxUnderline.values,
  <String, XlsxUnderline>{'double': XlsxUnderline.doubleLine},
)..remove('doubleLine');
final Map<String, XlsxFontScript> _scripts = _names(XlsxFontScript.values);
final Map<String, XlsxFontScheme> _schemes = _names(XlsxFontScheme.values);

/// A flag element such as `<b/>`: true without `val`; the writer writes only
/// the true form, without `val`.
bool? _readFlag(XmlPullReader r, _Acc acc, String name) {
  final String? val = _valOnly(r, acc);
  if (val == null) return true;
  acc.inexact();
  final bool? flag = _parseBool(val);
  if (flag == null) acc.bad('The font $name val "$val" is not a boolean.');
  return flag;
}

/// Reads a `<font>` element. A field whose element is missing or unreadable
/// is `null`.
///
/// [nameElement] is the local name of the element that holds the font name:
/// `name` in a `<font>`, `rFont` in the `<rPr>` of a rich text run, which
/// this function reads as well. `exact` is `false` for an `<rPr>` whose
/// children are not in the order `CT_Font` has.
ReadStyleValue<XlsxFont> readFont(
  XmlPullReader r, {
  String nameElement = 'name',
}) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{});
  bool? bold, italic, strike, condense, extend, outline, shadow;
  XlsxUnderline? underline;
  XlsxFontScript? script;
  double? size;
  XlsxColor? color;
  String? name;
  int? family, charset;
  XlsxFontScheme? scheme;
  final Set<String> seen = <String>{};
  var last = -1;
  _eachChild(r, acc, () {
    final String local = r.localName;
    // The name element of the other spelling is not a font name here.
    final String n = local == nameElement
        ? 'name'
        : (local == 'name' ? '' : local);
    final int? rank = _fontOrder[n];
    if (rank == null) return false;
    if (!seen.add(n) || rank < last) acc.inexact();
    if (rank > last) last = rank;
    switch (n) {
      case 'b':
        bold = _readFlag(r, acc, n);
      case 'i':
        italic = _readFlag(r, acc, n);
      case 'strike':
        strike = _readFlag(r, acc, n);
      case 'condense':
        condense = _readFlag(r, acc, n);
      case 'extend':
        extend = _readFlag(r, acc, n);
      case 'outline':
        outline = _readFlag(r, acc, n);
      case 'shadow':
        shadow = _readFlag(r, acc, n);
      case 'u':
        final String? val = _valOnly(r, acc);
        if (val == null) {
          underline = XlsxUnderline.single;
        } else {
          underline = _underlines[val];
          if (underline == null) {
            acc.bad('The font underline "$val" is not an underline style.');
          } else if (underline == XlsxUnderline.single ||
              underline == XlsxUnderline.none) {
            acc.inexact();
          }
        }
      case 'vertAlign':
        final String? val = _valOnly(r, acc);
        script = val == null ? null : _scripts[val];
        if (script == null) {
          acc.bad('The font vertAlign "$val" is not a script.');
        } else if (script == XlsxFontScript.baseline) {
          acc.inexact();
        }
      case 'sz':
        final String? val = _valOnly(r, acc);
        size = val == null ? null : _double(val, acc, 'The font size');
        if (size == null && val == null) acc.bad('A font size has no val.');
        final double? s = size;
        if (s != null && !_valid(acc, () => validateFont(XlsxFont(size: s)))) {
          size = null;
        }
      case 'color':
        final ReadStyleValue<XlsxColor?> c = readColor(
          r,
          tooltipText: nameElement == 'rFont',
        );
        acc.absorb(c);
        color = c.value;
      case 'name':
        name = _valOnly(r, acc);
        final String? nm = name;
        if (nm == null) {
          acc.bad('A font name has no val.');
        } else if (!_valid(acc, () => validateFont(XlsxFont(name: nm)))) {
          name = null;
        }
      case 'family':
        final String? val = _valOnly(r, acc);
        family = val == null ? null : _int(val, acc, 'The font family');
        final int? f = family;
        if (f != null &&
            !_valid(acc, () => validateFont(XlsxFont(family: f)))) {
          family = null;
        }
      case 'charset':
        final String? val = _valOnly(r, acc);
        charset = val == null ? null : _int(val, acc, 'The font charset');
        final int? c = charset;
        if (c != null &&
            !_valid(acc, () => validateFont(XlsxFont(charset: c)))) {
          charset = null;
        }
      case 'scheme':
        final String? val = _valOnly(r, acc);
        scheme = val == null ? null : _schemes[val];
        if (scheme == null) {
          acc.bad('The font scheme "$val" is not a scheme.');
        } else if (scheme == XlsxFontScheme.none) {
          acc.inexact();
        }
    }
    return true;
  });
  return acc.result(
    XlsxFont(
      name: name,
      size: size,
      color: color,
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      script: script,
      outline: outline,
      shadow: shadow,
      condense: condense,
      extend: extend,
      family: family,
      charset: charset,
      scheme: scheme,
    ),
  );
}

// -- Fills -------------------------------------------------------------------

const XlsxFill _defaultFill = XlsxPatternFill(XlsxPatternType.none);

final Map<String, XlsxPatternType> _patterns = _names(XlsxPatternType.values);

/// Reads a `<fill>` element: a `patternFill` or a `gradientFill`. A fill the
/// types cannot hold is a pattern fill of `none` and a `problem`.
ReadStyleValue<XlsxFill> readFill(XmlPullReader r) =>
    _readFill(r, differential: false);

/// [readFill] for the fill of a differential style, which the writer writes
/// differently: a solid fill as a `bgColor` and no `patternType`.
ReadStyleValue<XlsxFill> _readFill(
  XmlPullReader r, {
  required bool differential,
}) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{});
  XlsxFill? fill;
  _eachChild(r, acc, () {
    final String n = r.localName;
    if (n != 'patternFill' && n != 'gradientFill') return false;
    if (fill != null) {
      acc.inexact();
      r.skip();
      return true;
    }
    fill = n == 'patternFill'
        ? _readPatternFill(r, acc, differential)
        : _readGradient(r, acc);
    return true;
  });
  final XlsxFill? read = fill;
  if (read == null) {
    acc.bad('A fill has neither a patternFill nor a gradientFill.');
    return acc.result(_defaultFill);
  }
  if (!_valid(acc, () => validateFill(read))) return acc.result(_defaultFill);
  return acc.result(read);
}

XlsxFill? _readPatternFill(XmlPullReader r, _Acc acc, bool differential) {
  _checkAttributes(r, acc, const <String>{'patternType'});
  final String? type = _attr(r, 'patternType');
  XlsxColor? fg, bg;
  var last = -1;
  _eachChild(r, acc, () {
    final String n = r.localName;
    final int rank = n == 'fgColor' ? 0 : 1;
    if (n != 'fgColor' && n != 'bgColor') return false;
    if (rank <= last) acc.inexact();
    last = rank;
    final ReadStyleValue<XlsxColor?> c = readColor(r);
    acc.absorb(c);
    if (rank == 0) {
      fg = c.value;
    } else {
      bg = c.value;
    }
    return true;
  });
  if (differential) {
    // A differential style's solid fill is written as its color in
    // `bgColor` (the color a cell shows) and without a `patternType`.
    if (type == null) {
      if (fg != null) acc.inexact();
      return XlsxPatternFill(XlsxPatternType.solid, foreground: fg ?? bg);
    }
    if (type == 'solid') acc.inexact();
  }
  if (type == null) {
    acc.inexact();
    return XlsxPatternFill(
      XlsxPatternType.none,
      foreground: fg,
      background: bg,
    );
  }
  final XlsxPatternType? pattern = _patterns[type];
  if (pattern == null) {
    acc.bad('The patternType "$type" is not a pattern.');
    return null;
  }
  return XlsxPatternFill(pattern, foreground: fg, background: bg);
}

XlsxFill? _readGradient(XmlPullReader r, _Acc acc) {
  _checkAttributes(r, acc, const <String>{
    'type',
    'degree',
    'left',
    'right',
    'top',
    'bottom',
  });
  final String? type = _attr(r, 'type');
  final bool path = type == 'path';
  if (type == 'linear') acc.inexact();
  if (type != null && type != 'path' && type != 'linear') {
    acc.bad('The gradient type "$type" is not linear or path.');
  }
  double edge(String name) {
    final String? raw = _attr(r, name);
    if (raw == null) {
      if (path) acc.inexact();
      return 0;
    }
    if (!path) acc.inexact();
    return _double(raw, acc, 'The gradient $name') ?? 0;
  }

  final double left = edge('left');
  final double right = edge('right');
  final double top = edge('top');
  final double bottom = edge('bottom');
  double degree = 0;
  final String? degreeRaw = _attr(r, 'degree');
  if (degreeRaw != null) {
    degree = _double(degreeRaw, acc, 'The gradient degree') ?? 0;
    if (path || degree == 0) acc.inexact();
  }
  final List<XlsxGradientStop> stops = <XlsxGradientStop>[];
  _eachChild(r, acc, () {
    if (r.localName != 'stop') return false;
    final XlsxGradientStop? stop = _readStop(r, acc);
    if (stop != null) stops.add(stop);
    return true;
  });
  if (type != null && !path && type != 'linear') return null;
  return path
      ? XlsxGradientFill.path(
          left: left,
          right: right,
          top: top,
          bottom: bottom,
          stops: stops,
        )
      : XlsxGradientFill.linear(degree: degree, stops: stops);
}

XlsxGradientStop? _readStop(XmlPullReader r, _Acc acc) {
  _checkAttributes(r, acc, const <String>{'position'});
  final String? raw = _attr(r, 'position');
  final double? position = raw == null
      ? null
      : _double(raw, acc, 'The gradient stop position');
  if (raw == null) acc.bad('A gradient stop has no position.');
  XlsxColor? color;
  var seen = false;
  _eachChild(r, acc, () {
    if (r.localName != 'color') return false;
    if (seen) acc.inexact();
    seen = true;
    final ReadStyleValue<XlsxColor?> c = readColor(r);
    acc.absorb(c);
    color = c.value;
    return true;
  });
  final XlsxColor? c = color;
  if (c == null) {
    acc.bad('A gradient stop has no usable color.');
    return null;
  }
  return position == null ? null : XlsxGradientStop(position, c);
}

// -- Borders -----------------------------------------------------------------

const Map<String, int> _borderOrder = <String, int>{
  'left': 0,
  'right': 1,
  'top': 2,
  'bottom': 3,
  'diagonal': 4,
  'vertical': 5,
  'horizontal': 6,
};

final Map<String, XlsxBorderStyle> _borderStyles = _names(
  XlsxBorderStyle.values,
  <String, XlsxBorderStyle>{'double': XlsxBorderStyle.doubleLine},
)..remove('doubleLine');

bool _draws(XlsxBorderSide? side) =>
    side?.style != null && side!.style != XlsxBorderStyle.none;

XlsxBorderSide? _readSide(XmlPullReader r, _Acc acc) {
  _checkAttributes(r, acc, const <String>{'style'});
  final String? raw = _attr(r, 'style');
  XlsxBorderStyle? style;
  if (raw != null) {
    style = _borderStyles[raw];
    if (style == null) {
      acc.bad('The border style "$raw" is not a border style.');
    } else if (style == XlsxBorderStyle.none) {
      acc.inexact();
    }
  }
  XlsxColor? color;
  var seen = false;
  _eachChild(r, acc, () {
    if (r.localName != 'color') return false;
    if (seen) acc.inexact();
    seen = true;
    final ReadStyleValue<XlsxColor?> c = readColor(r);
    acc.absorb(c);
    color = c.value;
    return true;
  });
  if (color != null && !_draws(XlsxBorderSide(style: style))) acc.inexact();
  if (style == null && color == null) return null;
  return XlsxBorderSide(style: style, color: color);
}

/// Reads a `<border>` element. A side with no line is `null`.
ReadStyleValue<XlsxBorder> readBorder(XmlPullReader r) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{
    'diagonalUp',
    'diagonalDown',
    'outline',
  });
  bool? flag(String name, bool written) {
    final String? raw = _attr(r, name);
    if (raw == null) return null;
    final bool? value = _parseBool(raw);
    if (value == null) {
      acc.bad('The border $name "$raw" is not a boolean.');
    } else if (value != written || raw != (written ? '1' : '0')) {
      acc.inexact();
    }
    return value;
  }

  final bool? up = flag('diagonalUp', true);
  final bool? down = flag('diagonalDown', true);
  final bool? outline = flag('outline', false);
  final Map<String, XlsxBorderSide?> sides = <String, XlsxBorderSide?>{};
  var last = -1;
  _eachChild(r, acc, () {
    final String n = r.localName;
    final int? rank = _borderOrder[n];
    if (rank == null) return false;
    if (sides.containsKey(n) || rank < last) acc.inexact();
    if (rank > last) last = rank;
    final XlsxBorderSide? side = _readSide(r, acc);
    if (!sides.containsKey(n)) sides[n] = side;
    // The writer omits a vertical or horizontal side that draws no line.
    if (rank >= 5 && !_draws(side)) acc.inexact();
    return true;
  });
  for (final String n in const <String>[
    'left',
    'right',
    'top',
    'bottom',
    'diagonal',
  ]) {
    if (!sides.containsKey(n)) acc.inexact();
  }
  // The writer writes a diagonal line only under a direction.
  if (_draws(sides['diagonal']) && !(up ?? false) && !(down ?? false)) {
    acc.inexact();
  }
  return acc.result(
    XlsxBorder(
      left: sides['left'],
      right: sides['right'],
      top: sides['top'],
      bottom: sides['bottom'],
      diagonal: sides['diagonal'],
      vertical: sides['vertical'],
      horizontal: sides['horizontal'],
      diagonalUp: up,
      diagonalDown: down,
      outline: outline,
    ),
  );
}

// -- Cell formats ------------------------------------------------------------

final Map<String, XlsxHorizontalAlignment> _horizontals = _names(
  XlsxHorizontalAlignment.values,
);
final Map<String, XlsxVerticalAlignment> _verticals = _names(
  XlsxVerticalAlignment.values,
);

ReadStyleValue<XlsxAlignment?> _readAlignment(XmlPullReader r) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{
    'horizontal',
    'vertical',
    'textRotation',
    'wrapText',
    'indent',
    'justifyLastLine',
    'shrinkToFit',
    'readingOrder',
  });
  bool? flag(String name) {
    final String? raw = _attr(r, name);
    if (raw == null) return null;
    final bool? value = _parseBool(raw);
    if (value == null) {
      acc.bad('The alignment $name "$raw" is not a boolean.');
    } else if (raw != '1') {
      acc.inexact();
    }
    return value;
  }

  XlsxHorizontalAlignment? horizontal;
  final String? h = _attr(r, 'horizontal');
  if (h != null) {
    horizontal = _horizontals[h];
    if (horizontal == null) {
      acc.bad('The alignment horizontal "$h" is not an alignment.');
    } else if (horizontal == XlsxHorizontalAlignment.general) {
      acc.inexact();
    }
  }
  XlsxVerticalAlignment? vertical;
  final String? v = _attr(r, 'vertical');
  if (v != null) {
    vertical = _verticals[v];
    if (vertical == null) {
      acc.bad('The alignment vertical "$v" is not an alignment.');
    } else if (vertical == XlsxVerticalAlignment.bottom) {
      acc.inexact();
    }
  }
  int? rotation;
  final String? rot = _attr(r, 'textRotation');
  if (rot != null) {
    rotation = _int(rot, acc, 'The alignment textRotation');
    final int? ro = rotation;
    if (ro != null) {
      if (ro == 0) acc.inexact();
      if (!_valid(
        acc,
        () => validateAlignment(XlsxAlignment(textRotation: ro)),
      )) {
        rotation = null;
      }
    }
  }
  int? indent;
  final String? ind = _attr(r, 'indent');
  if (ind != null) {
    indent = _int(ind, acc, 'The alignment indent');
    final int? i = indent;
    if (i != null) {
      if (i == 0) acc.inexact();
      if (!_valid(acc, () => validateAlignment(XlsxAlignment(indent: i)))) {
        indent = null;
      }
    }
  }
  XlsxReadingOrder? order;
  final String? ord = _attr(r, 'readingOrder');
  if (ord != null) {
    final int? n = _int(ord, acc, 'The alignment readingOrder');
    if (n != null) {
      if (n < 0 || n >= XlsxReadingOrder.values.length) {
        acc.bad('The alignment readingOrder "$ord" is not 0, 1 or 2.');
      } else {
        order = XlsxReadingOrder.values[n];
        if (order == XlsxReadingOrder.context) acc.inexact();
      }
    }
  }
  final bool? wrap = flag('wrapText');
  final bool? justify = flag('justifyLastLine');
  final bool? shrink = flag('shrinkToFit');
  // `<alignment/>` with nothing in it is not written by the writer.
  if (r.attributeCount == 0) acc.inexact();
  _finishLeaf(r, acc);
  return acc.result<XlsxAlignment?>(
    XlsxAlignment(
      horizontal: horizontal,
      vertical: vertical,
      wrapText: wrap,
      indent: indent,
      textRotation: rotation,
      shrinkToFit: shrink,
      readingOrder: order,
      justifyLastLine: justify,
    ),
  );
}

ReadStyleValue<XlsxProtection?> _readProtection(XmlPullReader r) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{'locked', 'hidden'});
  bool? flag(String name, bool written) {
    final String? raw = _attr(r, name);
    if (raw == null) return null;
    final bool? value = _parseBool(raw);
    if (value == null) {
      acc.bad('The protection $name "$raw" is not a boolean.');
    } else if (value != written || raw != (written ? '1' : '0')) {
      acc.inexact();
    }
    return value;
  }

  final bool? locked = flag('locked', false);
  final bool? hidden = flag('hidden', true);
  if (r.attributeCount == 0) acc.inexact();
  _finishLeaf(r, acc);
  return acc.result<XlsxProtection?>(
    XlsxProtection(locked: locked, hidden: hidden),
  );
}

const ReadStyleValue<Null> _absent = (value: null, exact: true, problem: null);

/// Reads an `<xf>` element: its ids (an absent or unreadable one is 0), its
/// `xfId` as written (0 when absent), and its alignment and protection.
///
/// An `<xf>` is exact only with an `xfId` of 0 or none, no attribute beyond
/// the five ids and the `apply*` flags, and no child other than a readable
/// `alignment` and `protection` that are themselves exact. A cell format
/// with another `xfId` belongs to a named style and needs it kept.
({
  int numFmtId,
  int fontId,
  int fillId,
  int borderId,
  int xfId,
  ReadStyleValue<XlsxAlignment?> alignment,
  ReadStyleValue<XlsxProtection?> protection,
  bool exact,
})
readXf(XmlPullReader r) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{
    'numFmtId',
    'fontId',
    'fillId',
    'borderId',
    'xfId',
    'applyNumberFormat',
    'applyFont',
    'applyFill',
    'applyBorder',
    'applyAlignment',
    'applyProtection',
  });
  int id(String name) {
    final String? raw = _attr(r, name);
    if (raw == null) return 0;
    final int? value = readStyleId(raw);
    if (value == null) acc.inexact();
    return value ?? 0;
  }

  final int numFmtId = id('numFmtId');
  final int fontId = id('fontId');
  final int fillId = id('fillId');
  final int borderId = id('borderId');
  final int xfId = id('xfId');
  if (xfId != 0) acc.inexact();
  ReadStyleValue<XlsxAlignment?> alignment = _absent;
  ReadStyleValue<XlsxProtection?> protection = _absent;
  var sawAlignment = false;
  var sawProtection = false;
  _eachChild(r, acc, () {
    switch (r.localName) {
      case 'alignment':
        if (sawAlignment) {
          acc.inexact();
          r.skip();
        } else {
          sawAlignment = true;
          alignment = _readAlignment(r);
        }
        return true;
      case 'protection':
        if (sawProtection) {
          acc.inexact();
          r.skip();
        } else {
          sawProtection = true;
          protection = _readProtection(r);
        }
        return true;
    }
    return false;
  });
  acc.absorb(alignment);
  acc.absorb(protection);
  return (
    numFmtId: numFmtId,
    fontId: fontId,
    fillId: fillId,
    borderId: borderId,
    xfId: xfId,
    alignment: alignment,
    protection: protection,
    exact: acc.exact,
  );
}

// -- Differential styles -----------------------------------------------------

/// A differential style read from a `<dxf>`: what [readDifferentialStyle]
/// gives, and the number format as the element wrote it (`null` for none, or
/// for one that could not be read), which only a registry key needs.
typedef ReadDifferentialStyle = ({
  XlsxStyle value,
  bool exact,
  String? problem,
  DifferentialNumFmt? numFmt,
});

/// The children of a `<dxf>` in `CT_Dxf` order.
const Map<String, int> _dxfOrder = <String, int>{
  'font': 0,
  'numFmt': 1,
  'fill': 2,
  'alignment': 3,
  'border': 4,
  'protection': 5,
};

/// Reads a `<dxf>` element, the reverse of `writeDifferentialStyleXml`.
///
/// The value holds only what a differential style can hold, so it passes
/// `validateDifferentialStyle`: a font's flags, underline, script and colour,
/// a number format, a fill and the four sides of a border. A font name, size,
/// family, charset or scheme, an alignment, a protection, and a diagonal,
/// vertical or horizontal border side are read past and dropped, and make the
/// result inexact, as does anything else the writer would not write back:
/// the value is exact only when `writeDifferentialStyleXml` of it gives the
/// element that was read. A font flag is `null` when its element is absent
/// (the cell's font shows through) and `false` for `val="0"`. A number
/// format is the built-in one when the file's code is that format's code,
/// else a custom one; a custom id is the registry's to number, so it does
/// not make the element inexact.
ReadStyleValue<XlsxStyle> readDifferentialStyle(XmlPullReader r) {
  final ReadDifferentialStyle read = readDifferentialEntry(r);
  return (value: read.value, exact: read.exact, problem: read.problem);
}

/// [readDifferentialStyle], with the number format as written in the
/// element.
ReadDifferentialStyle readDifferentialEntry(XmlPullReader r) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{});
  XlsxFont? font;
  XlsxNumFmt? numFmt;
  DifferentialNumFmt? written;
  XlsxFill? fill;
  XlsxBorder? border;
  final Set<String> seen = <String>{};
  var last = -1;
  _eachChild(r, acc, () {
    final String n = r.localName;
    final int? rank = _dxfOrder[n];
    if (rank == null) return false;
    final bool first = seen.add(n);
    if (!first || rank < last) acc.inexact();
    if (rank > last) last = rank;
    if (!first) {
      // The first of a kind is the one read, as for a cell format.
      r.skip();
      return true;
    }
    switch (n) {
      case 'font':
        final ReadStyleValue<XlsxFont?> f = _readDifferentialFont(r);
        acc.absorb(f);
        font = f.value;
      case 'numFmt':
        final ({
          XlsxNumFmt? value,
          DifferentialNumFmt? written,
          bool exact,
          String? problem,
        })
        f = _readDifferentialNumFmt(r);
        acc.absorb((value: f.value, exact: f.exact, problem: f.problem));
        numFmt = f.value;
        written = f.written;
      case 'fill':
        final ReadStyleValue<XlsxFill> f = _readFill(r, differential: true);
        acc.absorb(f);
        fill = f.value;
      case 'border':
        final ReadStyleValue<XlsxBorder> b = readBorder(r);
        acc.absorb(b);
        final XlsxBorder read = b.value;
        // A differential style has the four sides and the outline flag.
        if (read.diagonal != null ||
            read.vertical != null ||
            read.horizontal != null ||
            read.diagonalUp != null ||
            read.diagonalDown != null) {
          acc.inexact();
        }
        border = XlsxBorder(
          left: read.left,
          right: read.right,
          top: read.top,
          bottom: read.bottom,
          outline: read.outline,
        );
      default:
        // An alignment or a protection: a differential style has neither.
        acc.inexact();
        r.skip();
    }
    return true;
  });
  return (
    value: XlsxStyle(numFmt: numFmt, font: font, fill: fill, border: border),
    exact: acc.exact,
    problem: acc.problem,
    numFmt: written,
  );
}

/// Reads the `<font>` of a differential style, which has no defaults: an
/// absent flag is `null`. The result is `null` for a font that sets nothing
/// a differential style can hold, which the writer does not write.
ReadStyleValue<XlsxFont?> _readDifferentialFont(XmlPullReader r) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{});
  bool? bold, italic, strike, condense, extend, outline, shadow;
  XlsxUnderline? underline;
  XlsxFontScript? script;
  XlsxColor? color;
  final Set<String> seen = <String>{};
  var last = -1;

  // `<b/>` is true and `<b val="0"/>` false, as the writer spells them.
  bool? flag(String name) {
    final String? val = _valOnly(r, acc);
    if (val == null) return true;
    final bool? value = _parseBool(val);
    if (value == null) {
      acc.bad('The font $name val "$val" is not a boolean.');
    } else if (val != '0') {
      acc.inexact();
    }
    return value;
  }

  _eachChild(r, acc, () {
    final String n = r.localName;
    final int? rank = _fontOrder[n];
    if (rank == null) return false;
    if (!seen.add(n) || rank < last) acc.inexact();
    if (rank > last) last = rank;
    switch (n) {
      case 'b':
        bold = flag(n);
      case 'i':
        italic = flag(n);
      case 'strike':
        strike = flag(n);
      case 'condense':
        condense = flag(n);
      case 'extend':
        extend = flag(n);
      case 'outline':
        outline = flag(n);
      case 'shadow':
        shadow = flag(n);
      case 'u':
        final String? val = _valOnly(r, acc);
        if (val == null) {
          underline = XlsxUnderline.single;
        } else {
          underline = _underlines[val];
          if (underline == null) {
            acc.bad('The font underline "$val" is not an underline style.');
          } else if (underline == XlsxUnderline.single) {
            acc.inexact();
          }
        }
      case 'vertAlign':
        final String? val = _valOnly(r, acc);
        script = val == null ? null : _scripts[val];
        if (script == null) {
          acc.bad('The font vertAlign "$val" is not a script.');
        } else if (script == XlsxFontScript.baseline) {
          acc.inexact();
        }
      case 'color':
        final ReadStyleValue<XlsxColor?> c = readColor(r);
        acc.absorb(c);
        color = c.value;
      default:
        // Size, name, family, charset and scheme: a differential style does
        // not hold them.
        acc.inexact();
        r.skip();
    }
    return true;
  });
  final bool sets =
      bold != null ||
      italic != null ||
      strike != null ||
      condense != null ||
      extend != null ||
      outline != null ||
      shadow != null ||
      underline != null ||
      color != null ||
      (script != null && script != XlsxFontScript.baseline);
  // The writer writes nothing for a font that sets nothing.
  if (!sets) {
    acc.inexact();
    return acc.result<XlsxFont?>(null);
  }
  return acc.result<XlsxFont?>(
    XlsxFont(
      bold: bold,
      italic: italic,
      strike: strike,
      condense: condense,
      extend: extend,
      outline: outline,
      shadow: shadow,
      underline: underline,
      script: script == XlsxFontScript.baseline ? null : script,
      color: color,
    ),
  );
}

/// Reads the `<numFmt>` of a differential style: the format, and the id and
/// code as written (`null` when the element has no usable id and code).
({XlsxNumFmt? value, DifferentialNumFmt? written, bool exact, String? problem})
_readDifferentialNumFmt(XmlPullReader r) {
  final _Acc acc = _Acc();
  _checkAttributes(r, acc, const <String>{'numFmtId', 'formatCode'});
  final String? rawId = _attr(r, 'numFmtId');
  final String? rawCode = _attr(r, 'formatCode');
  _finishLeaf(r, acc);
  final int? id = readStyleId(rawId);
  if (id == null) {
    acc.bad('The numFmt numFmtId "$rawId" is not a number format id.');
  }
  if (rawCode == null || rawCode.isEmpty) {
    acc.bad('The numFmt has no formatCode.');
  }
  if (id == null || rawCode == null || rawCode.isEmpty) {
    return (value: null, written: null, exact: false, problem: acc.problem);
  }
  final String code = decodeXstring(rawCode);
  if (code != rawCode) acc.inexact();
  if (scrubXmlText(code).removed != 0) {
    acc.bad('The numFmt formatCode has characters XML cannot carry.');
    return (value: null, written: null, exact: false, problem: acc.problem);
  }
  XlsxNumFmt value;
  if (id < 164 && builtinNumberFormatCode(id) == code) {
    value = XlsxNumFmt.builtin(id);
  } else {
    value = XlsxNumFmt.custom(code);
    // The writer numbers a custom format from 164, so an id below it with
    // another code is not one it would write.
    if (id < 164) acc.inexact();
  }
  return (
    value: value,
    written: (id: id, code: code),
    exact: acc.exact,
    problem: acc.problem,
  );
}
