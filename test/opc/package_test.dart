import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import '../xlsx/read/support/zip_builder.dart';

const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _relNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _typesNs =
    'http://schemas.openxmlformats.org/package/2006/content-types';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

String _rels(List<String> items) =>
    '<Relationships xmlns="$_relNs">${items.join()}</Relationships>';

String _item(String id, String type, String target, {bool external = false}) =>
    '<Relationship Id="$id" Type="$type" Target="$target"'
    '${external ? ' TargetMode="External"' : ''}/>';

ZipReader _reader(List<(String, String)> entries) => ZipReader(
  buildZipOrdered(<(String, List<int>)>[
    for (final (String name, String body) in entries) (name, _utf8(body)),
  ]),
  maxEntries: 1000,
  maxEntryBytes: 1 << 24,
  maxTotalBytes: 1 << 26,
  maxCompressionRatio: 1000,
);

OpcPackage _package(List<(String, String)> entries) =>
    OpcPackage.read(_reader(entries), maxDepth: 64);

OpcPackage _reopen(OpcPackage package) {
  final ZipWriter writer = ZipWriter();
  package.writeTo(writer);
  return OpcPackage.read(
    ZipReader(
      writer.close()!,
      maxEntries: 1000,
      maxEntryBytes: 1 << 24,
      maxTotalBytes: 1 << 26,
      maxCompressionRatio: 1000,
    ),
    maxDepth: 64,
  );
}

final class _Text implements PartContent {
  _Text(this.text);
  final String text;

  @override
  List<Uint8List> encode() => <Uint8List>[_utf8(text)];
}

String _text(OpcPackage p, String name) => utf8.decode(p.originalBytes(name));

