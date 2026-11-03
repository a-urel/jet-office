// Tests the semantic comparer for DOCX packages and WordprocessingML parts
// (phase 4, D1): the yardstick the round-trip tests use to say that opening
// and saving a document keeps every part. They build small ZIPs in memory
// and read no files, so they run on the web as well as the VM.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../xlsx/read/support/zip_builder.dart';

const String _w =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

const String _sml = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

const String _types =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
    '</Types>';

const String _rootRels =
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="$_rel/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

/// A DOCX package of [parts] besides the content types and the root rels.
Uint8List _docx(Map<String, String> parts) => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(_types),
  '_rels/.rels': utf8.encode(_rootRels),
  for (final MapEntry<String, String> p in parts.entries)
    p.key: utf8.encode(p.value),
});

/// A main document whose body is [body], in the namespace prefix [p].
String _document(String body, {String p = 'w'}) =>
    '<$p:document xmlns:$p="$_w" xmlns:r="$_rel"><$p:body>$body</$p:body>'
    '</$p:document>';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test('compareXmlParts reports a changed w:t and accepts a prefix change', () {
    final Uint8List e = _bytes(
      _document('<w:p><w:r><w:t>Hello</w:t></w:r></w:p>'),
    );
    final Uint8List prefixed = _bytes(
      _document('<x:p><x:r><x:t>Hello</x:t></x:r></x:p>', p: 'x'),
    );
    expect(compareXmlParts('word/document.xml', e, prefixed), isEmpty);

    final Uint8List changed = _bytes(
      _document('<w:p><w:r><w:t>Hallo</w:t></w:r></w:p>'),
    );
    final List<String> diff = compareXmlParts('word/document.xml', e, changed);
    expect(diff, hasLength(1));
    expect(
      diff.single,
      allOf(
        startsWith('word/document.xml: '),
        contains('/document/body/p/r/t'),
        contains('"Hello" vs "Hallo"'),
      ),
    );
  });

  test('compareXmlParts keeps the whitespace of w:t, w:instrText and '
      'w:delText', () {
    for (final String name in <String>['t', 'instrText', 'delText']) {
      final List<String> diff = compareXmlParts(
        'word/document.xml',
        _bytes(_document('<w:p><w:r><w:$name> </w:$name></w:r></w:p>')),
        _bytes(_document('<w:p><w:r><w:$name></w:$name></w:r></w:p>')),
      );
      expect(diff, hasLength(1), reason: name);
    }
    // Whitespace between elements is still layout.
    expect(
      compareXmlParts(
        'word/document.xml',
        _bytes(_document('\n  <w:p>\n    <w:r><w:t>a</w:t></w:r>\n  </w:p>\n')),
        _bytes(_document('<w:p><w:r><w:t>a</w:t></w:r></w:p>')),
      ),
      isEmpty,
    );
  });

  test('compareXmlParts compares relationship ids literally', () {
    final List<String> diff = compareXmlParts(
      'word/document.xml',
      _bytes(
        _document('<w:sectPr><w:headerReference r:id="rId1"/></w:sectPr>'),
      ),
      _bytes(
        _document('<w:sectPr><w:headerReference r:id="rId2"/></w:sectPr>'),
      ),
    );
    expect(diff, hasLength(1));
    expect(diff.single, contains('attribute id "rId1" vs "rId2"'));
  });

  test('compareXmlParts reports a part that is not XML, not throws', () {
    final Uint8List good = _bytes(_document(''));
    final Uint8List bad = Uint8List.fromList(<int>[0x3c, 0x61, 0xff, 0x3e]);
    expect(compareXmlParts('word/document.xml', good, bad), hasLength(1));
    expect(compareXmlParts('word/document.xml', bad, good), hasLength(1));
  });

  test('equal DOCX packages with different prefixes compare equal', () {
    final Uint8List e = _docx(<String, String>{
      'word/document.xml': _document('<w:p><w:r><w:t>Hello</w:t></w:r></w:p>'),
    });
    final Uint8List a = _docx(<String, String>{
      'word/document.xml': _document(
        '<ns0:p><ns0:r><ns0:t>Hello</ns0:t></ns0:r></ns0:p>',
        p: 'ns0',
      ),
    });
    expect(comparePackages(e, a), isEmpty);
  });

  test('a changed w:t is reported with the part and path', () {
    final Uint8List e = _docx(<String, String>{
      'word/document.xml': _document(
        '<w:p><w:r><w:t xml:space="preserve">a b </w:t></w:r></w:p>',
      ),
    });
    final Uint8List a = _docx(<String, String>{
      'word/document.xml': _document(
        '<w:p><w:r><w:t xml:space="preserve">a b</w:t></w:r></w:p>',
      ),
    });
    final List<String> diff = comparePackages(e, a);
    expect(diff, hasLength(1));
    expect(
      diff.single,
      allOf(
        startsWith('word/document.xml: '),
        contains('/document/body/p/r/t'),
        contains('"a b " vs "a b"'),
      ),
    );
  });

  test('a dropped xml:space on w:t is reported', () {
    // Unlike SpreadsheetML's t, the attribute compares as written even when
    // the text has no spaces around it (plan Ruling 4).
    for (final String text in <String>['ab', ' ab']) {
      final Uint8List e = _docx(<String, String>{
        'word/document.xml': _document(
          '<w:p><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>',
        ),
      });
      final Uint8List a = _docx(<String, String>{
        'word/document.xml': _document(
          '<w:p><w:r><w:t>$text</w:t></w:r></w:p>',
        ),
      });
      final List<String> diff = comparePackages(e, a);
      expect(diff, hasLength(1), reason: text);
      expect(
        diff.single,
        allOf(
          contains('/document/body/p/r/t'),
          contains('attribute space "preserve" vs missing'),
        ),
      );
    }
  });

  test('an r:id renumbered with the same target compares equal', () {
    String document(String first, String second) => _document(
      '<w:p><w:hyperlink r:id="$first"><w:r><w:t>x</w:t></w:r></w:hyperlink>'
      '</w:p><w:sectPr><w:headerReference w:type="default" r:id="$second"/>'
      '</w:sectPr>',
    );
    String rels(String hyperlink, String header) =>
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="$hyperlink" Type="$_rel/hyperlink" Target="https://example.com/" TargetMode="External"/>'
        '<Relationship Id="$header" Type="$_rel/header" Target="header1.xml"/>'
        '</Relationships>';
    String header(String id) =>
        '<w:hdr xmlns:w="$_w" xmlns:r="$_rel"><w:p>'
        '<w:hyperlink r:id="$id"><w:r><w:t>h</w:t></w:r></w:hyperlink>'
        '</w:p></w:hdr>';
    const String headerRels =
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/hyperlink" Target="https://example.com/h" TargetMode="External"/>'
        '</Relationships>';
    const String headerRelsRenumbered =
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId7" Type="$_rel/hyperlink" Target="https://example.com/h" TargetMode="External"/>'
        '</Relationships>';
    final Uint8List e = _docx(<String, String>{
      'word/document.xml': document('rId1', 'rId2'),
      'word/_rels/document.xml.rels': rels('rId1', 'rId2'),
      'word/header1.xml': header('rId1'),
      'word/_rels/header1.xml.rels': headerRels,
    });
    final Uint8List a = _docx(<String, String>{
      'word/document.xml': document('rId9', 'rId3'),
      'word/_rels/document.xml.rels': rels('rId9', 'rId3'),
      'word/header1.xml': header('rId7'),
      'word/_rels/header1.xml.rels': headerRelsRenumbered,
    });
    expect(comparePackages(e, a), isEmpty);

    // The same ids pointing elsewhere are a difference.
    final Uint8List swapped = _docx(<String, String>{
      'word/document.xml': document('rId2', 'rId1'),
      'word/_rels/document.xml.rels': rels('rId1', 'rId2'),
      'word/header1.xml': header('rId1'),
      'word/_rels/header1.xml.rels': headerRels,
    });
    final List<String> diff = comparePackages(e, swapped);
    expect(diff, isNotEmpty);
    expect(diff, everyElement(startsWith('word/document.xml: ')));
  });

  test('an added part is reported', () {
    final Uint8List e = _docx(<String, String>{
      'word/document.xml': _document(''),
    });
    final Uint8List a = _docx(<String, String>{
      'word/document.xml': _document(''),
      'word/header1.xml': '<w:hdr xmlns:w="$_w"/>',
    });
    final List<String> diff = comparePackages(e, a);
    expect(diff, hasLength(1));
    expect(diff.single, 'word/header1.xml: added to the actual package');
  });

  test('a DOCX has no SpreadsheetML rules applied', () {
    // Elements in the SpreadsheetML namespace inside a DOCX (a custom XML
    // part) compare by the plain XML rules: t="n" is not dropped and
    // xml:space on a t is kept.
    Uint8List pkg(String custom) => _docx(<String, String>{
      'word/document.xml': _document(''),
      'customXml/item1.xml': custom,
    });
    final List<String> diff = comparePackages(
      pkg(
        '<x xmlns="$_sml"><c t="n"><v>1</v></c>'
        '<t xml:space="preserve">a</t></x>',
      ),
      pkg('<x xmlns="$_sml"><c><v>1</v></c><t>a</t></x>'),
    );
    expect(diff, hasLength(2), reason: '$diff');
    expect(diff, everyElement(startsWith('customXml/item1.xml: ')));

    // The same package marked as a workbook would compare equal.
    expect(
      compareXml(
        'customXml/item1.xml',
        '<x xmlns="$_sml"><c t="n"><v>1</v></c>'
            '<t xml:space="preserve">a</t></x>',
        '<x xmlns="$_sml"><c><v>1</v></c><t>a</t></x>',
      ),
      isEmpty,
    );
  });
  test('a package is a DOCX by its main part\'s content type', () {
    // The main part has an unusual name; its Override makes it
    // WordprocessingML, so the SpreadsheetML t rule does not apply.
    Uint8List pkg(
      String t, {
      String mainType = 'wordprocessingml',
    }) => buildZip(<String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/main.bin" ContentType="application/vnd.openxmlformats-officedocument.$mainType.document.main+xml"/>'
        '</Types>',
      ),
      '_rels/.rels': utf8.encode(
        _rootRels.replaceFirst('word/document.xml', '/main.bin'),
      ),
      'main.bin': utf8.encode(_document('')),
      'custom.xml': utf8.encode('<x xmlns="$_sml">$t</x>'),
    });
    final Uint8List e = pkg('<t xml:space="preserve">a</t>');
    final List<String> diff = comparePackages(e, pkg('<t>a</t>'));
    expect(diff, hasLength(1), reason: '$diff');
    expect(diff.single, startsWith('custom.xml: '));

    final List<String> mixed = comparePackages(
      e,
      pkg('<t xml:space="preserve">a</t>', mainType: 'spreadsheetml'),
    );
    expect(
      mixed,
      contains(
        'package: the main part is WordprocessingML in the expected '
        'package only',
      ),
    );
  });
}
