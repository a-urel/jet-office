/// A formula moved by an offset, as Excel translates a shared formula's text
/// from its master to each follower: relative rows and columns move, `$`
/// ones stay.
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import '../limits.dart';
import 'formula_reference.dart';
import 'formula_rewrite.dart';

/// The mapper that moves every reference's relative rows by [rows] and
/// relative columns by [columns]. A part moved off the sheet makes the
/// reference `#REF!`, as Excel writes it. Every reference moves, whatever its
/// sheet (a translation is a copy, not a structural edit).
final class FormulaTranslation implements ReferenceMapper {
  /// A translation by [rows] and [columns], either of which may be negative.
  const FormulaTranslation(this.rows, this.columns);

  /// The rows relative references move by.
  final int rows;

  /// The columns relative references move by.
  final int columns;

  static int? _moved(int? value, bool absolute, int by, int limit) {
    if (value == null || absolute) return value;
    final int moved = value + by;
    return moved < 1 || moved > limit ? -1 : moved;
  }

  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String hostSheet) {
    if (rows == 0 && columns == 0) return null;
    final int? firstRow = _moved(
      ref.firstRow,
      ref.absFirstRow,
      rows,
      XlsxLimits.maxRows,
    );
    final int? lastRow = _moved(
      ref.lastRow,
      ref.absLastRow,
      rows,
      XlsxLimits.maxRows,
    );
    final int? firstColumn = _moved(
      ref.firstColumn,
      ref.absFirstColumn,
      columns,
      XlsxLimits.maxColumns,
    );
    final int? lastColumn = _moved(
      ref.lastColumn,
      ref.absLastColumn,
      columns,
      XlsxLimits.maxColumns,
    );
    if (firstRow == -1 ||
        lastRow == -1 ||
        firstColumn == -1 ||
        lastColumn == -1) {
      return const FormulaReferenceResult.refError();
    }
    if (firstRow == ref.firstRow &&
        lastRow == ref.lastRow &&
        firstColumn == ref.firstColumn &&
        lastColumn == ref.lastColumn) {
      return null;
    }
    return FormulaReferenceResult.to(
      FormulaReference(
        form: ref.form,
        sheet: ref.sheet,
        lastSheet: ref.lastSheet,
        externalIndex: ref.externalIndex,
        firstRow: firstRow,
        lastRow: lastRow,
        firstColumn: firstColumn,
        lastColumn: lastColumn,
        absFirstRow: ref.absFirstRow,
        absLastRow: ref.absLastRow,
        absFirstColumn: ref.absFirstColumn,
        absLastColumn: ref.absLastColumn,
      ),
    );
  }

  @override
  String? mapSheetName(String sheet) => null;

  @override
  String? mapStructured(String table, String spec, String hostSheet) => null;
}

/// [formula] moved by [rows] and [columns] (see [FormulaTranslation]), or
/// `null` when the lexer cannot read it fully.
String? translateFormula(
  String formula,
  int rows,
  int columns,
  String hostSheet,
) {
  bool unlexable = false;
  final String? moved = rewriteFormula(
    formula,
    FormulaTranslation(rows, columns),
    hostSheet,
    onUnlexable: (_) => unlexable = true,
  );
  return unlexable ? null : (moved ?? formula);
}
