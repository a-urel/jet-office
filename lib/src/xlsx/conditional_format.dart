/// [XlsxConditionalFormat] and its rules, their checks and the
/// `conditionalFormatting` XML.
///
/// Ported from quds_office_engine `lib/src/sheet/serial/sheet_serial.dart` at commit 15c5d29.
/// Ported: the `conditionalFormatting` writing. What changed: Quds wrote
/// one `cellIs` rule per element and nothing else, without the required
/// `priority` and without a `dxfId`, so a rule had no formatting; it wrote
/// "contains" and "duplicate" as `cellIs` with the operators `containsText`
/// and `duplicateValues`, which `cellIs` does not have; and its worksheet
/// wrote conditional formats before `mergeCells`, against the
/// `CT_Worksheet` order. Here a format is a value type holding one or more
/// rules of nine kinds, from cell-value comparisons to icon sets; the writer
/// checks it when it is registered, registers the rules' styles as
/// differential styles (`differential_style.dart`) and numbers the rules
/// with the sheet's next priorities; the trailer writes `cfRule`
/// attributes in `CT_CfRule` order. The Excel 2010 rules of data bars and
/// of the icon sets only Excel 2010 has are written by
/// `conditional_format_x14.dart`.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'color.dart';
import 'comparison.dart';
import 'conditional_format_x14.dart';
import 'differential_style.dart';
import 'formula_text.dart';
import 'limits.dart';
import 'range.dart';
import 'style.dart';

/// Rules that format the cells of [ranges] when their conditions hold.
///
/// Register it with the sheet writer's `conditionalFormat`, which checks it
/// and throws [ArgumentError] naming the field, such as `rules[2].rank`.
/// The rules are evaluated in order: each gets the sheet's next priority,
/// so an earlier rule wins over a later one, and a rule with
/// [XlsxConditionalRule.stopIfTrue] stops the rules after it. The ranges
/// of different formats may overlap.
final class XlsxConditionalFormat {
  /// A format of [rules] on [ranges].
  ///
  /// Both lists are copied into unmodifiable lists, so the constructor is
  /// not `const`. Nothing is checked here.
  XlsxConditionalFormat(List<XlsxRange> ranges, List<XlsxConditionalRule> rules)
    : ranges = List<XlsxRange>.unmodifiable(ranges),
      rules = List<XlsxConditionalRule>.unmodifiable(rules);

  /// The cells the rules apply to, an unmodifiable copy; at least one.
  final List<XlsxRange> ranges;

  /// The rules, in priority order, an unmodifiable copy; at least one.
  final List<XlsxConditionalRule> rules;

  @override
  bool operator ==(Object other) =>
      other is XlsxConditionalFormat &&
      _listEquals(other.ranges, ranges) &&
      _listEquals(other.rules, rules);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(ranges), Object.hashAll(rules));

  @override
  String toString() => 'XlsxConditionalFormat($ranges, $rules)';
}

/// One rule of an [XlsxConditionalFormat] (`CT_CfRule`).
///
/// The subclasses are the kinds of rule. Those that format a cell take an
/// optional style, written as a differential style: only what the style
/// sets is applied over the cell's own formatting (see
/// `validateDifferentialStyle` for what such a style may not set). A rule
/// without a style changes nothing when it holds, but still counts for
/// [stopIfTrue]. [XlsxColorScale], [XlsxDataBar] and [XlsxIconSet] draw
/// their own formatting and take no style.
sealed class XlsxConditionalRule {
  const XlsxConditionalRule({this.stopIfTrue = false});

  /// Whether the rules after this one are skipped for a cell where this one
  /// holds. XML `stopIfTrue`.
  final bool stopIfTrue;
}

/// Formats a cell whose value compares with [formula1] (and [formula2]) as
/// [comparison] says. XML type `cellIs`.
///
/// The operands are formula text: `10`, `"text"`, `$B$1`, `AVERAGE(A:A)`;
/// a leading `=` is dropped. [formula2] is required for
/// [XlsxComparison.between] and [XlsxComparison.notBetween] and refused for
/// the other comparisons, when the format is registered.
final class XlsxCellValueRule extends XlsxConditionalRule {
  /// A rule that compares the cell with [formula1] (and [formula2]).
  const XlsxCellValueRule(
    this.comparison,
    this.formula1, {
    this.formula2,
    this.style,
    super.stopIfTrue,
  });

  /// How the cell is compared. XML `operator`.
  final XlsxComparison comparison;

  /// The first operand, formula text.
  final String formula1;

  /// The second operand of a range comparison, formula text, or `null`.
  final String? formula2;

  /// The formatting applied when the rule holds, or `null` for none.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxCellValueRule &&
      other.comparison == comparison &&
      other.formula1 == formula1 &&
      other.formula2 == formula2 &&
      other.style == style &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode =>
      Object.hash(comparison, formula1, formula2, style, stopIfTrue);

  @override
  String toString() =>
      'XlsxCellValueRule(${comparison.name}, $formula1'
      '${formula2 == null ? '' : ', $formula2'})';
}

