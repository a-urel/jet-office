// Tests DocxDocument: opening a DOCX file, loading the body on first access,
// editing its blocks, and saving with nothing lost. A part never loaded is
// copied from its bytes; a loaded body is written from the model and means
// what the input meant. Every failure caused by the file is a
// DocxReadException. The packages are built in memory, so these tests run
// on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../support/read_xlsx.dart';
import 'support/docx_builder.dart';
import 'support/styles_documents.dart' show docxWithStyles;
import 'support/word_document.dart';

/// The document's paragraph texts and opaque block names, in order.
List<String> _outline(DocxDocument doc) => <String>[
  for (final DocxBlock b in doc.body.blocks)
    switch (b) {
      DocxParagraph() => 'p:${b.text}',
      DocxTable() => 'table:${b.rows.length}',
      DocxOpaqueBlock() => 'opaque:${b.localName}',
    },
];

/// Expects [body] to throw a [DocxReadException] of [reason] and returns it.
DocxReadException _refused(void Function() body, DocxReadFailure reason) {
  try {
    body();
  } on DocxReadException catch (e) {
    expect(e.reason, reason, reason: e.toString());
    return e;
  }
  fail('No DocxReadException was thrown.');
}

/// Collects the chunks a save streams.
final class _Collect implements Sink<List<int>> {
  final BytesBuilder bytes = BytesBuilder();
  bool closed = false;

  @override
  void add(List<int> data) => bytes.add(data);

  @override
  void close() => closed = true;
}

