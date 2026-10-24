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
import 'date_serial.dart';
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

/// Whether Excel, which stores every number as a double, may round [v].
bool _losesPrecision(int v) => v.abs() > _maxExactInt;

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

  /// Whether any formula cell has been written, so the workbook can ask
  /// Excel to recalculate on load.
  bool get wroteFormula => _wroteFormula;

  /// Writes the cell at zero-based [row] and [column] of [sheet] to [out].
  ///
  /// [value] is a `String`, `int`, `double`, `bool`, [DateTime], [XlsxDate],
  /// [XlsxDecimal], [XlsxFormula], an [XlsxCell] wrapping one of those, or
  /// `null`, which writes nothing. The effective style is the [XlsxCell]'s
  /// style, else [rowStyle]; styles are replaced, not merged.
  ///
  /// Data problems (characters XML forbids, text past 32,767 UTF-16 code
  /// units, integers past 2^53, dates outside 1900 to 9999, a date shown in
  /// a non-date format) are repaired and reported to the warning collector;
  /// a formula's cached string or integer is treated like a plain one.
  /// Programmer errors throw an [ArgumentError]: an unsupported type, a
  /// nested [XlsxCell], a `NaN` or infinite number, an impossible date, a
  /// formula that is empty after its leading `=`, longer than 8,192 UTF-16
  /// code units or holds characters XML forbids, an invalid cached value; an invalid style throws like
  /// [StyleRegistry.idFor]. When it throws, nothing is written to [out] and
  /// nothing is recorded: the string table, the style registry and the
  /// warnings are as they were.
  void encode(
    XmlWriter out, {
    required String sheet,
    required int row,
    required int column,
    required Object? value,
    XlsxStyle? rowStyle,
  }) {
    final String ref = cellRef(row, column);
    XlsxStyle? style = rowStyle;
    Object? v = value;
    if (v is XlsxCell) {
      style = v.style ?? rowStyle;
      v = v.value;
      if (v is XlsxCell) {
        throw ArgumentError(
          'Cell $ref on sheet "$sheet" nests an XlsxCell '
          'inside an XlsxCell.',
        );
      }
    }
    switch (v) {
      case null:
        return;
      case String():
        _writeString(out, sheet, ref, v, style);
      case num() when !v.isFinite:
        // Before the int case: on the web NaN and infinity also satisfy
        // `is int`.
        throw _nonFinite(v, sheet, ref);
      case bool():
        _write(out, ref, _styles.idFor(style), 'b', '<v>${v ? 1 : 0}</v>');
      case int():
        final int id = _styles.idFor(style);
        if (_losesPrecision(v)) {
          _warnings.add(
            XlsxWarningCode.intPrecisionLost,
            sheet: sheet,
            cell: ref,
          );
        }
        _write(out, ref, id, null, '<v>$v</v>');
      case double():
        _write(out, ref, _styles.idFor(style), null, '<v>$v</v>');
      case XlsxDecimal():
        _write(out, ref, _styles.idFor(style), null, '<v>${v.digits}</v>');
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
        final int? serial = dateSerial(v.year, v.month, v.day);
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
    XlsxStyle? style, {
    bool outsideDateRange = false,
  }) {
    final ScrubResult scrubbed = scrubXmlText(text);
    final String result = _truncate(scrubbed.text);
    // The style can throw; resolve it before anything is recorded.
    final int id = _styles.idFor(style);
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
  static String _truncate(String text) {
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
    XlsxStyle? style,
    XlsxNumFmt defaultFormat,
  ) {
    XlsxStyle? effective = style;
    final XlsxNumFmt? format = style?.numFmt;
    if (format == null) {
      effective = (style ?? const XlsxStyle()).copyWith(numFmt: defaultFormat);
    }
    // The style can throw; resolve it before the warning is recorded.
    final int id = _styles.idFor(effective);
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
    XlsxStyle? style,
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
        final String kept = _truncate(cached);
        if (kept.length < cached.length) {
          warning = XlsxWarningCode.textTruncated;
        }
        type = 'str';
        cachedXml = '<v>${escapeXmlText(kept)}</v>';
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
    final int id = _styles.idFor(style);
    if (warning != null) _warnings.add(warning, sheet: sheet, cell: ref);
    _write(
      out,
      ref,
      id,
      type,
      '<f>${escapeXmlText(text)}</f>${cachedXml ?? ''}',
    );
    _wroteFormula = true;
  }

  ArgumentError _nonFinite(num value, String sheet, String ref) =>
      ArgumentError(
        'Cell $ref on sheet "$sheet" holds $value; Excel cannot store NaN or '
        'infinity.',
      );

  /// Writes the cell element with the style id [id], resolved by the caller
  /// before it recorded anything.
  void _write(XmlWriter out, String ref, int id, String? type, String body) {
    final StringBuffer cell = StringBuffer('<c r="$ref"');
    if (id != 0) cell.write(' s="$id"');
    if (type != null) cell.write(' t="$type"');
    cell
      ..write('>')
      ..write(body)
      ..write('</c>');
    out.raw(cell.toString());
  }

  String _isoDate(XlsxDate date) {
    final String year = date.year.abs().toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year < 0 ? '-' : ''}$year-$month-$day';
  }
}
