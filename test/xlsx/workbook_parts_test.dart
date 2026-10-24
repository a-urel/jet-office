import 'package:jet_office/jet_office.dart' show XlsxRange, XlsxSheetVisibility;
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xlsx/workbook_parts.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String _render(void Function(XmlWriter w) write) {
  final StringBuffer out = StringBuffer();
  write(XmlWriter(out));
  return out.toString();
}

const String _decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

void main() {
  group('writeWorkbook', () {
    test('lists sheets in tab order with creation-order ids', () {
      final String xml = _render(
        (XmlWriter w) => writeWorkbook(
          w,
          tabs: const <WorkbookSheet>[
            (
              name: 'Summary',
              number: 3,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
            (
              name: 'Detail A',
              number: 1,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
            (
              name: 'Detail B',
              number: 2,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
          ],
          activeTab: 0,
          fullCalcOnLoad: false,
        ),
      );
      expect(
        xml,
        '$_decl<workbook xmlns="${Ns.main}" xmlns:r="${Ns.rel}">'
        '<bookViews><workbookView activeTab="0"/></bookViews>'
        '<sheets>'
        '<sheet name="Summary" sheetId="3" r:id="rId3"/>'
        '<sheet name="Detail A" sheetId="1" r:id="rId1"/>'
        '<sheet name="Detail B" sheetId="2" r:id="rId2"/>'
        '</sheets></workbook>',
      );
    });

    test('writes state for a hidden and a very hidden sheet', () {
      final String xml = _render(
        (XmlWriter w) => writeWorkbook(
          w,
          tabs: const <WorkbookSheet>[
            (
              name: 'V',
              number: 1,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
            (
              name: 'H',
              number: 2,
              visibility: XlsxSheetVisibility.hidden,
              autoFilter: null,
            ),
            (
              name: 'X',
              number: 3,
              visibility: XlsxSheetVisibility.veryHidden,
              autoFilter: null,
            ),
          ],
          activeTab: 0,
          fullCalcOnLoad: false,
        ),
      );
      expect(
        xml,
        contains(
          '<sheet name="V" sheetId="1" r:id="rId1"/>'
          '<sheet name="H" sheetId="2" state="hidden" r:id="rId2"/>'
          '<sheet name="X" sheetId="3" state="veryHidden" r:id="rId3"/>',
        ),
      );
    });

    test('escapes _xHHHH_ in a sheet name, then XML-escapes it', () {
      final String xml = _render(
        (XmlWriter w) => writeWorkbook(
          w,
          tabs: const <WorkbookSheet>[
            (
              name: '_x0041_',
              number: 1,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
            (
              name: 'a&_x0042_',
              number: 2,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
          ],
          activeTab: 0,
          fullCalcOnLoad: false,
        ),
      );
      expect(xml, contains('<sheet name="_x005F_x0041_" sheetId="1"'));
      expect(xml, contains('<sheet name="a&amp;_x005F_x0042_" sheetId="2"'));
    });

    test('adds calcPr after sheets only for formulas', () {
      final String xml = _render(
        (XmlWriter w) => writeWorkbook(
          w,
          tabs: const <WorkbookSheet>[
            (
              name: 'A',
              number: 1,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
          ],
          activeTab: 0,
          fullCalcOnLoad: true,
        ),
      );
      expect(xml, endsWith('</sheets><calcPr fullCalcOnLoad="1"/></workbook>'));
    });

    test('escapes sheet names in the attribute', () {
      final String xml = _render(
        (XmlWriter w) => writeWorkbook(
          w,
          tabs: const <WorkbookSheet>[
            (
              name: 'P&L "2026"',
              number: 1,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
            (
              name: 'B',
              number: 2,
              visibility: XlsxSheetVisibility.visible,
              autoFilter: null,
            ),
          ],
          activeTab: 1,
          fullCalcOnLoad: false,
        ),
      );
      expect(xml, contains('<sheet name="P&amp;L &quot;2026&quot;"'));
      expect(xml, contains('<workbookView activeTab="1"/>'));
    });
  });

  group('_xlnm._FilterDatabase', () {
    String workbook(List<WorkbookSheet> tabs, {bool calc = false}) => _render(
      (XmlWriter w) =>
          writeWorkbook(w, tabs: tabs, activeTab: 0, fullCalcOnLoad: calc),
    );

    WorkbookSheet sheet(String name, int number, [String? filter]) => (
      name: name,
      number: number,
      visibility: XlsxSheetVisibility.visible,
      autoFilter: filter == null ? null : XlsxRange.parse(filter),
    );

    test('no filter writes no definedNames', () {
      expect(
        workbook(<WorkbookSheet>[sheet('A', 1)]),
        isNot(contains('defin')),
      );
    });

    test('quotes the sheet name, doubles quotes, uses the tab index', () {
      expect(
        workbook(<WorkbookSheet>[sheet("Bob's Data", 1, 'A6:D20')]),
        endsWith(
          '</sheets><definedNames><definedName name="_xlnm._FilterDatabase" '
          'localSheetId="0" hidden="1">\'Bob\'\'s Data\'!\$A\$6:\$D\$20'
          '</definedName></definedNames></workbook>',
        ),
      );
    });

    test('one name per filtered sheet, in tab order, before calcPr', () {
      final String xml = workbook(<WorkbookSheet>[
        sheet('Plain', 3),
        sheet('B', 1, 'A1:B2'),
        sheet('C', 2, 'C3'),
      ], calc: true);
      expect(
        xml,
        contains(
          '</sheets><definedNames>'
          '<definedName name="_xlnm._FilterDatabase" localSheetId="1" '
          "hidden=\"1\">'B'!\$A\$1:\$B\$2</definedName>"
          '<definedName name="_xlnm._FilterDatabase" localSheetId="2" '
          "hidden=\"1\">'C'!\$C\$3</definedName>"
          '</definedNames><calcPr fullCalcOnLoad="1"/></workbook>',
        ),
      );
    });

    test('the text goes through escapeXstring, then XML escaping', () {
      final String xml = workbook(<WorkbookSheet>[
        sheet('a&_x0041_', 1, 'A1:B2'),
      ]);
      expect(
        xml,
        contains(">'a&amp;_x005F_x0041_'!\$A\$1:\$B\$2</definedName>"),
      );
    });
  });

  test('workbook relationships: worksheets, then styles and strings', () {
    final String xml = _render(
      (XmlWriter w) => writeWorkbookRelationships(w, 2),
    );
    expect(
      xml,
      '$_decl<Relationships xmlns="${Ns.packageRel}">'
      '<Relationship Id="rId1" Type="${RelType.worksheet}" '
      'Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="${RelType.worksheet}" '
      'Target="worksheets/sheet2.xml"/>'
      '<Relationship Id="rId3" Type="${RelType.styles}" Target="styles.xml"/>'
      '<Relationship Id="rId4" Type="${RelType.sharedStrings}" '
      'Target="sharedStrings.xml"/>'
      '</Relationships>',
    );
  });

  test('root relationships: workbook and both property parts', () {
    final String xml = _render(writeRootRelationships);
    expect(
      xml,
      '$_decl<Relationships xmlns="${Ns.packageRel}">'
      '<Relationship Id="rId1" Type="${RelType.officeDocument}" '
      'Target="xl/workbook.xml"/>'
      '<Relationship Id="rId2" Type="${RelType.coreProperties}" '
      'Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="${RelType.extendedProperties}" '
      'Target="docProps/app.xml"/>'
      '</Relationships>',
    );
  });

  test('content types: defaults and one override per part', () {
    final String xml = _render((XmlWriter w) => writeContentTypes(w, 2));
    expect(
      xml,
      '$_decl<Types xmlns="${Ns.contentTypes}">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Default Extension="xml" ContentType="${ContentType.xml}"/>'
      '<Override PartName="/docProps/app.xml" '
      'ContentType="${ContentType.extendedProperties}"/>'
      '<Override PartName="/docProps/core.xml" '
      'ContentType="${ContentType.coreProperties}"/>'
      '<Override PartName="/xl/sharedStrings.xml" '
      'ContentType="${ContentType.sharedStrings}"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="${ContentType.styles}"/>'
      '<Override PartName="/xl/workbook.xml" '
      'ContentType="${ContentType.workbook}"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="${ContentType.worksheet}"/>'
      '<Override PartName="/xl/worksheets/sheet2.xml" '
      'ContentType="${ContentType.worksheet}"/>'
      '</Types>',
    );
  });

  test('worksheet part names follow the creation number', () {
    expect(worksheetPartName(1), 'xl/worksheets/sheet1.xml');
    expect(worksheetPartName(12), 'xl/worksheets/sheet12.xml');
  });

  test('worksheet relationship ids come from worksheetRelationshipId', () {
    final StringBuffer out = StringBuffer();
    writeWorkbookRelationships(XmlWriter(out), 12);
    final String xml = out.toString();
    for (int n = 1; n <= 12; n++) {
      expect(
        xml,
        contains(
          'Id="${worksheetRelationshipId(n)}" Type="${RelType.worksheet}" '
          'Target="worksheets/sheet$n.xml"',
        ),
      );
    }
    final Set<String> ids = RegExp(
      r'Id="([^"]+)"',
    ).allMatches(xml).map((RegExpMatch m) => m.group(1)!).toSet();
    expect(ids, hasLength(14));
  });
}
