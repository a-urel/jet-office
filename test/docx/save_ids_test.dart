import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/docx/docx_package.dart';
import 'package:jet_office/src/docx/read_limits.dart';
import 'package:jet_office/src/docx/save_ids.dart';
import 'package:jet_office/src/docx/warnings.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import 'support/docx_builder.dart';

const String _ns = 'xmlns:w="${Ns.w}" xmlns:wp="${Ns.wp}" xmlns:r="${Ns.rel}"';

/// A drawing whose `wp:docPr` has the id [id].
String _drawing(String id) =>
    '<w:r><w:drawing><wp:inline><wp:docPr id="$id" name="P"/>'
    '</wp:inline></w:drawing></w:r>';

/// A bookmark start and end with the id [id].
String _bookmark(String id) =>
    '<w:bookmarkStart w:id="$id" w:name="b$id"/><w:bookmarkEnd w:id="$id"/>';

String _paragraph(String inner) => '<w:p>$inner</w:p>';

String _document(String body, {String after = ''}) =>
    '<w:document $_ns><w:body>$body</w:body></w:document>$after';

/// A package of [parts] (entry name to `(content type, XML)`) beside the
/// main part [document], with [mainRels] as the main part's relationships.
Uint8List _package(
  String document, {
  Map<String, (String, String)> parts = const <String, (String, String)>{},
  String? mainRels,
}) => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="${ContentType.xml}"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '${parts.entries.map((MapEntry<String, (String, String)> e) => '<Override PartName="/${e.key}" ContentType="${e.value.$1}"/>').join()}'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(rootRels('word/document.xml')),
  'word/document.xml': utf8.encode(document),
  if (mainRels != null) 'word/_rels/document.xml.rels': utf8.encode(mainRels),
  for (final MapEntry<String, (String, String)> e in parts.entries)
    e.key: utf8.encode(e.value.$2),
});

DocxPackage _open(Uint8List bytes) =>
    DocxPackage(bytes, const DocxReadLimits(), DocxWarningCollector());

String _rels(List<String> ids) =>
    '<Relationships xmlns="$packageRelsNs">'
    '${ids.map((String id) => '<Relationship Id="$id" Type="t" Target="x$id.xml"/>').join()}'
    '</Relationships>';

Uint8List _write(OpcPackage p) {
  final ZipWriter w = ZipWriter();
  p.writeTo(w);
  return w.close()!;
}

ZipReader _zip(Uint8List bytes) => ZipReader(
  bytes,
  maxEntries: 1000,
  maxEntryBytes: 1 << 24,
  maxTotalBytes: 1 << 26,
  maxCompressionRatio: 1000,
);

