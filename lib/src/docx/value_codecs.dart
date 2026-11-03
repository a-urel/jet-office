/// The codecs of the shared formatting values: colour, shading and border
/// (`w:color`, `w:shd`, `w:top` and the like), and the one writer of the
/// colour attributes.
///
/// Not ported from Quds; written for jet_office.
///
/// A colour is `auto` or six hex digits in its colour attribute, with a
/// theme colour in the matching theme attributes, whose tint and shade are
/// two hex digits. A theme colour is written with the colour attribute
/// `auto` beside its theme attributes: the schema requires the attribute
/// (`w:color/@w:val`), and Word draws the theme colour. Reading a colour
/// that has a theme colour gives the theme colour, whatever the colour
/// attribute holds. Each codec types an element only when it has no child
/// element and no text, and gives `null` for any value it cannot hold: a
/// colour that is neither `auto` nor six hex digits, a shading pattern or a
/// border line it has no name for (so an art border), a width or space out
/// of range (plan Rulings 2 and 4).
library;

import '../xml/xml_writer.dart';
import 'model/formatting.dart';
import 'property_codec.dart';
import 'units.dart';

final Map<String, DocxThemeColor> _themeColors = <String, DocxThemeColor>{
  for (final DocxThemeColor c in DocxThemeColor.values) c.name: c,
};

final Map<String, DocxShadingPattern> _patterns = <String, DocxShadingPattern>{
  for (final DocxShadingPattern p in DocxShadingPattern.values) p.name: p,
};

final Map<String, DocxBorderStyle> _borderStyles = <String, DocxBorderStyle>{
  for (final DocxBorderStyle s in DocxBorderStyle.values) s.name: s,
};

/// The names of the theme attributes that go with a colour attribute:
/// `theme` gives `themeColor`, `themeTint` and `themeShade`; `themeFill`
/// gives `themeFill`, `themeFillTint` and `themeFillShade`.
({String color, String tint, String shade}) _themeNames(String themePrefix) => (
  color: themePrefix == 'theme' ? 'themeColor' : themePrefix,
  tint: '${themePrefix}Tint',
  shade: '${themePrefix}Shade',
);

String _hexByte(int n) => n.toRadixString(16).toUpperCase().padLeft(2, '0');

/// Writes the attributes of [c]: [colorAttribute] (`val`, `color` or
/// `fill`) as `auto` or six hex digits, and, for a theme colour, the theme
/// attributes named by [themePrefix] (`theme` or `themeFill`), each
/// prefixed with [prefix].
///
/// This is the one writer of these attributes. A theme colour writes
/// [colorAttribute] as `auto`.
void writeColorAttributes(
  XmlWriter w,
  String prefix,
  DocxColor c, {
  required String colorAttribute,
  required String themePrefix,
}) {
  final DocxThemeColor? theme = c.themeColor;
  w.attribute('$prefix:$colorAttribute', c.rgb ?? 'auto');
  if (theme == null) {
    return;
  }
  final ({String color, String tint, String shade}) names = _themeNames(
    themePrefix,
  );
  w.attribute('$prefix:${names.color}', theme.name);
  final int? tint = c.tint;
  if (tint != null) {
    w.attribute('$prefix:${names.tint}', _hexByte(tint));
  }
  final int? shade = c.shade;
  if (shade != null) {
    w.attribute('$prefix:${names.shade}', _hexByte(shade));
  }
}

/// What [readColorAttributes] found: whether the element has the colour at
/// all, and its value, which is `null` when it has one that cannot be typed.
typedef ColorRead = ({bool present, DocxColor? color});

/// Reads the colour of [e] from `colorAttribute` and the theme attributes
/// named by `themePrefix`, as [writeColorAttributes] writes them.
///
/// The colour is present when [e] has the colour attribute or the theme
/// colour; its value is `null` when the attribute is neither `auto` nor six
/// hex digits, or a theme name, tint or shade is not valid.
ColorRead readColorAttributes(
  PropertyElement e, {
  required String colorAttribute,
  required String themePrefix,
}) {
  final ({String color, String tint, String shade}) names = _themeNames(
    themePrefix,
  );
  final String? raw = e.w(colorAttribute);
  final String? themeRaw = e.w(names.color);
  if (raw == null && themeRaw == null) {
    return (present: false, color: null);
  }
  const ColorRead invalid = (present: true, color: null);
  if (raw != null && raw != 'auto' && parseHex6(raw) == null) {
    return invalid;
  }
  if (themeRaw != null) {
    final DocxThemeColor? theme = parseEnum(themeRaw, _themeColors);
    final String? tintRaw = e.w(names.tint);
    final String? shadeRaw = e.w(names.shade);
    final int? tint = parseHexByte(tintRaw);
    final int? shade = parseHexByte(shadeRaw);
    if (theme == null ||
        (tintRaw != null && tint == null) ||
        (shadeRaw != null && shade == null)) {
      return invalid;
    }
    return (
      present: true,
      color: DocxColor.theme(theme, tint: tint, shade: shade),
    );
  }
  return (
    present: true,
    color: raw == 'auto' ? DocxColor.auto : DocxColor.rgb(parseHex6(raw)!),
  );
}

bool _plain(PropertyElement e) => e.children.isEmpty && !e.hasText;

