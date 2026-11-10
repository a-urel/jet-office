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
import 'support/app_titles.dart';

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

  test('app.xml titles follow, named ranges too', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withPart(
        _book(),
        'docProps/app.xml',
        appXml(
          <(String, int)>[('Worksheets', 2), ('Named Ranges', 2)],
          <String>['Data', 'Other', 'Data!Print_Area', 'Other!Data'],
        ),
      ),
    );
    final String before = readXlsx(book.save().bytes)['docProps/app.xml']!;
    final ChangeLog log = changeLogOf(book);
    final XlsxSheet data = book.sheet('Data');
    final ChangeSet set = log.transaction(
      () => book.renameSheet(data, 'R & D'),
    );
    final String renamed = readXlsx(book.save().bytes)['docProps/app.xml']!;
    expect(appTitles(renamed), <String>[
      'R & D',
      'Other',
      "'R & D'!Print_Area",
      'Other!Data',
    ]);
    expect(renamed, contains('<vt:i4>2</vt:i4>'));
    expect(XlsxReader(book.save().bytes).warnings, isEmpty);
    log.revertSet(set);
    expect(readXlsx(book.save().bytes)['docProps/app.xml'], before);
    expect(data.name, 'Data');
  });

  test('titles that cannot be read together are removed', () {
    for (final String app in <String>[
      // The counts disagree with the titles.
      appXml(<(String, int)>[('Worksheets', 3)], <String>['Data', 'Other']),
      // No slice lists the sheets.
      appXml(<(String, int)>[('Worksheets', 2)], <String>['Data', 'Gone']),
      // Titles without heading pairs.
      appXml(null, <String>['Data', 'Other']),
    ]) {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withPart(_book(), 'docProps/app.xml', app),
      );
      book.renameSheet(book.sheet('Data'), 'Facts');
      final String out = readXlsx(book.save().bytes)['docProps/app.xml']!;
      expect(out, isNot(contains('TitlesOfParts')));
      expect(out, isNot(contains('HeadingPairs')));
      expect(out, contains('<Application>Microsoft Excel</Application>'));
    }
  });

  test('a rename that throws leaves the package byte-equal', () {
    final Uint8List input = _withPart(
      _withPart(
        _book(),
        'docProps/app.xml',
        appXml(<(String, int)>[('Worksheets', 2)], <String>['Data', 'Other']),
      ),
      'xl/worksheets/sheet2.xml',
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
          '2006/main"><sheetData><row>',
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final Uint8List before = book.save().bytes;
    expect(
      () => book.renameSheet(book.sheet('Data'), 'Facts'),
      throwsA(isA<XlsxReadException>()),
    );
    expect(book.sheet('Data').name, 'Data');
    final Uint8List after = book.save().bytes;
    // The properties, loaded inside the edit, are written from the file's
    // bytes again.
    final Map<String, Uint8List> was = readXlsxBytes(before);
    final Map<String, Uint8List> now = readXlsxBytes(after);
    for (final String part in <String>[
      'docProps/app.xml',
      'docProps/core.xml',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      '[Content_Types].xml',
    ]) {
      expect(now[part], was[part], reason: part);
    }
    // The registry loaded the shared strings, which are then written from
    // the model: equal in meaning (an unreadable sheet compares as one).
    expect(comparePackages(before, after), <String>[
      'xl/worksheets/sheet2.xml: the expected part is not well-formed XML '
          'or not UTF-8',
      'xl/worksheets/sheet2.xml: the actual part is not well-formed XML or '
          'not UTF-8',
    ]);
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

/// [bytes] with the part [name] replaced by [text].
Uint8List _withPart(Uint8List bytes, String name, String text) =>
    buildZipOrdered(<(String, List<int>)>[
      for (final MapEntry<String, Uint8List> p in readXlsxBytes(bytes).entries)
        (p.key, p.key == name ? utf8.encode(text) : p.value),
    ]);
