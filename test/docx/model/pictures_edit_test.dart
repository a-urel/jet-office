// Tests building pictures: `DocxParagraph.addPicture` adds a run holding a new
// `DocxPicture`, sized from the image's pixels at 96 dpi or from the size
// given, and each save gives it a media part (shared with any part holding the
// same image), an image relationship of the part it is in, a `wp:docPr` id
// unique across the story parts and, without a name, `Picture <id>`; nothing
// of that is stored in the model, and the save takes it all back once the
// file is written (plan D5, Rulings 6, 7 and A). Bad arguments throw and
// change nothing; a failed transaction or an undo leaves no media part,
// content type or relationship. They build documents in memory, so they run
// on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/m4_fixtures.dart';
import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';

/// The ZIP entries of [bytes].
Map<String, Uint8List> _entries(Uint8List bytes) => readXlsxBytes(bytes);

/// The `Relationship` elements of [rels] of the image type, each as its id
/// and target.
List<(String, String)> _images(String rels) => <(String, String)>[
  for (final Match m in RegExp(
    r'<Relationship [^>]*Id="([^"]*)"[^>]*Type="'
    '${RegExp.escape(RelType.image)}'
    r'"[^>]*Target="([^"]*)"',
  ).allMatches(rels))
    (m[1]!, m[2]!),
];

/// The value of every [attribute] of every [element] (a qualified name) of
/// [xml], in order.
List<String> _values(String xml, String element, String attribute) => <String>[
  for (final Match m in RegExp(
    '<${RegExp.escape(element)}\\b[^>]*?\\s$attribute="([^"]*)"',
  ).allMatches(xml))
    m[1]!,
];

/// The media parts of [entries], by name.
List<String> _media(Map<String, Uint8List> entries) =>
    entries.keys.where((String k) => k.startsWith('word/media/')).toList();

/// The first paragraph of [doc]'s body.
DocxParagraph _first(DocxDocument doc) =>
    doc.body.blocks.whereType<DocxParagraph>().first;

/// A package whose body shows `word/media/image3.png` and whose content types
/// declare `png` by default.
Uint8List _withImage3() {
  const String decls =
      'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}" xmlns:wp="${Ns.wp}" '
      'xmlns:a="$_a" xmlns:pic="$_pic"';
  return buildDocx(
    document:
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $decls><w:body><w:p><w:r><w:drawing><wp:inline>'
        '<wp:extent cx="38100" cy="19050"/><wp:docPr id="7" name="Old"/>'
        '<a:graphic><a:graphicData uri="$_pic"><pic:pic><pic:nvPicPr>'
        '<pic:cNvPr id="7" name="Old"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rId1"/></pic:blipFill><pic:spPr/>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
        '</w:p></w:body></w:document>',
    extra: <String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="$contentTypesNs">'
        '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="${ContentType.wmlDocument}"/></Types>',
      ),
      'word/_rels/document.xml.rels': utf8.encode(
        '<Relationships xmlns="$packageRelsNs">'
        '<Relationship Id="rId1" Type="${RelType.image}" '
        'Target="media/image3.png"/></Relationships>',
      ),
      'word/media/image3.png': png4x2,
    },
  );
}

/// The first 24 bytes of a PNG of [width] by [height] pixels: its signature
/// and the start of its `IHDR`, which is all `checkImage` reads of it.
Uint8List _pngOfSize(int width, int height) {
  int byte(int value, int shift) => (value >> shift) & 0xFF;
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
    byte(width, 24), byte(width, 16), byte(width, 8), byte(width, 0), //
    byte(height, 24), byte(height, 16), byte(height, 8), byte(height, 0), //
    8, 2, 0, 0, 0, 0, 0, 0, 0, //
  ]);
}

/// [_withImage3] with [rels] in place of the main part's relationships and
/// [footer], when given, as `word/footer1.xml`, a footer part the main
/// part's `rId2` names.
Uint8List _withImage3And({required String rels, String? footer}) {
  final Uint8List base = _withImage3();
  final Map<String, Uint8List> entries = _entries(base);
  return buildDocx(
    document: utf8.decode(entries['word/document.xml']!),
    extra: <String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="$contentTypesNs">'
        '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="${ContentType.wmlDocument}"/>'
        '<Override PartName="/word/footer1.xml" '
        'ContentType="${ContentType.wmlFooter}"/></Types>',
      ),
      'word/_rels/document.xml.rels': utf8.encode(
        '<Relationships xmlns="$packageRelsNs">$rels</Relationships>',
      ),
      'word/media/image3.png': png4x2,
      if (footer != null) 'word/footer1.xml': utf8.encode(footer),
    },
  );
}

