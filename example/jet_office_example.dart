// Writes `example.xlsx`: an accounts list and a summary sheet.
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
  summary.row(<Object?>['Written by jet_office, no Excel needed.']);
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

void main() {
  final XlsxResult result = buildExample();
  File('example.xlsx').writeAsBytesSync(result.bytes);
  stdout.writeln('example.xlsx: ${result.bytes.length} bytes');
  for (final XlsxWarning warning in result.warnings) {
    stdout.writeln(warning.message(XlsxLocale.tr));
  }
}
