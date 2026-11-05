import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

/// A one-sheet package whose workbook part holds [names] (raw XML, the
/// `<definedNames>` or nothing) between `<sheets>` and `<calcPr>`; with
/// [calcChain], a calculation chain, and with [formula], a cell with one.
Uint8List _package(
  String names, {
  bool calcChain = false,
  bool formula = false,
  String root = 'workbook',
}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    packageWith(
      rows: formula
          ? '<row r="1"><c r="A1"><f>1+1</f><v>2</v></c></row>'
          : '<row r="1"><c r="A1"><v>2</v></c></row>',
      calcChain: calcChain,
    ),
  );
  parts['xl/workbook.xml'] = Uint8List.fromList(
    utf8.encode(
      '<$root xmlns="$mainNs" xmlns:r="$relNs"><sheets>'
      '<sheet name="S" sheetId="1" r:id="rId1"/></sheets>'
      '$names<calcPr calcId="191029"/></$root>',
    ),
  );
  return buildZip(<String, List<int>>{...parts});
}

String _workbookXml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/workbook.xml');

String _namesXml(String xml) =>
    RegExp(
      '<definedNames[^>]*/>|<definedNames[ >].*?</definedNames>',
    ).firstMatch(xml)?.group(0) ??
    '';

Uint8List _m3Names() =>
    allFixtures().firstWhere((Fixture f) => f.name == 'm3_names').build();

List<XlsxWarning> _invalid(XlsxWorkbook book) => <XlsxWarning>[
  for (final XlsxWarning w in book.warnings)
    if (w.code == XlsxWarningCode.featureEntryInvalid) w,
];

