/// The Excel 2010 extensions of conditional formats: the rule every data
/// bar gains, and the icon sets only Excel 2010 has.
///
/// New in jet_office; Quds wrote no data bars or icon sets. A data bar
/// keeps its Excel 2007 `cfRule`, which [writeX14RuleReference] gives an
/// `extLst` naming its Excel 2010 rule by id; [writeX14ConditionalFormats]
/// writes those rules, and the rules of the icon sets only Excel 2010 has,
/// which have no Excel 2007 `cfRule`, in the worksheet's `extLst`. Excel
/// 2010 and later write both for every data bar, and without the second
/// Excel 2016 draws the 2007 bar. The elements follow the `x14` schema of
/// MS-XLSX, as the Open XML SDK validates it: `CT_ConditionalFormatting`
/// (`cfRule`, then `xm:sqref`), `CT_CfRule`, `CT_DataBar`, `CT_IconSet` and
/// `CT_Cfvo`. What both files need, [isX14OnlyRule], [x14RuleId] and
/// [writeX14RuleReference], lives in `conditional_format.dart`, so only
/// this file imports the other.
library;

import '../opc/ooxml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'color.dart';
import 'conditional_format.dart';
import 'formula_text.dart';
import 'range.dart';

/// The `uri` of the worksheet `ext` that holds Excel 2010 conditional
/// formats. Excel writes it with the lowercase `d`.
const String _sheetExtUri = '{78C0D931-6437-407d-A8EE-F0AAD7539E65}';

/// Whether [rule] has an Excel 2010 rule: a data bar, or an icon set only
/// Excel 2010 has.
bool hasX14Rule(XlsxConditionalRule rule) =>
    rule is XlsxDataBar || isX14OnlyRule(rule);

/// Writes the worksheet `extLst` holding the Excel 2010 rules of
/// [formats], which the writer has checked, or nothing when no rule has
/// one (see [hasX14Rule]).
///
/// One `x14:conditionalFormatting` per format with such a rule, in the
/// order registered, holding those rules in order and then the format's
/// ranges as `xm:sqref`. A data bar's rule has no `priority`: its Excel
/// 2007 `cfRule` has it. The rule of an icon set only Excel 2010 has takes
/// the priority it was numbered with, from the same counter as the Excel
/// 2007 rules, and its `stopIfTrue`. [sheetNumber] is the sheet's creation
/// order, for [x14RuleId].
///
/// The `extLst` is the worksheet's last child (`CT_Worksheet`).
void writeX14ConditionalFormats(
  XmlWriter w,
  List<WorksheetConditionalFormat> formats,
  int sheetNumber,
) {
  bool hasRules(WorksheetConditionalFormat f) => f.format.rules.any(hasX14Rule);
  if (!formats.any(hasRules)) return;
  w.start('extLst');
  w.start('ext');
  w.attribute('uri', _sheetExtUri);
  w.attribute('xmlns:x14', Ns.x14);
  w.start('x14:conditionalFormattings');
  for (final WorksheetConditionalFormat f in formats.where(hasRules)) {
    w.start('x14:conditionalFormatting');
    w.attribute('xmlns:xm', Ns.xm);
    final List<XlsxConditionalRule> rules = f.format.rules;
    for (int i = 0; i < rules.length; i++) {
      if (!hasX14Rule(rules[i])) continue;
      final int priority = f.firstPriority + i;
      // Priorities run from 1 over the sheet's rules in registration order,
      // so a rule's 0-based index on the sheet is its priority less one.
      _writeRule(w, rules[i], priority, x14RuleId(sheetNumber, priority - 1));
    }
    w.start('xm:sqref');
    w.text(f.format.ranges.map((XlsxRange r) => r.ref).join(' '));
    w.end();
    w.end();
  }
  w.end();
  w.end();
  w.end();
}

/// Writes the `x14:cfRule` of [rule], a data bar or an icon set only
/// Excel 2010 has, with the id [id].
void _writeRule(
  XmlWriter w,
  XlsxConditionalRule rule,
  int priority,
  String id,
) {
  w.start('x14:cfRule');
  switch (rule) {
    case XlsxDataBar():
      w.attribute('type', 'dataBar');
      w.attribute('id', id);
      _writeDataBar(w, rule);
    case XlsxIconSet():
      w.attribute('type', 'iconSet');
      w.attribute('priority', '$priority');
      if (rule.stopIfTrue) w.attribute('stopIfTrue', '1');
      w.attribute('id', id);
      _writeIconSet(w, rule);
    default:
      throw StateError('$rule has no Excel 2010 rule.');
  }
  w.end();
}