void main() {
  group('open and save', () {
    test('open then save without access keeps document.xml bytes', () {
      final Uint8List input = wordDocx();
      final DocxDocument doc = DocxDocument.open(input);
      final Uint8List output = doc.save().bytes;
      expect(isBodyLoaded(doc), isFalse);
      final Map<String, Uint8List> before = readXlsxBytes(input);
      final Map<String, Uint8List> after = readXlsxBytes(output);
      expect(after['word/document.xml'], before['word/document.xml']);
      expect(after['word/settings.xml'], before['word/settings.xml']);
      expect(after['word/media/image1.png'], before['word/media/image1.png']);
      expect(comparePackages(input, output), isEmpty);
    });

    test('open, read body, save is semantically equal', () {
      final Uint8List input = wordDocx();
      final DocxDocument doc = DocxDocument.open(input);
      expect(_outline(doc), <String>[
        'p:Fiyat listesiÜrün ',
        'opaque:sdt',
        'p:Kalem: Defter\t12\nadet',
        'p:',
        'p:Son',
      ]);
      final Uint8List output = doc.save().bytes;
      expect(isBodyLoaded(doc), isTrue);
      expect(comparePackages(input, output), isEmpty);
      final Map<String, Uint8List> before = readXlsxBytes(input);
      final Map<String, Uint8List> after = readXlsxBytes(output);
      expect(
        compareXmlParts(
          '/word/document.xml',
          before['word/document.xml']!,
          after['word/document.xml']!,
        ),
        isEmpty,
      );
      expect(after['word/document.xml'], before['word/document.xml']);
      expect(after['word/settings.xml'], before['word/settings.xml']);
      expect(doc.warnings, isEmpty);
    });

    group('a main part with no edit keeps its bytes', () {
      const String outOfOrder =
          '<?xml version="1.0"?>\n<w:document xmlns:w="${Ns.w}">\n'
          '  <!-- a comment --><w:body><w:p><w:pPr><w:jc w:val="left"/>'
          '<w:keepNext/></w:pPr><w:r><w:rPr><w:sz w:val="20"/><w:b/></w:rPr>'
          '<w:t>a</w:t></w:r></w:p></w:body></w:document>';

      Uint8List mainOf(Uint8List docx) =>
          readXlsxBytes(docx)['word/document.xml']!;

      test('out-of-order properties, opened, read and saved', () {
        final Uint8List input = buildDocx(document: outOfOrder);
        final DocxDocument doc = DocxDocument.open(input);
        expect(doc.body.blocks, hasLength(1));
        expect(mainOf(doc.save().bytes), mainOf(input));
      });

      test('a set to the value it reads is no edit', () {
        final Uint8List input = buildDocx(document: outOfOrder);
        final DocxDocument doc = DocxDocument.open(input);
        final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
        p.properties.alignment = p.properties.alignment;
        expect(mainOf(doc.save().bytes), mainOf(input));
      });

      test('an edit that failed leaves no edit', () {
        final Uint8List input = buildDocx(document: outOfOrder);
        final DocxDocument doc = DocxDocument.open(input);
        final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
        editsOf(doc).afterRecord = () => throw StateError('fail');
        expect(() => p.addRun('b'), throwsStateError);
        editsOf(doc).afterRecord = null;
        expect(changeLogOf(doc).hasChanges, isFalse);
        expect(mainOf(doc.save().bytes), mainOf(input));
      });

      test('a real edit writes the part from the model', () {
        final DocxDocument doc = DocxDocument.open(
          buildDocx(document: outOfOrder),
        );
        (doc.body.blocks.single as DocxParagraph).addRun('b');
        final String xml = utf8.decode(mainOf(doc.save().bytes));
        expect(xml, isNot(contains('a comment')));
        expect(xml, contains('<w:keepNext/><w:jc w:val="left"/>'));
        expect(xml, contains('<w:b/><w:sz w:val="20"/>'));
        expect(xml, contains('<w:t>b</w:t>'));
      });

      test('an edit undone still counts as an edit, as the log says', () {
        final DocxDocument doc = DocxDocument.open(
          buildDocx(document: outOfOrder),
        );
        final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
        p.addRun('b');
        p.removeInlineAt(1);
        expect(changeLogOf(doc).hasChanges, isTrue);
        expect(
          utf8.decode(mainOf(doc.save().bytes)),
          isNot(contains('a comment')),
        );
      });

      test('an edit of the styles counts too: the log is the document\'s', () {
        final DocxDocument doc = DocxDocument.open(
          docxWithStyles(document: outOfOrder),
        );
        expect(doc.body.blocks, hasLength(1));
        doc.styles.defaults.runProperties.bold = true;
        expect(
          utf8.decode(mainOf(doc.save().bytes)),
          isNot(contains('a comment')),
        );
      });
    });

    test('open, set one run text, save differs only in that w:t', () {
      final Uint8List input = wordDocx();
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = doc.body.blocks[2] as DocxParagraph;
      final DocxRun run = p.inlines.first as DocxRun;
      expect(run.text, 'Kalem: ');
      run.text = 'Kalem adı: ';
      final Uint8List output = doc.save().bytes;
      final List<String> differences = comparePackages(input, output);
      expect(differences, hasLength(1), reason: differences.join('\n'));
      expect(differences.single, startsWith('word/document.xml: '));
      expect(differences.single, contains('/r/t: text '));
      expect(differences.single, contains('Kalem: '));
      expect(differences.single, contains('Kalem adı: '));
      final String xml = utf8.decode(
        readXlsxBytes(output)['word/document.xml']!,
      );
      expect(xml, contains('<w:t xml:space="preserve">Kalem adı: </w:t>'));
    });

    group('a Word-like document with tracked changes, fields and a table', () {
      test('declares w15 and adds its blocks', () {
        expect(richWordDocumentXml, contains('mc:Ignorable="w14 w15 wp14"'));
        expect(richWordDocumentXml, contains('xmlns:w15='));
        expect(richWordDocumentXml, contains('<w:tbl>'));
        expect(
          richWordDocumentXml.indexOf('<w:tbl>'),
          lessThan(richWordDocumentXml.indexOf('<w:sectPr')),
        );
      });

      test('opens with its paragraphs and its table typed', () {
        final DocxDocument doc = DocxDocument.open(richWordDocx());
        expect(_outline(doc), <String>[
          'p:Fiyat listesiÜrün ',
          'opaque:sdt',
          'p:Kalem: Defter\t12\nadet',
          'p:',
          'p:Son',
          'p:Değişiklikler',
          'p:Eski tutar, bkz. site',
          'p:Sayfa 1 / 2',
          'p:Gizli',
          'table:1',
          'p:',
        ]);
      });

      test('open, read body, save is semantically equal', () {
        final Uint8List input = richWordDocx();
        final DocxDocument doc = DocxDocument.open(input);
        expect(doc.body.blocks, hasLength(11));
        final Uint8List output = doc.save().bytes;
        expect(comparePackages(input, output), isEmpty);
        expect(doc.warnings, isEmpty);
      });

      test('open, edit one paragraph, save differs only in it', () {
        final Uint8List input = richWordDocx();
        final DocxDocument doc = DocxDocument.open(input);
        final DocxParagraph p = doc.body.blocks[5] as DocxParagraph;
        (p.inlines[1] as DocxRun).text = 'Yenilikler';
        final List<String> differences = comparePackages(
          input,
          doc.save().bytes,
        );
        expect(differences, hasLength(1), reason: differences.join('\n'));
        expect(differences.single, startsWith('word/document.xml: '));
        expect(differences.single, contains('Değişiklikler'));
        expect(differences.single, contains('Yenilikler'));
      });

      test('replacing a paragraph block changes only that block', () {
        final Uint8List input = richWordDocx();
        final DocxDocument doc = DocxDocument.open(input);
        doc.body.replaceBlockAt(7, DocxParagraph.text('Sayfa yok'));
        final Uint8List output = doc.save().bytes;
        final List<String> differences = comparePackages(input, output);
        expect(differences, isNotEmpty);
        expect(
          differences.every((String d) => d.startsWith('word/document.xml: ')),
          isTrue,
          reason: differences.join('\n'),
        );
        final DocxDocument again = DocxDocument.open(output);
        final List<String> outline = _outline(again);
        expect(outline[7], 'p:Sayfa yok');
        expect(
          <String>[...outline]..removeAt(7),
          <String>[..._outline(DocxDocument.open(input))]..removeAt(7),
        );
      });
    });

    test('saveTo streams the same bytes as save', () {
      final DocxDocument doc = DocxDocument.open(wordDocx());
      (doc.body.blocks.first as DocxParagraph).addRun(' 2026');
      final Uint8List saved = doc.save().bytes;
      final _Collect sink = _Collect();
      doc.saveTo(sink);
      expect(sink.closed, isTrue);
      expect(sink.bytes.takeBytes(), saved);
    });

    test('a save returns the warnings of that save, and warnings keeps '
        'them', () {
      final DocxDocument doc = DocxDocument.open(wordDocx());
      expect(doc.warnings, isEmpty);
      final DocxRun run =
          (doc.body.blocks.first as DocxParagraph).inlines.first as DocxRun;
      run.text = 'a\u0001b\u0002';
      final DocxResult first = doc.save();
      expect(first.warnings, hasLength(1));
      final DocxWarning w = first.warnings.single;
      expect(w.code, DocxWarningCode.invalidCharactersRemoved);
      expect(w.part, '/word/document.xml');
      expect(w.count, 2);
      expect(w.locations, <String>['body/p[0]/r[0]']);
      expect(doc.warnings, first.warnings);
      expect(() => first.warnings.add(w), throwsUnsupportedError);

      // Saving again reports the run once more, not twice.
      expect(doc.save().warnings.single.count, 2);
      run.text = 'clean';
      final DocxResult clean = doc.save();
      expect(clean.warnings, isEmpty);
      expect(doc.warnings, isEmpty);
      expect(first.warnings, hasLength(1));
    });

    test('warnings raised while opening come first in every save', () {
      final DocxDocument doc = DocxDocument.open(buildDocx(contentType: null));
      expect(doc.warnings.single.code, DocxWarningCode.contentTypeMissing);
      (doc.body.blocks.single as DocxParagraph).addRun('\u0001');
      final DocxResult result = doc.save();
      expect(result.warnings.map((DocxWarning w) => w.code), <DocxWarningCode>[
        DocxWarningCode.contentTypeMissing,
        DocxWarningCode.invalidCharactersRemoved,
      ]);
      expect(doc.warnings, result.warnings);
    });

    test('an edited body saves and reopens with the edits', () {
      final DocxDocument doc = DocxDocument.open(wordDocx());
      final DocxBody body = doc.body;
      body.addParagraph('Toplam: 1.234,50 ₺').style = 'Total';
      body.removeBlockAt(3);
      body.replaceBlockAt(0, DocxParagraph.text('Başlık'));
      body.insertBlock(1, DocxParagraph());
      final DocxDocument reopened = DocxDocument.open(doc.save().bytes);
      expect(_outline(reopened), <String>[
        'p:Başlık',
        'p:',
        'opaque:sdt',
        'p:Kalem: Defter\t12\nadet',
        'p:Son',
        'p:Toplam: 1.234,50 ₺',
      ]);
      expect((reopened.body.blocks.last as DocxParagraph).style, 'Total');
    });

    test('DocxDocument() starts a document of one empty paragraph', () {
      final DocxDocument doc = DocxDocument();
      expect(doc.body.blocks, hasLength(1));
      expect((doc.body.blocks.single as DocxParagraph).inlines, isEmpty);
    });

    test('a limit below 1 throws ArgumentError', () {
      expect(
        () => DocxDocument.open(
          wordDocx(),
          limits: const DocxReadLimits(maxDepth: 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('body edits', () {
    test('inserting a block twice throws StateError and changes nothing', () {
      final DocxDocument doc = DocxDocument.open(wordDocx());
      final DocxBody body = doc.body;
      final DocxParagraph p = DocxParagraph.text('yeni');
      body.insertBlock(1, p);
      final List<DocxBlock> before = body.blocks.toList();
      expect(() => body.insertBlock(0, p), throwsStateError);
      expect(() => body.insertBlock(6, p), throwsStateError);
      final DocxBlock read = body.blocks.first;
      expect(() => body.insertBlock(0, read), throwsStateError);
      expect(() => body.replaceBlockAt(0, p), throwsStateError);
      expect(body.blocks, before);
      expect(blockContainerOf(p), same(body));

      // A removed block has no container and can be inserted again.
      body.removeBlockAt(1);
      expect(blockContainerOf(p), isNull);
      body.insertBlock(0, p);
      expect(body.blocks.first, same(p));
    });

    test('a block of another document throws StateError', () {
      final DocxBody one = DocxDocument.open(wordDocx()).body;
      final DocxBody two = DocxDocument.open(wordDocx()).body;
      expect(() => two.insertBlock(0, one.blocks.first), throwsStateError);
      expect(two.blocks, hasLength(5));
    });

    test('addParagraph appends a paragraph with the text', () {
      final DocxBody body = DocxDocument.open(wordDocx()).body;
      final DocxParagraph p = body.addParagraph('a\tb');
      expect(body.blocks.last, same(p));
      expect(p.text, 'a\tb');
      expect(body.addParagraph().inlines, isEmpty);
    });

    test('a bad index throws RangeError and changes nothing', () {
      final DocxDocument doc = DocxDocument.open(wordDocx());
      final DocxBody body = doc.body;
      expect(() => body.insertBlock(-1, DocxParagraph()), throwsRangeError);
      expect(() => body.insertBlock(6, DocxParagraph()), throwsRangeError);
      expect(() => body.removeBlockAt(5), throwsRangeError);
      expect(() => body.replaceBlockAt(5, DocxParagraph()), throwsRangeError);
      expect(body.blocks, hasLength(5));
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('the blocks view is unmodifiable and shows later edits', () {
      final DocxBody body = DocxDocument.open(wordDocx()).body;
      final List<DocxBlock> blocks = body.blocks;
      expect(() => blocks.add(DocxParagraph()), throwsUnsupportedError);
      expect(blocks.removeLast, throwsUnsupportedError);
      body.addParagraph('x');
      expect(blocks, hasLength(6));
    });

    test('the body is loaded once', () {
      final DocxDocument doc = DocxDocument.open(wordDocx());
      expect(isBodyLoaded(doc), isFalse);
      expect(doc.body, same(doc.body));
      expect(isBodyLoaded(doc), isTrue);
    });

    test('a paragraph edit is recorded as a change', () {
      final DocxDocument doc = DocxDocument.open(wordDocx());
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      expect(changeLogOf(doc).hasChanges, isFalse);
      p.style = 'Heading1';
      expect(changeLogOf(doc).hasChanges, isTrue);
    });
  });

  group('failures', () {
    test('a broken document.xml throws DocxReadException on first body '
        'access, and saving without access copies it', () {
      const String broken =
          '<w:document xmlns:w="${Ns.w}"><w:body><w:p></w:body>'
          '</w:document>';
      final Uint8List input = wordDocx(document: broken);
      final DocxDocument doc = DocxDocument.open(input);
      final DocxReadException e = _refused(
        () => doc.body,
        DocxReadFailure.malformedXml,
      );
      expect(e.part, '/word/document.xml');
      // Still broken on a second access, and still not loaded.
      _refused(() => doc.body, DocxReadFailure.malformedXml);
      expect(isBodyLoaded(doc), isFalse);
      final Uint8List output = doc.save().bytes;
      expect(readXlsxBytes(output)['word/document.xml'], utf8.encode(broken));
    });

    test('a bad entity surfacing while reading the body is '
        'DocxReadException', () {
      final DocxDocument doc = DocxDocument.open(
        wordDocx(
          document:
              '<w:document xmlns:w="${Ns.w}"><w:body><w:p><w:r>'
              '<w:t>a &bogus; b</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
      _refused(() => doc.body, DocxReadFailure.malformedXml);
    });

    test('a body past maxTextLength is limitExceeded on first access', () {
      final DocxDocument doc = DocxDocument.open(
        wordDocx(),
        limits: const DocxReadLimits(maxTextLength: 5),
      );
      _refused(() => doc.body, DocxReadFailure.limitExceeded);
    });

    test('a document.xml missing from the ZIP but named by the root '
        'relationship throws missingDocument at open', () {
      final Map<String, List<int>> entries = docxEntries()
        ..remove('word/document.xml');
      final DocxReadException e = _refused(
        () => DocxDocument.open(buildZip(entries)),
        DocxReadFailure.missingDocument,
      );
      expect(e.part, '/word/document.xml');
    });

    test('a document.xml.rels that is malformed throws DocxReadException, '
        'not OpcFormatException, on first body access', () {
      final Uint8List input = wordDocx(documentRels: '<Relationships');
      final DocxDocument doc = DocxDocument.open(input);
      final DocxReadException e = _refused(
        () => doc.body,
        DocxReadFailure.malformedXml,
      );
      expect(e.part, '/word/_rels/document.xml.rels');
      // Never parsed, so it is copied as it was.
      expect(
        readXlsxBytes(doc.save().bytes)['word/_rels/document.xml.rels'],
        utf8.encode('<Relationships'),
      );
    });

    test('a relationship to a missing header is kept as written and does '
        'not throw in D1', () {
      const String rels =
          '<Relationships xmlns="$packageRelsNs">'
          '<Relationship Id="rId4" Type="${RelType.image}" '
          'Target="media/image1.png"/>'
          '<Relationship Id="rId9" Type="${RelType.header}" '
          'Target="header1.xml"/>'
          '</Relationships>';
      final Uint8List input = wordDocx(documentRels: rels);
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.body.blocks, hasLength(5));
      final Uint8List output = doc.save().bytes;
      expect(comparePackages(input, output), isEmpty);
      final String saved = utf8.decode(
        readXlsxBytes(output)['word/_rels/document.xml.rels']!,
      );
      expect(saved, contains('Target="header1.xml"'));
      expect(saved, contains('Id="rId9"'));
      expect(readXlsxBytes(output).containsKey('word/header1.xml'), isFalse);
    });

    test('a damaged entry of a part never loaded is refused at open', () {
      final Uint8List zip = wordDocx(store: true);
      final int at = indexOfBytes(zip, utf8.encode('<w:zoom'));
      expect(at, greaterThan(0));
      final DocxReadException e = _refused(
        () => DocxDocument.open(Uint8List.fromList(zip)..[at + 3] = 0x5A),
        DocxReadFailure.corruptZip,
      );
      expect(e.part, '/word/settings.xml');
    });

    test('a file that is not a ZIP throws notZip at open', () {
      _refused(
        () => DocxDocument.open(Uint8List.fromList(utf8.encode('hello'))),
        DocxReadFailure.notZip,
      );
    });
  });
}
