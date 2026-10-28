/// Turns the XML of one worksheet cell into a value, in one place.
///
/// This is the reader's half of decision 0007 and the mirror of the
/// writer's single cell encoder (decision 0002): no other file under `lib/`
/// reads a `t` attribute, the `<c>`'s or the `<f>`'s (enforced by
/// `test/architecture/cell_decoder_test.dart`). The row walker reads the
/// attributes through [decodeCellType] and [decodeFormulaType] and the
/// element texts, resolves the cell's style to a [CellFormat], then calls
/// [decodeCell].
///
/// Not ported from Quds, whose reader decoded cells inline in
/// `XlsxGridReader`; written for jet_office.
library;

import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../values.dart';
import '../warnings.dart';
import 'format_kind.dart';
import 'read_cell.dart';
import 'serial_dates.dart';
import 'styles_reader.dart';

/// The largest exponent (in magnitude) a number may carry.
const int _maxExponent = 400;

/// Optional sign, mantissa, optional exponent.
final RegExp _number = RegExp(
  r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?)(\d+))?$',
);

final RegExp _leadingZeros = RegExp('^0+');

final RegExp _leadingZerosBeforeDigit = RegExp(r'^0+(?=\d)');

final RegExp _nonZeroDigit = RegExp('[1-9]');

final RegExp _index = RegExp(r'^\d{1,9}$');

/// What one cell decoded to.
final class DecodedCell {
  /// A decoded cell with [value], [formula] and [warning].
  const DecodedCell({this.value, this.formula, this.warning});

  /// `null`, a `String`, a `bool`, an [XlsxDecimal], a `DateTime`, a
  /// `Duration` or an [XlsxErrorValue].
  ///
  /// `null` for an empty cell and when [warning] says the value could not
  /// be read; a number whose format could not be applied keeps its
  /// [XlsxDecimal] alongside the warning.
  final Object? value;

  /// The formula text, XML-string decoded, or `null` when the cell has none.
  final String? formula;

  /// Why the value could not be read exactly, or `null` when it could.
  final XlsxWarningCode? warning;
}

/// The `t` attribute (no namespace) of the cell element [r] is on, or `null`.
String? decodeCellType(XmlPullReader r) =>
    r.getAttribute('t', namespaceUri: '');

/// The type of a formula, the `t` attribute of its `<f>`.
enum FormulaType {
  /// A formula of its own cell (`t` absent, `normal` or unknown).
  normal,

  /// `t="shared"`: a master (with `ref`) or a follower of a shared formula.
  shared,

  /// `t="array"`: the master of an array formula.
  array,

  /// `t="dataTable"`: the master of a data table.
  dataTable,
}

/// The type of the `<f>` element [r] is on, from its `t` attribute (no
/// namespace); an absent or unknown value is [FormulaType.normal].
FormulaType decodeFormulaType(XmlPullReader r) =>
    switch (r.getAttribute('t', namespaceUri: '')) {
      'shared' => FormulaType.shared,
      'array' => FormulaType.array,
      'dataTable' => FormulaType.dataTable,
      _ => FormulaType.normal,
    };

