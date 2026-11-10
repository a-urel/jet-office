/// Writes the workbooks the owner opens in the W1 to W5 Excel checks: each
/// made from nothing with `XlsxWorkbook`.
///
/// ```bash
/// dart run tool/write_model_sample.dart build/model_generated
/// ```
///
/// The files are `<dir>/w1_generated.xlsx` to `<dir>/w5_generated.xlsx`
/// (the directory is created).
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
/// The sheet `Objects` of `w4_generated.xlsx` has a rich text cell, a hidden
/// and a visible note, a PNG and a JPEG each as a one-cell and a two-cell
/// picture (the PNG twice, for one media part), a PNG added small and moved to
/// a larger size, a table with a totals row and a second table without a
/// style. The sheet `Removed` had a table and a picture added and removed
/// again. `docs/excel-checks.md`, "W4", says what Excel shows.
///
/// `w5_generated.xlsx` is made, then edited structurally. The sheet `Data`
/// has a table `Sales` (A1:C6) whose `Tax` column is one shared formula
/// group, a table `Extra` (F1:G3), the rate in J1, a column chart over
/// `Sales` (drawn by the test host `withCharts`, as the model adds no chart
/// yet, and the group shared by hand, as the model writes none), a validation
/// and a rule on the amounts, a note on A1 and a picture. The sheet `Summary`
/// holds formulas into `Data`, the names `Rate` and `Amounts`, a 3D sum
/// (`Data:Summary`) and a sum of `Extra[Qty]`. Then two rows are inserted
/// inside `Sales`, column D is deleted, `Data` is renamed `Veri 2026` and
/// moved last, and `Extra` is removed, which turns its uses into ranges.
/// `docs/excel-checks.md`, "W5", says what Excel shows.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';

import '../test/drawingml/chart/support/chart_host.dart';
import '../test/fixtures/m4_fixtures.dart' show jpeg3x5, png4x2;
import '../test/support/read_xlsx.dart';
import '../test/xlsx/read/support/zip_builder.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/write_model_sample.dart <outDir>');
    exitCode = 2;
    return;
  }
  writeModelSample(args.single).forEach(stdout.writeln);
}

/// Writes `w1_generated.xlsx` to `w5_generated.xlsx` to [dir] and returns
/// their paths, in that order.
List<String> writeModelSample(String dir) => <String>[
  _writeBook('$dir/w1_generated.xlsx', _valuesBook()),
  _writeBook('$dir/w2_generated.xlsx', _reportBook()),
  _writeBook('$dir/w3_generated.xlsx', _featuresBook()),
  _writeBook('$dir/w4_generated.xlsx', _objectsBook()),
  _writeBook('$dir/w5_generated.xlsx', _structureBook()),
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
  book.properties = const OfficeProperties(
    title: 'W3 sample',
    subject: 'Sheet and workbook features',
    creator: 'jet_office',
    application: 'jet_office',
    custom: <String, Object>{'Project': 'Atlas', 'Reviewed': true},
  );
  return book;
}

