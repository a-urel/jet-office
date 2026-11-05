import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart'
    show setSheetAutoFilter;
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
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
/// `workbook.xml` holds [names] (raw `<definedNames>`) after `<sheets>`.
Uint8List _package(Map<String, String> sheets, {String names = ''}) {
  final Map<String, Uint8List> parts = readXlsxBytes(buildWorkbook(sheets));
  final String workbook = utf8.decode(parts['xl/workbook.xml']!);
  parts['xl/workbook.xml'] = Uint8List.fromList(
    utf8.encode(workbook.replaceFirst('</sheets>', '</sheets>$names')),
  );
  return buildZip(<String, List<int>>{...parts});
}

String _worksheet(String body, {String data = '<sheetData/>'}) =>
    '<worksheet xmlns="$mainNs">$data$body</worksheet>';

String _workbookXml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/workbook.xml');

String _sheetXml(XlsxWorkbook book, [int n = 1]) =>
    partText(book.save().bytes, 'xl/worksheets/sheet$n.xml');

String _namesXml(String xml) =>
    RegExp(
      '<definedNames[^>]*/>|<definedNames[ >].*?</definedNames>',
    ).firstMatch(xml)?.group(0) ??
    '';

String _filterXml(String xml) =>
    RegExp(
      '<autoFilter[^>]*/>|<autoFilter[ >].*?</autoFilter>',
    ).firstMatch(xml)?.group(0) ??
    '';

XlsxRange _r(String ref) => XlsxRange.parse(ref);

int _invalid(XlsxWorkbook book) => book.warnings
    .where((XlsxWarning w) => w.code == XlsxWarningCode.featureEntryInvalid)
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

