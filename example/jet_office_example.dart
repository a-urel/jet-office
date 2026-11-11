// Writes `example.xlsx`, an accounts list and a summary sheet, then reads
// it back with `XlsxReader` and prints the first rows of the list. Then it
// writes `example.docx`, the same accounts as a Word list with a page header
// and footer. Last it opens the workbook with `XlsxWorkbook`, edits it and
// generates a small one, then saves both.
//
// Run it from the repository root:
//
//     dart run example/jet_office_example.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

/// Builds the example workbook and returns it with its warnings.
XlsxResult buildExample() {
  final XlsxWriter book = XlsxWriter(
    properties: const OfficeProperties(title: 'Accounts'),
  );

  // The list helper writes caption, header, rows and totals on one sheet.
  XlsxListExport(const <XlsxListColumn>[
    XlsxListColumn('Code', width: 12, totalsLabel: 'Total'),
    XlsxListColumn('Customer', width: 24),
    XlsxListColumn(
      'Balance',
      width: 16,
      style: XlsxStyle(numFmt: XlsxNumFmt.thousands2),
      totalsFunction: XlsxTotalsFunction.sum,
    ),
    XlsxListColumn(
      'Opened',
      width: 14,
      style: XlsxStyle(numFmt: XlsxNumFmt.localeShortDate),
    ),
  ], caption: 'Accounts').writeTo(book.addSheet('Accounts'), <List<Object?>>[
    <Object?>[
      'A-1',
      'Acme Ltd',
      XlsxDecimal('1234.50'),
      const XlsxDate(2026, 1, 5),
    ],
    <Object?>[
      'A-2',
      'Birch & Co',
      XlsxDecimal('99.99'),
      const XlsxDate(2026, 3, 17),
    ],
    <Object?>[
      'A-3',
      'Cedar\u0001 GmbH',
      XlsxDecimal('480'),
      const XlsxDate(2026, 6, 2),
    ],
  ]);

  // The summary goes first in the tab order. Rows are written top down.
  final XlsxSheetWriter summary = book.addSheet('Summary', position: 0);
  summary.columns(const <XlsxColumn?>[
    XlsxColumn(width: 28),
    XlsxColumn(width: 16),
  ]);
  summary.row(<Object?>[
    'Item',
    'Value',
  ], style: const XlsxStyle(font: XlsxFont(bold: true)));
  summary.row(<Object?>[
    'Total balance',
    const XlsxFormula('SUM(Accounts!C3:C5)', cached: 1814.49),
  ]);
  // A note on the total, at the zero-based cell B2.
  summary.note(
    1,
    1,
    XlsxNote.plain('Sum of the Accounts balances.', author: 'jet_office'),
  );
  summary.row(<Object?>[
    XlsxHyperlink.url(
      'https://github.com/a-urel/jet-office',
      text: 'Project page',
    ),
  ]);

  return book.close();
}

/// The example workbook as bytes.
Uint8List buildExampleWorkbook() => buildExample().bytes;

/// Builds the same accounts as a Word document: a header with the report's
/// name and date, the list with its header row repeated on every page, a
/// totals row the caller adds up, and a footer with the page numbers.
DocxResult buildExampleDocument() {
  final DocxListExport list = DocxListExport(
    const <DocxListColumn>[
      DocxListColumn('Code', widthPt: 60),
      DocxListColumn('Customer'),
      DocxListColumn('Balance', widthPt: 90, numberFormat: '#,##0.00'),
      DocxListColumn('Opened', widthPt: 80),
    ],
    title: 'Accounts',
    date: DateTime(2026, 11, 8),
    caption: 'Accounts',
  );
  // Word has no formulas: the totals are the values to show.
  return list.toDocx(
    <List<Object?>>[
      <Object?>[
        'A-1',
        'Acme Ltd',
        XlsxDecimal('1234.50'),
        DateTime(2026, 1, 5),
      ],
      <Object?>[
        'A-2',
        'Birch & Co',
        XlsxDecimal('99.99'),
        DateTime(2026, 3, 17),
      ],
      <Object?>[
        'A-3',
        'Cedar\u0001 GmbH',
        XlsxDecimal('480'),
        DateTime(2026, 6, 2),
      ],
    ],
    totals: <Object?>['Total', null, XlsxDecimal('1814.49'), null],
    properties: const OfficeProperties(title: 'Accounts'),
  );
}