/// The codec of a colour element such as `w:color`: its `w:val` is the
/// colour, with `w:themeColor`, `w:themeTint` and `w:themeShade`.
///
/// `w:val` is required; an element without it has no view.
final class ColorCodec extends PropertyCodec<DocxColor> {
  /// The codec of the colour element `w:<localName>`.
  const ColorCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{
    'val',
    'themeColor',
    'themeTint',
    'themeShade',
  };

  @override
  DocxColor? parse(PropertyElement e) {
    if (!_plain(e) || e.w('val') == null) {
      return null;
    }
    return readColorAttributes(
      e,
      colorAttribute: 'val',
      themePrefix: 'theme',
    ).color;
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxColor value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    writeColorAttributes(
      w,
      prefix,
      value,
      colorAttribute: 'val',
      themePrefix: 'theme',
    );
    w.end();
  }
}

/// The codec of `w:shd`: pattern (`w:val`, required), pattern colour and
/// fill, each with its theme attributes.
final class ShadingCodec extends PropertyCodec<DocxShading> {
  /// The codec of `w:shd`.
  const ShadingCodec() : super('shd');

  @override
  Set<String> get attributes => const <String>{
    'val',
    'color',
    'themeColor',
    'themeTint',
    'themeShade',
    'fill',
    'themeFill',
    'themeFillTint',
    'themeFillShade',
  };

  @override
  DocxShading? parse(PropertyElement e) {
    final DocxShadingPattern? pattern = parseEnum(e.w('val'), _patterns);
    if (!_plain(e) || pattern == null) {
      return null;
    }
    final ColorRead color = readColorAttributes(
      e,
      colorAttribute: 'color',
      themePrefix: 'theme',
    );
    final ColorRead fill = readColorAttributes(
      e,
      colorAttribute: 'fill',
      themePrefix: 'themeFill',
    );
    if ((color.present && color.color == null) ||
        (fill.present && fill.color == null)) {
      return null;
    }
    return DocxShading(pattern: pattern, color: color.color, fill: fill.color);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxShading value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', value.pattern.name);
    final DocxColor? color = value.color;
    if (color != null) {
      writeColorAttributes(
        w,
        prefix,
        color,
        colorAttribute: 'color',
        themePrefix: 'theme',
      );
    }
    final DocxColor? fill = value.fill;
    if (fill != null) {
      writeColorAttributes(
        w,
        prefix,
        fill,
        colorAttribute: 'fill',
        themePrefix: 'themeFill',
      );
    }
    w.end();
  }
}

/// The codec of a border element such as `w:top` or `w:bdr`: line
/// (`w:val`, required), width (`w:sz`, eighths of a point), space
/// (`w:space`, points), colour, shadow and frame.
///
/// A line the model has no name for (an art border) gives no view. A
/// missing width reads as 0.5 pt, and so does `w:sz="0"` on a line that is
/// not drawn (`nil` or `none`), since Word writes it for those; any other
/// width out of range or malformed, on a drawn line or not, and a space out
/// of range, give no view.
final class BorderCodec extends PropertyCodec<DocxBorder> {
  /// The codec of the border element `w:<localName>`.
  const BorderCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{
    'val',
    'sz',
    'space',
    'color',
    'themeColor',
    'themeTint',
    'themeShade',
    'shadow',
    'frame',
  };

  @override
  DocxBorder? parse(PropertyElement e) {
    final DocxBorderStyle? style = parseEnum(e.w('val'), _borderStyles);
    if (!_plain(e) || style == null) {
      return null;
    }
    final bool drawn =
        style != DocxBorderStyle.nil && style != DocxBorderStyle.none;
    final String? szRaw = e.w('sz');
    int? eighths = parseDecimal(szRaw, min: 2, max: 96);
    if (szRaw == null || (!drawn && szRaw == '0')) {
      eighths = 4;
    }
    final String? spaceRaw = e.w('space');
    final int? space = spaceRaw == null
        ? 0
        : parseDecimal(spaceRaw, min: 0, max: 31);
    final bool? shadow = parseOnOff(e.w('shadow') ?? 'false');
    final bool? frame = parseOnOff(e.w('frame') ?? 'false');
    final ColorRead color = readColorAttributes(
      e,
      colorAttribute: 'color',
      themePrefix: 'theme',
    );
    if (eighths == null ||
        space == null ||
        shadow == null ||
        frame == null ||
        (color.present && color.color == null)) {
      return null;
    }
    return DocxBorder(
      style: style,
      widthPt: ptOfEighths(eighths),
      spacePt: space.toDouble(),
      color: color.color,
      shadow: shadow,
      frame: frame,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxBorder value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', value.style.name);
    w.attribute(
      '$prefix:sz',
      '${eighthsOf(value.widthPt, 'widthPt', min: 2, max: 96)}',
    );
    w.attribute('$prefix:space', '${value.spacePt.round()}');
    final DocxColor? color = value.color;
    if (color != null) {
      writeColorAttributes(
        w,
        prefix,
        color,
        colorAttribute: 'color',
        themePrefix: 'theme',
      );
    }
    if (value.shadow) {
      w.attribute('$prefix:shadow', '1');
    }
    if (value.frame) {
      w.attribute('$prefix:frame', '1');
    }
    w.end();
  }
}
