/// The values shared by run, paragraph, style and numbering formatting:
/// colours, shading and borders, the values of run properties (fonts,
/// underline, highlight, vertical alignment) and those of paragraph
/// properties (alignment, indentation, spacing, borders, tab stops, list
/// reference).
///
/// Not ported from Quds; written for jet_office.
///
/// Every value is immutable and equal by value. Lengths are points at the
/// API and are stored in the file's unit (a border's width in eighths of a
/// point), so a value reads back rounded to it and two values are equal
/// when their stored units are (plan Ruling 4). The `ST_` names of the
/// enums are their Dart names.
library;

import '../../xml/xml_escape.dart';
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
///
/// A theme colour read from a file has no fallback hex in its view: the
/// colour attribute beside the theme attributes (`w:val="4472C4"`) is
/// dropped from the view, but stays in the file until the colour is set.
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

/// The font names of a run (`w:rFonts`): one name for each script slot the
/// model types.
///
/// A value the caller makes names fonts; one read from a file may also
/// carry theme fonts ([asciiTheme], [hAnsiTheme], [eastAsiaTheme], such as
/// `minorHAnsi`), which a caller cannot make. Setting fonts replaces these
/// slots and the theme attributes, and keeps the complex-script font and
/// the other attributes of the file (plan Ruling 3).
final class DocxFonts {
  /// Fonts named for the slots given; a slot left out is not set.
  ///
  /// A name that is empty or holds a character XML forbids throws
  /// [ArgumentError].
  DocxFonts({String? ascii, String? hAnsi, String? eastAsia})
    : ascii = _checkName(ascii, 'ascii'),
      hAnsi = _checkName(hAnsi, 'hAnsi'),
      eastAsia = _checkName(eastAsia, 'eastAsia'),
      asciiTheme = null,
      hAnsiTheme = null,
      eastAsiaTheme = null;

  /// The same font [name] in the ASCII, high ANSI and East Asian slots.
  ///
  /// A name that is empty or holds a character XML forbids throws
  /// [ArgumentError].
  DocxFonts.all(String name) : this(ascii: name, hAnsi: name, eastAsia: name);

  DocxFonts._read({
    this.ascii,
    this.hAnsi,
    this.eastAsia,
    this.asciiTheme,
    this.hAnsiTheme,
    this.eastAsiaTheme,
  });

  /// The font for ASCII characters (`w:ascii`), or `null`.
  final String? ascii;

  /// The font for high ANSI characters (`w:hAnsi`), or `null`.
  final String? hAnsi;

  /// The font for East Asian characters (`w:eastAsia`), or `null`.
  final String? eastAsia;

  /// The theme font of the ASCII slot (`w:asciiTheme`), such as
  /// `minorHAnsi`; `null` in a value the caller made.
  final String? asciiTheme;

  /// The theme font of the high ANSI slot (`w:hAnsiTheme`); `null` in a
  /// value the caller made.
  final String? hAnsiTheme;

  /// The theme font of the East Asian slot (`w:eastAsiaTheme`); `null` in a
  /// value the caller made.
  final String? eastAsiaTheme;

  static String? _checkName(String? name, String parameter) {
    if (name != null && (name.isEmpty || scrubXmlText(name).removed > 0)) {
      throw ArgumentError.value(
        name,
        parameter,
        'must not be empty or hold a character XML forbids',
      );
    }
    return name;
  }

  @override
  bool operator ==(Object other) =>
      other is DocxFonts &&
      other.ascii == ascii &&
      other.hAnsi == hAnsi &&
      other.eastAsia == eastAsia &&
      other.asciiTheme == asciiTheme &&
      other.hAnsiTheme == hAnsiTheme &&
      other.eastAsiaTheme == eastAsiaTheme;

  @override
  int get hashCode => Object.hash(
    ascii,
    hAnsi,
    eastAsia,
    asciiTheme,
    hAnsiTheme,
    eastAsiaTheme,
  );

  @override
  String toString() =>
      'DocxFonts(ascii: $ascii, hAnsi: $hAnsi, eastAsia: $eastAsia)';
}

