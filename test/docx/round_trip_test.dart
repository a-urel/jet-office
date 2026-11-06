// Every D1 and D2 fixture (test/fixtures/docx_fixtures.dart) opens with the
// paragraphs it was built with, reports the warnings it should, and saves
// to a package equal to its input by the comparer of tool/src/part_compare
// (spec 4.2). A D2 fixture is also round-tripped with its styles and
// numbering loaded, and the two parts are encoded and compared as well,
// since a loaded part nothing changed is saved as it was read. The owner's
// Word files are round-tripped in owner_files_test.dart, which reads them
// from disk and runs on the VM only.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/docx_serialize.dart';
import '../../tool/src/part_compare.dart';
import '../../tool/src/text_compare.dart';
import '../fixtures/docx_fixtures.dart';
import 'support/styles_documents.dart' show readDocxText;

void main() {
  final List<DocxFixture> all = docxFixtures();
  final List<DocxFixture> fixtures = <DocxFixture>[
    for (final DocxFixture f in all)
      if (f.name.startsWith('d1_')) f,
  ];
  final List<DocxFixture> d2 = <DocxFixture>[
    for (final DocxFixture f in all)
      if (f.name.startsWith('d2_')) f,
  ];

  test('the D1 fixtures are the five the plan names, each named once', () {
    final List<String> names = <String>[
      for (final DocxFixture f in fixtures) f.name,
    ];
    expect(names.toSet(), hasLength(names.length));
    expect(
      names,
      containsAll(<String>[
        'd1_blank',
        'd1_paragraphs',
        'd1_text_rules',
        'd1_unicode',
        'd1_large',
      ]),
    );
    expect(names, hasLength(5));
  });

  test('the D2 fixtures are the four the plan names, each named once', () {
    expect(
      <String>[for (final DocxFixture f in d2) f.name],
      <String>[
        'd2_run_formatting',
        'd2_paragraph_formatting',
        'd2_styles',
        'd2_lists',
      ],
    );
    expect(all, hasLength(9));
    expect(<String>{for (final DocxFixture f in all) f.name}, hasLength(9));
  });

  test('every D1 fixture builds the same bytes every time', () {
    for (final DocxFixture f in fixtures) {
      expect(f.build().bytes, f.build().bytes, reason: f.name);
    }
  });

  test('every D1 fixture builds with exactly its expected warnings', () {
    for (final DocxFixture f in fixtures) {
      final Map<DocxWarningCode, int> counts = <DocxWarningCode, int>{};
      for (final DocxWarning w in f.build().warnings) {
        counts[w.code] = (counts[w.code] ?? 0) + w.count;
      }
      expect(counts, f.expectedWarnings, reason: f.name);
    }
  });

  test('d1_text_rules expects one removed character', () {
    final DocxFixture f = fixtures.singleWhere(
      (DocxFixture f) => f.name == 'd1_text_rules',
    );
    expect(f.expectedWarnings, <DocxWarningCode, int>{
      DocxWarningCode.invalidCharactersRemoved: 1,
    });
  });

  test('d1_large holds 2,000 paragraphs', () {
    final DocxFixture f = fixtures.singleWhere(
      (DocxFixture f) => f.name == 'd1_large',
    );
    final DocxDocument doc = DocxDocument.open(f.build().bytes);
    expect(doc.body.blocks, hasLength(2000));
  });

  test('every D1 fixture round-trips', () {
    for (final DocxFixture f in fixtures) {
      final Uint8List input = f.build().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      expect(
        doc.body.blocks.every((DocxBlock b) => b is DocxParagraph),
        isTrue,
        reason: '${f.name}: a D1 fixture holds paragraphs only',
      );
      expect(docxBodyText(doc), f.expectedText, reason: f.name);
      final DocxResult saved = doc.save();
      expect(saved.warnings, isEmpty, reason: f.name);
      final List<String> differences = comparePackages(input, saved.bytes);
      expect(
        differences,
        isEmpty,
        reason: '${f.name}\n${differences.join('\n')}',
      );
    }
  });

  group('D2', () {
    test('every D2 fixture builds the same bytes and no warnings', () {
      for (final DocxFixture f in d2) {
        final DocxResult built = f.build();
        expect(built.bytes, f.build().bytes, reason: f.name);
        expect(built.warnings, isEmpty, reason: f.name);
      }
    });

    test('every D2 fixture round-trips with styles and numbering loaded', () {
      for (final DocxFixture f in d2) {
        final Uint8List input = f.build().bytes;
        final DocxDocument doc = DocxDocument.open(input);
        expect(
          doc.body.blocks.every((DocxBlock b) => b is DocxParagraph),
          isTrue,
          reason: '${f.name}: a D2 fixture holds paragraphs only',
        );
        expect(docxBodyText(doc), f.expectedText, reason: f.name);
        expect(readTypedProperties(doc), greaterThan(0), reason: f.name);
        expect(doc.styles.styles, isNotEmpty, reason: f.name);
        doc.numbering.instances.length;
        final DocxResult saved = doc.save();
        expect(saved.warnings, isEmpty, reason: f.name);
        final List<String> differences = <String>[
          ...comparePackages(input, saved.bytes),
          ...encodedPartDifferences(input),
          ...encodedPartDifferences(saved.bytes),
          ...encodedMainDifferences(input),
        ];
        expect(
          differences,
          isEmpty,
          reason: '${f.name}\n${differences.join('\n')}',
        );
      }
    });

    test('the D2 fixtures hold the styles and numbering parts they use', () {
      for (final DocxFixture f in d2) {
        final Set<String> parts = encodedParts(f.build().bytes).keys.toSet();
        expect(parts, contains('word/styles.xml'), reason: f.name);
        expect(
          parts.contains('word/numbering.xml'),
          f.name == 'd2_lists',
          reason: f.name,
        );
      }
    });

    test('d2_run_formatting writes a theme colour with w:val="auto"', () {
      final DocxFixture f = d2.singleWhere(
        (DocxFixture f) => f.name == 'd2_run_formatting',
      );
      final String xml = readDocxText(f.build().bytes)['word/document.xml']!;
      expect(
        RegExp(
          r'<w:color [^>]*w:val="auto"[^>]*w:themeColor="accent1"'
          r'|<w:color [^>]*w:themeColor="accent1"[^>]*w:val="auto"',
        ).hasMatch(xml),
        isTrue,
        reason: xml,
      );
    });

    test(
      'd2_lists lists LibreOffice\'s labels apart from the model\'s text',
      () {
        final DocxFixture f = d2.singleWhere(
          (DocxFixture f) => f.name == 'd2_lists',
        );
        expect(f.libreOfficeText, isNot(f.expectedText));
        expect(f.libreOfficeText, contains('    \u2022 Bullet one'));
        expect(f.libreOfficeText, contains('    1. Num one'));
        for (final DocxFixture other in all) {
          if (other.name == 'd2_lists') continue;
          expect(other.libreOfficeText, other.expectedText, reason: other.name);
        }
      },
    );

    test('d2_paragraph_formatting reads back its properties', () {
      final DocxFixture f = d2.singleWhere(
        (DocxFixture f) => f.name == 'd2_paragraph_formatting',
      );
      final DocxDocument doc = DocxDocument.open(f.build().bytes);
      final List<DocxParagraph> p = <DocxParagraph>[
        for (final DocxBlock b in doc.body.blocks) b as DocxParagraph,
      ];
      DocxParagraphProperties of(String text) =>
          p.singleWhere((DocxParagraph x) => x.text == text).properties;
      expect(p.first.properties.pageBreakBefore, isTrue);
      expect(of('Alignment center').alignment, DocxAlignment.center);
      expect(of('Keep with next').keepWithNext, isTrue);
      expect(of('Widow control off').widowControl, isFalse);
      expect(of('Outline level 2').outlineLevel, 1);
      expect(
        of('Indentation left 54, hanging 27').indentation,
        DocxIndentation(leftPt: 54, hangingPt: 27),
      );
      expect(of('Tab stops:\tleft\tcenter\tright').tabs, hasLength(3));
      expect(
        of('Borders: a red box and a rule between').borders!.top,
        isNotNull,
      );
    });

    test('d2_run_formatting reads back its properties', () {
      final DocxFixture f = d2.singleWhere(
        (DocxFixture f) => f.name == 'd2_run_formatting',
      );
      final DocxDocument doc = DocxDocument.open(f.build().bytes);
      DocxRunProperties of(String text) => <DocxRun>[
        for (final DocxBlock b in doc.body.blocks)
          ...(b as DocxParagraph).inlines.whereType<DocxRun>(),
      ].singleWhere((DocxRun r) => r.text == text).properties;
      expect(of('Bold').bold, isTrue);
      expect(of('Size 9.5').sizePt, 9.5);
      expect(of('Language de-DE').language, 'de-DE');
      expect(
        of('Underline double red').underline,
        DocxUnderline(
          DocxUnderlineStyle.double,
          color: DocxColor.rgb('FF0000'),
        ),
      );
      expect(
        of('Color theme accent1 shade').color,
        DocxColor.theme(DocxThemeColor.accent1, shade: 191),
      );
      expect(of('Superscript').verticalAlign, DocxVerticalAlign.superscript);
    });

    test('d2_lists restarts a numbered list with a start override', () {
      final DocxFixture f = d2.singleWhere(
        (DocxFixture f) => f.name == 'd2_lists',
      );
      final DocxDocument doc = DocxDocument.open(f.build().bytes);
      final DocxNumbering numbering = doc.numbering;
      expect(numbering.instances, hasLength(3));
      final DocxNumberingInstance restarted = numbering.instances.last;
      expect(restarted.overrides.single.level, 0);
      expect(restarted.overrides.single.startOverride, 1);
      expect(
        restarted.abstractId,
        numbering.instances[1].abstractId,
        reason: 'the same definition as the numbered list',
      );
    });
  });
}
