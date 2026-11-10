import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:jet_office/src/xlsx/sheet_protection.dart'
    show legacyPasswordHash;
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

/// A package of the sheets [sheets] (name to worksheet XML) whose
/// `workbook.xml` holds [protection] (raw XML) before `<sheets>`.
Uint8List _package(Map<String, String> sheets, {String protection = ''}) {
  final Map<String, Uint8List> parts = readXlsxBytes(buildWorkbook(sheets));
  final String workbook = utf8.decode(parts['xl/workbook.xml']!);
  parts['xl/workbook.xml'] = Uint8List.fromList(
    utf8.encode(workbook.replaceFirst('<sheets>', '$protection<sheets>')),
  );
  return buildZip(<String, List<int>>{...parts});
}

String _worksheet(String body, {String data = '<sheetData/>'}) =>
    '<worksheet xmlns="$mainNs">$data$body</worksheet>';

String _sheetXml(XlsxWorkbook book, [int n = 1]) =>
    partText(book.save().bytes, 'xl/worksheets/sheet$n.xml');

String _workbookXml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/workbook.xml');

String _element(String xml, String name) =>
    RegExp('<(\\w+:)?$name[^>]*/>').firstMatch(xml)?.group(0) ?? '';

String _sheetProtection(XlsxWorkbook book) =>
    _element(_sheetXml(book), 'sheetProtection');

String _workbookProtection(XlsxWorkbook book) =>
    _element(_workbookXml(book), 'workbookProtection');

XlsxWorkbook _openSheet(String body) =>
    XlsxWorkbook.open(_package(<String, String>{'S': _worksheet(body)}));

XlsxWorkbook _openBook(String protection) => XlsxWorkbook.open(
  _package(<String, String>{'S': _worksheet('')}, protection: protection),
);

const String _hashedSheet =
    '<sheetProtection algorithmName="SHA-512" hashValue="HHH" '
    'saltValue="SSS" spinCount="100000" sheet="1" objects="1" '
    'scenarios="1"/>';

const String _hashedBook =
    '<workbookProtection workbookAlgorithmName="SHA-512" '
    'workbookHashValue="HHH" workbookSaltValue="SSS" '
    'workbookSpinCount="100000" lockStructure="1" '
    'revisionsAlgorithmName="SHA-512" revisionsHashValue="RRR" '
    'lockRevision="1"/>';

