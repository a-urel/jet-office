/// The number format engine's entry point: [XlsxNumberFormatter].
///
/// New in jet_office; Quds has no number format engine. The formatter
/// resolves a cell's number format code from its id, its code and the
/// format locale, parses it once into a bounded cache, renders the value
/// with [renderValue] and falls back to `General` with
/// [XlsxWarningCode.numberFormatInvalid] when the code cannot be read or
/// would show too much.
///
/// @docImport '../read/xlsx_reader.dart';
/// @docImport '../values.dart';
library;

import '../color.dart';
import '../read/read_cell.dart';
import '../warnings.dart';
import 'builtin_formats.dart';
import 'format_code.dart';
import 'format_locale.dart';
import 'formatted_value.dart';
import 'section_choice.dart';
import 'value_renderer.dart';

/// Renders cell values the way Excel for Mac shows them.
///
/// A formatter is cheap to keep: it compiles each distinct format code once
/// and holds at most 1,024 compiled codes, dropping them all when full, so
/// a file with many distinct codes costs time but not memory.
final class XlsxNumberFormatter {
  /// Creates a formatter that renders with [locale] and the date system of
  /// [date1904].
  XlsxNumberFormatter({
    this.locale = XlsxFormatLocale.enUS,
    this.date1904 = false,
  });

  /// The region whose separators, names and words the results use.
  final XlsxFormatLocale locale;

  /// Whether date serials count from 1904, as [XlsxReader.date1904] says
  /// for the workbook.
  final bool date1904;

  static const int _cacheLimit = 1024;
  static const int _codeLimit = 255;
  static const int _outputLimit = 1000;
  static final ParsedFormat _general = parseFormatCode('General');

  final Map<String, ParsedFormat> _cache = <String, ParsedFormat>{};

  /// Formats [value] with the number format [numberFormatId] and
  /// [numberFormat], as the reader gives them.
  ///
  /// [value] is an [XlsxDecimal], a [num], a [DateTime], a [Duration], a
  /// [String], a [bool], an [XlsxErrorValue] or `null`.
  ///
  /// The code is resolved as Excel does in [locale]:
  ///
  /// - Ids 5–8, 14–22 and 37–44 differ by locale. Without [numberFormat],
  ///   or with the en-US code of ECMA-376 (`mm-dd-yy` for id 14, as the
  ///   reader gives it), they use [XlsxFormatLocale.builtinCodes]; another
  ///   code is used as written.
  /// - Otherwise [numberFormat] wins over [numberFormatId]. Without it,
  ///   id 0 is `General` and ids 1–4, 9–13 and 45–49 use the ECMA-376 code.
  /// - Ids 27–31, 36 and 50–58 without a code show as the locale's id 14,
  ///   ids 32–35 as its id 21, and ids 23–26 and 59–163 as `General`, each
  ///   with [XlsxWarningCode.numberFormatLocaleDependent].
  /// - Any other id without a code shows `General` with
  ///   [XlsxWarningCode.unresolvedNumberFormat].
  ///
  /// A result carries one warning: [XlsxWarningCode.numberFormatInvalid]
  /// first, then the resolution warning above, then
  /// [XlsxWarningCode.numberFormatUnsupported] from rendering.
  /// [generalWidth] is the number of characters `General` may use (11,
  /// Excel's default column width).
  ///
  /// Never throws for any code. A value of another type, or a
  /// [generalWidth] below 1, is a programmer error and throws
  /// [ArgumentError].
  XlsxFormattedValue format(
    Object? value, {
    int numberFormatId = 0,
    String? numberFormat,
    int generalWidth = 11,
  }) {
    if (generalWidth < 1) {
      throw ArgumentError.value(
        generalWidth,
        'generalWidth',
        'Must be at least 1',
      );
    }
    final (String code, XlsxWarningCode? resolved) = _resolve(
      numberFormatId,
      numberFormat,
    );
    // One warning per result: numberFormatInvalid, set below, beats the
    // resolution warning, which beats the render warning (see [_build]).
    XlsxWarningCode? warning = resolved;
    // A code over Excel's 255 characters is invalid whatever it holds, so
    // it is neither parsed nor cached: a 1 MiB code costs no memory.
    ParsedFormat parsed = code.length > _codeLimit ? _general : _parse(code);
    // An unterminated quote or bracket leaves the code unreadable too
    // (spec §6.4), though the parser keeps what it scanned.
    if (code.length > _codeLimit ||
        parsed.invalidReason != null ||
        parsed.truncated) {
      parsed = _general;
      warning = XlsxWarningCode.numberFormatInvalid;
    }
    // The bound is on what the code adds; a text shown unchanged is never
    // over it. Text is checked before it is built.
    if (value is String) {
      final FormatSection? section = chooseTextSection(parsed);
      if (section != null &&
          addedTextLength(section, value.length) > _outputLimit) {
        return _build(
          renderValue(
            value,
            _general,
            locale: locale,
            generalWidth: generalWidth,
            date1904: date1904,
          ),
          XlsxWarningCode.numberFormatInvalid,
        );
      }
    }
    RenderedValue result = renderValue(
      value,
      parsed,
      locale: locale,
      generalWidth: generalWidth,
      date1904: date1904,
    );
    XlsxFormattedValue formatted = _build(result, warning);
    if (value is! String && formatted.text.length > _outputLimit) {
      result = renderValue(
        value,
        _general,
        locale: locale,
        generalWidth: generalWidth,
        date1904: date1904,
      );
      formatted = _build(result, XlsxWarningCode.numberFormatInvalid);
    }
    return formatted;
  }