/// Fonts as the reader builds them: the names are checked by the caller,
/// and themes are allowed.
DocxFonts readFonts({
  String? ascii,
  String? hAnsi,
  String? eastAsia,
  String? asciiTheme,
  String? hAnsiTheme,
  String? eastAsiaTheme,
}) => DocxFonts._read(
  ascii: ascii,
  hAnsi: hAnsi,
  eastAsia: eastAsia,
  asciiTheme: asciiTheme,
  hAnsiTheme: hAnsiTheme,
  eastAsiaTheme: eastAsiaTheme,
);

/// An underline line style (`ST_Underline`). The Dart name of each value is
/// its spelling in the file.
enum DocxUnderlineStyle {
  /// A single line.
  single,

  /// A single line under words only, not under spaces.
  words,

  /// A double line.
  double,

  /// A thick line.
  thick,

  /// A dotted line.
  dotted,

  /// A thick dotted line.
  dottedHeavy,

  /// A dashed line.
  dash,

  /// A thick dashed line.
  dashedHeavy,

  /// A line of long dashes.
  dashLong,

  /// A thick line of long dashes.
  dashLongHeavy,

  /// A dot-dash line.
  dotDash,

  /// A thick dot-dash line.
  dashDotHeavy,

  /// A dot-dot-dash line.
  dotDotDash,

  /// A thick dot-dot-dash line.
  dashDotDotHeavy,

  /// A wavy line.
  wave,

  /// A thick wavy line.
  wavyHeavy,

  /// A double wavy line.
  wavyDouble,

  /// No underline; written explicitly it removes an inherited underline.
  none,
}

/// The underline of a run (`w:u`): its line style and, optionally, a colour
/// of its own.
final class DocxUnderline {
  /// An underline of [style], drawn in [color] when given and in the text
  /// colour otherwise.
  const DocxUnderline(this.style, {this.color});

  /// The line style.
  final DocxUnderlineStyle style;

  /// The underline's colour, or `null` for the text colour.
  final DocxColor? color;

  @override
  bool operator ==(Object other) =>
      other is DocxUnderline && other.style == style && other.color == color;

  @override
  int get hashCode => Object.hash(style, color);

  @override
  String toString() => 'DocxUnderline(${style.name}, color: $color)';
}

/// A highlight colour (`ST_HighlightColor`), one of the 16 colours of
/// Word's highlighter and none. The Dart name of each value is its spelling
/// in the file.
enum DocxHighlight {
  /// Black.
  black,

  /// Blue.
  blue,

  /// Cyan.
  cyan,

  /// Green.
  green,

  /// Magenta.
  magenta,

  /// Red.
  red,

  /// Yellow.
  yellow,

  /// White.
  white,

  /// Dark blue.
  darkBlue,

  /// Dark cyan.
  darkCyan,

  /// Dark green.
  darkGreen,

  /// Dark magenta.
  darkMagenta,

  /// Dark red.
  darkRed,

  /// Dark yellow.
  darkYellow,

  /// Dark gray.
  darkGray,

  /// Light gray.
  lightGray,

  /// No highlight; written explicitly it removes an inherited highlight.
  none,
}

/// Whether a run is raised or lowered (`ST_VerticalAlignRun`). The Dart
/// name of each value is its spelling in the file.
enum DocxVerticalAlign {
  /// On the baseline, at the normal size.
  baseline,

  /// Raised and smaller.
  superscript,

  /// Lowered and smaller.
  subscript,
}

/// The alignment of a paragraph (`w:jc`, without the kashida values). The
/// Dart name of each value is its spelling in the file, except [justify],
/// which is `both`.
///
/// A `w:jc` of `lowKashida`, `mediumKashida`, `highKashida`, `numTab` or
/// `thaiDistribute` reads as `null`: the model does not type it, and the
/// file keeps it as written.
enum DocxAlignment {
  /// Aligned to the left (`left`).
  left,

  /// Centered.
  center,

  /// Aligned to the right (`right`).
  right,

  /// Both edges straight (`both`).
  justify,

  /// Both edges straight, with the space spread between characters too.
  distribute,

  /// Aligned to the start of the line: the left edge, or the right one in
  /// a right-to-left paragraph.
  start,

