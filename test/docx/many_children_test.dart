// Tests that a property container with very many children the schema lacks
// reads, writes and saves: a small ZIP can hold hundreds of thousands of them,
// so nothing may recurse once per child. The documents are built in memory,
// so these tests run on the web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_package.dart';
import 'package:jet_office/src/docx/related_part.dart';
import 'package:jet_office/src/docx/warnings.dart';
import 'package:jet_office/src/opc/ooxml.dart' show ContentType, Ns, RelType;
import 'package:jet_office/src/opc/package.dart' show PartContent;
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import 'support/docx_builder.dart';
import 'support/numbering_documents.dart';
import 'support/styles_documents.dart';

const int _count = 200000;

const String _x = 'urn:x';

/// [_count] children the schema lacks.
final String _kept = '<x:a/>' * _count;

/// Such children compress far past the default ratio.
const DocxReadLimits _limits = DocxReadLimits(maxCompressionRatio: 1000000);

DocxDocument _open(Uint8List bytes) =>
    DocxDocument.open(bytes, limits: _limits);

/// A main part whose body is [body].
String _document(String body) =>
    '<w:document xmlns:w="${Ns.w}" xmlns:x="$_x"><w:body>$body</w:body>'
    '</w:document>';

/// How many of the children [xml] holds.
int _keptIn(String xml) => '<x:a/>'.allMatches(xml).length;

DocxParagraph _paragraph(DocxDocument doc) =>
    doc.body.blocks.first as DocxParagraph;

/// A package content whose encode throws what [_fail] throws.
final class _Failing implements PartContent {
  _Failing(this._fail);

  final Never Function() _fail;

  @override
  List<Uint8List> encode() => _fail();
}

void main() {
  group('$_count children the schema lacks', () {
    test('in a run: the body loads, saves and is edited', () {
      final DocxDocument doc = _open(
        buildDocx(
          document: _document(
            '<w:p><w:r><w:rPr><w:i/>$_kept</w:rPr><w:t>a</w:t></w:r></w:p>',
          ),
        ),
      );
      final DocxRun run = _paragraph(doc).inlines.single as DocxRun;
      expect(doc.save().bytes, isNotEmpty);
      run.properties.bold = true;
      final String xml = readDocxText(doc.save().bytes)['word/document.xml']!;
      expect(_keptIn(xml), _count);
      expect(xml, contains('<w:rPr><w:b/><w:i/><x:a/>'));
    });

    test('in a paragraph: the kept children stay in their order', () {
      final DocxDocument doc = _open(
        buildDocx(
          document: _document(
            '<w:p><w:pPr>$_kept<x:last/><w:keepNext/></w:pPr></w:p>',
          ),
        ),
      );
      _paragraph(doc).properties.keepLines = true;
      final String xml = readDocxText(doc.save().bytes)['word/document.xml']!;
      expect(_keptIn(xml), _count);
      expect(xml, contains('<x:a/><x:last/><w:keepNext/><w:keepLines/>'));
    });

    test('in a style: the styles load, save and are edited', () {
      final DocxDocument doc = _open(
        docxWithStyles(
          styles:
              '<w:styles xmlns:w="${Ns.w}" xmlns:x="$_x">'
              '<w:style w:type="paragraph" w:styleId="S"><w:name w:val="s"/>'
              '<w:rPr><w:i/>$_kept</w:rPr></w:style></w:styles>',
        ),
      );
      final DocxStyle style = doc.styles.byId('S')!;
      expect(doc.save().bytes, isNotEmpty);
      style.runProperties.bold = true;
      final String xml = readDocxText(doc.save().bytes)['word/styles.xml']!;
      expect(_keptIn(xml), _count);
    });

    test('in a list level: the numbering loads, saves and is edited', () {
      final DocxDocument doc = _open(
        docxWithNumbering(
          numbering:
              '<w:numbering xmlns:w="${Ns.w}" xmlns:x="$_x">'
              '<w:abstractNum w:abstractNumId="0">'
              '<w:lvl w:ilvl="0"><w:start w:val="1"/>$_kept'
              '<w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>'
              '${numXml('1', '0')}</w:numbering>',
        ),
      );
      final DocxNumberingLevel level =
          doc.numbering.abstractNumberings.single.levels.single;
      expect(doc.save().bytes, isNotEmpty);
      level.start = 3;
      final String xml = readDocxText(doc.save().bytes)['word/numbering.xml']!;
      expect(_keptIn(xml), _count);
    });
  });

  group('the encode of a part when it loads', () {
    RelatedPart slot() => RelatedPart.find(
      DocxPackage(docxWithStyles(), _limits, DocxWarningCollector()),
      source: '/word/document.xml',
      relationshipType: RelType.styles,
      defaultName: '/word/styles.xml',
      contentType: ContentType.wmlStyles,
    );

    for (final (String name, Never Function() fail)
        in <(String, Never Function())>[
          ('an error', () => throw StateError('broken')),
          ('a stack overflow', () => throw const StackOverflowError()),
          ('an exception', () => throw const FormatException('broken')),
        ]) {
      test('that fails with $name is a DocxReadException naming the part', () {
        expect(
          () => slot().load<_Failing>((XmlPullReader r) => _Failing(fail)),
          throwsA(
            isA<DocxReadException>().having(
              (DocxReadException e) => e.part,
              'part',
              '/word/styles.xml',
            ),
          ),
        );
      });
    }

    test('that fails leaves the part to be copied as it was', () {
      final Uint8List input = docxWithStyles();
      final DocxPackage package = DocxPackage(
        input,
        const DocxReadLimits(),
        DocxWarningCollector(),
      );
      final RelatedPart part = RelatedPart.find(
        package,
        source: '/word/document.xml',
        relationshipType: RelType.styles,
        defaultName: '/word/styles.xml',
        contentType: ContentType.wmlStyles,
      );
      expect(
        () => part.load<_Failing>(
          (XmlPullReader r) => _Failing(() => throw StateError('broken')),
        ),
        throwsA(isA<DocxReadException>()),
      );
      final ZipWriter zip = ZipWriter();
      package.package.writeTo(zip);
      expect(
        readDocxText(zip.close()!)['word/styles.xml'],
        readDocxText(input)['word/styles.xml'],
      );
    });
  });
}
