/// Splits an Excel formula into tokens with exact offsets.
///
/// Ported from Quds `packages/quds_office_engine/lib/src/sheet/formula/
/// formula_eval.dart` (`FormulaLexer.tokenize`, the token loop
/// `formula_ast.dart`'s tokens come from) at commit `15c5d29`. Quds skipped
/// whitespace, unquoted strings, folded `;` into `,` and knew no sheet
/// prefixes, errors, arrays or structured references; this lexer keeps every
/// character in some token, so the tokens' texts joined are always the
/// formula, which lets structural edits rewrite a reference in place and
/// leave the rest untouched.
library;

import '../limits.dart';
import 'formula_token.dart';

/// The error literals Excel writes, longest first where one prefixes another.
const List<String> _errors = <String>[
  '#GETTING_DATA',
  '#DIV/0!',
  '#VALUE!',
  '#NAME?',
  '#NULL!',
  '#SPILL!',
  '#CALC!',
  '#FIELD!',
  '#BLOCKED!',
  '#CONNECT!',
  '#BUSY!',
  '#UNKNOWN!',
  '#PYTHON!',
  '#REF!',
  '#NUM!',
  '#N/A',
];

/// Lexes [formula] (without the leading `=`). The tokens' texts joined are
/// always [formula]. Never throws, and runs in time linear in its length.
List<XlsxFormulaToken> lexFormula(String formula) =>
    _FormulaLexer(formula).run();

final class _FormulaLexer {
  _FormulaLexer(this._s);

  final String _s;
  final List<XlsxFormulaToken> _out = <XlsxFormulaToken>[];
  int _i = 0;
  int _arrayDepth = 0;

  int get _n => _s.length;

  int _at(int i) => i < _n ? _s.codeUnitAt(i) : -1;

  void _emit(XlsxFormulaTokenKind kind, int start, int end) {
    _out.add(XlsxFormulaToken(kind, _s.substring(start, end), start));
    _i = end;
  }

  List<XlsxFormulaToken> run() {
    while (_i < _n) {
      _next();
    }
    return _out;
  }

  void _next() {
    final int start = _i;
    final int c = _at(_i);
    if (_isSpace(c)) {
      int j = _i;
      while (_isSpace(_at(j))) {
        j++;
      }
      return _emit(XlsxFormulaTokenKind.whitespace, start, j);
    }
    switch (c) {
      case 0x22: // "
        return _string();
      case 0x27: // '
        return _quotedPrefix();
      case 0x5B: // [
        return _bracket();
      case 0x23: // #
        return _hash();
      case 0x40: // @
        return _emit(XlsxFormulaTokenKind.implicitIntersection, start, _i + 1);
      case 0x28:
        return _emit(XlsxFormulaTokenKind.open, start, _i + 1);
      case 0x29:
        return _emit(XlsxFormulaTokenKind.close, start, _i + 1);
      case 0x7B:
        _arrayDepth++;
        return _emit(XlsxFormulaTokenKind.arrayOpen, start, _i + 1);
      case 0x7D:
        if (_arrayDepth > 0) _arrayDepth--;
        return _emit(XlsxFormulaTokenKind.arrayClose, start, _i + 1);
      case 0x2C:
        return _emit(XlsxFormulaTokenKind.comma, start, _i + 1);
      case 0x3B:
        return _emit(
          _arrayDepth > 0
              ? XlsxFormulaTokenKind.semicolon
              : XlsxFormulaTokenKind.invalid,
          start,
          _i + 1,
        );
      case 0x3C: // <
        final int d = _at(_i + 1);
        return _emit(
          XlsxFormulaTokenKind.operator,
          start,
          _i + (d == 0x3E || d == 0x3D ? 2 : 1),
        );
      case 0x3E: // >
        return _emit(
          XlsxFormulaTokenKind.operator,
          start,
          _i + (_at(_i + 1) == 0x3D ? 2 : 1),
        );
      case 0x2B || 0x2D || 0x2A || 0x2F || 0x5E || 0x26 || 0x3D || 0x25 || 0x3A:
        return _emit(XlsxFormulaTokenKind.operator, start, _i + 1);
    }
    if (_isDigit(c) || (c == 0x2E && _isDigit(_at(_i + 1)))) {
      return _numberOrRows();
    }
    if (_isIdentStart(c)) {
      return _word();
    }
    _emit(XlsxFormulaTokenKind.invalid, start, _i + 1);
  }

