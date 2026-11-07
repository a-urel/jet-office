/// The one place a cell value becomes SpreadsheetML (decision 0002).
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: the cell branch of `_sheetXml`. Changed: Quds wrote a `DateTime`
/// as its `toString()` text and `NaN` and infinity verbatim; both are fixed
/// here (dates become serials, non-finite numbers throw). Added: strings go
/// through the shared-string table after scrubbing and truncation to Excel's
/// limit, decimals, date-only values, formulas, hyperlinks and rich text,
/// and warnings for lossy conversions.
///
/// Both the streaming writer and the workbook model call [CellEncoder]; no
/// other file under `lib/` writes a cell element. The writer calls
/// [CellEncoder.encode]; the model calls [CellEncoder.prepare] to turn a
/// value into the stored form it keeps (a `RawCell`) and
/// [CellEncoder.writeRaw] to write a stored cell back. Added for the model:
/// `prepare`, `writeRaw` and 1904 date serials; `encode` is unchanged, and
/// both paths share the checks, repairs and warnings.
library;

import 'package:jet_core/jet_core.dart' show FormatKind;

import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'color.dart';
import 'date_serial.dart';
import 'font.dart';
import 'formula_text.dart';
import 'hyperlink.dart';
import 'limits.dart';
import 'number_format.dart';
import 'raw_cell.dart';
import 'read/cell_decoder.dart' show encodeFormulaType, encodeRawKind;
import 'read/styles_reader.dart' show CellFormat;
import 'rich_text.dart';
import 'shared_strings.dart';
import 'style.dart';
import 'style_registry.dart';
import 'values.dart';
import 'warnings.dart';

/// The largest whole number a `double` holds exactly (2^53).
const int _maxExactInt = 9007199254740992;

/// The font of a hyperlink cell: the theme's hyperlink color, underlined.
/// The lowest font layer: whatever a column, row or cell font sets wins.
const XlsxFont _hyperlinkFont = XlsxFont(
  color: XlsxColor.theme(10),
  underline: XlsxUnderline.single,
);

/// [style] with the hyperlink font beneath its font: the theme's hyperlink
/// color, underlined, unless [style] sets a font field.
///
/// What the writer gives a hyperlink cell, and the workbook model gives one
/// it sets.
XlsxStyle withHyperlinkFont(XlsxStyle? style) => (style ?? const XlsxStyle())
    .copyWith(font: _hyperlinkFont.merge(style?.font));

/// `intPrecisionLost` when Excel, which stores every number as a double,
/// may round [v]; otherwise `null`.
///
/// Not `v.abs()`: the absolute value of the 64-bit minimum overflows to
/// itself, a negative number.
XlsxWarningCode? _intWarning(int v) => v > _maxExactInt || v < -_maxExactInt
    ? XlsxWarningCode.intPrecisionLost
    : null;

/// The `<v>` text of [v].
String _boolText(bool v) => v ? '1' : '0';

/// Encodes cell values as `<c>` elements.
///
/// One encoder serves one workbook: it shares the workbook's string table,
/// style registry and warning collector across all sheets.
final class CellEncoder {
  /// Creates an encoder that interns strings in [strings], assigns style ids
  /// through [styles] and reports data problems to [warnings].
  CellEncoder({
    required SharedStrings strings,
    required StyleRegistry styles,
    required WarningCollector warnings,
  }) : _strings = strings,
       _styles = styles,
       _warnings = warnings;

  final SharedStrings _strings;
  final StyleRegistry _styles;
  final WarningCollector _warnings;
  bool _wroteFormula = false;

  /// The `beforeWrite` callback of the [encode] call in progress.
  void Function()? _beforeWrite;

  // The resolved layers of the last cell of each column. Layers are
  // immutable, so a cell in that column with the same three layer objects
  // (compared by identity, which costs no hashing, and bounded by the number
  // of columns, unlike a map keyed on freshly allocated styles) reuses the
  // merged style and its cell format id. Keyed by column because the cells
  // of one row usually differ in column style while a column's cells repeat.
  final List<_Resolved?> _byColumn = <_Resolved?>[];
  int _resolveCount = 0;

  /// How many times the style layers of a cell were merged and resolved
  /// afresh instead of coming from the cache. A diagnostic for tests: it
  /// shows that a sheet of many rows costs one resolution per column.
  int get resolveCount => _resolveCount;

  /// Whether the encoder still holds a `beforeWrite` callback. A diagnostic
  /// for tests: it is `false` whenever no [encode] call is in progress, so
  /// a callback, and the row state it captures, is never kept alive.
  bool get holdsBeforeWrite => _beforeWrite != null;

