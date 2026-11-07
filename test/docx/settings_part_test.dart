// Tests the settings part: `DocxDocument.evenAndOddHeaders` reads and writes
// `w:evenAndOddHeaders` of `word/settings.xml` at its schema position, the
// part loads on the first access and is copied while the model writes what it
// read, a document without one gains it holding only that child, an even
// header or footer turns the setting on in its own edit, and a broken part
// throws a DocxReadException naming it. The packages are built in memory, so
// these tests run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, isSettingsLoaded;
import 'package:jet_office/src/opc/change_log.dart' show ChangeSet;
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../support/read_xlsx.dart';
import 'support/docx_builder.dart';
import 'support/styles_documents.dart' show readDocxText;

const String _w = 'xmlns:w="${Ns.w}"';

/// A settings part of [children] (the default `w:` root).
String _settings(String children, {String root = '<w:settings $_w>'}) =>
    '$root$children</w:settings>';

/// A document of two paragraphs, with a settings part holding [settings]
/// (none when null), related by [rels] or by a default relationship.
Uint8List _docx(
  String? settings, {
  String? rels,
  String settingsType = ContentType.wmlSettings,
}) => buildDocx(
  document:
      '<w:document $_w><w:body><w:p><w:r><w:t>One</w:t></w:r></w:p>'
      '<w:sectPr/></w:body></w:document>',
  extra: <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$contentTypesNs">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="${ContentType.wmlDocument}"/>'
      '${settings == null ? '' : '<Override PartName="/word/settings.xml" '
                'ContentType="$settingsType"/>'}'
      '</Types>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">'
      '${rels ?? (settings == null ? '' : '<Relationship Id="rId1" '
                    'Type="${RelType.settings}" Target="settings.xml"/>')}'
      '</Relationships>',
    ),
    if (settings != null) 'word/settings.xml': utf8.encode(settings),
  },
);

String _part(Uint8List docx, String name) => readDocxText(docx)[name] ?? '';

/// The names of the element children of the settings root, in order.
List<String> _children(Uint8List docx) => <String>[
  for (final RegExpMatch m in RegExp(
    r'<w:(\w+)[ />]',
  ).allMatches(_part(docx, 'word/settings.xml')))
    if (m.group(1) != 'settings') m.group(1)!,
];

