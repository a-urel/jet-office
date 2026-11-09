/// Reading `<dataValidation>` elements as [XlsxDataValidation] values, and
/// the reading of a `sqref`.
///
/// Not ported from Quds; written for jet_office.
///
/// A reading gives each field the value the element states, through the
/// schema defaults: an attribute the file leaves out reads as the schema
/// says (`allowBlank` false, `showDropDown` false, so the arrow shows), and
/// the writer writes each flag exactly when it differs from that default, so
/// what the writer wrote reads back equal. Only what the writer writes has
/// a meaning: `operator` and `formula2` belong to the types that compare,
/// and `formula1` to every type but `any`. A text attribute is an
/// `ST_Xstring` (`_xHHHH_` decoded) and a formula is decoded the same way.
/// An element that cannot be read (no usable `sqref`, an unknown `type`,
/// `errorStyle` or `operator`) is a problem, and the model keeps it as
/// written.
library;

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../comparison.dart';
import '../data_validation.dart';
import '../formula/formula_rewrite.dart';
import '../range.dart';
import '../read/merge_reader.dart' show parseMergeRange;
import 'item_group.dart' show readerOf;
import 'reference_holders.dart';

/// The ranges of [text], a space-separated list of references (`A1 C3:D4`),
/// or `null` when the text is empty or any of its parts is not a range of
/// cells (`XlsxRange.parse` refuses it). Never throws.
List<XlsxRange>? parseSqref(String text) {
  final List<String> parts = text
      .split(RegExp(r'[ \t\r\n]+'))
      .where((String p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  final List<XlsxRange> ranges = <XlsxRange>[];
  for (final String part in parts) {
    final XlsxRange? range = parseMergeRange(part);
    if (range == null) return null;
    ranges.add(range);
  }
  return ranges;
}

/// `1` or `true` as true, `0` or `false` as false, anything else as the
/// schema default, false.
bool _flag(String? text) => text == '1' || text == 'true';

/// The [XlsxDataValidation] of the `<dataValidation>` [element], or the
/// problem that keeps it from being read, named `dataValidation`.
///
/// `showDropDown="1"` is `showDropDownArrow: false`; an absent `type` is
/// `any` and an absent `operator` is `between`.
({XlsxDataValidation? value, String? problem}) readDataValidation(
  OpaqueXml element,
) {
  const ({XlsxDataValidation? value, String? problem}) bad = (
    value: null,
    problem: 'dataValidation',
  );
  final XmlPullReader r = readerOf(element);
  String? attribute(String name) => r.getAttribute(name, namespaceUri: '');
  String? text(String name) {
    final String? value = attribute(name);
    return value == null ? null : decodeXstring(value);
  }

  final String? sqref = attribute('sqref');
  final List<XlsxRange>? ranges = sqref == null ? null : parseSqref(sqref);
  if (ranges == null) return bad;
  final String? typeText = attribute('type');
  final XlsxValidationType? type = typeText == null || typeText == 'none'
      ? XlsxValidationType.any
      : _byName(XlsxValidationType.values, typeText);
  final String? styleText = attribute('errorStyle');
  final XlsxValidationErrorStyle? style = styleText == null
      ? XlsxValidationErrorStyle.stop
      : _byName(XlsxValidationErrorStyle.values, styleText);
  final String? operatorText = attribute('operator');
  final XlsxComparison? comparison = operatorText == null
      ? XlsxComparison.between
      : _byName(XlsxComparison.values, operatorText);
  if (type == null || style == null || comparison == null) return bad;

  // The attributes are read before the children move the reader.
  final bool allowBlank = _flag(attribute('allowBlank'));
  final bool showDropDown = _flag(attribute('showDropDown'));
  final bool showInput = _flag(attribute('showInputMessage'));
  final bool showError = _flag(attribute('showErrorMessage'));
  final String? errorTitle = text('errorTitle');
  final String? error = text('error');
  final String? promptTitle = text('promptTitle');
  final String? prompt = text('prompt');

  String? formula1;
  String? formula2;
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement ||
        r.depth != depth + 1 ||
        r.namespaceUri != Ns.main) {
      continue;
    }
    final String name = r.localName;
    if (name != 'formula1' && name != 'formula2') continue;
    final String formula = childText(r);
    if (name == 'formula1') {
      formula1 ??= formula;
    } else {
      formula2 ??= formula;
    }
  }
  final bool compares = type.compares;
  return (
    value: XlsxDataValidation(
      ranges,
      type,
      comparison: compares ? comparison : XlsxComparison.between,
      formula1: type == XlsxValidationType.any ? null : formula1,
      formula2: compares && comparison.takesTwoOperands ? formula2 : null,
      allowBlank: allowBlank,
      showDropDownArrow: !showDropDown,
      showInputMessage: showInput,
      showErrorMessage: showError,
      errorStyle: style,
      errorTitle: errorTitle,
      error: error,
      promptTitle: promptTitle,
      prompt: prompt,
    ),
    problem: null,
  );
}

