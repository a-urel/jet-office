/// The codecs of the children of a run's `w:rPr`, and the schema that
/// types them.
///
/// Not ported from Quds; written for jet_office.
///
/// [runPropertiesSchema] types the sixteen properties of
/// `DocxRunProperties`. A child is typed only when it is in `w:`, occurs
/// once, has no `w:` attribute its codec does not list, and parses (plan
/// Ruling 2); `w:sz w:val="abc"` or `1in`, `w:b w:val="maybe"` or a colour
/// `red` read `null` and are written back as read.
///
/// Two codecs keep what the model does not type (Ruling 3, and the
/// complex-script variants of spec §2): [FontsCodec] keeps `w:cs`,
/// `w:cstheme`, `w:hint` and every attribute but the six it sets, and
/// [LanguageCodec] keeps `w:eastAsia` and `w:bidi`. Those attributes are in
/// the codec's [PropertyCodec.attributes], so a Word file that has them
/// still types its fonts and language.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'model/formatting.dart';
import 'properties.dart';
import 'property_codec.dart';
import 'schema_order.dart';
import 'units.dart';
import 'value_codecs.dart';

bool _plain(PropertyElement e) => e.children.isEmpty && !e.hasText;

/// The smallest and largest `w:sz`, in half-points: 1 to 1638 points.
const int _minSize = 2;
const int _maxSize = 3276;

/// The smallest and largest `w:spacing/@w:val`, in twips: -1584 to 1584
/// points.
const int _minSpacing = -31680;
const int _maxSpacing = 31680;

final RegExp _language = RegExp(r'^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$');

/// Whether [value] is a language tag the model types: letters, then
/// groups of letters and digits joined by hyphens (`tr`, `tr-TR`,
/// `zh-Hant-TW`).
bool isLanguageTag(String value) => _language.hasMatch(value);

/// The theme fonts `w:rFonts` may name (`ST_Theme`).
const Set<String> _themeFonts = <String>{
  'majorEastAsia',
  'majorBidi',
  'majorAscii',
  'majorHAnsi',
  'minorEastAsia',
  'minorBidi',
  'minorAscii',
  'minorHAnsi',
};

/// Writes the attributes of [asRead] that are not in [replaced] (local
/// names in `w:`), as the codec of a set value keeps them (plan Ruling 3).
///
/// An attribute in `w:` is written with [prefix]; one in another namespace
/// keeps its own prefix and declares it. One whose prefix is [prefix] but
/// is not WordprocessingML cannot be written beside `[prefix]:` attributes
/// and is dropped.
void _writeKept(
  XmlWriter w,
  String prefix,
  PropertyElement? asRead,
  Set<String> replaced,
) {
  if (asRead == null) {
    return;
  }
  for (final KeptAttribute a in asRead.attributes) {
    final String name = a.qualifiedName;
    final int colon = name.indexOf(':');
    if (a.namespaceUri == Ns.w) {
      final String local = name.substring(colon + 1);
      if (!replaced.contains(local)) {
        w.attribute('$prefix:$local', scrubXmlText(a.value).text);
      }
    } else if (colon <= 0 || name.substring(0, colon) != prefix) {
      writeKeptAttributes(w, <KeptAttribute>[a]);
    }
  }
}

/// The codec of an on/off property such as `w:b`: `true` is written as the
/// bare element and `false` as `w:val="0"`.
///
/// `w:val` reads as `ST_OnOff` does: absent, `true`, `1` or `on` is `true`,
/// `false`, `0` or `off` is `false`, anything else gives no view.
final class OnOffCodec extends PropertyCodec<bool> {
  /// The codec of the on/off element `w:<localName>`.
  const OnOffCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  bool? parse(PropertyElement e) => _plain(e) ? parseOnOff(e.w('val')) : null;

  @override
  void write(XmlWriter w, String prefix, bool value, PropertyElement? asRead) {
    w.start('$prefix:$localName');
    if (!value) {
      w.attribute('$prefix:val', '0');
    }
    w.end();
  }
}

/// The codec of a length in points stored as a whole number of half-points
/// or twips in `w:val`: `w:sz` and `w:spacing`.
///
/// Use [sizeCodec] and [characterSpacingCodec].
final class MeasureCodec extends PropertyCodec<double> {
  /// A codec of `w:<localName>` that stores a number of units per point,
  /// from a smallest to a largest count; the last argument names the value
  /// in errors.
  const MeasureCodec(
    super.localName,
    this._perPoint,
    this._min,
    this._max,
    this._parameter,
  );

  final int _perPoint;
  final int _min;
  final int _max;
  final String _parameter;

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  double? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    final int? n = parseDecimal(e.w('val'), min: _min, max: _max);
    return n == null ? null : n / _perPoint;
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    double value,
    PropertyElement? asRead,
  ) {
    final int n = stored(value);
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', '$n');
    w.end();
  }

  /// [pt] points in the file's unit, rounded; throws as `units.dart` does.
  int stored(double pt) => _perPoint == 2
      ? halfPointsOf(pt, _parameter, min: _min, max: _max)
      : twipsOf(pt, _parameter, min: _min, max: _max);

  /// [pt] rounded to the file's unit, as it reads back.
  double rounded(double pt) => stored(pt) / _perPoint;
}

