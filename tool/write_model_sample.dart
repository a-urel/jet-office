/// Writes the workbooks the owner opens in the W1, W2 and W3 Excel checks:
/// each made from nothing with `XlsxWorkbook`.
///
/// ```bash
/// dart run tool/write_model_sample.dart build/model_generated
/// ```
///
/// The files are `<dir>/w1_generated.xlsx`, `<dir>/w2_generated.xlsx` and
/// `<dir>/w3_generated.xlsx` (the directory is created).
///
/// The sheet `Values` of `w1_generated.xlsx` holds, in row 1, text, an
/// integer, a double, an `XlsxDecimal`, a boolean, a date, a date and time
/// and a formula that sums its own row's B and C, with its result, and in
/// row 2 the same values after a cell was set twice and another cleared, so
/// the file shows what `setCell` leaves. A second sheet holds one text.
/// `docs/excel-checks.md`, "W1", says what Excel shows.
///
/// The sheet `Report` of `w2_generated.xlsx` has a merged title, a frozen
/// header of bold, a fill and a bottom border, date and money columns with
/// widths, a hidden and a grouped row and a tab colour. A second sheet is
/// hidden, and the first is the active one. `docs/excel-checks.md`, "W2",
/// says what Excel shows.
///
/// The sheet `Report` of `w3_generated.xlsx` has a header, a filter, a list
/// validation, a cell-value rule, a colour scale, a data bar and an icon set,
/// a data bar with `showValue` off in a column of its own, a link to a web
/// page and one to the sheet `Locked`, a print area and print titles, a
/// landscape fit-to-width page setup, a header and a footer, and a formula
/// that uses the workbook name `TaxRate`. `Locked` is protected with the
/// password `secret`. The workbook has properties, one of them custom.
/// `docs/excel-checks.md`, "W3", says what Excel shows.
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

/// Writes `w1_generated.xlsx`, `w2_generated.xlsx` and `w3_generated.xlsx`
/// to [dir] and returns their paths, in that order.
List<String> writeModelSample(String dir) => <String>[
  _writeBook('$dir/w1_generated.xlsx', _valuesBook()),
  _writeBook('$dir/w2_generated.xlsx', _reportBook()),
  _writeBook('$dir/w3_generated.xlsx', _featuresBook()),
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

/// The workbook of the W3 check: sheet and workbook features.
XlsxWorkbook _featuresBook() {
  const XlsxStyle header = XlsxStyle(font: XlsxFont(bold: true));
  const List<String> headers = <String>[
    'Product',
    'Region',
    'Amount',
    'Score',
    'Stock',
    'Rating',
    'With tax',
    'Bar only',
  ];
  const List<(String, String, int, int, int, int)> rows =
      <(String, String, int, int, int, int)>[
        ('Apples', 'North', 1200, 10, 20, 1),
        ('Pears', 'South', 3400, 35, 60, 2),
        ('Plums', 'East', 2500, 50, 40, 3),
        ('Cherries', 'West', 4100, 75, 90, 4),
        ('Figs', 'North', 900, 90, 10, 5),
        ('Grapes', 'South', 5200, 100, 70, 3),
      ];
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet report = book.addSheet('Report');
  final XlsxSheet locked = book.addSheet('Locked');
  book.defineName(const XlsxDefinedName('TaxRate', '0.18'));
  for (int column = 0; column < headers.length; column++) {
    report.setCell(0, column, XlsxCell(headers[column], style: header));
  }
  for (int i = 0; i < rows.length; i++) {
    final (
      String name,
      String region,
      int amount,
      int score,
      int stock,
      int r,
    ) = rows[i];
    report
      ..setCell(i + 1, 0, name)
      ..setCell(i + 1, 1, region)
      ..setCell(i + 1, 2, amount)
      ..setCell(i + 1, 3, score)
      ..setCell(i + 1, 4, stock)
      ..setCell(i + 1, 5, r)
      ..setCell(
        i + 1,
        6,
        XlsxFormula('C${i + 2}*(1+TaxRate)', cached: amount * 118 / 100),
      )
      ..setCell(i + 1, 7, stock);
  }
  report
    ..setCell(
      8,
      0,
      XlsxHyperlink.url(
        'https://example.com/jet-office',
        text: 'jet_office web page',
        tooltip: 'Opens a web page',
      ),
    )
    ..setCell(9, 0, XlsxHyperlink.sheet('Locked', text: 'Go to Locked'))
    ..autoFilter = XlsxRange.parse('A1:G7')
    ..addDataValidation(
      XlsxDataValidation(
        <XlsxRange>[XlsxRange.parse('B2:B7')],
        XlsxValidationType.list,
        formula1: '"North,South,East,West"',
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('C2:C7')],
        <XlsxConditionalRule>[
          const XlsxCellValueRule(
            XlsxComparison.greaterThanOrEqual,
            '3000',
            style: XlsxStyle(fill: XlsxFill.solid(XlsxColor.rgb(0xFFC7CE))),
          ),
        ],
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('D2:D7')],
        <XlsxConditionalRule>[
          XlsxColorScale(
            <XlsxCfValue>[
              const XlsxCfValue.min(),
              XlsxCfValue.percentile(50),
              const XlsxCfValue.max(),
            ],
            <XlsxColor>[
              const XlsxColor.rgb(0xF8696B),
              const XlsxColor.rgb(0xFFEB84),
              const XlsxColor.rgb(0x63BE7B),
            ],
          ),
        ],
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('E2:E7')],
        <XlsxConditionalRule>[
          const XlsxDataBar(color: XlsxColor.rgb(0x638EC6)),
        ],
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('H2:H7')],
        <XlsxConditionalRule>[
          const XlsxDataBar(color: XlsxColor.rgb(0x63C384), showValue: false),
        ],
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('F2:F7')],
        <XlsxConditionalRule>[XlsxIconSet(XlsxIconSetType.threeArrows)],
      ),
    )
    ..printArea = <XlsxRange>[XlsxRange.parse('A1:G7')]
    ..setPrintTitles(rows: (0, 0))
    ..pageSetup = const XlsxPageSetup(
      orientation: XlsxOrientation.landscape,
      paperSize: XlsxPaperSize.a4,
      fitToWidth: 1,
      fitToHeight: 0,
    )
    ..headerFooter = const XlsxHeaderFooter(
      oddHeader: '&CSales report',
      oddFooter: '&LPrinted &D&RPage &P of &N',
    );
  locked
    ..setCell(0, 0, 'Locked sheet')
    ..setCell(1, 0, 'Editing this sheet asks for the password: secret')
    ..protection = const XlsxSheetProtection(password: 'secret');
  book.properties = const XlsxProperties(
    title: 'W3 sample',
    subject: 'Sheet and workbook features',
    creator: 'jet_office',
    custom: <String, Object>{'Project': 'Atlas', 'Reviewed': true},
  );
  return book;
}
