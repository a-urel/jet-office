import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/sheet_protection.dart'
    show legacyPasswordHash;
import 'package:test/test.dart';

import '../support/read_xlsx.dart';

const String _sheet1 = 'xl/worksheets/sheet1.xml';

Matcher _argumentNamed(String name) => throwsA(
  isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name),
);

/// Sheet 1 of a workbook in which [setup] sets up the sheet `S`.
String _sheet(void Function(XlsxSheetWriter sheet) setup) {
  final XlsxWriter book = XlsxWriter();
  final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>['x']);
  setup(sheet);
  return readXlsx(book.close().bytes)[_sheet1]!;
}

String _protected(XlsxSheetProtection protection) =>
    _sheet((XlsxSheetWriter s) => s.protect(protection));

String _workbook(XlsxWorkbookProtection protection) {
  final XlsxWriter book = XlsxWriter();
  book.addSheet('S').row(<Object?>['x']);
  book.protectWorkbook(protection);
  return readXlsx(book.close().bytes)['xl/workbook.xml']!;
}

void main() {
  group('legacyPasswordHash', () {
    test('matches the known vectors', () {
      expect(legacyPasswordHash('password'), '83AF');
      expect(legacyPasswordHash('test'), 'CBEB');
      expect(legacyPasswordHash('a'), 'CE88');
      expect(legacyPasswordHash('abcdefghijklmno'), 'C6BC');
    });

    test('is always four uppercase hex digits', () {
      for (final String p in <String>['a', 'zz', '~~~~', ' ', 'Pa55 w0rd']) {
        expect(legacyPasswordHash(p), matches(RegExp(r'^[0-9A-F]{4}$')));
      }
    });
  });

  group('sheet protection', () {
    test('the default writes Excel\'s three flags after sheetData', () {
      final String xml = _protected(
        const XlsxSheetProtection(password: 'password'),
      );
      expect(
        xml,
        contains(
          '</sheetData><sheetProtection password="83AF" sheet="1" '
          'objects="1" scenarios="1"/>',
        ),
      );
    });

    test('precedes autoFilter (Quds wrote it after)', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        s
          ..autoFilter(XlsxRange.parse('A1:B1'))
          ..protect(const XlsxSheetProtection());
      });
      expect(
        xml,
        contains('<sheetProtection sheet="1" objects="1" scenarios="1"/>'),
      );
      expect(
        xml.indexOf('<sheetProtection'),
        lessThan(xml.indexOf('<autoFilter')),
      );
    });

    test('follows an empty sheetData too', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').protect(const XlsxSheetProtection());
      final String xml = readXlsx(book.close().bytes)[_sheet1]!;
      expect(xml, contains('<sheetData/><sheetProtection sheet="1"'));
    });

    test('a changed permission is written in schema order', () {
      final String xml = _protected(
        const XlsxSheetProtection(
          allowFormatColumns: true,
          allowSelectLockedCells: false,
        ),
      );
      expect(
        xml,
        contains(
          '<sheetProtection sheet="1" objects="1" scenarios="1" '
          'formatColumns="0" selectLockedCells="1"/>',
        ),
      );
    });

    test('allowing everything leaves only sheet and select flags', () {
      final String xml = _protected(
        const XlsxSheetProtection(
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
          allowSelectUnlockedCells: false,
        ),
      );
      expect(
        xml,
        contains(
          '<sheetProtection sheet="1" formatCells="0" formatColumns="0" '
          'formatRows="0" insertColumns="0" insertRows="0" '
          'insertHyperlinks="0" deleteColumns="0" deleteRows="0" sort="0" '
          'autoFilter="0" pivotTables="0" selectUnlockedCells="1"/>',
        ),
      );
    });

    test('without a password there is no password attribute', () {
      expect(
        _protected(const XlsxSheetProtection()),
        isNot(contains('password')),
      );
    });

    test('a later call replaces the earlier one', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        s
          ..protect(const XlsxSheetProtection(password: 'one'))
          ..protect(const XlsxSheetProtection(password: 'password'));
      });
      expect(RegExp('<sheetProtection').allMatches(xml), hasLength(1));
      expect(xml, contains('password="83AF"'));
    });

    test('after the sheet is finished it is a StateError', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('A')..row(<Object?>[1]);
      book.addSheet('B');
      expect(
        () => first.protect(const XlsxSheetProtection()),
        throwsStateError,
      );
    });
  });

  group('passwords', () {
    test('1 to 15 printable ASCII characters are accepted', () {
      for (final String p in <String>[' ', '~', 'a' * 15, 'Pa55 w0rd!']) {
        expect(
          () => _protected(XlsxSheetProtection(password: p)),
          returnsNormally,
          reason: p,
        );
      }
    });

    test('an invalid password names password and records nothing', () {
      for (final String p in <String>[
        '',
        'a' * 16,
        'café',
        'tab\t',
        '\u007f',
      ]) {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>[1]);
        sheet.protect(const XlsxSheetProtection(password: 'password'));
        expect(
          () => sheet.protect(XlsxSheetProtection(password: p)),
          _argumentNamed('password'),
          reason: p,
        );
        expect(
          readXlsx(book.close().bytes)[_sheet1],
          contains('password="83AF"'),
          reason: 'the earlier setting stays for "$p"',
        );
      }
    });

    test('a workbook password is checked the same way', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S');
      expect(
        () => book.protectWorkbook(const XlsxWorkbookProtection(password: '')),
        _argumentNamed('password'),
      );
      expect(
        () => book.protectWorkbook(
          const XlsxWorkbookProtection(password: '\u00e9'),
        ),
        _argumentNamed('password'),
      );
      expect(
        readXlsx(book.close().bytes)['xl/workbook.xml'],
        isNot(contains('workbookProtection')),
      );
    });
  });

  group('workbook protection', () {
    test('writes the hash and lockStructure before bookViews', () {
      final String xml = _workbook(
        const XlsxWorkbookProtection(password: 'test'),
      );
      expect(
        xml,
        contains(
          '<workbookProtection workbookPassword="CBEB" lockStructure="1"/>'
          '<bookViews>',
        ),
      );
    });

    test('lockWindows adds lockWindows', () {
      expect(
        _workbook(
          const XlsxWorkbookProtection(password: 'test', lockWindows: true),
        ),
        contains(
          '<workbookProtection workbookPassword="CBEB" lockStructure="1" '
          'lockWindows="1"/>',
        ),
      );
    });

    test('without a password or a lock nothing is written', () {
      expect(
        _workbook(const XlsxWorkbookProtection(lockStructure: false)),
        isNot(contains('workbookProtection')),
      );
      expect(
        _workbook(const XlsxWorkbookProtection()),
        contains('<workbookProtection lockStructure="1"/>'),
      );
    });

    test('a later call replaces the earlier one', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S');
      book
        ..protectWorkbook(const XlsxWorkbookProtection(password: 'a'))
        ..protectWorkbook(const XlsxWorkbookProtection(password: 'test'));
      final String xml = readXlsx(book.close().bytes)['xl/workbook.xml']!;
      expect(RegExp('<workbookProtection').allMatches(xml), hasLength(1));
      expect(xml, contains('workbookPassword="CBEB"'));
    });

    test('after close it is a StateError', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S');
      book.close();
      expect(
        () => book.protectWorkbook(const XlsxWorkbookProtection()),
        throwsStateError,
      );
    });
  });

  group('value types', () {
    test('compare by value and hash alike', () {
      expect(
        const XlsxSheetProtection(password: 'x', allowSort: true),
        const XlsxSheetProtection(password: 'x', allowSort: true),
      );
      expect(
        const XlsxSheetProtection(password: 'x').hashCode,
        const XlsxSheetProtection(password: 'x').hashCode,
      );
      expect(
        const XlsxSheetProtection(password: 'x'),
        isNot(const XlsxSheetProtection(password: 'y')),
      );
      expect(
        const XlsxSheetProtection(allowSort: true),
        isNot(const XlsxSheetProtection()),
      );
      expect(
        const XlsxWorkbookProtection(password: 'x', lockWindows: true),
        const XlsxWorkbookProtection(password: 'x', lockWindows: true),
      );
      expect(
        const XlsxWorkbookProtection(password: 'x'),
        isNot(const XlsxWorkbookProtection(password: 'x', lockWindows: true)),
      );
    });

    test('toString never prints the password', () {
      const XlsxSheetProtection sheet = XlsxSheetProtection(password: 'sekret');
      const XlsxWorkbookProtection book = XlsxWorkbookProtection(
        password: 'sekret',
      );
      expect(sheet.toString(), isNot(contains('sekret')));
      expect(book.toString(), isNot(contains('sekret')));
      expect(sheet.toString(), contains('password: ***'));
      expect(book.toString(), contains('password: ***'));
    });
  });
}