/// The negative fill Excel writes on a data bar it creates: red.
const XlsxColor _defaultNegativeFill = XlsxColor.argb(0xFFFF0000);

/// The axis color Excel writes on a data bar it creates: black.
const XlsxColor _defaultAxis = XlsxColor.argb(0xFF000000);

/// Writes `x14:dataBar`: attributes in `CT_DataBar` order, those at the
/// schema default left out except the lengths; then the two `x14:cfvo`,
/// `x14:borderColor`, `x14:negativeFillColor`, `x14:negativeBorderColor`
/// and `x14:axisColor`.
///
/// The lengths are 0 and 100 when the Excel 2007 ones are their defaults,
/// 10 and 90, as Excel writes them. The border colors are written only
/// with a border; a border without its own color takes the bar's.
/// `negativeBarBorderColorSameAsPositive="0"` comes with a negative border
/// color, as Excel ignores the color otherwise.
///
/// The negative fill and the axis color are always written, Excel's
/// defaults, red and black, when the rule has none: Excel does not fall
/// back to them, and shows a missing color as white. The axis color is
/// written with no axis too, as Excel does. With the fill always written,
/// `negativeBarColorSameAsPositive` keeps its schema default, false.
void _writeDataBar(XmlWriter w, XlsxDataBar bar) {
  final XlsxColor? negativeBorder = bar.border ? bar.negativeBorderColor : null;
  w.start('x14:dataBar');
  w.attribute('minLength', '${bar.minLength == 10 ? 0 : bar.minLength}');
  w.attribute('maxLength', '${bar.maxLength == 90 ? 100 : bar.maxLength}');
  if (bar.border) w.attribute('border', '1');
  if (!bar.gradient) w.attribute('gradient', '0');
  if (negativeBorder != null) {
    w.attribute('negativeBarBorderColorSameAsPositive', '0');
  }
  if (bar.axis != XlsxDataBarAxis.automatic) {
    w.attribute('axisPosition', bar.axis.name);
  }
  _writeCfValue(w, bar.min, automatic: true);
  _writeCfValue(w, bar.max, automatic: true);
  if (bar.border) {
    _writeColor(w, 'x14:borderColor', bar.borderColor ?? bar.color);
  }
  _writeColor(
    w,
    'x14:negativeFillColor',
    bar.negativeFillColor ?? _defaultNegativeFill,
  );
  if (negativeBorder != null) {
    _writeColor(w, 'x14:negativeBorderColor', negativeBorder);
  }
  _writeColor(w, 'x14:axisColor', bar.axisColor ?? _defaultAxis);
  w.end();
}

/// Writes `x14:iconSet`: attributes in `CT_IconSet` order, those at the
/// schema default left out, then one `x14:cfvo` per threshold, Excel's
/// default ones when none are given.
void _writeIconSet(XmlWriter w, XlsxIconSet set) {
  w.start('x14:iconSet');
  w.attribute('iconSet', set.type.xmlName);
  if (!set.showValue) w.attribute('showValue', '0');
  if (set.reverse) w.attribute('reverse', '1');
  final List<XlsxCfValue> thresholds =
      set.thresholds ?? defaultIconSetThresholds(set.type.iconCount);
  for (final XlsxCfValue threshold in thresholds) {
    _writeCfValue(w, threshold, automatic: false);
  }
  w.end();
}

/// Writes `x14:cfvo` for [cfvo]; a value goes into `xm:f` through
/// `escapeFormulaText`. With [automatic], as for a data bar, `min` and
/// `max` are written as Excel's automatic bounds `autoMin` and `autoMax`.
void _writeCfValue(XmlWriter w, XlsxCfValue cfvo, {required bool automatic}) {
  w.start('x14:cfvo');
  w.attribute('type', switch (cfvo.type) {
    XlsxCfValueType.min when automatic => 'autoMin',
    XlsxCfValueType.max when automatic => 'autoMax',
    _ => cfvo.type.xmlName,
  });
  if (!cfvo.greaterOrEqual) w.attribute('gte', '0');
  final String? value = cfvo.value;
  if (cfvo.type.needsValue && value != null) {
    w.start('xm:f');
    w.raw(escapeFormulaText(writtenFormulaText(value)));
    w.end();
  }
  w.end();
}

void _writeColor(XmlWriter w, String name, XlsxColor color) {
  w.start(name);
  writeColorAttributes(w, color);
  w.end();
}