  /// Whether any formula cell has been written, so the workbook can ask
  /// Excel to recalculate on load.
  bool get wroteFormula => _wroteFormula;

  /// Writes the cell at zero-based [row] and [column] of [sheet] to [out].
  ///
  /// [value] is a `String`, `int`, `double`, `bool`, [DateTime], [XlsxDate],
  /// [XlsxDecimal], [XlsxFormula], [XlsxHyperlink], [XlsxRichText], an
  /// [XlsxCell] wrapping one of those, or `null`, which writes nothing. An
  /// [XlsxCell] whose value is `null` and whose style is not writes an empty
  /// styled cell, `<c r="C5" s="7"/>`, when the merged style below is not
  /// the default; with the default style, or with no cell style, it writes
  /// nothing (ruling R11).
  ///
  /// The effective style is [columnStyle] merged with [rowStyle] and then
  /// with the [XlsxCell]'s style, so a cell beats its row and a row beats
  /// its column (see [XlsxStyle.merge]): a field a higher layer leaves
  /// `null` is inherited, one it sets, even back to its default (a font
  /// that is not bold, `XlsxNumFmt.general`), wins.
  ///
  /// A hyperlink is written as its text, a string, with the hyperlink font
  /// merged beneath the effective style's font; the sheet writer records
  /// the link itself (and validates it, which the encoder does not).
  ///
  /// A rich text is a shared string whose `<si>` holds its runs. A run with
  /// a font carries that font merged over the effective style's font and
  /// resolved (Calibri 11 where neither sets a name or size), so a bold run
  /// in an Arial 14 cell is Arial 14 bold. A run without a font carries the
  /// effective style's font, resolved, when that style has a font, since
  /// Excel draws a run without one in the workbook's default font, not the
  /// cell's; in a cell whose style has no font it carries none. The same
  /// rich text in cells of different fonts is therefore two shared strings.
  /// A run left with no text is dropped. A rich text left with one run
  /// without a font shares the `<si>` of that plain string, and one left
  /// with no runs that of the empty string.
  ///
  /// Data problems (characters XML forbids, text past 32,767 UTF-16 code
  /// units, integers past 2^53, dates outside 1900 to 9999, a date shown in
  /// a non-date format) are repaired and reported to the warning collector.
  /// Rich text is cleaned with [cleanRichText] and warns once per cell for
  /// each kind of repair.
  /// On the web a whole `double` beyond 2^53 is indistinguishable from an
  /// `int`, so it also warns `intPrecisionLost`. An [XlsxDecimal] beyond the
  /// `double` range is written verbatim, and Excel rounds it.
  /// A date gets the date-time or short-date format only when the merged
  /// number format is `null`; in any other format it keeps that format, and
  /// warns when that format shows no date.
  /// A formula's cached string or integer is treated like a plain one.
  /// Programmer errors throw an [ArgumentError]: an unsupported type, a
  /// nested [XlsxCell], a `NaN` or infinite number, an impossible date, a
  /// formula that is empty after its leading `=`, longer than 8,192 UTF-16
  /// code units or holds characters XML forbids (the checks of
  /// `checkFormulaText`, named `text`, with the cell in the message), an
  /// invalid cached value, a rich text without runs (named `runs`), a run
  /// font that is invalid once merged over the cell's font (named
  /// `runs[i].font.<field>`, the checks of `validateFont`).
  /// An invalid style throws like [StyleRegistry.idFor]. When it throws,
  /// nothing is written to [out] and nothing is recorded: the string table,
  /// the style registry and the warnings are as they were.
  ///
  /// [beforeWrite], when given, is called once right before the cell
  /// element is written, after everything that can throw, and not at all
  /// when nothing is written. The sheet writer opens the row's element in
  /// it, so a row whose cells all write nothing gets no element.
  void encode(
    XmlWriter out, {
    required String sheet,
    required int row,
    required int column,
    required Object? value,
    XlsxStyle? rowStyle,
    XlsxStyle? columnStyle,
    void Function()? beforeWrite,
  }) {
    _beforeWrite = beforeWrite;
    try {
      _encode(out, sheet, row, column, value, rowStyle, columnStyle);
    } finally {
      // Not kept past the call: it captures the sheet's row state.
      _beforeWrite = null;
    }
  }