  /// Aligned to the end of the line: the right edge, or the left one in a
  /// right-to-left paragraph.
  end,
}

/// The indentation of a paragraph (`w:ind`): the distance from the margins,
/// in points.
///
/// Each member is `null` when the file has none, and the style or the
/// document default decides. At most one of [firstLinePt] and [hangingPt]
/// is set. A value is stored in twips and reads back rounded to a
/// twentieth of a point; two values are equal when their twips are (plan
/// Ruling 4). A `w:ind` with `w:start`, `w:end` or a `…Chars` attribute has
/// no view.
final class DocxIndentation {
  /// An indentation of the given distances. [leftPt] and [rightPt] go from
  /// -1584 to 1584 points (negative moves into the margin), [firstLinePt]
  /// and [hangingPt] from 0 to 1584.
  ///
  /// Throws [ArgumentError] when [firstLinePt] and [hangingPt] are both
  /// given or a value is not finite, and [RangeError] for a value out of
  /// range once rounded.
  factory DocxIndentation({
    double? leftPt,
    double? rightPt,
    double? firstLinePt,
    double? hangingPt,
  }) {
    if (firstLinePt != null && hangingPt != null) {
      throw ArgumentError(
        'firstLinePt and hangingPt cannot both be set: an indentation is '
        'either a first line or a hanging one',
      );
    }
    int? twips(double? v, String name, int min) =>
        v == null ? null : twipsOf(v, name, min: min, max: maxTwips);
    return DocxIndentation._(
      twips(leftPt, 'leftPt', -maxTwips),
      twips(rightPt, 'rightPt', -maxTwips),
      twips(firstLinePt, 'firstLinePt', 0),
      twips(hangingPt, 'hangingPt', 0),
    );
  }

  const DocxIndentation._(
    this._left,
    this._right,
    this._firstLine,
    this._hanging,
  );

  final int? _left;
  final int? _right;
  final int? _firstLine;
  final int? _hanging;

  /// The distance from the left margin (the start side), or `null`.
  double? get leftPt => _left == null ? null : ptOfTwips(_left);

  /// The distance from the right margin (the end side), or `null`.
  double? get rightPt => _right == null ? null : ptOfTwips(_right);

  /// How far the first line goes in beyond [leftPt], or `null`.
  double? get firstLinePt => _firstLine == null ? null : ptOfTwips(_firstLine);

  /// How far the first line goes out before [leftPt], or `null`.
  double? get hangingPt => _hanging == null ? null : ptOfTwips(_hanging);

  @override
  bool operator ==(Object other) =>
      other is DocxIndentation &&
      other._left == _left &&
      other._right == _right &&
      other._firstLine == _firstLine &&
      other._hanging == _hanging;

  @override
  int get hashCode => Object.hash(_left, _right, _firstLine, _hanging);

  @override
  String toString() =>
      'DocxIndentation(left: $leftPt, right: $rightPt, '
      'firstLine: $firstLinePt, hanging: $hangingPt)';
}

/// How a line's height is read (`w:lineRule`).
enum DocxLineRule {
  /// A multiple of the font's line height; [DocxLineSpacing.value] is in
  /// lines.
  auto,

  /// Exactly that height; [DocxLineSpacing.value] is in points.
  exact,

  /// At least that height; [DocxLineSpacing.value] is in points.
  atLeast,
}

/// The line spacing of a paragraph (`w:spacing/@w:line` with
/// `w:lineRule`): a multiple of the line height, or a height in points.
///
/// A multiple is stored in 240ths of a line and a height in twips, so a
/// value reads back rounded to them and two values are equal when their
/// stored numbers are (plan Ruling 4).
final class DocxLineSpacing {
  /// A multiple of the line height: 1 is single spacing, 1.5 one and a
  /// half. From 1/240 to 132 lines; throws [ArgumentError] for a value that
  /// is not finite and [RangeError] outside that range once rounded.
  factory DocxLineSpacing.multiple(double lines) => DocxLineSpacing._(
    DocxLineRule.auto,
    lineUnitsOf(lines, 'lines', min: 1, max: maxTwips),
  );