void main() {
  test('reads m3_names', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_m3Names());
    expect(book.definedNames, const <XlsxDefinedName>[
      XlsxDefinedName('TaxRate', '0.18'),
    ]);
    expect(book.sheet('Data').definedNames, const <XlsxDefinedName>[
      XlsxDefinedName('Local', r'Data!$B$2'),
    ]);
    // The names of "O'Brien" are the built-in print area and titles.
    expect(book.sheet("O'Brien").definedNames, isEmpty);
    expect(
      () => book.definedNames.add(const XlsxDefinedName('a', '1')),
      throwsA(anything),
    );
    expect(book.warnings, isEmpty);
  });

  test('define and remove round-trip through a saved file', () {
    final XlsxWriter writer = XlsxWriter();
    writer
      ..addSheet('S').row(<Object?>[1])
      ..defineName(
        const XlsxDefinedName(
          'Rate',
          'Data!\$A\$1',
          hidden: true,
          comment: 'a & b',
        ),
      );
    final String expected = _namesXml(
      partText(writer.close().bytes, 'xl/workbook.xml'),
    );

    final XlsxWorkbook book = XlsxWorkbook.open(_package(''));
    book.defineName(
      const XlsxDefinedName(
        'Rate',
        '=Data!\$A\$1',
        hidden: true,
        comment: 'a & b',
      ),
    );
    final String xml = _workbookXml(book);
    expect(_namesXml(xml), expected);
    expect(xml.indexOf('</sheets>'), lessThan(xml.indexOf('<definedNames')));
    expect(xml.indexOf('</definedNames>'), lessThan(xml.indexOf('<calcPr')));

    final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
    expect(again.definedNames, const <XlsxDefinedName>[
      XlsxDefinedName('Rate', 'Data!\$A\$1', hidden: true, comment: 'a & b'),
    ]);
    again.removeName('RATE');
    expect(again.definedNames, isEmpty);
    expect(_namesXml(_workbookXml(again)), '');
  });

  test('a name is added after the others, a sheet name in its scope', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_m3Names());
    book.defineName(const XlsxDefinedName('Zed', '1'));
    book.sheet('Data').defineName(const XlsxDefinedName('Sheeted', '2'));
    final String names = _namesXml(_workbookXml(book));
    expect(
      names.indexOf('name="Zed"'),
      greaterThan(names.indexOf('name="_xlnm.Print_Titles"')),
    );
    expect(names, contains('<definedName name="Sheeted" localSheetId="0">2'));
    expect(book.definedNames.map((XlsxDefinedName n) => n.name), <String>[
      'TaxRate',
      'Zed',
    ]);
    expect(
      book.sheet('Data').definedNames.map((XlsxDefinedName n) => n.name),
      <String>['Local', 'Sheeted'],
    );
    expect(book.sheet("O'Brien").definedNames, isEmpty);
  });

  test('the same name in two scopes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_m3Names());
    book.sheet("O'Brien").defineName(const XlsxDefinedName('TaxRate', '2'));
    book.sheet('Data').defineName(const XlsxDefinedName('TaxRate', '3'));
    expect(book.definedNames.single.formula, '0.18');
    expect(book.sheet("O'Brien").definedNames.single.formula, '2');
    expect(
      book.sheet('Data').definedNames.map((XlsxDefinedName n) => n.name),
      <String>['Local', 'TaxRate'],
    );
    final String names = _namesXml(_workbookXml(book));
    expect(names, contains('<definedName name="TaxRate" localSheetId="1">2'));
    expect(names, contains('<definedName name="TaxRate" localSheetId="0">3'));
  });

  test('a name taken ignoring case throws; nothing changes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_m3Names());
    final String before = _workbookXml(book);
    final ChangeLog log = changeLogOf(book);
    expect(
      () => book.defineName(const XlsxDefinedName('TAXRATE', '1')),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'name')),
    );
    expect(
      () => book.sheet('Data').defineName(const XlsxDefinedName('LOCAL', '1')),
      throwsArgumentError,
    );
    expect(
      () => book.defineName(const XlsxDefinedName('Print_Area', '1')),
      throwsArgumentError,
    );
    expect(
      () => book.defineName(const XlsxDefinedName('Bad', '')),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'formula')),
    );
    expect(
      () => book.removeName('Local'),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'name')),
    );
    expect(() => book.sheet('Data').removeName('TaxRate'), throwsArgumentError);
    expect(() => book.removeName('_xlnm.Print_Area'), throwsArgumentError);
    expect(log.hasChanges, isFalse);
    expect(_workbookXml(book), before);
  });

  test('a name that a table has throws; nothing changes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      allFixtures().firstWhere((Fixture f) => f.name == 'm4_tables').build(),
    );
    final String before = _workbookXml(book);
    final ChangeLog log = changeLogOf(book);
    expect(
      () => book.defineName(const XlsxDefinedName('Sales', '1')),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'name')),
    );
    expect(
      () => book.sheet('Plain').defineName(const XlsxDefinedName('COSTS', '1')),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'name')),
    );
    expect(log.hasChanges, isFalse);
    expect(_workbookXml(book), before);
  });

  test('a removed name\'s group goes with its last child', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<definedNames><definedName name="a">1'
        '</definedName></definedNames>',
      ),
    );
    book.removeName('a');
    final String xml = _workbookXml(book);
    expect(xml, isNot(contains('definedNames')));
    expect(xml.indexOf('</sheets>'), lessThan(xml.indexOf('<calcPr')));
  });

  test('removing a name keeps the others', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<definedNames><definedName name="a">1'
        '</definedName><definedName name="b">2</definedName>'
        '</definedNames>',
      ),
    );
    book.removeName('a');
    expect(
      _namesXml(_workbookXml(book)),
      '<definedNames><definedName name="b">2</definedName></definedNames>',
    );
  });

  test('a hidden name and a comment read', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<definedNames>'
        '<definedName name="h" hidden="1">1</definedName>'
        '<definedName name="t" hidden="true">2</definedName>'
        '<definedName name="c" comment="Rate_x0041_ &amp; more">'
        '3</definedName>'
        '<definedName name="e"/>'
        '</definedNames>',
      ),
    );
    expect(book.definedNames, const <XlsxDefinedName>[
      XlsxDefinedName('h', '1', hidden: true),
      XlsxDefinedName('t', '2', hidden: true),
      XlsxDefinedName('c', '3', comment: 'RateA & more'),
      XlsxDefinedName('e', ''),
    ]);
    expect(book.warnings, isEmpty);
  });

  test('other attributes are kept', () {
    const String names =
        '<definedNames><definedName name="f" function="1" '
        'vbProcedure="1">SUM(1,2)</definedName></definedNames>';
    final XlsxWorkbook book = XlsxWorkbook.open(_package(names));
    expect(book.definedNames.single.name, 'f');
    book.defineName(const XlsxDefinedName('g', '1'));
    expect(
      _namesXml(_workbookXml(book)),
      '<definedNames><definedName name="f" function="1" vbProcedure="1">'
      'SUM(1,2)</definedName><definedName name="g">1</definedName>'
      '</definedNames>',
    );
    book.removeName('g');
    expect(_namesXml(_workbookXml(book)), contains('function="1"'));
  });

  test('bad values are kept and reported', () {
    const String names =
        '<definedNames count="4">'
        '<definedName name="far" localSheetId="99">1</definedName>'
        '<definedName>2</definedName>'
        '<definedName name="neg" localSheetId="-1">3</definedName>'
        '<definedName name="ok" localSheetId="0">4</definedName>'
        '<note/>'
        '</definedNames>';
    final Uint8List input = _package(names);
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(
      _invalid(book).fold<int>(0, (int s, XlsxWarning w) => s + w.count),
      3,
    );
    expect(book.definedNames, isEmpty);
    expect(book.sheets.single.definedNames, const <XlsxDefinedName>[
      XlsxDefinedName('ok', '4'),
    ]);
    // Nothing is lost on save with no change.
    expect(_namesXml(_workbookXml(book)), names);

    // Nor when a name is added or removed beside them.
    book.defineName(const XlsxDefinedName('late', '5'));
    book.sheets.single.removeName('ok');
    final String xml = _namesXml(_workbookXml(book));
    expect(xml, contains('<definedName name="far" localSheetId="99">1'));
    expect(xml, contains('<definedName>2</definedName>'));
    expect(xml, contains('<definedName name="neg" localSheetId="-1">3'));
    expect(xml, contains('<note/>'));
    expect(xml, isNot(contains('name="ok"')));
    expect(xml, contains('<definedName name="late">5</definedName>'));
  });

  test('a prefixed workbook keeps its namespace', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildZip(<String, List<int>>{
        ...readXlsxBytes(_package('')),
        'xl/workbook.xml': utf8.encode(
          '<x:workbook xmlns:x="$mainNs" xmlns:r="$relNs"><x:sheets>'
          '<x:sheet name="S" sheetId="1" r:id="rId1"/></x:sheets>'
          '</x:workbook>',
        ),
      }),
    );
    book.defineName(const XlsxDefinedName('n', '1'));
    final String xml = _workbookXml(book);
    expect(xml, contains('<x:definedNames>'));
    expect(XlsxWorkbook.open(book.save().bytes).definedNames.single.name, 'n');
  });

  group('recalculation', () {
    String calcPr(XlsxWorkbook book) =>
        RegExp('<calcPr[^>]*/>').firstMatch(_workbookXml(book))!.group(0)!;

    Map<String, String> parts(XlsxWorkbook book) => readXlsx(book.save().bytes);

    test('a name edit asks for recalculation; calcChain stays', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package('', calcChain: true, formula: true),
      );
      expect(calcPr(book), isNot(contains('fullCalcOnLoad')));
      book.defineName(const XlsxDefinedName('n', '1'));
      expect(calcPr(book), contains('fullCalcOnLoad="1"'));
      final Map<String, String> saved = parts(book);
      expect(saved.containsKey('xl/calcChain.xml'), isTrue);
      expect(saved['xl/_rels/workbook.xml.rels'], contains('calcChain'));
    });

    test('a removal asks too', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          '<definedNames><definedName name="n">1</definedName>'
          '</definedNames>',
          formula: true,
        ),
      );
      book.removeName('n');
      expect(calcPr(book), contains('fullCalcOnLoad="1"'));
    });

    test('a workbook without formulas asks nothing', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_package(''));
      book.sheets.single.rows.toList();
      book.sheets.single.defineName(const XlsxDefinedName('n', '1'));
      expect(calcPr(book), isNot(contains('fullCalcOnLoad')));
    });

    test('a removed name then undone does not', () {
      final Uint8List input = _package(
        '<definedNames><definedName name="n">1</definedName>'
        '</definedNames>',
        calcChain: true,
        formula: true,
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() => book.removeName('n'));
      log.revertSet(set);
      expect(book.definedNames.single.name, 'n');
      // Saved after the undo: no recalculation, and nothing else changed.
      final Uint8List saved = book.save().bytes;
      expect(
        partText(saved, 'xl/workbook.xml'),
        isNot(contains('fullCalcOnLoad')),
      );
      expect(comparePackages(input, saved), isEmpty);

      // Redone, it asks again; undone once more, a new book is clean.
      final XlsxWorkbook other = XlsxWorkbook.open(input);
      final ChangeLog otherLog = changeLogOf(other);
      final ChangeSet again = otherLog.transaction(() => other.removeName('n'));
      otherLog
        ..revertSet(again)
        ..reapplySet(again);
      expect(other.definedNames, isEmpty);
      expect(calcPr(other), contains('fullCalcOnLoad="1"'));
    });

    test('an added name then undone leaves no group', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_package('', formula: true));
      final ChangeLog log = changeLogOf(book);
      final String before = _workbookXml(book);
      final ChangeSet set = log.transaction(
        () => book.defineName(const XlsxDefinedName('n', '1')),
      );
      log.revertSet(set);
      expect(_workbookXml(book), before);
    });
  });
}