/// The codec of `w:sz`, the font size in half-points: 1 to 1638 points.
const MeasureCodec sizeCodec = MeasureCodec(
  'sz',
  2,
  _minSize,
  _maxSize,
  'sizePt',
);

/// The codec of `w:spacing`, the character spacing in twips: -1584 to 1584
/// points.
const MeasureCodec characterSpacingCodec = MeasureCodec(
  'spacing',
  20,
  _minSpacing,
  _maxSpacing,
  'characterSpacingPt',
);

/// [pt] rounded to a half-point as `w:sz` stores it; throws
/// [ArgumentError] for a value that is not finite and [RangeError] outside
/// 1 to 1638 points.
double roundedSizePt(double pt) => sizeCodec.rounded(pt);

/// [pt] rounded to a twip as `w:spacing` stores it; throws
/// [ArgumentError] for a value that is not finite and [RangeError] outside
/// -1584 to 1584 points.
double roundedCharacterSpacingPt(double pt) =>
    characterSpacingCodec.rounded(pt);

/// The codec of a property whose `w:val` is one of an enum's values, such
/// as `w:highlight` and `w:vertAlign`; a subclass gives the values.
abstract base class ValEnumCodec<E extends Enum> extends PropertyCodec<E> {
  /// The codec of the child `w:<localName>`.
  const ValEnumCodec(super.localName);

  /// The enum value of each spelling of `w:val`.
  Map<String, E> get byXml;

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  E? parse(PropertyElement e) =>
      _plain(e) ? parseEnum(e.w('val'), byXml) : null;

  @override
  void write(XmlWriter w, String prefix, E value, PropertyElement? asRead) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', value.name);
    w.end();
  }
}

final Map<String, DocxHighlight> _highlights = <String, DocxHighlight>{
  for (final DocxHighlight h in DocxHighlight.values) h.name: h,
};

/// The codec of `w:highlight`.
final class HighlightCodec extends ValEnumCodec<DocxHighlight> {
  /// The codec of `w:highlight`.
  const HighlightCodec() : super('highlight');

  @override
  Map<String, DocxHighlight> get byXml => _highlights;
}

final Map<String, DocxVerticalAlign> _verticalAligns =
    <String, DocxVerticalAlign>{
      for (final DocxVerticalAlign v in DocxVerticalAlign.values) v.name: v,
    };

/// The codec of `w:vertAlign`.
final class VerticalAlignCodec extends ValEnumCodec<DocxVerticalAlign> {
  /// The codec of `w:vertAlign`.
  const VerticalAlignCodec() : super('vertAlign');

  @override
  Map<String, DocxVerticalAlign> get byXml => _verticalAligns;
}

final Map<String, DocxUnderlineStyle> _underlineStyles =
    <String, DocxUnderlineStyle>{
      for (final DocxUnderlineStyle s in DocxUnderlineStyle.values) s.name: s,
    };

/// The codec of `w:u`: line style (`w:val`) with an optional colour.
///
/// `w:val` is required here; an underline without it has no view.
final class UnderlineCodec extends PropertyCodec<DocxUnderline> {
  /// The codec of `w:u`.
  const UnderlineCodec() : super('u');

  @override
  Set<String> get attributes => const <String>{
    'val',
    'color',
    'themeColor',
    'themeTint',
    'themeShade',
  };

  @override
  DocxUnderline? parse(PropertyElement e) {
    final DocxUnderlineStyle? style = parseEnum(e.w('val'), _underlineStyles);
    if (!_plain(e) || style == null) {
      return null;
    }
    final ColorRead color = readColorAttributes(
      e,
      colorAttribute: 'color',
      themePrefix: 'theme',
    );
    if (color.present && color.color == null) {
      return null;
    }
    return DocxUnderline(style, color: color.color);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxUnderline value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', value.style.name);
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
    w.end();
  }
}

const Set<String> _fontSlots = <String>{
  'ascii',
  'hAnsi',
  'eastAsia',
  'asciiTheme',
  'hAnsiTheme',
  'eastAsiaTheme',
};

/// The codec of `w:rFonts`: the ASCII, high ANSI and East Asian slots and
/// their theme fonts.
///
/// `w:cs`, `w:cstheme` and `w:hint` are understood, so a Word file that has
/// them still types its fonts; a set replaces the six slot attributes and
/// keeps every other attribute as read (plan Ruling 3). An element with no
/// slot, or an empty name, has no view.
final class FontsCodec extends PropertyCodec<DocxFonts> {
  /// The codec of `w:rFonts`.
  const FontsCodec() : super('rFonts');

  @override
  Set<String> get attributes => const <String>{
    ..._fontSlots,
    'cs',
    'cstheme',
    'hint',
  };