/// Formats a cell for which [formula] is true. XML type `expression`.
///
/// The formula is written for the top-left cell of the format's first
/// range and is relative to it, as in Excel's dialog: on `B2:B9`,
/// `B2>AVERAGE($B$2:$B$9)` tests each cell of the column. A leading `=` is
/// dropped.
final class XlsxExpressionRule extends XlsxConditionalRule {
  /// A rule that holds where [formula] is true.
  const XlsxExpressionRule(this.formula, {this.style, super.stopIfTrue});

  /// The condition, formula text.
  final String formula;

  /// The formatting applied when the rule holds, or `null` for none.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxExpressionRule &&
      other.formula == formula &&
      other.style == style &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode => Object.hash(formula, style, stopIfTrue);

  @override
  String toString() => 'XlsxExpressionRule($formula)';
}

/// Formats the [rank] highest values of the ranges, or the lowest with
/// [bottom]; with [percent], the top or bottom [rank] percent. XML type
/// `top10`.
///
/// [rank] is 1 to [XlsxLimits.maxTopBottomRank], or 1 to 100 with
/// [percent]; checked when the format is registered.
final class XlsxTopBottomRule extends XlsxConditionalRule {
  /// A rule on the top (or [bottom]) [rank] values (or percent).
  const XlsxTopBottomRule({
    this.rank = 10,
    this.percent = false,
    this.bottom = false,
    this.style,
    super.stopIfTrue,
  });

  /// How many values, or what percentage of them, are formatted.
  final int rank;

  /// Whether [rank] is a percentage of the values.
  final bool percent;

  /// Whether the lowest values are formatted instead of the highest.
  final bool bottom;

  /// The formatting applied when the rule holds, or `null` for none.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxTopBottomRule &&
      other.rank == rank &&
      other.percent == percent &&
      other.bottom == bottom &&
      other.style == style &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode => Object.hash(rank, percent, bottom, style, stopIfTrue);

  @override
  String toString() =>
      'XlsxTopBottomRule(${bottom ? 'bottom' : 'top'} $rank'
      '${percent ? '%' : ''})';
}

/// Formats the values [above] the average of the ranges, or below it; with
/// [orEqual], the average itself too. XML type `aboveAverage`.
///
/// With [standardDeviations], 1 to 3, only values that many standard
/// deviations above (or below) the average are formatted; checked when the
/// format is registered.
final class XlsxAverageRule extends XlsxConditionalRule {
  /// A rule on the values above (or below) the average.
  const XlsxAverageRule({
    this.above = true,
    this.orEqual = false,
    this.standardDeviations,
    this.style,
    super.stopIfTrue,
  });

  /// Whether values above the average are formatted, rather than below.
  /// XML `aboveAverage`.
  final bool above;

  /// Whether a value equal to the average is formatted too. XML
  /// `equalAverage`.
  final bool orEqual;

  /// How many standard deviations from the average a value must be, 1 to
  /// 3, or `null` for any distance. XML `stdDev`.
  final int? standardDeviations;

  /// The formatting applied when the rule holds, or `null` for none.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxAverageRule &&
      other.above == above &&
      other.orEqual == orEqual &&
      other.standardDeviations == standardDeviations &&
      other.style == style &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode =>
      Object.hash(above, orEqual, standardDeviations, style, stopIfTrue);

  @override
  String toString() =>
      'XlsxAverageRule(${above ? 'above' : 'below'}'
      '${orEqual ? ' or equal' : ''}'
      '${standardDeviations == null ? '' : ', $standardDeviations sd'})';
}

/// Formats the values that occur more than once in the ranges, or with
/// [unique] those that occur once. XML type `duplicateValues` or
/// `uniqueValues`.
final class XlsxDuplicateRule extends XlsxConditionalRule {
  /// A rule on duplicate (or [unique]) values.
  const XlsxDuplicateRule({this.unique = false, this.style, super.stopIfTrue});

  /// Whether values that occur once are formatted, rather than duplicates.
  final bool unique;

  /// The formatting applied when the rule holds, or `null` for none.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxDuplicateRule &&
      other.unique == unique &&
      other.style == style &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode => Object.hash(unique, style, stopIfTrue);

  @override
  String toString() => 'XlsxDuplicateRule(${unique ? 'unique' : 'duplicate'})';
}

/// How an [XlsxTextRule] matches a cell's text. Matching ignores case.
enum XlsxTextOperator {
  /// The text occurs anywhere in the cell. XML type `containsText`.
  contains,

  /// The text occurs nowhere in the cell. XML type `notContainsText`.
  notContains,

  /// The cell starts with the text. XML type `beginsWith`.
  beginsWith,

  /// The cell ends with the text. XML type `endsWith`.
  endsWith,
}