void main() {
  test('reads the print area and titles of m3_names', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_names'));
    final XlsxSheet sheet = book.sheet("O'Brien");
    expect(sheet.printArea, <XlsxRange>[_r('A1:B4'), _r('D1:D3')]);
    expect(sheet.printTitles, (rows: (0, 0), columns: (0, 0)));
    expect(book.sheet('Data').printArea, isEmpty);
    expect(book.sheet('Data').printTitles, (rows: null, columns: null));
    expect(
      () => sheet.printArea.add(_r('A1')),
      throwsA(anything),
      reason: 'unmodifiable',
    );
    expect(book.warnings, isEmpty);
    expect(book.sheet("O'Brien").autoFilter, isNull);
  });

  test('reads the filter of m2_merges_filter', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m2_merges_filter'));
    expect(book.sheet("Bob's Data").autoFilter, _r('A6:D20'));
    expect(book.sheet('Plain').autoFilter, isNull);
    expect(book.warnings, isEmpty);
  });

  test('set each, and the names are the writer\'s', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('S')
      ..autoFilter(_r('A1:C3'))
      ..printArea(<XlsxRange>[_r('A1:B4'), _r('D1:D3')])
      ..printTitles(rows: (0, 1), columns: (0, 0));
    final Uint8List expected = writer.close().bytes;

    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S')
      ..autoFilter = _r('A1:C3')
      ..printArea = <XlsxRange>[_r('A1:B4'), _r('D1:D3')]
      ..setPrintTitles(rows: (0, 1), columns: (0, 0));
    expect(
      _namesXml(_workbookXml(book)),
      _namesXml(partText(expected, 'xl/workbook.xml')),
    );
    expect(
      _filterXml(_sheetXml(book)),
      _filterXml(partText(expected, 'xl/worksheets/sheet1.xml')),
    );
    expect(
      compareXml(
        'xl/workbook.xml',
        _namesXml(partText(expected, 'xl/workbook.xml')),
        _namesXml(_workbookXml(book)),
      ),
      isEmpty,
    );
    expect(sheet.autoFilter, _r('A1:C3'));
    expect(sheet.printArea, <XlsxRange>[_r('A1:B4'), _r('D1:D3')]);
    expect(sheet.printTitles, (rows: (0, 1), columns: (0, 0)));

    final XlsxWorkbook reopened = XlsxWorkbook.open(book.save().bytes);
    expect(reopened.sheet('S').autoFilter, _r('A1:C3'));
    expect(reopened.sheet('S').printArea.length, 2);
    expect(reopened.sheet('S').printTitles, (rows: (0, 1), columns: (0, 0)));
    expect(reopened.warnings, isEmpty);
  });

  test('clear each; the group and the element go with the last', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S')
      ..autoFilter = _r('A1:C3')
      ..printArea = <XlsxRange>[_r('A1:B4')]
      ..setPrintTitles(rows: (0, 0));
    sheet.printArea = const <XlsxRange>[];
    expect(_namesXml(_workbookXml(book)), isNot(contains('Print_Area')));
    expect(_namesXml(_workbookXml(book)), contains('Print_Titles'));
    sheet.setPrintTitles();
    expect(_namesXml(_workbookXml(book)), isNot(contains('Print_Titles')));
    expect(_namesXml(_workbookXml(book)), contains('_FilterDatabase'));
    sheet.autoFilter = null;
    expect(_workbookXml(book), isNot(contains('definedNames')));
    expect(_sheetXml(book), isNot(contains('autoFilter')));
    expect(sheet.autoFilter, isNull);
    expect(sheet.printArea, isEmpty);
    expect(sheet.printTitles, (rows: null, columns: null));
  });

  test('a sheet name that needs quoting', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet("O'Brien")
      ..printArea = <XlsxRange>[_r('A1:B4')]
      ..setPrintTitles(rows: (0, 0), columns: (1, 2))
      ..autoFilter = _r('A1:B4');
    final String names = _namesXml(_workbookXml(book));
    expect(names, contains("'O''Brien'!\$A\$1:\$B\$4</definedName>"));
    expect(
      names,
      contains("'O''Brien'!\$B:\$C,'O''Brien'!\$1:\$1</definedName>"),
    );
    final XlsxSheet again = XlsxWorkbook.open(book.save().bytes).sheets.single;
    expect(again.printArea, sheet.printArea);
    expect(again.printTitles, (rows: (0, 0), columns: (1, 2)));
    expect(again.autoFilter, _r('A1:B4'));
  });

  test('a changed name is replaced in place', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_names'));
    book.sheet("O'Brien").printArea = <XlsxRange>[_r('A1:C2')];
    final String names = _namesXml(_workbookXml(book));
    expect(
      names,
      '<definedNames><definedName name="TaxRate">0.18</definedName>'
      '<definedName name="Local" localSheetId="0">Data!\$B\$2'
      '</definedName>'
      '<definedName name="_xlnm.Print_Area" localSheetId="1">'
      "'O''Brien'!\$A\$1:\$C\$2</definedName>"
      '<definedName name="_xlnm.Print_Titles" localSheetId="1">'
      "'O''Brien'!\$A:\$A,'O''Brien'!\$1:\$1</definedName>"
      '</definedNames>',
    );
  });

  test('a filter over a table throws; nothing changes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_tables'));
    final XlsxSheet sheet = book.sheet('Sales');
    // Loaded, so that both saves are written from the model.
    expect(sheet.autoFilter, isNull);
    final String workbookBefore = _workbookXml(book);
    final String sheetBefore = _sheetXml(book);
    expect(
      () => sheet.autoFilter = _r('B2:D3'),
      throwsA(
        isA<ArgumentError>()
            .having((ArgumentError e) => e.name, 'name', 'range')
            .having(
              (ArgumentError e) => e.message,
              'message',
              allOf(contains('B2:D3'), contains('Sales')),
            ),
      ),
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_workbookXml(book), workbookBefore);
    expect(_sheetXml(book), sheetBefore);
    expect(sheet.autoFilter, isNull);
    // Beside the table is fine.
    sheet.autoFilter = _r('H1:I3');
    expect(sheet.autoFilter, _r('H1:I3'));
  });

  test('a range outside the sheet or a bad span throws; nothing changes', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S');
    final String before = _workbookXml(book);
    expect(
      () => sheet.printArea = <XlsxRange>[
        _r('A1:B2'),
        const XlsxRange(0, 0, 0, 16384),
      ],
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'ranges[1]',
        ),
      ),
    );
    expect(
      () => sheet.setPrintTitles(rows: (3, 1)),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'rows',
        ),
      ),
    );
    expect(
      () => sheet.setPrintTitles(rows: (0, 0), columns: (0, 16384)),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'columns',
        ),
      ),
    );
    expect(
      () => sheet.autoFilter = const XlsxRange(2, 2, 1, 1),
      throwsArgumentError,
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_workbookXml(book), before);
  });

  test('rows a filter hid stay hidden when it narrows and when it goes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(<String, String>{
        'S': _worksheet(
          '<autoFilter ref="A1:D10"/>',
          data:
              '<sheetData><row r="1"><c r="A1"><v>1</v></c></row>'
              '<row r="2" hidden="1"><c r="A2"><v>2</v></c></row>'
              '</sheetData>',
        ),
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.rowFormat(1).hidden, isTrue);
    sheet.autoFilter = _r('A1:B10');
    expect(sheet.rowFormat(1).hidden, isTrue);
    expect(_sheetXml(book), contains('hidden="1"'));
    sheet.autoFilter = null;
    expect(_filterXml(_sheetXml(book)), isEmpty);
    expect(sheet.rowFormat(1).hidden, isTrue);
    expect(
      XlsxWorkbook.open(book.save().bytes).sheets.single.rowFormat(1).hidden,
      isTrue,
    );
  });

  group('narrowing a filter', () {
    const String filter =
        '<autoFilter ref="A1:D10" x="1">'
        '<filterColumn colId="0"><filters><filter val="a"/></filters>'
        '</filterColumn>'
        '<filterColumn colId="2" hiddenButton="1"/>'
        '<filterColumn colId="3"/>'
        '<filterColumn colId="x"/>'
        '<sortState ref="A2:D10"/>'
        '</autoFilter>';

    XlsxWorkbook open() =>
        XlsxWorkbook.open(_package(<String, String>{'S': _worksheet(filter)}));

    test('keeps the filter columns inside it', () {
      final XlsxWorkbook book = open();
      book.sheets.single.autoFilter = _r('A1:C10');
      expect(
        _filterXml(_sheetXml(book)),
        '<autoFilter ref="A1:C10" x="1">'
        '<filterColumn colId="0"><filters><filter val="a"/></filters>'
        '</filterColumn>'
        '<filterColumn colId="2" hiddenButton="1"/>'
        '</autoFilter>',
      );
      expect(
        _namesXml(_workbookXml(book)),
        contains('\'S\'!\$A\$1:\$C\$10</definedName>'),
      );
    });

    test('drops every child when the first column moves', () {
      final XlsxWorkbook book = open();
      book.sheets.single.autoFilter = _r('B1:D10');
      expect(_filterXml(_sheetXml(book)), '<autoFilter ref="B1:D10" x="1"/>');
    });

    test('widening keeps the filter columns; the rest goes', () {
      final XlsxWorkbook book = open();
      book.sheets.single.autoFilter = _r('A1:F20');
      expect(
        _filterXml(_sheetXml(book)),
        '<autoFilter ref="A1:F20" x="1">'
        '<filterColumn colId="0"><filters><filter val="a"/></filters>'
        '</filterColumn>'
        '<filterColumn colId="2" hiddenButton="1"/>'
        '<filterColumn colId="3"/>'
        '</autoFilter>',
      );
    });

    test('undo puts the element and the name back', () {
      final Uint8List input = _package(
        <String, String>{'S': _worksheet(filter)},
        names:
            '<definedNames><definedName name="_xlnm._FilterDatabase" '
            'localSheetId="0" hidden="1">\'S\'!\$A\$1:\$D\$10</definedName>'
            '</definedNames>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => book.sheets.single.autoFilter = _r('A1:B5'),
      );
      expect(_filterXml(_sheetXml(book)), contains('A1:B5'));
      log.revertSet(set);
      expect(comparePackages(input, book.save().bytes), isEmpty);
      log.reapplySet(set);
      expect(_filterXml(_sheetXml(book)), contains('A1:B5'));
    });
  });

  test('a failure in the second part leaves the first as it was', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S')..autoFilter = _r('A1:B2');
    final Uint8List before = book.save().bytes;
    final ChangeLog log = changeLogOf(book);
    final bool hadChanges = log.hasChanges;
    expect(
      () => setSheetAutoFilter(
        sheet,
        _r('C1:D4'),
        afterName: () => throw StateError('boom'),
      ),
      throwsStateError,
    );
    expect(log.hasChanges, hadChanges);
    expect(comparePackages(before, book.save().bytes), isEmpty);
    expect(sheet.autoFilter, _r('A1:B2'));
    expect(_namesXml(_workbookXml(book)), contains('\$A\$1:\$B\$2'));
    expect(
      () => setSheetAutoFilter(
        sheet,
        null,
        afterName: () => throw StateError('boom'),
      ),
      throwsStateError,
    );
    expect(comparePackages(before, book.save().bytes), isEmpty);
  });

  group('bad values', () {
    const String names =
        '<definedNames count="3">'
        '<definedName name="_xlnm.Print_Area" localSheetId="0">'
        'OFFSET(S!\$A\$1,0,0)</definedName>'
        '<definedName name="_xlnm.Print_Titles" localSheetId="0">'
        '#REF!</definedName>'
        '<definedName name="_xlnm.Print_Area" localSheetId="1">'
        '\$A\$1:\$B\$2</definedName>'
        '</definedNames>';

    XlsxWorkbook open() => XlsxWorkbook.open(
      _package(<String, String>{
        'S': _worksheet('<autoFilter ref="A1:ZZZZ99999999"/>'),
        'T': _worksheet(''),
      }, names: names),
    );

    test('are kept and reported once', () {
      final XlsxWorkbook book = open();
      final XlsxSheet sheet = book.sheets.first;
      expect(sheet.printArea, isEmpty);
      expect(sheet.printTitles, (rows: null, columns: null));
      expect(sheet.autoFilter, isNull);
      expect(_invalid(book), 3);
      // Read again: nothing new.
      sheet
        ..printArea
        ..printTitles
        ..autoFilter;
      expect(_invalid(book), 3);
      for (final XlsxWarning w in book.warnings) {
        expect(w.code, XlsxWarningCode.featureEntryInvalid);
      }
      // Another sheet's name for this sheet is not this sheet's.
      expect(book.sheets.last.printArea, isEmpty);
      expect(_namesXml(_workbookXml(book)), names);
      expect(
        _filterXml(_sheetXml(book)),
        '<autoFilter ref="A1:ZZZZ99999999"/>',
      );
    });

    test('setting replaces them', () {
      final XlsxWorkbook book = open();
      final XlsxSheet sheet = book.sheets.first;
      sheet.printArea = <XlsxRange>[_r('A1:B2')];
      sheet.setPrintTitles(rows: (0, 0));
      sheet.autoFilter = _r('A1:C3');
      final String xml = _namesXml(_workbookXml(book));
      expect(xml, isNot(contains('OFFSET')));
      expect(xml, isNot(contains('#REF!')));
      expect(
        xml.indexOf('Print_Area'),
        lessThan(xml.indexOf('Print_Titles')),
        reason: 'in place',
      );
      expect(sheet.printArea, <XlsxRange>[_r('A1:B2')]);
      expect(sheet.printTitles, (rows: (0, 0), columns: null));
      expect(sheet.autoFilter, _r('A1:C3'));
      expect(_filterXml(_sheetXml(book)), '<autoFilter ref="A1:C3"/>');
    });
  });

  test('plain references of this sheet read, in any form Excel writes', () {
    const String names =
        '<definedNames>'
        '<definedName name="_xlnm.Print_Area" localSheetId="0">'
        "S!A1:B2,'s'!\$D\$1</definedName>"
        '<definedName name="_XLNM.PRINT_TITLES" localSheetId="0">'
        "S!\$1:\$2,'S'!\$C:\$D</definedName>"
        '</definedNames>';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(<String, String>{'S': _worksheet('')}, names: names),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.printArea, <XlsxRange>[_r('A1:B2'), _r('D1')]);
    expect(sheet.printTitles, (rows: (0, 1), columns: (2, 3)));
    expect(book.warnings, isEmpty);
    // The same value set back is no edit.
    final ChangeLog log = changeLogOf(book);
    sheet
      ..printArea = <XlsxRange>[_r('A1:B2'), _r('D1')]
      ..setPrintTitles(rows: (0, 1), columns: (2, 3));
    expect(log.hasChanges, isFalse);
  });

  group('a sheet that is not a worksheet', () {
    XlsxWorkbook chart() => XlsxWorkbook.open(
      buildWorkbook(<String, String?>{'C': '<chartsheet xmlns="$mainNs"/>'}),
    );
    XlsxWorkbook partless() =>
        XlsxWorkbook.open(buildWorkbook(<String, String?>{'P': null}));

    for (final (String name, XlsxWorkbook Function() open)
        in <(String, XlsxWorkbook Function())>[
          ('a chartsheet', chart),
          ('a sheet without a part', partless),
        ]) {
      test('$name takes no print area or titles', () {
        final XlsxWorkbook book = open();
        final XlsxSheet sheet = book.sheets.single;
        expect(
          () => sheet.printArea = <XlsxRange>[_r('A1:B2')],
          throwsStateError,
        );
        expect(() => sheet.setPrintTitles(rows: (0, 0)), throwsStateError);
        expect(changeLogOf(book).hasChanges, isFalse);
        expect(_workbookXml(book), isNot(contains('definedName')));
      });
    }

    test('a bad range is still an ArgumentError', () {
      final XlsxSheet sheet = chart().sheets.single;
      expect(() => sheet.setPrintTitles(rows: (2, 1)), throwsArgumentError);
    });
  });

  group('a changed name keeps what it does not type', () {
    const String kept =
        'publishToServer="1" description="kept" xr:uid="{1}" '
        'xmlns:xr="urn:xr"';

    Uint8List file(String name, String formula, {String hidden = ''}) =>
        _package(
          <String, String>{'S': _worksheet('<autoFilter ref="A1:B2"/>')},
          names:
              '<definedNames><definedName name="$name" localSheetId="0" '
              '$hidden$kept>$formula</definedName></definedNames>',
        );

    void keeps(String xml) {
      expect(xml, contains('publishToServer="1"'));
      expect(xml, contains('description="kept"'));
      expect(xml, contains('xr:uid="{1}"'));
      expect(xml, contains('xmlns:xr="urn:xr"'));
    }

    test('a print area', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        file('_xlnm.Print_Area', r'S!$A$1:$B$2'),
      );
      book.sheets.single.printArea = <XlsxRange>[_r('C3:D4')];
      final String xml = _namesXml(_workbookXml(book));
      keeps(xml);
      expect(xml, contains(r"'S'!$C$3:$D$4</definedName>"));
      expect(book.sheets.single.printArea, <XlsxRange>[_r('C3:D4')]);
    });

    test('print titles', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        file('_xlnm.Print_Titles', r'S!$1:$1'),
      );
      book.sheets.single.setPrintTitles(rows: (1, 2));
      final String xml = _namesXml(_workbookXml(book));
      keeps(xml);
      expect(xml, contains(r"'S'!$2:$3</definedName>"));
    });

    test('a filter', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        file('_xlnm._FilterDatabase', r'S!$A$1:$B$2', hidden: 'hidden="true" '),
      );
      book.sheets.single.autoFilter = _r('A1:C9');
      final String xml = _namesXml(_workbookXml(book));
      keeps(xml);
      expect(xml, contains('hidden="true"'));
      expect(xml, contains(r"'S'!$A$1:$C$9</definedName>"));
    });

    test('a filter name that was not hidden becomes hidden', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        file('_xlnm._FilterDatabase', r'S!$A$1:$B$2'),
      );
      book.sheets.single.autoFilter = _r('A1:C9');
      final String xml = _namesXml(_workbookXml(book));
      keeps(xml);
      expect(xml, contains('hidden="1"'));
    });

    test('a prefixed name stays prefixed, and undo restores it', () {
      final Uint8List input = _package(
        <String, String>{'S': _worksheet('')},
        names:
            '<x:definedNames xmlns:x="$mainNs"><x:definedName '
            'name="_xlnm.Print_Area" localSheetId="0" $kept>'
            'S!\$A\$1</x:definedName></x:definedNames>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        book.sheets.single.printArea = <XlsxRange>[_r('B2')];
      });
      expect(_workbookXml(book), contains(r"'S'!$B$2</x:definedName>"));
      log.revertSet(set);
      expect(comparePackages(input, book.save().bytes), isEmpty);
    });

    test('a formula is escaped as the writer escapes it', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          <String, String>{'A&B': _worksheet('')},
          names:
              '<definedNames><definedName name="_xlnm.Print_Area" '
              'localSheetId="0" $kept>\'A&amp;B\'!\$A\$1</definedName>'
              '</definedNames>',
        ),
      );
      book.sheets.single.printArea = <XlsxRange>[_r('B2')];
      expect(_workbookXml(book), contains("'A&amp;B'!"));
      expect(book.sheets.single.printArea, <XlsxRange>[_r('B2')]);
    });
  });

  test('an equal set records nothing', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_names'));
    final XlsxSheet sheet = book.sheet("O'Brien");
    final ChangeLog log = changeLogOf(book);
    sheet
      ..printArea = sheet.printArea
      ..setPrintTitles(
        rows: sheet.printTitles.rows,
        columns: sheet.printTitles.columns,
      )
      ..autoFilter = sheet.autoFilter;
    book.sheet('Data')
      ..printArea = const <XlsxRange>[]
      ..setPrintTitles()
      ..autoFilter = null;
    expect(log.hasChanges, isFalse);
  });

  test('a filter element without its name reads; setting adds the name', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(<String, String>{'S': _worksheet('<autoFilter ref="A1:B9"/>')}),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.autoFilter, _r('A1:B9'));
    sheet.autoFilter = _r('A1:C9');
    expect(
      _namesXml(_workbookXml(book)),
      '<definedNames><definedName name="_xlnm._FilterDatabase" '
      'localSheetId="0" hidden="1">\'S\'!\$A\$1:\$C\$9</definedName>'
      '</definedNames>',
    );
    expect(_filterXml(_sheetXml(book)), '<autoFilter ref="A1:C9"/>');
  });

  test('the filter is written in schema position', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(<String, String>{
        'S': _worksheet(
          '<mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells>'
          '<pageMargins left="1" right="1" top="1" bottom="1" '
          'header="0" footer="0"/>',
        ),
      }),
    );
    book.sheets.single.autoFilter = _r('A3:B9');
    final String xml = _sheetXml(book);
    expect(xml.indexOf('<autoFilter'), greaterThan(xml.indexOf('</sheetData')));
    expect(xml.indexOf('<autoFilter'), lessThan(xml.indexOf('<mergeCells')));
  });

  test('print and filter names do not ask for recalculation', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      packageWith(
        rows: '<row r="1"><c r="A1"><f>1+1</f><v>2</v></c></row>',
        calcChain: true,
      ),
    );
    book.sheets.single
      ..printArea = <XlsxRange>[_r('A1:B2')]
      ..setPrintTitles(rows: (0, 0))
      ..autoFilter = _r('A1:B2');
    final Uint8List saved = book.save().bytes;
    expect(partText(saved, 'xl/workbook.xml'), isNot(contains('fullCalcOn')));
    expect(readXlsx(saved), contains('xl/calcChain.xml'));
  });

  test('a sheet name with a forbidden character takes print names', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'a\u0001b': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      }).replaceSheetName(),
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet
      ..printArea = <XlsxRange>[XlsxRange.parse('A1:B2')]
      ..setPrintTitles(rows: (0, 0))
      ..autoFilter = XlsxRange.parse('A1:B2');
    final String xml = partText(book.save().bytes, 'xl/workbook.xml');
    expect(xml, contains('<sheet name="ab"'));
    expect(xml, contains(r"'ab'!$A$1:$B$2"));
    expect(xml, contains(r"'ab'!$1:$1"));
  });
}

extension on Uint8List {
  /// This package with the control character of a sheet's name written as
  /// the character reference a file needs for it.
  Uint8List replaceSheetName() => buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> p in readXlsxBytes(this).entries)
      (
        p.key,
        p.key == 'xl/workbook.xml'
            ? utf8.encode(utf8.decode(p.value).replaceAll('\u0001', '&#1;'))
            : p.value,
      ),
  ]);
}