/// The workbook of the W4 check: rich text, notes, pictures and tables.
XlsxWorkbook _objectsBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet objects = book.addSheet('Objects');
  final XlsxSheet removed = book.addSheet('Removed');
  final OfficeImage png = OfficeImage(png4x2);
  final OfficeImage jpeg = OfficeImage(jpeg3x5);

  objects
    ..setColumn(0, const XlsxColumn(width: 28))
    ..setCell(
      0,
      0,
      XlsxRichText(<XlsxTextRun>[
        const XlsxTextRun('Bold', font: XlsxFont(bold: true)),
        const XlsxTextRun(', plain and '),
        const XlsxTextRun(
          'red italic',
          font: XlsxFont(italic: true, color: XlsxColor.rgb(0xC00000)),
        ),
      ]),
    )
    ..setCell(2, 0, 'Notes: hover B3; the note of C3 is always shown')
    ..setCell(2, 1, 'Hidden note')
    ..setCell(2, 2, 'Visible note')
    ..setNote(
      2,
      1,
      XlsxNote(
        XlsxRichText(<XlsxTextRun>[
          const XlsxTextRun('jet_office:\n', font: XlsxFont(bold: true)),
          const XlsxTextRun('shown only when the pointer rests on B3.'),
        ]),
        author: 'jet_office',
      ),
    )
    ..setNote(
      2,
      2,
      XlsxNote.plain(
        'Always shown, beside C3.',
        author: 'jet_office',
        visible: true,
      ),
    )
    // The PNG twice, one-cell and two-cell, shares one media part.
    ..addPicture(
      XlsxPicture(
        png,
        const XlsxOneCellAnchor(XlsxAnchorPoint(4, 4), width: 120, height: 60),
        name: 'PNG one-cell',
        description: 'A 4 by 2 pixel gradient, 120 by 60 pixels',
      ),
    )
    ..addPicture(
      XlsxPicture(
        png,
        XlsxTwoCellAnchor.range(const XlsxRange(4, 7, 7, 9)),
        name: 'PNG two-cell',
        description: 'The same gradient, filling H5:J8',
      ),
    )
    ..addPicture(
      XlsxPicture(
        jpeg,
        const XlsxOneCellAnchor(XlsxAnchorPoint(10, 4), width: 60, height: 100),
        name: 'JPEG one-cell',
        description: 'A 3 by 5 pixel gradient, 60 by 100 pixels',
      ),
    )
    ..addPicture(
      XlsxPicture(
        jpeg,
        XlsxTwoCellAnchor.range(const XlsxRange(10, 7, 14, 9)),
        name: 'JPEG two-cell',
        description: 'The same gradient, filling H11:J15',
      ),
    )
    // Added small, then moved: Excel must show the new size.
    ..addPicture(
      XlsxPicture(
        png,
        const XlsxOneCellAnchor(XlsxAnchorPoint(4, 11), width: 40, height: 20),
        name: 'Moved picture',
        description: 'Added 40 by 20 pixels, then moved to 200 by 100',
      ),
    )
    ..movePicture(
      4,
      const XlsxOneCellAnchor(XlsxAnchorPoint(4, 11), width: 200, height: 100),
    )
    ..setCell(15, 0, 'Table with a totals row (Sales, A17:B21)')
    ..addTable(
      XlsxTable('Sales', const XlsxRange(16, 0, 20, 1), <XlsxTableColumn>[
        const XlsxTableColumn('Product', totalsLabel: 'Total'),
        const XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
      ], totalsRow: true),
    );
  const List<(String, int)> sales = <(String, int)>[
    ('Apples', 120),
    ('Pears', 80),
    ('Plums', 45),
  ];
  for (int i = 0; i < sales.length; i++) {
    objects
      ..setCell(17 + i, 0, sales[i].$1)
      ..setCell(17 + i, 1, sales[i].$2);
  }
  objects
    ..setCell(15, 3, 'Table without a style (Plain, D17:E19)')
    ..addTable(
      XlsxTable('Plain', const XlsxRange(16, 3, 18, 4), <XlsxTableColumn>[
        const XlsxTableColumn('Item'),
        const XlsxTableColumn('Count'),
      ], style: null),
    )
    ..setCell(17, 3, 'Screws')
    ..setCell(17, 4, 12)
    ..setCell(18, 3, 'Nails')
    ..setCell(18, 4, 30);

  // A table and a picture are added and removed again: only cells remain.
  removed
    ..setCell(0, 0, 'A table and a picture were added here, then removed.')
    ..addPicture(
      XlsxPicture(
        png,
        const XlsxOneCellAnchor(XlsxAnchorPoint(2, 2), width: 80, height: 40),
      ),
    )
    ..addTable(
      XlsxTable('Gone', const XlsxRange(4, 0, 6, 1), <XlsxTableColumn>[
        const XlsxTableColumn('First'),
        const XlsxTableColumn('Second'),
      ]),
    )
    ..removePicture(0)
    ..removeTable('Gone');
  return book;
}

/// The months and amounts of the table `Sales` of `w5_generated.xlsx`.
const List<(String, int)> _sales = <(String, int)>[
  ('Jan', 100),
  ('Feb', 200),
  ('Mar', 300),
  ('Apr', 400),
  ('May', 500),
];