/// Formats a cell whose text matches [text] as [operator] says.
///
/// The file stores the formula Excel evaluates as well as [text]; the
/// writer derives it, relative to the top-left cell of the format's first
/// range, with a `"` in [text] doubled: `NOT(ISERROR(SEARCH("a""b",C2)))`
/// for [XlsxTextOperator.contains] of `a"b` on `C2:C9`.
final class XlsxTextRule extends XlsxConditionalRule {
  /// A rule that matches [text] as [operator] says.
  const XlsxTextRule(this.operator, this.text, {this.style, super.stopIfTrue});

  /// How the text is matched.
  final XlsxTextOperator operator;

  /// The text to look for.
  final String text;

  /// The formatting applied when the rule holds, or `null` for none.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxTextRule &&
      other.operator == operator &&
      other.text == text &&
      other.style == style &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode => Object.hash(operator, text, style, stopIfTrue);

  @override
  String toString() => 'XlsxTextRule(${operator.name}, $text)';
}

/// Shades each cell by where its value lies between [points], blending
/// their [colors]. XML type `colorScale`.
///
/// Two or three points, each with the color at index `i` of [colors]; the
/// counts must agree. Checked when the format is registered.
final class XlsxColorScale extends XlsxConditionalRule {
  /// A scale of [points] with their [colors].
  ///
  /// Both lists are copied into unmodifiable lists, so the constructor is
  /// not `const`.
  XlsxColorScale(
    List<XlsxCfValue> points,
    List<XlsxColor> colors, {
    super.stopIfTrue,
  }) : points = List<XlsxCfValue>.unmodifiable(points),
       colors = List<XlsxColor>.unmodifiable(colors);

  /// The values the colors sit at, lowest first, an unmodifiable copy.
  final List<XlsxCfValue> points;

  /// The color of each point, an unmodifiable copy.
  final List<XlsxColor> colors;

  @override
  bool operator ==(Object other) =>
      other is XlsxColorScale &&
      _listEquals(other.points, points) &&
      _listEquals(other.colors, colors) &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(points), Object.hashAll(colors), stopIfTrue);

  @override
  String toString() => 'XlsxColorScale($points, $colors)';
}

/// Draws a bar of [color] in each cell, as long as its value lies between
/// [min] and [max]. XML type `dataBar`.
///
/// The shortest bar takes [minLength] percent of the cell's width, the
/// longest [maxLength]; both 0 to 100, with [minLength] not above
/// [maxLength], checked when the format is registered. [showValue] false
/// hides the cell's value behind the bar.
///
/// Excel 2010 and later draw a bar from its Excel 2010 rule, which the
/// writer adds to every data bar (`conditional_format_x14.dart`); Excel
/// 2007 draws the plain rule. Only the Excel 2010 rule has [gradient],
/// [border], the negative colors and the [axis]; it draws from 0 to 100
/// percent when [minLength] and [maxLength] are the defaults 10 and 90,
/// and a [min] or [max] of `min` or `max` is Excel's automatic bound.
final class XlsxDataBar extends XlsxConditionalRule {
  /// A data bar of [color] from [min] to [max], with every field given.
  const XlsxDataBar({
    this.min = const XlsxCfValue.min(),
    this.max = const XlsxCfValue.max(),
    required this.color,
    this.showValue = true,
    this.minLength = 10,
    this.maxLength = 90,
    this.gradient = true,
    this.border = false,
    this.borderColor,
    this.negativeFillColor,
    this.negativeBorderColor,
    this.axis = XlsxDataBarAxis.automatic,
    this.axisColor,
    super.stopIfTrue,
  });

  /// The value of the shortest bar.
  final XlsxCfValue min;

  /// The value of the longest bar.
  final XlsxCfValue max;

  /// The bar's color.
  final XlsxColor color;

  /// Whether the cell's value is shown beside the bar.
  final bool showValue;

  /// The length of the shortest bar, in percent of the cell's width.
  final int minLength;

  /// The length of the longest bar, in percent of the cell's width.
  final int maxLength;

  /// Whether the bar fades out to the right, rather than being solid.
  final bool gradient;

  /// Whether the bar has a border.
  final bool border;

  /// The border's color, or `null` for [color]; used only with [border].
  final XlsxColor? borderColor;

  /// The color of a bar for a negative value, or `null` for Excel's.
  final XlsxColor? negativeFillColor;

  /// The border color of a bar for a negative value, or `null` for the
  /// border's own; used only with [border].
  final XlsxColor? negativeBorderColor;

  /// Where the axis between negative and positive bars lies.
  final XlsxDataBarAxis axis;

  /// The axis's color, or `null` for Excel's.
  final XlsxColor? axisColor;

  @override
  bool operator ==(Object other) =>
      other is XlsxDataBar &&
      other.min == min &&
      other.max == max &&
      other.color == color &&
      other.showValue == showValue &&
      other.minLength == minLength &&
      other.maxLength == maxLength &&
      other.gradient == gradient &&
      other.border == border &&
      other.borderColor == borderColor &&
      other.negativeFillColor == negativeFillColor &&
      other.negativeBorderColor == negativeBorderColor &&
      other.axis == axis &&
      other.axisColor == axisColor &&
      other.stopIfTrue == stopIfTrue;

