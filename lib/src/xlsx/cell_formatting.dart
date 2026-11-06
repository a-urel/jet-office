/// What jet_office adds to jet_core's number format engine: formatting a
/// cell the reader read, and mapping the engine's neutral results to the
/// XLSX types.
///
/// New in jet_office; Quds has no number format engine. The engine lives in
/// jet_core (decision 0012) and knows no file format: it takes a number
/// format id and code, and it names its warnings and colours plainly. These
/// extensions give a [NumberFormatter] the reader's cell, a
/// [FormatWarning] its [XlsxWarningCode] and a [FormatColor] its
/// [XlsxColor], so a caller keeps the XLSX vocabulary of the writers and the
/// reader without jet_core knowing it.
///
/// @docImport 'read/xlsx_reader.dart';
/// @docImport 'values.dart';
/// @docImport 'warnings.dart';
library;

import 'package:jet_core/jet_core.dart';

import 'color.dart';
import 'read/read_cell.dart';
import 'warnings.dart';

/// Formats a cell the reader read.
extension XlsxCellFormatting on NumberFormatter {
  /// Formats [cell]'s value with its number format: `format` of
  /// [XlsxReadCell.value], [XlsxReadCell.numberFormatId] and
  /// [XlsxReadCell.numberFormat].
  ///
  /// The value is passed on as the reader gave it: an [XlsxDecimal] and an
  /// [XlsxErrorValue] are the engine's own `FormatDecimal` and
  /// `FormatErrorValue`. [generalWidth] is as in `format`: the number of
  /// characters `General` may use (11, Excel's default column width).
  FormattedValue formatCell(XlsxReadCell cell, {int generalWidth = 11}) =>
      format(
        cell.value,
        numberFormatId: cell.numberFormatId,
        numberFormat: cell.numberFormat,
        generalWidth: generalWidth,
      );
}

/// The [XlsxWarningCode] of a [FormatWarning].
extension XlsxFormatWarning on FormatWarning {
  /// The code that reports this warning as an [XlsxWarning]:
  /// [XlsxWarningCode.numberFormatInvalid] for [FormatWarning.invalidCode],
  /// [XlsxWarningCode.numberFormatUnsupported] for
  /// [FormatWarning.unsupported],
  /// [XlsxWarningCode.numberFormatLocaleDependent] for
  /// [FormatWarning.localeDependent] and
  /// [XlsxWarningCode.unresolvedNumberFormat] for [FormatWarning.unresolved].
  XlsxWarningCode get xlsxCode => switch (this) {
    FormatWarning.invalidCode => XlsxWarningCode.numberFormatInvalid,
    FormatWarning.unsupported => XlsxWarningCode.numberFormatUnsupported,
    FormatWarning.localeDependent =>
      XlsxWarningCode.numberFormatLocaleDependent,
    FormatWarning.unresolved => XlsxWarningCode.unresolvedNumberFormat,
  };
}

/// The [XlsxColor] of a [FormatColor].
extension XlsxFormatColor on FormatColor {
  /// The colour as an [XlsxColor]: [XlsxColor.rgb] for a named colour
  /// (`[Red]`), [XlsxColor.indexed] for a palette entry (`[Color56]`).
  XlsxColor get xlsxColor =>
      rgb != null ? XlsxColor.rgb(rgb!) : XlsxColor.indexed(index!);
}
