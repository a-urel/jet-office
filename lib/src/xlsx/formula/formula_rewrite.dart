/// Rewrites the references of a formula, or of a `sqref` list, through a
/// [ReferenceMapper], copying every untouched span as read.
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import 'formula_lexer.dart';
import 'formula_reference.dart';
import 'formula_token.dart';
import 'structured_reference.dart';

/// What a reference becomes when it changes: another reference, or
/// `#REF!` (Excel's error for a reference whose cells are gone).
final class FormulaReferenceResult {
  /// The reference becomes [reference].
  const FormulaReferenceResult.to(FormulaReference this.reference);

  /// The reference becomes `#REF!`; a sheet prefix stays in front of it.
  const FormulaReferenceResult.refError() : reference = null;

  /// The new reference; `null` for `#REF!`.
  final FormulaReference? reference;
}

/// What a reference becomes: unchanged (`null` from [mapReference]), another
/// reference, or `#REF!`.
abstract interface class ReferenceMapper {
  /// What [ref] becomes; `null` when it is unchanged. [hostSheet] is the
  /// sheet the formula lives on (for unqualified refs). External references
  /// (`ref.externalIndex` set) are passed too; they name another workbook.
  FormulaReferenceResult? mapReference(FormulaReference ref, String hostSheet);

  /// The new name of [sheet], or `null` when it keeps its name. Never asked
  /// for an external prefix's sheet.
  String? mapSheetName(String sheet);

  /// The new text of the structured reference of [table] (`''` for `[@Qty]`
  /// inside the table) whose bracket span is [spec], or `null` when it is
  /// unchanged.
  String? mapStructured(String table, String spec, String hostSheet);
}

/// Rewrites [formula]; returns `null` when nothing changed (the caller keeps
/// the original text), else the new text. Untouched spans are copied as read.
///
/// A formula that cannot be lexed (it holds an `invalid` token) is left
/// alone: the result is `null` and [onUnlexable] gets [formula] once.
///
/// [row] and [column] (0-based) are the cell the formula lives in, when it
/// has one; a [PositionedStructuredMapper] gets them with each structured
/// reference. A structured reference behind a sheet or workbook prefix
/// (`[1]!T[A]`) names another workbook's table and is never mapped.
String? rewriteFormula(
  String formula,
  ReferenceMapper mapper,
  String hostSheet, {
  void Function(String formula)? onUnlexable,
  int? row,
  int? column,
}) {
  final List<XlsxFormulaToken> tokens = lexFormula(formula);
  if (_hasInvalid(tokens)) {
    onUnlexable?.call(formula);
    return null;
  }
  final StringBuffer out = StringBuffer();
  bool changed = false;
  for (int i = 0; i < tokens.length; i++) {
    final XlsxFormulaToken t = tokens[i];
    if (t.kind == XlsxFormulaTokenKind.sheetPrefix) {
      final XlsxFormulaToken? next = i + 1 < tokens.length
          ? tokens[i + 1]
          : null;
      final FormulaReference? ref = next == null
          ? null
          : FormulaReference.parse(t.text, next);
      if (ref != null) {
        final String? text = _mapped(t.text, ref, mapper, hostSheet);
        if (text != null) {
          out.write(text);
          changed = true;
        } else {
          out
            ..write(t.text)
            ..write(next!.text);
        }
        i++;
        continue;
      }
      final String? renamed = _renamedPrefix(t.text, mapper);
      out.write(renamed ?? t.text);
      changed |= renamed != null;
      continue;
    }
    if (t.kind == XlsxFormulaTokenKind.structured) {
      final XlsxFormulaToken? before = i > 0 ? tokens[i - 1] : null;
      if (before != null &&
          before.kind == XlsxFormulaTokenKind.sheetPrefix &&
          before.end == t.start) {
        out.write(t.text);
        continue;
      }
      final int open = t.text.indexOf('[');
      final String table = t.text.substring(0, open);
      final String spec = t.text.substring(open);
      final String? text = mapper is PositionedStructuredMapper
          ? mapper.mapStructuredAt(table, spec, hostSheet, row, column)
          : mapper.mapStructured(table, spec, hostSheet);
      out.write(text ?? t.text);
      changed |= text != null && text != t.text;
      continue;
    }
    final FormulaReference? ref = FormulaReference.parse('', t);
    final String? text = ref == null
        ? null
        : _mapped('', ref, mapper, hostSheet);
    out.write(text ?? t.text);
    changed |= text != null;
  }
  if (!changed) return null;
  final String result = out.toString();
  return result == formula ? null : result;
}