  /// Formats [cell]'s value with its number format: [format] of
  /// [XlsxReadCell.value], [XlsxReadCell.numberFormatId] and
  /// [XlsxReadCell.numberFormat].
  XlsxFormattedValue formatCell(XlsxReadCell cell, {int generalWidth = 11}) =>
      format(
        cell.value,
        numberFormatId: cell.numberFormatId,
        numberFormat: cell.numberFormat,
        generalWidth: generalWidth,
      );

  /// The code that the number format [id] and [numberFormat] stand for in
  /// [locale], with the resolution warning.
  (String, XlsxWarningCode?) _resolve(int id, String? numberFormat) {
    if (_isLocaleBuiltin(id) &&
        (numberFormat == null || numberFormat == builtinNumberFormatCode(id))) {
      return (_localeCode(id), null);
    }
    if (numberFormat != null) return (numberFormat, null);
    if (id == 0) return ('General', null);
    final String? builtin = builtinNumberFormatCode(id);
    if (builtin != null) return (builtin, null);
    if ((id >= 27 && id <= 31) || id == 36 || (id >= 50 && id <= 58)) {
      return (_localeCode(14), XlsxWarningCode.numberFormatLocaleDependent);
    }
    if (id >= 32 && id <= 35) {
      return (_localeCode(21), XlsxWarningCode.numberFormatLocaleDependent);
    }
    if (id >= 23 && id <= 163) {
      return ('General', XlsxWarningCode.numberFormatLocaleDependent);
    }
    return ('General', XlsxWarningCode.unresolvedNumberFormat);
  }

  /// Whether the code of the built-in id [id] differs by locale: ids 5–8,
  /// 14–22 and 37–44.
  static bool _isLocaleBuiltin(int id) =>
      (id >= 5 && id <= 8) || (id >= 14 && id <= 22) || (id >= 37 && id <= 44);

  /// [locale]'s code for the built-in id [id], or the invariant one when a
  /// caller's locale leaves it out.
  String _localeCode(int id) =>
      locale.builtinCodes[id] ?? builtinNumberFormatCode(id)!;

  ParsedFormat _parse(String code) {
    final ParsedFormat? cached = _cache[code];
    if (cached != null) return cached;
    if (_cache.length >= _cacheLimit) _cache.clear();
    return _cache[code] = parseFormatCode(code);
  }

  /// Builds the result of [result]; the render warning counts only when
  /// [warning] (the formatter's own) is null.
  static XlsxFormattedValue _build(
    RenderedValue result,
    XlsxWarningCode? warning,
  ) {
    final FormatColor? color = result.section?.color;
    return XlsxFormattedValue(
      result.parts,
      color: color == null
          ? null
          : color.rgb != null
          ? XlsxColor.rgb(color.rgb!)
          : XlsxColor.indexed(color.index!),
      overflow: result.overflow,
      warning: warning ?? result.warning,
    );
  }
}

/// How many compiled codes [formatter]'s cache holds, at most 1,024.
///
/// For tests: `lib/jet_office.dart` exports only [XlsxNumberFormatter], so
/// this is not public API.
int formatterCacheSize(XlsxNumberFormatter formatter) =>
    formatter._cache.length;
