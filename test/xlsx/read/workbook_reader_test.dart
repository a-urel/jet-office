import 'dart:convert';

import 'package:jet_office/src/xlsx/read/package_reader.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/read/workbook_reader.dart';
import 'package:jet_office/src/xlsx/sheet_view.dart';
import 'package:test/test.dart';

import 'support/zip_builder.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _wbType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';

PackageReader _package(
  String workbook, {
  Map<String, String> rels = const <String, String>{},
  Set<String> parts = const <String>{},
}) => PackageReader(
  buildZip(<String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types"><Override PartName="/xl/workbook.xml" '
      'ContentType="$_wbType"/></Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships"><Relationship Id="rId1" Type="$_rel/officeDocument" '
      'Target="xl/workbook.xml"/></Relationships>',
    ),
    'xl/workbook.xml': utf8.encode(workbook),
    'xl/_rels/workbook.xml.rels': utf8.encode(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">'
      '${rels.entries.map((e) => '<Relationship Id="${e.key}" Type="$_rel/worksheet" Target="${e.value}"/>').join()}'
      '</Relationships>',
    ),
    for (final String p in parts) p: utf8.encode('<worksheet xmlns="$_main"/>'),
  }),
  const XlsxReadLimits(),
);

String _wb(String body) =>
    '<workbook xmlns="$_main" xmlns:r="$_rel">$body</workbook>';

void main() {
  test('lists sheets in order with visibility and keeps a missing part', () {
    final PackageReader p = _package(
      _wb(
        '<sheets>'
        '<sheet name="A &amp; B" sheetId="1" r:id="rId1"/>'
        '<sheet name="Hid" sheetId="2" state="hidden" r:id="rId2"/>'
        '<sheet name="Very" sheetId="3" state="veryHidden" r:id="rId3"/>'
        '<sheet name="Odd" sheetId="4" state="bogus" r:id="rId4"/>'
        '<sheet name="NoRel" sheetId="5" r:id="rId9"/>'
        '<sheet name="NoId" sheetId="6"/>'
        '<sheet name="NoPart" sheetId="7" r:id="rId5"/>'
        '</sheets>',
      ),
      rels: <String, String>{
        'rId1': 'worksheets/sheet1.xml',
        'rId2': '/xl/worksheets/sheet2.xml',
        'rId3': 'worksheets/sheet3.xml',
        'rId4': 'worksheets/sheet4.xml',
        'rId5': 'worksheets/missing.xml',
      },
      parts: <String>{
        'xl/worksheets/sheet1.xml',
        'xl/worksheets/sheet2.xml',
        'xl/worksheets/sheet3.xml',
        'xl/worksheets/sheet4.xml',
      },
    );
    final WorkbookInfo info = readWorkbook(p);
    expect(info.date1904, isFalse);
    expect(
      <(String, XlsxSheetVisibility, String?)>[
        for (final WorkbookSheet s in info.sheets)
          (s.name, s.visibility, s.part),
      ],
      <(String, XlsxSheetVisibility, String?)>[
        ('A & B', XlsxSheetVisibility.visible, 'xl/worksheets/sheet1.xml'),
        ('Hid', XlsxSheetVisibility.hidden, 'xl/worksheets/sheet2.xml'),
        ('Very', XlsxSheetVisibility.veryHidden, 'xl/worksheets/sheet3.xml'),
        ('Odd', XlsxSheetVisibility.visible, 'xl/worksheets/sheet4.xml'),
        ('NoRel', XlsxSheetVisibility.visible, null),
        ('NoId', XlsxSheetVisibility.visible, null),
        ('NoPart', XlsxSheetVisibility.visible, null),
      ],
    );
  });

  test('decodes escapes in sheet names', () {
    final PackageReader p = _package(
      _wb('<sheets><sheet name="a_x0009_b" r:id="rId1"/></sheets>'),
    );
    expect(readWorkbook(p).sheets.single.name, 'a\tb');
  });

  test('a workbook without sheets has none', () {
    expect(readWorkbook(_package(_wb(''))).sheets, isEmpty);
    expect(readWorkbook(_package(_wb('<sheets/>'))).sheets, isEmpty);
  });

  test('reads date1904 as 1 or true', () {
    for (final (String, bool) c in <(String, bool)>[
      ('<workbookPr date1904="1"/>', true),
      ('<workbookPr date1904="true"/>', true),
      ('<workbookPr date1904="0"/>', false),
      ('<workbookPr date1904="false"/>', false),
      ('<workbookPr/>', false),
      ('', false),
    ]) {
      expect(readWorkbook(_package(_wb(c.$1))).date1904, c.$2, reason: c.$1);
    }
  });

  test('reads prefixed elements', () {
    final PackageReader p = _package(
      '<x:workbook xmlns:x="$_main" xmlns:q="$_rel">'
      '<x:workbookPr date1904="1"/>'
      '<x:sheets><x:sheet name="P" state="hidden" q:id="rId1"/></x:sheets>'
      '</x:workbook>',
      rels: <String, String>{'rId1': 'worksheets/s.xml'},
      parts: <String>{'xl/worksheets/s.xml'},
    );
    final WorkbookInfo info = readWorkbook(p);
    expect(info.date1904, isTrue);
    expect(info.sheets.single.name, 'P');
    expect(info.sheets.single.visibility, XlsxSheetVisibility.hidden);
    expect(info.sheets.single.part, 'xl/worksheets/s.xml');
  });

  test('ignores sheet elements outside the sheets list', () {
    final PackageReader p = _package(
      _wb(
        '<extLst><sheet name="no" r:id="rId1"/></extLst>'
        '<sheets><sheet name="yes" r:id="rId1"/></sheets>',
      ),
      rels: <String, String>{'rId1': 'worksheets/s.xml'},
      parts: <String>{'xl/worksheets/s.xml'},
    );
    expect(readWorkbook(p).sheets.map((WorkbookSheet s) => s.name), <String>[
      'yes',
    ]);
  });

  test('malformed workbook XML names the workbook part', () {
    final PackageReader p = _package(_wb('<sheets><sheet name="&bogus;"/>'));
    try {
      readWorkbook(p);
      fail('expected an exception');
    } on XlsxReadException catch (e) {
      expect(e.reason, XlsxReadFailure.malformedXml);
      expect(e.part, 'xl/workbook.xml');
    }
  });
}