/// A GIF's first bytes: a format neither PNG nor JPEG.
final Uint8List _gif = Uint8List.fromList(utf8.encode('GIF89a\x04\x00'));

void main() {
  group('a picture in the body', () {
    test('adds a media part, a png default, a relationship and an inline', () {
      final DocxDocument doc = DocxDocument();
      final OfficeImage image = OfficeImage(png4x2);
      final DocxPicture picture = _first(doc).addPicture(image);
      expect(picture.widthPt, 3);
      expect(picture.heightPt, 1.5);
      expect(picture.image, same(image));
      expect(picture.name, '');
      expect(picture.description, isNull);
      final DocxRun run = _first(doc).inlines.single as DocxRun;
      expect(run.content.single, same(picture));
      expect(run.text, '');

      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), <String>['word/media/image1.png']);
      expect(entries['word/media/image1.png'], png4x2);
      final String types = utf8.decode(entries['[Content_Types].xml']!);
      expect(
        types,
        contains('<Default Extension="png" ContentType="image/png"/>'),
      );
      expect(types, isNot(contains('/word/media/image1.png')));
      final List<(String, String)> rels = _images(
        utf8.decode(entries['word/_rels/document.xml.rels']!),
      );
      expect(rels.single.$2, 'media/image1.png');
      final String main = utf8.decode(entries['word/document.xml']!);
      expect(_values(main, 'wp:extent', 'cx'), <String>['38100']);
      expect(_values(main, 'wp:extent', 'cy'), <String>['19050']);
      final List<String> ids = _values(main, 'wp:docPr', 'id');
      expect(ids, hasLength(1));
      expect(_values(main, 'pic:cNvPr', 'id'), ids);
      expect(_values(main, 'wp:docPr', 'name'), <String>[
        'Picture ${ids.single}',
      ]);
      expect(_values(main, 'a:blip', 'r:embed'), <String>[rels.single.$1]);
    });

    test('a large image with no size is scaled to fit 1584 pt', () {
      final DocxDocument doc = DocxDocument();
      final DocxPicture wide = _first(
        doc,
      ).addPicture(OfficeImage(_pngOfSize(3000, 1500)));
      expect((wide.widthPt, wide.heightPt), (1584, 792));
      final DocxPicture tall = _first(
        doc,
      ).addPicture(OfficeImage(_pngOfSize(100, 4000)));
      expect((tall.widthPt, tall.heightPt), (39.6, 1584));
    });

    test('one side given scales the other; both are used as given', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = _first(doc);
      final OfficeImage image = OfficeImage(png4x2);
      final DocxPicture wide = p.addPicture(image, widthPt: 96);
      expect((wide.widthPt, wide.heightPt), (96, 48));
      final DocxPicture tall = p.addPicture(image, heightPt: 10);
      expect((tall.widthPt, tall.heightPt), (20, 10));
      final DocxPicture both = p.addPicture(image, widthPt: 7, heightPt: 70);
      expect((both.widthPt, both.heightPt), (7, 70));
      final String main = utf8.decode(
        _entries(doc.save().bytes)['word/document.xml']!,
      );
      expect(_values(main, 'wp:extent', 'cx'), <String>[
        '1219200',
        '254000',
        '88900',
      ]);
      expect(_values(main, 'wp:extent', 'cy'), <String>[
        '609600',
        '127000',
        '889000',
      ]);
      // One media part and one relationship for three pictures of one image.
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), hasLength(1));
      expect(
        _images(utf8.decode(entries['word/_rels/document.xml.rels']!)),
        hasLength(1),
      );
      final List<String> ids = _values(main, 'wp:docPr', 'id');
      expect(ids.toSet(), hasLength(3));
      expect(_values(main, 'pic:cNvPr', 'id'), ids);
    });

    test('a name and a description are written on docPr and cNvPr', () {
      final DocxDocument doc = DocxDocument();
      final DocxPicture picture = _first(doc).addPicture(
        OfficeImage(png4x2),
        name: 'Logo <1>',
        description: 'Our "logo"',
      );
      expect(picture.name, 'Logo <1>');
      expect(picture.description, 'Our "logo"');
      final String main = utf8.decode(
        _entries(doc.save().bytes)['word/document.xml']!,
      );
      expect(_values(main, 'wp:docPr', 'name'), <String>['Logo &lt;1&gt;']);
      expect(_values(main, 'pic:cNvPr', 'name'), <String>['Logo &lt;1&gt;']);
      expect(_values(main, 'wp:docPr', 'descr'), <String>[
        'Our &quot;logo&quot;',
      ]);
    });

    test('a JPEG takes .jpeg and its own default', () {
      final DocxDocument doc = DocxDocument();
      final DocxPicture picture = _first(doc).addPicture(OfficeImage(jpeg3x5));
      expect((picture.widthPt, picture.heightPt), (2.25, 3.75));
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), <String>['word/media/image1.jpeg']);
      expect(
        utf8.decode(entries['[Content_Types].xml']!),
        contains('<Default Extension="jpeg" ContentType="image/jpeg"/>'),
      );
    });

    test('equal bytes in another OfficeImage share the media part', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = _first(doc);
      p.addPicture(OfficeImage(png4x2));
      p.addPicture(OfficeImage(Uint8List.fromList(png4x2)));
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), <String>['word/media/image1.png']);
    });

    test('a file whose media has image3.png gets image4.png', () {
      final DocxDocument doc = DocxDocument.open(_withImage3());
      _first(doc).addPicture(OfficeImage(jpeg3x5));
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries)..sort(), <String>[
        'word/media/image3.png',
        'word/media/image4.jpeg',
      ]);
      final String main = utf8.decode(entries['word/document.xml']!);
      // The new docPr id is one more than the highest the file holds.
      expect(_values(main, 'wp:docPr', 'id'), <String>['7', '8']);
    });

    test('a name a dangling relationship targets is skipped', () {
      final DocxDocument doc = DocxDocument.open(
        _withImage3And(
          rels:
              '<Relationship Id="rId1" Type="${RelType.image}" '
              'Target="media/image3.png"/>'
              '<Relationship Id="rId9" Type="${RelType.image}" '
              'Target="media/image4.png"/>',
        ),
      );
      // Other bytes than image3.png's, so the image is not shared.
      _first(doc).addPicture(OfficeImage(_pngOfSize(8, 8)));
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries)..sort(), <String>[
        'word/media/image3.png',
        'word/media/image5.png',
      ]);
    });

    test('an unreadable relationships part does not block a picture', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document: utf8.decode(_entries(_withImage3())['word/document.xml']!),
          extra: <String, List<int>>{
            ..._entries(_withImage3()),
            'word/other.xml': utf8.encode('<x/>'),
            'word/_rels/other.xml.rels': utf8.encode('<Relationships'),
          },
        ),
      );
      _first(doc).addPicture(OfficeImage(jpeg3x5));
      expect(
        _media(_entries(doc.save().bytes)),
        contains('word/media/image4.jpeg'),
      );
    });

    test('a new docPr id goes past one held in a footer of the file', () {
      final DocxDocument doc = DocxDocument.open(
        _withImage3And(
          rels:
              '<Relationship Id="rId1" Type="${RelType.image}" '
              'Target="media/image3.png"/>'
              '<Relationship Id="rId2" Type="${RelType.footer}" '
              'Target="footer1.xml"/>',
          footer:
              '<w:ftr xmlns:w="${Ns.w}" xmlns:wp="${Ns.wp}"><w:p><w:r>'
              '<w:drawing><wp:inline><wp:docPr id="40" name="Foot"/>'
              '</wp:inline></w:drawing></w:r></w:p></w:ftr>',
        ),
      );
      _first(doc).addPicture(OfficeImage(png4x2));
      final String main = utf8.decode(
        _entries(doc.save().bytes)['word/document.xml']!,
      );
      expect(_values(main, 'wp:docPr', 'id'), <String>['7', '41']);
    });

    test('the image a file holds is shared, through its relationship', () {
      final Uint8List input = _withImage3();
      final DocxDocument doc = DocxDocument.open(input);
      final DocxPicture read = _first(doc).inlines
          .whereType<DocxRun>()
          .single
          .content
          .whereType<DocxPicture>()
          .single;
      _first(doc).addPicture(read.image!);
      _first(doc).addPicture(OfficeImage(Uint8List.fromList(png4x2)));
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), <String>['word/media/image3.png']);
      final String rels = utf8.decode(entries['word/_rels/document.xml.rels']!);
      expect(_images(rels), <(String, String)>[('rId1', 'media/image3.png')]);
      final String main = utf8.decode(entries['word/document.xml']!);
      expect(_values(main, 'a:blip', 'r:embed'), <String>[
        'rId1',
        'rId1',
        'rId1',
      ]);
      expect(
        entries['[Content_Types].xml'],
        _entries(DocxDocument.open(input).save().bytes)['[Content_Types].xml'],
      );
    });

    test('a relationship whose id XML cannot hold is not shared', () {
      // As the XLSX model's feature fuzz found (seed 9 case 446 of
      // tool/fuzz_reader.dart --features): the id read is U+FFFE.
      final DocxDocument doc = DocxDocument.open(
        _withImage3And(
          rels:
              '<Relationship Id="&#xFFFE;" Type="${RelType.image}" '
              'Target="media/image3.png"/>',
        ),
      );
      _first(doc).addPicture(OfficeImage(Uint8List.fromList(png4x2)));
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), <String>['word/media/image3.png']);
      final String main = utf8.decode(entries['word/document.xml']!);
      final String id = _values(main, 'a:blip', 'r:embed').last;
      expect(id, isNot('\uFFFE'));
      final String rels = utf8.decode(entries['word/_rels/document.xml.rels']!);
      expect(_images(rels), contains((id, 'media/image3.png')));
    });

    test('a, pic and wp are declared where the root does not', () {
      // A new document's root declares wp but neither a nor pic.
      final DocxDocument doc = DocxDocument();
      _first(doc).addPicture(OfficeImage(png4x2));
      final String main = utf8.decode(
        _entries(doc.save().bytes)['word/document.xml']!,
      );
      expect(main, contains('<wp:inline distT="0" distB="0" distL="0" '));
      expect(main, isNot(contains('<wp:inline xmlns:wp')));
      expect(main, contains('<a:graphic xmlns:a="$_a">'));
      expect(main, contains('<a:graphicFrameLocks xmlns:a="$_a" '));
      expect(main, contains('<pic:pic xmlns:pic="$_pic">'));
      // A root that declares all three gets no declaration below it.
      final DocxDocument declared = DocxDocument.open(_withImage3());
      _first(declared).addPicture(OfficeImage(png4x2));
      final String all = utf8.decode(
        _entries(declared.save().bytes)['word/document.xml']!,
      );
      for (final String prefix in <String>['wp', 'a', 'pic', 'r']) {
        expect(RegExp('xmlns:$prefix=').allMatches(all), hasLength(1));
      }
      // A root that declares none of them, nor r.
      final DocxDocument bare = DocxDocument.open(
        buildDocx(
          document:
              '<w:document xmlns:w="${Ns.w}"><w:body><w:p/></w:body>'
              '</w:document>',
        ),
      );
      _first(bare).addPicture(OfficeImage(png4x2));
      final String none = utf8.decode(
        _entries(bare.save().bytes)['word/document.xml']!,
      );
      expect(none, contains('<wp:inline xmlns:wp="${Ns.wp}" '));
      expect(none, contains('<pic:pic xmlns:pic="$_pic" xmlns:r="${Ns.rel}">'));
    });
  });

  group('one image in several parts', () {
    test('body, a header cell and a footer: one media part, three rels', () {
      final DocxDocument doc = DocxDocument();
      final OfficeImage image = OfficeImage(png4x2);
      final DocxSection section = doc.sections.single;
      _first(doc).addPicture(image);
      final DocxTable table = section.header.addTable(columns: 1);
      table.addRow(<String?>[null]);
      section.header.addParagraph();
      (table.rows.single.cells.single.blocks.single as DocxParagraph)
          .addPicture(image);
      section.footer.addParagraph().addPicture(image);

      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), <String>['word/media/image1.png']);
      final List<String> ids = <String>[];
      for (final String part in <String>['document', 'header1', 'footer1']) {
        final List<(String, String)> rels = _images(
          utf8.decode(entries['word/_rels/$part.xml.rels']!),
        );
        expect(rels.single.$2, 'media/image1.png', reason: part);
        final String xml = utf8.decode(entries['word/$part.xml']!);
        expect(_values(xml, 'a:blip', 'r:embed'), <String>[rels.single.$1]);
        ids.addAll(_values(xml, 'wp:docPr', 'id'));
      }
      expect(ids.toSet(), hasLength(3));
    });

    test('the body and a body cell share one relationship', () {
      final DocxDocument doc = DocxDocument();
      final OfficeImage image = OfficeImage(png4x2);
      _first(doc).addPicture(image);
      final DocxTable table = doc.body.addTable(columns: 1);
      table.addRow(<String?>[null]);
      doc.body.addParagraph();
      (table.rows.single.cells.single.blocks.single as DocxParagraph)
          .addPicture(image);
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      final List<(String, String)> rels = _images(
        utf8.decode(entries['word/_rels/document.xml.rels']!),
      );
      expect(rels, hasLength(1));
      expect(
        _values(
          utf8.decode(entries['word/document.xml']!),
          'a:blip',
          'r:embed',
        ),
        <String>[rels.single.$1, rels.single.$1],
      );
    });

    test('a picture in a header saved twice gives the same file', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.single.header.addParagraph().addPicture(OfficeImage(png4x2));
      final Uint8List first = doc.save().bytes;
      expect(doc.save().bytes, first);
      final Map<String, Uint8List> entries = _entries(first);
      expect(_media(entries), <String>['word/media/image1.png']);
      expect(
        _images(utf8.decode(entries['word/_rels/header1.xml.rels']!)),
        hasLength(1),
      );
    });
  });

  group('bad arguments throw and change nothing', () {
    final Map<String, DocxPicture Function(DocxParagraph)> cases =
        <String, DocxPicture Function(DocxParagraph)>{
          'a GIF': (DocxParagraph p) => p.addPicture(OfficeImage(_gif)),
          'widthPt 0': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), widthPt: 0),
          'widthPt 2000': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), widthPt: 2000),
          'heightPt NaN': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), heightPt: double.nan),
          'heightPt infinite': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), heightPt: double.infinity),
          'widthPt -1 with heightPt': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), widthPt: -1, heightPt: 5),
          'a side computed from widthPt over 1584': (DocxParagraph p) =>
              p.addPicture(OfficeImage(_pngOfSize(100, 4000)), widthPt: 50),
          'a side computed from heightPt over 1584': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), heightPt: 800),
          'a name with U+0001': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), name: 'a\u0001'),
          'a description with U+FFFE': (DocxParagraph p) =>
              p.addPicture(OfficeImage(png4x2), description: 'a\uFFFE'),
        };
    final Map<String, Matcher> errors = <String, Matcher>{
      'a GIF': throwsArgumentError,
      'a name with U+0001': throwsArgumentError,
      'a description with U+FFFE': throwsArgumentError,
    };
    for (final MapEntry<String, DocxPicture Function(DocxParagraph)> c
        in cases.entries) {
      test(c.key, () {
        final Uint8List input = DocxDocument().save().bytes;
        final DocxDocument doc = DocxDocument.open(input);
        final DocxParagraph p = _first(doc);
        expect(() => c.value(p), errors[c.key] ?? throwsRangeError);
        expect(p.inlines, isEmpty);
        expect(changeLogOf(doc).hasChanges, isFalse);
        expect(doc.save().bytes, input);
      });
    }
  });

  group('undo and saves', () {
    test('a transaction that throws leaves no media, type or relationship', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = _first(doc);
      expect(
        () => editsOf(doc).transaction(() {
          p.addPicture(OfficeImage(png4x2));
          throw StateError('stop');
        }),
        throwsStateError,
      );
      expect(p.inlines, isEmpty);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('save, picture, save, undo, save gives the first file again', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      // The footer's part is created, and kept, by the first save (D4).
      final DocxParagraph foot = doc.sections.single.footer.addParagraph();
      final Uint8List first = doc.save().bytes;
      final DocxParagraph p = _first(doc);
      final ChangeSet set = editsOf(doc).transaction(() {
        p.addPicture(OfficeImage(png4x2));
        foot.addPicture(OfficeImage(jpeg3x5));
      });
      final Uint8List withPictures = doc.save().bytes;
      expect(_media(_entries(withPictures)), hasLength(2));
      expect(doc.save().bytes, withPictures);
      changeLogOf(doc).revertSet(set);
      final Uint8List undone = doc.save().bytes;
      expect(_media(_entries(undone)), isEmpty);
      expect(
        utf8.decode(_entries(undone)['[Content_Types].xml']!),
        isNot(anyOf(contains('Extension="png"'), contains('jpeg'))),
      );
      expect(comparePackages(first, undone), isEmpty);
      changeLogOf(doc).reapplySet(set);
      expect(doc.save().bytes, withPictures);
    });

    test('a picture and a first properties set save the same bytes twice', () {
      // The properties parts are kept by the save, the media parts are taken
      // back after it: kept parts must be added first, or the next save writes
      // the media before the properties and the ZIP order differs.
      final DocxDocument built = DocxDocument();
      built.sections.single.footer.addParagraph();
      final Uint8List input = built.save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = _first(doc);
      final DocxParagraph foot =
          doc.sections.single.footer.blocks.single as DocxParagraph;
      final ChangeSet set = editsOf(doc).transaction(() {
        p.addPicture(OfficeImage(png4x2));
        foot.addHyperlink('site', url: 'https://x.test/');
        foot.addPicture(OfficeImage(jpeg3x5));
        doc.properties = const OfficeProperties(title: 'T');
      });
      final Uint8List first = doc.save().bytes;
      expect(_media(_entries(first)), hasLength(2));
      expect(doc.save().bytes, first);
      changeLogOf(doc).revertSet(set);
      expect(doc.save().bytes, input);
      changeLogOf(doc).reapplySet(set);
      expect(doc.save().bytes, first);
    });

    test('a removed picture leaves no media part at the next save', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = _first(doc);
      p.addPicture(OfficeImage(png4x2));
      doc.save();
      p.removeInlineAt(0);
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), isEmpty);
      expect(
        entries['word/_rels/document.xml.rels'],
        _entries(input)['word/_rels/document.xml.rels'],
      );
      expect(
        entries['[Content_Types].xml'],
        _entries(DocxDocument.open(input).save().bytes)['[Content_Types].xml'],
      );
    });

    test('setting the text of a built picture\'s run leaves no media', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = _first(doc);
      p.addPicture(OfficeImage(png4x2));
      expect(_media(_entries(doc.save().bytes)), hasLength(1));
      (p.inlines.single as DocxRun).text = 'words';
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), isEmpty);
      expect(
        entries['word/_rels/document.xml.rels'],
        _entries(input)['word/_rels/document.xml.rels'],
      );
    });

    test('a picture built in a paragraph of no document saves once in one', () {
      final DocxParagraph p = DocxParagraph();
      final DocxPicture picture = p.addPicture(OfficeImage(png4x2));
      final DocxDocument doc = DocxDocument();
      doc.body.insertBlock(1, p);
      final Map<String, Uint8List> entries = _entries(doc.save().bytes);
      expect(_media(entries), <String>['word/media/image1.png']);
      final List<(String, String)> rels = _images(
        utf8.decode(entries['word/_rels/document.xml.rels']!),
      );
      expect(
        _values(
          utf8.decode(entries['word/document.xml']!),
          'a:blip',
          'r:embed',
        ),
        <String>[rels.single.$1],
      );
      expect(picture.image!.bytes, png4x2);
    });

    test('a picture reads back typed, with its image', () {
      final DocxDocument doc = DocxDocument();
      _first(
        doc,
      ).addPicture(OfficeImage(png4x2), widthPt: 30, description: 'Alt');
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxPicture read = _first(again).inlines
          .whereType<DocxRun>()
          .single
          .content
          .whereType<DocxPicture>()
          .single;
      expect((read.widthPt, read.heightPt), (30, 15));
      expect(read.name, startsWith('Picture '));
      expect(read.description, 'Alt');
      expect(read.image!.bytes, png4x2);
      expect(comparePackages(doc.save().bytes, again.save().bytes), isEmpty);
    });

    test('a built picture works in a second document', () {
      final DocxDocument one = DocxDocument();
      final DocxParagraph p = _first(one);
      final DocxPicture picture = p.addPicture(OfficeImage(png4x2));
      one.save();
      final DocxRun run = p.inlines.single as DocxRun;
      p.removeInlineAt(0);
      final DocxDocument two = DocxDocument();
      _first(two).insertInline(0, run);
      expect(run.content.single, same(picture));
      final Map<String, Uint8List> entries = _entries(two.save().bytes);
      expect(_media(entries), <String>['word/media/image1.png']);
      expect(
        _images(utf8.decode(entries['word/_rels/document.xml.rels']!)),
        hasLength(1),
      );
      expect(_media(_entries(one.save().bytes)), isEmpty);
    });
  });
}
