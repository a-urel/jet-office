/// The values shared by run, paragraph, style and numbering formatting:
/// colours, shading and borders.
///
/// Not ported from Quds; written for jet_office.
///
/// Every value is immutable and equal by value. Lengths are points at the
/// API and are stored in the file's unit (a border's width in eighths of a
/// point), so a value reads back rounded to it and two values are equal
/// when their stored units are (plan Ruling 4). The `ST_` names of the
/// enums are their Dart names.
library;

import '../units.dart';

/// A theme colour of a document (`ST_ThemeColor`): the slot of the theme
/// part a colour refers to. The Dart name of each value is its spelling in
/// the file.
enum DocxThemeColor {
  /// The first dark colour.
  dark1,

  /// The first light colour.
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

  /// The hyperlink colour.
  hyperlink,

  /// The followed hyperlink colour.
  followedHyperlink,

  /// No theme colour.
  none,

  /// The first background colour (an alias of light 1 in Word's UI).
  background1,

  /// The first text colour (an alias of dark 1 in Word's UI).
  text1,

  /// The second background colour (an alias of light 2).
  background2,

  /// The second text colour (an alias of dark 2).
  text2,
}

/// A colour: automatic, six hex digits, or a theme colour with an optional
/// tint or shade.
final class DocxColor {
  /// A colour of six hex digits, such as `FF8800`, stored in upper case.
  ///
  /// Throws [ArgumentError] when [hex] is not exactly six hex digits.
  DocxColor.rgb(String hex)
    : rgb = _checkHex(hex),
      themeColor = null,
      tint = null,
      shade = null,
      isAuto = false;

  /// The theme colour [color], lightened by [tint] or darkened by [shade]
  /// (0 to 255 each, as the file stores them).
  ///
  /// Throws [RangeError] when [tint] or [shade] is outside 0 to 255.
  DocxColor.theme(DocxThemeColor color, {int? tint, int? shade})
    : rgb = null,
      themeColor = color,
      tint = _checkByte(tint, 'tint'),
      shade = _checkByte(shade, 'shade'),
      isAuto = false;

  const DocxColor._auto()
    : rgb = null,
      themeColor = null,
      tint = null,
      shade = null,
      isAuto = true;

  /// The automatic colour: black on a light background and white on a dark
  /// one, as the reader of the document chooses.
  static const DocxColor auto = DocxColor._auto();

  /// The six hex digits in upper case, or `null` for an automatic or theme
  /// colour.
  final String? rgb;

  /// The theme colour, or `null` for an automatic or RGB colour.
  final DocxThemeColor? themeColor;

  /// The theme colour's tint (0 to 255), or `null`.
  final int? tint;

  /// The theme colour's shade (0 to 255), or `null`.
  final int? shade;

  /// Whether the colour is automatic.
  final bool isAuto;

