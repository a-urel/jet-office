@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_list_into.dart';

void main() {
  late Directory temp;
  late Directory input;
  late Directory output;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('write_list_into_test');
    input = Directory('${temp.path}/in')..createSync();
    output = Directory('${temp.path}/out');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  int run(List<String> args, StringBuffer out, StringBuffer err) =>
      writeListInto(args, out: out, err: err);

  test('writes the list into every document and skips lock files', () {
    final List<int> blank = DocxDocument().save().bytes;
    File('${input.path}/a.docx').writeAsBytesSync(blank);
    File('${input.path}/b.docx').writeAsBytesSync(blank);
    File('${input.path}/~\$a.docx').writeAsBytesSync(<int>[1, 2]);
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(run(<String>[input.path, output.path], out, err), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), 'a.docx: written\nb.docx: written\n');
    final DocxDocument doc = DocxDocument.open(
      File('${output.path}/a.docx').readAsBytesSync(),
    );
    expect(doc.warnings, isEmpty);
    expect(doc.body.blocks.whereType<DocxTable>(), hasLength(1));
    final DocxSection last = doc.sections.last;
    expect((last.footer.blocks.single as DocxParagraph).text, 'Sayfa 1 / 1');
    expect(File('${output.path}/~\$a.docx').existsSync(), isFalse);
  });

  test('a file that cannot be opened is reported and exits 1', () {
    File('${input.path}/bad.docx').writeAsBytesSync(<int>[1, 2, 3]);
    File(
      '${input.path}/good.docx',
    ).writeAsBytesSync(DocxDocument().save().bytes);
    final StringBuffer out = StringBuffer();
    expect(run(<String>[input.path, output.path], out, StringBuffer()), 1);
    expect(out.toString(), contains('bad.docx: '));
    expect(out.toString(), contains('good.docx: written'));
  });

  test('bad arguments and an empty or missing directory exit 2', () {
    final StringBuffer err = StringBuffer();
    expect(run(<String>[], StringBuffer(), err), 2);
    expect(run(<String>['x'], StringBuffer(), err), 2);
    expect(
      run(<String>['${temp.path}/none', output.path], StringBuffer(), err),
      2,
    );
    expect(run(<String>[input.path, output.path], StringBuffer(), err), 2);
    expect(err.toString(), contains('Usage'));
  });
}