void main() {
  test('reads m3_protection', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_protection'));
    expect(
      book.sheet('Locked').protection,
      const XlsxSheetProtection(allowFormatColumns: true),
    );
    expect(book.sheet('Locked').hasStoredPassword, isTrue);
    expect(book.protection, const XlsxWorkbookProtection(lockStructure: true));
    expect(book.hasStoredPassword, isTrue);
    expect(book.warnings, isEmpty);
  });

  test('a sheet and a workbook without protection read null', () {
    final XlsxWorkbook book = _openSheet('');
    expect(book.sheets.single.protection, isNull);
    expect(book.sheets.single.hasStoredPassword, isFalse);
    expect(book.protection, isNull);
    expect(book.hasStoredPassword, isFalse);
  });

  group('set writes what the writer writes', () {
    const XlsxSheetProtection everything = XlsxSheetProtection(
      password: 'secret',
      allowSelectLockedCells: false,
      allowSelectUnlockedCells: false,
      allowFormatCells: true,
      allowFormatColumns: true,
      allowFormatRows: true,
      allowInsertColumns: true,
      allowInsertRows: true,
      allowInsertHyperlinks: true,
      allowDeleteColumns: true,
      allowDeleteRows: true,
      allowSort: true,
      allowAutoFilter: true,
      allowPivotTables: true,
      allowEditObjects: true,
      allowEditScenarios: true,
    );

    for (final (String, XlsxSheetProtection) c
        in <(String, XlsxSheetProtection)>[
          ('defaults', const XlsxSheetProtection()),
          ('a password', const XlsxSheetProtection(password: 'password')),
          ('everything', everything),
          (
            'some',
            const XlsxSheetProtection(allowSort: true, allowEditObjects: true),
          ),
        ]) {
      test('a sheet with ${c.$1}', () {
        final XlsxWriter writer = XlsxWriter();
        writer.addSheet('S').protect(c.$2);
        final String expected = _element(
          partText(writer.close().bytes, 'xl/worksheets/sheet1.xml'),
          'sheetProtection',
        );
        final XlsxWorkbook book = XlsxWorkbook();
        final XlsxSheet sheet = book.addSheet('S')..protection = c.$2;
        final String actual = _sheetProtection(book);
        expect(expected, isNotEmpty);
        expect(compareXml('s', expected, actual), isEmpty);
        expect(actual, expected);
        expect(sheet.protection, c.$2.password == null ? c.$2 : isNotNull);
        expect(
          sheet.protection?.password,
          isNull,
          reason: 'a password is never read back',
        );
        expect(sheet.hasStoredPassword, c.$2.password != null);
        expect(XlsxWorkbook.open(book.save().bytes).warnings, isEmpty);
      });
    }

    for (final (String, XlsxWorkbookProtection) c
        in <(String, XlsxWorkbookProtection)>[
          ('structure', const XlsxWorkbookProtection()),
          ('a password', const XlsxWorkbookProtection(password: 'test')),
          ('both locks', const XlsxWorkbookProtection(lockWindows: true)),
          (
            'windows only',
            const XlsxWorkbookProtection(
              lockStructure: false,
              lockWindows: true,
            ),
          ),
        ]) {
      test('a workbook with ${c.$1}', () {
        final XlsxWriter writer = XlsxWriter()
          ..addSheet('S')
          ..protectWorkbook(c.$2);
        final String expected = _element(
          partText(writer.close().bytes, 'xl/workbook.xml'),
          'workbookProtection',
        );
        final XlsxWorkbook book = XlsxWorkbook()..addSheet('S');
        book.protection = c.$2;
        final String actual = _workbookProtection(book);
        expect(expected, isNotEmpty);
        expect(compareXml('w', expected, actual), isEmpty);
        expect(actual, expected);
        expect(book.hasStoredPassword, c.$2.password != null);
      });
    }

    test('the sheet element goes after sheetData, before mergeCells', () {
      final XlsxWorkbook book = _openSheet(
        '<autoFilter ref="A1:B2"/><mergeCells count="1">'
        '<mergeCell ref="A1:B1"/></mergeCells><pageMargins left="1" '
        'right="1" top="1" bottom="1" header="0" footer="0"/>',
      );
      book.sheets.single.protection = const XlsxSheetProtection();
      expect(
        RegExp('<(\\w+)').allMatches(_sheetXml(book)).map((m) => m.group(1)),
        containsAllInOrder(<String>[
          'sheetData',
          'sheetProtection',
          'autoFilter',
          'mergeCells',
          'pageMargins',
        ]),
      );
    });

    test('the workbook element goes before bookViews', () {
      final XlsxWorkbook book = _openBook(
        '<bookViews><workbookView/></bookViews>',
      );
      book.protection = const XlsxWorkbookProtection();
      expect(
        _workbookXml(book).indexOf('<workbookProtection'),
        lessThan(_workbookXml(book).indexOf('<bookViews')),
      );
    });

    test('a prefixed worksheet keeps its namespace', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(<String, String>{
          'S': '<x:worksheet xmlns:x="$mainNs"><x:sheetData/></x:worksheet>',
        }),
      );
      book.sheets.single.protection = const XlsxSheetProtection(password: 'a');
      expect(_sheetXml(book), contains('<x:sheetProtection '));
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.protection,
        isNotNull,
      );
    });
  });

  group('a stored hash survives a flag change', () {
    test('on a sheet', () {
      final XlsxWorkbook book = _openSheet(_hashedSheet);
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.hasStoredPassword, isTrue);
      expect(sheet.protection?.password, isNull);
      expect(sheet.protection?.allowEditObjects, isFalse);
      sheet.protection = const XlsxSheetProtection(
        allowSort: true,
        allowEditObjects: false,
        allowEditScenarios: false,
      );
      final String xml = _sheetProtection(book);
      expect(xml, contains('algorithmName="SHA-512"'));
      expect(xml, contains('hashValue="HHH"'));
      expect(xml, contains('saltValue="SSS"'));
      expect(xml, contains('spinCount="100000"'));
      expect(xml, contains('sort="0"'));
      expect(xml, contains('objects="1"'));
      expect(sheet.hasStoredPassword, isTrue);
      expect(sheet.protection?.allowSort, isTrue);
    });

    test('on a workbook, and the revisions hash stays', () {
      final XlsxWorkbook book = _openBook(_hashedBook);
      expect(book.hasStoredPassword, isTrue);
      expect(book.protection?.password, isNull);
      expect(book.protection?.lockStructure, isTrue);
      book.protection = const XlsxWorkbookProtection(lockWindows: true);
      final String xml = _workbookProtection(book);
      expect(xml, contains('workbookAlgorithmName="SHA-512"'));
      expect(xml, contains('workbookHashValue="HHH"'));
      expect(xml, contains('workbookSaltValue="SSS"'));
      expect(xml, contains('workbookSpinCount="100000"'));
      expect(xml, contains('revisionsHashValue="RRR"'));
      expect(xml, contains('lockRevision="1"'));
      expect(xml, contains('lockStructure="1"'));
      expect(xml, contains('lockWindows="1"'));
    });

    test('a workbook with no lock keeps its element for the hash', () {
      final XlsxWorkbook book = _openBook(_hashedBook);
      book.protection = const XlsxWorkbookProtection(lockStructure: false);
      final String xml = _workbookProtection(book);
      expect(xml, contains('workbookHashValue="HHH"'));
      expect(xml, isNot(contains('lockStructure')));
      expect(book.hasStoredPassword, isTrue);
    });
  });

  group('a new password replaces the hash attributes', () {
    test('on a sheet', () {
      final XlsxWorkbook book = _openSheet(_hashedSheet);
      book.sheets.single.protection = const XlsxSheetProtection(
        password: 'abc',
      );
      final String xml = _sheetProtection(book);
      expect(xml, contains('password="${legacyPasswordHash('abc')}"'));
      for (final String gone in <String>[
        'algorithmName',
        'hashValue',
        'saltValue',
        'spinCount',
      ]) {
        expect(xml, isNot(contains(gone)), reason: gone);
      }
      expect(xml, contains('objects="1"'));
    });

    test('on a workbook, leaving the revisions attributes', () {
      final XlsxWorkbook book = _openBook(_hashedBook);
      book.protection = const XlsxWorkbookProtection(password: 'abc');
      final String xml = _workbookProtection(book);
      expect(xml, contains('workbookPassword="${legacyPasswordHash('abc')}"'));
      for (final String gone in <String>[
        'workbookAlgorithmName',
        'workbookHashValue',
        'workbookSaltValue',
        'workbookSpinCount',
      ]) {
        expect(xml, isNot(contains(gone)), reason: gone);
      }
      expect(xml, contains('revisionsAlgorithmName="SHA-512"'));
      expect(xml, contains('revisionsHashValue="RRR"'));
      expect(xml, contains('lockRevision="1"'));
    });

    test('replaces a legacy password', () {
      final XlsxWorkbook book = _openSheet(
        '<sheetProtection password="CC3D" sheet="1"/>',
      );
      book.sheets.single.protection = const XlsxSheetProtection(password: 'zz');
      expect(
        _sheetProtection(book),
        contains('password="${legacyPasswordHash('zz')}"'),
      );
    });
  });

  group('null removes the element', () {
    test('sheet, with a stored hash too', () {
      final XlsxWorkbook book = _openSheet(_hashedSheet);
      book.sheets.single.protection = null;
      expect(_sheetXml(book), isNot(contains('sheetProtection')));
      expect(book.sheets.single.protection, isNull);
      expect(book.sheets.single.hasStoredPassword, isFalse);
    });

    test('workbook', () {
      final XlsxWorkbook book = _openBook(_hashedBook);
      book.protection = null;
      expect(_workbookXml(book), isNot(contains('workbookProtection')));
      expect(book.protection, isNull);
    });

    test('a workbook with no lock and no password removes it', () {
      final XlsxWorkbook book = _openBook(
        '<workbookProtection lockStructure="1"/>',
      );
      book.protection = const XlsxWorkbookProtection(lockStructure: false);
      expect(_workbookXml(book), isNot(contains('workbookProtection')));
      // addSheet is a change: the log starts clean on the saved file.
      final XlsxWorkbook fresh = XlsxWorkbook.open(
        (XlsxWorkbook()..addSheet('S')).save().bytes,
      );
      fresh.protection = const XlsxWorkbookProtection(lockStructure: false);
      expect(_workbookXml(fresh), isNot(contains('workbookProtection')));
      expect(changeLogOf(fresh).hasChanges, isFalse);
    });

    test('nothing to remove changes nothing', () {
      final XlsxWorkbook book = _openSheet('');
      book.sheets.single.protection = null;
      book.protection = null;
      expect(changeLogOf(book).hasChanges, isFalse);
    });
  });

  group('sheet="0"', () {
    test('reads null and stays', () {
      final XlsxWorkbook book = _openSheet(
        '<sheetProtection sheet="0" sort="0" lockRevision="1"/>',
      );
      expect(book.sheets.single.protection, isNull);
      expect(book.sheets.single.hasStoredPassword, isFalse);
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_sheetProtection(book), contains('sheet="0"'));
    });

    test('an absent sheet attribute reads null', () {
      final XlsxWorkbook book = _openSheet('<sheetProtection sort="0"/>');
      expect(book.sheets.single.protection, isNull);
    });

    test('setting a protection edits that element', () {
      final XlsxWorkbook book = _openSheet(
        '<sheetProtection sheet="0" sort="0" password="CC3D"/>',
      );
      book.sheets.single.protection = const XlsxSheetProtection(
        allowSort: true,
      );
      final String xml = _sheetXml(book);
      expect('<sheetProtection'.allMatches(xml), hasLength(1));
      expect(xml, contains('sheet="1"'));
      expect(xml, contains('sort="0"'));
      expect(xml, contains('password="CC3D"'));
      expect(book.sheets.single.protection?.allowSort, isTrue);
    });
  });

  group('kept forms stay', () {
    test('a sheet re-set to what it reads is no edit', () {
      final XlsxWorkbook book = _openSheet(
        '<sheetProtection sheet="true" objects="0" scenarios="false" '
        'formatCells="1" sort="false" selectLockedCells="0"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      final XlsxSheetProtection read = sheet.protection!;
      expect(read.allowEditObjects, isTrue);
      expect(read.allowEditScenarios, isTrue);
      expect(read.allowFormatCells, isFalse);
      expect(read.allowSort, isTrue);
      expect(read.allowSelectLockedCells, isTrue);
      sheet.protection = read;
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_sheetProtection(book), contains('objects="0"'));
      expect(_sheetProtection(book), contains('sheet="true"'));
    });

    test('a changed flag changes only its own attribute', () {
      final XlsxWorkbook book = _openSheet(
        '<sheetProtection sheet="true" objects="0" sort="false" '
        'formatCells="1"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.protection = const XlsxSheetProtection(
        allowEditObjects: true,
        allowSort: true,
        allowFormatCells: true,
        allowInsertRows: true,
      );
      final String xml = _sheetProtection(book);
      expect(xml, contains('sheet="true"'));
      expect(xml, contains('objects="0"'));
      expect(xml, contains('sort="false"'));
      expect(xml, contains('formatCells="0"'));
      expect(xml, contains('insertRows="0"'));
    });

    test('a wanted default drops the attribute', () {
      final XlsxWorkbook book = _openSheet(
        '<sheetProtection sheet="1" objects="1" formatCells="0" '
        'selectLockedCells="1"/>',
      );
      book.sheets.single.protection = const XlsxSheetProtection(
        allowFormatCells: false,
        allowEditObjects: true,
        allowSelectLockedCells: true,
      );
      final String xml = _sheetProtection(book);
      expect(xml, isNot(contains('formatCells')));
      expect(xml, isNot(contains('selectLockedCells')));
      expect(xml, isNot(contains('objects="1"')));
    });

    test('a workbook re-set to what it reads is no edit', () {
      final XlsxWorkbook book = _openBook(
        '<workbookProtection lockStructure="true" lockWindows="0"/>',
      );
      book.protection = book.protection;
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_workbookProtection(book), contains('lockStructure="true"'));
      book.protection = const XlsxWorkbookProtection(lockWindows: true);
      expect(_workbookProtection(book), contains('lockStructure="true"'));
      expect(_workbookProtection(book), contains('lockWindows="1"'));
    });

    test('a bad boolean reads as its default', () {
      final XlsxWorkbook book = _openSheet(
        '<sheetProtection sheet="yes" objects="maybe"/>',
      );
      expect(book.sheets.single.protection, isNull);
      final XlsxWorkbook b2 = _openSheet(
        '<sheetProtection sheet="1" objects="maybe" sort="x"/>',
      );
      expect(b2.sheets.single.protection?.allowEditObjects, isTrue);
      expect(b2.sheets.single.protection?.allowSort, isFalse);
      final XlsxWorkbook b3 = _openBook(
        '<workbookProtection lockStructure="x"/>',
      );
      expect(b3.protection?.lockStructure, isFalse);
    });
  });

  group('a bad password throws; nothing changes', () {
    test('sheet', () {
      final XlsxWorkbook book = _openSheet(_hashedSheet);
      final Uint8List before = book.save().bytes;
      for (final String bad in <String>['', 'x' * 16, 'café']) {
        expect(
          () => book.sheets.single.protection = XlsxSheetProtection(
            password: bad,
            allowSort: true,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'password',
            ),
          ),
        );
      }
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });

    test('workbook', () {
      final XlsxWorkbook book = _openBook(_hashedBook);
      final Uint8List before = book.save().bytes;
      expect(
        () => book.protection = XlsxWorkbookProtection(password: 'x' * 16),
        throwsArgumentError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });
  });

  group('undo', () {
    test('a sheet protection and a workbook protection', () {
      final Uint8List input = _package(<String, String>{
        'S': _worksheet(_hashedSheet),
      }, protection: _hashedBook);
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        book.sheets.single.protection = const XlsxSheetProtection(
          password: 'abc',
        );
        book.protection = null;
      });
      expect(_sheetProtection(book), contains('password='));
      log.revertSet(set);
      expect(comparePackages(input, book.save().bytes), isEmpty);
      log.reapplySet(set);
      expect(_sheetProtection(book), contains('password='));
      expect(_workbookXml(book), isNot(contains('workbookProtection')));
    });

    test('a new element goes on undo', () {
      final XlsxWorkbook book = XlsxWorkbook();
      book.addSheet('S');
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        book.sheets.single.protection = const XlsxSheetProtection();
        book.protection = const XlsxWorkbookProtection();
      });
      log.revertSet(set);
      expect(_sheetXml(book), isNot(contains('sheetProtection')));
      expect(_workbookXml(book), isNot(contains('workbookProtection')));
    });
  });

  test('a repeated element stays and is not typed', () {
    final XlsxWorkbook book = _openSheet(
      '<sheetProtection sheet="1"/><sheetProtection sheet="1" sort="0"/>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(
      sheet.protection,
      const XlsxSheetProtection(
        allowEditObjects: true,
        allowEditScenarios: true,
      ),
    );
    sheet.protection = const XlsxSheetProtection(allowSort: true);
    final String xml = _sheetXml(book);
    expect('<sheetProtection'.allMatches(xml), hasLength(2));
    expect(xml, contains('<sheetProtection sheet="1" sort="0"/>'));
  });
}