  @override
  int get hashCode => Object.hash(
    min,
    max,
    color,
    showValue,
    minLength,
    maxLength,
    gradient,
    border,
    borderColor,
    negativeFillColor,
    negativeBorderColor,
    axis,
    axisColor,
    stopIfTrue,
  );

  @override
  String toString() =>
      'XlsxDataBar($min, $max, $color, gradient: $gradient, '
      'border: $border, borderColor: $borderColor, '
      'negativeFillColor: $negativeFillColor, '
      'negativeBorderColor: $negativeBorderColor, axis: ${axis.name}, '
      'axisColor: $axisColor)';
}

/// Where the axis of an [XlsxDataBar] lies (`ST_DataBarAxisPosition` of
/// Excel 2010). XML `axisPosition`, the name of the value.
enum XlsxDataBarAxis {
  /// Where zero falls between the lowest and the highest value; with no
  /// negative value, at the left edge.
  automatic,

  /// In the middle of the cell, negative bars to the left of it.
  middle,

  /// No axis: negative bars are drawn to the right, like positive ones.
  none,
}

/// The icon sets of Excel (`ST_IconSetType`), with their XML name and
/// number of icons.
///
/// [threeStars], [threeTriangles] and [fiveBoxes] came with Excel 2010
/// ([isX14Only]): they have no Excel 2007 rule, and Excel 2007 shows no
/// icons for them.
enum XlsxIconSetType {
  /// Up, sideways and down arrows in color.
  threeArrows('3Arrows', 3),

  /// Up, sideways and down arrows in gray.
  threeArrowsGray('3ArrowsGray', 3),

  /// Three flags.
  threeFlags('3Flags', 3),

  /// Three unrimmed traffic lights.
  threeTrafficLights1('3TrafficLights1', 3),

  /// Three rimmed traffic lights.
  threeTrafficLights2('3TrafficLights2', 3),

  /// Three signs.
  threeSigns('3Signs', 3),

  /// Three circled symbols.
  threeSymbols('3Symbols', 3),

  /// Three uncircled symbols.
  threeSymbols2('3Symbols2', 3),

  /// Four arrows in color.
  fourArrows('4Arrows', 4),

  /// Four arrows in gray.
  fourArrowsGray('4ArrowsGray', 4),

  /// Four circles from red to black.
  fourRedToBlack('4RedToBlack', 4),

  /// Four rating bars.
  fourRating('4Rating', 4),

  /// Four traffic lights.
  fourTrafficLights('4TrafficLights', 4),

  /// Five arrows in color.
  fiveArrows('5Arrows', 5),

  /// Five arrows in gray.
  fiveArrowsGray('5ArrowsGray', 5),

  /// Five rating bars.
  fiveRating('5Rating', 5),

  /// Five quarters of a circle.
  fiveQuarters('5Quarters', 5),

  /// Three stars: empty, half and full. Excel 2010.
  threeStars('3Stars', 3, isX14Only: true),

  /// Three triangles: down, a dash and up. Excel 2010.
  threeTriangles('3Triangles', 3, isX14Only: true),

  /// Five boxes, from empty to full. Excel 2010.
  fiveBoxes('5Boxes', 5, isX14Only: true);

  const XlsxIconSetType(this.xmlName, this.iconCount, {this.isX14Only = false});

  /// The name the file uses, such as `3Arrows`.
  final String xmlName;

  /// How many icons the set has, and so how many thresholds it takes.
  final int iconCount;

  /// Whether the set came with Excel 2010, so that only an Excel 2010 rule
  /// can show it.
  final bool isX14Only;
}

/// Shows one icon of [type] in each cell, chosen by the [thresholds] its
/// value reaches. XML type `iconSet`.
///
/// Threshold `i` is where icon `i` starts, lowest first; the first is
/// usually 0 percent. `null` takes Excel's default: equal percent steps,
/// 0, 33 and 67 for three icons, 0, 25, 50 and 75 for four, 0, 20, 40, 60
/// and 80 for five. Given thresholds must number [XlsxIconSetType.iconCount],
/// checked when the format is registered. [reverse] reverses the order of
/// the icons; [showValue] false shows the icon only.
final class XlsxIconSet extends XlsxConditionalRule {
  /// An icon set of [type].
  ///
  /// [thresholds] is copied into an unmodifiable list, so the constructor
  /// is not `const`.
  XlsxIconSet(
    this.type, {
    List<XlsxCfValue>? thresholds,
    this.reverse = false,
    this.showValue = true,
    super.stopIfTrue,
  }) : thresholds = thresholds == null
           ? null
           : List<XlsxCfValue>.unmodifiable(thresholds);

  /// The icons.
  final XlsxIconSetType type;

  /// Where each icon starts, an unmodifiable copy, or `null` for Excel's
  /// default.
  final List<XlsxCfValue>? thresholds;

  /// Whether the icons are shown in reverse order.
  final bool reverse;

  /// Whether the cell's value is shown beside the icon.
  final bool showValue;