/// What [readExample] reads: the sheet names, the cell values of the first
/// rows of the `Accounts` sheet and the reader's warnings.
typedef ExampleReadBack = ({
  List<String> sheets,
  List<List<Object?>> rows,
  List<XlsxWarning> warnings,
});

/// Reads [bytes] with [XlsxReader] and returns the sheet names, the values
/// of the first [count] rows of `Accounts` and the warnings.
///
/// Every row is read, not only the first [count]: a sheet's warnings are
/// complete once its rows have been iterated to the end.
ExampleReadBack readExample(Uint8List bytes, {int count = 4}) {
  final XlsxReader reader = XlsxReader(bytes);
  final List<List<Object?>> rows = <List<Object?>>[];
  for (final XlsxReadRow row in reader.rows('Accounts')) {
    if (rows.length == count) continue;
    rows.add(<Object?>[for (final XlsxReadCell cell in row.cells) cell.value]);
  }
  return (
    sheets: <String>[
      for (final XlsxReadSheet sheet in reader.sheets) sheet.name,
    ],
    rows: rows,
    warnings: reader.warnings,
  );
}

/// Opens [bytes] with the workbook model, changes the first balance and
/// inserts a row in a transaction that is then undone, and saves.
XlsxResult editExample(Uint8List bytes) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  final XlsxSheet accounts = book.sheet('Accounts');
  accounts.setCell(2, 2, XlsxDecimal('2000'));
  final XlsxChangeSet set = book.transaction(() => accounts.insertRows(3));
  book.undo(set);
  return book.save();
}

/// Generates a small workbook with the model.
XlsxResult generateExample() {
  final XlsxWorkbook book = XlsxWorkbook();
  book.addSheet('Prices')
    ..setCell(0, 0, 'Tea')
    ..setCell(0, 1, XlsxDecimal('3.50'))
    ..setStyle(0, 0, const XlsxStyle(font: XlsxFont(bold: true)));
  return book.save();
}

void main() {
  final XlsxResult result = buildExample();
  File('example.xlsx').writeAsBytesSync(result.bytes);
  stdout.writeln('example.xlsx: ${result.bytes.length} bytes');
  for (final XlsxWarning warning in result.warnings) {
    stdout.writeln(warning.message(OfficeLocale.tr));
  }

  // Read the file back. The totals row's SUBTOTAL formula has no cached
  // result, so the reader reports it as formulaWithoutValue.
  final ExampleReadBack read = readExample(result.bytes);
  stdout.writeln('sheets: ${read.sheets.join(', ')}');
  for (final List<Object?> row in read.rows) {
    stdout.writeln(row.join(' | '));
  }
  for (final XlsxWarning warning in read.warnings) {
    stdout.writeln(warning.message());
  }

  // The same list as a Word document. Its warnings come in the same locales.
  final DocxResult document = buildExampleDocument();
  File('example.docx').writeAsBytesSync(document.bytes);
  stdout.writeln('example.docx: ${document.bytes.length} bytes');
  for (final DocxWarning warning in document.warnings) {
    stdout.writeln(warning.message(OfficeLocale.tr));
  }

  // The model opens the file, edits it and saves it; what it did not change
  // stays as it was.
  final XlsxResult edited = editExample(result.bytes);
  File('example-edited.xlsx').writeAsBytesSync(edited.bytes);
  stdout.writeln('example-edited.xlsx: ${edited.bytes.length} bytes');
  final XlsxResult generated = generateExample();
  File('example-model.xlsx').writeAsBytesSync(generated.bytes);
  stdout.writeln('example-model.xlsx: ${generated.bytes.length} bytes');
}