  @override
  DocxFonts? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    bool bad = false;
    String? name(String slot) {
      final String? v = e.w(slot);
      if (v != null && (v.isEmpty || scrubXmlText(v).removed > 0)) {
        bad = true;
      }
      return v;
    }

    String? theme(String slot) {
      final String? v = e.w(slot);
      if (v != null && !_themeFonts.contains(v)) {
        bad = true;
      }
      return v;
    }

    final DocxFonts fonts = readFonts(
      ascii: name('ascii'),
      hAnsi: name('hAnsi'),
      eastAsia: name('eastAsia'),
      asciiTheme: theme('asciiTheme'),
      hAnsiTheme: theme('hAnsiTheme'),
      eastAsiaTheme: theme('eastAsiaTheme'),
    );
    final bool any =
        fonts.ascii != null ||
        fonts.hAnsi != null ||
        fonts.eastAsia != null ||
        fonts.asciiTheme != null ||
        fonts.hAnsiTheme != null ||
        fonts.eastAsiaTheme != null;
    return bad || !any ? null : fonts;
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxFonts value,
    PropertyElement? asRead,
  ) => _writeFonts(w, '$prefix:$localName', prefix, value, asRead);
}

/// Writes the `w:rFonts` [qualifiedName] of [value]: its six slots, then
/// [extra] (attribute local name to value, written with [prefix]), then
/// every other attribute of [asRead] as read.
void _writeFonts(
  XmlWriter w,
  String qualifiedName,
  String prefix,
  DocxFonts value,
  PropertyElement? asRead, {
  Map<String, String> extra = const <String, String>{},
}) {
  w.start(qualifiedName);
  void slot(String name, String? v) {
    if (v != null) w.attribute('$prefix:$name', scrubXmlText(v).text);
  }

  slot('ascii', value.ascii);
  slot('hAnsi', value.hAnsi);
  slot('eastAsia', value.eastAsia);
  slot('asciiTheme', value.asciiTheme);
  slot('hAnsiTheme', value.hAnsiTheme);
  slot('eastAsiaTheme', value.eastAsiaTheme);
  extra.forEach(slot);
  _writeKept(w, prefix, asRead, <String>{..._fontSlots, ...extra.keys});
  w.end();
}

/// The codec of the `w:rFonts` of a numbering level's `w:rPr`: the font of
/// a bullet.
///
/// It reads as [FontsCodec] does. A set writes the slots the value names
/// and keeps every other attribute as read (`w:cs`, `w:hint`, say), as
/// [FontsCodec] does (plan Ruling 3); a `w:rFonts` without `w:hint` gets
/// `w:hint="default"`, as Word writes a bullet's font.
final class BulletFontsCodec extends PropertyCodec<DocxFonts> {
  /// The codec of a level's `w:rFonts`.
  const BulletFontsCodec() : super('rFonts');

  @override
  Set<String> get attributes => const FontsCodec().attributes;

  @override
  DocxFonts? parse(PropertyElement e) => const FontsCodec().parse(e);

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxFonts value,
    PropertyElement? asRead,
  ) {
    _writeFonts(
      w,
      '$prefix:$localName',
      prefix,
      value,
      asRead,
      extra: asRead?.w('hint') == null
          ? const <String, String>{'hint': 'default'}
          : const <String, String>{},
    );
  }
}

/// The codec of `w:lang`: the language of Latin text (`w:val`).
///
/// `w:eastAsia` and `w:bidi` are understood and kept as read when the
/// language is set (plan Ruling 3). An element without `w:val`, or with
/// one that is not a language tag ([isLanguageTag]), has no view.
final class LanguageCodec extends PropertyCodec<String> {
  /// The codec of `w:lang`.
  const LanguageCodec() : super('lang');

  @override
  Set<String> get attributes => const <String>{'val', 'eastAsia', 'bidi'};

  @override
  String? parse(PropertyElement e) {
    final String? value = e.w('val');
    return _plain(e) && value != null && isLanguageTag(value) ? value : null;
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    String value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', value);
    _writeKept(w, prefix, asRead, const <String>{'val'});
    w.end();
  }
}

/// The schema of a run's `w:rPr`: [rPrOrder], typing the sixteen
/// properties of `DocxRunProperties`.
const ContainerSchema runPropertiesSchema = ContainerSchema(
  rPrOrder,
  codecs: <String, PropertyCodec<Object>>{
    'rStyle': StyleIdCodec('rStyle'),
    'rFonts': FontsCodec(),
    'b': OnOffCodec('b'),
    'i': OnOffCodec('i'),
    'caps': OnOffCodec('caps'),
    'smallCaps': OnOffCodec('smallCaps'),
    'strike': OnOffCodec('strike'),
    'dstrike': OnOffCodec('dstrike'),
    'color': ColorCodec('color'),
    'spacing': characterSpacingCodec,
    'sz': sizeCodec,
    'highlight': HighlightCodec(),
    'u': UnderlineCodec(),
    'shd': ShadingCodec(),
    'vertAlign': VerticalAlignCodec(),
    'lang': LanguageCodec(),
  },
);