  /// The body of [encode], which holds [_beforeWrite] while this runs.
  void _encode(
    XmlWriter out,
    String sheet,
    int row,
    int column,
    Object? value,
    XlsxStyle? rowStyle,
    XlsxStyle? columnStyle,
  ) {
    final String ref = cellRef(row, column);
    XlsxStyle? cellStyle;
    Object? v = value;
    if (v is XlsxCell) {
      cellStyle = v.style;
      v = v.value;
      if (v is XlsxCell) {
        throw ArgumentError(
          'Cell $ref on sheet "$sheet" nests an XlsxCell '
          'inside an XlsxCell.',
        );
      }
    }
    if (v == null) {
      if (cellStyle == null) return;
      final int id = _idOf(_resolve(column, columnStyle, rowStyle, cellStyle));
      if (id != 0) _write(out, ref, id, null, null);
      return;
    }
    final _Resolved style = _resolve(column, columnStyle, rowStyle, cellStyle);
    switch (v) {
      case String():
        _writeString(out, sheet, ref, v, style);
      case num() when !v.isFinite:
        // Before the int case: on the web NaN and infinity also satisfy
        // `is int`.
        throw _nonFinite(v, sheet, ref);
      case bool():
        _write(out, ref, _idOf(style), 'b', '<v>${_boolText(v)}</v>');
      case int():
        final int id = _idOf(style);
        _report(_intWarning(v), sheet, ref);
        _write(out, ref, id, null, '<v>${_intText(v)}</v>');
      case double():
        _write(out, ref, _idOf(style), null, '<v>${formatXmlDouble(v)}</v>');
      case XlsxDecimal():
        _write(out, ref, _idOf(style), null, '<v>${v.digits}</v>');
      case DateTime():
        final String? serial = _dateTimeSerialText(v, date1904: false);
        if (serial == null) {
          _writeString(
            out,
            sheet,
            ref,
            v.toIso8601String(),
            style,
            outsideDateRange: true,
          );
        } else {
          _writeDate(out, sheet, ref, serial, style, XlsxNumFmt.localeDateTime);
        }
      case XlsxDate():
        final int? serial = _dateSerialOf(v, sheet, ref, date1904: false);
        if (serial == null) {
          _writeString(
            out,
            sheet,
            ref,
            _isoDate(v),
            style,
            outsideDateRange: true,
          );
        } else {
          _writeDate(
            out,
            sheet,
            ref,
            '$serial',
            style,
            XlsxNumFmt.localeShortDate,
          );
        }
      case XlsxFormula():
        _writeFormula(out, sheet, ref, v, style);
      case XlsxHyperlink():
        _writeString(out, sheet, ref, v.text, style.linked);
      case XlsxRichText():
        _writeRichText(out, sheet, ref, v, style);
      default:
        throw _unsupported(v, sheet, ref);
    }
  }

