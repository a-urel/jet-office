import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/zip_builder.dart';

/// Two sheets, `Data` and `Other`, where `Other` points at `Data` from a
/// formula, a name, a validation and a conditional format.
Uint8List _book() {
  final XlsxWorkbook book = XlsxWorkbook();
  book.addSheet('Data')
    ..setCell(0, 0, 1)
    ..setCell(1, 0, 2);
  book.addSheet('Other')
    ..setCell(0, 0, const XlsxFormula('Data!A1+SUM(Data!A1:A2)', cached: 4))
    ..addDataValidation(
      XlsxDataValidation(
        <XlsxRange>[XlsxRange.parse('B1')],
        XlsxValidationType.list,
        formula1: r'Data!$A$1:$A$2',
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('C1')],
        <XlsxConditionalRule>[
          const XlsxExpressionRule(
            r'Data!$A$1>0',
            style: XlsxStyle(font: XlsxFont(bold: true)),
          ),
        ],
      ),
    );
  book.defineName(const XlsxDefinedName('Rng', r'Data!$A$1:$A$2'));
  book.properties = const OfficeProperties(title: 'T');
  return book.save().bytes;
}

void main() {
  test('rename rewrites formulas, names, rules, validations, charts', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.renameSheet(book.sheet('Data'), 'Facts');
    expect(book.sheets.first.name, 'Facts');
    final Map<String, String> parts = readXlsx(book.save().bytes);
    final String workbook = parts['xl/workbook.xml']!;
    expect(workbook, contains('<sheet name="Facts"'));
    expect(workbook, contains(r'Facts!$A$1:$A$2'));
    final String other = parts['xl/worksheets/sheet2.xml']!;
    expect(other, contains('Facts!A1+SUM(Facts!A1:A2)'));
    expect(other, contains(r'Facts!$A$1:$A$2'));
    expect(other, contains(r'Facts!$A$1&gt;0'));
    expect(other, isNot(contains('Data!')));

    final Fixture kinds = allFixtures().firstWhere(
      (Fixture f) => f.name == 'c1_kinds',
    );
    final XlsxWorkbook charts = XlsxWorkbook.open(kinds.build());
    charts.renameSheet(charts.sheet('Data'), 'My Data');
    final Map<String, String> chartParts = readXlsx(charts.save().bytes);
    final String chart = chartParts['xl/charts/chart1.xml']!;
    expect(chart, contains("'My Data'!"));
    expect(chart, isNot(contains('<c:f>Data!')));
  });

  test('quotes added and removed as needed', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.renameSheet(book.sheet('Data'), 'My Data');
    String other() => readXlsx(book.save().bytes)['xl/worksheets/sheet2.xml']!;
    expect(other(), contains("'My Data'!A1+SUM('My Data'!A1:A2)"));
    book.renameSheet(book.sheet('My Data'), 'Plain');
    expect(other(), contains('Plain!A1+SUM(Plain!A1:A2)'));
  });

  test('a taken name throws', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    final Uint8List before = book.save().bytes;
    final XlsxSheet data = book.sheet('Data');
    Matcher named() => throwsA(
      isA<ArgumentError>().having(
        (ArgumentError e) => e.name,
        'name',
        'newName',
      ),
    );
    expect(() => book.renameSheet(data, 'other'), named());
    expect(() => book.renameSheet(data, 'History'), named());
    expect(() => book.renameSheet(data, 'a/b'), named());
    expect(() => book.renameSheet(data, ''), named());
    expect(() => book.renameSheet(data, 'x' * 32), named());
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(
      comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
    // The same name changes nothing; a case-only rename is one.
    book.renameSheet(data, 'Data');
    expect(changeLogOf(book).hasChanges, isFalse);
    book.renameSheet(data, 'DATA');
    expect(data.name, 'DATA');
    expect(
      readXlsx(book.save().bytes)['xl/worksheets/sheet2.xml'],
      contains('DATA!A1'),
    );
  });

  test('app.xml titles follow', () {
    // Excel lists the sheets, then the names, in `TitlesOfParts`.
    const String app =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="$_extended" xmlns:vt="$_vTypes">'
        '<Application>Microsoft Excel</Application>'
        '<TitlesOfParts><vt:vector size="3" baseType="lpstr">'
        '<vt:lpstr>Data</vt:lpstr><vt:lpstr>Other</vt:lpstr>'
        '<vt:lpstr>Rng</vt:lpstr></vt:vector></TitlesOfParts>'
        '</Properties>';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withPart(_book(), 'docProps/app.xml', app),
    );
    final String before = readXlsx(book.save().bytes)['docProps/app.xml']!;
    final ChangeLog log = changeLogOf(book);
    final XlsxSheet data = book.sheet('Data');
    final ChangeSet set = log.transaction(
      () => book.renameSheet(data, 'R & D'),
    );
    final String renamed = readXlsx(book.save().bytes)['docProps/app.xml']!;
    expect(renamed, contains('<vt:lpstr>R &amp; D</vt:lpstr>'));
    expect(renamed, contains('<vt:lpstr>Other</vt:lpstr>'));
    expect(renamed, isNot(contains('<vt:lpstr>Data</vt:lpstr>')));
    expect(XlsxReader(book.save().bytes).warnings, isEmpty);
    log.revertSet(set);
    expect(readXlsx(book.save().bytes)['docProps/app.xml'], before);
    expect(data.name, 'Data');
  });

  test('undo restores bytes', () {
    final Uint8List input = _book();
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final Uint8List before = book.save().bytes;
    final ChangeLog log = changeLogOf(book);
    log.revertSet(
      log.transaction(() => book.renameSheet(book.sheet('Data'), 'My Data')),
    );
    expect(
      comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });
}

const String _extended =
    'http://schemas.openxmlformats.org/officeDocument/2006/extended-properties';
const String _vTypes =
    'http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes';

/// [bytes] with the part [name] replaced by [text].
Uint8List _withPart(Uint8List bytes, String name, String text) =>
    buildZipOrdered(<(String, List<int>)>[
      for (final MapEntry<String, Uint8List> p in readXlsxBytes(bytes).entries)
        (p.key, p.key == name ? utf8.encode(text) : p.value),
    ]);