/// Decodes one cell.
///
/// [type] is the `t` attribute, [value] the `<v>` text (`null` when absent),
/// [formula] the `<f>` text (`null` when `<f>` is absent or empty),
/// [hasFormula] whether a `<f>` element exists, [inlineText] the text of an
/// `<is>` (`null` when absent), [sharedStrings] the workbook's shared-string
/// table (`null` when it has none), [format] the cell's number format and
/// [date1904] whether the workbook uses the 1904 date system.
///
/// The cases, first match wins; a cell gets at most one warning:
///
/// * [hasFormula] and no [value]: value `null`, warning
///   [XlsxWarningCode.formulaWithoutValue].
/// * `null` or `n`: a number, see below.
/// * `s`: the shared string at that index
///   ([XlsxWarningCode.sharedStringInvalid] when the index is not a
///   non-negative integer inside the table, or there is no table).
/// * `b`: `0` is `false`, `1` is `true` ([XlsxWarningCode.booleanInvalid]
///   otherwise).
/// * `str`: the [value] XML-string decoded, `''` when absent.
/// * `e`: the [XlsxErrorValue] of the [value], XML-string decoded and
///   trimmed ([XlsxWarningCode.errorValueInvalid] when that is empty).
/// * `inlineStr`: [inlineText]; without it the [value] XML-string decoded;
///   without either `''`.
/// * `d`: the ISO 8601 [value], trimmed, as a UTC `DateTime`
///   ([XlsxWarningCode.dateTextInvalid] when it is not one).
/// * anything else: [XlsxWarningCode.cellTypeUnsupported].
///
/// A number is an [XlsxDecimal] ([XlsxWarningCode.numberInvalid] when the
/// text is not a number, or its exponent is beyond +-400). Then [format]
/// applies, first match wins: an `invalid` format keeps the decimal with
/// [XlsxWarningCode.styleInvalid]; a format without a code (a
/// locale-dependent built-in id) keeps it with
/// [XlsxWarningCode.unresolvedNumberFormat]; a date format makes it a
/// `DateTime` and a time format a `Duration`, and a serial neither can hold
/// keeps the decimal with [XlsxWarningCode.phantomLeapDay] or
/// [XlsxWarningCode.serialOutOfRange]. Formats apply to numbers only.
///
/// The decoded [formula] is returned in every case. Never throws.
DecodedCell decodeCell({
  required String? type,
  required String? value,
  required String? formula,
  required bool hasFormula,
  required String? inlineText,
  required List<String>? sharedStrings,
  required CellFormat format,
  required bool date1904,
}) {
  final String? decodedFormula = formula == null
      ? null
      : decodeXstring(formula);
  DecodedCell result(Object? v, [XlsxWarningCode? warning]) =>
      DecodedCell(value: v, formula: decodedFormula, warning: warning);

  if (hasFormula && value == null) {
    return result(null, XlsxWarningCode.formulaWithoutValue);
  }
  switch (type) {
    case null:
    case 'n':
      final String? digits = value == null ? null : normalizeNumber(value);
      if (digits == null) return result(null, XlsxWarningCode.numberInvalid);
      final XlsxDecimal number = XlsxDecimal(digits);
      if (format.invalid) return result(number, XlsxWarningCode.styleInvalid);
      if (format.code == null && format.id != 0) {
        return result(number, XlsxWarningCode.unresolvedNumberFormat);
      }
      switch (format.kind) {
        case FormatKind.number:
          return result(number);
        case FormatKind.date:
          final ({DateTime? date, XlsxWarningCode? warning}) mapped =
              serialToDateTime(digits, date1904: date1904);
          return result(mapped.date ?? number, mapped.warning);
        case FormatKind.time:
          final ({Duration? duration, XlsxWarningCode? warning}) mapped =
              serialToDuration(digits);
          return result(mapped.duration ?? number, mapped.warning);
      }
    case 's':
      final String trimmed = value?.trim() ?? '';
      if (sharedStrings != null && _index.hasMatch(trimmed)) {
        final int i = int.parse(trimmed);
        if (i < sharedStrings.length) {
          return result(sharedStrings[i]);
        }
      }
      return result(null, XlsxWarningCode.sharedStringInvalid);
    case 'b':
      return switch (value?.trim()) {
        '0' => result(false),
        '1' => result(true),
        _ => result(null, XlsxWarningCode.booleanInvalid),
      };
    case 'str':
      return result(value == null ? '' : decodeXstring(value));
    case 'e':
      final String code = value == null ? '' : decodeXstring(value).trim();
      return code.isEmpty
          ? result(null, XlsxWarningCode.errorValueInvalid)
          : result(XlsxErrorValue(code));
    case 'inlineStr':
      return result(inlineText ?? (value == null ? '' : decodeXstring(value)));
    case 'd':
      final DateTime? date = value == null
          ? null
          : parseIsoDateTime(value.trim());
      return date == null
          ? result(null, XlsxWarningCode.dateTextInvalid)
          : result(date);
    default:
      return result(null, XlsxWarningCode.cellTypeUnsupported);
  }
}

/// The digits of the number written in [text], or `null` when it is not one.
///
/// [text] is trimmed and must match
/// `[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?`. The result matches
/// `-?\d+(\.\d+)?`, so it is always a valid [XlsxDecimal]:
///
/// * Without an exponent the file's digits are kept as written
///   (`1234.50` and `007` stay), except that a leading `+` and a trailing
///   `.` are dropped and `.5` becomes `0.5`.
/// * With an exponent the point moves by it. The significant digits the file
///   wrote are kept (`1.50E1` is `15.0`, `12E-1` is `1.2`), the integer part
///   becomes canonical (no leading zeros but a single `0`) and a fraction
///   exists only when digits remain after the point.
/// * A zero loses its sign (`-0` is `0`, `-0.0` is `0.0`); any other
///   negative number keeps it.
/// * An exponent whose magnitude exceeds 400 gives `null`, so the result is
///   never longer than the mantissa plus 400 characters.
String? normalizeNumber(String text) {
  final RegExpMatch? m = _number.firstMatch(text.trim());
  if (m == null) {
    return null;
  }
  final String sign = m.group(1) == '-' ? '-' : '';
  final String intPart = m.group(2) ?? '';
  final String fraction = m.group(3) ?? m.group(4) ?? '';
  final String? exponentDigits = m.group(6);

  String whole = intPart.isEmpty ? '0' : intPart;
  String fractional = fraction;
  if (exponentDigits != null) {
    final String significant = exponentDigits.replaceFirst(_leadingZeros, '');
    if (significant.length > 3) {
      return null;
    }
    final int magnitude = significant.isEmpty ? 0 : int.parse(significant);
    if (magnitude > _maxExponent) {
      return null;
    }
    final int exponent = m.group(5) == '-' ? -magnitude : magnitude;
    final String all = intPart + fraction;
    final int point = intPart.length + exponent;
    if (point <= 0) {
      whole = '0';
      fractional = '${'0' * -point}$all';
    } else if (point >= all.length) {
      whole = '$all${'0' * (point - all.length)}';
      fractional = '';
    } else {
      whole = all.substring(0, point);
      fractional = all.substring(point);
    }
    whole = whole.replaceFirst(_leadingZerosBeforeDigit, '');
  }
  final String digits = fractional.isEmpty ? whole : '$whole.$fractional';
  final bool isZero = !digits.contains(_nonZeroDigit);
  return isZero ? digits : '$sign$digits';
}