void main() {
  group('drawing and bookmark ids', () {
    /// Drawings 1 to 9 and bookmarks 0 to 9 in the body, drawing 10 in a
    /// footer, bookmark 10 in a footnotes part, and higher ids where the
    /// scan must not look.
    Uint8List ids() => _package(
      _document(
        <String>[
          for (int i = 1; i <= 9; i++) _paragraph(_drawing('$i')),
          for (int i = 0; i <= 9; i++) _paragraph(_bookmark('$i')),
          _paragraph(_drawing('abc') + _bookmark('x')),
          _paragraph(_drawing('-40') + _bookmark('-40')),
          _paragraph(_drawing('99999999999999999999')),
        ].join(),
      ),
      parts: <String, (String, String)>{
        'word/footer1.xml': (
          ContentType.wmlFooter,
          '<w:ftr $_ns>${_paragraph(_drawing('10'))}</w:ftr>',
        ),
        'word/footnotes.xml': (
          ContentType.wmlFootnotes,
          '<w:footnotes $_ns><w:footnote w:id="1">'
              '${_paragraph(_bookmark('10'))}</w:footnote></w:footnotes>',
        ),
        // Not a story part: its ids do not count.
        'word/other.xml': (
          ContentType.xml,
          '<w:ftr $_ns>${_paragraph(_drawing('500') + _bookmark('500'))}'
              '</w:ftr>',
        ),
      },
    );

    test('a new drawing id is one more than the highest of every story', () {
      final SaveIds saveIds = SaveIds(_open(ids()));
      expect(saveIds.nextDrawingId(), 11);
      expect(saveIds.nextDrawingId(), 12);
    });

    test('a new bookmark id is one more than the highest of every story', () {
      final SaveIds saveIds = SaveIds(_open(ids()));
      expect(saveIds.nextBookmarkId(), 11);
      expect(saveIds.nextBookmarkId(), 12);
      // The two counters are apart.
      expect(saveIds.nextDrawingId(), 11);
    });

    test('headers, endnotes and comments count', () {
      for (final String type in <String>[
        ContentType.wmlHeader,
        ContentType.wmlEndnotes,
        ContentType.wmlComments,
      ]) {
        final SaveIds saveIds = SaveIds(
          _open(
            _package(
              _document(_paragraph(_drawing('3'))),
              parts: <String, (String, String)>{
                'word/part.xml': (
                  type,
                  '<w:root $_ns>${_paragraph(_drawing('7') + _bookmark('4'))}'
                      '</w:root>',
                ),
              },
            ),
          ),
        );
        expect(saveIds.nextDrawingId(), 8, reason: type);
        expect(saveIds.nextBookmarkId(), 5, reason: type);
      }
    });

    test('a story part typed as generic XML counts when the main part names '
        'it as a header or footer', () {
      for (final (String, String) named in <(String, String)>[
        (RelType.footer, 'w:ftr'),
        (RelType.header, 'w:hdr'),
      ]) {
        final SaveIds saveIds = SaveIds(
          _open(
            _package(
              _document(_paragraph(_drawing('3') + _bookmark('4'))),
              mainRels:
                  '<Relationships xmlns="$packageRelsNs">'
                  '<Relationship Id="rId1" Type="${named.$1}" '
                  'Target="part.xml"/></Relationships>',
              parts: <String, (String, String)>{
                'word/part.xml': (
                  ContentType.xml,
                  '<${named.$2} $_ns>'
                      '${_paragraph(_drawing('20') + _bookmark('20'))}'
                      '</${named.$2}>',
                ),
              },
            ),
          ),
        );
        expect(saveIds.nextBookmarkId(), 21, reason: named.$2);
        expect(saveIds.nextDrawingId(), 21, reason: named.$2);
      }
    });

    test('an id of eleven digits is reserved', () {
      final SaveIds saveIds = SaveIds(
        _open(_package(_document(_paragraph(_bookmark('12345678901'))))),
      );
      expect(saveIds.nextBookmarkId(), 12345678902);
    });

    test('with none, drawings start at 1 and bookmarks at 0', () {
      final SaveIds saveIds = SaveIds(_open(buildDocx()));
      expect(saveIds.nextDrawingId(), 1);
      expect(saveIds.nextBookmarkId(), 0);
      expect(saveIds.nextBookmarkId(), 1);
    });

    test('the scan stops at the end of the root', () {
      final SaveIds saveIds = SaveIds(
        _open(
          _package(
            _document(
              _paragraph(_drawing('2') + _bookmark('2')),
              // Well formed, with its own namespaces: only stopping at the
              // root's end leaves it out.
              after: '<w:p $_ns>${_drawing('70')}${_bookmark('70')}</w:p>',
            ),
          ),
        ),
      );
      expect(saveIds.nextDrawingId(), 3);
      expect(saveIds.nextBookmarkId(), 3);
    });

    test('an unreadable story keeps the ids found before it broke', () {
      final SaveIds saveIds = SaveIds(
        _open(
          _package(
            _document(_paragraph(_drawing('2'))),
            parts: <String, (String, String)>{
              'word/header1.xml': (
                ContentType.wmlHeader,
                '<w:hdr $_ns>${_paragraph(_drawing('20'))}<w:p><w:r',
              ),
            },
          ),
        ),
      );
      expect(saveIds.nextDrawingId(), 21);
      expect(saveIds.nextBookmarkId(), 0);
    });
  });

  group('relationship ids', () {
    const String referencing =
        '<w:p><w:hyperlink r:id="rId4"><w:r><w:t>a</w:t></w:r></w:hyperlink>'
        '<w:r><w:drawing><wp:inline><a:blip xmlns:a="a" r:embed="rId2"/>'
        '<a:blip xmlns:a="a" r:link="rId3"/></wp:inline></w:drawing></w:r>'
        '</w:p>';

    test('fileReferenceIds holds every r:id, r:embed and r:link', () {
      final SaveIds saveIds = SaveIds(
        _open(
          _package(
            _document(referencing, after: '<w:p $_ns r:id="rId7"/>'),
            mainRels: _rels(<String>['rId1']),
          ),
        ),
      );
      expect(saveIds.fileReferenceIds('/word/document.xml'), <String>{
        'rId4',
        'rId2',
        'rId3',
      });
      expect(saveIds.fileReferenceIds('/word/missing.xml'), isEmpty);
    });

    test('a new relationship takes none of them, a dangling one stays', () {
      final DocxPackage package = _open(
        _package(_document(referencing), mainRels: _rels(<String>['rId1'])),
      );
      final SaveIds saveIds = SaveIds(package);
      expect(
        saveIds.addRelationship(
          '/word/document.xml',
          type: RelType.hyperlink,
          target: 'https://example.com/',
          external: true,
        ),
        'rId5',
      );
      expect(
        saveIds.addRelationship(
          '/word/document.xml',
          type: RelType.image,
          target: 'media/image1.png',
        ),
        'rId6',
      );
      final List<OpcRelationship> rels = package.package.relationshipsOf(
        '/word/document.xml',
      );
      expect(rels.map((OpcRelationship r) => r.id), <String>[
        'rId1',
        'rId5',
        'rId6',
      ]);
      expect(rels[1].external, isTrue);
      expect(rels[1].target, 'https://example.com/');
      expect(rels[2].external, isFalse);
    });

    test('a story part gets its own, avoiding its own references', () {
      final DocxPackage package = _open(
        _package(
          _document('<w:p/>'),
          mainRels: _rels(<String>['rId1']),
          parts: <String, (String, String)>{
            'word/footer1.xml': (
              ContentType.wmlFooter,
              '<w:ftr $_ns>$referencing</w:ftr>',
            ),
          },
        ),
      );
      final SaveIds saveIds = SaveIds(package);
      expect(
        saveIds.addRelationship(
          '/word/footer1.xml',
          type: RelType.image,
          target: 'media/image1.png',
        ),
        'rId1',
      );
      expect(
        saveIds.addRelationship(
          '/word/footer1.xml',
          type: RelType.image,
          target: 'media/image2.png',
        ),
        'rId5',
      );
      final ZipReader zip = _zip(_write(package.package));
      expect(
        utf8.decode(zip.read('word/_rels/footer1.xml.rels')),
        contains('Id="rId5"'),
      );
      // The main part's relationships were never touched.
      expect(
        utf8.decode(zip.read('word/_rels/document.xml.rels')),
        _rels(<String>['rId1']),
      );
    });
  });
}
