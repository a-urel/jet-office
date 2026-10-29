import 'dart:convert';

import 'package:jet_office/src/xlsx/read/package_reader.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/read/shared_strings_reader.dart';
import 'package:test/test.dart';

import 'support/zip_builder.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _wbType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';

PackageReader _package(String sst, XlsxReadLimits limits) => PackageReader(
  buildZip(<String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types"><Override PartName="/xl/workbook.xml" '
      'ContentType="$_wbType"/></Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships"><Relationship Id="rId1" Type="http://schemas.'
      'openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/></Relationships>',
    ),
    'xl/workbook.xml': utf8.encode('<workbook xmlns="$_main"/>'),
    'xl/sharedStrings.xml': utf8.encode(sst),
  }),
  limits,
);

List<String> _strings(
  String body, {
  XlsxReadLimits limits = const XlsxReadLimits(),
  String root = 'sst',
}) {
  final PackageReader p = _package(
    '<$root xmlns="$_main">$body</$root>',
    limits,
  );
  return readSharedStrings(p, 'xl/sharedStrings.xml', limits);
}

XlsxReadException _failure(void Function() body) {
  try {
    body();
  } on XlsxReadException catch (e) {
    return e;
  }
  throw StateError('expected an XlsxReadException');
}

void main() {
  test('skips phonetic runs', () {
    expect(
      _strings(
        '<si><t>東京</t><rPh sb="0" eb="2"><t>トウキョウ</t></rPh>'
        '<phoneticPr fontId="1"/></si>',
      ),
      <String>['東京'],
    );
  });

  test('keeps a whitespace-only <t> as written', () {
    expect(_strings('<si><t xml:space="preserve">  </t></si>'), <String>['  ']);
  });

  test('skips phonetic text between runs', () {
    expect(
      _strings(
        '<si><r><t>a</t></r><rPh sb="0" eb="1"><t>X</t></rPh>'
        '<r><t>b</t></r></si>',
      ),
      <String>['ab'],
    );
  });

  test('joins runs and decodes escapes', () {
    expect(
      _strings(
        '<si><r><t>a</t></r><r><rPr><b/></rPr>'
        '<t xml:space="preserve"> _x005F_x0041_</t></r></si><si/>',
      ),
      <String>['a _x0041_', ''],
    );
  });

  test('decodes each <t> on its own, as Excel and the writer do', () {
    // An escape split across two runs is literal text, not `A`.
    expect(
      _strings(
        '<si><r><t>_x00</t></r><r><t>41_</t></r></si>'
        '<si><t>_x00</t><r><t>41_</t></r></si>'
        '<si><r><t>_x0041_</t></r><r><t>_x0042_</t></r></si>',
      ),
      <String>['_x0041_', '_x0041_', 'AB'],
    );
  });

  test('joins a direct text and runs in order', () {
    expect(
      _strings('<si><t>a</t><r><t>b</t></r><r><t/></r><r><t>c</t></r></si>'),
      <String>['abc'],
    );
  });

  test('reads CDATA and entities', () {
    expect(_strings('<si><t>a &amp; <![CDATA[<b>]]></t></si>'), <String>[
      'a & <b>',
    ]);
  });

  test('reads prefixed elements', () {
    final PackageReader p = _package(
      '<x:sst xmlns:x="$_main"><x:si><x:r><x:t>p</x:t></x:r></x:si></x:sst>',
      const XlsxReadLimits(),
    );
    expect(
      readSharedStrings(p, 'xl/sharedStrings.xml', const XlsxReadLimits()),
      <String>['p'],
    );
  });

  test('an si in another namespace or nested elsewhere is not a string', () {
    expect(
      _strings(
        '<si><t>a</t></si><extLst><si><t>no</t></si></extLst>'
        '<si xmlns="urn:other"><t>no</t></si>',
      ),
      <String>['a'],
    );
  });

  test('a bad entity is a malformedXml failure naming the part', () {
    final XlsxReadException e = _failure(
      () => _strings('<si><t>&bogus;</t></si>'),
    );
    expect(e.reason, XlsxReadFailure.malformedXml);
    expect(e.part, 'xl/sharedStrings.xml');
  });

  test('enforces maxSharedStrings at one more than the limit', () {
    const XlsxReadLimits limits = XlsxReadLimits(maxSharedStrings: 2);
    expect(_strings('<si/><si/>', limits: limits), <String>['', '']);
    final XlsxReadException e = _failure(
      () => _strings('<si/><si/><si/>', limits: limits),
    );
    expect(e.reason, XlsxReadFailure.limitExceeded);
    expect(e.message, startsWith('Limit maxSharedStrings'));
    expect(e.part, 'xl/sharedStrings.xml');
  });

  test('enforces maxTextLength on the decoded string', () {
    const XlsxReadLimits limits = XlsxReadLimits(maxTextLength: 4);
    expect(_strings('<si><t>abcd</t></si>', limits: limits), <String>['abcd']);
    // 24 characters of escapes decode to 4.
    expect(
      _strings('<si><t>_x0041__x0042__x0043__x0044_</t></si>', limits: limits),
      <String>['ABCD'],
    );
    final XlsxReadException e = _failure(
      () => _strings(
        '<si><r><t>abc</t></r><r><t>de</t></r></si>',
        limits: limits,
      ),
    );
    expect(e.reason, XlsxReadFailure.limitExceeded);
    expect(e.message, startsWith('Limit maxTextLength'));
  });
}
