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

/// Sheets `A` to `D`; `A` sums `B:C`, `C` has a name of its own and is
/// active.
Uint8List _book() {
  final XlsxWorkbook book = XlsxWorkbook();
  book.addSheet('A').setCell(0, 0, const XlsxFormula('SUM(B:C!A1)', cached: 0));
  book.addSheet('B');
  final XlsxSheet c = book.addSheet('C');
  book.addSheet('D');
  c.defineName(const XlsxDefinedName('Local', r'C!$A$1'));
  book.activeSheet = c;
  return book.save().bytes;
}

List<String> _names(XlsxWorkbook book) =>
    book.sheets.map((XlsxSheet s) => s.name).toList();

void main() {
  test('move keeps localSheetId pointing at the same sheet', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.moveSheet(book.sheet('C'), 0);
    expect(_names(book), <String>['C', 'A', 'B', 'D']);
    expect(book.activeSheet.name, 'C');
    expect(book.sheet('C').definedNames.single.name, 'Local');
    final XlsxWorkbook reopened = XlsxWorkbook.open(book.save().bytes);
    expect(_names(reopened), <String>['C', 'A', 'B', 'D']);
    expect(reopened.activeSheet.name, 'C');
    expect(reopened.sheet('C').definedNames.single.name, 'Local');
    expect(reopened.sheet('A').definedNames, isEmpty);
    final String workbook = readXlsx(book.save().bytes)['xl/workbook.xml']!;
    expect(workbook, contains('localSheetId="0"'));
    expect(workbook, contains('activeTab="0"'));
  });

  test('firstSheet follows its sheet', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    final Map<String, String> parts = readXlsx(book.save().bytes);
    final String text = parts['xl/workbook.xml']!.replaceFirst(
      '<workbookView ',
      '<workbookView firstSheet="1" ',
    );
    final XlsxWorkbook edited = XlsxWorkbook.open(
      _withPart(book.save().bytes, 'xl/workbook.xml', text),
    );
    edited.moveSheet(edited.sheet('B'), 3);
    final String out = readXlsx(edited.save().bytes)['xl/workbook.xml']!;
    expect(out, contains('firstSheet="3"'));
    expect(out, contains('activeTab="1"'));
  });

  test('3D spans follow a move', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.moveSheet(book.sheet('B'), 2);
    expect(_names(book), <String>['A', 'C', 'B', 'D']);
    final String a = readXlsx(book.save().bytes)['xl/worksheets/sheet1.xml']!;
    // Excel quotes the sheet name C, which reads as a column in R1C1.
    expect(a, contains("SUM('C:B'!A1)"));
    expect(
      readXlsx(book.save().bytes)['xl/workbook.xml'],
      contains('fullCalcOnLoad="1"'),
    );
  });

  test('a move to the same place changes nothing; bad ones throw', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.moveSheet(book.sheet('B'), 1);
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(
      () => book.moveSheet(book.sheet('B'), 4),
      throwsA(isA<RangeError>().having((e) => e.name, 'name', 'position')),
    );
    final XlsxSheet foreign = XlsxWorkbook.open(_book()).sheets.first;
    expect(() => book.moveSheet(foreign, 0), throwsArgumentError);
  });

  test('move undo restores bytes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    final Uint8List before = book.save().bytes;
    final ChangeLog log = changeLogOf(book);
    log.revertSet(log.transaction(() => book.moveSheet(book.sheet('B'), 3)));
    expect(_names(book), <String>['A', 'B', 'C', 'D']);
    expect(
      comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  test('addSheet places the sheet and keeps indexes on their sheets', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.addSheet('New', position: 1);
    expect(_names(book), <String>['A', 'New', 'B', 'C', 'D']);
    expect(book.activeSheet.name, 'C');
    final XlsxWorkbook reopened = XlsxWorkbook.open(book.save().bytes);
    expect(_names(reopened), <String>['A', 'New', 'B', 'C', 'D']);
    expect(reopened.activeSheet.name, 'C');
    expect(reopened.sheet('C').definedNames.single.name, 'Local');
    expect(
      () => book.addSheet('X', position: 6),
      throwsA(isA<RangeError>().having((e) => e.name, 'name', 'position')),
    );
  });

  test('app.xml titles follow a move and an added sheet', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withPart(
        _book(),
        'docProps/app.xml',
        appXml(
          <(String, int)>[('Worksheets', 4), ('Named Ranges', 1)],
          <String>['A', 'B', 'C', 'D', 'C!Local'],
        ),
      ),
    );
    String app() => readXlsx(book.save().bytes)['docProps/app.xml']!;
    final String before = app();
    final ChangeLog log = changeLogOf(book);
    final ChangeSet move = log.transaction(
      () => book.moveSheet(book.sheet('D'), 0),
    );
    expect(appTitles(app()), <String>['D', 'A', 'B', 'C', 'C!Local']);
    final ChangeSet add = log.transaction(
      () => book.addSheet('New', position: 2),
    );
    expect(appTitles(app()), <String>['D', 'A', 'New', 'B', 'C', 'C!Local']);
    expect(appCounts(app()), ('5', '6'));
    expect(XlsxReader(book.save().bytes).warnings, isEmpty);
    log
      ..revertSet(add)
      ..revertSet(move);
    expect(app(), before);
  });

  test('addSheet takes a free part name among oddly named parts', () {
    // Sheets in sheet1.xml and sheet3.xml: the third sheet's name is taken.
    final Uint8List odd = _renamedPart(
      _book(),
      'xl/worksheets/sheet2.xml',
      'xl/worksheets/sheet5.xml',
    );
    final XlsxWorkbook book = XlsxWorkbook.open(odd);
    book.addSheet('New').setCell(0, 0, 'new');
    final Uint8List saved = book.save().bytes;
    final Map<String, String> parts = readXlsx(saved);
    expect(parts.keys, contains('xl/worksheets/sheet5.xml'));
    final XlsxWorkbook reopened = XlsxWorkbook.open(saved);
    expect(_names(reopened), <String>['A', 'B', 'C', 'D', 'New']);
    expect(reopened.sheet('New').cellAt(0, 0)?.value, 'new');
    expect(reopened.sheet('B').cellAt(0, 0), isNull);
    expect(XlsxReader(saved).warnings, isEmpty);
  });

  test('addSheet undo restores bytes', () {
    for (final Fixture f in allFixtures()) {
      final XlsxWorkbook book = XlsxWorkbook.open(f.build());
      final Uint8List before = book.save().bytes;
      final ChangeLog log = changeLogOf(book);
      final int count = book.sheets.length;
      log.revertSet(log.transaction(() => book.addSheet('Added', position: 0)));
      expect(book.sheets.length, count, reason: f.name);
      expect(
        comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
        reason: f.name,
      );
    }
  });
}

/// [bytes] with the part [name] replaced by [text].
Uint8List _withPart(Uint8List bytes, String name, String text) =>
    buildZipOrdered(<(String, List<int>)>[
      for (final MapEntry<String, Uint8List> p in readXlsxBytes(bytes).entries)
        (p.key, p.key == name ? utf8.encode(text) : p.value),
    ]);

/// [bytes] with the part [from] stored as [to], its relationship and
/// content type following.
Uint8List _renamedPart(Uint8List bytes, String from, String to) {
  final String fromTarget = from.substring('xl/'.length);
  final String toTarget = to.substring('xl/'.length);
  return buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> p in readXlsxBytes(bytes).entries)
      if (p.key == from)
        (to, p.value)
      else if (p.key == 'xl/_rels/workbook.xml.rels' ||
          p.key == '[Content_Types].xml')
        (
          p.key,
          utf8.encode(
            utf8
                .decode(p.value)
                .replaceAll('/$from"', '/$to"')
                .replaceAll('"$fromTarget"', '"$toTarget"'),
          ),
        )
      else
        (p.key, p.value),
  ]);
}
