import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/xml/xml_escape.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

void _drain(String xml, {int maxDepth = 256}) {
  final XmlPullReader r = XmlPullReader(xml, maxDepth: maxDepth);
  while (r.next()) {
    if (r.eventType == XmlEventType.endDocument) {
      break;
    }
  }
}

/// Reads every event and every text, so lazy decoding is exercised too.
void _drainAll(String xml) {
  final XmlPullReader r = XmlPullReader(xml);
  while (r.next()) {
    r.text;
    r.localName;
    r.namespaceUri;
    if (r.eventType == XmlEventType.endDocument) {
      break;
    }
  }
}

Matcher _throwsKind(XmlParseKind kind) => throwsA(
  isA<XmlParseException>().having(
    (XmlParseException e) => e.kind,
    'kind',
    kind,
  ),
);

String _textOf(String body) {
  final XmlPullReader r = XmlPullReader('<a>$body</a>');
  r.nextTag();
  r.next();
  return r.text;
}

void main() {
  group('reading', () {
    test('reads elements, attributes and text with namespaces', () {
      final XmlPullReader r = XmlPullReader(
        '<x:a xmlns:x="urn:m" k="1&amp;2"><x:b>t&lt;</x:b></x:a>',
      );
      expect(r.nextTag(), isTrue);
      expect(
        (r.localName, r.namespaceUri, r.getAttribute('k')),
        ('a', 'urn:m', '1&2'),
      );
      r.nextTag();
      r.next();
      expect(r.text, 't<');
    });

    test('resolves a prefixed attribute by namespace', () {
      final XmlPullReader r = XmlPullReader(
        '<a xmlns:r="urn:r" r:id="7" id="8"/>',
      );
      r.nextTag();
      expect(r.getAttribute('id', namespaceUri: 'urn:r'), '7');
      expect(r.getAttribute('id'), '7');
      expect(r.getAttribute('id', namespaceUri: ''), '8');
      expect(r.getAttribute('nope'), isNull);
    });

    test('reports empty elements, depth and the matching end event', () {
      final XmlPullReader r = XmlPullReader('<a><b/></a>');
      r.nextTag();
      expect((r.depth, r.isEmptyElement), (1, false));
      r.nextTag();
      expect((r.depth, r.isEmptyElement), (2, true));
      r.next();
      expect((r.eventType, r.depth), (XmlEventType.endElement, 1));
    });

    test('reads CDATA, comments and the XML declaration', () {
      final XmlPullReader r = XmlPullReader(
        '<?xml version="1.0"?><!--c--><a><![CDATA[<x>]]></a>',
      );
      r.next();
      expect(r.eventType, XmlEventType.xmlDeclaration);
      r.next();
      expect((r.eventType, r.text), (XmlEventType.comment, 'c'));
      r.next();
      r.next();
      expect((r.eventType, r.text), (XmlEventType.cdata, '<x>'));
    });

    test('skip passes a whole subtree', () {
      final XmlPullReader r = XmlPullReader('<a><b><c/>t</b><d/></a>');
      r.nextTag();
      r.nextTag();
      expect(r.localName, 'b');
      r.skip();
      r.nextTag();
      expect(r.localName, 'd');
    });

    test('skips a UTF-8 BOM in a string', () {
      final XmlPullReader r = XmlPullReader('﻿<a/>');
      expect(r.nextTag(), isTrue);
      expect(r.localName, 'a');
    });

    test('normalizes literal line endings, with or without an entity', () {
      expect(_textOf('x\r\ny'), 'x\ny');
      expect(_textOf('x\ry'), 'x\ny');
      expect(_textOf('a\r\nb&amp;\rc'), 'a\nb&\nc');
    });

    test('keeps a CR written as a character reference', () {
      expect(_textOf('x&#13;y'), 'x\ry');
      expect(_textOf('a&#13;\nb'), 'a\r\nb');
    });

    test('normalizes line endings in attribute values the same way', () {
      XmlPullReader r = XmlPullReader('<a k="x\r\ny"/>');
      r.nextTag();
      expect(r.getAttribute('k'), 'x\ny');
      r = XmlPullReader('<a k="x&#13;y"/>');
      r.nextTag();
      expect(r.getAttribute('k'), 'x\ry');
    });

    test('normalizes CR in CDATA', () {
      final XmlPullReader r = XmlPullReader('<a><![CDATA[x\r\ny]]></a>');
      r.nextTag();
      r.next();
      expect(r.text, 'x\ny');
    });

    test('round-trips CR through the writer escaping', () {
      for (final String v in <String>['a\r\nb', 'a\rb', '\r', 'a\nb&\r<']) {
        expect(_textOf(escapeXmlText(v)), v);
        final XmlPullReader r = XmlPullReader(
          '<a k="${escapeXmlAttribute(v)}"/>',
        );
        r.nextTag();
        expect(r.getAttribute('k'), v);
      }
    });
  });

  group('DOCTYPE', () {
    test('refuses a DOCTYPE', () {
      expect(
        () => _drain('<!DOCTYPE a [<!ENTITY e "x">]><a/>'),
        _throwsKind(XmlParseKind.doctype),
      );
    });

    test('refuses a DOCTYPE after a declaration', () {
      expect(
        () => _drain('<?xml version="1.0"?><!DOCTYPE a><a/>'),
        _throwsKind(XmlParseKind.doctype),
      );
    });
  });

  group('depth', () {
    test('refuses depth above maxDepth', () {
      final String deep = '${'<a>' * 5}${'</a>' * 5}';
      expect(
        () => _drain(deep, maxDepth: 4),
        _throwsKind(XmlParseKind.tooDeep),
      );
      expect(() => _drain(deep, maxDepth: 5), returnsNormally);
    });

    test('counts empty elements as depth too', () {
      expect(
        () => _drain('<a><b/></a>', maxDepth: 1),
        _throwsKind(XmlParseKind.tooDeep),
      );
    });

    test('a very deep document is refused, not a stack problem', () {
      final String deep = '<a>' * 100000;
      expect(() => _drain(deep), _throwsKind(XmlParseKind.tooDeep));
    });
  });

  group('fromBytes', () {
    test('reads UTF-8 and skips its BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('<a>é</a>'),
      ]);
      final XmlPullReader r = XmlPullReader.fromBytes(bytes);
      r.nextTag();
      r.next();
      expect(r.text, 'é');
    });

    test('refuses a UTF-16 BOM', () {
      for (final List<int> bom in <List<int>>[
        <int>[0xFE, 0xFF],
        <int>[0xFF, 0xFE],
      ]) {
        expect(
          () =>
              XmlPullReader.fromBytes(Uint8List.fromList(<int>[...bom, 60, 0])),
          _throwsKind(XmlParseKind.encoding),
        );
      }
    });

    test('refuses a declared encoding other than UTF-8', () {
      for (final String decl in <String>[
        '<?xml version="1.0" encoding="ISO-8859-1"?>',
        '<?xml version="1.0" encoding="utf-16"?>',
        "<?xml version='1.0' encoding='windows-1252'?>",
        '<?xml version="1.0" encoding = "UTF-8x" standalone="yes"?>',
      ]) {
        expect(
          () => XmlPullReader.fromBytes(
            Uint8List.fromList(utf8.encode('$decl<a/>')),
          ),
          _throwsKind(XmlParseKind.encoding),
          reason: decl,
        );
      }
    });

    test('accepts UTF-8 in any case and a declaration without encoding', () {
      for (final String decl in <String>[
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<?xml version="1.0" encoding="utf-8" standalone="yes"?>',
        "<?xml version='1.0' encoding='Utf-8'?>",
        '<?xml version="1.0"?>',
      ]) {
        final XmlPullReader r = XmlPullReader.fromBytes(
          Uint8List.fromList(utf8.encode('$decl<a/>')),
        );
        expect(r.nextTag(), isTrue, reason: decl);
      }
    });

    test('invalid UTF-8 is an encoding error', () {
      expect(
        () => XmlPullReader.fromBytes(
          Uint8List.fromList(<int>[...utf8.encode('<a>'), 0xC3, 0x28]),
        ),
        _throwsKind(XmlParseKind.encoding),
      );
    });
  });

  group('entities', () {
    test('decodes the predefined and numeric references', () {
      expect(
        _textOf('&lt;&gt;&amp;&quot;&apos;&#65;&#x42;&#X43;'),
        '<>&"\'ABC',
      );
      expect(_textOf('&#x1F600;'), '\u{1F600}');
    });

    test('decodes a reference to a C0 control', () {
      expect(_textOf('&#1;'), '\u0001');
    });

    test('refuses what cannot be decoded as malformed', () {
      for (final String ref in <String>[
        '&bogus;',
        '&#xZZ;',
        '&#;',
        '&#x;',
        '&#-1;',
        '&#+1;',
        '&# 1;',
        '&#0;',
        '&#x0;',
        '&#xD800;',
        '&#xDFFF;',
        '&#x110000;',
        '&#99999999999999999999999999;',
        '&#x${'F' * 5000};',
        '&;',
      ]) {
        expect(
          () => _textOf(ref),
          _throwsKind(XmlParseKind.malformed),
          reason: ref,
        );
      }
    });

    test('refuses a bad reference in an attribute', () {
      expect(
        () => XmlPullReader('<a k="&#0;"/>').nextTag(),
        _throwsKind(XmlParseKind.malformed),
      );
    });
  });

  group('malformed input', () {
    test('truncated and broken documents throw XmlParseException', () {
      for (final String xml in <String>[
        '<',
        '<a',
        '<a ',
        '<a b',
        '<a b=',
        '<a b="1',
        '<a b=1/>',
        '<a b="1"',
        '<a b="1" /',
        '<a/',
        '<a><!--',
        '<a><![CDATA[x',
        '<a><?pi',
        '<a>&amp',
        '<a>&',
        '<a></',
        '<a></a',
        '<a></b>',
        '</a>',
        '<a><',
        '<a><!',
        '<a><!x>',
        '<>',
        '<a><b></a>',
        '<a>',
        '<a><b>',
        '<a b="&#xD800;"/>',
        '<a>&#x110000;</a>',
        '<1/>',
        '<a "/>',
      ]) {
        expect(
          () => _drainAll(xml),
          _throwsKind(XmlParseKind.malformed),
          reason: xml,
        );
      }
    });

    test('carries the offset of the failure', () {
      try {
        _drain('<a></b>');
        fail('should throw');
      } on XmlParseException catch (e) {
        expect(e.offset, greaterThan(0));
        expect(e.message, contains('Mismatched'));
        expect(e.toString(), contains('XmlParseException'));
      }
    });

    test('never throws anything else on mutated documents', () {
      const String base =
          '<?xml version="1.0"?><a xmlns:x="urn:x" k="v&amp;"><x:b>t&#65;'
          '<![CDATA[c]]></x:b><!--c--><d/></a>';
      for (int i = 0; i <= base.length; i++) {
        for (final String cut in <String>[
          base.substring(0, i),
          base.substring(i),
          base.replaceRange(i == base.length ? i - 1 : i, i, '&'),
        ]) {
          try {
            _drainAll(cut);
          } on XmlParseException {
            // expected
          }
        }
      }
    });
  });
}
