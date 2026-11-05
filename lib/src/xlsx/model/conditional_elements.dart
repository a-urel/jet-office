/// Reading `<conditionalFormatting>` elements as [CfEntry] values, and the
/// [CfBlock] that keeps them in a worksheet part.
///
/// Not ported from Quds; written for jet_office.
///
/// A reading is `writeConditionalFormats` in reverse. Each attribute goes
/// through the schema's default, as the writer writes it, so what the writer
/// wrote reads back equal: `aboveAverage` is true when left out, `minLength`
/// 10, `maxLength` 90, `showValue` true and `iconSet` `3TrafficLights1`. A
/// text attribute, a `cfvo` value and a formula are `ST_Xstring`s (`_xHHHH_`
/// decoded). An icon set with Excel's default thresholds reads with none, as
/// the writer writes those for none. A text rule's formula is derived from
/// its text (`textRuleFormula`), so it is not read. A data bar reads with the
/// fields the Excel 2007 element holds and the id of its Excel 2010 rule; the
/// other fields are read in `conditional_x14.dart`.
///
/// `timePeriod`, `containsBlanks`, `notContainsBlanks`, `containsErrors` and
/// `notContainsErrors` have no value type: they carry a `<formula>` and read
/// as [XlsxExpressionRule]s. Their element stays as written.
///
/// The value of a rule that formats a cell holds no style: the file names it
/// by [CfRuleEntry.dxfId], and the styles part knows it. An element with a
/// rule that cannot be read is a problem as a whole, the same as one whose
/// value the writer would refuse (`checkConditionalFormat`), so every value
/// read here can be written; the model keeps it as written.
library;

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../color.dart';
import '../comparison.dart';
import '../conditional_format.dart';
import '../conditional_format_x14.dart'
    show defaultBarAxisColor, defaultNegativeBarFill;
import '../range.dart';
import 'item_group.dart' show GroupItem, readerOf;
import 'style_elements.dart' show ReadStyleValue, readColor;
import 'validation_elements.dart' show childText, parseSqref;

/// The highest value of the `xsd:int` a `priority` is.
const int maxRulePriority = 0x7FFFFFFF;

/// The highest value of the `xsd:unsignedInt` a `dxfId` is.
const int _maxDxfId = 0xFFFFFFFF;

/// One `<cfRule>`, as the model reads it.
final class CfRuleEntry {
  /// A rule reading as [rule], with [priority].
  const CfRuleEntry(this.rule, this.priority, {this.dxfId, this.x14Id});

  /// The rule, with no style: [dxfId] names that.
  final XlsxConditionalRule rule;

  /// The index of the rule's `<dxf>` in the styles part, as written, or
  /// `null` for none.
  final int? dxfId;

  /// The rule's priority: the lowest number is evaluated first.
  final int priority;

  /// The id of the rule's Excel 2010 rule, or `null` for none.
  final String? x14Id;
}

/// One readable `<conditionalFormatting>`.
final class CfEntry {
  /// An entry of [rules] on [ranges], read from [source].
  const CfEntry(this.ranges, this.rules, this.source);

  /// The cells the rules apply to.
  final List<XlsxRange> ranges;

  /// The rules, in file order.
  final List<CfRuleEntry> rules;

  /// The element, as read or as the writer rendered it.
  final OpaqueXml source;
}

/// The first run of adjacent `<conditionalFormatting>` elements of a
/// worksheet: one child of the part, so that swapping it undoes an edit and
/// keeps the order of the elements.
///
/// The elements are [items] in file order, each kept as written; one that
/// cannot be read has no value. A block is immutable: an edit makes a new one,
/// and it may hold no item, when it writes nothing and only keeps its place,
/// so an undo puts the elements back there.
final class CfBlock {
  /// A block of [items].
  const CfBlock(this.items);

  /// The elements, in file order.
  final List<GroupItem<CfEntry>> items;

  /// The highest priority the elements hold, or 0 for none.
  int get highestPriority {
    int highest = 0;
    for (final GroupItem<CfEntry> item in items) {
      final CfEntry? entry = item.value;
      if (entry == null) {
        final int found = highestRulePriority(item.source);
        if (found > highest) highest = found;
        continue;
      }
      for (final CfRuleEntry rule in entry.rules) {
        if (rule.priority > highest) highest = rule.priority;
      }
    }
    return highest;
  }