  /// The stored form of [value] for the cell at zero-based [row] and
  /// [column] of [sheet], for the workbook model, which keeps it in place of
  /// [current] (`null` when the cell does not exist yet).
  ///
  /// [value] is a `String`, `int`, `double`, `bool`, [DateTime],
  /// [XlsxDate], [XlsxDecimal], [XlsxFormula], [XlsxRichText] or `null`. The
  /// checks, repairs and warnings are those of [encode], and it throws as
  /// [encode] does, with nothing recorded: the string table and the warnings
  /// are as they were. A string is interned into the shared-string table and
  /// stored as its index. A formula is stored as a normal formula with its
  /// text as written (one leading `=` removed) and its cached result as the
  /// `<v>` text [encode] writes. `null` gives an empty cell carrying
  /// [current]'s style; whether the store keeps it is the caller's rule.
  ///
  /// The result keeps [current]'s style, except for a date: the date rule
  /// of [encode] applied to [currentFormat], the format of [current]'s
  /// style. A format that shows a date or a time keeps the style; General
  /// (id 0) takes the style [dateStyle] returns for [current]'s style,
  /// with `withTime` true for a [DateTime] (the writer gives every
  /// [DateTime] its date-time format and an [XlsxDate] its short-date one);
  /// any other format keeps the style and warns `dateInNonDateFormat`, and
  /// so does General when [dateStyle] returns `null` (no date style can be
  /// added). Dates are serials of the 1904 system when [date1904] is true,
  /// and a date that has no serial there (before 1904-01-01) is written as
  /// text with `dateOutsideExcelRange`, like one before 1900.
  ///
  /// An [XlsxRichText] is stored as a shared string whose runs have [cellFont]
  /// (the font of the cell's style, or `null`) merged under their fonts, and
  /// a run without a font given it, as [encode] does; the cell is checked
  /// before anything is recorded, so a rich text without runs throws
  /// [ArgumentError] with the table unchanged. An [XlsxHyperlink], an
  /// [XlsxCell] or any other type throws [ArgumentError]; the model unwraps
  /// them itself.
  RawCell prepare(
    Object? value, {
    required String sheet,
    required int row,
    required int column,
    required RawCell? current,
    required CellFormat currentFormat,
    required bool date1904,
    required int? Function(int? style, {required bool withTime}) dateStyle,
    XlsxFont? cellFont,
  }) {
    final String ref = cellRef(row, column);
    final int? style = current?.style;
    switch (value) {
      case null:
        return RawCell(kind: RawCellKind.number, style: style);
      case XlsxRichText():
        return _preparedRichText(sheet, ref, value, style, cellFont);
      case String():
        return _preparedString(sheet, ref, value, style);
      case num() when !value.isFinite:
        // Before the int case: on the web NaN and infinity also satisfy
        // `is int`.
        throw _nonFinite(value, sheet, ref);
      case bool():
        return RawCell(
          kind: RawCellKind.boolean,
          style: style,
          value: _boolText(value),
        );
      case int():
        _report(_intWarning(value), sheet, ref);
        return RawCell(
          kind: RawCellKind.number,
          style: style,
          value: _intText(value),
        );
      case double():
        return RawCell(
          kind: RawCellKind.number,
          style: style,
          value: formatXmlDouble(value),
        );
      case XlsxDecimal():
        return RawCell(
          kind: RawCellKind.number,
          style: style,
          value: value.digits,
        );
      case DateTime():
        final String? serial = _dateTimeSerialText(value, date1904: date1904);
        if (serial == null) {
          return _preparedString(
            sheet,
            ref,
            value.toIso8601String(),
            style,
            outsideDateRange: true,
          );
        }
        return _preparedDate(
          sheet,
          ref,
          serial,
          style,
          currentFormat,
          () => dateStyle(style, withTime: true),
        );
      case XlsxDate():
        final int? serial = _dateSerialOf(
          value,
          sheet,
          ref,
          date1904: date1904,
        );
        if (serial == null) {
          return _preparedString(
            sheet,
            ref,
            _isoDate(value),
            style,
            outsideDateRange: true,
          );
        }
        return _preparedDate(
          sheet,
          ref,
          '$serial',
          style,
          currentFormat,
          () => dateStyle(style, withTime: false),
        );
      case XlsxFormula():
        final _CheckedFormula checked = _checkFormula(value, sheet, ref);
        _report(checked.warning, sheet, ref);
        return RawCell(
          kind: checked.kind,
          style: style,
          value: checked.value,
          formula: RawFormula(type: FormulaType.normal, text: checked.text),
        );
      default:
        throw _unsupported(value, sheet, ref);
    }
  }

  /// [text] as a stored shared-string cell with [style], repaired and
  /// reported as [_writeString] does.
  RawCell _preparedString(
    String sheet,
    String ref,
    String text,
    int? style, {
    bool outsideDateRange = false,
  }) {
    final _CleanText clean = _cleanText(text);
    _reportText(sheet, ref, clean, outsideDateRange: outsideDateRange);
    return RawCell(
      kind: RawCellKind.sharedString,
      style: style,
      value: '${_strings.indexOf(clean.text)}',
    );
  }

  /// The date [serial] as a stored number cell, styled by the date rule:
  /// [style] kept when [format] shows a date or a time, [dateStyle]'s style
  /// when [format] is General and it gives one, and otherwise [style] kept
  /// with a warning.
  RawCell _preparedDate(
    String sheet,
    String ref,
    String serial,
    int? style,
    CellFormat format,
    int? Function() dateStyle,
  ) {
    final int? id;
    final int? general = format.id == 0 ? dateStyle() : null;
    if (format.kind == FormatKind.date || format.kind == FormatKind.time) {
      id = style;
    } else if (general != null) {
      id = general;
    } else {
      _warnings.add(
        XlsxWarningCode.dateInNonDateFormat,
        sheet: sheet,
        cell: ref,
      );
      id = style;
    }
    return RawCell(kind: RawCellKind.number, style: id, value: serial);
  }