  static String _checkHex(String hex) {
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      throw ArgumentError.value(
        hex,
        'hex',
        'must be exactly six hex digits, such as FF8800',
      );
    }
    return hex.toUpperCase();
  }

  static int? _checkByte(int? value, String name) {
    if (value != null && (value < 0 || value > 255)) {
      throw RangeError.range(value, 0, 255, name);
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is DocxColor &&
      other.rgb == rgb &&
      other.themeColor == themeColor &&
      other.tint == tint &&
      other.shade == shade &&
      other.isAuto == isAuto;

  @override
  int get hashCode => Object.hash(rgb, themeColor, tint, shade, isAuto);

  @override
  String toString() => isAuto
      ? 'DocxColor.auto'
      : rgb != null
      ? 'DocxColor.rgb($rgb)'
      : 'DocxColor.theme(${themeColor!.name}, tint: $tint, shade: $shade)';
}

/// A shading pattern (`ST_Shd`): how the pattern colour is laid over the
/// fill. The Dart name of each value is its spelling in the file.
enum DocxShadingPattern {
  /// No shading.
  nil,

  /// Only the fill shows.
  clear,

  /// Only the pattern colour shows.
  solid,

  /// Horizontal stripes.
  horzStripe,

  /// Vertical stripes.
  vertStripe,

  /// Reverse diagonal stripes.
  reverseDiagStripe,

  /// Diagonal stripes.
  diagStripe,

  /// Horizontal cross hatch.
  horzCross,

  /// Diagonal cross hatch.
  diagCross,

  /// Thin horizontal stripes.
  thinHorzStripe,

  /// Thin vertical stripes.
  thinVertStripe,

  /// Thin reverse diagonal stripes.
  thinReverseDiagStripe,

  /// Thin diagonal stripes.
  thinDiagStripe,

  /// Thin horizontal cross hatch.
  thinHorzCross,

  /// Thin diagonal cross hatch.
  thinDiagCross,

  /// 5 percent pattern colour.
  pct5,

  /// 10 percent pattern colour.
  pct10,

  /// 12.5 percent pattern colour.
  pct12,

  /// 15 percent pattern colour.
  pct15,

  /// 20 percent pattern colour.
  pct20,

  /// 25 percent pattern colour.
  pct25,

  /// 30 percent pattern colour.
  pct30,

  /// 35 percent pattern colour.
  pct35,

  /// 37.5 percent pattern colour.
  pct37,

  /// 40 percent pattern colour.
  pct40,

  /// 45 percent pattern colour.
  pct45,

  /// 50 percent pattern colour.
  pct50,

  /// 55 percent pattern colour.
  pct55,

  /// 60 percent pattern colour.
  pct60,

  /// 62.5 percent pattern colour.
  pct62,

  /// 65 percent pattern colour.
  pct65,

  /// 70 percent pattern colour.
  pct70,

  /// 75 percent pattern colour.
  pct75,

  /// 80 percent pattern colour.
  pct80,

  /// 85 percent pattern colour.
  pct85,

  /// 87.5 percent pattern colour.
  pct87,

  /// 90 percent pattern colour.
  pct90,

  /// 95 percent pattern colour.
  pct95,
}

/// The shading of a paragraph, a run, a cell or a table (`w:shd`): a
/// [pattern] drawn in [color] over a [fill].
///
/// The common case is a plain background: `DocxShading(fill:
/// DocxColor.rgb('FFFF00'))`.
final class DocxShading {
  /// A shading of [pattern] in [color] over [fill]; an omitted colour is
  /// not written, and Word reads it as automatic.
  const DocxShading({
    this.pattern = DocxShadingPattern.clear,
    this.color,
    this.fill,
  });

  /// The pattern.
  final DocxShadingPattern pattern;

  /// The colour of the pattern, or `null` when the file has none.
  final DocxColor? color;

  /// The background colour, or `null` when the file has none.
  final DocxColor? fill;

  @override
  bool operator ==(Object other) =>
      other is DocxShading &&
      other.pattern == pattern &&
      other.color == color &&
      other.fill == fill;

  @override
  int get hashCode => Object.hash(pattern, color, fill);

  @override
  String toString() =>
      'DocxShading(${pattern.name}, color: $color, fill: $fill)';
}

/// The line of a border (`ST_Border`, without the art borders). The Dart
/// name of each value is its spelling in the file.
///
/// A border with an art pattern (apples, stars) reads as `null`: the
/// model does not type it, and the file keeps it as written.
enum DocxBorderStyle {
  /// No border, as if the element were absent.
  nil,

  /// No border.
  none,

  /// A single line.
  single,

  /// A thick line.
  thick,

  /// A double line.
  double,

  /// A dotted line.
  dotted,

  /// A dashed line.
  dashed,

  /// Alternating dashes and dots.
  dotDash,

  /// A dash and two dots, repeated.
  dotDotDash,

  /// Three lines.
  triple,

  /// A thin line outside a thick one, small gap.
  thinThickSmallGap,

  /// A thick line outside a thin one, small gap.
  thickThinSmallGap,

  /// Thin, thick and thin lines, small gaps.
  thinThickThinSmallGap,

  /// A thin line outside a thick one, medium gap.
  thinThickMediumGap,

  /// A thick line outside a thin one, medium gap.
  thickThinMediumGap,

  /// Thin, thick and thin lines, medium gaps.
  thinThickThinMediumGap,

  /// A thin line outside a thick one, large gap.
  thinThickLargeGap,

  /// A thick line outside a thin one, large gap.
  thickThinLargeGap,

  /// Thin, thick and thin lines, large gaps.
  thinThickThinLargeGap,

  /// A wavy line.
  wave,

  /// A double wavy line.
  doubleWave,

  /// A dashed line with small gaps.
  dashSmallGap,

  /// A dash and dot line, stroked.
  dashDotStroked,

  /// A three-dimensional embossed line.
  threeDEmboss,

  /// A three-dimensional engraved line.
  threeDEngrave,

  /// An outset line.
  outset,

  /// An inset line.
  inset,
}

/// One border line (`w:top`, `w:left`, `w:bdr` and the like).
///
/// The width is stored in eighths of a point (0.25 to 12 pt) and the space
/// between the border and the text in whole points (0 to 31), so a value
/// reads back rounded to them.
final class DocxBorder {
  /// A border of [style] and [widthPt] points, [spacePt] points from the
  /// text, in [color] (`null` writes none, which Word reads as
  /// automatic).
  ///
  /// Throws [ArgumentError] for a width or space that is not finite and
  /// [RangeError] for one outside 0.25 to 12 points or 0 to 31 points once
  /// rounded.
  DocxBorder({
    this.style = DocxBorderStyle.single,
    double widthPt = 0.5,
    double spacePt = 0,
    this.color,
    this.shadow = false,
    this.frame = false,
  }) : _eighths = eighthsOf(widthPt, 'widthPt', min: 2, max: 96),
       _space = pointsOf(spacePt, 'spacePt', min: 0, max: 31);

  /// The line.
  final DocxBorderStyle style;

  /// The colour, or `null` when the file has none.
  final DocxColor? color;

  /// Whether the border has a shadow.
  final bool shadow;

  /// Whether the border is a frame.
  final bool frame;

  final int _eighths;

  final int _space;

  /// The width in points, a multiple of 0.125.
  double get widthPt => ptOfEighths(_eighths);

  /// The space between the border and the text, in whole points.
  double get spacePt => _space.toDouble();

  @override
  bool operator ==(Object other) =>
      other is DocxBorder &&
      other.style == style &&
      other._eighths == _eighths &&
      other._space == _space &&
      other.color == color &&
      other.shadow == shadow &&
      other.frame == frame;

  @override
  int get hashCode =>
      Object.hash(style, _eighths, _space, color, shadow, frame);

  @override
  String toString() =>
      'DocxBorder(${style.name}, $widthPt pt, space: $spacePt pt, '
      'color: $color)';
}
