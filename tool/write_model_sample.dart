/// Writes the workbook the owner opens in the W1 Excel check: one made from
/// nothing with `XlsxWorkbook`.
///
/// ```bash
/// dart run tool/write_model_sample.dart build/model_generated
/// ```
///
/// The file is `<dir>/w1_generated.xlsx` (the directory is created). Its
/// sheet `Values` holds, in row 1, text, an integer, a double, an
/// `XlsxDecimal`, a boolean, a date, a date and time and a formula with a
/// cached result, and in row 2 the same values after a cell was set twice and
/// another cleared, so the file shows what `setCell` leaves. A second sheet
/// holds one text. `docs/excel-checks.md`, "W1", says what Excel shows.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/write_model_sample.dart <outDir>');
    exitCode = 2;
    return;
  }
  stdout.writeln(writeModelSample(args.single));
}

/// Writes `w1_generated.xlsx` to [dir] and returns its path.
String writeModelSample(String dir) {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet values = book.addSheet('Values');
  void row(int r) {
    values
      ..setCell(r, 0, 'jet_office')
      ..setCell(r, 1, 42)
      ..setCell(r, 2, 3.14159)
      ..setCell(r, 3, XlsxDecimal('1234.50'))
      ..setCell(r, 4, true)
      ..setCell(r, 5, const XlsxDate(2026, 10, 24))
      ..setCell(r, 6, DateTime.utc(2026, 10, 24, 13, 45))
      ..setCell(r, 7, const XlsxFormula('SUM(B1:C1)', cached: 45.14159));
  }

  row(0);
  row(1);
  values
    ..setCell(1, 1, 'replaced')
    ..setCell(1, 2, 7)
    ..setCell(1, 2, 8)
    ..setCell(1, 3, null);
  book.addSheet('Second').setCell(0, 0, 'second sheet');
  final File file = File('$dir/w1_generated.xlsx')
    ..createSync(recursive: true)
    ..writeAsBytesSync(book.save().bytes);
  return file.path;
}
