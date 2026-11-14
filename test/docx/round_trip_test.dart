// Every DOCX fixture (test/fixtures/docx_fixtures.dart) opens with the
// paragraphs it was built with, reports the warnings it should, and saves
// to a package equal to its input by the comparer of tool/src/part_compare
// (spec 4.2). A D2 fixture is also round-tripped with its styles and
// numbering loaded, and the two parts are encoded and compared as well,
// since a loaded part nothing changed is saved as it was read. The owner's
// Word files are round-tripped in owner_files_test.dart, which reads them
// from disk and runs on the VM only.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  final List<DocxFixture> d3 = <DocxFixture>[
    for (final DocxFixture f in all)
      if (f.name.startsWith('d3_')) f,
  ];

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
    expect(all, hasLength(26));
    expect(<String>{for (final DocxFixture f in all) f.name}, hasLength(26));
  });

  test('the T1 fixtures are the four the plan names, last', () {
    expect(
      <String>[for (final DocxFixture f in all.skip(22)) f.name],
      <String>[
        't1_values',
        't1_merge_fields',
        't1_merge_fields_template',
        't1_template',
      ],
    );
  });

  test('the D3 fixtures are the five the plan names', () {
    expect(
      <String>[for (final DocxFixture f in d3) f.name],
      <String>[
        'd3_basic',
        'd3_header_row',
        'd3_merges',
        'd3_formatting',
        'd3_nested',
      ],
    );
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
          if (other.name == 'd2_lists' || other.name == 'd3_nested') continue;
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

  group('D3', () {
    test('every D3 fixture builds the same bytes and no warnings', () {
      for (final DocxFixture f in d3) {
        final DocxResult built = f.build();
        expect(built.bytes, f.build().bytes, reason: f.name);
        expect(built.warnings, isEmpty, reason: f.name);
      }
    });

    test('every D3 fixture reads its text and round-trips', () {
      for (final DocxFixture f in d3) {
        final Uint8List input = f.build().bytes;
        final DocxDocument doc = DocxDocument.open(input);
        expect(docxFullText(doc), f.expectedText, reason: f.name);
        expect(
          doc.body.blocks.whereType<DocxTable>(),
          isNotEmpty,
          reason: f.name,
        );
        expect(readTypedProperties(doc), greaterThan(0), reason: f.name);
        expect(doc.styles.styles, isNotEmpty, reason: f.name);
        final DocxResult saved = doc.save();
        expect(saved.warnings, isEmpty, reason: f.name);
        final List<String> differences = <String>[
          ...comparePackages(input, saved.bytes),
          ...encodedPartDifferences(input),
          ...encodedMainDifferences(input),
        ];
        expect(
          differences,
          isEmpty,
          reason: '${f.name}\n${differences.join('\n')}',
        );
      }
    });

    test('a body that ends in a table saves and reads back', () {
      final DocxDocument doc = DocxDocument();
      doc.body.removeBlockAt(0);
      doc.body.addTable(columns: 2).addRow(<String?>['a', 'b']);
      final Uint8List bytes = doc.save().bytes;
      final DocxDocument again = DocxDocument.open(bytes);
      expect(again.body.blocks.single, isA<DocxTable>());
      expect(docxFullText(again), 'a\tb');
      expect(comparePackages(bytes, again.save().bytes), isEmpty);
    });

    test('d3_header_row repeats its header over 120 rows', () {
      final DocxFixture f = d3.singleWhere(
        (DocxFixture f) => f.name == 'd3_header_row',
      );
      final DocxTable table = DocxDocument.open(
        f.build().bytes,
      ).body.blocks.whereType<DocxTable>().single;
      expect(table.rows, hasLength(121));
      expect(table.rows.first.isHeader, isTrue);
      expect(table.rows[3].properties.height!.rule, DocxRowHeightRule.exact);
      expect(table.rows[5].properties.cantSplit, isTrue);
    });

    test('d3_merges reads each merge shape', () {
      final DocxFixture f = d3.singleWhere(
        (DocxFixture f) => f.name == 'd3_merges',
      );
      final DocxTable table = DocxDocument.open(
        f.build().bytes,
      ).body.blocks.whereType<DocxTable>().single;
      expect(table.rows[0].cells, hasLength(3));
      expect(table.rows[0].cells.first.properties.gridSpan, 2);
      expect(
        table.rows[1].cells.first.properties.verticalMerge,
        DocxVerticalMerge.restart,
      );
      expect(
        table.rows[2].cells.first.properties.verticalMerge,
        DocxVerticalMerge.continuation,
      );
    });

    test('d3_nested holds a table in a cell, a list and a last table', () {
      final DocxFixture f = d3.singleWhere(
        (DocxFixture f) => f.name == 'd3_nested',
      );
      final DocxDocument doc = DocxDocument.open(f.build().bytes);
      final DocxTable outer = doc.body.blocks.whereType<DocxTable>().single;
      expect(
        outer.rows[1].cells[0].blocks.whereType<DocxTable>(),
        hasLength(1),
      );
      expect(
        outer.rows[2].cells[0].blocks.whereType<DocxTable>(),
        hasLength(1),
      );
      expect(
        outer.rows[1].cells[1].blocks.whereType<DocxParagraph>().where(
          (DocxParagraph p) => p.properties.numbering != null,
        ),
        hasLength(2),
      );
    });
  });

  group('D4', () {
    final List<DocxFixture> d4 = <DocxFixture>[
      for (final DocxFixture f in all)
        if (f.name.startsWith('d4_')) f,
    ];
    DocxDocument open(String name) => DocxDocument.open(
      d4.singleWhere((DocxFixture f) => f.name == name).build().bytes,
    );

    test('the D4 fixtures are the three the plan names', () {
      expect(
        <String>[for (final DocxFixture f in d4) f.name],
        <String>['d4_sections', 'd4_headers', 'd4_fields'],
      );
    });

    test('every D4 fixture builds the same bytes and no warnings', () {
      for (final DocxFixture f in d4) {
        final DocxResult built = f.build();
        expect(built.bytes, f.build().bytes, reason: f.name);
        expect(built.warnings, isEmpty, reason: f.name);
      }
    });

    test('every D4 fixture round-trips with everything read and encoded', () {
      for (final DocxFixture f in d4) {
        final Uint8List input = f.build().bytes;
        final DocxDocument doc = DocxDocument.open(input);
        expect(docxFullText(doc), f.expectedText, reason: f.name);
        expect(readTypedProperties(doc), greaterThan(0), reason: f.name);
        final DocxResult saved = doc.save();
        expect(saved.warnings, isEmpty, reason: f.name);
        final List<String> differences = <String>[
          ...comparePackages(input, saved.bytes),
          ...encodedPartDifferences(input),
          ...encodedMainDifferences(input),
          ...encodedStoryDifferences(input),
        ];
        expect(
          differences,
          isEmpty,
          reason: '${f.name}\n${differences.join('\n')}',
        );
      }
    });

    test('no fixture ends in a table or a section break', () {
      for (final DocxFixture f in all) {
        final DocxBlock last = DocxDocument.open(
          f.build().bytes,
        ).body.blocks.last;
        expect(last, isA<DocxParagraph>(), reason: f.name);
        expect((last as DocxParagraph).section, isNull, reason: f.name);
      }
    });

    test('each story of a fixture reads the text it lists', () {
      for (final DocxFixture f in d4) {
        final String? stories = f.headerFooterText;
        if (stories != null) {
          expect(docxStoriesText(DocxDocument.open(f.build().bytes)), stories);
        }
      }
      expect(
        d4.singleWhere((DocxFixture f) => f.name == 'd4_sections'),
        isA<DocxFixture>().having(
          (DocxFixture f) => f.headerFooterText,
          'headerFooterText',
          isNull,
        ),
      );
    });

    test('LibreOffice writes the text of every D4 fixture as it is', () {
      // Pinned from a run: its text export gives the cached result of the
      // body's PAGE and of the custom field, as the model reads them.
      for (final DocxFixture f in d4) {
        expect(f.libreOfficeText, f.expectedText, reason: f.name);
        expect(f.libreOfficeTextSkip, isNull, reason: f.name);
      }
    });

    test('d4_sections reads back the page of each section', () {
      final List<DocxSection> s = open('d4_sections').sections;
      expect(s, hasLength(4));
      expect(s[0].pageSize, DocxPageSize.a4());
      expect(s[0].margins!.leftPt, 108);
      expect(s[0].margins!.gutterPt, 18);
      expect(s[0].pageNumbering, DocxPageNumbering(start: 5));
      expect(
        s[0].lineNumbering,
        DocxLineNumbering(
          countBy: 1,
          restart: DocxLineNumberRestart.newSection,
        ),
      );
      expect(s[0].verticalAlignment, DocxSectionVerticalAlignment.center);

      expect(s[1].pageSize, DocxPageSize.a4(landscape: true));
      expect(s[1].start, DocxSectionStart.nextPage);
      expect(s[1].columns, DocxColumns(count: 2, separator: true));
      expect(s[1].pageNumbering, isNull);
      expect(s[1].lineNumbering, isNull);
      expect(s[1].verticalAlignment, isNull);

      expect(s[2].start, DocxSectionStart.continuous);
      expect(s[2].pageSize, DocxPageSize.a4(landscape: true));
      expect(s[2].columns, DocxColumns());

      expect(s[3].start, DocxSectionStart.nextPage);
      expect(s[3].pageSize, DocxPageSize.letter());
    });

    test('d4_sections shares the Letter text width less 10 twips', () {
      final DocxDocument doc = open('d4_sections');
      expect(doc.sections.last.textWidthPt, 468);
      final DocxTable table = doc.body.blocks.whereType<DocxTable>().single;
      // 9360 twips less 10, shared by two columns.
      expect(table.gridColumnsPt, <double>[233.75, 233.75]);
    });

    test('d4_headers shows each story on the pages it is for', () {
      final DocxDocument doc = open('d4_headers');
      final List<DocxSection> s = doc.sections;
      expect(s, hasLength(3));
      expect(doc.evenAndOddHeaders, isTrue);
      expect(s[0].titlePage, isTrue);
      expect(s[1].titlePage, isFalse);
      expect(s[0].header.isInherited, isFalse);
      expect(s[1].header.isInherited, isTrue);
      expect(s[1].evenFooter.isInherited, isTrue);
      expect(s[2].header.isInherited, isFalse);
      expect(s[2].footer.isInherited, isFalse);
      expect(s[2].evenHeader.isInherited, isTrue);
      // The second and third pages of section one come from page breaks.
      expect(
        <bool?>[
          for (final DocxBlock b in doc.body.blocks.take(3))
            (b as DocxParagraph).properties.pageBreakBefore,
        ],
        <bool?>[null, true, true],
      );
    });

    test('d4_fields has its fields where the plan puts them', () {
      final DocxDocument doc = open('d4_fields');
      List<String> instructions(List<DocxBlock> blocks) => <String>[
        for (final DocxBlock b in blocks)
          for (final DocxInline i in (b as DocxParagraph).inlines)
            if (i is DocxField) i.instruction,
      ];
      expect(instructions(doc.sections.last.footer.blocks), <String>[
        ' PAGE ',
        ' NUMPAGES ',
        ' SECTIONPAGES ',
        r' DATE \@ "dd.MM.yyyy" ',
        r' TIME \@ "HH:mm" ',
      ]);
      expect(instructions(doc.body.blocks), <String>[
        ' PAGE ',
        ' QUOTE "Custom text" ',
      ]);
      final DocxParagraph printed =
          doc.sections.last.footer.blocks.last as DocxParagraph;
      expect(printed.text, 'Printed on  at ');
    });
  });

  group('D5', () {
    final List<DocxFixture> d5 = <DocxFixture>[
      for (final DocxFixture f in all)
        if (f.name.startsWith('d5_')) f,
    ];
    DocxDocument open(String name) => DocxDocument.open(
      d5.singleWhere((DocxFixture f) => f.name == name).build().bytes,
    );
    List<DocxPicture> pictures(List<DocxBlock> blocks) => <DocxPicture>[
      for (final DocxBlock b in blocks)
        ...switch (b) {
          DocxParagraph() => <DocxPicture>[
            for (final DocxInline i in b.inlines)
              if (i is DocxRun) ...i.content.whereType<DocxPicture>(),
          ],
          DocxTable() => <DocxPicture>[
            for (final DocxTableRow row in b.rows)
              for (final DocxTableCell cell in row.cells)
                ...pictures(cell.blocks),
          ],
          DocxOpaqueBlock() => const <DocxPicture>[],
        },
    ];

    test('the D5 fixtures are the three the plan names', () {
      expect(
        <String>[for (final DocxFixture f in d5) f.name],
        <String>['d5_pictures', 'd5_links', 'd5_properties'],
      );
    });

    test('every D5 fixture builds the same bytes and no warnings, and '
        'round-trips with everything read and encoded', () {
      for (final DocxFixture f in d5) {
        final DocxResult built = f.build();
        expect(built.bytes, f.build().bytes, reason: f.name);
        expect(built.warnings, isEmpty, reason: f.name);
        final Uint8List input = built.bytes;
        final DocxDocument doc = DocxDocument.open(input);
        expect(docxFullText(doc), f.expectedText, reason: f.name);
        expect(docxStoriesText(doc), f.headerFooterText ?? '', reason: f.name);
        expect(readTypedProperties(doc), greaterThan(0), reason: f.name);
        final DocxResult saved = doc.save();
        expect(saved.warnings, isEmpty, reason: f.name);
        final List<String> differences = <String>[
          ...comparePackages(input, saved.bytes),
          ...encodedPartDifferences(input),
          ...encodedMainDifferences(input),
          ...encodedStoryDifferences(input),
          ...encodedPropertiesDifferences(input),
        ];
        expect(
          differences,
          isEmpty,
          reason: '${f.name}\n${differences.join('\n')}',
        );
        expect(f.libreOfficeText, f.expectedText, reason: f.name);
      }
    });

    test('d5_pictures reads back its pictures, sizes and one PNG part', () {
      final DocxDocument doc = open('d5_pictures');
      final List<DocxPicture> body = pictures(doc.body.blocks);
      expect(
        body.map(
          (DocxPicture p) => (p.name, p.widthPt, p.heightPt, p.description),
        ),
        <Object>[
          ('PNG', 3.0, 1.5, 'A PNG of 4 by 2 pixels'),
          ('JPEG', 144.0, 240.0, null),
        ],
      );
      expect(body[0].image!.format, OfficeImageFormat.png);
      expect(body[1].image!.format, OfficeImageFormat.jpeg);
      final DocxPicture logo = pictures(doc.sections.last.header.blocks).single;
      expect((logo.name, logo.widthPt, logo.heightPt), ('Logo', 3.0, 1.5));
      expect(logo.image, body[0].image);
      final Archive package = ZipDecoder().decodeBytes(
        d5
            .singleWhere((DocxFixture f) => f.name == 'd5_pictures')
            .build()
            .bytes,
      );
      expect(
        <String>[
          for (final ArchiveFile f in package.files)
            if (f.name.startsWith('word/media/')) f.name,
        ]..sort(),
        <String>['word/media/image1.png', 'word/media/image2.jpeg'],
      );
    });

    test('d5_links reads back its links and the bookmark they name', () {
      final DocxDocument doc = open('d5_links');
      final List<DocxBlock> blocks = doc.body.blocks;
      final DocxParagraph heading = blocks[0] as DocxParagraph;
      final DocxBookmarkStart start =
          heading.inlines.first as DocxBookmarkStart;
      final DocxBookmarkEnd end = heading.inlines.last as DocxBookmarkEnd;
      expect(start.name, 'Overview');
      expect(start.id, isNotNull);
      expect(end.id, start.id);
      expect(heading.style, 'Heading1');
      DocxHyperlink link(DocxParagraph p) =>
          p.inlines.whereType<DocxHyperlink>().single;
      final DocxHyperlink external = link(blocks[1] as DocxParagraph);
      expect(
        (external.url, external.anchor, external.tooltip, external.text),
        (
          'https://example.com/jet-office',
          null,
          'The project page',
          'the project page',
        ),
      );
      final DocxHyperlink internal = link(blocks[2] as DocxParagraph);
      expect((internal.url, internal.anchor), (null, 'Overview'));
      final DocxHyperlink footer = link(
        doc.sections.last.footer.blocks.single as DocxParagraph,
      );
      expect(footer.url, 'https://example.com/');
    });

    test('d5_properties reads back every property it set', () {
      expect(open('d5_properties').properties, d5Properties);
    });
  });
}
