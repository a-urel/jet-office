/// The tokens of an Excel formula, as `lexFormula` produces them.
///
/// Ported from Quds `packages/quds_office_engine/lib/src/sheet/formula/
/// formula_ast.dart` (`FormulaTokenKind`, `FormulaToken`) at commit
/// `15c5d29`, widened to every token an en-US formula of a file holds and
/// reduced to exact text and offsets: a token keeps its text verbatim, so
/// the tokens of a formula joined give the formula back.
library;

/// What an [XlsxFormulaToken] is.
enum XlsxFormulaTokenKind {
  /// A number literal: `1`, `1.5`, `.5`, `1.5E+3`.
  number,

  /// A string literal with its quotes, `""` escapes kept: `"a""b"`.
  string,

  /// `TRUE` or `FALSE` not followed by `(`.
  boolean,

  /// An error literal: `#REF!`, `#N/A`, `#SPILL!`, `#GETTING_DATA` and the
  /// others Excel writes.
  error,

  /// A cell reference within Excel's limits, with `$` marks: `$A$1`.
  cell,

  /// Two cell references joined by `:`, one token: `A1:$B$2`.
  area,

  /// A range of whole rows: `3:5`, `$3:$5`.
  rowRange,

  /// A range of whole columns: `B:D`, `$B:$D`.
  columnRange,

  /// A sheet prefix with its `!`: `Sheet1!`, `'My Sheet'!`,
  /// `Sheet1:Sheet3!`, `[1]Sheet1!`, `[1]!`.
  sheetPrefix,

  /// A structured reference, the whole bracket span:
  /// `Table[[#This Row],[Qty]]`, or `[@Qty]` inside a table's own formula.
  structured,

  /// A defined name, a table name alone or a `LAMBDA` parameter.
  name,

  /// A function's name without its `(`: `SUM`, `_xlfn._xlws.FILTER`.
  function,

  /// `(`.
  parenOpen,

  /// `)`.
  parenClose,

  /// `{`, which opens an array constant.
  arrayOpen,

  /// `}`, which closes an array constant.
  arrayClose,

  /// `,`.
  comma,

  /// `;` inside an array constant, which ends a row.
  semicolon,

  /// An operator: `+ - * / ^ & = <> <= >= < > % :`. The intersection
  /// operator, a space, is [whitespace].
  operator,

  /// The `#` right after a reference or a name: `A2#`.
  spill,

  /// A leading `@`.
  implicitIntersection,

  /// Spaces, tabs, carriage returns and line feeds, kept verbatim.
  whitespace,

  /// Text that cannot be lexed: an unterminated string, quoted sheet name or
  /// bracket span takes the rest of the formula; a stray character, or `;`
  /// outside an array, is a token of its own.
  invalid,
}

/// One token of a formula: its kind, its text verbatim and where it starts.
final class XlsxFormulaToken {
  /// A token of [kind] whose [text] starts at [start] in the formula.
  const XlsxFormulaToken(this.kind, this.text, this.start);

  /// What the token is.
  final XlsxFormulaTokenKind kind;

  /// The token's text exactly as the formula holds it; never empty.
  final String text;

  /// The offset of the token in the formula text, in UTF-16 code units.
  final int start;

  /// The offset just past the token.
  int get end => start + text.length;

  @override
  String toString() => '${kind.name}($text @$start)';
}