  /// Writes the elements to [w]. [above] holds the bindings in scope.
  void writeTo(XmlWriter w, Map<String, String> above) {
    for (final GroupItem<CfEntry> item in items) {
      item.source.writeTo(w, declaredAbove: above);
    }
  }
}

/// The highest usable `priority` of the `<cfRule>`s and `x14:cfRule`s of
/// [element], which may be unreadable otherwise, or 0 for none. Never throws.
int highestRulePriority(OpaqueXml element) {
  final XmlPullReader r = readerOf(element);
  final int depth = r.depth;
  int highest = 0;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement ||
        r.namespaceUri != Ns.main && r.namespaceUri != Ns.x14 ||
        r.localName != 'cfRule') {
      continue;
    }
    final int? priority = readPriority(
      r.getAttribute('priority', namespaceUri: ''),
    );
    if (priority != null && priority > highest) highest = priority;
  }
  return highest;
}

/// The [CfEntry] of the `<conditionalFormatting>` [element], or the problem
/// that keeps it from being read, named `conditionalFormatting`: no usable
/// `sqref`, no rule, a rule that cannot be read, or a value the writer's
/// `checkConditionalFormat` refuses.
({CfEntry? value, String? problem}) readConditionalFormatting(
  OpaqueXml element,
) {
  const ({CfEntry? value, String? problem}) bad = (
    value: null,
    problem: 'conditionalFormatting',
  );
  final XmlPullReader r = readerOf(element);
  final String? sqref = r.getAttribute('sqref', namespaceUri: '');
  final List<XlsxRange>? ranges = sqref == null ? null : parseSqref(sqref);
  if (ranges == null) return bad;
  final List<CfRuleEntry> rules = <CfRuleEntry>[];
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.namespaceUri != Ns.main || r.localName != 'cfRule') {
      r.skip();
      continue;
    }
    final CfRuleEntry? rule = _readRule(r);
    if (rule == null) return bad;
    rules.add(rule);
  }
  try {
    checkConditionalFormat(
      XlsxConditionalFormat(ranges, <XlsxConditionalRule>[
        for (final CfRuleEntry rule in rules) rule.rule,
      ]),
    );
  } on ArgumentError {
    return bad;
  }
  return (value: CfEntry(ranges, rules, element), problem: null);
}

/// [format] as a reading of what the writer writes for it gives: a leading
/// `=` of a formula or a `cfvo` value is not written, an icon set's default
/// thresholds read as none, and so do the colors of a data bar `barAsWritten`
/// drops. An added entry holds this form, so the
/// model says what its file says, and removal looks for it, so a value built
/// by hand matches the entry it was added as, after a save too.
XlsxConditionalFormat normalizedConditionalFormat(
  XlsxConditionalFormat format,
) => XlsxConditionalFormat(format.ranges, <XlsxConditionalRule>[
  for (final XlsxConditionalRule rule in format.rules) _normalizedRule(rule),
]);

XlsxConditionalRule _normalizedRule(XlsxConditionalRule rule) => switch (rule) {
  XlsxCellValueRule() => XlsxCellValueRule(
    rule.comparison,
    _written(rule.formula1),
    formula2: rule.formula2 == null ? null : _written(rule.formula2!),
    style: rule.style,
    stopIfTrue: rule.stopIfTrue,
  ),
  XlsxExpressionRule() => XlsxExpressionRule(
    _written(rule.formula),
    style: rule.style,
    stopIfTrue: rule.stopIfTrue,
  ),
  XlsxColorScale() => XlsxColorScale(
    rule.points.map(_normalizedPoint).toList(),
    rule.colors,
    stopIfTrue: rule.stopIfTrue,
  ),
  XlsxDataBar() => barAsWritten(
    rule,
    min: _normalizedPoint(rule.min),
    max: _normalizedPoint(rule.max),
  ),
  XlsxIconSet() => XlsxIconSet(
    rule.type,
    thresholds: rule.thresholds == null
        ? null
        : iconThresholds(
            rule.type,
            rule.thresholds!.map(_normalizedPoint).toList(),
          ),
    reverse: rule.reverse,
    showValue: rule.showValue,
    stopIfTrue: rule.stopIfTrue,
  ),
  XlsxTopBottomRule() ||
  XlsxAverageRule() ||
  XlsxDuplicateRule() ||
  XlsxTextRule() => rule,
};