/// [validation] as a reading of what the writer writes for it gives: the
/// fields the writer leaves out are the ones it ignores, and a leading `=`
/// of a formula is not written. Removal compares this form, so a value
/// built by hand matches the entry it was added as.
XlsxDataValidation normalizedValidation(XlsxDataValidation validation) {
  final XlsxValidationType type = validation.type;
  final bool compares = type.compares;
  String? formula(String? text) =>
      text != null && text.startsWith('=') ? text.substring(1) : text;
  return XlsxDataValidation(
    validation.ranges,
    type,
    comparison: compares ? validation.comparison : XlsxComparison.between,
    formula1: type == XlsxValidationType.any
        ? null
        : formula(validation.formula1),
    formula2: compares && validation.comparison.takesTwoOperands
        ? formula(validation.formula2)
        : null,
    allowBlank: validation.allowBlank,
    showDropDownArrow: validation.showDropDownArrow,
    showInputMessage: validation.showInputMessage,
    showErrorMessage: validation.showErrorMessage,
    errorStyle: validation.errorStyle,
    errorTitle: validation.errorTitle,
    error: validation.error,
    promptTitle: validation.promptTitle,
    prompt: validation.prompt,
  );
}

/// The decoded text of the element [r] is on, consuming it.
String childText(XmlPullReader r) {
  final StringBuffer out = StringBuffer();
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType == XmlEventType.characters ||
        r.eventType == XmlEventType.cdata) {
      out.write(r.text);
    }
  }
  return decodeXstring(out.toString());
}

T? _byName<T extends Enum>(List<T> values, String name) {
  for (final T v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// The `<dataValidation>` [source] after a structural edit: its `sqref`
/// through [rewriteSqref], and its `formula1` and `formula2` through
/// the rewriter as written (Excel evaluates them at the `sqref`'s first
/// cell, so they shift as a cell formula of the sheet does);
/// `null` when the edit empties the `sqref`, [source] itself when nothing
/// changes. Only the changed text is rewritten. [onUnlexable] gets each
/// `sqref` or formula that cannot be lexed, which stays as read.
OpaqueXml? shiftedValidation(
  OpaqueXml source,
  ReferenceMapper mapper,
  String host,
  void Function(String text) onUnlexable,
) => shiftedSqrefElement(
  source,
  mapper,
  host,
  onUnlexable,
  isFormula: (XmlPullReader r, int level) =>
      level == 1 &&
      r.namespaceUri == Ns.main &&
      (r.localName == 'formula1' || r.localName == 'formula2'),
);

/// [source], an element whose `sqref` attribute says what it covers, after
/// a structural edit, as [shiftedValidation] says, with the text of each
/// descendant [isFormula] names as a formula, and,
/// when [isFormulaValue] names a descendant, its `val` attribute too.
OpaqueXml? shiftedSqrefElement(
  OpaqueXml source,
  ReferenceMapper mapper,
  String host,
  void Function(String text) onUnlexable, {
  required bool Function(XmlPullReader r, int level) isFormula,
  bool Function(XmlPullReader r, int level)? isFormulaValue,
}) {
  final String? sqref = readerOf(
    source,
  ).getAttribute('sqref', namespaceUri: '');
  if (sqref == null) return source;
  final String? nextSqref = rewriteSqref(
    sqref,
    mapper,
    host,
    onUnlexable: onUnlexable,
  );
  if (nextSqref != null && nextSqref.isEmpty) return null;
  String? formula(String text) =>
      rewriteFormula(text, mapper, host, onUnlexable: onUnlexable);
  return spliceElement(source, (XmlPullReader r, int level) {
    if (level == 0) {
      return nextSqref == null
          ? null
          : SpliceEdit(attributes: <String, String>{'sqref': nextSqref});
    }
    if (isFormula(r, level)) {
      return SpliceEdit(
        text: (String text) => rewrittenFormulaMarkup(text, formula),
      );
    }
    if (isFormulaValue != null && isFormulaValue(r, level)) {
      final String? value = r.getAttribute('val', namespaceUri: '');
      final String? next = value == null ? null : formula(decodeXstring(value));
      return next == null
          ? null
          : SpliceEdit(
              attributes: <String, String>{'val': escapeXstring(next)},
            );
    }
    return null;
  });
}
