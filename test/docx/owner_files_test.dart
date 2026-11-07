/// Reads the owner's Word for Mac files (`test/fixtures/owner/docx/`):
/// every one round-trips through `DocxDocument` with nothing lost, and every
/// one the owner confirmed reads the text the owner confirmed. A draft
/// (`"confirmedBy": null`) prints `pending` instead. The manifest format is
/// in `test/support/owner_docx.dart` and `test/fixtures/owner/README.md`.
/// VM only: it reads files from disk.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/docx_serialize.dart';
import '../../tool/src/part_compare.dart';
import '../../tool/src/text_compare.dart';
import '../support/owner_docx.dart';

const String _dir = 'test/fixtures/owner/docx';

void main() {
  final List<String> names = <String>[
    for (final FileSystemEntity e in Directory(_dir).listSync())
      if (e is File) e.uri.pathSegments.last,
  ];
  final List<OwnerDocx> manifest = parseOwnerDocxManifest(
    File('$_dir/manifest.json').readAsStringSync(),
  );

  test('every .docx and .expected.txt is listed and has its partner', () {
    expect(ownerDocxDirectoryProblems(names, manifest), isEmpty);
  });

  test('the manifest lists the four Word for Mac files', () {
    expect(<String>[
      for (final OwnerDocx e in manifest) e.file,
    ], containsAll(<String>['blank.docx', 'features.docx', 'long.docx']));
  });

  test('blank.docx is one A4 section with the margins of the file', () {
    final DocxDocument doc = DocxDocument.open(
      File('$_dir/blank.docx').readAsBytesSync(),
    );
    final DocxSection section = doc.sections.single;
    expect(section.pageSize, DocxPageSize.a4());
    expect(
      section.margins,
      DocxPageMargins(
        top: 70.85,
        right: 70.85,
        bottom: 70.85,
        left: 70.85,
        header: 35.4,
        footer: 35.4,
        gutter: 0,
      ),
    );
    expect(section.columns, DocxColumns(spacingPt: 35.4));
  });

  test('features.docx reads its header, and saves it as read', () {
    final Uint8List input = File('$_dir/features.docx').readAsBytesSync();
    final DocxDocument doc = DocxDocument.open(input);
    final DocxSection section = doc.sections.last;
    expect(
      (section.header.blocks.first as DocxParagraph).text,
      'Jet Office test header',
    );
    for (final DocxHeaderFooter story in <DocxHeaderFooter>[
      section.firstHeader,
      section.evenHeader,
      section.footer,
      section.firstFooter,
      section.evenFooter,
    ]) {
      expect(story.blocks, isNotEmpty);
    }
    expect(comparePackages(input, doc.save().bytes), isEmpty);
    expect(doc.save().warnings, isEmpty);
  });

  test('long.docx keeps its TOC as runs, its PAGEREFs in hyperlinks', () {
    final DocxDocument doc = DocxDocument.open(
      File('$_dir/long.docx').readAsBytesSync(),
    );
    final List<DocxInline> inlines = <DocxInline>[
      for (final DocxBlock block in doc.body.blocks)
        if (block is DocxParagraph) ...block.inlines,
    ];
    expect(inlines.whereType<DocxField>(), isEmpty);
    expect(
      <DocxFieldMarkType>[
        for (final DocxRun run in inlines.whereType<DocxRun>())
          for (final DocxRunContent c in run.content)
            if (c is DocxFieldMark) c.type,
      ],
      <DocxFieldMarkType>[
        DocxFieldMarkType.begin,
        DocxFieldMarkType.separate,
        DocxFieldMarkType.end,
      ],
    );
    expect(
      <String>[
        for (final DocxRun run in inlines.whereType<DocxRun>())
          for (final DocxRunContent c in run.content)
            if (c is DocxFieldInstruction) c.text,
      ],
      <String>[' TOC \\o "1-1" \\h \\* MERGEFORMAT '],
    );
    expect(
      inlines.whereType<DocxOpaqueInline>().where(
        (DocxOpaqueInline i) => i.localName == 'hyperlink',
      ),
      hasLength(13),
    );
  });

  test('every owner file round-trips', () {
    for (final OwnerDocx entry in manifest) {
      final Uint8List input = File('$_dir/${entry.file}').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.body.blocks, isNotEmpty, reason: entry.file);
      final DocxResult saved = doc.save();
      expect(saved.warnings, isEmpty, reason: entry.file);
      final List<String> differences = comparePackages(input, saved.bytes);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  group('tables', () {
    /// Every table of [doc]'s body.
    Iterable<DocxTable> tables(DocxDocument doc) =>
        doc.body.blocks.whereType<DocxTable>();

    for (final (String file, int count) in <(String, int)>[
      ('builtins.docx', 1),
      ('features.docx', 1),
      ('long.docx', 2),
    ]) {
      test('a table saves semantically equal: $file', () {
        final Uint8List input = File('$_dir/$file').readAsBytesSync();
        final DocxDocument doc = DocxDocument.open(input);
        expect(tables(doc), hasLength(count));
        expect(encodedMainDifferences(input), isEmpty);
        // An edit in a cell runs the writer on the whole part: only that
        // text differs.
        final DocxParagraph p =
            tables(doc).first.rows.first.cells.first.blocks.first
                as DocxParagraph;
        final DocxRun run = p.inlines.whereType<DocxRun>().first;
        final String text = run.text;
        run.text = '$text!';
        final Uint8List saved = doc.save().bytes;
        final DocxDocument again = DocxDocument.open(saved);
        final DocxParagraph edited =
            tables(again).first.rows.first.cells.first.blocks.first
                as DocxParagraph;
        expect(edited.text, startsWith('$text!'));
        expect(comparePackages(input, saved), hasLength(1));
      });
    }

    test('a table reads rows, cells and paragraphs: builtins.docx', () {
      final DocxTable table = tables(
        DocxDocument.open(File('$_dir/builtins.docx').readAsBytesSync()),
      ).single;
      expect(table.gridColumnsPt, <double>[226.55, 226.55]);
      expect(
        <String>[
          for (final DocxTableRow row in table.rows)
            for (final DocxTableCell cell in row.cells) cell.text,
        ],
        <String>['A', 'B', 'C', 'D'],
      );
    });

    test('owner tables read their cells', () {
      for (final (String file, List<String>? expected)
          in <(String, List<String>?)>[
            ('builtins.docx', <String>['A', 'B', 'C', 'D']),
            ('features.docx', null),
            ('long.docx', null),
          ]) {
        final DocxDocument doc = DocxDocument.open(
          File('$_dir/$file').readAsBytesSync(),
        );
        final List<DocxTableCell> cells = <DocxTableCell>[
          for (final DocxTable table in tables(doc))
            for (final DocxTableRow row in table.rows) ...row.cells,
        ];
        expect(cells, isNotEmpty, reason: file);
        for (final DocxTableCell cell in cells) {
          expect(cell.blocks, isNotEmpty, reason: file);
          expect(
            cell.text,
            <String>[
              for (final DocxBlock b in cell.blocks)
                if (b is DocxParagraph) b.text,
            ].join('\n'),
            reason: file,
          );
        }
        if (expected != null) {
          expect(<String>[
            for (final DocxTableCell c in cells) c.text,
          ], expected);
        }
        expect(doc.warnings, isEmpty, reason: file);
      }
    });

    test('a table style resolves in the document: builtins.docx', () {
      final DocxDocument doc = DocxDocument.open(
        File('$_dir/builtins.docx').readAsBytesSync(),
      );
      final DocxTable table = tables(doc).single;
      expect(table.properties.style, 'TabloKlavuzu');
      final int styles = doc.styles.styles.length;
      table.properties.style = null;
      table.properties.style = 'TableGrid';
      expect(table.properties.style, 'TabloKlavuzu');
      expect(doc.styles.styles, hasLength(styles));
    });
  });

  test('every owner file round-trips with its styles loaded', () {
    for (final OwnerDocx entry in manifest) {
      final Uint8List input = File('$_dir/${entry.file}').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.styles.styles, isNotEmpty, reason: entry.file);
      expect(doc.styles.byName('Normal'), isNotNull, reason: entry.file);
      final List<String> differences = comparePackages(input, doc.save().bytes);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  test('every owner file round-trips with its numbering loaded', () {
    for (final OwnerDocx entry in manifest) {
      final Uint8List input = File('$_dir/${entry.file}').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      final DocxNumbering numbering = doc.numbering;
      for (final DocxNumberingInstance n in numbering.instances) {
        expect(n.abstractNumbering, isNotNull, reason: '${entry.file} $n');
      }
      final List<String> differences = comparePackages(input, doc.save().bytes);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  test('every owner file round-trips with styles and numbering loaded', () {
    // A loaded part nothing changed is saved as it was read, so the two
    // parts are also encoded and compared: that is what proves the model
    // can write what Word wrote.
    for (final OwnerDocx entry in manifest) {
      final Uint8List input = File('$_dir/${entry.file}').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.styles.styles, isNotEmpty, reason: entry.file);
      doc.numbering.instances.length;
      expect(doc.body.blocks, isNotEmpty, reason: entry.file);
      final DocxResult saved = doc.save();
      expect(saved.warnings, isEmpty, reason: entry.file);
      final List<String> differences = <String>[
        ...comparePackages(input, saved.bytes),
        ...encodedPartDifferences(input),
        ...encodedMainDifferences(input),
      ];
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
      expect(
        encodedParts(input).keys,
        contains('word/styles.xml'),
        reason: entry.file,
      );
    }
  });

  test('reading every typed property of the owner files throws nothing', () {
    for (final OwnerDocx entry in manifest) {
      final DocxDocument doc = DocxDocument.open(
        File('$_dir/${entry.file}').readAsBytesSync(),
      );
      expect(readTypedProperties(doc), greaterThan(0), reason: entry.file);
    }
    final DocxDocument doc = DocxDocument.open(
      File('$_dir/long.docx').readAsBytesSync(),
    );
    final List<DocxParagraph> paragraphs = <DocxParagraph>[
      for (final DocxBlock b in doc.body.blocks)
        if (b is DocxParagraph) b,
    ];
    final DocxParagraph first = paragraphs.first;
    expect(first.properties.style, 'KonuBal');
    expect(first.properties.alignment, DocxAlignment.center);
    final DocxRun firstRun = first.inlines.whereType<DocxRun>().first;
    expect(firstRun.properties.color, DocxColor.rgb('17365D'));
    expect(firstRun.properties.sizePt, 36);

    // Word wrote this heading's 13.5 pt (w:sz 27) in the paragraph mark's
    // properties, which the model keeps but does not type; the run itself
    // names no size, and its style (heading 3) says 14.
    final DocxParagraph detail = paragraphs.singleWhere(
      (DocxParagraph p) => p.text == '3.1.1. Ayrıntı düzeyi',
    );
    expect(detail.properties.style, 'Balk3');
    expect(
      detail.inlines.whereType<DocxRun>().single.properties.sizePt,
      isNull,
    );
    expect(doc.styles.byId('Balk3')!.runProperties.sizePt, 14);

    final DocxParagraph toc = paragraphs.firstWhere(
      (DocxParagraph p) => doc.styles.byId(p.style ?? '')?.name == 'toc 1',
    );
    expect(toc.properties.tabs, <DocxTabStop>[
      DocxTabStop(
        453.1,
        alignment: DocxTabAlignment.right,
        leader: DocxTabLeader.dot,
      ),
    ]);
    expect(doc.styles.defaults.runProperties.language, 'tr-TR');
  });

  test('every owner file reads its confirmed text', () {
    for (final OwnerDocx entry in manifest) {
      final String stem = entry.file.substring(0, entry.file.length - 5);
      final String expected = readExpectedText(
        File('$_dir/$stem.expected.txt').readAsStringSync(),
      );
      final DocxDocument doc = DocxDocument.open(
        File('$_dir/${entry.file}').readAsBytesSync(),
      );
      final String actual = docxBodyText(doc);
      if (!entry.confirmed) {
        // ignore: avoid_print
        print('${entry.file}: pending (drafted, not confirmed by the owner)');
        continue;
      }
      final List<String> differences = textDifferences(expected, actual);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  test('a draft still matches what the model reads', () {
    // A draft is the model's own answer, which the owner then checks
    // against Word; one that no longer matches the model would make that
    // check meaningless. A confirmed text is the owner's and is checked
    // above instead.
    for (final OwnerDocx entry in manifest) {
      if (entry.confirmed) continue;
      final String stem = entry.file.substring(0, entry.file.length - 5);
      final String expected = readExpectedText(
        File('$_dir/$stem.expected.txt').readAsStringSync(),
      );
      final DocxDocument doc = DocxDocument.open(
        File('$_dir/${entry.file}').readAsBytesSync(),
      );
      expect(
        textDifferences(expected, docxBodyText(doc)),
        isEmpty,
        reason: entry.file,
      );
    }
  });
}