/// [bar] as a reading gives it, with [min] and [max] for its points when
/// given: a color the writer fills for none reads as none (a negative fill of
/// red, an axis of black, a border of the bar's color), and the colors of a
/// border go without one, as the writer leaves them out.
XlsxDataBar barAsWritten(
  XlsxDataBar bar, {
  XlsxCfValue? min,
  XlsxCfValue? max,
}) {
  XlsxColor? unless(XlsxColor? color, XlsxColor filled) =>
      color == filled ? null : color;
  return XlsxDataBar(
    min: min ?? bar.min,
    max: max ?? bar.max,
    color: bar.color,
    showValue: bar.showValue,
    minLength: bar.minLength,
    maxLength: bar.maxLength,
    gradient: bar.gradient,
    border: bar.border,
    borderColor: bar.border ? unless(bar.borderColor, bar.color) : null,
    negativeFillColor: unless(bar.negativeFillColor, defaultNegativeBarFill),
    negativeBorderColor: bar.border ? bar.negativeBorderColor : null,
    axis: bar.axis,
    axisColor: unless(bar.axisColor, defaultBarAxisColor),
    stopIfTrue: bar.stopIfTrue,
  );
}

XlsxCfValue _normalizedPoint(XlsxCfValue point) => XlsxCfValue(
  point.type,
  value: point.value == null ? null : _written(point.value!),
  greaterOrEqual: point.greaterOrEqual,
);

/// [text] without one leading `=`.
String _written(String text) => text.startsWith('=') ? text.substring(1) : text;

/// [points] as an icon set of [type] holds them: `null` when they are
/// Excel's default thresholds, which the writer writes for none.
List<XlsxCfValue>? iconThresholds(
  XlsxIconSetType type,
  List<XlsxCfValue> points,
) {
  final List<XlsxCfValue> defaults = defaultIconSetThresholds(type.iconCount);
  if (points.length != defaults.length) return points;
  for (int i = 0; i < points.length; i++) {
    if (points[i] != defaults[i]) return points;
  }
  return null;
}

/// What the children of a `<cfRule>` hold.
final class _RuleBody {
  /// The texts of the `<formula>` children, in order.
  final List<String> formulas = <String>[];

  /// The local name of the first `colorScale`, `dataBar` or `iconSet`.
  String? name;

  /// The attributes of that element.
  final Map<String, String> attributes = <String, String>{};

  /// Its `<cfvo>` children, in order.
  final List<XlsxCfValue> points = <XlsxCfValue>[];

  /// Its `<color>` children, in order.
  final List<XlsxColor> colors = <XlsxColor>[];

  /// Whether a child of that element cannot be read.
  bool invalid = false;

  /// The id the `extLst` names.
  String? x14Id;
}