  @override
  bool operator ==(Object other) {
    if (other is! XlsxIconSet ||
        other.type != type ||
        other.reverse != reverse ||
        other.showValue != showValue ||
        other.stopIfTrue != stopIfTrue) {
      return false;
    }
    final List<XlsxCfValue>? a = thresholds;
    final List<XlsxCfValue>? b = other.thresholds;
    return a == null ? b == null : b != null && _listEquals(a, b);
  }

  @override
  int get hashCode => Object.hash(
    type,
    thresholds == null ? null : Object.hashAll(thresholds!),
    reverse,
    showValue,
    stopIfTrue,
  );

  @override
  String toString() =>
      'XlsxIconSet(${type.xmlName}'
      '${thresholds == null ? '' : ', $thresholds'})';
}

/// What an [XlsxCfValue] measures (`ST_CfvoType`).
enum XlsxCfValueType {
  /// The lowest value of the ranges.
  min('min'),

  /// The highest value of the ranges.
  max('max'),

  /// A number. XML `num`.
  number('num'),

  /// A percentage of the way from the lowest value to the highest.
  percent('percent'),

  /// A percentile of the values.
  percentile('percentile'),

  /// The result of a formula.
  formula('formula');

  const XlsxCfValueType(this.xmlName);

  /// The name the file uses.
  final String xmlName;

  /// Whether a value of this type needs [XlsxCfValue.value].
  bool get needsValue => this != min && this != max;
}

/// A point on the scale of a color scale, data bar or icon set
/// (`CT_Cfvo`).
///
/// [value] is formula text: a number, or a reference or formula that
/// gives one, as Excel accepts `=$A$1` for a number or a percent. A
/// percent or percentile written as a number is 0 to 100, and a number
/// must be finite; checked when the format is registered.
final class XlsxCfValue {
  /// A point of [type] at [value], with every field given.
  ///
  /// [value] is required for every type but [XlsxCfValueType.min] and
  /// [XlsxCfValueType.max], which Excel writes with or without one; checked
  /// when the format is registered.
  const XlsxCfValue(this.type, {this.value, this.greaterOrEqual = true});

  /// The lowest value of the ranges.
  const XlsxCfValue.min({this.greaterOrEqual = true})
    : type = XlsxCfValueType.min,
      value = null;

  /// The highest value of the ranges.
  const XlsxCfValue.max({this.greaterOrEqual = true})
    : type = XlsxCfValueType.max,
      value = null;

  /// The number [value].
  factory XlsxCfValue.number(num value, {bool greaterOrEqual = true}) =>
      XlsxCfValue(
        XlsxCfValueType.number,
        value: describeDouble(value.toDouble()),
        greaterOrEqual: greaterOrEqual,
      );

  /// [value] percent of the way from the lowest value to the highest.
  factory XlsxCfValue.percent(num value, {bool greaterOrEqual = true}) =>
      XlsxCfValue(
        XlsxCfValueType.percent,
        value: describeDouble(value.toDouble()),
        greaterOrEqual: greaterOrEqual,
      );

  /// The [value]th percentile of the values.
  factory XlsxCfValue.percentile(num value, {bool greaterOrEqual = true}) =>
      XlsxCfValue(
        XlsxCfValueType.percentile,
        value: describeDouble(value.toDouble()),
        greaterOrEqual: greaterOrEqual,
      );

  /// The result of [formula], formula text; a leading `=` is dropped.
  const XlsxCfValue.formula(String formula, {this.greaterOrEqual = true})
    : type = XlsxCfValueType.formula,
      value = formula;

  /// What the point measures.
  final XlsxCfValueType type;

  /// The number, percentage or formula, as formula text, or `null`.
  final String? value;

  /// Whether a value equal to this point reaches it, rather than only a
  /// greater one; it matters for icon set thresholds. XML `gte`.
  final bool greaterOrEqual;

  @override
  bool operator ==(Object other) =>
      other is XlsxCfValue &&
      other.type == type &&
      other.value == value &&
      other.greaterOrEqual == greaterOrEqual;

  @override
  int get hashCode => Object.hash(type, value, greaterOrEqual);

