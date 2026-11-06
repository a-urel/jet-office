// Tests the numbering part of a document: it loads on the first access to
// DocxDocument.numbering through the main part's relationship; an untouched
// one is copied byte for byte, a loaded one is written from the model and
// means what it meant; a document without one gains it at save only when
// it holds a definition, once (plan Ruling 7); a numPr set through the API
// that names no instance is reported at save (Ruling 8). The packages are
// built in memory, so these tests run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/docx/model/numbering.dart';
import 'package:jet_office/src/docx/model/primitives.dart' show DocxEdits;
import 'package:jet_office/src/docx/numbering_part.dart';
import 'package:jet_office/src/opc/change_log.dart' show ChangeSet;
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../support/read_xlsx.dart';
import 'support/numbering_documents.dart';
import 'support/styles_documents.dart' show readDocxText, stylesRelationship;

/// The targets of the main part's relationships of the numbering type.
List<String> _numberingTargets(Uint8List docx) {
  final String rels = readDocxText(docx)['word/_rels/document.xml.rels'] ?? '';
  return <String>[
    for (final RegExpMatch m in RegExp(
      r'<Relationship [^>]*Type="([^"]*)"[^>]*Target="([^"]*)"',
    ).allMatches(rels))
      if (m.group(1) == RelType.numbering) m.group(2)!,
  ];
}

/// The content type overrides of [docx] for [part] with the numbering type.
int _overridesOf(Uint8List docx, String part) => RegExp(
  '<Override PartName="${RegExp.escape(part)}" '
  'ContentType="${RegExp.escape(ContentType.wmlNumbering)}"/>',
).allMatches(readDocxText(docx)['[Content_Types].xml']!).length;

/// What [numbering] lists: each abstract definition's id with its number
/// of levels, each instance's id with its overrides (level and start), and
/// how many members of the levels read a value (all but `level`).
String _summary(DocxNumbering numbering) {
  int values = 0;
  for (final DocxAbstractNumbering a in numbering.abstractNumberings) {
    for (final DocxNumberingLevel l in a.levels) {
      values += <Object?>[
        l.format,
        l.text,
        l.start,
        l.alignment,
        l.indentation,
        l.bulletFont,
      ].where((Object? v) => v != null).length;
    }
  }
  final String abstracts = numbering.abstractNumberings
      .map((DocxAbstractNumbering a) => '${a.id}(${a.levels.length})')
      .join(' ');
  final String instances = numbering.instances
      .map(
        (DocxNumberingInstance n) =>
            '${n.id}[${n.overrides.map((DocxLevelOverride o) => '${o.level}:${o.startOverride}').join(' ')}]',
      )
      .join(' ');
  return 'abstracts $abstracts; instances $instances; values $values';
}

/// A document without a numbering part.
Uint8List _withoutNumbering() =>
    docxWithNumbering(numbering: null, relationships: '');

/// Gives [doc] a one-level decimal list and returns its instance.
DocxNumberingInstance _addList(DocxDocument doc) {
  final DocxNumbering numbering = doc.numbering;
  return numbering.addInstance(
    addAbstractNumbering(numbering, decimalTemplate),
  );
}