/// Same for a space-separated `sqref` list (validation, rule, selection):
/// each range is mapped, a range that becomes `#REF!` is dropped, as Excel
/// drops it, and an emptied list comes back as `''` (the caller removes
/// the entry). `null` when nothing changed, or when an item is not a
/// reference ([onUnlexable] gets [sqref] once).
String? rewriteSqref(
  String sqref,
  ReferenceMapper mapper,
  String hostSheet, {
  void Function(String sqref)? onUnlexable,
}) {
  final List<String> items = sqref
      .split(' ')
      .where((String s) => s.isNotEmpty)
      .toList();
  final List<String> out = <String>[];
  bool changed = false;
  for (final String item in items) {
    final List<XlsxFormulaToken> tokens = lexFormula(item);
    final FormulaReference? ref = tokens.length == 1
        ? FormulaReference.parse('', tokens.single)
        : null;
    if (ref == null) {
      onUnlexable?.call(sqref);
      return null;
    }
    final FormulaReferenceResult? result = mapper.mapReference(ref, hostSheet);
    if (result == null) {
      out.add(item);
    } else {
      changed = true;
      final FormulaReference? to = result.reference;
      if (to != null) out.add(to.render());
    }
  }
  if (!changed) return null;
  final String result = out.join(' ');
  return result == sqref ? null : result;
}

bool _hasInvalid(List<XlsxFormulaToken> tokens) =>
    tokens.any((XlsxFormulaToken t) => t.kind == XlsxFormulaTokenKind.invalid);

/// The new text of [ref] written behind [prefix], or `null` when neither
/// it nor its sheet's name changes.
String? _mapped(
  String prefix,
  FormulaReference ref,
  ReferenceMapper mapper,
  String hostSheet,
) {
  final FormulaReferenceResult? result = mapper.mapReference(ref, hostSheet);
  if (result == null) {
    final String? renamed = prefix.isEmpty
        ? null
        : _renamedPrefix(prefix, mapper);
    return renamed == null ? null : '$renamed${ref.renderBody()}';
  }
  final FormulaReference? to = result.reference;
  final String kept = prefix.isEmpty
      ? ''
      : (_renamedPrefix(prefix, mapper) ?? prefix);
  if (to == null) return '$kept#REF!';
  final bool samePrefix =
      to.sheet == ref.sheet &&
      to.lastSheet == ref.lastSheet &&
      to.externalIndex == ref.externalIndex;
  return samePrefix ? '$kept${to.renderBody()}' : to.render();
}

/// [prefix] with its sheet names renamed by [mapper], or `null` when none
/// is renamed (or it is external, or cannot be read).
String? _renamedPrefix(String prefix, ReferenceMapper mapper) {
  final FormulaReference? probe = FormulaReference.parse(
    prefix,
    const XlsxFormulaToken(XlsxFormulaTokenKind.cell, 'A1', 0),
  );
  if (probe == null || probe.externalIndex != null) return null;
  final String? first = mapper.mapSheetName(probe.sheet!);
  final String? last = probe.lastSheet == null
      ? null
      : mapper.mapSheetName(probe.lastSheet!);
  if (first == null && last == null) return null;
  return renderSheetPrefix(
    first ?? probe.sheet,
    lastSheet: last ?? probe.lastSheet,
  );
}
