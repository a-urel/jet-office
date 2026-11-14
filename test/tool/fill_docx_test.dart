// Tests tool/fill_docx.dart: every document of a directory filled with the
// fixed Turkish data, for the Open XML SDK to validate. It reads and writes
// files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/fill_docx.dart';
import '../../tool/src/text_compare.dart' show docxFullText, docxStoriesText;
import '../docx/support/docx_builder.dart' show rewriteDocxPart;
import '../docx/support/template_documents.dart';
import '../fixtures/docx_fixtures.dart';

void main() {
  late Directory temp;
  late Directory input;
  late Directory output;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fill_docx_test');
    input = Directory('${temp.path}/in')..createSync();
    output = Directory('${temp.path}/out');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Uint8List fixture(String name) => docxFixtures()
      .singleWhere((DocxFixture f) => f.name == name)
      .build()
      .bytes;

  void put(String name, List<int> bytes) =>
      File('${input.path}/$name').writeAsBytesSync(bytes);

  int run({
    StringBuffer? out,
    StringBuffer? err,
    Uint8List Function(String name, Uint8List saved)? corruptForTest,
  }) => runFillDocx(
    <String>[input.path, output.path],
    out: out ?? StringBuffer(),
    err: err ?? StringBuffer(),
    corruptForTest: corruptForTest,
  );

  List<String> written() => <String>[
    for (final FileSystemEntity e in output.listSync()) e.uri.pathSegments.last,
  ];

  test('fills the template and a document without tags: exit 0', () {
    put('t1_template.docx', fixture('t1_template'));
    put('d4_headers.docx', fixture('d4_headers'));
    put(r'~$t1_template.docx', <int>[1, 2]);
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(
      run(out: out, err: err),
      0,
      reason: '$out$err',
    );
    expect(err.toString(), isEmpty);
    expect(
      written(),
      unorderedEquals(<String>['t1_template.docx', 'd4_headers.docx']),
    );
    expect(out.toString(), contains('All 2 documents filled.'));
    final DocxDocument filled = DocxDocument.open(
      File('${output.path}/t1_template.docx').readAsBytesSync(),
    );
    final DocxFixture values = docxFixtures().singleWhere(
      (DocxFixture f) => f.name == 't1_values',
    );
    // The tool fills with the data the t1_values fixture was filled with.
    expect(docxFullText(filled), values.expectedText);
    expect(docxStoriesText(filled), values.headerFooterText);
  });

  test('the data is the fixed Turkish set', () {
    final Map<String, Object?> data = fillDocxData();
    expect(data['tarih'], DateTime(2026, 11, 14));
    expect(data['tutar'], FormatDecimal('1234.56'));
    expect(data['miktar'], FormatDecimal('2.5'));
    expect((data['firma']! as Map<String, Object?>).keys, <String>[
      'unvan',
      'adres',
    ]);
    expect(data.keys, containsAll(<String>['Ad', 'Müşteri Adı', 'Tarih']));
    expect(dataHasPath(data, 'firma.unvan'), isTrue);
    expect(dataHasPath(data, 'firma.yok'), isFalse);
    expect(dataHasPath(data, 'tarih.gun'), isFalse);
  });

  test('fills the merge fields: exit 0', () {
    put('t1_merge_fields_template.docx', t1MergeFieldsTemplate());
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final DocxDocument filled = DocxDocument.open(
      File('${output.path}/t1_merge_fields_template.docx').readAsBytesSync(),
    );
    final DocxFixture merge = docxFixtures().singleWhere(
      (DocxFixture f) => f.name == 't1_merge_fields',
    );
    expect(docxFullText(filled), merge.expectedText);
    expect(DocxTemplate.tagsOf(filled), isEmpty);
  });

  test('reports a header changed where only an unfillable tag is', () {
    // `{{musteri.ad}}` in a tracked insertion is listed with a problem and
    // left as written, so its header may not change.
    put(
      'insertion.docx',
      templateWithHeader(
        headerInline: tagInInsertion('{{musteri.ad}}'),
        bodyInline: templateRun('{{firma.unvan}}'),
      ),
    );
    expect(run(), 0);
    final StringBuffer out = StringBuffer();
    expect(
      run(
        out: out,
        corruptForTest: (String name, Uint8List saved) => rewriteDocxPart(
          saved,
          'word/header1.xml',
          (String xml) => xml.replaceFirst('</w:hdr>', '<w:p/></w:hdr>'),
        ),
      ),
      1,
    );
    expect(
      out.toString(),
      contains(
        'insertion.docx: a part outside the allowed set: '
        'word/header1.xml',
      ),
    );
  });

  test('bad arguments: exit 2', () {
    final StringBuffer err = StringBuffer();
    expect(runFillDocx(<String>[], out: StringBuffer(), err: err), 2);
    expect(err.toString(), contains('Usage'));
    expect(
      runFillDocx(
        <String>['${temp.path}/none', output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      2,
    );
    // A directory without a .docx.
    expect(run(), 2);
  });

  test('a truncated copy: exit 1, named', () {
    final Uint8List bytes = fixture('t1_template');
    put('t1_template.docx', bytes);
    put('broken.docx', Uint8List.sublistView(bytes, 0, bytes.length ~/ 2));
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 1);
    expect(out.toString(), contains('broken.docx: '));
    expect(out.toString(), isNot(contains('t1_template.docx: ')));
    expect(out.toString(), contains('1 of 2 documents failed.'));
  });

  test('reports a filled tag still in the text', () {
    put('t1_template.docx', fixture('t1_template'));
    final StringBuffer out = StringBuffer();
    expect(
      run(
        out: out,
        corruptForTest: (String name, Uint8List saved) => rewriteDocxPart(
          saved,
          'word/document.xml',
          (String xml) => xml.replaceFirst('Saygılarımızla.', '{{miktar}}'),
        ),
      ),
      1,
    );
    expect(out.toString(), contains('t1_template.docx: '));
    expect(out.toString(), contains('{{miktar}}'));
  });

  test('reports a missing tag that was removed', () {
    put('t1_template.docx', fixture('t1_template'));
    final StringBuffer out = StringBuffer();
    expect(
      run(
        out: out,
        corruptForTest: (String name, Uint8List saved) => rewriteDocxPart(
          saved,
          'word/document.xml',
          (String xml) => xml.replaceFirst('{{yok}}', ''),
        ),
      ),
      1,
    );
    expect(out.toString(), contains('{{yok}}'));
  });

  test('reports a merge field left whose name the data has', () {
    put('t1_merge_fields.docx', fixture('t1_merge_fields'));
    final StringBuffer out = StringBuffer();
    expect(
      run(
        out: out,
        corruptForTest: (String name, Uint8List saved) => rewriteDocxPart(
          saved,
          'word/document.xml',
          (String xml) => xml.replaceFirst(
            'Saygılarımızla.</w:t></w:r>',
            'Saygılarımızla.</w:t></w:r>'
                '<w:fldSimple w:instr=" MERGEFIELD Ad "><w:r><w:t>«Ad»</w:t>'
                '</w:r></w:fldSimple>',
          ),
        ),
      ),
      1,
    );
    expect(out.toString(), contains('MERGEFIELD Ad'));
  });

  test('reports a part outside the allowed set', () {
    put('d4_headers.docx', fixture('d4_headers'));
    final StringBuffer out = StringBuffer();
    expect(
      run(
        out: out,
        corruptForTest: (String name, Uint8List saved) => rewriteDocxPart(
          saved,
          'word/header1.xml',
          (String xml) => xml.replaceFirst('Header one', 'Header two'),
        ),
      ),
      1,
    );
    expect(out.toString(), contains('word/header1.xml'));
  });

  test('reports a changed [Content_Types].xml', () {
    put('t1_template.docx', fixture('t1_template'));
    final StringBuffer out = StringBuffer();
    expect(
      run(
        out: out,
        corruptForTest: (String name, Uint8List saved) => rewriteDocxPart(
          saved,
          '[Content_Types].xml',
          (String xml) => xml.replaceFirst(
            '</Types>',
            '<Default Extension="png" ContentType="image/png"/></Types>',
          ),
        ),
      ),
      1,
    );
    expect(out.toString(), contains('[Content_Types].xml'));
  });
}
