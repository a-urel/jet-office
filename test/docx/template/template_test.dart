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
import '../../../tool/src/text_compare.dart' show docxFullText, docxStoriesText;
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

  test('t1_values: the fixed data fills the split, formatted, coloured, '
      'header, footer and table tags, and leaves {{yok}}', () {
    final DocxFixture fixture = docxFixtures().singleWhere(
      (DocxFixture f) => f.name == 't1_values',
    );
    final DocxResult result = fixture.build();
    final DocxDocument doc = DocxDocument.open(result.bytes);
    final String text = docxFullText(doc);
    expect(text, fixture.expectedText);
    expect(text, contains('Firma: Acme A.Ş.'));
    expect(text, contains('Tarih: 14.11.2026'));
    expect(text, contains('Tutar: 1.234,56 ₺'));
    expect(text, contains('14.11.2026\t1.234,56 ₺'));
    expect(text, contains('Eksik: {{yok}}'));
    expect(text, isNot(contains('{{firma')));
    expect(docxStoriesText(doc), fixture.headerFooterText);
    expect(
      result.warnings.map((DocxWarning w) => (w.code, w.detail)).toList(),
      <(DocxWarningCode, String?)>[
        (DocxWarningCode.templateValueMissing, '{{yok}}'),
      ],
    );
    // The first brace's bold run keeps the filled value; the coloured tag
    // keeps its colour.
    final List<DocxParagraph> paragraphs = doc.body.blocks
        .whereType<DocxParagraph>()
        .toList();
    final DocxRun firma = paragraphs[0].inlines.whereType<DocxRun>().firstWhere(
      (DocxRun r) => r.text.contains('Acme'),
    );
    expect(firma.properties.bold, isTrue);
    final DocxRun musteri = paragraphs[4].inlines
        .whereType<DocxRun>()
        .firstWhere((DocxRun r) => r.text.contains('Ayşe'));
    expect(musteri.properties.color, DocxColor.rgb('C00000'));
  });

  test('t1_template lists its tags; t1_merge_fields fills every field', () {
    DocxFixture fixture(String name) =>
        docxFixtures().singleWhere((DocxFixture f) => f.name == name);
    final DocxTemplate template = DocxTemplate(
      fixture('t1_template').build().bytes,
    );
    expect(
      template.tags.map((DocxTemplateTag t) => (t.name, t.part)).toList(),
      <(String?, String)>[
        ('firma.unvan', '/word/document.xml'),
        ('firma.adres', '/word/document.xml'),
        ('tarih', '/word/document.xml'),
        ('tutar', '/word/document.xml'),
        ('musteri.ad', '/word/document.xml'),
        ('miktar', '/word/document.xml'),
        ('firma.unvan', '/word/document.xml'),
        ('musteri.ad', '/word/document.xml'),
        ('tarih', '/word/document.xml'),
        ('tutar', '/word/document.xml'),
        ('miktar', '/word/document.xml'),
        ('firma.adres', '/word/document.xml'),
        ('yok', '/word/document.xml'),
        ('firma.unvan', '/word/header1.xml'),
        ('tarih', '/word/footer1.xml'),
      ],
    );
    expect(
      template.tags.every((DocxTemplateTag t) => t.problem == null),
      isTrue,
    );
    final DocxFixture merge = fixture('t1_merge_fields');
    final DocxResult filled = merge.build();
    expect(filled.warnings, isEmpty);
    final DocxDocument doc = DocxDocument.open(filled.bytes);
    expect(docxFullText(doc), merge.expectedText);
    expect(DocxTemplate.tagsOf(doc), isEmpty);
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

  test('a header that cannot be read throws and changes nothing', () {
    final Uint8List bytes = templateWithHeader(
      headerInline: '<w:r><w:t>{{a}}</w:r>',
      bodyInline: _run('{{a}}'),
    );
    final DocxDocument document = DocxDocument.open(bytes);
    expect(
      () => DocxTemplate.fillDocument(document, <String, Object?>{'a': 'A'}),
      throwsA(isA<DocxReadException>()),
    );
    final DocxParagraph p = document.body.blocks.first as DocxParagraph;
    expect(p.text, '{{a}}');
    expect(() => DocxTemplate(bytes), throwsA(isA<DocxReadException>()));
  });

  test('tags cannot be modified', () {
    final DocxTemplate template = DocxTemplate(_template());
    final DocxTemplateTag first = template.tags.first;
    expect(() => template.tags[0] = first, throwsUnsupportedError);
    final List<DocxTemplateTag> held = DocxTemplate.tagsOf(
      DocxDocument.open(_template()),
    );
    expect(() => held[0] = held[1], throwsUnsupportedError);
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
