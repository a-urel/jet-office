// Tests tool/write_t1_check.dart: the files of the owner's T1 Word check.
// It writes files and reads the owner's folder, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_t1_check.dart';
import '../fixtures/docx_fixtures.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('t1_check'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('writes the four fixtures, each opening with DocxDocument', () {
    final List<String> written = writeT1Check('${temp.path}/t1');
    expect(
      <String>[
        for (final String p in written) p.substring(temp.path.length + 4),
      ],
      <String>[
        't1_values.docx',
        't1_merge_fields.docx',
        't1_template.docx',
        't1_merge_fields_template.docx',
      ],
    );
    for (final String p in written) {
      final DocxDocument doc = DocxDocument.open(File(p).readAsBytesSync());
      expect(doc.body.blocks, isNotEmpty, reason: p);
    }
  });

  test('the filled fixtures hold no tag and the templates do', () {
    writeT1Check('${temp.path}/t1');
    List<DocxTemplateTag> tags(String name) =>
        DocxTemplate(File('${temp.path}/t1/$name.docx').readAsBytesSync()).tags;
    expect(
      tags('t1_values').where((DocxTemplateTag t) => t.name == 'tutar'),
      isEmpty,
    );
    expect(tags('t1_template'), isNotEmpty);
    expect(tags('t1_merge_fields_template'), isNotEmpty);
    expect(
      docxFixtures().map((DocxFixture f) => f.name),
      containsAll(<String>['t1_values', 't1_template']),
    );
  });

  test('fills each owner template into owner/', () {
    final Directory owner = Directory('${temp.path}/in')..createSync();
    File(
      '${owner.path}/template_invoice.docx',
    ).writeAsBytesSync(t1ValuesTemplate());
    File('${owner.path}/blank.docx').writeAsBytesSync(t1ValuesTemplate());
    final List<String> written = writeT1Check(
      '${temp.path}/t1',
      ownerDir: owner.path,
    );
    expect(written.last, endsWith('owner/template_invoice.docx'));
    expect(written, hasLength(5));
    final DocxTemplate filled = DocxTemplate(
      File(written.last).readAsBytesSync(),
    );
    expect(
      filled.tags.where((DocxTemplateTag t) => t.name == 'tutar'),
      isEmpty,
    );
  });

  test('says when the owner folder has no template and still succeeds', () {
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    final Directory owner = Directory('${temp.path}/in')..createSync();
    final int code = runT1Check(
      <String>['${temp.path}/t1'],
      out: out,
      err: err,
      ownerDir: owner.path,
    );
    expect(code, 0);
    expect(out.toString(), contains('no template_*.docx'));
    expect(err.toString(), isEmpty);
  });

  test('exit 2 on bad arguments, 1 on an error', () {
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(runT1Check(<String>[], out: out, err: err), 2);
    expect(runT1Check(<String>['a', 'b'], out: out, err: err), 2);
    expect(err.toString(), contains('usage'));
    final File blocker = File('${temp.path}/file')..writeAsStringSync('x');
    expect(runT1Check(<String>['${blocker.path}/sub'], out: out, err: err), 1);
  });
}
