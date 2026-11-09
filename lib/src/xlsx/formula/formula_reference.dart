/// A reference of a formula, parsed from its lexer tokens.
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import '../cell_ref.dart';
import '../limits.dart';
import 'formula_token.dart';

/// The written form of a [FormulaReference].
enum FormulaReferenceForm {
  /// One cell: `A1`.
  cell,

  /// Two cells joined by `:`: `A1:B2`.
  area,

  /// Whole rows: `3:5`.
  rows,

  /// Whole columns: `B:D`.
  columns,
}

/// A cell, area, row range or column range, with its sheet prefix.
///
/// Rows and columns are 1-based, as written. A row range has no columns
/// (`firstColumn` and `lastColumn` are `null`), a column range no rows. A
/// cell has its first and last row, and column, equal.
final class FormulaReference {
  /// A reference of [form] with the given bounds and `$` marks.
  const FormulaReference({
    required this.form,
    this.sheet,
    this.lastSheet,
    this.externalIndex,
    this.firstRow,
    this.lastRow,
    this.firstColumn,
    this.lastColumn,
    this.absFirstRow = false,
    this.absLastRow = false,
    this.absFirstColumn = false,
    this.absLastColumn = false,
  });

  /// How the reference is written.
  final FormulaReferenceForm form;

  /// The sheet of the prefix, or the first sheet of a 3D prefix; `null`
  /// when the reference is unqualified.
  final String? sheet;

  /// The last sheet of a 3D prefix (`Sheet1:Sheet3!`), else `null`.
  final String? lastSheet;

  /// The `n` of an external prefix `[n]`, else `null`.
  final int? externalIndex;

  /// The first row, 1-based; `null` for a column range.
  final int? firstRow;

  /// The last row, 1-based; `null` for a column range.
  final int? lastRow;

  /// The first column, 1-based; `null` for a row range.
  final int? firstColumn;

  /// The last column, 1-based; `null` for a row range.
  final int? lastColumn;

  /// Whether the first row is written with `$`.
  final bool absFirstRow;

  /// Whether the last row is written with `$`.
  final bool absLastRow;

  /// Whether the first column is written with `$`.
  final bool absFirstColumn;

  /// Whether the last column is written with `$`.
  final bool absLastColumn;

  /// The reference of [token] behind the sheet prefix [prefix] (a
  /// `sheetPrefix` token's text, or `''`); `null` when [token] is not a
  /// reference: another kind, an area with a name as one half, or a prefix
  /// that cannot be read.
  static FormulaReference? parse(String prefix, XlsxFormulaToken token) {
    final _Prefix? p = prefix.isEmpty ? const _Prefix() : _Prefix.parse(prefix);
    if (p == null || (p.sheet == null && p.externalIndex != null)) return null;
    final String text = token.text;
    switch (token.kind) {
      case XlsxFormulaTokenKind.cell:
        final _Cell? c = _Cell.parse(text);
        if (c == null) return null;
        return p.reference(FormulaReferenceForm.cell, c, c);
      case XlsxFormulaTokenKind.area:
        final int colon = text.indexOf(':');
        final _Cell? a = _Cell.parse(text.substring(0, colon));
        final _Cell? b = _Cell.parse(text.substring(colon + 1));
        if (a == null || b == null) return null;
        return p.reference(FormulaReferenceForm.area, a, b);
      case XlsxFormulaTokenKind.rowRange:
        final List<String> halves = text.split(':');
        final (int, bool)? a = _part(halves.first, _rowOf);
        final (int, bool)? b = _part(halves.last, _rowOf);
        if (a == null || b == null) return null;
        return p.reference(
          FormulaReferenceForm.rows,
          _Cell(null, false, a.$1, a.$2),
          _Cell(null, false, b.$1, b.$2),
        );
      case XlsxFormulaTokenKind.columnRange:
        final List<String> halves = text.split(':');
        final (int, bool)? a = _part(halves.first, _columnOf);
        final (int, bool)? b = _part(halves.last, _columnOf);
        if (a == null || b == null) return null;
        return p.reference(
          FormulaReferenceForm.columns,
          _Cell(a.$1, a.$2, null, false),
          _Cell(b.$1, b.$2, null, false),
        );
      default:
        return null;
    }
  }

  /// The reference as Excel writes it: the prefix (quoted when the sheet
  /// names need it), then the reference in its [form] with its `$` marks.
  String render() => '${renderPrefix()}${renderBody()}';

  /// The sheet prefix with its `!`, or `''` when unqualified.
  String renderPrefix() =>
      renderSheetPrefix(sheet, lastSheet: lastSheet, external: externalIndex);

  /// The reference without its prefix.
  String renderBody() {
    String col(int c, bool abs) => '${abs ? r'$' : ''}${columnName(c - 1)}';
    String row(int r, bool abs) => '${abs ? r'$' : ''}$r';
    switch (form) {
      case FormulaReferenceForm.cell:
        return '${col(firstColumn!, absFirstColumn)}'
            '${row(firstRow!, absFirstRow)}';
      case FormulaReferenceForm.area:
        return '${col(firstColumn!, absFirstColumn)}'
            '${row(firstRow!, absFirstRow)}:'
            '${col(lastColumn!, absLastColumn)}'
            '${row(lastRow!, absLastRow)}';
      case FormulaReferenceForm.rows:
        return '${row(firstRow!, absFirstRow)}:${row(lastRow!, absLastRow)}';
      case FormulaReferenceForm.columns:
        return '${col(firstColumn!, absFirstColumn)}:'
            '${col(lastColumn!, absLastColumn)}';
    }
  }

