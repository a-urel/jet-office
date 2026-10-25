import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

XlsxWriter _book() => XlsxWriter();

String _workbook(XlsxWriter book) =>
    readXlsx(book.close().bytes)['xl/workbook.xml']!;

void main() {
  group('XlsxDefinedName', () {
    test('has value equality and a toString', () {
      expect(
        const XlsxDefinedName('A', '=1', hidden: true, comment: 'c'),
        const XlsxDefinedName('A', '=1', hidden: true, comment: 'c'),
      );
      expect(
        const XlsxDefinedName('A', '=1').hashCode,
        const XlsxDefinedName('A', '=1').hashCode,
      );
      expect(
        const XlsxDefinedName('A', '=1'),
        isNot(const XlsxDefinedName('A', '=2')),
      );
      expect(const XlsxDefinedName('A', '=1').toString(), contains('A'));
    });
  });

  group('name rules', () {
    test('valid names are accepted', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      for (final String name in <String>[
        'Total',
        '_tax',
        r'\path',
        'Şube.Gelir',
        'A1B',
        'XFE1',
      ]) {
        book.defineName(XlsxDefinedName(name, '1'));
      }
      expect(_workbook(book), contains('<definedName name="Şube.Gelir">1<'));
    });

    test('invalid names throw ArgumentError and record nothing', () {
      for (final String name in <String>[
        '',
        '1st',
        'My Name',
        'A1',
        'a1',
        'XFD1048576',
        'R1C1',
        'r2c3',
        'RC',
        'R',
        'c',
        'C',
        '_xlnm.Print_Area',
        '_XLNM.x',
        'a' * 256,
        'a-b',
      ]) {
        final XlsxWriter book = _book();
        book.addSheet('S');
        expect(
          () => book.defineName(XlsxDefinedName(name, '1')),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'name',
            ),
          ),
          reason: 'name "$name"',
        );
        expect(_workbook(book), isNot(contains('definedName')));
      }
    });

    test('a name of 255 characters is accepted', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      book.defineName(XlsxDefinedName('a' * 255, '1'));
      expect(_workbook(book), contains('name="${'a' * 255}"'));
    });

    test('the comment is limited to 255 characters', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      book.defineName(XlsxDefinedName('Ok', '1', comment: 'c' * 255));
      expect(
        () => book.defineName(XlsxDefinedName('Bad', '1', comment: 'c' * 256)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'comment',
          ),
        ),
      );
      expect(
        () => book.defineName(
          const XlsxDefinedName('Bad', '1', comment: 'a\u0001'),
        ),
        throwsArgumentError,
      );
    });

    test('the formula is checked like other formula text', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      for (final String formula in <String>['', '=', '1' * 8193, 'A\u0001']) {
        expect(
          () => book.defineName(XlsxDefinedName('F', formula)),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'formula',
            ),
          ),
        );
      }
      expect(_workbook(book), isNot(contains('definedName')));
    });

    test('writes the formula without its =, hidden and comment', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      book.defineName(
        const XlsxDefinedName(
          'Rate',
          '=0.18&"<x>"',
          hidden: true,
          comment: 'a "b" & _x0041_',
        ),
      );
      expect(
        _workbook(book),
        contains(
          '<definedNames><definedName name="Rate" '
          'comment="a &quot;b&quot; &amp; _x005F_x0041_" hidden="1">'
          '0.18&amp;"&lt;x&gt;"</definedName></definedNames>',
        ),
      );
    });

    test('the formula is escaped like <f> text', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      book.defineName(const XlsxDefinedName('X', '"_x0041_"'));
      expect(_workbook(book), contains('>"_x005F_x0041_"</definedName>'));
    });
  });

  group('uniqueness', () {
    test('a workbook name twice, ignoring case, names both', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      book.defineName(const XlsxDefinedName('Total', '1'));
      expect(
        () => book.defineName(const XlsxDefinedName('TOTAL', '2')),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            allOf(contains('TOTAL'), contains('Total')),
          ),
        ),
      );
      final String wb = _workbook(book);
      expect(wb, contains('<definedName name="Total">1</definedName>'));
      expect(wb, isNot(contains('TOTAL')));
    });

    test('a sheet name twice on one sheet throws, the first stays', () {
      final XlsxWriter book = _book();
      final XlsxSheetWriter s = book.addSheet('S');
      s.defineName(const XlsxDefinedName('Local', r'S!$A$1'));
      expect(
        () => s.defineName(const XlsxDefinedName('local', r'S!$A$2')),
        throwsArgumentError,
      );
      final String wb = _workbook(book);
      expect(wb, contains(r'>S!$A$1<'));
      expect(wb, isNot(contains(r'S!$A$2')));
    });

    test('the same name in the workbook and on a sheet is allowed', () {
      final XlsxWriter book = _book();
      final XlsxSheetWriter s = book.addSheet('S');
      book.defineName(const XlsxDefinedName('Total', '1'));
      s.defineName(const XlsxDefinedName('Total', '2'));
      book.addSheet('T').defineName(const XlsxDefinedName('Total', '3'));
      final XlsxResult out = book.close();
      expect(checkXlsx(out.bytes), isEmpty);
      final String wb = readXlsx(out.bytes)['xl/workbook.xml']!;
      expect(
        wb,
        contains(
          '<definedName name="Total">1</definedName>'
          '<definedName name="Total" localSheetId="0">2</definedName>'
          '<definedName name="Total" localSheetId="1">3</definedName>',
        ),
      );
    });
  });

  group('order and scope', () {
    test('workbook names, then per tab: filter, area, titles, names', () {
      final XlsxWriter book = _book();
      final XlsxSheetWriter a = book.addSheet('A');
      a
        ..defineName(const XlsxDefinedName('Mine', r'A!$A$1'))
        ..printTitles(rows: (0, 0))
        ..printArea(<XlsxRange>[XlsxRange.parse('A1:B2')])
        ..autoFilter(XlsxRange.parse('A1:B2'));
      book.defineName(const XlsxDefinedName('Zed', '1'));
      book.defineName(const XlsxDefinedName('Alpha', '2'));
      final XlsxSheetWriter b = book.addSheet('B', position: 0);
      b.defineName(const XlsxDefinedName('OnB', '3'));
      book.defineName(const XlsxDefinedName('Late', '4'));
      final String wb = _workbook(book);
      final List<String> names = <String>[
        for (final RegExpMatch m in RegExp(
          r'<definedName name="([^"]+)"(?: localSheetId="(\d)")?',
        ).allMatches(wb))
          '${m.group(1)}@${m.group(2) ?? '-'}',
      ];
      expect(names, <String>[
        'Zed@-',
        'Alpha@-',
        'Late@-',
        'OnB@0',
        '_xlnm._FilterDatabase@1',
        '_xlnm.Print_Area@1',
        '_xlnm.Print_Titles@1',
        'Mine@1',
      ]);
    });

    test('a sheet name keeps its localSheetId after a front sheet', () {
      final XlsxWriter book = _book();
      book.addSheet('Data').defineName(const XlsxDefinedName('L', '1'));
      book.addSheet('Front', position: 0);
      expect(
        _workbook(book),
        contains('<definedName name="L" localSheetId="1">1</definedName>'),
      );
    });

    test('a workbook name is allowed until close()', () {
      final XlsxWriter book = _book();
      book.addSheet('S');
      book.addSheet('T');
      book.defineName(const XlsxDefinedName('Late', '1'));
      book.close();
      expect(
        () => book.defineName(const XlsxDefinedName('Later', '1')),
        throwsStateError,
      );
    });
  });

  group('print area', () {
    test('quotes the sheet and scopes it by localSheetId', () {
      final XlsxWriter book = _book();
      book.addSheet('First');
      book.addSheet("O'Brien").printArea(<XlsxRange>[
        XlsxRange.parse('A1:D20'),
        XlsxRange.parse('F1:G5'),
      ]);
      final XlsxResult out = book.close();
      expect(
        readXlsx(out.bytes)['xl/workbook.xml'],
        contains(
          '<definedName name="_xlnm.Print_Area" localSheetId="1">'
          r"'O''Brien'!$A$1:$D$20,'O''Brien'!$F$1:$G$5</definedName>",
        ),
      );
      expect(checkXlsx(out.bytes), isEmpty);
    });

    test('a sheet name that needs escaping or was renamed', () {
      final XlsxWriter book = _book();
      book.addSheet('_x0041_').printArea(<XlsxRange>[const XlsxRange(0, 0)]);
      final XlsxSheetWriter renamed = book.addSheet('a/b');
      renamed.printArea(<XlsxRange>[const XlsxRange(0, 0, 1, 1)]);
      final String wb = _workbook(book);
      expect(wb, contains(r">'_x005F_x0041_'!$A$1</definedName>"));
      expect(renamed.name, isNot('a/b'));
      expect(wb, contains(">'${renamed.name}'!\$A\$1:\$B\$2</definedName>"));
    });

    test('a later call replaces the earlier one', () {
      final XlsxWriter book = _book();
      book.addSheet('S')
        ..printArea(<XlsxRange>[XlsxRange.parse('A1:B2')])
        ..printArea(<XlsxRange>[XlsxRange.parse('C3:D4')]);
      final String wb = _workbook(book);
      expect(wb, contains(r"'S'!$C$3:$D$4"));
      expect(wb, isNot(contains(r"'S'!$A$1")));
    });

    test('an empty list or a range outside the sheet throws', () {
      final XlsxWriter book = _book();
      final XlsxSheetWriter s = book.addSheet('S')
        ..printArea(<XlsxRange>[XlsxRange.parse('A1:B2')]);
      expect(() => s.printArea(<XlsxRange>[]), throwsArgumentError);
      expect(
        () => s.printArea(<XlsxRange>[
          XlsxRange.parse('A1'),
          const XlsxRange(0, 0, 1048576, 0),
        ]),
        throwsArgumentError,
      );
      expect(
        () => s.printArea(<XlsxRange>[const XlsxRange(3, 3, 1, 1)]),
        throwsArgumentError,
      );
      // Atomic: the earlier area is in force.
      expect(_workbook(book), contains(r"'S'!$A$1:$B$2"));
    });
  });

  group('print titles', () {
    test('columns first, as Excel writes them, absolute and quoted', () {
      final XlsxWriter book = _book();
      book.addSheet('S').printTitles(rows: (0, 0), columns: (0, 1));
      expect(
        _workbook(book),
        contains(
          '<definedName name="_xlnm.Print_Titles" localSheetId="0">'
          r"'S'!$A:$B,'S'!$1:$1</definedName>",
        ),
      );
    });

    test('rows only and columns only', () {
      final XlsxWriter book = _book();
      book.addSheet("O'B").printTitles(rows: (1, 3));
      book.addSheet('T').printTitles(columns: (26, 27));
      final String wb = _workbook(book);
      expect(wb, contains(r">'O''B'!$2:$4</definedName>"));
      expect(wb, contains(r">'T'!$AA:$AB</definedName>"));
    });

    test('regression: Quds wrote relative, unquoted titles', () {
      final XlsxWriter book = _book();
      book.addSheet('My Sheet').printTitles(rows: (0, 0));
      final String wb = _workbook(book);
      expect(wb, contains(r">'My Sheet'!$1:$1<"));
      expect(wb, isNot(contains(r'>My Sheet!1:1<')));
    });

    test('no arguments clears the titles', () {
      final XlsxWriter book = _book();
      book.addSheet('S')
        ..printTitles(rows: (0, 0))
        ..printTitles();
      expect(_workbook(book), isNot(contains('Print_Titles')));
    });

    test('a bad span throws naming rows or columns, records nothing', () {
      final XlsxWriter book = _book();
      final XlsxSheetWriter s = book.addSheet('S')..printTitles(rows: (0, 1));
      for (final (int, int) bad in <(int, int)>[
        (-1, 0),
        (2, 1),
        (0, 1048576),
      ]) {
        expect(
          () => s.printTitles(rows: bad),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'rows',
            ),
          ),
        );
      }
      for (final (int, int) bad in <(int, int)>[(-1, 0), (2, 1), (0, 16384)]) {
        expect(
          () => s.printTitles(rows: (5, 6), columns: bad),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'columns',
            ),
          ),
        );
      }
      expect(_workbook(book), contains(r"'S'!$1:$2"));
    });

    test('the last row and column are accepted', () {
      final XlsxWriter book = _book();
      book.addSheet('S').printTitles(rows: (0, 1048575), columns: (0, 16383));
      expect(_workbook(book), contains(r"'S'!$A:$XFD,'S'!$1:$1048576"));
    });
  });

  group('after the sheet is finished', () {
    test('defineName, printArea and printTitles throw StateError', () {
      final XlsxWriter book = _book();
      final XlsxSheetWriter s = book.addSheet('S');
      book.addSheet('T');
      expect(
        () => s.defineName(const XlsxDefinedName('X', '1')),
        throwsStateError,
      );
      expect(
        () => s.printArea(<XlsxRange>[XlsxRange.parse('A1')]),
        throwsStateError,
      );
      expect(() => s.printTitles(rows: (0, 0)), throwsStateError);
      expect(_workbook(book), isNot(contains('definedName')));
    });
  });

  group('with a filter', () {
    test('the filter name still comes from the one writer', () {
      final XlsxWriter book = _book();
      book.addSheet('F')
        ..row(<Object?>[1, 2])
        ..autoFilter(XlsxRange.parse('A1:B2'));
      final XlsxResult out = book.close();
      expect(
        readXlsx(out.bytes)['xl/workbook.xml'],
        contains(
          '<definedNames><definedName name="_xlnm._FilterDatabase" '
          'localSheetId="0" hidden="1">'
          r"'F'!$A$1:$B$2</definedName></definedNames>",
        ),
      );
      expect(checkXlsx(out.bytes), isEmpty);
    });
  });
}
