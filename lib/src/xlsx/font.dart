/// Fonts for cell formats.
///
/// New in jet_office. Quds keeps a font as a private `_Font` class inside
/// `builders/xlsx_io.dart` with a few fields and no validation; here a font is
/// a public, model-neutral value type with every `CT_Font` property, and the
/// writer checks it when it is registered.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'color.dart';
import 'limits.dart';

/// The name [resolveFont] gives a font without one.
const String _defaultFontName = 'Calibri';

/// The size [resolveFont] gives a font without one.
const double _defaultFontSize = 11;

/// Excel's longest font name, in UTF-16 code units.
const int _maxNameLength = 31;

/// How text is underlined (`ST_UnderlineValues`).
enum XlsxUnderline {
  /// No underline.
  none,

  /// A single line under the text.
  single,

  /// A double line under the text; written as `double`.
  doubleLine,

  /// A single line for accounting columns.
  singleAccounting,

  /// A double line for accounting columns.
  doubleAccounting,
}

/// Where text sits relative to the baseline (`ST_VerticalAlignRun`).
enum XlsxFontScript {
  /// On the baseline.
  baseline,

  /// Raised and smaller.
  superscript,

  /// Lowered and smaller.
  subscript,
}

/// The theme font scheme a font belongs to (`ST_FontScheme`).
enum XlsxFontScheme {
  /// Not tied to the theme.
  none,

  /// The theme's heading font.
  major,

  /// The theme's body font.
  minor,
}

/// A font as SpreadsheetML (`CT_Font`) describes it.
///
/// Every field is nullable, and `null` means "inherit": [merge] lets the
/// non-null fields of one font win over another, and a font that reaches the
/// writer with no [name] or [size] gets `Calibri` and `11`. The `const`
/// constructor cannot check its arguments; the writer does, when the font is
/// registered, and throws [ArgumentError] naming the field.
final class XlsxFont {
  /// Creates a font. See each field for its limits.
  const XlsxFont({
    this.name,
    this.size,
    this.color,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.script,
    this.outline,
    this.shadow,
    this.condense,
    this.extend,
    this.family,
    this.charset,
    this.scheme,
  });

  /// The typeface name, 1 to 31 UTF-16 code units.
  final String? name;

  /// The size in points, finite within 1 to [XlsxLimits.maxFontSize].
  final double? size;

  /// The text color.
  final XlsxColor? color;

  /// Whether the text is bold.
  final bool? bold;

  /// Whether the text is italic.
  final bool? italic;

  /// The underline style.
  final XlsxUnderline? underline;

  /// Whether the text is struck through.
  final bool? strike;

  /// Superscript or subscript.
  final XlsxFontScript? script;

  /// Whether the text is drawn as an outline (a Macintosh option).
  final bool? outline;

  /// Whether the text has a shadow (a Macintosh option).
  final bool? shadow;

  /// Whether the text is condensed (a Macintosh option).
  final bool? condense;

  /// Whether the text is extended (a Macintosh option).
  final bool? extend;

  /// The font family class (`CT_Font.family`), within `0..14`.
  final int? family;

  /// The character set (`CT_Font.charset`), within `0..255`.
  final int? charset;

  /// The theme font scheme.
  final XlsxFontScheme? scheme;

  /// This font with every non-null field of [other] applied on top.
  ///
  /// A null [other] changes nothing.
  XlsxFont merge(XlsxFont? other) {
    if (other == null) {
      return this;
    }
    return copyWith(
      name: other.name,
      size: other.size,
      color: other.color,
      bold: other.bold,
      italic: other.italic,
      underline: other.underline,
      strike: other.strike,
      script: other.script,
      outline: other.outline,
      shadow: other.shadow,
      condense: other.condense,
      extend: other.extend,
      family: other.family,
      charset: other.charset,
      scheme: other.scheme,
    );
  }

  /// A copy with each given (non-null) field replaced.
  ///
  /// A field cannot be reset to null with this method.
  XlsxFont copyWith({
    String? name,
    double? size,
    XlsxColor? color,
    bool? bold,
    bool? italic,
    XlsxUnderline? underline,
    bool? strike,
    XlsxFontScript? script,
    bool? outline,
    bool? shadow,
    bool? condense,
    bool? extend,
    int? family,
    int? charset,
    XlsxFontScheme? scheme,
  }) => XlsxFont(
    name: name ?? this.name,
    size: size ?? this.size,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    script: script ?? this.script,
    outline: outline ?? this.outline,
    shadow: shadow ?? this.shadow,
    condense: condense ?? this.condense,
    extend: extend ?? this.extend,
    family: family ?? this.family,
    charset: charset ?? this.charset,
    scheme: scheme ?? this.scheme,
  );

  @override
  bool operator ==(Object other) =>
      other is XlsxFont &&
      other.name == name &&
      other.size == size &&
      other.color == color &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.script == script &&
      other.outline == outline &&
      other.shadow == shadow &&
      other.condense == condense &&
      other.extend == extend &&
      other.family == family &&
      other.charset == charset &&
      other.scheme == scheme;

