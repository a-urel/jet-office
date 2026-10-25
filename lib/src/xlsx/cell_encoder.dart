/// The one place a cell value becomes SpreadsheetML (decision 0002).
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: the cell branch of `_sheetXml`. Changed: Quds wrote a `DateTime`
/// as its `toString()` text and `NaN` and infinity verbatim; both are fixed
/// here (dates become serials, non-finite numbers throw). Added: strings go
/// through the shared-string table after scrubbing and truncation to Excel's
/// limit, decimals, date-only values and formulas, and warnings for lossy
/// conversions.
///
/// Both the streaming writer and the workbook model call [CellEncoder]; no
/// other file under `lib/` writes a cell element.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'color.dart';
import 'date_serial.dart';
import 'font.dart';
import 'hyperlink.dart';
import 'limits.dart';
import 'number_format.dart';
import 'shared_strings.dart';
import 'style.dart';
import 'style_registry.dart';
import 'values.dart';
import 'warnings.dart';

/// The largest whole number a `double` holds exactly (2^53).
const int _maxExactInt = 9007199254740992;

/// The most characters (UTF-16 code units) Excel accepts in a formula.
const int _maxFormulaLength = 8192;

/// The font of a hyperlink cell: the theme's hyperlink color, underlined.
/// The lowest font layer: whatever a column, row or cell font sets wins.
const XlsxFont _hyperlinkFont = XlsxFont(
  color: XlsxColor.theme(10),
  underline: XlsxUnderline.single,
);

/// Whether Excel, which stores every number as a double, may round [v].
///
/// Not `v.abs()`: the absolute value of the 64-bit minimum overflows to
/// itself, a negative number.
bool _losesPrecision(int v) => v > _maxExactInt || v < -_maxExactInt;

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
  /// [XlsxDecimal], [XlsxFormula], [XlsxHyperlink], an [XlsxCell] wrapping
  /// one of those, or `null`, which writes nothing. An [XlsxCell] whose
  /// value is `null` and whose style is not writes an empty styled cell,
  /// `<c r="C5" s="7"/>`, when the merged style below is not the default;
  /// with the default style, or with no cell style, it writes nothing
  /// (ruling R11).
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
  /// Data problems (characters XML forbids, text past 32,767 UTF-16 code
  /// units, integers past 2^53, dates outside 1900 to 9999, a date shown in
  /// a non-date format) are repaired and reported to the warning collector.
  /// On the web a whole `double` beyond 2^53 is indistinguishable from an
  /// `int`, so it also warns `intPrecisionLost`. An [XlsxDecimal] beyond the
  /// `double` range is written verbatim, and Excel rounds it.
  /// A date gets the date-time or short-date format only when the merged
  /// number format is `null`; in any other format it keeps that format, and
  /// warns when that format shows no date.
  /// a formula's cached string or integer is treated like a plain one.
  /// Programmer errors throw an [ArgumentError]: an unsupported type, a
  /// nested [XlsxCell], a `NaN` or infinite number, an impossible date, a
  /// formula that is empty after its leading `=`, longer than 8,192 UTF-16
  /// code units or holds characters XML forbids, an invalid cached value.
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
        _write(out, ref, _idOf(style), 'b', '<v>${v ? 1 : 0}</v>');
      case int():
        final int id = _idOf(style);
        if (_losesPrecision(v)) {
          _warnings.add(
            XlsxWarningCode.intPrecisionLost,
            sheet: sheet,
            cell: ref,
          );
        }
        _write(out, ref, id, null, '<v>$v</v>');
      case double():
        _write(out, ref, _idOf(style), null, '<v>$v</v>');
      case XlsxDecimal():
        _write(out, ref, _idOf(style), null, '<v>${v.digits}</v>');
      case DateTime():
        final double? serial = dateTimeSerial(v);
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
          _writeDate(
            out,
            sheet,
            ref,
            serial == serial.truncateToDouble()
                ? '${serial.toInt()}'
                : '$serial',
            style,
            XlsxNumFmt.localeDateTime,
          );
        }
      case XlsxDate():
        final int? serial;
        try {
          serial = dateSerial(v.year, v.month, v.day);
        } on ArgumentError {
          throw ArgumentError(
            'Cell $ref on sheet "$sheet" holds the date '
            '${v.year}-${v.month}-${v.day}, which does not exist.',
          );
        }
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
      default:
        throw ArgumentError(
          'Cell $ref on sheet "$sheet" holds a ${v.runtimeType}, which is not '
          'a supported cell value.',
        );
    }
  }

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
    final ScrubResult scrubbed = scrubXmlText(text);
    final String result = truncateCellText(scrubbed.text);
    // The style can throw; resolve it before anything is recorded.
    final int id = _idOf(style);
    if (scrubbed.removed > 0) {
      _warnings.add(
        XlsxWarningCode.invalidCharactersRemoved,
        sheet: sheet,
        cell: ref,
      );
    }
    if (result.length < scrubbed.text.length) {
      _warnings.add(XlsxWarningCode.textTruncated, sheet: sheet, cell: ref);
    }
    if (outsideDateRange) {
      _warnings.add(
        XlsxWarningCode.dateOutsideExcelRange,
        sheet: sheet,
        cell: ref,
      );
    }
    _write(out, ref, id, 's', '<v>${_strings.indexOf(result)}</v>');
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
    final String text = formula.text.startsWith('=')
        ? formula.text.substring(1)
        : formula.text;
    if (text.isEmpty) {
      throw ArgumentError(
        'The formula in cell $ref on sheet "$sheet" is empty.',
      );
    }
    if (text.length > _maxFormulaLength) {
      throw ArgumentError(
        'The formula in cell $ref on sheet "$sheet" has ${text.length} '
        'characters; Excel accepts at most $_maxFormulaLength.',
      );
    }
    if (scrubXmlText(text).removed > 0) {
      throw ArgumentError(
        'The formula in cell $ref on sheet "$sheet" contains characters '
        'XML forbids.',
      );
    }
    final Object? cached = formula.cached;
    String? type;
    String? cachedXml;
    XlsxWarningCode? warning;
    switch (cached) {
      case null:
        break;
      case String():
        if (scrubXmlText(cached).removed > 0) {
          throw ArgumentError(
            'The cached result of the formula in cell $ref on sheet '
            '"$sheet" contains characters XML forbids.',
          );
        }
        final String kept = truncateCellText(cached);
        if (kept.length < cached.length) {
          warning = XlsxWarningCode.textTruncated;
        }
        type = 'str';
        cachedXml = '<v>${escapeXmlText(escapeXstring(kept))}</v>';
      case bool():
        type = 'b';
        cachedXml = '<v>${cached ? 1 : 0}</v>';
      case num() when !cached.isFinite:
        throw _nonFinite(cached, sheet, ref);
      case num():
        if (cached is int && _losesPrecision(cached)) {
          warning = XlsxWarningCode.intPrecisionLost;
        }
        cachedXml = '<v>$cached</v>';
      default:
        throw ArgumentError(
          'The cached result of the formula in cell $ref on sheet "$sheet" '
          'is a ${cached.runtimeType}; expected null, num, String or bool.',
        );
    }
    // The style can throw; resolve it before the warning is recorded.
    final int id = _idOf(style);
    if (warning != null) _warnings.add(warning, sheet: sheet, cell: ref);
    _write(
      out,
      ref,
      id,
      type,
      '<f>${escapeFormulaText(text)}</f>${cachedXml ?? ''}',
    );
    _wroteFormula = true;
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
    (style ?? const XlsxStyle()).copyWith(
      font: _hyperlinkFont.merge(style?.font),
    ),
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