void main() {
  group('reading', () {
    test('a document without a settings part reads false and loads it', () {
      final DocxDocument doc = DocxDocument.open(_docx(null));
      expect(isSettingsLoaded(doc), isFalse);
      expect(doc.evenAndOddHeaders, isFalse);
      expect(isSettingsLoaded(doc), isTrue);
    });

    test('the bare child reads true; val 1, true and on too', () {
      for (final String child in <String>[
        '<w:evenAndOddHeaders/>',
        '<w:evenAndOddHeaders w:val="1"/>',
        '<w:evenAndOddHeaders w:val="true"/>',
        '<w:evenAndOddHeaders w:val="on"/>',
      ]) {
        expect(
          DocxDocument.open(_docx(_settings(child))).evenAndOddHeaders,
          isTrue,
          reason: child,
        );
      }
    });

    test('val 0, off and false, and a value it cannot parse, read false', () {
      for (final String child in <String>[
        '<w:evenAndOddHeaders w:val="0"/>',
        '<w:evenAndOddHeaders w:val="off"/>',
        '<w:evenAndOddHeaders w:val="false"/>',
        '<w:evenAndOddHeaders w:val="maybe"/>',
      ]) {
        expect(
          DocxDocument.open(_docx(_settings(child))).evenAndOddHeaders,
          isFalse,
          reason: child,
        );
      }
    });

    test('the child twice reads false', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(_settings('<w:evenAndOddHeaders/><w:evenAndOddHeaders/>')),
      );
      expect(doc.evenAndOddHeaders, isFalse);
    });

    test('a settings part of the generic XML type is found', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          _settings('<w:evenAndOddHeaders/>'),
          settingsType: ContentType.xml,
        ),
      );
      expect(doc.evenAndOddHeaders, isTrue);
    });
  });

  group('setting', () {
    test('true writes the child in schema order among the others', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          _settings(
            '<w:zoom w:percent="100"/><w:defaultTabStop w:val="720"/>'
            '<w:bookFoldPrinting/><w:compat><w:x/></w:compat>'
            '<w14:future xmlns:w14="urn:w14"/>',
          ),
        ),
      );
      doc.evenAndOddHeaders = true;
      expect(doc.evenAndOddHeaders, isTrue);
      final Uint8List out = doc.save().bytes;
      expect(
        _part(out, 'word/settings.xml'),
        contains(
          '<w:defaultTabStop w:val="720"/><w:evenAndOddHeaders/>'
          '<w:bookFoldPrinting/><w:compat><w:x/></w:compat>'
          '<w14:future xmlns:w14="urn:w14"/>',
        ),
      );
      expect(DocxDocument.open(out).evenAndOddHeaders, isTrue);
    });

    test('true replaces a child read with val 0', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(_settings('<w:evenAndOddHeaders w:val="0"/>')),
      );
      doc.evenAndOddHeaders = true;
      expect(_children(doc.save().bytes), <String>['evenAndOddHeaders']);
      expect(
        _part(doc.save().bytes, 'word/settings.xml'),
        contains('<w:evenAndOddHeaders/>'),
      );
    });

    test('true replaces both of a child read twice', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          _settings(
            '<w:zoom/><w:evenAndOddHeaders/><w:evenAndOddHeaders w:val="0"/>',
          ),
        ),
      );
      doc.evenAndOddHeaders = true;
      final Uint8List out = doc.save().bytes;
      expect(_children(out), <String>['zoom', 'evenAndOddHeaders']);
      expect(DocxDocument.open(out).evenAndOddHeaders, isTrue);
    });

    test('false removes the child and leaves the others', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(_settings('<w:zoom/><w:evenAndOddHeaders/><w:compat/>')),
      );
      doc.evenAndOddHeaders = false;
      expect(doc.evenAndOddHeaders, isFalse);
      expect(_children(doc.save().bytes), <String>['zoom', 'compat']);
    });

    test('a value it already reads changes nothing', () {
      for (final (String, bool) c in <(String, bool)>[
        ('<w:evenAndOddHeaders w:val="0"/>', false),
        ('<w:evenAndOddHeaders/><w:evenAndOddHeaders/>', false),
        ('<w:evenAndOddHeaders/>', true),
        ('', false),
      ]) {
        final Uint8List input = _docx(_settings(c.$1));
        final DocxDocument doc = DocxDocument.open(input);
        doc.evenAndOddHeaders = c.$2;
        expect(changeLogOf(doc).hasChanges, isFalse, reason: c.$1);
        expect(comparePackages(input, doc.save().bytes), isEmpty);
      }
    });

    test('is one undoable edit, and an undone save is the input', () {
      final Uint8List input = _docx(_settings('<w:zoom/>'));
      final DocxDocument doc = DocxDocument.open(input);
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => doc.evenAndOddHeaders = true);
      expect(set.changes, hasLength(1));
      expect(doc.evenAndOddHeaders, isTrue);
      changeLogOf(doc).revertSet(set);
      expect(doc.evenAndOddHeaders, isFalse);
      expect(
        _part(doc.save().bytes, 'word/settings.xml'),
        _part(input, 'word/settings.xml'),
      );
      changeLogOf(doc).reapplySet(set);
      expect(doc.evenAndOddHeaders, isTrue);
    });

    test('a root with a prefix of its own is written with it', () {
      final DocxDocument doc = DocxDocument.open(
        _docx('<x:settings xmlns:x="${Ns.w}"><x:zoom/></x:settings>'),
      );
      doc.evenAndOddHeaders = true;
      final String text = _part(doc.save().bytes, 'word/settings.xml');
      expect(text, contains('<x:evenAndOddHeaders/>'));
      expect(DocxDocument.open(doc.save().bytes).evenAndOddHeaders, isTrue);
    });

    test(
      'a root that binds WordprocessingML only by default cannot take it',
      () {
        final Uint8List input = _docx(
          '<settings xmlns="${Ns.w}"><zoom/></settings>',
        );
        final DocxDocument doc = DocxDocument.open(input);
        expect(
          () => doc.evenAndOddHeaders = true,
          throwsA(
            isA<DocxReadException>().having(
              (DocxReadException e) => e.part,
              'part',
              '/word/settings.xml',
            ),
          ),
        );
        expect(changeLogOf(doc).hasChanges, isFalse);
        expect(
          _part(doc.save().bytes, 'word/settings.xml'),
          _part(input, 'word/settings.xml'),
        );
      },
    );
    test('removing the child needs no prefix', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<settings xmlns="${Ns.w}"><evenAndOddHeaders/><zoom/></settings>',
        ),
      );
      expect(doc.evenAndOddHeaders, isTrue);
      doc.evenAndOddHeaders = false;
      expect(doc.evenAndOddHeaders, isFalse);
      final String part = _part(doc.save().bytes, 'word/settings.xml');
      expect(part, isNot(contains('evenAndOddHeaders')));
      expect(part, contains('zoom'));
    });
  });

  group('the part in the package', () {
    test('a read that changes nothing saves the file bytes', () {
      final Uint8List input = _docx(
        '<?xml version="1.0"?>\r\n<!-- note -->'
        '${_settings('<w:zoom/>\n<w:evenAndOddHeaders w:val="0"/>')}',
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.evenAndOddHeaders, isFalse);
      expect(
        _part(doc.save().bytes, 'word/settings.xml'),
        _part(input, 'word/settings.xml'),
      );
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('a getter that does not touch even stories leaves it unloaded', () {
      final DocxDocument doc = DocxDocument.open(_docx(_settings('')));
      doc.body.addParagraph('x');
      doc.sections.first.header.addParagraph('x');
      doc.sections.first.firstHeader.addParagraph('x');
      doc.sections.first.footer;
      expect(isSettingsLoaded(doc), isFalse);
    });

    test('a document without the part gains it holding only the child', () {
      final DocxDocument doc = DocxDocument.open(_docx(null));
      doc.evenAndOddHeaders = true;
      final Uint8List out = doc.save().bytes;
      expect(
        _part(out, 'word/settings.xml'),
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:settings $_w><w:evenAndOddHeaders/></w:settings>',
      );
      expect(_part(out, 'word/settings.xml'), isNot(contains('compat')));
      expect(
        _part(out, '[Content_Types].xml'),
        contains(
          '<Override PartName="/word/settings.xml" '
          'ContentType="${ContentType.wmlSettings}"/>',
        ),
      );
      expect(
        _part(out, 'word/_rels/document.xml.rels'),
        contains('Type="${RelType.settings}" Target="settings.xml"'),
      );
      expect(DocxDocument.open(out).evenAndOddHeaders, isTrue);
      // The second save gives the same bytes.
      expect(doc.save().bytes, out);
    });

    test('set true then false on a document without the part adds none', () {
      final DocxDocument doc = DocxDocument.open(_docx(null));
      doc.evenAndOddHeaders = true;
      doc.evenAndOddHeaders = false;
      expect(
        readXlsxBytes(doc.save().bytes).containsKey('word/settings.xml'),
        isFalse,
      );
    });

    test('a broken part throws naming it, and is saved as read', () {
      final Uint8List input = _docx('<w:settings $_w><w:zoom></w:settings>');
      final DocxDocument doc = DocxDocument.open(input);
      expect(
        () => doc.evenAndOddHeaders,
        throwsA(
          isA<DocxReadException>().having(
            (DocxReadException e) => e.part,
            'part',
            '/word/settings.xml',
          ),
        ),
      );
      expect(
        () => doc.evenAndOddHeaders = true,
        throwsA(isA<DocxReadException>()),
      );
      expect(isSettingsLoaded(doc), isFalse);
      expect(
        _part(doc.save().bytes, 'word/settings.xml'),
        _part(input, 'word/settings.xml'),
      );
    });

    test('a root that is not w:settings throws naming the part', () {
      final DocxDocument doc = DocxDocument.open(_docx('<w:styles $_w/>'));
      expect(() => doc.evenAndOddHeaders, throwsA(isA<DocxReadException>()));
    });
  });

  group('an even story turns it on', () {
    test('the first content of an even header sets it in the same edit', () {
      final DocxDocument doc = DocxDocument.open(_docx(null));
      final DocxHeaderFooter even = doc.sections.first.evenHeader;
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => even.addParagraph('Even'));
      expect(doc.evenAndOddHeaders, isTrue);
      expect(_children(doc.save().bytes), <String>['evenAndOddHeaders']);
      changeLogOf(doc).revertSet(set);
      expect(doc.evenAndOddHeaders, isFalse);
      expect(even.blocks, isEmpty);
    });

    test('an even footer and an own even story set it too', () {
      final DocxDocument footer = DocxDocument.open(_docx(_settings('')));
      footer.sections.first.evenFooter.addParagraph('Even');
      expect(footer.evenAndOddHeaders, isTrue);
      final DocxDocument own = DocxDocument.open(_docx(_settings('')));
      own.sections.first.ownHeader(DocxHeaderFooterType.even);
      expect(own.evenAndOddHeaders, isTrue);
      final DocxDocument ownFooter = DocxDocument.open(_docx(_settings('')));
      ownFooter.sections.first.ownFooter(DocxHeaderFooterType.even);
      expect(ownFooter.evenAndOddHeaders, isTrue);
    });

    test('a primary or first story does not', () {
      final DocxDocument doc = DocxDocument.open(_docx(_settings('')));
      doc.sections.first.header.addParagraph('x');
      doc.sections.first.ownFooter(DocxHeaderFooterType.first);
      expect(isSettingsLoaded(doc), isFalse);
      expect(doc.evenAndOddHeaders, isFalse);
    });

    test(
      'a story of empty paragraphs has no content: the next block is first',
      () {
        final DocxDocument doc = DocxDocument.open(
          buildDocx(
            document:
                '<w:document $_w xmlns:r="${Ns.rel}"><w:body><w:p/><w:sectPr>'
                '<w:headerReference w:type="even" r:id="rId1"/></w:sectPr>'
                '</w:body></w:document>',
            extra: <String, List<int>>{
              '[Content_Types].xml': utf8.encode(
                '<Types xmlns="$contentTypesNs">'
                '<Default Extension="rels" '
                'ContentType="${ContentType.relationships}"/>'
                '<Override PartName="/word/document.xml" '
                'ContentType="${ContentType.wmlDocument}"/>'
                '<Override PartName="/word/header1.xml" '
                'ContentType="${ContentType.wmlHeader}"/></Types>',
              ),
              'word/_rels/document.xml.rels': utf8.encode(
                '<Relationships xmlns="$packageRelsNs"><Relationship '
                'Id="rId1" Type="${RelType.header}" Target="header1.xml"/>'
                '</Relationships>',
              ),
              'word/header1.xml': utf8.encode(
                '<w:hdr $_w><w:p><w:pPr><w:pStyle w:val="Header"/></w:pPr>'
                '</w:p></w:hdr>',
              ),
            },
          ),
        );
        expect(doc.evenAndOddHeaders, isFalse);
        doc.sections.first.evenHeader.addParagraph('Text');
        expect(doc.evenAndOddHeaders, isTrue);
      },
    );

    test('a second block, or a set already true, changes the setting once', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(_settings('<w:evenAndOddHeaders/>')),
      );
      final DocxHeaderFooter even = doc.sections.first.evenHeader;
      even.addParagraph('a');
      even.addParagraph('b');
      expect(doc.evenAndOddHeaders, isTrue);
      expect(_children(doc.save().bytes), <String>['evenAndOddHeaders']);
    });

    test('removing an even story turns nothing off', () {
      final DocxDocument doc = DocxDocument.open(_docx(_settings('')));
      doc.sections.first.evenHeader.addParagraph('Even');
      doc.sections.first.removeHeader(DocxHeaderFooterType.even);
      expect(doc.evenAndOddHeaders, isTrue);
    });

    test(
      'a broken settings part makes the edit throw, and nothing changes',
      () {
        final Uint8List input = _docx('<w:settings $_w><w:zoom></w:settings>');
        final DocxDocument doc = DocxDocument.open(input);
        final DocxHeaderFooter even = doc.sections.first.evenHeader;
        expect(
          () => even.addParagraph('Even'),
          throwsA(
            isA<DocxReadException>().having(
              (DocxReadException e) => e.part,
              'part',
              '/word/settings.xml',
            ),
          ),
        );
        expect(
          () => doc.sections.first.ownHeader(DocxHeaderFooterType.even),
          throwsA(isA<DocxReadException>()),
        );
        expect(changeLogOf(doc).hasChanges, isFalse);
        expect(even.blocks, isEmpty);
        final Uint8List out = doc.save().bytes;
        expect(
          _part(out, 'word/settings.xml'),
          _part(input, 'word/settings.xml'),
        );
        expect(
          readXlsxBytes(out).keys.where((String k) => k.contains('header')),
          isEmpty,
        );
      },
    );

    test('a transaction that fails leaves the setting unset and no part', () {
      final Uint8List input = _docx(null);
      final DocxDocument doc = DocxDocument.open(input);
      expect(
        () => changeLogOf(doc).transaction(() {
          doc.sections.first.evenHeader.addParagraph('Even');
          throw StateError('fail');
        }),
        throwsStateError,
      );
      expect(doc.evenAndOddHeaders, isFalse);
      final Uint8List out = doc.save().bytes;
      expect(comparePackages(input, out), isEmpty);
    });
  });
}
