/// Writes the workbooks the owner opens in the W1 and W2 Excel checks: each
/// made from nothing with `XlsxWorkbook`.
///
/// ```bash
/// dart run tool/write_model_sample.dart build/model_generated
/// ```
///
/// The files are `<dir>/w1_generated.xlsx` and `<dir>/w2_generated.xlsx` (the
/// directory is created).
///
/// The sheet `Values` of `w1_generated.xlsx` holds, in row 1, text, an integer, a double, an
/// `XlsxDecimal`, a boolean, a date, a date and time and a formula that sums
/// its own row's B and C, with its result, and in row 2 the same values
/// after a cell was set twice and another cleared, so the file shows what
/// `setCell` leaves. A second sheet
/// holds one text. `docs/excel-checks.md`, "W1", says what Excel shows.
///
/// The sheet `Report` of `w2_generated.xlsx` has a merged title, a frozen
/// header of bold, a fill and a bottom border, date and money columns with
/// widths, a hidden and a grouped row and a tab colour. A second sheet is
/// hidden, and the first is the active one. `docs/excel-checks.md`, "W2",
/// says what Excel shows.
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
  writeModelSample(args.single).forEach(stdout.writeln);
}

/// Writes `w1_generated.xlsx` and `w2_generated.xlsx` to [dir] and returns
/// their paths, in that order.
List<String> writeModelSample(String dir) => <String>[
  _writeBook('$dir/w1_generated.xlsx', _valuesBook()),
  _writeBook('$dir/w2_generated.xlsx', _reportBook()),
];

/// Saves [book] to [path], making its directory, and returns [path].
String _writeBook(String path, XlsxWorkbook book) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(book.save().bytes);
  return path;
}

/// The workbook of the W1 check: values, set and cleared.
XlsxWorkbook _valuesBook() {
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
      ..setCell(
        r,
        7,
        XlsxFormula('SUM(B${r + 1}:C${r + 1})', cached: r == 0 ? 45.14159 : 8),
      );
  }

  row(0);
  row(1);
  values
    ..setCell(1, 1, 'replaced')
    ..setCell(1, 2, 7)
    ..setCell(1, 2, 8)
    ..setCell(1, 3, null);
  book.addSheet('Second').setCell(0, 0, 'second sheet');
  return book;
}

/// The workbook of the W2 check: styles, layout and sheet states.
XlsxWorkbook _reportBook() {
  const XlsxStyle title = XlsxStyle(
    font: XlsxFont(bold: true, size: 14),
    alignment: XlsxAlignment(horizontal: XlsxHorizontalAlignment.center),
  );
  const XlsxStyle header = XlsxStyle(
    font: XlsxFont(bold: true),
    fill: XlsxFill.solid(XlsxColor.rgb(0xDDEBF7)),
    border: XlsxBorder(bottom: XlsxBorderSide(style: XlsxBorderStyle.medium)),
  );
  const XlsxStyle date = XlsxStyle(numFmt: XlsxNumFmt.custom('dd.mm.yyyy'));
  const XlsxStyle money = XlsxStyle(numFmt: XlsxNumFmt.custom('#,##0.00'));

  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet report = book.addSheet('Report');
  report
    ..setColumn(0, const XlsxColumn(width: 24))
    ..setColumn(1, const XlsxColumn(width: 14, style: date))
    ..setColumn(2, const XlsxColumn(width: 16, style: money))
    ..setCell(0, 0, const XlsxCell('Sales report', style: title))
    ..merge(const XlsxRange(0, 0, 0, 3));
  const List<String> headers = <String>['Product', 'Date', 'Amount', 'Note'];
  for (int column = 0; column < headers.length; column++) {
    report.setCell(1, column, XlsxCell(headers[column], style: header));
  }
  const List<(String, XlsxDate, double, String)> sales =
      <(String, XlsxDate, double, String)>[
        ('Apples', XlsxDate(2026, 1, 15), 1234.5, 'shown'),
        ('Pears', XlsxDate(2026, 2, 16), 2345.75, 'hidden row'),
        ('Plums', XlsxDate(2026, 3, 17), 3456, 'grouped row'),
        ('Cherries', XlsxDate(2026, 4, 18), 4567.25, 'shown'),
      ];
  for (int i = 0; i < sales.length; i++) {
    final (String product, XlsxDate day, double amount, String note) = sales[i];
    report
      ..setCell(i + 2, 0, product)
      ..setCell(i + 2, 1, XlsxCell(day))
      ..setCell(i + 2, 2, XlsxCell(amount))
      ..setCell(i + 2, 3, note);
  }
  report
    ..setRowFormat(3, const XlsxRowFormat(hidden: true))
    ..setRowFormat(4, const XlsxRowFormat(outlineLevel: 1))
    ..view = const XlsxSheetView(pane: XlsxPane.frozen(rows: 2))
    ..tabColor = const XlsxColor.rgb(0x00B050);
  book.addSheet('Hidden').setCell(0, 0, 'hidden sheet');
  book.sheets.last.visibility = XlsxSheetVisibility.hidden;
  book.activeSheet = report;
  return book;
}