/// The workbook of the W5 check, made and then edited structurally.
XlsxWorkbook _structureBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet data = book.addSheet('Data');
  final XlsxSheet summary = book.addSheet('Summary');
  data
    ..setCell(0, 0, 'Month')
    ..setCell(0, 1, 'Amount')
    ..setCell(0, 2, 'Tax')
    ..setCell(0, 8, 'Rate')
    ..setCell(0, 9, 0.2);
  for (int i = 0; i < _sales.length; i++) {
    data
      ..setCell(i + 1, 0, _sales[i].$1)
      ..setCell(i + 1, 1, _sales[i].$2)
      ..setCell(
        i + 1,
        2,
        XlsxFormula('B${i + 2}*Rate', cached: _sales[i].$2 / 5),
      );
  }
  data
    ..addTable(
      XlsxTable('Sales', const XlsxRange(0, 0, 5, 2), <XlsxTableColumn>[
        const XlsxTableColumn('Month'),
        const XlsxTableColumn('Amount'),
        const XlsxTableColumn('Tax'),
      ]),
    )
    ..setCell(1, 5, 'Bolts')
    ..setCell(1, 6, 40)
    ..setCell(2, 5, 'Nuts')
    ..setCell(2, 6, 60)
    ..addTable(
      XlsxTable('Extra', const XlsxRange(0, 5, 2, 6), <XlsxTableColumn>[
        const XlsxTableColumn('Item'),
        const XlsxTableColumn('Qty'),
      ]),
    )
    ..addDataValidation(
      XlsxDataValidation(
        <XlsxRange>[XlsxRange.parse('B2:B6')],
        XlsxValidationType.whole,
        comparison: XlsxComparison.greaterThanOrEqual,
        formula1: '0',
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('B2:B6')],
        <XlsxConditionalRule>[
          const XlsxCellValueRule(
            XlsxComparison.greaterThan,
            r'$J$1*1000',
            style: XlsxStyle(fill: XlsxFill.solid(XlsxColor.rgb(0xFFC7CE))),
          ),
        ],
      ),
    )
    ..setNote(
      0,
      0,
      XlsxNote.plain('Two rows go in after Feb.', author: 'jet_office'),
    );
  book
    ..defineName(const XlsxDefinedName('Rate', r'Data!$J$1'))
    ..defineName(const XlsxDefinedName('Amounts', r'Data!$B$2:$B$6'));
  summary
    ..setCell(0, 0, 'Total')
    ..setCell(0, 1, const XlsxFormula('SUM(Sales[Amount])', cached: 1500))
    ..setCell(1, 0, 'February')
    ..setCell(1, 1, const XlsxFormula('Data!B3', cached: 200))
    ..setCell(2, 0, 'Named')
    ..setCell(2, 1, const XlsxFormula('SUM(Amounts)*Rate', cached: 300))
    ..setCell(3, 0, '3D sum')
    ..setCell(3, 1, const XlsxFormula('SUM(Data:Summary!B2)', cached: 100))
    ..setCell(4, 0, 'Extra')
    ..setCell(4, 1, const XlsxFormula('SUM(Extra[Qty])', cached: 100));

  final XlsxWorkbook edited = XlsxWorkbook.open(
    withCharts(_shareTax(book.save().bytes), 'Data', <Uint8List>[
      writeDrawingChartSpace(_salesChart(), ChartTheme.office).bytes,
    ]),
  );
  final XlsxSheet sheet = edited.sheet('Data');
  sheet.addPicture(
    XlsxPicture(
      OfficeImage(png4x2),
      const XlsxOneCellAnchor(XlsxAnchorPoint(0, 11), width: 120, height: 60),
      name: 'Picture',
      description: 'A 4 by 2 pixel gradient right of the rate',
    ),
  );
  edited.transaction(() {
    sheet
      ..insertRows(3, 2)
      ..deleteColumns(3);
    edited
      ..renameSheet(sheet, 'Veri 2026')
      ..moveSheet(sheet, edited.sheets.length - 1);
    sheet.removeTable('Extra');
  });
  return edited;
}

/// [xlsx] with the `Tax` formulas of `Data` (C2:C6) made one shared group,
/// as Excel writes a filled-down formula.
Uint8List _shareTax(Uint8List xlsx) {
  const String part = 'xl/worksheets/sheet1.xml';
  final Map<String, Uint8List> parts = readXlsxBytes(xlsx);
  String text = utf8.decode(parts[part]!);
  for (int row = 2; row <= 6; row++) {
    final String plain = '<f>B$row*Rate</f>';
    if (!text.contains(plain)) {
      throw StateError('The Tax formula of row $row is not $plain.');
    }
    text = text.replaceFirst(
      plain,
      row == 2
          ? '<f t="shared" ref="C2:C6" si="0">B2*Rate</f>'
          : '<f t="shared" si="0"/>',
    );
  }
  return buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> e in parts.entries)
      (e.key, e.key == part ? utf8.encode(text) : e.value),
  ]);
}

/// A column chart of the amounts of `Sales`, by month.
DrawingChartSpace _salesChart() => DrawingChartSpace(
  chart: Chart(
    kind: ChartKind.column,
    title: const ChartTitle(text: 'Sales'),
    series: <ChartSeries>[
      ChartSeries(
        name: ChartData<String>(
          values: <String?>['Amount'],
          reference: r'Data!$B$1',
        ),
        categories: ChartData<Object>(
          values: <Object>[for (final (String m, int _) in _sales) m],
          reference: r'Data!$A$2:$A$6',
        ),
        values: ChartData<double>(
          values: <double?>[for (final (String _, int a) in _sales) a * 1.0],
          reference: r'Data!$B$2:$B$6',
        ),
      ),
    ],
  ),
  ids: const DrawingChartIds(
    categoryAxis: 500001,
    valueAxis: 500002,
    series: <String>['{00000000-00C5-0000-0000-000000000001}'],
  ),
);