  /// Writes the stored [cell] at zero-based [row] and [column] to [out], for
  /// the workbook model.
  ///
  /// The `<c>` carries `r`, the style as `s` (whenever there is one, `0`
  /// included, as the file wrote it), the kind's `t` and the kept
  /// attributes, in that order. Its children follow the schema's order: the
  /// `<f>` with its type, `ref`, `si` and kept attributes, the `<v>`, the
  /// inline `<is>` and the other kept children. [declaredAbove] holds the
  /// namespace bindings in scope at the cell (the worksheet root's); a kept
  /// attribute or element whose prefix it lacks declares it (see
  /// `writeKeptAttributes`).
  ///
  /// The formula text is escaped as [encode] escapes it (ST_Xstring, then
  /// XML); the `<v>` text and attribute values are escaped as XML only. A
  /// character XML forbids in them, which only a character reference in the
  /// source (`&#1;`) can have put there, is dropped without a warning:
  /// writing has no sheet to report it against, and dropping it is what
  /// keeps the saved part well-formed. An empty cell with a style or kept
  /// attributes writes `<c r="C5" s="7"/>`; an empty cell with neither
  /// writes nothing.
  void writeRaw(
    XmlWriter out, {
    required int row,
    required int column,
    required RawCell cell,
    Map<String, String> declaredAbove = const <String, String>{},
  }) {
    final int? style = cell.style;
    if (cell.isEmpty && style == null && cell.attributes.isEmpty) return;
    out
      ..start('c')
      ..attribute('r', cellRef(row, column));
    if (style != null) out.attribute('s', '$style');
    final String? type = encodeRawKind(cell);
    if (type != null) out.attribute('t', _clean(type));
    writeKeptAttributes(out, cell.attributes, declaredAbove: declaredAbove);
    if (cell.isEmpty) {
      out.end();
      return;
    }
    // The bindings inside the <c>, with those its kept attributes declared.
    final Map<String, String> inside = _withKept(
      declaredAbove,
      cell.attributes,
    );
    final RawFormula? formula = cell.formula;
    if (formula != null) {
      out.start('f');
      final String? formulaType = encodeFormulaType(formula.type);
      if (formulaType != null) out.attribute('t', formulaType);
      final String? range = formula.ref;
      if (range != null) out.attribute('ref', _clean(range));
      final String? si = formula.si;
      if (si != null) out.attribute('si', _clean(si));
      writeKeptAttributes(out, formula.attributes, declaredAbove: inside);
      final String? text = formula.text;
      if (text != null && text.isNotEmpty) {
        out.text(escapeXstring(_clean(text)));
      }
      out.end();
      _wroteFormula = true;
    }
    final String? value = cell.value;
    if (value != null) {
      out
        ..start('v')
        ..text(_clean(value))
        ..end();
    }
    cell.inline?.writeTo(out, declaredAbove: inside);
    for (final OpaqueXml child in cell.extraChildren) {
      child.writeTo(out, declaredAbove: inside);
    }
    out.end();
  }

  /// [declaredAbove] with the bindings of the prefixed [attributes] added,
  /// as `writeKeptAttributes` declares them; [declaredAbove] itself when
  /// none is new.
  static Map<String, String> _withKept(
    Map<String, String> declaredAbove,
    List<KeptAttribute> attributes,
  ) {
    Map<String, String>? merged;
    for (final KeptAttribute a in attributes) {
      final int colon = a.qualifiedName.indexOf(':');
      if (colon <= 0) continue;
      final String prefix = a.qualifiedName.substring(0, colon);
      if (prefix == 'xml' || declaredAbove[prefix] == a.namespaceUri) continue;
      (merged ??= <String, String>{...declaredAbove})[prefix] = a.namespaceUri;
    }
    return merged ?? declaredAbove;
  }

  /// [text] without the characters XML forbids.
  static String _clean(String text) => scrubXmlText(text).text;

  /// Writes [text] as a shared-string cell. With [outsideDateRange], the
  /// text stands for a date Excel cannot store, which is reported too.
  void _writeString(
    XmlWriter out,
    String sheet,
    String ref,
    String text,
    _Resolved style, {
    bool outsideDateRange = false,
  }) {
    final _CleanText clean = _cleanText(text);
    // The style can throw; resolve it before anything is recorded.
    final int id = _idOf(style);
    _reportText(sheet, ref, clean, outsideDateRange: outsideDateRange);
    _write(out, ref, id, 's', '<v>${_strings.indexOf(clean.text)}</v>');
  }

  /// [text] scrubbed of the characters XML forbids and cut to Excel's cell
  /// limit, with what was repaired. Records nothing.
  static _CleanText _cleanText(String text) {
    final ScrubResult scrubbed = scrubXmlText(text);
    final String result = truncateCellText(scrubbed.text);
    return (
      text: result,
      removed: scrubbed.removed > 0,
      truncated: result.length < scrubbed.text.length,
    );
  }

  /// Reports the repairs of [clean] for the cell [ref], and with
  /// [outsideDateRange] that the text stands for a date Excel cannot store.
  void _reportText(
    String sheet,
    String ref,
    _CleanText clean, {
    required bool outsideDateRange,
  }) {
    if (clean.removed) {
      _warnings.add(
        XlsxWarningCode.invalidCharactersRemoved,
        sheet: sheet,
        cell: ref,
      );
    }
    if (clean.truncated) {
      _warnings.add(XlsxWarningCode.textTruncated, sheet: sheet, cell: ref);
    }
    if (outsideDateRange) {
      _warnings.add(
        XlsxWarningCode.dateOutsideExcelRange,
        sheet: sheet,
        cell: ref,
      );
    }
  }

