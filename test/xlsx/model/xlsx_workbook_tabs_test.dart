import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

const String _selected =
    '<sheetViews><sheetView tabSelected="1" workbookViewId="0"/></sheetViews>';
const String _plain =
    '<sheetViews><sheetView workbookViewId="0"/></sheetViews>';

String _sheet(String views) =>
    '<worksheet xmlns="$mainNs">$views<sheetData/></worksheet>';

/// A package of sheets `S1`.. with the given `state` attributes, sheet XML
/// (`null` for a missing part) and the raw [head] of the workbook before
/// `<sheets>`.
Uint8List _book({
  List<String> states = const <String>['', '', ''],
  List<String?>? sheets,
  String head = '<bookViews><workbookView activeTab="0"/></bookViews>',
  bool calcChain = false,
}) {
  final List<String?> xml =
      sheets ??
      <String?>[
        for (int i = 0; i < states.length; i++)
          _sheet(i == 0 ? _selected : _plain),
      ];
  final StringBuffer list = StringBuffer();
  final StringBuffer rels = StringBuffer();
  final Map<String, List<int>> parts = <String, List<int>>{};
  for (int i = 0; i < xml.length; i++) {
    final String state = states[i].isEmpty ? '' : ' state="${states[i]}"';
    list.write(
      '<sheet name="S${i + 1}" sheetId="${i + 1}"$state r:id="rId${i + 1}"/>',
    );
    rels.write(
      '<Relationship Id="rId${i + 1}" Type="$relNs/worksheet" '
      'Target="worksheets/sheet${i + 1}.xml"/>',
    );
    if (xml[i] != null) parts[sheetEntry(i)] = utf8.encode(xml[i]!);
  }
  if (calcChain) {
    rels.write(
      '<Relationship Id="rIdC" Type="$relNs/calcChain" Target="calcChain.xml"/>',
    );
    parts['xl/calcChain.xml'] = utf8.encode(
      '<calcChain xmlns="$mainNs"><c r="A1" i="1"/></calcChain>',
    );
  }
  return buildZip(<String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$ctNs"><Override PartName="/xl/workbook.xml" '
      'ContentType="$wbType"/>'
      '${calcChain ? '<Override PartName="/xl/calcChain.xml" ContentType="'
                'application/vnd.openxmlformats-officedocument.spreadsheetml.'
                'calcChain+xml"/>' : ''}</Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
      'Type="$relNs/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    ),
    'xl/workbook.xml': utf8.encode(
      '<workbook xmlns="$mainNs" xmlns:r="$relNs"><workbookPr/>'
      '$head<sheets>$list</sheets><calcPr calcId="1"/></workbook>',
    ),
    'xl/_rels/workbook.xml.rels': utf8.encode(
      '<Relationships xmlns="$pkgRelNs">$rels</Relationships>',
    ),
    ...parts,
  });
}

String _workbookXml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/workbook.xml');

String _sheetXml(XlsxWorkbook book, int i) =>
    partText(book.save().bytes, 'xl/worksheets/sheet${i + 1}.xml');

List<XlsxSheetVisibility> _states(Uint8List bytes) => <XlsxSheetVisibility>[
  for (final XlsxReadSheet s in XlsxReader(bytes).sheets) s.visibility,
];