/// Reads the `<cfRule>` [r] is on and consumes it; `null` when it cannot be
/// read.
CfRuleEntry? _readRule(XmlPullReader r) {
  // The attributes are read before the children move the reader.
  String? attribute(String name) => r.getAttribute(name, namespaceUri: '');
  final int? priority = readPriority(attribute('priority'));
  final String? dxfText = attribute('dxfId');
  final int? dxfId = dxfText == null ? null : readInt(dxfText, 0, _maxDxfId);
  final String? type = attribute('type');
  final String? operator = attribute('operator');
  final String? text = attribute('text');
  final String? rank = attribute('rank');
  final String? stdDev = attribute('stdDev');
  final bool stopIfTrue = readFlag(attribute('stopIfTrue'));
  final bool percent = readFlag(attribute('percent'));
  final bool bottom = readFlag(attribute('bottom'));
  final bool above = readFlag(attribute('aboveAverage'), fallback: true);
  final bool orEqual = readFlag(attribute('equalAverage'));

  final _RuleBody body = _RuleBody();
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    final String name = r.namespaceUri == Ns.main ? r.localName : '';
    switch (name) {
      case 'formula':
        body.formulas.add(childText(r));
      case 'colorScale' || 'dataBar' || 'iconSet' when body.name == null:
        _readBody(r, body);
      case 'extLst':
        body.x14Id ??= _readX14Id(r);
      default:
        r.skip();
    }
  }
  if (priority == null || type == null) return null;
  if (dxfText != null && dxfId == null) return null;
  final List<String> formulas = body.formulas;
  XlsxExpressionRule? expression() => formulas.isEmpty
      ? null
      : XlsxExpressionRule(formulas.first, stopIfTrue: stopIfTrue);
  XlsxTextRule? textRule(XlsxTextOperator operator) => text == null
      ? null
      : XlsxTextRule(operator, decodeXstring(text), stopIfTrue: stopIfTrue);
  final XlsxConditionalRule? rule = switch (type) {
    'cellIs' => cellValueRule(operator, formulas, stopIfTrue),
    'expression' ||
    'timePeriod' ||
    'containsBlanks' ||
    'notContainsBlanks' ||
    'containsErrors' ||
    'notContainsErrors' => expression(),
    'top10' => _topBottomRule(rank, percent, bottom, stopIfTrue),
    'aboveAverage' => _averageRule(above, orEqual, stdDev, stopIfTrue),
    'duplicateValues' => XlsxDuplicateRule(stopIfTrue: stopIfTrue),
    'uniqueValues' => XlsxDuplicateRule(unique: true, stopIfTrue: stopIfTrue),
    'containsText' => textRule(XlsxTextOperator.contains),
    'notContainsText' => textRule(XlsxTextOperator.notContains),
    'beginsWith' => textRule(XlsxTextOperator.beginsWith),
    'endsWith' => textRule(XlsxTextOperator.endsWith),
    'colorScale' => _colorScale(body, stopIfTrue),
    'dataBar' => _dataBar(body, stopIfTrue),
    'iconSet' => _iconSet(body, stopIfTrue),
    _ => null,
  };
  if (rule == null) return null;
  return CfRuleEntry(rule, priority, dxfId: dxfId, x14Id: body.x14Id);
}

/// The rule [operator] and [formulas] make, the reading of a `cellIs` rule, or
/// `null` for an unknown operator or too few formulas.
XlsxCellValueRule? cellValueRule(
  String? operator,
  List<String> formulas,
  bool stopIfTrue,
) {
  XlsxComparison? comparison;
  for (final XlsxComparison c in XlsxComparison.values) {
    if (c.name == operator) comparison = c;
  }
  if (comparison == null || formulas.isEmpty) return null;
  final bool two = comparison.takesTwoOperands;
  if (two && formulas.length < 2) return null;
  return XlsxCellValueRule(
    comparison,
    formulas.first,
    formula2: two ? formulas[1] : null,
    stopIfTrue: stopIfTrue,
  );
}

XlsxTopBottomRule? _topBottomRule(
  String? rankText,
  bool percent,
  bool bottom,
  bool stopIfTrue,
) {
  final int? rank = rankText == null
      ? null
      : readInt(rankText, 0, maxRulePriority);
  if (rank == null) return null;
  return XlsxTopBottomRule(
    rank: rank,
    percent: percent,
    bottom: bottom,
    stopIfTrue: stopIfTrue,
  );
}

XlsxAverageRule? _averageRule(
  bool above,
  bool orEqual,
  String? stdDevText,
  bool stopIfTrue,
) {
  final int? stdDev = stdDevText == null
      ? null
      : readInt(stdDevText, 0, maxRulePriority);
  if (stdDevText != null && stdDev == null) return null;
  return XlsxAverageRule(
    above: above,
    orEqual: orEqual,
    standardDeviations: stdDev,
    stopIfTrue: stopIfTrue,
  );
}

XlsxColorScale? _colorScale(_RuleBody body, bool stopIfTrue) =>
    body.name != 'colorScale' || body.invalid
    ? null
    : XlsxColorScale(body.points, body.colors, stopIfTrue: stopIfTrue);