void main() {
  group('open and save', () {
    test('open, access numbering, save is semantically equal', () {
      final Uint8List input = docxWithNumbering();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.numbering.instances, hasLength(2));
      expect(isNumberingLoaded(doc), isTrue);
      final Uint8List output = doc.save().bytes;
      expect(comparePackages(input, output), isEmpty);
      // Nothing changed, so the part is copied.
      expect(
        readXlsxBytes(output)['word/numbering.xml'],
        readXlsxBytes(input)['word/numbering.xml'],
      );
      // What the model would write means the same.
      final String xml = utf8.decode(
        NumberingPart.read(
          XmlPullReader(wordNumberingXml),
          '/word/numbering.xml',
          DocxEdits(),
        ).encode().expand((Uint8List c) => c).toList(),
      );
      expect(compareXml('word/numbering.xml', wordNumberingXml, xml), isEmpty);
      for (final String kept in <String>[
        'w15:restartNumberingAfterBreak="0"',
        'w16cid:durableId="987654321"',
        '<w:numPicBullet w:numPicBulletId="0">',
        '<w:numIdMacAtCleanup w:val="1"/>',
        '<w:nsid w:val="1F2E3D4C"/>',
        '<w:tmpl w:val="A1B2C3D4"/>',
        'w:tplc="041F0003" w:tentative="1"',
        'mc:Ignorable="w14 w15 w16cid"',
      ]) {
        expect(xml, contains(kept));
      }
    });

    test('without access numbering.xml is copied byte for byte', () {
      final Uint8List input = docxWithNumbering();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.body.blocks, isNotEmpty);
      final Uint8List output = doc.save().bytes;
      expect(isNumberingLoaded(doc), isFalse);
      expect(
        readXlsxBytes(output)['word/numbering.xml'],
        readXlsxBytes(input)['word/numbering.xml'],
      );
    });

    test('an edit of a level writes the change and keeps the rest', () {
      final DocxDocument doc = DocxDocument.open(docxWithNumbering());
      doc.numbering.abstractNumberings[1].levels[0].start = 4;
      final Uint8List output = doc.save().bytes;
      final String xml = readDocxText(output)['word/numbering.xml']!;
      expect(
        xml,
        contains(
          '<w:lvl w:ilvl="0" w:tplc="041F000F"><w:start w:val="4"/>'
          '<w:numFmt w:val="decimal"/>',
        ),
      );
      final DocxDocument back = DocxDocument.open(output);
      expect(back.numbering.abstractNumberings[1].levels[0].start, 4);
      expect(back.numbering.abstractNumberings[1].levels[1].start, 3);
    });
  });

  group('a document without numbering.xml', () {
    test('reads an empty numbering and saves without the part', () {
      final DocxDocument doc = DocxDocument.open(_withoutNumbering());
      expect(doc.numbering.abstractNumberings, isEmpty);
      expect(doc.numbering.instances, isEmpty);
      final Uint8List output = doc.save().bytes;
      expect(readXlsxBytes(output).containsKey('word/numbering.xml'), isFalse);
      expect(_numberingTargets(output), isEmpty);
    });

    test('a document without numbering.xml that gets an instance gains the '
        'part, its override with ContentType.wmlNumbering and one '
        'relationship', () {
      final DocxDocument doc = DocxDocument.open(_withoutNumbering());
      final DocxNumberingInstance list = _addList(doc);
      expect(list.id, 1);
      expect(list.abstractId, 0);
      final Uint8List output = doc.save().bytes;
      expect(
        readDocxText(output)['word/numbering.xml'],
        contains('<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'),
      );
      expect(_overridesOf(output, '/word/numbering.xml'), 1);
      expect(_numberingTargets(output), <String>['numbering.xml']);
      final DocxDocument back = DocxDocument.open(output);
      expect(back.numbering.instanceById(1)?.abstractNumbering?.id, 0);
      expect(
        back.numbering.abstractNumberings.single.levels.single.text,
        '%1.',
      );
    });

    test('a second save adds nothing', () {
      final DocxDocument doc = DocxDocument.open(_withoutNumbering());
      _addList(doc);
      final Uint8List first = doc.save().bytes;
      final Uint8List second = doc.save().bytes;
      expect(_overridesOf(second, '/word/numbering.xml'), 1);
      expect(_numberingTargets(second), <String>['numbering.xml']);
      expect(comparePackages(first, second), isEmpty);
      expect(readXlsxBytes(second).keys, readXlsxBytes(first).keys);
    });

    test('a rolled-back instance leaves no part', () {
      final DocxDocument doc = DocxDocument.open(_withoutNumbering());
      expect(
        () => editsOf(doc).transaction(() {
          _addList(doc);
          throw StateError('fail');
        }),
        throwsStateError,
      );
      expect(doc.numbering.abstractNumberings, isEmpty);
      expect(doc.numbering.instances, isEmpty);
      final Uint8List output = doc.save().bytes;
      expect(readXlsxBytes(output).containsKey('word/numbering.xml'), isFalse);
      expect(_numberingTargets(output), isEmpty);
      expect(
        readDocxText(output)['[Content_Types].xml'],
        isNot(contains(ContentType.wmlNumbering)),
      );
    });

    test('a relationship to a missing part is reused at its target', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithNumbering(
          numbering: null,
          relationships: numberingRelationship('lists/n.xml'),
        ),
      );
      expect(doc.numbering.instances, isEmpty);
      _addList(doc);
      final Uint8List output = doc.save().bytes;
      expect(readDocxText(output)['word/lists/n.xml'], contains('w:numId'));
      expect(_numberingTargets(output), <String>['lists/n.xml']);
      expect(_overridesOf(output, '/word/lists/n.xml'), 1);
    });
  });

  group('hostile relationship targets', () {
    test('styles and numbering relationships to the same missing target '
        'both survive a save and reopen', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithNumbering(
          numbering: null,
          relationships:
              '${numberingRelationship('x.xml')}'
              '${stylesRelationship('x.xml')}',
        ),
      );
      doc.styles.add(
        DocxStyle(type: DocxStyleType.paragraph, id: 'Note', name: 'Note'),
      );
      _addList(doc);
      final Uint8List output = doc.save().bytes;
      final DocxDocument back = DocxDocument.open(output);
      expect(back.styles.byId('Note'), isNotNull);
      expect(back.numbering.instances, hasLength(1));
      expect(back.numbering.abstractNumberings.single.id, 0);
      expect(_numberingTargets(output), <String>['x.xml', 'x2.xml']);
    });

    for (final String target in <String>[
      'lists/',
      '',
      '../[Content_Types].xml',
      '_rels/document.xml.rels',
      'document.xml',
      'settings.xml',
      'media/image1.png',
    ]) {
      test('a numbering relationship to "$target" is kept and a new '
          '/word/numbering.xml gets its own relationship', () {
        final Uint8List input = docxWithNumbering(
          numbering: null,
          relationships: numberingRelationship(target),
        );
        final DocxDocument doc = DocxDocument.open(input);
        expect(doc.numbering.instances, isEmpty);
        final int blocks = doc.body.blocks.length;
        _addList(doc);
        final Uint8List output = doc.save().bytes;
        final Map<String, Uint8List> before = readXlsxBytes(input);
        final Map<String, Uint8List> after = readXlsxBytes(output);
        for (final String part in <String>[
          'word/settings.xml',
          'word/media/image1.png',
        ]) {
          expect(after[part], before[part], reason: part);
        }
        expect(readDocxText(output)['word/numbering.xml'], contains('w:numId'));
        expect(_numberingTargets(output), <String>[target, 'numbering.xml']);
        final DocxDocument back = DocxDocument.open(output);
        expect(back.body.blocks, hasLength(blocks));
        expect(back.numbering.instances, hasLength(1));
      });
    }
  });

  group('a broken numbering part', () {
    for (final (String name, String xml) in <(String, String)>[
      ('malformed XML', '<w:numbering xmlns:w="${Ns.w}"><w:num'),
      ('another root', '<w:styles xmlns:w="${Ns.w}"/>'),
    ]) {
      test('a malformed numbering.xml throws DocxReadException naming the '
          'part ($name)', () {
        final Uint8List input = docxWithNumbering(numbering: xml);
        final DocxDocument doc = DocxDocument.open(input);
        for (int i = 0; i < 2; i++) {
          expect(
            () => doc.numbering,
            throwsA(
              isA<DocxReadException>()
                  .having(
                    (DocxReadException e) => e.part,
                    'part',
                    '/word/numbering.xml',
                  )
                  .having(
                    (DocxReadException e) => e.reason,
                    'reason',
                    DocxReadFailure.malformedXml,
                  ),
            ),
          );
        }
        expect(isNumberingLoaded(doc), isFalse);
        final Uint8List output = doc.save().bytes;
        expect(
          readXlsxBytes(output)['word/numbering.xml'],
          readXlsxBytes(input)['word/numbering.xml'],
        );
      });
    }
  });

  group('untrusted input', () {
    final Map<String, String> cases = <String, String>{
      'duplicate ids':
          '${abstractNumXml('0')}${abstractNumXml('0')}'
          '${numXml('1', '0')}${numXml('1', '0')}',
      'a num of a missing abstractNum': numXml('1', '7'),
      'huge and negative ids':
          '${abstractNumXml('99999999999999999999')}'
          '${abstractNumXml('-1')}${numXml('-3', '0')}'
          '${numXml('999999999', '-1')}'
          '<w:num w:numId="4"/>'
          '<w:num w:numId="5"><w:abstractNumId w:val="0"/>'
          '<w:abstractNumId w:val="1"/></w:num>',
      'more than 9 levels':
          '<w:abstractNum w:abstractNumId="0">'
          '${List<String>.generate(12, (int i) => '<w:lvl w:ilvl="$i">'
              '<w:start w:val="$i"/><w:lvlText w:val="%${i % 9 + 1}"/></w:lvl>').join()}'
          '<w:lvl w:ilvl="x"/><w:lvl/>'
          '</w:abstractNum>${numXml('1', '0')}'
          '<w:num w:numId="2"><w:abstractNumId w:val="0"/>'
          '<w:lvlOverride w:ilvl="12"><w:startOverride w:val="1"/>'
          '</w:lvlOverride><w:lvlOverride w:ilvl="0">'
          '<w:startOverride w:val="99999"/><w:lvl w:ilvl="0"/>'
          '</w:lvlOverride></w:num>',
      'odd values':
          '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
          '<w:start w:val="1in"/><w:numFmt w:val="chicago"/>'
          '<w:numFmt w:val="custom" w:format="001, 002"/>'
          '<w:lvlText w:val="%0"/><w:lvlJc w:val="both"/>'
          '<w:pPr><w:ind w:left="1in"/></w:pPr>'
          '<w:rPr><w:rFonts w:ascii=""/></w:rPr></w:lvl></w:abstractNum>',
    };
    // What each case lists: the abstract ids with their level count, the
    // instance ids with their overrides, and how many level members read
    // a value.
    final Map<String, String> expected = <String, String>{
      'duplicate ids': 'abstracts 0(1) 0(1); instances 1[] 1[]; values 6',
      'a num of a missing abstractNum': 'abstracts ; instances 1[]; values 0',
      'huge and negative ids': 'abstracts ; instances ; values 0',
      'more than 9 levels':
          'abstracts 0(9); instances 1[] 2[0:null]; values 18',
      'odd values': 'abstracts 0(1); instances ; values 0',
    };
    cases.forEach((String name, String children) {
      test('$name: lists what it types, adds a list and saves', () {
        final DocxDocument doc = DocxDocument.open(
          docxWithNumbering(numbering: numberingXml(children)),
        );
        final DocxNumbering numbering = doc.numbering;
        expect(_summary(numbering), expected[name], reason: name);
        final DocxNumberingInstance added = _addList(doc);
        final Uint8List output = doc.save().bytes;
        final DocxDocument back = DocxDocument.open(output);
        expect(back.numbering.instanceById(added.id), isNotNull);
      });
    });

    test('duplicate ids are both kept and lookups return the first', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithNumbering(
          numbering: numberingXml(
            '${abstractNumXml('0')}${abstractNumXml('0')}'
            '${numXml('1', '0')}${numXml('1', '0')}',
          ),
        ),
      );
      final DocxNumbering numbering = doc.numbering;
      expect(numbering.abstractNumberings, hasLength(2));
      expect(numbering.instances, hasLength(2));
      expect(numbering.instanceById(1), same(numbering.instances.first));
      expect(
        numbering.instances.last.abstractNumbering,
        same(numbering.abstractNumberings.first),
      );
    });

    test('a picture bullet with a broken image relationship is kept', () {
      final Uint8List input = docxWithNumbering(
        pictureTarget: 'media/gone.png',
      );
      final DocxDocument doc = DocxDocument.open(input);
      _addList(doc);
      final Uint8List output = doc.save().bytes;
      expect(
        readDocxText(output)['word/numbering.xml'],
        contains('<v:imagedata r:id="rId1" o:title="mso"/>'),
      );
      expect(
        readXlsxBytes(output)['word/_rels/numbering.xml.rels'],
        readXlsxBytes(input)['word/_rels/numbering.xml.rels'],
      );
    });
  });

  group('a numbering part with no change keeps its bytes', () {
    final String kept =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<w:numbering xmlns:w="${Ns.w}"><!-- kept -->'
        '${abstractNumXml('0')}${numXml('1', '0')}</w:numbering>';

    DocxDocument open() =>
        DocxDocument.open(docxWithNumbering(numbering: kept));

    String saved(DocxDocument doc) =>
        readDocxText(doc.save().bytes)['word/numbering.xml']!;

    test('reading the numbering keeps it', () {
      final DocxDocument doc = open();
      expect(doc.numbering.instances, hasLength(1));
      expect(saved(doc), kept);
    });

    test('a list set that the check loads the part for keeps it', () {
      final DocxDocument doc = open();
      doc.body.addParagraph('a').properties.numbering = DocxNumberingRef(1);
      expect(saved(doc), kept);
      expect(isNumberingLoaded(doc), isTrue);
    });

    test('a change is written from the model, and its revert is as read', () {
      final DocxDocument doc = open();
      final ChangeSet set = changeLogOf(doc).transaction(
        () => doc.numbering.addInstance(doc.numbering.abstractNumberings.first),
      );
      final String changed = saved(doc);
      expect(changed, contains('w:numId="2"'));
      expect(changed, isNot(contains('<!-- kept -->')));

      changeLogOf(doc).revertSet(set);
      expect(saved(doc), kept);

      changeLogOf(doc).reapplySet(set);
      expect(saved(doc), changed);
    });
  });

  group('numberingNotFound (Ruling 8)', () {
    test('a numId set through the API that the document lacks warns at the '
        'paragraph', () {
      final DocxDocument doc = DocxDocument.open(docxWithNumbering());
      final int before = doc.body.blocks.whereType<DocxParagraph>().length;
      doc.body.addParagraph('a').properties.numbering = DocxNumberingRef(7);
      doc.body.addParagraph('b').properties.numbering = DocxNumberingRef(
        7,
        level: 1,
      );
      final DocxResult result = doc.save();
      final List<DocxWarning> found = result.warnings
          .where((DocxWarning w) => w.code == DocxWarningCode.numberingNotFound)
          .toList();
      expect(found, hasLength(1));
      final DocxWarning w = found.single;
      expect(w.detail, '7');
      expect(w.count, 2);
      expect(w.part, '/word/document.xml');
      expect(w.locations, <String>['body/p[$before]', 'body/p[${before + 1}]']);
      expect(w.message(), contains('belong to the list 7'));
    });

    test('numId 0, a defined numId and a read dangling numPr do not warn', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithNumbering(
          document:
              '<w:document xmlns:w="${Ns.w}"><w:body>'
              '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/>'
              '<w:numId w:val="42"/></w:numPr></w:pPr></w:p>'
              '</w:body></w:document>',
        ),
      );
      doc.body.addParagraph('a').properties.numbering = DocxNumberingRef(0);
      doc.body.addParagraph('b').properties.numbering = DocxNumberingRef(2);
      expect(
        doc.save().warnings.map((DocxWarning w) => w.code),
        isNot(contains(DocxWarningCode.numberingNotFound)),
      );
    });

    test('a list set in a document without numbering.xml warns', () {
      final DocxDocument doc = DocxDocument.open(_withoutNumbering());
      doc.body.addParagraph('a').properties.numbering = DocxNumberingRef(1);
      final DocxResult result = doc.save();
      expect(
        result.warnings.map((DocxWarning w) => w.code),
        contains(DocxWarningCode.numberingNotFound),
      );
      expect(
        readXlsxBytes(result.bytes).containsKey('word/numbering.xml'),
        isFalse,
      );
    });

    test('an instance added before the save is defined', () {
      final DocxDocument doc = DocxDocument.open(_withoutNumbering());
      final DocxNumberingInstance list = _addList(doc);
      doc.body.addParagraph('a').properties.numbering = list.ref();
      expect(
        doc.save().warnings.map((DocxWarning w) => w.code),
        isNot(contains(DocxWarningCode.numberingNotFound)),
      );
    });

    test('a broken numbering part reports nothing and saves', () {
      final Uint8List input = docxWithNumbering(numbering: '<w:numbering');
      final DocxDocument doc = DocxDocument.open(input);
      doc.body.addParagraph('a').properties.numbering = DocxNumberingRef(9);
      final DocxResult result = doc.save();
      expect(
        result.warnings.map((DocxWarning w) => w.code),
        isNot(contains(DocxWarningCode.numberingNotFound)),
      );
      expect(
        readXlsxBytes(result.bytes)['word/numbering.xml'],
        readXlsxBytes(input)['word/numbering.xml'],
      );
    });
  });
}