void main() {
  test('visibility round-trips through XlsxReader.sheets', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.sheets[1].visibility = XlsxSheetVisibility.hidden;
    book.sheets[2].visibility = XlsxSheetVisibility.veryHidden;
    expect(book.sheets[1].visibility, XlsxSheetVisibility.hidden);
    expect(_states(book.save().bytes), <XlsxSheetVisibility>[
      XlsxSheetVisibility.visible,
      XlsxSheetVisibility.hidden,
      XlsxSheetVisibility.veryHidden,
    ]);
    book.sheets[1].visibility = XlsxSheetVisibility.visible;
    final String xml = _workbookXml(book);
    expect(xml, contains('<sheet name="S2" sheetId="2" r:id="rId2"/>'));
    expect(xml, contains('state="veryHidden"'));
    expect(_states(book.save().bytes)[1], XlsxSheetVisibility.visible);
  });

  test('an explicit state="visible" is removed when visibility is set', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _book(states: <String>['visible', 'hidden']),
    );
    book.sheets[0].visibility = XlsxSheetVisibility.visible; // equal: kept
    expect(_workbookXml(book), contains('state="visible"'));
    book.sheets[1].visibility = XlsxSheetVisibility.visible;
    book.sheets[0].visibility = XlsxSheetVisibility.hidden;
    book.sheets[0].visibility = XlsxSheetVisibility.visible;
    expect(_workbookXml(book), isNot(contains('state=')));
  });

  test('hiding the last visible sheet throws; nothing changes', () {
    final Uint8List bytes = _book(states: <String>['', 'hidden', 'veryHidden']);
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    final String before = _workbookXml(book);
    expect(
      () => book.sheets[0].visibility = XlsxSheetVisibility.hidden,
      throwsStateError,
    );
    expect(
      () => book.sheets[0].visibility = XlsxSheetVisibility.veryHidden,
      throwsStateError,
    );
    expect(book.sheets[0].visibility, XlsxSheetVisibility.visible);
    expect(_workbookXml(book), before);
    expect(changeLogOf(book).hasChanges, isFalse);
    // A hidden sheet may become very hidden, and hiding is allowed while
    // another sheet stays visible.
    book.sheets[1].visibility = XlsxSheetVisibility.veryHidden;
    book.sheets[2].visibility = XlsxSheetVisibility.visible;
    book.sheets[0].visibility = XlsxSheetVisibility.hidden;
    expect(book.activeSheet.name, 'S3');
  });

  test('the last-visible guard itself: the last visible sheet is not '
      'the active tab', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _book(
        states: <String>['hidden', '', 'hidden'],
        head: '<bookViews><workbookView activeTab="0"/></bookViews>',
      ),
    );
    final Matcher guard = throwsA(
      isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('last visible sheet'),
      ),
    );
    expect(() => book.sheets[1].visibility = XlsxSheetVisibility.hidden, guard);
    expect(
      () => book.sheets[1].visibility = XlsxSheetVisibility.veryHidden,
      guard,
    );
    expect(book.sheets[1].visibility, XlsxSheetVisibility.visible);
    expect(book.activeSheet.name, 'S1');
    expect(changeLogOf(book).hasChanges, isFalse);
  });

  test('the guard only applies to hiding a visible sheet', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _book(states: <String>['hidden', 'hidden']),
    );
    book.sheets[0].visibility = XlsxSheetVisibility.veryHidden;
    book.sheets[1].visibility = XlsxSheetVisibility.veryHidden;
    book.sheets[0].visibility = XlsxSheetVisibility.hidden;
    expect(_states(book.save().bytes), <XlsxSheetVisibility>[
      XlsxSheetVisibility.hidden,
      XlsxSheetVisibility.veryHidden,
    ]);
  });

  group('calcChain and fullCalcOnLoad follow cell changes only', () {
    const String formulaSheet =
        '<worksheet xmlns="$mainNs">$_selected<sheetData><row r="1">'
        '<c r="A1"><f>1+1</f><v>2</v></c></row></sheetData></worksheet>';
    final Map<String, void Function(XlsxWorkbook)> edits =
        <String, void Function(XlsxWorkbook)>{
          'setStyle': (XlsxWorkbook b) => b.sheets[0].setStyle(
            0,
            0,
            const XlsxStyle(font: XlsxFont(bold: true)),
          ),
          'setRowFormat': (XlsxWorkbook b) =>
              b.sheets[0].setRowFormat(0, const XlsxRowFormat(height: 30)),
          'setColumn': (XlsxWorkbook b) =>
              b.sheets[0].setColumn(0, const XlsxColumn(width: 20)),
          'merge': (XlsxWorkbook b) =>
              b.sheets[0].merge(XlsxRange.parse('B1:C2')),
          'view': (XlsxWorkbook b) =>
              b.sheets[0].view = const XlsxSheetView(zoom: 150),
          'tabColor': (XlsxWorkbook b) =>
              b.sheets[0].tabColor = const XlsxColor.rgb(0x1F4E79),
          'visibility': (XlsxWorkbook b) =>
              b.sheets[1].visibility = XlsxSheetVisibility.hidden,
          'activeSheet': (XlsxWorkbook b) => b.activeSheet = b.sheets[1],
        };

    Uint8List input() =>
        _book(sheets: <String?>[formulaSheet, _sheet(_plain)], calcChain: true);

    for (final MapEntry<String, void Function(XlsxWorkbook)> e
        in edits.entries) {
      test('${e.key} keeps calcChain and sets no fullCalcOnLoad', () {
        final XlsxWorkbook book = XlsxWorkbook.open(input());
        e.value(book);
        final Map<String, String> parts = readXlsx(book.save().bytes);
        expect(parts, contains('xl/calcChain.xml'));
        expect(parts['xl/_rels/workbook.xml.rels'], contains('calcChain'));
        expect(parts['xl/workbook.xml'], isNot(contains('fullCalcOnLoad')));
      });
    }

    test('setCell still drops calcChain and sets fullCalcOnLoad', () {
      final XlsxWorkbook book = XlsxWorkbook.open(input());
      book.sheets[0].setCell(5, 0, 1);
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts, isNot(contains('xl/calcChain.xml')));
      expect(parts['xl/workbook.xml'], contains('fullCalcOnLoad="1"'));
    });

    test('a failed setCell leaves calcChain', () {
      final XlsxWorkbook book = XlsxWorkbook.open(input());
      expect(() => book.sheets[0].setCell(0, 0, Object()), throwsA(anything));
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts, contains('xl/calcChain.xml'));
      expect(parts['xl/workbook.xml'], isNot(contains('fullCalcOnLoad')));
    });

    test('a transaction rolled back after a setCell leaves calcChain', () {
      final XlsxWorkbook book = XlsxWorkbook.open(input());
      expect(
        () => changeLogOf(book).transaction(() {
          book.sheets[0].setCell(5, 0, 1);
          throw StateError('later failure');
        }),
        throwsStateError,
      );
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts, contains('xl/calcChain.xml'));
      expect(parts['xl/workbook.xml'], isNot(contains('fullCalcOnLoad')));
    });
  });

  test('activeSheet matches the writer\'s active tab', () {
    final Fixture sheets = allFixtures().firstWhere(
      (Fixture f) => f.name == 'm1_sheets',
    );
    final XlsxWorkbook book = XlsxWorkbook.open(sheets.build());
    expect(book.activeSheet.name, 'şube (2)');
    for (final Fixture f in allFixtures()) {
      final Uint8List bytes = f.build();
      final XlsxWorkbook b = XlsxWorkbook.open(bytes);
      final RegExpMatch? m = RegExp(
        r'<workbookView[^>]*activeTab="(\d+)"',
      ).firstMatch(partText(bytes, 'xl/workbook.xml'));
      expect(
        b.sheets.indexOf(b.activeSheet),
        int.parse(m?.group(1) ?? '0'),
        reason: f.name,
      );
    }
  });

  test('activeSheet defaults to the first sheet and is empty-safe', () {
    final XlsxWorkbook none = XlsxWorkbook.open(_book(head: ''));
    expect(none.activeSheet.name, 'S1');
    final XlsxWorkbook past = XlsxWorkbook.open(
      _book(head: '<bookViews><workbookView activeTab="9"/></bookViews>'),
    );
    expect(past.activeSheet.name, 'S1');
    expect(() => XlsxWorkbook().activeSheet, throwsStateError);
  });

  test('hiding the active sheet moves the active tab', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _book(states: <String>['', 'hidden', '']),
    );
    book.sheets[0].visibility = XlsxSheetVisibility.hidden;
    expect(book.activeSheet.name, 'S3');
    final String xml = _workbookXml(book);
    expect(xml, contains('activeTab="2"'));
    expect(_sheetXml(book, 0), isNot(contains('tabSelected')));
    expect(_sheetXml(book, 2), contains('tabSelected="1"'));
    // Hiding a sheet that is not active leaves the active tab alone.
    book.sheets[1].visibility = XlsxSheetVisibility.visible;
    book.sheets[1].visibility = XlsxSheetVisibility.hidden;
    expect(book.activeSheet.name, 'S3');
  });

  test('setting activeSheet moves activeTab and tabSelected', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    book.activeSheet = book.sheets[2];
    expect(book.activeSheet.name, 'S3');
    expect(_workbookXml(book), contains('activeTab="2"'));
    expect(_sheetXml(book, 0), isNot(contains('tabSelected')));
    expect(_sheetXml(book, 2), contains('tabSelected="1"'));
    // A sheet without a view gets one.
    final XlsxWorkbook bare = XlsxWorkbook.open(
      _book(sheets: <String?>[_sheet(''), _sheet('')]),
    );
    bare.activeSheet = bare.sheets[1];
    expect(_sheetXml(bare, 1), contains('<sheetView tabSelected="1"'));
  });

  test('an invalid activeSheet changes nothing', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _book(states: <String>['', 'hidden', 'veryHidden']),
    );
    final XlsxWorkbook other = XlsxWorkbook.open(_book());
    final String before = _workbookXml(book);
    expect(() => book.activeSheet = book.sheets[1], throwsStateError);
    expect(() => book.activeSheet = book.sheets[2], throwsStateError);
    expect(() => book.activeSheet = other.sheets[0], throwsArgumentError);
    expect(_workbookXml(book), before);
    expect(changeLogOf(book).hasChanges, isFalse);
  });

  test('a new bookViews goes in schema position; attributes are kept', () {
    final XlsxWorkbook none = XlsxWorkbook.open(_book(head: ''));
    none.activeSheet = none.sheets[1];
    expect(
      _workbookXml(none),
      contains(
        '<workbookPr/><bookViews><workbookView activeTab="1"/></bookViews>'
        '<sheets>',
      ),
    );
    final XlsxWorkbook kept = XlsxWorkbook.open(
      _book(
        head:
            '<bookViews><workbookView xWindow="1" firstSheet="0" '
            'activeTab="0" tabRatio="600"/><workbookView activeTab="0"/>'
            '</bookViews>',
      ),
    );
    kept.activeSheet = kept.sheets[1];
    expect(
      _workbookXml(kept),
      contains(
        '<workbookView xWindow="1" firstSheet="0" activeTab="1" '
        'tabRatio="600"/><workbookView activeTab="0"/>',
      ),
    );
    // An absent attribute is added; activeTab 0 on an absent one is a no-op.
    final XlsxWorkbook bare = XlsxWorkbook.open(
      _book(head: '<bookViews><workbookView tabRatio="5"/></bookViews>'),
    );
    bare.activeSheet = bare.sheets[0];
    expect(_workbookXml(bare), contains('<workbookView tabRatio="5"/>'));
    bare.activeSheet = bare.sheets[2];
    expect(_workbookXml(bare), contains('tabRatio="5" activeTab="2"'));
  });

  test('a sheet without a worksheet part only changes activeTab', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _book(sheets: <String?>[_sheet(_selected), null]),
    );
    book.activeSheet = book.sheets[1];
    expect(book.activeSheet.name, 'S2');
    expect(_workbookXml(book), contains('activeTab="1"'));
    expect(_sheetXml(book, 0), isNot(contains('tabSelected')));
    // Hiding a sheet without a part that is active moves on to a worksheet.
    book.sheets[1].visibility = XlsxSheetVisibility.hidden;
    expect(book.activeSheet.name, 'S1');
    expect(_sheetXml(book, 0), contains('tabSelected="1"'));
  });

  test('visibility and the active sheet are changes of the log', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_book());
    final ChangeLog log = changeLogOf(book);
    late final ChangeSet set;
    final String before = _workbookXml(book);
    set = log.transaction(() {
      book.sheets[0].visibility = XlsxSheetVisibility.hidden;
    });
    expect(book.activeSheet.name, 'S2');
    log.revertSet(set);
    expect(book.activeSheet.name, 'S1');
    expect(book.sheets[0].visibility, XlsxSheetVisibility.visible);
    // Saving after a change asks for a recalculation (bookkeeping).
    expect(_workbookXml(book).replaceAll(' fullCalcOnLoad="1"', ''), before);
    expect(_sheetXml(book, 0), contains('tabSelected="1"'));
    expect(_sheetXml(book, 1), isNot(contains('tabSelected')));
    log.reapplySet(set);
    expect(book.activeSheet.name, 'S2');
    expect(_states(book.save().bytes)[0], XlsxSheetVisibility.hidden);
  });
}