XlsxDataBar? _dataBar(_RuleBody body, bool stopIfTrue) {
  if (body.name != 'dataBar' ||
      body.invalid ||
      body.points.length != 2 ||
      body.colors.isEmpty) {
    return null;
  }
  final String? minText = body.attributes['minLength'];
  final String? maxText = body.attributes['maxLength'];
  final int? minLength = minText == null ? 10 : readInt(minText, 0, 100);
  final int? maxLength = maxText == null ? 90 : readInt(maxText, 0, 100);
  if (minLength == null || maxLength == null) return null;
  return XlsxDataBar(
    min: body.points[0],
    max: body.points[1],
    color: body.colors.first,
    showValue: readFlag(body.attributes['showValue'], fallback: true),
    minLength: minLength,
    maxLength: maxLength,
    stopIfTrue: stopIfTrue,
  );
}

XlsxIconSet? _iconSet(_RuleBody body, bool stopIfTrue) {
  if (body.name != 'iconSet' || body.invalid) return null;
  final String name = body.attributes['iconSet'] ?? '3TrafficLights1';
  XlsxIconSetType? type;
  for (final XlsxIconSetType t in XlsxIconSetType.values) {
    if (t.xmlName == name && !t.isX14Only) type = t;
  }
  if (type == null) return null;
  return XlsxIconSet(
    type,
    thresholds: iconThresholds(type, body.points),
    reverse: readFlag(body.attributes['reverse']),
    showValue: readFlag(body.attributes['showValue'], fallback: true),
    stopIfTrue: stopIfTrue,
  );
}

/// Reads the `colorScale`, `dataBar` or `iconSet` [r] is on into [body] and
/// consumes it.
void _readBody(XmlPullReader r, _RuleBody body) {
  body.name = r.localName;
  for (final String name in const <String>[
    'minLength',
    'maxLength',
    'showValue',
    'iconSet',
    'reverse',
  ]) {
    final String? value = r.getAttribute(name, namespaceUri: '');
    if (value != null) body.attributes[name] = value;
  }
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    final String name = r.namespaceUri == Ns.main ? r.localName : '';
    if (name == 'cfvo') {
      final XlsxCfValue? point = _readCfValue(r);
      if (point == null) {
        body.invalid = true;
      } else {
        body.points.add(point);
      }
    } else if (name == 'color') {
      final ReadStyleValue<XlsxColor?> color = readColor(r);
      final XlsxColor? value = color.value;
      if (value == null) {
        body.invalid = true;
      } else {
        body.colors.add(value);
      }
    } else {
      r.skip();
    }
  }
}

/// The value of the `<cfvo>` [r] is on, consuming it; `null` for an unknown
/// `type`.
XlsxCfValue? _readCfValue(XmlPullReader r) {
  final String? type = r.getAttribute('type', namespaceUri: '');
  final String? value = r.getAttribute('val', namespaceUri: '');
  final bool gte = readFlag(
    r.getAttribute('gte', namespaceUri: ''),
    fallback: true,
  );
  r.skip();
  for (final XlsxCfValueType t in XlsxCfValueType.values) {
    if (t.xmlName == type) {
      return XlsxCfValue(
        t,
        value: value == null ? null : decodeXstring(value),
        greaterOrEqual: gte,
      );
    }
  }
  return null;
}

/// The text of the first `x14:id` of the `extLst` [r] is on, consuming it;
/// `null` for none.
String? _readX14Id(XmlPullReader r) {
  String? id;
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType == XmlEventType.startElement &&
        r.namespaceUri == Ns.x14 &&
        r.localName == 'id') {
      final String text = childText(r);
      id ??= text;
    }
  }
  return id;
}

/// The `priority` of [text], or `null` when it is absent or not an `xsd:int`.
int? readPriority(String? text) =>
    text == null ? null : readInt(text, -maxRulePriority - 1, maxRulePriority);

/// The integer [text] from [min] to [max], as `xsd:int` spells it, or `null`.
int? readInt(String text, int min, int max) {
  final String trimmed = text.trim();
  if (!RegExp(r'^[+-]?[0-9]{1,10}$').hasMatch(trimmed)) return null;
  final int value = int.parse(trimmed);
  return value < min || value > max ? null : value;
}

/// `1` or `true` as true, `0` or `false` as false, anything else as
/// [fallback], the schema's default.
bool readFlag(String? text, {bool fallback = false}) => switch (text) {
  '1' || 'true' => true,
  '0' || 'false' => false,
  _ => fallback,
};