  @override
  String toString() => render();
}

/// The sheet prefix of [sheet] (with `!`), `''` when it is `null`; quoted
/// when a name needs it, `''` doubled.
String renderSheetPrefix(String? sheet, {String? lastSheet, int? external}) {
  if (sheet == null) return external == null ? '' : '[$external]!';
  final String names = lastSheet == null ? sheet : '$sheet:$lastSheet';
  final String body = '${external == null ? '' : '[$external]'}$names';
  final bool quote =
      _needsQuotes(sheet) || (lastSheet != null && _needsQuotes(lastSheet));
  return quote ? "'${body.replaceAll("'", "''")}'!" : '$body!';
}

/// The prefix of a sheet prefix token, read; also builds references.
final class _Prefix {
  const _Prefix({this.sheet, this.lastSheet, this.externalIndex});

  final String? sheet;
  final String? lastSheet;
  final int? externalIndex;

  /// `Sheet!`, `'My Sheet'!`, `A:B!`, `[1]Sheet!`, `'[1]A b'!` or `[1]!`.
  static _Prefix? parse(String text) {
    if (!text.endsWith('!')) return null;
    String body = text.substring(0, text.length - 1);
    if (body.startsWith("'")) {
      if (body.length < 2 || !body.endsWith("'")) return null;
      body = body.substring(1, body.length - 1).replaceAll("''", "'");
    }
    int? external;
    if (body.startsWith('[')) {
      final int close = body.indexOf(']');
      if (close < 2) return null;
      external = int.tryParse(body.substring(1, close));
      if (external == null) return null;
      body = body.substring(close + 1);
      if (body.isEmpty) return _Prefix(externalIndex: external);
    }
    if (body.isEmpty) return null;
    final int colon = body.indexOf(':');
    if (colon < 0) return _Prefix(sheet: body, externalIndex: external);
    final String first = body.substring(0, colon);
    final String last = body.substring(colon + 1);
    if (first.isEmpty || last.isEmpty) return null;
    return _Prefix(sheet: first, lastSheet: last, externalIndex: external);
  }

  FormulaReference reference(FormulaReferenceForm form, _Cell a, _Cell b) =>
      FormulaReference(
        form: form,
        sheet: sheet,
        lastSheet: lastSheet,
        externalIndex: externalIndex,
        firstRow: a.row,
        lastRow: b.row,
        firstColumn: a.column,
        lastColumn: b.column,
        absFirstRow: a.absRow,
        absLastRow: b.absRow,
        absFirstColumn: a.absColumn,
        absLastColumn: b.absColumn,
      );
}

final class _Cell {
  const _Cell(this.column, this.absColumn, this.row, this.absRow);

  final int? column;
  final bool absColumn;
  final int? row;
  final bool absRow;

  static final RegExp _pattern = RegExp(
    r'^(\$?)([A-Za-z]{1,3})(\$?)(\d{1,7})$',
  );

  static _Cell? parse(String text) {
    final RegExpMatch? m = _pattern.firstMatch(text);
    if (m == null) return null;
    final int? column = _columnOf(m[2]!);
    final int? row = _rowOf(m[4]!);
    if (column == null || row == null) return null;
    return _Cell(column, m[1]!.isNotEmpty, row, m[3]!.isNotEmpty);
  }
}

(int, bool)? _part(String text, int? Function(String) read) {
  final bool abs = text.startsWith(r'$');
  final int? value = read(abs ? text.substring(1) : text);
  return value == null ? null : (value, abs);
}

int? _rowOf(String digits) {
  if (digits.isEmpty || digits.length > 7) return null;
  final int? row = int.tryParse(digits);
  return row != null && row >= 1 && row <= XlsxLimits.maxRows ? row : null;
}

int? _columnOf(String letters) {
  if (letters.isEmpty || letters.length > 3) return null;
  int column = 0;
  for (final int c in letters.toUpperCase().codeUnits) {
    if (c < 0x41 || c > 0x5A) return null;
    column = column * 26 + c - 0x40;
  }
  return column <= XlsxLimits.maxColumns ? column : null;
}

final RegExp _plainName = RegExp(r'^[A-Za-z_\\\u0080-￿][\w.\\\u0080-￿]*$');
final RegExp _cellLike = RegExp(r'^[A-Za-z]{1,3}\d+$');
final RegExp _r1c1Like = RegExp(r'^(R\d*C?\d*|C\d*)$', caseSensitive: false);

/// Whether Excel quotes [sheet] in a prefix: it holds a character other
/// than a letter, digit, `_`, `.` or `\`, starts with a digit or `.`, or
/// reads as an A1 or R1C1 reference.
bool _needsQuotes(String sheet) =>
    !_plainName.hasMatch(sheet) ||
    _cellLike.hasMatch(sheet) ||
    _r1c1Like.hasMatch(sheet);
