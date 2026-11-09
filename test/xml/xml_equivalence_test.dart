import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/xml/xml_equivalence.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

String? _diff(String a, String b) => xmlDifference(_b(a), _b(b));

void main() {
  const String c = 'http://example.com/c';

  test('equal with different prefixes for the same URI', () {
    expect(
      _diff(
        '<a:x xmlns:a="$c"><a:y v="1"/></a:x>',
        '<b:x xmlns:b="$c"><b:y v="1"/></b:x>',
      ),
      isNull,
    );
  });

  test('equal with and without declaration, whitespace and moved xmlns', () {
    expect(
      _diff(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
            '<x xmlns="$c" xmlns:r="urn:r">\r\n  <y a="1" b="2"/>\r\n  <!-- c -->'
            '<z/>\r\n</x>',
        '<x xmlns="$c"><y b="2" a="1" xmlns:r="urn:r"/><z/></x>',
      ),
      isNull,
    );
  });

  test('CDATA counts as text', () {
    expect(_diff('<x>a&amp;b</x>', '<x><![CDATA[a&b]]></x>'), isNull);
  });

  test('differs on attribute value with the element path', () {
    expect(
      _diff(
        '<a><b><gapWidth val="219"/></b></a>',
        '<a><b><gapWidth val="150"/></b></a>',
      ),
      '/a/b/gapWidth: attribute val 219 vs 150',
    );
  });

  test('differs on a missing attribute', () {
    expect(_diff('<a x="1"/>', '<a/>'), contains('attribute x'));
    expect(_diff('<a/>', '<a x="1"/>'), contains('attribute x'));
  });

  test('differs on child order', () {
    expect(_diff('<a><b/><c/></a>', '<a><c/><b/></a>'), contains('/a'));
  });

  test('differs on child count', () {
    expect(_diff('<a><b/></a>', '<a><b/><b/></a>'), isNotNull);
    expect(_diff('<a><b/><b/></a>', '<a><b/></a>'), isNotNull);
  });

  test('differs on leaf text exactly', () {
    expect(_diff('<a><v> a</v></a>', '<a><v>a</v></a>'), contains('/a/v'));
  });

  test('whitespace that is the whole content of a leaf is significant', () {
    expect(_diff('<a><t> </t></a>', '<a><t/></a>'), contains('/a/t'));
    expect(_diff('<a><t> </t></a>', '<a><t>  </t></a>'), contains('/a/t'));
    expect(_diff('<a><t> </t></a>', '<a><t> </t></a>'), isNull);
    expect(_diff('<a><t>\n</t></a>', '<a><t/></a>'), isNotNull);
  });

  test('whitespace between elements is ignored', () {
    expect(_diff('<a>\r\n  <b/>\r\n  <c/>\r\n</a>', '<a><b/><c/></a>'), isNull);
    expect(_diff('<a> <b/> </a>', '<a><b/></a>'), isNull);
  });

  test('text against a child element differs', () {
    expect(_diff('<a>x</a>', '<a><b/></a>'), isNotNull);
    expect(_diff('<a><b/></a>', '<a>x</a>'), isNotNull);
  });

  test('content after the root differs', () {
    expect(_diff('<a/>', '<a/><b/>'), isNotNull);
    expect(_diff('<a/><b/>', '<a/>'), isNotNull);
    expect(_diff('<a/>', '<a/>x'), isNotNull);
  });

  test('differs on namespace URI with the same prefix', () {
    expect(
      _diff('<p:x xmlns:p="$c"/>', '<p:x xmlns:p="urn:other"/>'),
      isNotNull,
    );
  });

  test('attribute namespaces are compared by URI', () {
    expect(
      _diff('<x xmlns:p="$c" p:k="1"/>', '<x xmlns:q="$c" q:k="1"/>'),
      isNull,
    );
    expect(_diff('<x xmlns:p="$c" p:k="1"/>', '<x k="1"/>'), isNotNull);
  });

  test('malformed input is a difference, never a throw', () {
    expect(_diff('<a>', '<a/>'), startsWith('a: unreadable: '));
    expect(_diff('<a><b/></a>', '<a><b></a>'), startsWith('b: unreadable: '));
    expect(
      xmlDifference(Uint8List(0), _b('<a/>')),
      startsWith('a: unreadable: '),
    );
  });

  test('depth beyond the reader limit is a difference', () {
    final String deep = '<a>' * 300 + '</a>' * 300;
    expect(_diff(deep, deep), isNotNull);
  });
}
