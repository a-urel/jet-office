// Tests tool/write_t2_check.dart: the files of the owner's T2 Word check.
// It writes files and reads the owner's folder, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_t2_check.dart';
import '../fixtures/docx_fixtures.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('t2_check'));
  tearDown(() => temp.deleteSync(recursive: true));

  DocxDocument open(String path) =>
      DocxDocument.open(File(path).readAsBytesSync());

  test('writes the seven files, each opening with DocxDocument', () {
    final Directory owner = Directory('${temp.path}/none')..createSync();
    final List<String> written = writeT2Check(
      '${temp.path}/t2',
      ownerDir: owner.path,
    );
    expect(
      <String>[
        for (final String p in written) p.substring(temp.path.length + 4),
      ],
      <String>[
        't2_values.docx',
        't2_empty.docx',
        't2_template.docx',
        't2_nested.docx',
        't2_nested_template.docx',
        't2_lines_1.docx',
        't2_lines_40.docx',
      ],
    );
    for (final String p in written) {
      expect(open(p).body.blocks, isNotEmpty, reason: p);
    }
  });

  test('t2_lines_40 has 40 lines between its header row and totals row', () {
    final Directory owner = Directory('${temp.path}/none')..createSync();
    writeT2Check('${temp.path}/t2', ownerDir: owner.path);
    final DocxTable lines40 = open(
      '${temp.path}/t2/t2_lines_40.docx',
    ).body.blocks.whereType<DocxTable>().single;
    expect(lines40.rows, hasLength(42));
    expect(lines40.rows.first.properties.repeatAsHeader, isTrue);
    expect(lines40.rows[40].cells.first.text, 'Kalem 40');
    expect(lines40.rows.last.cells.last.text, '410,00 ₺');
    final DocxDocument lines1 = open('${temp.path}/t2/t2_lines_1.docx');
    expect(lines1.body.blocks.whereType<DocxTable>().single.rows, hasLength(3));
    expect(
      lines1.body.blocks.whereType<DocxParagraph>().map(
        (DocxParagraph p) => p.text,
      ),
      contains('Durum: Ödendi'),
    );
    expect(
      open(
        '${temp.path}/t2/t2_lines_40.docx',
      ).body.blocks.whereType<DocxParagraph>().map((DocxParagraph p) => p.text),
      contains('Durum: Ödenmedi'),
    );
  });

  test('fills each owner invoice three times and each other template once', () {
    final Directory owner = Directory('${temp.path}/in')..createSync();
    File(
      '${owner.path}/template_invoice.docx',
    ).writeAsBytesSync(t2ValuesTemplate());
    File(
      '${owner.path}/template_letter.docx',
    ).writeAsBytesSync(t1ValuesTemplate());
    File('${owner.path}/blank.docx').writeAsBytesSync(t1ValuesTemplate());
    final List<String> written = writeT2Check(
      '${temp.path}/t2',
      ownerDir: owner.path,
    );
    expect(
      <String>[for (final String p in written.skip(7)) p.split('/t2/').last],
      <String>[
        'owner/template_invoice_1.docx',
        'owner/template_invoice_40.docx',
        'owner/template_invoice_0.docx',
        'owner/template_letter.docx',
      ],
    );
    final DocxTable none = open(
      written[9],
    ).body.blocks.whereType<DocxTable>().single;
    expect(none.rows, hasLength(2));
    expect(
      DocxTemplate(
        File(written[10]).readAsBytesSync(),
      ).tags.where((DocxTemplateTag t) => t.name == 'tutar'),
      isEmpty,
    );
  });

  test('says when the owner folder has no template and still succeeds', () {
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    final Directory owner = Directory('${temp.path}/in')..createSync();
    final int code = runT2Check(
      <String>['${temp.path}/t2'],
      out: out,
      err: err,
      ownerDir: owner.path,
    );
    expect(code, 0);
    expect(out.toString(), contains('no template_*.docx'));
    expect(Directory('${temp.path}/t2/owner').existsSync(), isFalse);
    expect(err.toString(), isEmpty);
  });

  test('exit 2 on bad arguments, 1 on an error', () {
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(runT2Check(<String>[], out: out, err: err), 2);
    expect(runT2Check(<String>['a', 'b'], out: out, err: err), 2);
    expect(err.toString(), contains('usage'));
    final File blocker = File('${temp.path}/file')..writeAsStringSync('x');
    expect(runT2Check(<String>['${blocker.path}/sub'], out: out, err: err), 1);
  });
}