  /// Writes [text] as a shared-string cell whose `<si>` holds its runs, each
  /// run's font merged over the font of [style] (Decision 3), and each run
  /// without a font given that font.
  void _writeRichText(
    XmlWriter out,
    String sheet,
    String ref,
    XlsxRichText text,
    _Resolved style,
  ) {
    final ({XlsxRichText text, int removed, bool truncated}) clean =
        _cleanedRuns(sheet, ref, text, style.style?.font);
    // The style can throw; resolve it before anything is recorded.
    final int id = _idOf(style);
    _reportRuns(sheet, ref, clean);
    _write(out, ref, id, 's', '<v>${_strings.indexOfRich(clean.text)}</v>');
  }

  /// [text] as a stored shared-string cell with [style], repaired and
  /// reported as [_writeRichText] does, its runs merged over [cellFont].
  RawCell _preparedRichText(
    String sheet,
    String ref,
    XlsxRichText text,
    int? style,
    XlsxFont? cellFont,
  ) {
    final ({XlsxRichText text, int removed, bool truncated}) clean =
        _cleanedRuns(sheet, ref, text, cellFont);
    _reportRuns(sheet, ref, clean);
    return RawCell(
      kind: RawCellKind.sharedString,
      style: style,
      value: '${_strings.indexOfRich(clean.text)}',
    );
  }

  /// [text] with its run fonts merged over [cellFont] and then cleaned (see
  /// [_mergeRunFonts] and [cleanRichText]). Throws [ArgumentError] for a
  /// rich text without runs or a merged font that is invalid.
  static ({XlsxRichText text, int removed, bool truncated}) _cleanedRuns(
    String sheet,
    String ref,
    XlsxRichText text,
    XlsxFont? cellFont,
  ) {
    if (text.runs.isEmpty) {
      throw ArgumentError.value(
        text.runs,
        'runs',
        'The rich text in cell $ref on sheet "$sheet" has no runs.',
      );
    }
    return cleanRichText(_mergeRunFonts(sheet, ref, text, cellFont));
  }

  void _reportRuns(
    String sheet,
    String ref,
    ({XlsxRichText text, int removed, bool truncated}) clean,
  ) {
    if (clean.removed > 0) {
      _warnings.add(
        XlsxWarningCode.invalidCharactersRemoved,
        sheet: sheet,
        cell: ref,
      );
    }
    if (clean.truncated) {
      _warnings.add(XlsxWarningCode.textTruncated, sheet: sheet, cell: ref);
    }
  }

  /// [text] with the font of each run that has one merged over [cellFont],
  /// resolved and checked, and each run without one given [cellFont]
  /// resolved; [text] itself when no run has a font and [cellFont] is
  /// `null`.
  ///
  /// A run without a font needs the cell's font written out: Excel draws a
  /// run without `rPr` in the workbook's default font (Calibri 11), not in
  /// the cell's. [cellFont] itself is checked when the cell's style is
  /// resolved, so only merged fonts are checked here.
  ///
  /// Throws [ArgumentError] named `runs[i].font.<field>` for a merged font
  /// that fails `validateFont`, with the cell in the message.
  static XlsxRichText _mergeRunFonts(
    String sheet,
    String ref,
    XlsxRichText text,
    XlsxFont? cellFont,
  ) {
    if (cellFont == null &&
        text.runs.every((XlsxTextRun run) => run.font == null)) {
      return text;
    }
    final XlsxFont? plainFont = cellFont == null ? null : resolveFont(cellFont);
    final List<XlsxTextRun> runs = <XlsxTextRun>[];
    for (int i = 0; i < text.runs.length; i++) {
      final XlsxTextRun run = text.runs[i];
      final XlsxFont? font = run.font;
      if (font == null) {
        runs.add(
          plainFont == null ? run : XlsxTextRun(run.text, font: plainFont),
        );
        continue;
      }
      final XlsxFont merged = resolveFont(
        cellFont == null ? font : cellFont.merge(font),
      );
      try {
        validateFont(merged);
      } on ArgumentError catch (error, stack) {
        final String? field = error.name;
        Error.throwWithStackTrace(
          ArgumentError.value(
            error.invalidValue,
            field == null ? 'runs[$i].font' : 'runs[$i].font.$field',
            'The font of run $i of the rich text in cell $ref on sheet '
            '"$sheet", merged over the cell\'s font, is invalid: '
            '${error.message}',
          ),
          stack,
        );
      }
      runs.add(XlsxTextRun(run.text, font: merged));
    }
    return XlsxRichText(runs);
  }

