// Writes `example.xlsx`, an accounts list and a summary sheet, then reads
// it back with `XlsxReader` and prints the first rows of the list.
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
    properties: const XlsxProperties(title: 'Accounts'),
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

void main() {
  final XlsxResult result = buildExample();
  File('example.xlsx').writeAsBytesSync(result.bytes);
  stdout.writeln('example.xlsx: ${result.bytes.length} bytes');
  for (final XlsxWarning warning in result.warnings) {
    stdout.writeln(warning.message(XlsxLocale.tr));
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
}
