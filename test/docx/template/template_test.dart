// Tests the public `DocxTemplate` of decision 0024 (T1): fill a template
// twice, its tags, the copy it keeps of its bytes, the warnings of a fill and
// its save, the fill of a held document, and that data naming nothing gives
// every fixture back unchanged. The owner's Word files are in
// `template_owner_test.dart` (VM only). Documents are built in memory, so the
// tests run on the web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/docx_fixtures.dart';
import '../support/styles_documents.dart' show readDocxText;
import '../support/template_documents.dart';

String _text(Uint8List bytes) => readDocxText(bytes).values.join('\n');

String _run(String text) => '<w:r><w:t xml:space="preserve">$text</w:t></w:r>';

Uint8List _template() => templateDocument(<String>[
  _run('Dear {{musteri.unvan}}, total {{tutar:0.00}}'),
  _run('{{#items}}{{.}}{{/items}} {{DOLDURULMAZ}}'),
]);

void main() {
  test('fill twice gives two documents with their own values', () {
    final DocxTemplate template = DocxTemplate(_template());
    final List<DocxTemplateTag> before = template.tags;
    final DocxResult a = template.fill(<String, Object?>{
      'musteri': <String, Object?>{'unvan': 'Acme'},
      'tutar': 1.5,
    });
    final DocxResult b = template.fill(<String, Object?>{
      'musteri': <String, Object?>{'unvan': 'Beta'},
      'tutar': 2,
    });
    final String ta = _text(a.bytes);
    final String tb = _text(b.bytes);
    expect(ta, contains('Dear Acme, total 1.50'));
    expect(tb, contains('Dear Beta, total 2.00'));
    expect(ta, isNot(contains('Beta')));
    expect(
      template.tags.map((DocxTemplateTag t) => t.text).toList(),
      before.map((DocxTemplateTag t) => t.text).toList(),
    );
    expect(template.tags, hasLength(before.length));
  });

  test('tags list kinds, names, formats and depth in reading order', () {
    final List<DocxTemplateTag> tags = DocxTemplate(_template()).tags;
    expect(
      tags.map((DocxTemplateTag t) => t.kind).toList(),
      <DocxTemplateTagKind>[
        DocxTemplateTagKind.value,
        DocxTemplateTagKind.value,
        DocxTemplateTagKind.section,
        DocxTemplateTagKind.current,
        DocxTemplateTagKind.sectionEnd,
        DocxTemplateTagKind.value,
      ],
    );
    expect(tags[0].name, 'musteri.unvan');
    expect(tags[1].name, 'tutar');
    expect(tags[1].format, '0.00');
    expect(tags[3].name, isNull);
    expect(tags[3].depth, 1);
    expect(tags[0].part, '/word/document.xml');
    expect(tags[0].location, 'body/p[0]');
    expect(tags[0].problem, isNull);
  });

  test('a malformed tag has the kind malformed and no name', () {
    final DocxTemplate template = DocxTemplate(
      templateDocument(<String>[_run('{{a b c')]),
    );
    final DocxTemplateTag tag = template.tags.single;
    expect(tag.kind, DocxTemplateTagKind.malformed);
    expect(tag.name, isNull);
    expect(tag.problem, isNotNull);
  });

  test('template bytes are copied', () {
    final Uint8List bytes = Uint8List.fromList(_template());
    final DocxTemplate template = DocxTemplate(bytes);
    bytes.fillRange(0, bytes.length, 0);
    final DocxResult result = template.fill(<String, Object?>{
      'musteri': <String, Object?>{'unvan': 'Acme'},
    });
    expect(_text(result.bytes), contains('Dear Acme'));
  });

  test('data naming nothing gives every fixture back', () {
    for (final fixture in docxFixtures()) {
      final Uint8List bytes = fixture.build().bytes;
      final DocxResult result = DocxTemplate(bytes).fill(<String, Object?>{});
      expect(
        comparePackages(bytes, result.bytes),
        isEmpty,
        reason: fixture.name,
      );
    }
  });

  test('fill warnings are the fill\'s, then the save\'s', () {
    final DocxTemplate template = DocxTemplate(
      templateDocument(<String>[_run('{{yok}} {{var}}')]),
    );
    final DocxResult result = template.fill(<String, Object?>{
      'var': 'a\u0001b',
    });
    expect(
      result.warnings.map((DocxWarning w) => w.code).toList(),
      <DocxWarningCode>[
        DocxWarningCode.templateValueMissing,
        DocxWarningCode.invalidCharactersRemoved,
      ],
    );
  });

  test('options: locale and removeMissing', () {
    final DocxTemplate template = DocxTemplate(
      templateDocument(<String>[_run('[{{yok}}] {{n:#,##0.00}}')]),
    );
    final DocxResult result = template.fill(
      <String, Object?>{'n': FormatDecimal('1234.56')},
      options: const DocxTemplateOptions(
        locale: FormatLocale.trTR,
        removeMissing: true,
      ),
    );
    expect(_text(result.bytes), contains('[] 1.234,56'));
  });

  test('an unreadable file throws DocxReadException', () {
    expect(() => DocxTemplate(Uint8List(0)), throwsA(isA<DocxReadException>()));
  });

  test('fillDocument fills in place and the document still edits', () {
    final DocxDocument document = DocxDocument.open(_template());
    final List<DocxWarning> warnings = DocxTemplate.fillDocument(
      document,
      <String, Object?>{
        'musteri': <String, Object?>{'unvan': 'Acme'},
      },
    );
    expect(
      warnings.map((DocxWarning w) => w.code),
      contains(DocxWarningCode.templateValueMissing),
    );
    expect(DocxTemplate.tagsOf(document), isNotEmpty);
    document.body.addParagraph('x');
    final String text = _text(document.save().bytes);
    expect(text, contains('Dear Acme'));
    expect(text, contains('x'));
  });
}
