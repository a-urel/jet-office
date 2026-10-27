// Every Dart block of README.md appears here verbatim, inside a function, so
// the README compiles and runs. Keep the two in step.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/xlsx_checker.dart';

XlsxResult quickStart() {
  final XlsxWriter book = XlsxWriter();
  final XlsxSheetWriter sheet = book.addSheet('Accounts');
  sheet.columns(const <XlsxColumn?>[
    XlsxColumn(width: 12),
    XlsxColumn(width: 16),
  ]);
  sheet.row(<Object?>[
    'Code',
    'Balance',
  ], style: const XlsxStyle(font: XlsxFont(bold: true)));
  sheet.row(<Object?>['A-1', XlsxDecimal('1234.50')]);
  sheet.row(<Object?>['A-2', 99.5]);
  sheet.row(<Object?>['Total', const XlsxFormula('SUM(B2:B3)', cached: 1334)]);
  final XlsxResult out = book.close();
  // out.bytes is the .xlsx file; out.warnings lists what had to be repaired.
  return out;
}

XlsxResult listExport() {
  const List<XlsxListColumn> columns = <XlsxListColumn>[
    XlsxListColumn('Code', width: 12),
    XlsxListColumn(
      'Amount',
      width: 16,
      style: XlsxStyle(numFmt: XlsxNumFmt.thousands2),
      totalsFunction: XlsxTotalsFunction.sum,
    ),
  ];
  final XlsxResult out = XlsxListExport(columns, caption: 'Accounts').toXlsx(
    <List<Object?>>[
      <Object?>['A-1', XlsxDecimal('1234.50')],
      <Object?>['A-2', 99.5],
    ],
  );
  return out;
}

List<String> warnings(void Function(String) print) {
  final XlsxWriter book = XlsxWriter();
  book.addSheet('Notes').row(<Object?>['bad\u0001text']);
  for (final XlsxWarning warning in book.close().warnings) {
    print(warning.message(XlsxLocale.tr));
  }
  return <String>[];
}

({Uint8List bytes, List<XlsxWarning> warnings}) streaming() {
  final BytesBuilder file = BytesBuilder(copy: false);
  final XlsxStreamWriter book = XlsxStreamWriter(
    ByteConversionSink.withCallback(file.add),
  );
  final XlsxSheetWriter sheet = book.addSheet('Rows');
  for (int i = 0; i < 1000; i++) {
    sheet.row(<Object?>[i, 'row $i']);
  }
  final List<XlsxWarning> warnings = book.close();
  return (bytes: file.takeBytes(), warnings: warnings);
}

void main() {
  test('README quick start block is clean', () {
    final XlsxResult out = quickStart();
    expect(checkXlsx(out.bytes), isEmpty);
    expect(out.warnings, isEmpty);
  });

  test('README list export block is clean', () {
    expect(checkXlsx(listExport().bytes), isEmpty);
  });

  test('README warnings block prints a Turkish message', () {
    final List<String> lines = <String>[];
    warnings(lines.add);
    expect(lines, hasLength(1));
    expect(lines.single, contains('Notes'));
  });

  test('README streaming block writes a clean file', () {
    final result = streaming();
    expect(checkXlsx(result.bytes), isEmpty);
    expect(result.warnings, isEmpty);
  });
}