  /// [text] cut to [XlsxLimits.maxCellTextLength] UTF-16 code units without
  /// splitting a surrogate pair; [text] itself when it fits.
  static String truncateCellText(String text) {
    if (text.length <= XlsxLimits.maxCellTextLength) return text;
    int cut = XlsxLimits.maxCellTextLength;
    // A high surrogate in the last kept unit would lose its low half.
    final int last = text.codeUnitAt(cut - 1);
    if (last >= 0xD800 && last <= 0xDBFF) cut--;
    return text.substring(0, cut);
  }

  void _writeDate(
    XmlWriter out,
    String sheet,
    String ref,
    String serial,
    _Resolved style,
    XlsxNumFmt defaultFormat,
  ) {
    final XlsxNumFmt? format = style.style?.numFmt;
    // The style can throw; resolve it before the warning is recorded.
    final int id = format == null
        ? _dateIdOf(style, defaultFormat)
        : _idOf(style);
    if (format != null && !isDateFormat(format)) {
      _warnings.add(
        XlsxWarningCode.dateInNonDateFormat,
        sheet: sheet,
        cell: ref,
      );
    }
    _write(out, ref, id, null, '<v>$serial</v>');
  }

  void _writeFormula(
    XmlWriter out,
    String sheet,
    String ref,
    XlsxFormula formula,
    _Resolved style,
  ) {
    final _CheckedFormula checked = _checkFormula(formula, sheet, ref);
    // The style can throw; resolve it before the warning is recorded.
    final int id = _idOf(style);
    _report(checked.warning, sheet, ref);
    final String? cached = checked.value;
    _write(
      out,
      ref,
      id,
      encodeRawKind(RawCell(kind: checked.kind)),
      '<f>${escapeFormulaText(checked.text)}</f>'
      '${cached == null ? '' : '<v>${escapeXmlText(cached)}</v>'}',
    );
    _wroteFormula = true;
  }

  /// Checks [formula], in cell [ref] of [sheet], without recording
  /// anything: its text as written (one leading `=` removed), the kind and
  /// `<v>` text of its cached result (a string escaped against ST_Xstring
  /// decoding and cut to Excel's cell limit), and the warning to report.
  ///
  /// Throws [ArgumentError] for invalid text (the checks of
  /// `checkFormulaText`, told at the cell) or an invalid cached value.
  _CheckedFormula _checkFormula(XlsxFormula formula, String sheet, String ref) {
    final String text;
    try {
      text = checkFormulaText(formula.text, 'text');
    } on ArgumentError catch (error, stack) {
      // The check every formula shares, told at the cell.
      Error.throwWithStackTrace(
        ArgumentError.value(
          error.invalidValue,
          error.name,
          'The formula in cell $ref on sheet "$sheet" is invalid: '
          '${error.message}',
        ),
        stack,
      );
    }
    final Object? cached = formula.cached;
    switch (cached) {
      case null:
        return (
          text: text,
          kind: RawCellKind.number,
          value: null,
          warning: null,
        );
      case String():
        if (scrubXmlText(cached).removed > 0) {
          throw ArgumentError(
            'The cached result of the formula in cell $ref on sheet '
            '"$sheet" contains characters XML forbids.',
          );
        }
        final String kept = truncateCellText(cached);
        return (
          text: text,
          kind: RawCellKind.string,
          value: escapeXstring(kept),
          warning: kept.length < cached.length
              ? XlsxWarningCode.textTruncated
              : null,
        );
      case bool():
        return (
          text: text,
          kind: RawCellKind.boolean,
          value: _boolText(cached),
          warning: null,
        );
      case num() when !cached.isFinite:
        throw _nonFinite(cached, sheet, ref);
      case num():
        return (
          text: text,
          kind: RawCellKind.number,
          value: switch (cached) {
            int() => _intText(cached),
            _ => formatXmlDouble(cached.toDouble()),
          },
          warning: cached is int ? _intWarning(cached) : null,
        );
      default:
        throw ArgumentError(
          'The cached result of the formula in cell $ref on sheet "$sheet" '
          'is a ${cached.runtimeType}; expected null, num, String or bool.',
        );
    }
  }

  /// The layers merged, cell over row over column, reusing the result last
  /// computed for column [index] when the three layer objects are the same.
  _Resolved _resolve(
    int index,
    XlsxStyle? column,
    XlsxStyle? row,
    XlsxStyle? cell,
  ) {
    while (_byColumn.length <= index) {
      _byColumn.add(null);
    }
    final _Resolved? last = _byColumn[index];
    if (last != null &&
        identical(last.column, column) &&
        identical(last.row, row) &&
        identical(last.cell, cell)) {
      return last;
    }
    _resolveCount++;
    XlsxStyle? merged = column;
    for (final XlsxStyle? layer in <XlsxStyle?>[row, cell]) {
      if (layer != null) merged = merged == null ? layer : merged.merge(layer);
    }
    return _byColumn[index] = _Resolved(column, row, cell, merged);
  }

