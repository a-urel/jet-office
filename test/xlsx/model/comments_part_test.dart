import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/model/comments_part.dart';
import 'package:jet_office/src/xlsx/model/vml_part.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';

const String _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

CommentsPart? _read(
  String xml, {
  List<String>? warned,
  XlsxReadLimits limits = const XlsxReadLimits(),
}) => CommentsPart.read(
  XmlPullReader(xml),
  warn: (String detail) => warned?.add(detail),
  limits: limits,
  part: 'xl/comments1.xml',
);

String _text(CommentsPart part) =>
    utf8.decode(part.encode().expand((Uint8List c) => c).toList());

void main() {
  group('CommentsPart', () {
    test('reads authors, entries and trailing children', () {
      const String xml =
          '<comments xmlns="$_ns"><authors><author>A</author>'
          '<author>B &amp; C</author></authors><commentList>'
          '<comment ref="B2" authorId="1"><text><t>Hi</t></text></comment>'
          '</commentList><extLst><ext uri="u"/></extLst></comments>';
      final CommentsPart part = _read(xml)!;
      expect(part.authors, <String>['A', 'B & C']);
      expect(part.entries, hasLength(1));
      final CommentEntry e = part.entries.single;
      expect((e.row, e.column, e.author), (1, 1, 'B & C'));
      expect(e.text.runs.single.text, 'Hi');
      expect(e.text.runs.single.font, isNull);
      expect(e.source, isA<OpaqueXml>());
      expect(part.trailing.single.localName, 'extLst');
      expect(_text(part), contains('<author>B &amp; C</author>'));
      expect(_text(part), contains('<ext uri="u"/>'));
    });

    test('an author holding a character XML forbids encodes scrubbed', () {
      // Feature fuzz, seed 30 case 354 of the long run: `&#1;` in an author
      // made encode throw when a structural edit's scan opened the part.
      const String xml =
          '<comments xmlns="$_ns"><authors><author>A&#1;B</author></authors>'
          '<commentList/></comments>';
      final CommentsPart part = _read(xml)!;
      expect(_text(part), contains('<author>AB</author>'));
    });

    test("encodes the fixture's comments and VML part as written", () {
      final Map<String, String> parts = readXlsx(
        allFixtures().firstWhere((Fixture f) => f.name == 'm4_notes').build(),
      );
      expect(
        _text(_read(parts['xl/comments1.xml']!)!),
        parts['xl/comments1.xml'],
      );
      expect(
        _vmlText(VmlPart.read(parts['xl/drawings/vmlDrawing1.vml']!)!),
        parts['xl/drawings/vmlDrawing1.vml'],
      );
    });

    test('is null for a root that is not SpreadsheetML comments', () {
      expect(_read('<comments xmlns="urn:other"/>'), isNull);
      expect(_read('<worksheet xmlns="$_ns"/>'), isNull);
    });

    test('an unreadable or repeated ref is kept with no cell', () {
      final List<String> warned = <String>[];
      final CommentsPart part = _read(
        '<comments xmlns="$_ns"><authors><author>A</author></authors>'
        '<commentList>'
        '<comment ref="A1" authorId="0"><text><t>one</t></text></comment>'
        '<comment ref="A1" authorId="0"><text><t>two</t></text></comment>'
        '<comment ref="zz" authorId="0"><text><t>three</t></text></comment>'
        '<comment authorId="0"><text><t>four</t></text></comment>'
        '</commentList></comments>',
        warned: warned,
      )!;
      expect(part.entries, hasLength(4));
      expect(part.entries.map((CommentEntry e) => e.row), <int?>[
        0,
        null,
        null,
        null,
      ]);
      expect(warned, everyElement('comment'));
      expect(warned, hasLength(3));
    });

    test('a bad authorId reads author empty and warns', () {
      final List<String> warned = <String>[];
      final CommentsPart part = _read(
        '<comments xmlns="$_ns"><authors><author>A</author></authors>'
        '<commentList>'
        '<comment ref="A1" authorId="7"><text><t>x</t></text></comment>'
        '<comment ref="A2" authorId="q"><text><t>x</t></text></comment>'
        '<comment ref="A3"><text><t>x</t></text></comment>'
        '</commentList></comments>',
        warned: warned,
      )!;
      expect(part.entries.map((CommentEntry e) => e.author), <String>[
        '',
        '',
        '',
      ]);
      expect(warned, <String>['comment', 'comment', 'comment']);
    });

    test('a prefixed root reads and encodes as written', () {
      const String xml =
          '<x:comments xmlns:x="$_ns"><x:authors><x:author>A</x:author>'
          '</x:authors><x:commentList><x:comment ref="C3" authorId="0">'
          '<x:text><x:r><x:t>a</x:t></x:r><x:r><x:t>b</x:t></x:r></x:text>'
          '</x:comment></x:commentList></x:comments>';
      final CommentsPart part = _read(xml)!;
      expect(part.entries.single.text.runs.map((r) => r.text), <String>[
        'a',
        'b',
      ]);
      expect(_text(part), contains('<x:comments xmlns:x="$_ns">'));
      expect(_text(part), contains('<x:author>A</x:author>'));
    });

    test('more comments than maxMerges throws limitExceeded', () {
      expect(
        () => _read(
          '<comments xmlns="$_ns"><authors><author>A</author></authors>'
          '<commentList>'
          '<comment ref="A1" authorId="0"><text><t>x</t></text></comment>'
          '<comment ref="A2" authorId="0"><text><t>x</t></text></comment>'
          '</commentList></comments>',
          limits: const XlsxReadLimits(maxMerges: 1),
        ),
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.limitExceeded,
          ),
        ),
      );
    });
  });

  group('VmlPart', () {
    test('splits head, shapes, text after them and tail', () {
      const String source =
          '<xml xmlns:v="urn:schemas-microsoft-com:vml" '
          'xmlns:o="urn:schemas-microsoft-com:office:office" '
          'xmlns:x="urn:schemas-microsoft-com:office:excel">\n'
          '<o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="1,3"/>'
          '</o:shapelayout>\n'
          '<v:shape id="_x0000_s1025"><x:ClientData ObjectType="Note">'
          '<x:Row>4</x:Row><x:Column>2</x:Column><x:Visible/></x:ClientData>'
          '</v:shape>\n'
          '<v:shape id="_x0000_s1026"><x:ClientData ObjectType="Note">'
          '<x:Row>x</x:Row></x:ClientData></v:shape>\n'
          '<v:shape id="_x0000_s1027"><x:ClientData ObjectType="Button">'
          '<x:Row>1</x:Row><x:Column>1</x:Column></x:ClientData></v:shape>\n'
          '</xml>';
      final VmlPart part = VmlPart.read(source)!;
      expect(part.blocks, <int>{1, 3});
      expect(part.shapes, hasLength(3));
      expect(part.head, startsWith('<xml '));
      expect(part.head, endsWith('</o:shapelayout>\n'));
      final VmlShape first = part.shapes[0];
      expect(first.isNote, isTrue);
      expect((first.row, first.column, first.visible), (4, 2, true));
      expect(first.after, '\n');
      expect(part.shapes[1].isNote, isTrue);
      expect(part.shapes[1].row, isNull);
      expect(part.shapes[2].isNote, isFalse);
      expect(part.tail, '\n</xml>');
      expect(_vmlText(part), source);
    });

    test('is null when it is not well formed', () {
      expect(VmlPart.read('<xml><v:shape></xml>'), isNull);
      expect(VmlPart.read('<xml><br></xml>'), isNull);
    });

    test('a part with no shape is all head', () {
      final VmlPart part = VmlPart.read('<xml/>')!;
      expect(part.shapes, isEmpty);
      expect(_vmlText(part), '<xml/>');
      expect(part.blocks, isEmpty);
    });
  });
}

String _vmlText(VmlPart part) =>
    utf8.decode(part.encode().expand((Uint8List c) => c).toList());
