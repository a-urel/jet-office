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
/// It also holds the two steps of the workbook model (decision 0009): the
/// raw step maps a `t` to a [RawCellKind] ([decodeRawKind]) and back
/// ([encodeRawKind]), and the typed step turns a stored [RawCell] into a
/// value ([decodeRawCell], which is [decodeCell]).
///
/// Not ported from Quds, whose reader decoded cells inline in
/// `XlsxGridReader`; written for jet_office.
library;

import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../format/format_kind.dart';
import '../raw_cell.dart';
import '../values.dart';
import '../warnings.dart';
import 'read_cell.dart';
import 'serial_dates.dart';
import 'shared_strings_reader.dart';
import 'styles_reader.dart';

export '../raw_cell.dart' show FormulaType;

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

/// The type of the `<f>` element [r] is on, from its `t` attribute (no
/// namespace); an absent or unknown value is [FormulaType.normal].
FormulaType decodeFormulaType(XmlPullReader r) =>
    switch (r.getAttribute('t', namespaceUri: '')) {
      'shared' => FormulaType.shared,
      'array' => FormulaType.array,
      'dataTable' => FormulaType.dataTable,
      _ => FormulaType.normal,
    };

/// The [RawCellKind] of a cell whose `t` attribute is [type]; `null` and
/// `n` are [RawCellKind.number], a value the format does not define
/// (matched exactly, so `S` too) is [RawCellKind.unknown].
RawCellKind decodeRawKind(String? type) => switch (type) {
  null || 'n' => RawCellKind.number,
  's' => RawCellKind.sharedString,
  'b' => RawCellKind.boolean,
  'e' => RawCellKind.error,
  'str' => RawCellKind.string,
  'inlineStr' => RawCellKind.inlineString,
  'd' => RawCellKind.isoDate,
  _ => RawCellKind.unknown,
};

/// The `t` text to write for [cell], or `null` for none: the inverse of
/// [decodeRawKind]. A number has no `t`; an unknown kind writes its
/// [RawCell.typeText] (`null` when it has none).
String? encodeRawKind(RawCell cell) => switch (cell.kind) {
  RawCellKind.number => null,
  RawCellKind.sharedString => 's',
  RawCellKind.boolean => 'b',
  RawCellKind.error => 'e',
  RawCellKind.string => 'str',
  RawCellKind.inlineString => 'inlineStr',
  RawCellKind.isoDate => 'd',
  RawCellKind.unknown => cell.typeText,
};

/// The typed value of the stored [cell]: [decodeCell] with the cell's parts.
///
/// [sharedStrings], [format] and [date1904] are as for [decodeCell]. The
/// text of [RawCell.inline] is the inline text, and only for a
/// [RawCellKind.inlineString], as the reader reads it; [inlineText] gives
/// it instead when the caller already read it (the reader does, without
/// keeping the element). An unknown kind without a [RawCell.typeText] is
/// unsupported, like any unknown `t`. The formula text is returned as
/// stored: [RawFormula.text] is already XML-string decoded.
DecodedCell decodeRawCell(
  RawCell cell, {
  required List<String>? sharedStrings,
  required CellFormat format,
  required bool date1904,
  String? inlineText,
}) {
  final RawFormula? formula = cell.formula;
  final OpaqueXml? inline = cell.inline;
  final DecodedCell decoded = decodeCell(
    type: cell.kind == RawCellKind.unknown
        ? (cell.typeText ?? '')
        : encodeRawKind(cell),
    value: cell.value,
    formula: null,
    hasFormula: formula != null,
    inlineText:
        inlineText ??
        (inline != null && cell.kind == RawCellKind.inlineString
            ? inlineTextOf(inline)
            : null),
    sharedStrings: sharedStrings,
    format: format,
    date1904: date1904,
  );
  final String? text = formula?.text;
  return text == null
      ? decoded
      : DecodedCell(
          value: decoded.value,
          formula: text,
          warning: decoded.warning,
        );
}

/// The text of the inline string element [inline] (an `<is>`), read as the
/// reader reads one: its `<t>` and the `<t>` of each run, decoded. `null`
/// when it is longer than [maxLength].
String? inlineTextOf(OpaqueXml inline, {int maxLength = 0x7fffffff}) {
  final StringBuffer standalone = StringBuffer();
  inline.writeTo(XmlWriter(standalone));
  final XmlPullReader r = XmlPullReader(standalone.toString());
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) {
      return readStringItem(r, maxLength);
    }
  }
  return '';
}

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
/// * [hasFormula] and neither [value] nor [inlineText]: value `null`,
///   warning [XlsxWarningCode.formulaWithoutValue].
/// * `null` or `n`: a number, see below.
/// * `s`: the shared string at that index
///   ([XlsxWarningCode.sharedStringInvalid] when the index is not a
///   non-negative integer inside the table, or there is no table).
/// * `b`: `0` is `false`, `1` is `true` ([XlsxWarningCode.booleanInvalid]
///   otherwise).
/// * `str`: the [value] XML-string decoded, `''` when absent. With
///   [hasFormula], a text that is exactly one of
///   [XlsxErrorValue.classic] is that error: Google Sheets writes a
///   formula's error result this way, Excel as `e`.
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

  if (hasFormula && value == null && inlineText == null) {
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
      final String text = value == null ? '' : decodeXstring(value);
      if (hasFormula) {
        final XlsxErrorValue error = XlsxErrorValue(text);
        if (error.isClassic) return result(error);
      }
      return result(text);
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