  /// A line of exactly [pt] points, from 0 to 1584; throws as
  /// [DocxLineSpacing.multiple] does.
  factory DocxLineSpacing.exactly(double pt) => DocxLineSpacing._(
    DocxLineRule.exact,
    twipsOf(pt, 'pt', min: 0, max: maxTwips),
  );

  /// A line of at least [pt] points, from 0 to 1584; throws as
  /// [DocxLineSpacing.multiple] does.
  factory DocxLineSpacing.atLeast(double pt) => DocxLineSpacing._(
    DocxLineRule.atLeast,
    twipsOf(pt, 'pt', min: 0, max: maxTwips),
  );

  const DocxLineSpacing._(this.rule, this._stored);

  /// How [value] is read.
  final DocxLineRule rule;

  final int _stored;

  /// The spacing: lines for [DocxLineRule.auto], points otherwise.
  double get value => rule == DocxLineRule.auto
      ? linesOfLineUnits(_stored)
      : ptOfTwips(_stored);

  @override
  bool operator ==(Object other) =>
      other is DocxLineSpacing &&
      other.rule == rule &&
      other._stored == _stored;

  @override
  int get hashCode => Object.hash(rule, _stored);

  @override
  String toString() => 'DocxLineSpacing(${rule.name}, $value)';
}

/// The spacing of a paragraph (`w:spacing`): the space before and after it,
/// and the line spacing inside it.
///
/// Each member is `null` (or false) when the file has none. The space is in
/// points, stored in twips, from 0 to 1584. [beforeAuto] and [afterAuto]
/// let the application choose the space (Word uses it for HTML paragraphs).
/// A `w:spacing` with a `…Lines` attribute, a `w:lineRule` without
/// `w:line`, or a `w:line` of 0 under the `auto` rule (or no rule) has no
/// view.
final class DocxSpacing {
  /// A spacing of the given parts. Throws [ArgumentError] for a value that
  /// is not finite and [RangeError] for one outside 0 to 1584 points once
  /// rounded.
  factory DocxSpacing({
    double? beforePt,
    double? afterPt,
    bool beforeAuto = false,
    bool afterAuto = false,
    DocxLineSpacing? line,
  }) => DocxSpacing._(
    beforePt == null
        ? null
        : twipsOf(beforePt, 'beforePt', min: 0, max: maxTwips),
    afterPt == null ? null : twipsOf(afterPt, 'afterPt', min: 0, max: maxTwips),
    beforeAuto,
    afterAuto,
    line,
  );

  const DocxSpacing._(
    this._before,
    this._after,
    this.beforeAuto,
    this.afterAuto,
    this.line,
  );

  final int? _before;
  final int? _after;

  /// Whether the application chooses the space before.
  final bool beforeAuto;

  /// Whether the application chooses the space after.
  final bool afterAuto;

  /// The line spacing, or `null`.
  final DocxLineSpacing? line;

  /// The space before the paragraph, or `null`.
  double? get beforePt => _before == null ? null : ptOfTwips(_before);

  /// The space after the paragraph, or `null`.
  double? get afterPt => _after == null ? null : ptOfTwips(_after);

  @override
  bool operator ==(Object other) =>
      other is DocxSpacing &&
      other._before == _before &&
      other._after == _after &&
      other.beforeAuto == beforeAuto &&
      other.afterAuto == afterAuto &&
      other.line == line;

  @override
  int get hashCode => Object.hash(_before, _after, beforeAuto, afterAuto, line);

  @override
  String toString() =>
      'DocxSpacing(before: $beforePt, after: $afterPt, '
      'beforeAuto: $beforeAuto, afterAuto: $afterAuto, line: $line)';
}

/// The borders of a paragraph (`w:pBdr`): each side, and the line between
/// paragraphs with the same borders and the bar beside them.
///
/// A side that is `null` has none in the file. A `w:pBdr` with a border
/// the model cannot type (an art border), a side twice or any other child
/// has no view.
final class DocxParagraphBorders {
  /// The borders of the given sides.
  const DocxParagraphBorders({
    this.top,
    this.left,
    this.bottom,
    this.right,
    this.between,
    this.bar,
  });

