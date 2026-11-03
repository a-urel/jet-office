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

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';
const String _wp14 =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing';
const String _wps =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingShape';

/// A `document.xml` as Word writes it: the root declares every namespace
/// and `mc:Ignorable`, paragraphs carry w14 ids and rsids, and the body
/// holds a block-level and an inline content control, a picture whose
/// `a:` namespace is declared on `a:graphic` itself, and markup
/// compatibility content.
const String _wordDocument =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/'
    'wordprocessingCanvas" xmlns:mc="${Ns.mc}" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:r="${Ns.rel}" '
    'xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="$_wp14" '
    'xmlns:wp="${Ns.wp}" xmlns:w10="urn:schemas-microsoft-com:office:word" '
    'xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}" xmlns:wps="$_wps" '
    'mc:Ignorable="w14 wp14">'
    '<w:body>'
    '<w:p w14:paraId="1A2B3C4D" w14:textId="77777777" w:rsidR="00A13F2E" '
    'w:rsidRDefault="00A13F2E" w:rsidP="00B21C11">'
    '<w:pPr><w:pStyle w:val="Title"/><w:rPr><w:lang w:val="tr-TR"/></w:rPr>'
    '</w:pPr>'
    '<w:r w:rsidRPr="00C3D4E5"><w:rPr><w:lang w:val="tr-TR"/></w:rPr>'
    '<w:t>Fiyat listesi</w:t></w:r>'
    '<w:proofErr w:type="spellStart"/>'
    '<w:r><w:t xml:space="preserve">Ürün </w:t></w:r>'
    '<w:proofErr w:type="spellEnd"/>'
    '</w:p>'
    '<w:sdt><w:sdtPr><w:id w:val="-1523981"/><w:docPartObj>'
    '<w:docPartGallery w:val="Table of Contents"/><w:docPartUnique/>'
    '</w:docPartObj></w:sdtPr><w:sdtEndPr/><w:sdtContent>'
    '<w:p w14:paraId="2B3C4D5E" w14:textId="2B3C4D5E" w:rsidR="00A13F2E">'
    '<w:r><w:t>İçindekiler</w:t></w:r></w:p>'
    '</w:sdtContent></w:sdt>'
    '<w:p w14:paraId="3C4D5E6F" w14:textId="3C4D5E6F" w:rsidR="00A13F2E" '
    'w:rsidRDefault="00D4E5F6">'
    '<w:r><w:t xml:space="preserve">Kalem: </w:t></w:r>'
    '<w:sdt><w:sdtPr><w:alias w:val="Ad"/><w:tag w:val="name"/>'
    '<w:id w:val="88"/></w:sdtPr><w:sdtContent>'
    '<w:r w:rsidR="00D4E5F6"><w:t>Defter</w:t></w:r>'
    '</w:sdtContent></w:sdt>'
    '<w:r><w:tab/><w:t>12</w:t><w:br/><w:t>adet</w:t></w:r>'
    '</w:p>'
    '<w:p w14:paraId="4D5E6F70" w14:textId="4D5E6F70" w:rsidR="00A13F2E">'
    '<w:r><w:rPr><w:noProof/></w:rPr><w:drawing>'
    '<wp:inline distT="0" distB="0" distL="0" distR="0" '
    'wp14:anchorId="5E6F7081" wp14:editId="5E6F7081">'
    '<wp:extent cx="914400" cy="457200"/>'
    '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
    '<wp:docPr id="1" name="Picture 1"/>'
    '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="$_a" '
    'noChangeAspect="1"/></wp:cNvGraphicFramePr>'
    '<a:graphic xmlns:a="$_a">'
    '<a:graphicData uri="$_pic">'
    '<pic:pic xmlns:pic="$_pic"><pic:nvPicPr>'
    '<pic:cNvPr id="1" name="logo.png"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="rId4"/><a:stretch><a:fillRect/>'
    '</a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="457200"/>'
    '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
    '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
    '</w:p>'
    '<w:p w14:paraId="5E6F7081" w14:textId="5E6F7081" w:rsidR="00A13F2E">'
    '<w:r><mc:AlternateContent><mc:Choice Requires="wps">'
    '<w:drawing><wp:anchor distT="0" distB="0" distL="114300" '
    'distR="114300" simplePos="0" relativeHeight="251659264" behindDoc="0" '
    'locked="0" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/>'
    '<wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset>'
    '</wp:positionH><wp:positionV relativeFrom="paragraph">'
    '<wp:posOffset>0</wp:posOffset></wp:positionV>'
    '<wp:extent cx="914400" cy="457200"/><wp:wrapNone/>'
    '<wp:docPr id="2" name="Text Box 2"/><a:graphic xmlns:a="$_a">'
    '<a:graphicData uri="$_wps"><wps:wsp><wps:bodyPr/></wps:wsp>'
    '</a:graphicData></a:graphic></wp:anchor></w:drawing>'
    '</mc:Choice><mc:Fallback><w:pict><v:rect style="width:72pt"/></w:pict>'
    '</mc:Fallback></mc:AlternateContent></w:r>'
    '<w:r><w:t>Son</w:t></w:r>'
    '</w:p>'
    '<w:sectPr w:rsidR="00A13F2E"><w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
    'w:header="708" w:footer="708" w:gutter="0"/><w:cols w:space="708"/>'
    '<w:docGrid w:linePitch="360"/></w:sectPr>'
    '</w:body></w:document>';

