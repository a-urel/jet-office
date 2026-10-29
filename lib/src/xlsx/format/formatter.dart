/// The number format engine's entry point: [XlsxNumberFormatter].
///
/// New in jet_office; Quds has no number format engine. The formatter
/// resolves a cell's number format code from its id and code, parses it
/// once into a bounded cache, renders the value with [renderValue] and
/// falls back to `General` with [XlsxWarningCode.numberFormatInvalid] when
/// the code cannot be read or would show too much.
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
  /// [String], a [bool], an [XlsxErrorValue] or `null`. [numberFormat]
  /// wins over [numberFormatId]; without it, id 0 and the built-in ids use
  /// their built-in code, and any other id shows `General` with
  /// [XlsxWarningCode.unresolvedNumberFormat]. [generalWidth] is the number
  /// of characters `General` may use (11, Excel's default column width).
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
    XlsxWarningCode? warning;
    String? code = numberFormat;
    if (code == null) {
      code = numberFormatId == 0
          ? 'General'
          : builtinNumberFormatCode(numberFormatId);
      if (code == null) {
        code = 'General';
        warning = XlsxWarningCode.unresolvedNumberFormat;
      }
    }
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