  @override
  String toString() =>
      'XlsxCfValue(${type.name}${value == null ? '' : ' $value'}'
      '${greaterOrEqual ? '' : ', >'})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The style of [rule], or `null` when it has none or its kind takes none.
XlsxStyle? conditionalRuleStyle(XlsxConditionalRule rule) => switch (rule) {
  XlsxCellValueRule(:final XlsxStyle? style) => style,
  XlsxExpressionRule(:final XlsxStyle? style) => style,
  XlsxTopBottomRule(:final XlsxStyle? style) => style,
  XlsxAverageRule(:final XlsxStyle? style) => style,
  XlsxDuplicateRule(:final XlsxStyle? style) => style,
  XlsxTextRule(:final XlsxStyle? style) => style,
  XlsxColorScale() || XlsxDataBar() || XlsxIconSet() => null,
};

/// A registered format as the trailer writes it: the rules' `dxfId`s
/// (`null` for a rule without a style) and the priority of its first rule;
/// rule `i` has priority `firstPriority + i`. Priorities run from 1 over
/// every rule of the sheet, Excel 2010 ones included, so rule `i` is rule
/// `firstPriority + i - 1` of the sheet (0-based), which its Excel 2010 id
/// encodes (`x14RuleId`).
typedef WorksheetConditionalFormat = ({
  XlsxConditionalFormat format,
  List<int?> dxfIds,
  int firstPriority,
});

/// The most standard deviations an [XlsxAverageRule] may ask for; Excel's
/// dialog offers 1 to 3.
const int _maxStandardDeviations = 3;

/// Checks [format] and throws [ArgumentError] naming the field when it is
/// not valid.
///
/// Checked: at least one range, each inside the sheet; at least one rule;
/// each rule's formulas (see `checkFormulaText`) and fields as its class
/// describes; and each style as a differential style
/// (`validateDifferentialStyle`), whose errors are named
/// `rules[i].style.<field>`. The number formats of the styles are checked
/// when they are registered. Nothing is recorded here.
void checkConditionalFormat(XlsxConditionalFormat format) {
  final List<XlsxRange> ranges = format.ranges;
  if (ranges.isEmpty) {
    throw ArgumentError.value(
      ranges,
      'ranges',
      'A conditional format needs at least one range.',
    );
  }
  for (int i = 0; i < ranges.length; i++) {
    validateRange(ranges[i], 'ranges[$i]');
  }
  final List<XlsxConditionalRule> rules = format.rules;
  if (rules.isEmpty) {
    throw ArgumentError.value(
      rules,
      'rules',
      'A conditional format needs at least one rule.',
    );
  }
  for (int i = 0; i < rules.length; i++) {
    _checkRule(rules[i], 'rules[$i]', ranges.first);
    final XlsxStyle? style = conditionalRuleStyle(rules[i]);
    if (style == null) continue;
    try {
      validateDifferentialStyle(style);
    } on ArgumentError catch (e, stack) {
      Error.throwWithStackTrace(
        ArgumentError.value(
          e.invalidValue,
          'rules[$i].style.${e.name}',
          e.message,
        ),
        stack,
      );
    }
  }
}

void _checkRule(XlsxConditionalRule rule, String field, XlsxRange first) {
  switch (rule) {
    case XlsxCellValueRule():
      checkFormulaText(rule.formula1, '$field.formula1');
      final String? second = rule.formula2;
      if (rule.comparison.takesTwoOperands) {
        if (second == null) {
          throw ArgumentError.value(
            second,
            '$field.formula2',
            'The comparison ${rule.comparison.name} needs a second value.',
          );
        }
      } else if (second != null) {
        throw ArgumentError.value(
          second,
          '$field.formula2',
          'Only between and notBetween take a second value, not '
              '${rule.comparison.name}.',
        );
      }
      if (second != null) checkFormulaText(second, '$field.formula2');
    case XlsxExpressionRule():
      checkFormulaText(rule.formula, '$field.formula');
    case XlsxTopBottomRule():
      final int max = rule.percent ? 100 : XlsxLimits.maxTopBottomRank;
      if (rule.rank < 1 || rule.rank > max) {
        throw ArgumentError.value(
          rule.rank,
          '$field.rank',
          'A ${rule.percent ? 'percent ' : ''}rank must be from 1 to $max.',
        );
      }
    case XlsxAverageRule():
      final int? sd = rule.standardDeviations;
      if (sd != null && (sd < 1 || sd > _maxStandardDeviations)) {
        throw ArgumentError.value(
          sd,
          '$field.standardDeviations',
          'Standard deviations must be from 1 to $_maxStandardDeviations.',
        );
      }
    case XlsxDuplicateRule():
      break;
    case XlsxTextRule():
      if (scrubXmlText(rule.text).removed > 0) {
        throw ArgumentError.value(
          rule.text,
          '$field.text',
          'The text must not contain characters XML forbids.',
        );
      }
      checkFormulaText(textRuleFormula(rule, first), '$field.text');
    case XlsxColorScale():
      final int count = rule.points.length;
      if (count < 2 || count > 3) {
        throw ArgumentError.value(
          count,
          '$field.points',
          'A color scale has 2 or 3 points.',
        );
      }
      if (rule.colors.length != count) {
        throw ArgumentError.value(
          rule.colors.length,
          '$field.colors',
          'A color scale needs one color per point: $count.',
        );
      }
      for (int j = 0; j < count; j++) {
        _checkCfValue(rule.points[j], '$field.points[$j]');
        validateColor(rule.colors[j], '$field.colors[$j]');
      }
    case XlsxDataBar():
      _checkCfValue(rule.min, '$field.min');
      _checkCfValue(rule.max, '$field.max');
      validateColor(rule.color, '$field.color');
      for (final (XlsxColor? color, String name) in <(XlsxColor?, String)>[
        (rule.borderColor, 'borderColor'),
        (rule.negativeFillColor, 'negativeFillColor'),
        (rule.negativeBorderColor, 'negativeBorderColor'),
        (rule.axisColor, 'axisColor'),
      ]) {
        if (color != null) validateColor(color, '$field.$name');
      }
      _checkLength(rule.minLength, '$field.minLength');
      _checkLength(rule.maxLength, '$field.maxLength');
      if (rule.minLength > rule.maxLength) {
        throw ArgumentError.value(
          rule.minLength,
          '$field.minLength',
          'The shortest bar must not be longer than the longest, '
              '${rule.maxLength}.',
        );
      }
    case XlsxIconSet():
      final List<XlsxCfValue>? thresholds = rule.thresholds;
      if (thresholds == null) break;
      if (thresholds.length != rule.type.iconCount) {
        throw ArgumentError.value(
          thresholds.length,
          '$field.thresholds',
          'The icon set ${rule.type.xmlName} takes ${rule.type.iconCount} '
              'thresholds.',
        );
      }
      for (int j = 0; j < thresholds.length; j++) {
        _checkCfValue(thresholds[j], '$field.thresholds[$j]');
      }
  }
}

void _checkLength(int length, String field) {
  if (length < 0 || length > 100) {
    throw ArgumentError.value(
      length,
      field,
      'A bar length must be from 0 to 100 percent.',
    );
  }
}

/// Throws unless [cfvo] has a value when its type needs one, valid formula
/// text, a finite number, and a percent or percentile from 0 to 100 when
/// the value reads as a number; a reference or formula passes unchecked.
void _checkCfValue(XlsxCfValue cfvo, String field) {
  final String? value = cfvo.value;
  if (value == null) {
    if (cfvo.type.needsValue) {
      throw ArgumentError.value(
        cfvo,
        field,
        'A ${cfvo.type.name} point needs a value.',
      );
    }
    return;
  }
  final String text = checkFormulaText(value, field);
  if (cfvo.type == XlsxCfValueType.formula) return;
  final double? number = double.tryParse(text);
  if (number == null) return;
  if (!number.isFinite) {
    throw ArgumentError.value(cfvo, field, 'A number must be finite.');
  }
  if ((cfvo.type == XlsxCfValueType.percent ||
          cfvo.type == XlsxCfValueType.percentile) &&
      (number < 0 || number > 100)) {
    throw ArgumentError.value(
      cfvo,
      field,
      'A ${cfvo.type.name} must be from 0 to 100.',
    );
  }
}

/// The formula Excel evaluates for [rule], relative to the top-left cell
/// of [first], the format's first range; a `"` in the text is doubled.
String textRuleFormula(XlsxTextRule rule, XlsxRange first) {
  final String cell = cellRef(first.firstRow, first.firstColumn);
  final String text = '"${rule.text.replaceAll('"', '""')}"';
  return switch (rule.operator) {
    XlsxTextOperator.contains => 'NOT(ISERROR(SEARCH($text,$cell)))',
    XlsxTextOperator.notContains => 'ISERROR(SEARCH($text,$cell))',
    XlsxTextOperator.beginsWith => 'LEFT($cell,LEN($text))=$text',
    XlsxTextOperator.endsWith => 'RIGHT($cell,LEN($text))=$text',
  };
}

/// The default thresholds of an icon set of [count] icons: equal percent
/// steps from 0, as Excel writes them.
List<XlsxCfValue> defaultIconSetThresholds(int count) => <XlsxCfValue>[
  for (int i = 0; i < count; i++)
    XlsxCfValue(XlsxCfValueType.percent, value: '${(i * 100 / count).round()}'),
];

/// Writes one `conditionalFormatting` element per format of [formats],
/// which the writer has checked, in the order registered.
///
/// An icon set only Excel 2010 has gets no `cfRule` (see
/// `writeX14ConditionalFormats`), and a format of nothing else no
/// `conditionalFormatting`, which needs a `cfRule`; its priority stays
/// taken. A data bar's `cfRule` ends with the `extLst` naming its Excel
/// 2010 rule, whose id [sheetNumber], the sheet's creation order, and the
/// rule's index on the sheet make (`x14RuleId`).
///
/// `cfRule` attributes follow `CT_CfRule` (`type`, `dxfId`, `priority`,
/// `stopIfTrue`, `aboveAverage`, `percent`, `bottom`, `operator`, `text`,
/// `rank`, `stdDev`, `equalAverage`), those at the schema default left
/// out; `rank` is always written for `top10`. Formulas go through
/// `escapeFormulaText`, the `text` attribute and `cfvo` values through
/// `escapeXstring`.
void writeConditionalFormats(
  XmlWriter w,
  List<WorksheetConditionalFormat> formats,
  int sheetNumber,
) {
  for (final WorksheetConditionalFormat f in formats) {
    final List<XlsxConditionalRule> rules = f.format.rules;
    if (rules.every(isX14OnlyRule)) continue;
    final List<XlsxRange> ranges = f.format.ranges;
    w.start('conditionalFormatting');
    w.attribute('sqref', ranges.map((XlsxRange r) => r.ref).join(' '));
    for (int i = 0; i < rules.length; i++) {
      if (isX14OnlyRule(rules[i])) continue;
      final int priority = f.firstPriority + i;
      _writeRule(
        w,
        rules[i],
        f.dxfIds[i],
        priority,
        ranges.first,
        x14RuleId(sheetNumber, priority - 1),
      );
    }
    w.end();
  }
}

/// Writes the `cfRule` of [rule]; [x14Id] is the id of its Excel 2010
/// rule, used when it is a data bar.
void _writeRule(
  XmlWriter w,
  XlsxConditionalRule rule,
  int? dxfId,
  int priority,
  XlsxRange first,
  String x14Id,
) {
  w.start('cfRule');
  w.attribute('type', switch (rule) {
    XlsxCellValueRule() => 'cellIs',
    XlsxExpressionRule() => 'expression',
    XlsxTopBottomRule() => 'top10',
    XlsxAverageRule() => 'aboveAverage',
    XlsxDuplicateRule(:final bool unique) =>
      unique ? 'uniqueValues' : 'duplicateValues',
    XlsxTextRule(:final XlsxTextOperator operator) => switch (operator) {
      XlsxTextOperator.contains => 'containsText',
      XlsxTextOperator.notContains => 'notContainsText',
      XlsxTextOperator.beginsWith => 'beginsWith',
      XlsxTextOperator.endsWith => 'endsWith',
    },
    XlsxColorScale() => 'colorScale',
    XlsxDataBar() => 'dataBar',
    XlsxIconSet() => 'iconSet',
  });
  if (dxfId != null) w.attribute('dxfId', '$dxfId');
  w.attribute('priority', '$priority');
  if (rule.stopIfTrue) w.attribute('stopIfTrue', '1');
  switch (rule) {
    case XlsxCellValueRule():
      w.attribute('operator', rule.comparison.name);
      _writeFormula(w, rule.formula1);
      final String? second = rule.formula2;
      if (second != null) _writeFormula(w, second);
    case XlsxExpressionRule():
      _writeFormula(w, rule.formula);
    case XlsxTopBottomRule():
      if (rule.percent) w.attribute('percent', '1');
      if (rule.bottom) w.attribute('bottom', '1');
      w.attribute('rank', '${rule.rank}');
    case XlsxAverageRule():
      if (!rule.above) w.attribute('aboveAverage', '0');
      final int? sd = rule.standardDeviations;
      if (sd != null) w.attribute('stdDev', '$sd');
      if (rule.orEqual) w.attribute('equalAverage', '1');
    case XlsxDuplicateRule():
      break;
    case XlsxTextRule():
      w.attribute('operator', switch (rule.operator) {
        XlsxTextOperator.contains => 'containsText',
        XlsxTextOperator.notContains => 'notContains',
        XlsxTextOperator.beginsWith => 'beginsWith',
        XlsxTextOperator.endsWith => 'endsWith',
      });
      w.attribute('text', escapeXstring(rule.text));
      _writeFormula(w, textRuleFormula(rule, first));
    case XlsxColorScale():
      w.start('colorScale');
      for (final XlsxCfValue point in rule.points) {
        _writeCfValue(w, point);
      }
      for (final XlsxColor color in rule.colors) {
        _writeColor(w, color);
      }
      w.end();
    case XlsxDataBar():
      w.start('dataBar');
      if (rule.minLength != 10) {
        w.attribute('minLength', '${rule.minLength}');
      }
      if (rule.maxLength != 90) {
        w.attribute('maxLength', '${rule.maxLength}');
      }
      if (!rule.showValue) w.attribute('showValue', '0');
      _writeCfValue(w, rule.min);
      _writeCfValue(w, rule.max);
      _writeColor(w, rule.color);
      w.end();
      writeX14RuleReference(w, x14Id);
    case XlsxIconSet():
      w.start('iconSet');
      w.attribute('iconSet', rule.type.xmlName);
      if (!rule.showValue) w.attribute('showValue', '0');
      if (rule.reverse) w.attribute('reverse', '1');
      final List<XlsxCfValue> thresholds =
          rule.thresholds ?? defaultIconSetThresholds(rule.type.iconCount);
      for (final XlsxCfValue threshold in thresholds) {
        _writeCfValue(w, threshold);
      }
      w.end();
  }
  w.end();
}

void _writeFormula(XmlWriter w, String text) {
  w.start('formula');
  w.raw(escapeFormulaText(writtenFormulaText(text)));
  w.end();
}

void _writeCfValue(XmlWriter w, XlsxCfValue cfvo) {
  w.start('cfvo');
  w.attribute('type', cfvo.type.xmlName);
  final String? value = cfvo.value;
  if (value != null) {
    w.attribute('val', escapeXstring(writtenFormulaText(value)));
  }
  if (!cfvo.greaterOrEqual) w.attribute('gte', '0');
  w.end();
}

void _writeColor(XmlWriter w, XlsxColor color) {
  w.start('color');
  writeColorAttributes(w, color);
  w.end();
}