/// The relationships of [_wordDocument]: its picture.
const String _wordDocumentRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId4" Type="${RelType.image}" '
    'Target="media/image1.png"/>'
    '</Relationships>';

/// A small binary stand-in for a PNG.
final List<int> _png = <int>[0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3, 255];

/// A DOCX holding [document], with [documentRels] as its relationships
/// when given, a picture, and a settings part the model never loads.
Uint8List _docx({
  String document = _wordDocument,
  String? documentRels = _wordDocumentRels,
  bool store = false,
}) => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(rootRels('word/document.xml')),
  'word/document.xml': utf8.encode(document),
  if (documentRels != null)
    'word/_rels/document.xml.rels': utf8.encode(documentRels),
  'word/media/image1.png': _png,
  'word/settings.xml': utf8.encode(
    '<w:settings xmlns:w="${Ns.w}"><w:zoom w:percent="100"/></w:settings>',
  ),
}, store: store);

/// The document's paragraph texts and opaque block names, in order.
List<String> _outline(DocxDocument doc) => <String>[
  for (final DocxBlock b in doc.body.blocks)
    switch (b) {
      DocxParagraph() => 'p:${b.text}',
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
      final Uint8List input = _docx();
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
      final Uint8List input = _docx();
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
      // The body was written from the model, not copied.
      expect(
        after['word/document.xml'],
        isNot(equals(before['word/document.xml'])),
      );
      expect(after['word/settings.xml'], before['word/settings.xml']);
      expect(doc.warnings, isEmpty);
    });

    test('open, set one run text, save differs only in that w:t', () {
      final Uint8List input = _docx();
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

    test('saveTo streams the same bytes as save', () {
      final DocxDocument doc = DocxDocument.open(_docx());
      (doc.body.blocks.first as DocxParagraph).addRun(' 2026');
      final Uint8List saved = doc.save().bytes;
      final _Collect sink = _Collect();
      doc.saveTo(sink);
      expect(sink.closed, isTrue);
      expect(sink.bytes.takeBytes(), saved);
    });

    test('a save returns the warnings of that save, and warnings keeps '
        'them', () {
      final DocxDocument doc = DocxDocument.open(_docx());
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
      final DocxDocument doc = DocxDocument.open(_docx());
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

    test('DocxDocument() starts an empty document', () {
      final DocxDocument doc = DocxDocument();
      expect(doc.body.blocks, isEmpty);
    }, skip: 'Task 11 fills in DocxDocument()');

    test('a limit below 1 throws ArgumentError', () {
      expect(
        () => DocxDocument.open(
          _docx(),
          limits: const DocxReadLimits(maxDepth: 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('body edits', () {
    test('inserting a block twice throws StateError and changes nothing', () {
      final DocxDocument doc = DocxDocument.open(_docx());
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
      final DocxBody one = DocxDocument.open(_docx()).body;
      final DocxBody two = DocxDocument.open(_docx()).body;
      expect(() => two.insertBlock(0, one.blocks.first), throwsStateError);
      expect(two.blocks, hasLength(5));
    });

    test('addParagraph appends a paragraph with the text', () {
      final DocxBody body = DocxDocument.open(_docx()).body;
      final DocxParagraph p = body.addParagraph('a\tb');
      expect(body.blocks.last, same(p));
      expect(p.text, 'a\tb');
      expect(body.addParagraph().inlines, isEmpty);
    });

    test('a bad index throws RangeError and changes nothing', () {
      final DocxDocument doc = DocxDocument.open(_docx());
      final DocxBody body = doc.body;
      expect(() => body.insertBlock(-1, DocxParagraph()), throwsRangeError);
      expect(() => body.insertBlock(6, DocxParagraph()), throwsRangeError);
      expect(() => body.removeBlockAt(5), throwsRangeError);
      expect(() => body.replaceBlockAt(5, DocxParagraph()), throwsRangeError);
      expect(body.blocks, hasLength(5));
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('the blocks view is unmodifiable and shows later edits', () {
      final DocxBody body = DocxDocument.open(_docx()).body;
      final List<DocxBlock> blocks = body.blocks;
      expect(() => blocks.add(DocxParagraph()), throwsUnsupportedError);
      expect(blocks.removeLast, throwsUnsupportedError);
      body.addParagraph('x');
      expect(blocks, hasLength(6));
    });

    test('the body is loaded once', () {
      final DocxDocument doc = DocxDocument.open(_docx());
      expect(isBodyLoaded(doc), isFalse);
      expect(doc.body, same(doc.body));
      expect(isBodyLoaded(doc), isTrue);
    });

    test('a paragraph edit is recorded as a change', () {
      final DocxDocument doc = DocxDocument.open(_docx());
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
      final Uint8List input = _docx(document: broken);
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
        _docx(
          document:
              '<w:document xmlns:w="${Ns.w}"><w:body><w:p><w:r>'
              '<w:t>a &bogus; b</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
      _refused(() => doc.body, DocxReadFailure.malformedXml);
    });

    test('a body past maxTextLength is limitExceeded on first access', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(),
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
      final Uint8List input = _docx(documentRels: '<Relationships');
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
      final Uint8List input = _docx(documentRels: rels);
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
      final Uint8List zip = _docx(store: true);
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