  void _string() {
    final int start = _i;
    int j = _i + 1;
    while (j < _n) {
      if (_at(j) == 0x22) {
        if (_at(j + 1) == 0x22) {
          j += 2;
          continue;
        }
        return _emit(XlsxFormulaTokenKind.string, start, j + 1);
      }
      j++;
    }
    _emit(XlsxFormulaTokenKind.invalid, start, _n);
  }

  /// `'...'!`, with `''` escapes; anything else is invalid.
  void _quotedPrefix() {
    final int start = _i;
    int j = _i + 1;
    while (j < _n) {
      if (_at(j) == 0x27) {
        if (_at(j + 1) == 0x27) {
          j += 2;
          continue;
        }
        if (_at(j + 1) == 0x21) {
          return _emit(XlsxFormulaTokenKind.sheetPrefix, start, j + 2);
        }
        return _emit(XlsxFormulaTokenKind.invalid, start, j + 1);
      }
      j++;
    }
    _emit(XlsxFormulaTokenKind.invalid, start, _n);
  }

  /// `[n]Sheet!`, `[n]!` or a structured reference of the enclosing table.
  void _bracket() {
    final int start = _i;
    int j = _i + 1;
    while (_isDigit(_at(j))) {
      j++;
    }
    if (j > _i + 1 && _at(j) == 0x5D) {
      j++;
      if (_at(j) == 0x21) {
        return _emit(XlsxFormulaTokenKind.sheetPrefix, start, j + 1);
      }
      final int end = _unquotedPrefixEnd(j);
      if (end > 0) {
        return _emit(XlsxFormulaTokenKind.sheetPrefix, start, end);
      }
    }
    _structured(start, _i);
  }

  /// Takes the balanced bracket span opening at [open] as one structured
  /// token starting at [start]; `'` escapes the next character.
  void _structured(int start, int open) {
    int depth = 0;
    int j = open;
    while (j < _n) {
      final int c = _at(j);
      if (c == 0x27) {
        j += 2;
        continue;
      }
      if (c == 0x5B) {
        depth++;
      } else if (c == 0x5D) {
        depth--;
        if (depth == 0) {
          return _emit(XlsxFormulaTokenKind.structured, start, j + 1);
        }
      }
      j++;
    }
    _emit(XlsxFormulaTokenKind.invalid, start, _n);
  }

  void _hash() {
    final int start = _i;
    if (_out.isNotEmpty && _out.last.end == start) {
      switch (_out.last.kind) {
        case XlsxFormulaTokenKind.cell ||
            XlsxFormulaTokenKind.area ||
            XlsxFormulaTokenKind.name ||
            XlsxFormulaTokenKind.structured:
          return _emit(XlsxFormulaTokenKind.spill, start, start + 1);
        default:
      }
    }
    for (final String e in _errors) {
      if (_s.length - start >= e.length &&
          _s.substring(start, start + e.length).toUpperCase() == e) {
        return _emit(XlsxFormulaTokenKind.error, start, start + e.length);
      }
    }
    _emit(XlsxFormulaTokenKind.invalid, start, start + 1);
  }

  void _numberOrRows() {
    final int start = _i;
    final int rows = _rowRangeEnd(start);
    if (rows > 0) {
      return _emit(XlsxFormulaTokenKind.rowRange, start, rows);
    }
    int j = start;
    while (_isDigit(_at(j))) {
      j++;
    }
    if (_at(j) == 0x2E) {
      j++;
      while (_isDigit(_at(j))) {
        j++;
      }
    }
    final int e = _at(j);
    if (e == 0x45 || e == 0x65) {
      int k = j + 1;
      if (_at(k) == 0x2B || _at(k) == 0x2D) k++;
      if (_isDigit(_at(k))) {
        while (_isDigit(_at(k))) {
          k++;
        }
        j = k;
      }
    }
    _emit(XlsxFormulaTokenKind.number, start, j);
  }