  /// The border above the paragraph.
  final DocxBorder? top;

  /// The border at the left.
  final DocxBorder? left;

  /// The border below the paragraph.
  final DocxBorder? bottom;

  /// The border at the right.
  final DocxBorder? right;

  /// The border between this paragraph and the next with the same borders.
  final DocxBorder? between;

  /// The bar border beside the paragraph.
  final DocxBorder? bar;

  @override
  bool operator ==(Object other) =>
      other is DocxParagraphBorders &&
      other.top == top &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.between == between &&
      other.bar == bar;

  @override
  int get hashCode => Object.hash(top, left, bottom, right, between, bar);

  @override
  String toString() =>
      'DocxParagraphBorders(top: $top, left: $left, bottom: $bottom, '
      'right: $right, between: $between, bar: $bar)';
}

/// How text lines up at a tab stop (`ST_TabJc`). The Dart name of each
/// value is its spelling in the file.
enum DocxTabAlignment {
  /// The text starts at the stop.
  left,

  /// The text is centered on the stop.
  center,

  /// The text ends at the stop.
  right,

  /// The decimal separator is at the stop.
  decimal,

  /// A vertical bar is drawn at the stop.
  bar,

  /// Removes a stop of the style at that position.
  clear,

  /// Like [left] in a left-to-right paragraph.
  start,

  /// Like [right] in a left-to-right paragraph.
  end,

  /// A list tab (`num`), for old files.
  num,
}

/// The leader drawn up to a tab stop (`ST_TabTlc`). The Dart name of each
/// value is its spelling in the file.
enum DocxTabLeader {
  /// No leader.
  none,

  /// A row of dots.
  dot,

  /// A row of hyphens.
  hyphen,

  /// A line.
  underscore,

  /// A thick line.
  heavy,

  /// A row of middle dots.
  middleDot,
}

/// A tab stop of a paragraph (`w:tab` in `w:tabs`).
///
/// The position is in points from the left margin, from -1584 to 1584,
/// stored in twips, so it reads back rounded to a twentieth of a point.
final class DocxTabStop {
  /// A tab stop at [positionPt]. Throws [ArgumentError] for a position that
  /// is not finite and [RangeError] for one out of range once rounded.
  DocxTabStop(
    double positionPt, {
    this.alignment = DocxTabAlignment.left,
    this.leader = DocxTabLeader.none,
  }) : _position = twipsOf(
         positionPt,
         'positionPt',
         min: -maxTwips,
         max: maxTwips,
       );

  final int _position;

  /// How text lines up at the stop.
  final DocxTabAlignment alignment;

  /// The leader up to the stop.
  final DocxTabLeader leader;

  /// The position in points from the left margin.
  double get positionPt => ptOfTwips(_position);

  @override
  bool operator ==(Object other) =>
      other is DocxTabStop &&
      other._position == _position &&
      other.alignment == alignment &&
      other.leader == leader;

  @override
  int get hashCode => Object.hash(_position, alignment, leader);

  @override
  String toString() =>
      'DocxTabStop($positionPt, ${alignment.name}, ${leader.name})';
}

/// The list a paragraph belongs to (`w:numPr`): the number of a list
/// instance (`w:numId`) and the level in it.
final class DocxNumberingRef {
  /// A reference to the list instance [numId] at [level].
  ///
  /// [numId] is from 0 to 999999999 (0 means "no list" and removes the
  /// paragraph from the list its style gives) and [level] from 0 to 8;
  /// anything else throws [RangeError].
  DocxNumberingRef(this.numId, {this.level = 0}) {
    RangeError.checkValueInInterval(numId, 0, maxNumId, 'numId');
    RangeError.checkValueInInterval(level, 0, 8, 'level');
  }

  /// The number of the list instance in the numbering part.
  final int numId;

  /// The level in the list, from 0.
  final int level;

  @override
  bool operator ==(Object other) =>
      other is DocxNumberingRef && other.numId == numId && other.level == level;

  @override
  int get hashCode => Object.hash(numId, level);

  @override
  String toString() => 'DocxNumberingRef($numId, level: $level)';
}
