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
            (name: 'Summary', number: 3),
            (name: 'Detail A', number: 1),
            (name: 'Detail B', number: 2),
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

    test('escapes _xHHHH_ in a sheet name, then XML-escapes it', () {
      final String xml = _render(
        (XmlWriter w) => writeWorkbook(
          w,
          tabs: const <WorkbookSheet>[
            (name: '_x0041_', number: 1),
            (name: 'a&_x0042_', number: 2),
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
          tabs: const <WorkbookSheet>[(name: 'A', number: 1)],
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
            (name: 'P&L "2026"', number: 1),
            (name: 'B', number: 2),
          ],
          activeTab: 1,
          fullCalcOnLoad: false,
        ),
      );
      expect(xml, contains('<sheet name="P&amp;L &quot;2026&quot;"'));
      expect(xml, contains('<workbookView activeTab="1"/>'));
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