  /// The cell format id of [r], registered on first use. A throw leaves
  /// nothing cached, so the next call throws again.
  int _idOf(_Resolved r) => r.id ??= _styles.idFor(r.style);

  /// The id of [r] with [format] as its number format, for a date whose
  /// merged style has none.
  int _dateIdOf(_Resolved r, XlsxNumFmt format) => r.dateIds[format] ??= _styles
      .idFor((r.style ?? const XlsxStyle()).copyWith(numFmt: format));

  /// Reports [warning] for the cell [ref] of [sheet], when there is one.
  void _report(XlsxWarningCode? warning, String sheet, String ref) {
    if (warning != null) _warnings.add(warning, sheet: sheet, cell: ref);
  }

  /// The `<v>` text of [v]. On the web a whole double is an `int` too, so
  /// `-0.0` arrives here and is written `0`.
  static String _intText(int v) => '${v == 0 ? 0 : v}';

  /// The serial of [v] as `<v>` text, whole days without a fraction, or
  /// `null` outside Excel's range.
  static String? _dateTimeSerialText(DateTime v, {required bool date1904}) {
    final double? serial = dateTimeSerial(v, date1904: date1904);
    if (serial == null) return null;
    return serial == serial.truncateToDouble()
        ? '${serial.toInt()}'
        : '$serial';
  }

  /// The serial of [v], or `null` outside Excel's range. Throws
  /// [ArgumentError] naming the cell when the date does not exist.
  static int? _dateSerialOf(
    XlsxDate v,
    String sheet,
    String ref, {
    required bool date1904,
  }) {
    try {
      return dateSerial(v.year, v.month, v.day, date1904: date1904);
    } on ArgumentError {
      throw ArgumentError(
        'Cell $ref on sheet "$sheet" holds the date '
        '${v.year}-${v.month}-${v.day}, which does not exist.',
      );
    }
  }

  ArgumentError _unsupported(Object v, String sheet, String ref) =>
      ArgumentError(
        'Cell $ref on sheet "$sheet" holds a ${v.runtimeType}, which is not '
        'a supported cell value.',
      );

  ArgumentError _nonFinite(num value, String sheet, String ref) =>
      ArgumentError(
        'Cell $ref on sheet "$sheet" holds $value; Excel cannot store NaN or '
        'infinity.',
      );

  /// Writes the cell element with the style id [id], resolved by the caller
  /// before it recorded anything, after calling the `beforeWrite` callback.
  /// A `null` [body] writes an empty cell.
  void _write(XmlWriter out, String ref, int id, String? type, String? body) {
    _beforeWrite?.call();
    final StringBuffer cell = StringBuffer('<c r="$ref"');
    if (id != 0) cell.write(' s="$id"');
    if (type != null) cell.write(' t="$type"');
    if (body == null) {
      cell.write('/>');
    } else {
      cell
        ..write('>')
        ..write(body)
        ..write('</c>');
    }
    out.raw(cell.toString());
  }

  String _isoDate(XlsxDate date) {
    final String year = date.year.abs().toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year < 0 ? '-' : ''}$year-$month-$day';
  }
}

/// The three style layers of a cell with their merged result and the cell
/// format ids already assigned to it.
final class _Resolved {
  _Resolved(this.column, this.row, this.cell, this.style);

  /// This style with the hyperlink font beneath its font, resolved and
  /// cached with it so a column of links costs one resolution.
  late final _Resolved linked = _Resolved(
    column,
    row,
    cell,
    withHyperlinkFont(style),
  );

  final XlsxStyle? column;
  final XlsxStyle? row;
  final XlsxStyle? cell;

  /// The layers merged; `null` when all three are.
  final XlsxStyle? style;

  /// The id of [style], once registered.
  int? id;

  /// The ids of [style] with a date format added, by that format.
  final Map<XlsxNumFmt, int> dateIds = <XlsxNumFmt, int>{};
}

/// Cell text after repair, and which repairs it needed.
typedef _CleanText = ({String text, bool removed, bool truncated});

/// A checked formula: its text as written, the kind and `<v>` text of its
/// cached result, and the warning the cell reports.
typedef _CheckedFormula = ({
  String text,
  RawCellKind kind,
  String? value,
  XlsxWarningCode? warning,
});