  /// A name, function, boolean, reference, sheet prefix or structured
  /// reference starting at an identifier character.
  void _word() {
    final int start = _i;
    final int prefix = _unquotedPrefixEnd(start);
    if (prefix > 0) {
      return _emit(XlsxFormulaTokenKind.sheetPrefix, start, prefix);
    }
    final int rows = _rowRangeEnd(start);
    if (rows > 0) {
      return _emit(XlsxFormulaTokenKind.rowRange, start, rows);
    }
    final int end = _wordEnd(start);
    final int after = _at(end);
    if (after == 0x28) {
      return _emit(XlsxFormulaTokenKind.function, start, end);
    }
    if (after == 0x5B) {
      return _structured(start, end);
    }
    final bool isCell = _isCell(start, end);
    if (after == 0x3A) {
      final int second = _wordEnd(end + 1);
      if (_isCell(end + 1, second) && _at(second) != 0x21) {
        return _emit(XlsxFormulaTokenKind.area, start, second);
      }
      if (_isColumn(start, end) &&
          second > end + 1 &&
          _isColumn(end + 1, second) &&
          _at(second) != 0x21 &&
          _at(second) != 0x28) {
        return _emit(XlsxFormulaTokenKind.columnRange, start, second);
      }
    }
    if (isCell) {
      return _emit(XlsxFormulaTokenKind.cell, start, end);
    }
    final String upper = _s.substring(start, end).toUpperCase();
    if (upper == 'TRUE' || upper == 'FALSE') {
      return _emit(XlsxFormulaTokenKind.boolean, start, end);
    }
    _emit(XlsxFormulaTokenKind.name, start, end);
  }

  /// The end of an identifier run starting at [i] (`i` when there is none).
  int _wordEnd(int i) {
    int j = i;
    while (_isIdentPart(_at(j))) {
      j++;
    }
    return j;
  }

  /// The end, past `!`, of `Sheet!` or `Sheet1:Sheet3!` at [i]; 0 if none.
  int _unquotedPrefixEnd(int i) {
    if (!_isIdentStart(_at(i))) return 0;
    final int j = _wordEnd(i);
    // Excel quotes a sheet name that reads as a cell, so `A1:Sheet1!` is
    // the end of an area followed by a prefix, never a 3D prefix.
    if (_at(j) == 0x3A && _isIdentStart(_at(j + 1)) && !_isCell(i, j)) {
      final int k = _wordEnd(j + 1);
      if (_at(k) == 0x21) return k + 1;
    }
    return _at(j) == 0x21 ? j + 1 : 0;
  }

  /// The end of `3:5` or `$3:$5` at [i]; 0 if none.
  int _rowRangeEnd(int i) {
    final int first = _rowEnd(i);
    if (first == 0 || _at(first) != 0x3A) return 0;
    final int second = _rowEnd(first + 1);
    if (second == 0 || _isIdentPart(_at(second))) return 0;
    return second;
  }

  /// The end of `$?[0-9]+` within the row limit at [i]; 0 if none.
  int _rowEnd(int i) {
    int j = i;
    if (_at(j) == 0x24) j++;
    final int digits = j;
    while (_isDigit(_at(j)) && j - digits < 8) {
      j++;
    }
    if (j == digits || _isDigit(_at(j))) return 0;
    final int row = int.parse(_s.substring(digits, j));
    return row >= 1 && row <= XlsxLimits.maxRows ? j : 0;
  }

  /// Whether `[start, end)` is `$?[A-Z]{1,3}` within the column limit.
  bool _isColumn(int start, int end) {
    int j = start;
    if (_at(j) == 0x24) j++;
    return j < end && _columnEnd(j) == end;
  }

  /// The end of up to three letters naming a column within the limit at
  /// [i]; `i` when they do not.
  int _columnEnd(int i) {
    int j = i;
    int column = 0;
    while (j - i < 4 && _isLetter(_at(j))) {
      column = column * 26 + (_at(j) | 0x20) - 0x60;
      j++;
    }
    if (j - i > 3 || column > XlsxLimits.maxColumns) return i;
    return j;
  }

  /// Whether `[start, end)` is `$?[A-Z]{1,3}$?[0-9]{1,7}` within limits.
  bool _isCell(int start, int end) {
    int j = start;
    if (_at(j) == 0x24) j++;
    final int letters = _columnEnd(j);
    if (letters == j) return false;
    final int rowEnd = _rowEnd(letters);
    return rowEnd == end;
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isLetter(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  static bool _isIdentStart(int c) =>
      _isLetter(c) || c == 0x5F || c == 0x5C || c == 0x24 || c >= 0x80;

  static bool _isIdentPart(int c) =>
      _isIdentStart(c) || _isDigit(c) || c == 0x2E || c == 0x3F;
}