  @override
  int get hashCode => Object.hash(
    name,
    size,
    color,
    bold,
    italic,
    underline,
    strike,
    script,
    outline,
    shadow,
    condense,
    extend,
    family,
    charset,
    scheme,
  );

  @override
  String toString() {
    final List<String> parts = <String>[
      if (name != null) 'name: $name',
      if (size != null) 'size: $size',
      if (color != null) 'color: $color',
      if (bold != null) 'bold: $bold',
      if (italic != null) 'italic: $italic',
      if (underline != null) 'underline: $underline',
      if (strike != null) 'strike: $strike',
      if (script != null) 'script: $script',
      if (outline != null) 'outline: $outline',
      if (shadow != null) 'shadow: $shadow',
      if (condense != null) 'condense: $condense',
      if (extend != null) 'extend: $extend',
      if (family != null) 'family: $family',
      if (charset != null) 'charset: $charset',
      if (scheme != null) 'scheme: $scheme',
    ];
    return 'XlsxFont(${parts.join(', ')})';
  }
}

/// [font] with a null `name` set to `Calibri` and a null `size` set to `11`.
///
/// A null [font] gives the default font, which is the font at id 0 of every
/// workbook.
XlsxFont resolveFont(XlsxFont? font) => (font ?? const XlsxFont()).copyWith(
  name: font?.name ?? _defaultFontName,
  size: font?.size ?? _defaultFontSize,
);

/// Checks a resolved [font] against Excel's limits: a non-empty XML-clean
/// name of at most 31 UTF-16 code units, a finite size within 1 to 409, a
/// family within `0..14`, a charset within `0..255` and a valid color.
///
/// Throws [ArgumentError] naming the field.
void validateFont(XlsxFont font) {
  final String? name = font.name;
  if (name != null) {
    if (name.isEmpty ||
        name.length > _maxNameLength ||
        scrubXmlText(name).removed > 0) {
      throw ArgumentError.value(
        name,
        'name',
        'A font name must be 1 to $_maxNameLength UTF-16 code units of '
            'XML-clean text.',
      );
    }
  }
  final double? size = font.size;
  if (size != null &&
      !(size.isFinite && size >= 1 && size <= XlsxLimits.maxFontSize)) {
    throw ArgumentError.value(
      size,
      'size',
      'A font size must be finite and within '
          '1..${XlsxLimits.maxFontSize} points.',
    );
  }
  final int? family = font.family;
  if (family != null && (family < 0 || family > 14)) {
    throw ArgumentError.value(
      family,
      'family',
      'A font family must be within 0..14.',
    );
  }
  final int? charset = font.charset;
  if (charset != null && (charset < 0 || charset > 255)) {
    throw ArgumentError.value(
      charset,
      'charset',
      'A font charset must be within 0..255.',
    );
  }
  final XlsxColor? color = font.color;
  if (color != null) {
    validateColor(color, 'color');
  }
}

/// Writes [resolved] as one `<font>` element, children in `CT_Font` order.
///
/// `false`, `none` and `baseline` are Excel's defaults and are omitted. The
/// font must have passed [resolveFont] and [validateFont].
void writeFontXml(XmlWriter w, XlsxFont resolved) {
  w.start('font');
  if (resolved.bold ?? false) {
    w.empty('b');
  }
  if (resolved.italic ?? false) {
    w.empty('i');
  }
  if (resolved.strike ?? false) {
    w.empty('strike');
  }
  if (resolved.condense ?? false) {
    w.empty('condense');
  }
  if (resolved.extend ?? false) {
    w.empty('extend');
  }
  if (resolved.outline ?? false) {
    w.empty('outline');
  }
  if (resolved.shadow ?? false) {
    w.empty('shadow');
  }
  switch (resolved.underline) {
    case null:
    case XlsxUnderline.none:
      break;
    case XlsxUnderline.single:
      w.empty('u');
    case XlsxUnderline.doubleLine:
      w.empty('u', <String, String>{'val': 'double'});
    case XlsxUnderline.singleAccounting:
      w.empty('u', <String, String>{'val': 'singleAccounting'});
    case XlsxUnderline.doubleAccounting:
      w.empty('u', <String, String>{'val': 'doubleAccounting'});
  }
  final XlsxFontScript? script = resolved.script;
  if (script != null && script != XlsxFontScript.baseline) {
    w.empty('vertAlign', <String, String>{'val': script.name});
  }
  final double? size = resolved.size;
  if (size != null) {
    w.empty('sz', <String, String>{'val': formatXmlDouble(size)});
  }
  final XlsxColor? color = resolved.color;
  if (color != null) {
    w.start('color');
    writeColorAttributes(w, color);
    w.end();
  }
  final String? name = resolved.name;
  if (name != null) {
    w.empty('name', <String, String>{'val': name});
  }
  final int? family = resolved.family;
  if (family != null) {
    w.empty('family', <String, String>{'val': '$family'});
  }
  final int? charset = resolved.charset;
  if (charset != null) {
    w.empty('charset', <String, String>{'val': '$charset'});
  }
  final XlsxFontScheme? scheme = resolved.scheme;
  if (scheme != null && scheme != XlsxFontScheme.none) {
    w.empty('scheme', <String, String>{'val': scheme.name});
  }
  w.end();
}