void main() {
  group('parts', () {
    test('parts keep ZIP order and names', () {
      final OpcPackage p = _package(<(String, String)>[
        ('xl/worksheets/sheet2.xml', '<b/>'),
        ('[Content_Types].xml', '<Types xmlns="$_typesNs"/>'),
        ('_rels/.rels', _rels(<String>[])),
        ('xl\\workbook.xml', '<a/>'),
        ('xl/_rels/workbook.xml.rels', _rels(<String>[])),
        ('docProps/App.xml', '<c/>'),
      ]);
      expect(p.partNames.toList(), <String>[
        '/xl/worksheets/sheet2.xml',
        '/xl/workbook.xml',
        '/docProps/App.xml',
      ]);
      expect(p.hasPart('/XL/Workbook.xml'), isTrue);
      expect(p.hasPart('xl/workbook.xml'), isTrue);
      expect(p.hasPart('[Content_Types].xml'), isFalse);
      expect(p.hasPart('/_rels/.rels'), isFalse);
      expect(p.hasPart('/nope.xml'), isFalse);
    });

    test('unloaded parts are written from their original bytes', () {
      final OpcPackage p = _package(<(String, String)>[
        ('[Content_Types].xml', '<Types xmlns="$_typesNs"/>'),
        ('b.xml', '<b>é</b>'),
        ('a.bin', 'raw \u0000 bytes'),
      ]);
      final OpcPackage again = _reopen(p);
      expect(again.partNames.toList(), <String>['/b.xml', '/a.bin']);
      for (final String name in p.partNames) {
        expect(again.originalBytes(name), p.originalBytes(name), reason: name);
      }
      expect(p.isLoaded('/b.xml'), isFalse);
    });

    test('originalBytes of an unknown part is a missingPart failure', () {
      final OpcPackage p = _package(<(String, String)>[('a.xml', '<a/>')]);
      expect(
        () => p.originalBytes('/gone.xml'),
        throwsA(
          isA<OpcFormatException>().having(
            (OpcFormatException e) => e.kind,
            'kind',
            OpcFormatKind.missingPart,
          ),
        ),
      );
    });

    test('verifyEntries reports a damaged entry as a zip failure', () {
      final Uint8List zip = buildZipOrdered(<(String, List<int>)>[
        ('a.xml', _utf8('<a/>')),
        ('_rels/.rels', _utf8(_rels(<String>[]))),
        ('b.xml', _utf8('<b>hello</b>')),
      ], store: true);
      ZipReader open() => ZipReader(
        zip,
        maxEntries: 1000,
        maxEntryBytes: 1 << 24,
        maxTotalBytes: 1 << 26,
        maxCompressionRatio: 1000,
      );
      final OpcPackage intact = OpcPackage.read(open(), maxDepth: 64)
        ..verifyEntries();
      expect(intact.partNames.where(intact.isLoaded), isEmpty);
      final int at = String.fromCharCodes(zip).indexOf('hello');
      zip[at] ^= 0x01;
      expect(
        () => OpcPackage.read(open(), maxDepth: 64).verifyEntries(),
        throwsA(
          isA<OpcFormatException>()
              .having(
                (OpcFormatException e) => e.kind,
                'kind',
                OpcFormatKind.zip,
              )
              .having((OpcFormatException e) => e.part, 'part', 'b.xml')
              .having(
                (OpcFormatException e) => e.cause,
                'cause',
                isA<ZipReadError>(),
              ),
        ),
      );
      expect(OpcPackage.empty().verifyEntries, returnsNormally);
    });

    test('openXml reads a part and a loaded part', () {
      final OpcPackage p = _package(<(String, String)>[('a.xml', '<a/>')]);
      final XmlPullReader r = p.openXml('/a.xml');
      expect(r.next(), isTrue);
      expect(r.localName, 'a');
      p.setContent('/a.xml', _Text('<z/>'));
      final XmlPullReader z = p.openXml('/a.xml');
      z.next();
      expect(z.localName, 'z');
    });

    test('a part set as content is serialized from it', () {
      final OpcPackage p = _package(<(String, String)>[
        ('[Content_Types].xml', '<Types xmlns="$_typesNs"/>'),
        ('a.xml', '<a/>'),
        ('b.xml', '<b/>'),
      ]);
      expect(p.isLoaded('/a.xml'), isFalse);
      p.setContent('/a.xml', _Text('<changed/>'));
      expect(p.isLoaded('/a.xml'), isTrue);
      expect(p.isLoaded('/b.xml'), isFalse);
      final OpcPackage again = _reopen(p);
      expect(_text(again, '/a.xml'), '<changed/>');
      expect(_text(again, '/b.xml'), '<b/>');
    });

    test('metadata parts are not loaded parts', () {
      final OpcPackage p = _package(<(String, String)>[('a.xml', '<a/>')]);
      expect(p.isLoaded('[Content_Types].xml'), isFalse);
      expect(p.isLoaded('/_rels/.rels'), isFalse);
      expect(p.isLoaded('/unknown'), isFalse);
    });
  });

  group('content types', () {
    test('content types keep unknown defaults and overrides', () {
      final OpcPackage p = _package(<(String, String)>[
        (
          '[Content_Types].xml',
          '<Types xmlns="$_typesNs">'
              '<Default Extension="XML" ContentType="application/xml"/>'
              '<Default Extension="weird" ContentType="x/weird"/>'
              '<Override PartName="/a.xml" ContentType="x/a+xml"/>'
              '<Override PartName="/ghost.xml" ContentType="x/ghost"/>'
              '</Types>',
        ),
        ('a.xml', '<a/>'),
        ('b.XML', '<b/>'),
        ('c.weird', 'c'),
        ('d.none', 'd'),
      ]);
      expect(p.contentTypeOf('/a.xml'), 'x/a+xml');
      expect(p.contentTypeOf('/A.XML'), 'x/a+xml');
      expect(p.contentTypeOf('/b.XML'), 'application/xml');
      expect(p.contentTypeOf('/c.weird'), 'x/weird');
      expect(p.contentTypeOf('/d.none'), isNull);
      final OpcPackage again = _reopen(p);
      expect(again.contentTypeOf('/a.xml'), 'x/a+xml');
      expect(again.contentTypeOf('/c.weird'), 'x/weird');
      expect(again.contentTypeOf('/b.XML'), 'application/xml');
      expect(again.contentTypeOf('/ghost.xml'), 'x/ghost');
      expect(again.contentTypeOf('/d.none'), isNull);
    });

    test('a package without content types has none', () {
      final OpcPackage p = _package(<(String, String)>[('a.xml', '<a/>')]);
      expect(p.contentTypeOf('/a.xml'), isNull);
    });

    test('a malformed content types part is an xml failure', () {
      expect(
        () => _package(<(String, String)>[('[Content_Types].xml', '<Types>')]),
        throwsA(
          isA<OpcFormatException>()
              .having((e) => e.kind, 'kind', OpcFormatKind.xml)
              .having((e) => e.part, 'part', '[Content_Types].xml')
              .having((e) => e.cause, 'cause', isA<XmlParseException>()),
        ),
      );
    });
  });

  group('relationships', () {
    test('relationships keep unknown types and external mode', () {
      final OpcPackage p = _package(<(String, String)>[
        ('[Content_Types].xml', '<Types xmlns="$_typesNs"/>'),
        (
          '_rels/.rels',
          _rels(<String>[
            _item('rId1', '$_rel/officeDocument', 'xl/workbook.xml'),
            _item(
              'rId9',
              'urn:vendor:thing',
              'https://x.test/a',
              external: true,
            ),
          ]),
        ),
        ('xl/workbook.xml', '<w/>'),
      ]);
      const List<OpcRelationship> expected = <OpcRelationship>[
        (
          id: 'rId1',
          type: '$_rel/officeDocument',
          target: 'xl/workbook.xml',
          external: false,
        ),
        (
          id: 'rId9',
          type: 'urn:vendor:thing',
          target: 'https://x.test/a',
          external: true,
        ),
      ];
      expect(p.relationshipsOf(''), expected);
      expect(_reopen(p).relationshipsOf(''), expected);
      expect(p.relationshipsOf('/xl/workbook.xml'), isEmpty);
    });

    test('a malformed relationships part is an xml failure naming it', () {
      final OpcPackage p = _package(<(String, String)>[
        ('xl/workbook.xml', '<w/>'),
        ('xl/_rels/workbook.xml.rels', '<Relationships><Relationship'),
      ]);
      expect(
        () => p.relationshipsOf('xl/workbook.xml'),
        throwsA(
          isA<OpcFormatException>()
              .having((e) => e.kind, 'kind', OpcFormatKind.xml)
              .having((e) => e.part, 'part', 'xl/_rels/workbook.xml.rels'),
        ),
      );
    });

    test('isNewPartName accepts only a free name that is no folder, no '
        'package metadata and no prefix of a part', () {
      final OpcPackage p = _package(<(String, String)>[
        ('[Content_Types].xml', '<Types xmlns="$_typesNs"/>'),
        ('word/document.xml', '<w/>'),
        ('word/media/image1.png', 'x'),
      ]);
      expect(p.isNewPartName('/word/styles.xml'), isTrue);
      expect(p.isNewPartName('word\\styles/s.xml'), isTrue);
      for (final String bad in <String>[
        '',
        '/',
        '/word/',
        '/word',
        '/word/media',
        '/WORD/MEDIA',
        '/word/document.xml',
        '/word/document.xml/inner.xml',
        '/[Content_Types].xml',
        '/word/_rels/x.xml.rels',
        '/_rels/.rels',
      ]) {
        expect(p.isNewPartName(bad), isFalse, reason: bad);
      }
      p.addPart('/word/new.xml', 'x/new', _Text('<n/>'));
      expect(p.isNewPartName('/word/new.xml'), isFalse);
      expect(p.isNewPartName('/word/new.xml/a'), isFalse);
    });

    test('free names', () {
      final OpcPackage p = _package(<(String, String)>[
        ('[Content_Types].xml', '<Types xmlns="$_typesNs"/>'),
        (
          'xl/_rels/workbook.xml.rels',
          _rels(<String>[_item('rId7', '$_rel/worksheet', 'ws/data.xml')]),
        ),
        ('xl/workbook.xml', '<w/>'),
        ('xl/ws/data.xml', '<d/>'),
        ('xl/worksheets/sheet1.xml', '<s/>'),
        ('xl/worksheets/sheet2.xml', '<s/>'),
        ('xl/worksheets/sheet3.xml', '<s/>'),
      ]);
      expect(
        p.addPart(
          '/xl/worksheets/sheet1.xml',
          'x/sheet',
          _Text('<worksheet/>'),
        ),
        '/xl/worksheets/sheet4.xml',
      );
      expect(
        p.addPart('/xl/worksheets/sheet1.xml', 'x/sheet', _Text('<w/>')),
        '/xl/worksheets/sheet5.xml',
      );
      expect(p.addPart('/xl/new.xml', 'x/new', _Text('<n/>')), '/xl/new.xml');
      expect(p.addPart('/xl/new.xml', 'x/new', _Text('<n/>')), '/xl/new2.xml');
      expect(
        p.addPart('/xl/WORKSHEETS/Sheet1.xml', 'x/sheet', _Text('<w/>')),
        '/xl/WORKSHEETS/Sheet6.xml',
      );
      expect(p.partNames.last, '/xl/WORKSHEETS/Sheet6.xml');
      expect(p.isLoaded('/xl/worksheets/sheet4.xml'), isTrue);
      expect(p.contentTypeOf('/xl/worksheets/sheet4.xml'), 'x/sheet');

      expect(
        p.addRelationship('', type: '$_rel/officeDocument', target: 'a.xml'),
        'rId1',
      );
      expect(
        p.addRelationship('', type: '$_rel/officeDocument', target: 'b.xml'),
        'rId2',
      );
      expect(
        p.addRelationship(
          '/xl/workbook.xml',
          type: '$_rel/worksheet',
          target: 'worksheets/sheet4.xml',
        ),
        'rId1',
      );
      expect(
        p.addRelationship(
          '/xl/workbook.xml',
          type: '$_rel/worksheet',
          target: 'https://example.com',
          external: true,
        ),
        'rId2',
      );
      final OpcPackage again = _reopen(p);
      expect(
        again.relationshipsOf('/xl/workbook.xml').map((r) => r.id).toList(),
        <String>['rId7', 'rId1', 'rId2'],
      );
      expect(again.relationshipsOf('/xl/workbook.xml').last.external, isTrue);
      expect(
        () => p.addRelationship('/nope.xml', type: 't', target: 'x'),
        throwsArgumentError,
      );
    });

    test('removePart drops its override and relationships', () {
      final OpcPackage p = _package(<(String, String)>[
        (
          '[Content_Types].xml',
          '<Types xmlns="$_typesNs">'
              '<Override PartName="/xl/a.xml" ContentType="x/a"/>'
              '<Override PartName="/xl/b.xml" ContentType="x/b"/>'
              '</Types>',
        ),
        (
          '_rels/.rels',
          _rels(<String>[
            _item('rId1', '$_rel/officeDocument', '/xl/a.xml'),
            _item('rId2', '$_rel/other', 'xl/b.xml'),
          ]),
        ),
        (
          'xl/_rels/b.xml.rels',
          _rels(<String>[
            _item('rId1', '$_rel/other', 'a.xml'),
            _item(
              'rId2',
              '$_rel/other',
              'https://x.test/a.xml',
              external: true,
            ),
          ]),
        ),
        ('xl/a.xml', '<a/>'),
        ('xl/b.xml', '<b/>'),
        ('xl/_rels/a.xml.rels', _rels(<String>[_item('rId1', 't', 'b.xml')])),
      ]);
      p.removePart('/xl/a.xml');
      expect(p.hasPart('/xl/a.xml'), isFalse);
      expect(p.partNames.toList(), <String>['/xl/b.xml']);
      expect(p.contentTypeOf('/xl/a.xml'), isNull);
      expect(p.contentTypeOf('/xl/b.xml'), 'x/b');
      expect(p.relationshipsOf('').map((r) => r.id), <String>['rId2']);
      expect(p.relationshipsOf('/xl/b.xml').map((r) => r.id), <String>['rId2']);
      expect(p.relationshipsOf('/xl/a.xml'), isEmpty);
      final OpcPackage again = _reopen(p);
      expect(again.partNames.toList(), <String>['/xl/b.xml']);
      expect(again.relationshipsOf('/xl/a.xml'), isEmpty);
      expect(again.relationshipsOf('').single.target, 'xl/b.xml');
    });
  });

  group('input relationships parts', () {
    Uint8List write(OpcPackage p) {
      final ZipWriter w = ZipWriter();
      p.writeTo(w);
      return w.close()!;
    }

    ZipReader open(Uint8List b) => ZipReader(
      b,
      maxEntries: 1000,
      maxEntryBytes: 1 << 24,
      maxTotalBytes: 1 << 26,
      maxCompressionRatio: 1000,
    );

    test('empty ones are still written', () {
      final OpcPackage p = _package(<(String, String)>[
        ('_rels/.rels', '<Relationships/>'),
        ('xl/workbook.xml', '<w/>'),
        ('xl/_rels/workbook.xml.rels', '<Relationships/>'),
      ]);
      // Parse one, leave the other untouched.
      expect(p.relationshipsOf(''), isEmpty);
      final ZipReader z = open(write(p));
      expect(z.contains('_rels/.rels'), isTrue);
      expect(z.contains('xl/_rels/workbook.xml.rels'), isTrue);
    });

    test('an untouched one comes back byte-identical', () {
      const String raw =
          '<Relationships xmlns="$_relNs">'
          '<Relationship Id="rId1" Type="t" Target="http://x" '
          'TargetMode="external" extra="1"/></Relationships>';
      final OpcPackage p = _package(<(String, String)>[
        ('xl/workbook.xml', '<w/>'),
        ('xl/_rels/workbook.xml.rels', raw),
      ]);
      final ZipReader z = open(write(p));
      expect(utf8.decode(z.read('xl/_rels/workbook.xml.rels')), raw);
    });

    test('a malformed untouched one does not stop writeTo', () {
      const String bad = '<Relationships><Relationship';
      final OpcPackage p = _package(<(String, String)>[
        ('xl/workbook.xml', '<w/>'),
        ('xl/_rels/workbook.xml.rels', bad),
      ]);
      final ZipReader z = open(write(p));
      expect(utf8.decode(z.read('xl/_rels/workbook.xml.rels')), bad);
    });

    test('a new empty one is skipped and a removed part loses its own', () {
      final OpcPackage p = _package(<(String, String)>[
        ('a.xml', '<a/>'),
        ('b.xml', '<b/>'),
        ('_rels/a.xml.rels', '<Relationships/>'),
      ]);
      p.removePart('/a.xml');
      final ZipReader z = open(write(p));
      expect(z.contains('_rels/a.xml.rels'), isFalse);
      expect(z.contains('_rels/b.xml.rels'), isFalse);
    });

    test('removePart does not parse the removed part\'s own relationships', () {
      final OpcPackage p = _package(<(String, String)>[
        ('a.xml', '<a/>'),
        ('_rels/a.xml.rels', '<Relationships><Relationship'),
      ]);
      p.removePart('/a.xml');
      expect(p.hasPart('/a.xml'), isFalse);
      expect(open(write(p)).contains('_rels/a.xml.rels'), isFalse);
    });

    test('removePart with sources reads only their relationships', () {
      const String bad = '<Relationships><Relationship';
      final OpcPackage p = _package(<(String, String)>[
        ('xl/workbook.xml', '<w/>'),
        ('xl/calcChain.xml', '<c/>'),
        ('xl/sheet.xml', '<s/>'),
        (
          'xl/_rels/workbook.xml.rels',
          _rels(<String>[
            _item('rId1', '$_rel/calcChain', 'calcChain.xml'),
            _item('rId2', '$_rel/other', 'sheet.xml'),
          ]),
        ),
        ('xl/_rels/sheet.xml.rels', bad),
      ]);
      p.removePart('/xl/calcChain.xml', sources: <String>['/xl/workbook.xml']);
      expect(p.hasPart('/xl/calcChain.xml'), isFalse);
      expect(p.relationshipsOf('/xl/workbook.xml').map((r) => r.id), <String>[
        'rId2',
      ]);
      final ZipReader z = open(write(p));
      expect(utf8.decode(z.read('xl/_rels/sheet.xml.rels')), bad);
      expect(z.contains('xl/calcChain.xml'), isFalse);
    });

    test('an entry stored with a leading slash has one slash', () {
      final OpcPackage p = _package(<(String, String)>[('/xl/a.xml', '<a/>')]);
      expect(p.partNames.toList(), <String>['/xl/a.xml']);
      expect(p.hasPart('/xl/a.xml'), isTrue);
      expect(_text(p, '/xl/a.xml'), '<a/>');
    });
  });

  group('resolve', () {
    test('targets resolve relative, absolute, percent-encoded and with '
        'backslashes', () {
      final OpcPackage p = _package(<(String, String)>[
        ('xl/workbook.xml', '<w/>'),
        ('xl/worksheets/my sheet.xml', '<s/>'),
        ('sheets/s1.xml', '<s/>'),
        ('Sheets\\S2.xml', '<s/>'),
      ]);
      expect(
        p.resolve('/xl/workbook.xml', 'worksheets/x.xml'),
        '/xl/worksheets/x.xml',
      );
      expect(
        p.resolve('xl/workbook.xml', '../sheets/s1.xml'),
        '/sheets/s1.xml',
      );
      expect(p.resolve('/xl/workbook.xml', '/sheets/s2.xml'), '/sheets/s2.xml');
      expect(
        p.resolve('/xl/workbook.xml', r'worksheets\x.xml'),
        '/xl/worksheets/x.xml',
      );
      expect(p.resolve('', 'xl/workbook.xml'), '/xl/workbook.xml');
      expect(
        p.resolve('/xl/workbook.xml', './worksheets/./a/../x.xml'),
        '/xl/worksheets/x.xml',
      );
      expect(
        p.resolve('/xl/workbook.xml', 'worksheets/my%20sheet.xml'),
        '/xl/worksheets/my sheet.xml',
      );
      for (final String bad in <String>[
        '%FF.xml',
        'a%C3.xml',
        '%zz.xml',
        '%',
      ]) {
        expect(p.resolve('/xl/workbook.xml', bad), '/xl/$bad', reason: bad);
      }
      expect(p.resolve('/xl/workbook.xml', '../../../up.xml'), '/up.xml');
    });
  });
}
