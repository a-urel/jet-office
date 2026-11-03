import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/document_part.dart';
import 'package:jet_office/src/docx/docx_package.dart';
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/inlines.dart';
import 'package:jet_office/src/docx/model/run_content.dart';
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import 'support/docx_builder.dart';

/// The namespace declarations the documents of these tests carry.
const String _decls =
    'xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}" xmlns:mc="${Ns.mc}"';

/// Reads the document whose body holds [body].
DocumentPart _read(
  String body, {
  DocxReadLimits limits = const DocxReadLimits(),
}) => _readXml(
  '<w:document $_decls><w:body>$body</w:body></w:document>',
  limits: limits,
);

/// Reads the whole document [xml].
DocumentPart _readXml(
  String xml, {
  DocxReadLimits limits = const DocxReadLimits(),
}) => DocumentPart.read(
  XmlPullReader(xml, maxDepth: limits.maxDepth),
  DocxWarningCollector(),
  '/word/document.xml',
  limits: limits,
);

/// The paragraph at [index] of [part].
DocxParagraph _p(DocumentPart part, [int index = 0]) =>
    part.blocks[index] as DocxParagraph;

/// The value of the kept attribute [qualifiedName] in [attributes], or null.
String? _attr(List<KeptAttribute> attributes, String qualifiedName) {
  for (final KeptAttribute a in attributes) {
    if (a.qualifiedName == qualifiedName) return a.value;
  }
  return null;
}

/// A prefix-free description of [part]'s model, for comparing two reads.
String _dump(DocumentPart part) {
  final StringBuffer out = StringBuffer();
  for (final DocxBlock block in part.blocks) {
    switch (block) {
      case DocxParagraph():
        out.write('p(${block.style}');
        final PropertyContainer pPr = paragraphPropertiesOf(block);
        for (final OpaqueXml k in pPr.kept) {
          out.write(' ${k.namespaceUri}|${k.localName}');
        }
        out.write(')[');
        for (final DocxInline inline in block.inlines) {
          switch (inline) {
            case DocxRun():
              out.write('r(${inline.style})');
              for (final DocxRunContent c in inline.content) {
                out.write(switch (c) {
                  DocxText(:final String text) => 't"$text"',
                  DocxTab() => 'tab',
                  DocxBreak(:final DocxBreakType type) => 'br:${type.name}',
                  DocxCarriageReturn() => 'cr',
                  DocxOpaqueRunContent() =>
                    'o:${c.namespaceUri}|${c.localName}',
                });
                out.write(',');
              }
            case DocxOpaqueInline():
              out.write(
                'oi:${inline.namespaceUri}|${inline.localName}'
                '"${inline.text}"',
              );
          }
          out.write(';');
        }
        out.write(']');
      case DocxOpaqueBlock():
        out.write('ob:${block.namespaceUri}|${block.localName}');
    }
    out.write('\n');
  }
  final OpaqueXml? sectPr = part.finalSectPr;
  out.write('sectPr:${sectPr?.namespaceUri}|${sectPr?.localName}');
  return out.toString();
}

void main() {
  test('reads paragraphs, runs, text, tabs and breaks', () {
    final DocumentPart part = _read(
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/>'
      '</w:pPr><w:r><w:rPr><w:rStyle w:val="Strong"/><w:b/><w:kern w:val="2"/></w:rPr>'
      '<w:t>a</w:t><w:tab/><w:t>b</w:t><w:br/><w:br w:type="page"/>'
      '<w:br w:type="column"/><w:cr/><w:t>c</w:t></w:r></w:p>'
      '<w:p/>'
      '<w:p><w:r><w:t>second</w:t></w:r></w:p>',
    );
    expect(part.blocks, hasLength(3));
    final DocxParagraph first = _p(part);
    expect(first.style, 'Heading1');
    expect(
      paragraphPropertiesOf(first).kept.map((OpaqueXml k) => k.localName),
      <String>['jc'],
    );
    final DocxRun run = first.inlines.single as DocxRun;
    expect(run.style, 'Strong');
    expect(
      runPropertiesOf(run).kept.map((OpaqueXml k) => k.localName),
      <String>['kern'],
    );
    expect(run.properties.bold, isTrue);
    expect(run.content, <DocxRunContent>[
      const DocxText('a'),
      const DocxTab(),
      const DocxText('b'),
      const DocxBreak(),
      const DocxBreak(DocxBreakType.page),
      const DocxBreak(DocxBreakType.column),
      const DocxCarriageReturn(),
      const DocxText('c'),
    ]);
    expect(first.text, 'a\tb\n\n\n\nc');
    expect(_p(part, 1).inlines, isEmpty);
    expect(_p(part, 1).style, isNull);
    expect(_p(part, 2).text, 'second');
    expect(part.finalSectPr, isNull);
    expect(part.root.qualifiedName, 'w:document');
    expect(part.root.namespaces['w14'], Ns.w14);
  });

  test('a textWrapping break reads as a line break and keeps its type', () {
    final DocxRun run =
        _p(
              _read(
                '<w:p><w:r><w:br w:type="textWrapping" w:clear="all"/>'
                '<w:br w:type="page"/></w:r></w:p>',
              ),
            ).inlines.single
            as DocxRun;
    expect(run.content, <DocxRunContent>[
      const DocxBreak(),
      const DocxBreak(DocxBreakType.page),
    ]);
    final List<KeptAttribute> wrap = contentAttributesOf(run.content[0]);
    expect(_attr(wrap, 'w:type'), 'textWrapping');
    expect(_attr(wrap, 'w:clear'), 'all');
    // A typed page break does not keep its type a second time.
    expect(_attr(contentAttributesOf(run.content[1]), 'w:type'), isNull);
  });

  test('tables and sdt blocks are opaque blocks in place', () {
    final DocumentPart part = _read(
      '<w:p><w:r><w:t>before</w:t></w:r></w:p>'
      '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>cell</w:t></w:r></w:p></w:tc>'
      '</w:tr></w:tbl>'
      '<w:sdt><w:sdtContent><w:p/></w:sdtContent></w:sdt>'
      '<w:bookmarkStart w:id="0" w:name="x"/>'
      '<w:p><w:r><w:t>after</w:t></w:r></w:p>',
    );
    expect(part.blocks.map((DocxBlock b) => b.runtimeType), <Type>[
      DocxParagraph,
      DocxOpaqueBlock,
      DocxOpaqueBlock,
      DocxOpaqueBlock,
      DocxParagraph,
    ]);
    final DocxOpaqueBlock table = part.blocks[1] as DocxOpaqueBlock;
    expect(table.localName, 'tbl');
    expect(table.namespaceUri, Ns.w);
    expect(opaqueBlockXml(table).xml, startsWith('<w:tbl>'));
    expect(opaqueBlockXml(table).xml, endsWith('</w:tbl>'));
    expect((part.blocks[2] as DocxOpaqueBlock).localName, 'sdt');
    expect((part.blocks[3] as DocxOpaqueBlock).localName, 'bookmarkStart');
    expect(_p(part, 4).text, 'after');
  });

  test('the final sectPr is held by the body, a paragraph sectPr stays in '
      'pPr', () {
    final DocumentPart part = _read(
      '<w:p><w:pPr><w:sectPr><w:pgSz w:w="11906"/></w:sectPr></w:pPr>'
      '<w:r><w:t>one</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>two</w:t></w:r></w:p>'
      '<w:sectPr w:rsidR="00A1"><w:pgSz w:w="12240"/></w:sectPr>',
    );
    expect(part.blocks, hasLength(2));
    expect(
      paragraphPropertiesOf(_p(part)).kept.map((OpaqueXml k) => k.localName),
      <String>['sectPr'],
    );
    final OpaqueXml sectPr = part.finalSectPr!;
    expect(sectPr.localName, 'sectPr');
    expect(sectPr.xml, contains('12240'));
  });

  test('a sectPr that is not the last child of the body is a block', () {
    final DocumentPart part = _read(
      '<w:sectPr/><w:p/><w:sectPr><w:cols/></w:sectPr>',
    );
    expect(part.blocks.map((DocxBlock b) => b.runtimeType), <Type>[
      DocxOpaqueBlock,
      DocxParagraph,
    ]);
    expect(part.finalSectPr!.xml, '<w:sectPr><w:cols/></w:sectPr>');
  });

  test('a ns0 prefix and a default namespace read the same model', () {
    const String body =
        '<p><pPr><pStyle val="Title"/><jc val="left"/></pPr>'
        '<r><rPr><rStyle val="Emph"/></rPr><t>a</t><tab/><br type="page"/>'
        '<t xml:space="preserve"> b </t><drawing/></r>'
        '<ins id="1"><r><t>c</t></r></ins><del id="2"><r><delText>x'
        '</delText></r></del></p>'
        '<tbl/><p/><sectPr/>';
    String prefixed(String prefix) => body.replaceAllMapped(
      RegExp(r'<(/?)(\w+)|\s(val|type|id)='),
      (Match m) => m.group(2) != null
          ? '<${m.group(1)}$prefix:${m.group(2)}'
          : ' $prefix:${m.group(3)}=',
    );
    final DocumentPart w = _read(prefixed('w'));
    final DocumentPart ns0 = _readXml(
      '<ns0:document xmlns:ns0="${Ns.w}"><ns0:body>${prefixed('ns0')}'
      '</ns0:body></ns0:document>',
    );
    final String plainBody = body.replaceAllMapped(
      RegExp(r'\s(val|type|id)='),
      (Match m) => ' w:${m.group(1)}=',
    );
    final DocumentPart plain = _readXml(
      '<document xmlns="${Ns.w}" xmlns:w="${Ns.w}"><body>$plainBody'
      '</body></document>',
    );
    final String expected = _dump(w);
    expect(expected, contains('p(Title'));
    expect(expected, contains('r(Emph)'));
    expect(expected, contains('br:page'));
    expect(expected, contains('oi:${Ns.w}|ins"c"'));
    expect(expected, contains('sectPr:${Ns.w}|sectPr'));
    expect(_dump(ns0), expected);
    expect(_dump(plain), expected);
    expect(_p(ns0).text, 'a\t\n b c');
  });

  test('elements in another namespace with w local names are not typed', () {
    final DocumentPart part = _read(
      '<x:p xmlns:x="urn:other"><x:r><x:t>no</x:t></x:r></x:p>'
      '<w:p><x:r xmlns:x="urn:other"><x:t>no</x:t></x:r>'
      '<w:r><x:t xmlns:x="urn:other">no</x:t></w:r></w:p>',
    );
    expect(part.blocks.first, isA<DocxOpaqueBlock>());
    final DocxParagraph p = _p(part, 1);
    expect(p.inlines.first, isA<DocxOpaqueInline>());
    final DocxRun run = p.inlines[1] as DocxRun;
    expect(run.content.single, isA<DocxOpaqueRunContent>());
    expect(p.text, '');
  });

  test('runs inside ins, moveTo, hyperlink, sdt and smartTag give paragraph '
      'text in order', () {
    final DocxParagraph p = _p(
      _read(
        '<w:p><w:r><w:t>1</w:t></w:r>'
        '<w:ins w:id="1"><w:r><w:t>2</w:t></w:r></w:ins>'
        '<w:moveTo w:id="2"><w:r><w:t>3</w:t></w:r></w:moveTo>'
        '<w:hyperlink w:anchor="a"><w:r><w:t>4</w:t><w:tab/></w:r>'
        '</w:hyperlink>'
        '<w:sdt><w:sdtPr><w:r><w:t>placeholder</w:t></w:r></w:sdtPr>'
        '<w:sdtContent><w:r><w:t>5</w:t></w:r></w:sdtContent></w:sdt>'
        '<w:smartTag w:element="x"><w:r><w:t>6</w:t><w:br/></w:r>'
        '</w:smartTag>'
        '<w:proofErr w:type="spellStart"/>'
        '<w:r><w:t>7</w:t></w:r></w:p>',
      ),
    );
    expect(p.text, '1234\t56\n7');
    expect(p.inlines.map((DocxInline i) => i.runtimeType), <Type>[
      DocxRun,
      DocxOpaqueInline,
      DocxOpaqueInline,
      DocxOpaqueInline,
      DocxOpaqueInline,
      DocxOpaqueInline,
      DocxOpaqueInline,
      DocxRun,
    ]);
    expect(
      p.inlines.whereType<DocxOpaqueInline>().map(
        (DocxOpaqueInline i) => i.text,
      ),
      <String>['2', '3', '4\t', '5', '6\n', ''],
    );
  });

  test('del, moveFrom, del inside ins and stray delText give no text', () {
    final DocxParagraph p = _p(
      _read(
        '<w:p><w:r><w:t>a</w:t></w:r>'
        '<w:del w:id="1"><w:r><w:delText>gone</w:delText></w:r></w:del>'
        '<w:moveFrom w:id="2"><w:r><w:t>moved</w:t></w:r></w:moveFrom>'
        '<w:ins w:id="3"><w:r><w:t>b</w:t></w:r><w:del w:id="4"><w:r>'
        '<w:delText>x</w:delText></w:r></w:del></w:ins>'
        '<w:r><w:delText>stray</w:delText><w:t>c</w:t></w:r></w:p>',
      ),
    );
    expect(p.text, 'abc');
    final DocxRun last = p.inlines.last as DocxRun;
    expect(last.content.first, isA<DocxOpaqueRunContent>());
    expect((last.content.first as DocxOpaqueRunContent).localName, 'delText');
  });

  test('w14:paraId and rsid attributes are kept', () {
    final DocumentPart part = _readXml(
      '<w:document $_decls mc:Ignorable="w14">'
      '<w:body w:foo="1"><w:p w14:paraId="1A2B3C4D" w14:textId="77"'
      ' w:rsidR="00AB" w:rsidRDefault="00CD"><w:r w:rsidR="00EF">'
      '<w:t xml:space="preserve" w:bar="2">x</w:t>'
      '<w:tab w:baz="3"/><w:br w:clear="left"/><w:cr w:q="4"/></w:r></w:p>'
      '</w:body></w:document>',
    );
    expect(_attr(part.root.attributes, 'mc:Ignorable'), 'w14');
    expect(_attr(part.bodyAttributes, 'w:foo'), '1');
    final DocxParagraph p = _p(part);
    final List<KeptAttribute> pa = paragraphAttributesOf(p);
    expect(pa.map((KeptAttribute a) => a.qualifiedName), <String>[
      'w14:paraId',
      'w14:textId',
      'w:rsidR',
      'w:rsidRDefault',
    ]);
    expect(pa.first.namespaceUri, Ns.w14);
    expect(pa.first.value, '1A2B3C4D');
    final DocxRun run = p.inlines.single as DocxRun;
    expect(_attr(runAttributesOf(run), 'w:rsidR'), '00EF');
    expect(_attr(contentAttributesOf(run.content[0]), 'w:bar'), '2');
    expect(_attr(contentAttributesOf(run.content[1]), 'w:baz'), '3');
    expect(_attr(contentAttributesOf(run.content[2]), 'w:clear'), 'left');
    expect(_attr(contentAttributesOf(run.content[3]), 'w:q'), '4');
  });

  test('mc:AlternateContent in a run is opaque run content', () {
    final DocxRun run =
        _p(
              _read(
                '<w:p><w:r><w:t>a</w:t><mc:AlternateContent>'
                '<mc:Choice Requires="w14"><w:t>choice</w:t></mc:Choice>'
                '<mc:Fallback><w:t>fallback</w:t></mc:Fallback>'
                '</mc:AlternateContent><w:t>b</w:t></w:r></w:p>',
              ),
            ).inlines.single
            as DocxRun;
    expect(run.content, hasLength(3));
    final DocxOpaqueRunContent alt = run.content[1] as DocxOpaqueRunContent;
    expect(alt.localName, 'AlternateContent');
    expect(alt.namespaceUri, Ns.mc);
    final OpaqueXml xml = opaqueRunContentXml(alt);
    expect(xml.xml, startsWith('<mc:AlternateContent>'));
    expect(xml.inheritedNamespaces, containsPair('mc', Ns.mc));
    expect(xml.inheritedNamespaces, containsPair('w', Ns.w));
    expect(run.text, 'ab');
  });

  test('a w:t whose text is split by an entity reads as one text', () {
    final DocxRun run =
        _p(
              _read(
                '<w:p><w:r><w:t>a&amp;b&#x41;c&lt;<![CDATA[d]]>e</w:t>'
                '</w:r></w:p>',
              ),
            ).inlines.single
            as DocxRun;
    expect(run.content, <DocxRunContent>[const DocxText('a&bAc<de')]);
  });

  test('whitespace-only w:t with xml:space preserve is kept', () {
    final DocxRun run =
        _p(
              _read(
                '<w:p><w:r><w:t>a</w:t><w:t xml:space="preserve">  </w:t>'
                '<w:t>b</w:t><w:t/></w:r></w:p>',
              ),
            ).inlines.single
            as DocxRun;
    expect(run.content, <DocxRunContent>[
      const DocxText('a'),
      const DocxText('  '),
      const DocxText('b'),
      const DocxText(''),
    ]);
    final List<KeptAttribute> space = contentAttributesOf(run.content[1]);
    expect(space.single.qualifiedName, 'xml:space');
    expect(space.single.value, 'preserve');
    expect(space.single.namespaceUri, 'http://www.w3.org/XML/1998/namespace');
    expect(contentAttributesOf(run.content[0]), isEmpty);
  });

  test('content before and after the body is kept in order', () {
    final DocumentPart part = _readXml(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<w:document $_decls><w:background w:color="FF0000"/>'
      '<x:extra xmlns:x="urn:x"/>'
      '<w:body><w:p/></w:body><w:after/></w:document>',
    );
    expect(part.beforeBody.map((OpaqueXml o) => o.localName), <String>[
      'background',
      'extra',
    ]);
    expect(part.afterBody.single.localName, 'after');
    expect(part.blocks, hasLength(1));
  });

  test('a document without a body has no blocks', () {
    final DocumentPart part = _readXml('<w:document $_decls/>');
    expect(part.blocks, isEmpty);
    expect(part.bodyAttributes, isEmpty);
    expect(part.finalSectPr, isNull);
  });

  test('a root that is not w:document is malformedXml', () {
    expect(
      () => _readXml('<x:document xmlns:x="urn:x"/>'),
      throwsA(
        isA<DocxReadException>()
            .having(
              (DocxReadException e) => e.reason,
              'reason',
              DocxReadFailure.malformedXml,
            )
            .having(
              (DocxReadException e) => e.part,
              'part',
              '/word/document.xml',
            ),
      ),
    );
  });

  test('opaque inline text honours maxDepth, not a fixed 256', () {
    final String deep =
        '${'<w:smartTag>' * 300}<w:r><w:t>x</w:t></w:r>'
        '${'</w:smartTag>' * 300}';
    final DocxParagraph p = _p(
      _read('<w:p>$deep</w:p>', limits: const DocxReadLimits(maxDepth: 1000)),
    );
    expect(p.text, 'x');
    expect(
      () => _read(
        '<w:p>$deep</w:p>',
        limits: const DocxReadLimits(maxDepth: 200),
      ),
      throwsA(
        isA<XmlParseException>().having(
          (XmlParseException e) => e.kind,
          'kind',
          XmlParseKind.tooDeep,
        ),
      ),
    );
  });

  group('through DocxPackage.guard', () {
    /// Opens [document] as a package and reads it within [limits] under
    /// guard; returns what [DocumentPart.read] gave.
    DocumentPart readPackage(
      String document, {
      DocxReadLimits limits = const DocxReadLimits(),
    }) {
      final Uint8List bytes = buildDocx(document: document);
      final DocxPackage package = DocxPackage(
        bytes,
        limits,
        DocxWarningCollector(),
      );
      return package.guard(
        package.mainPart,
        () => DocumentPart.read(
          package.openXml(package.mainPart),
          DocxWarningCollector(),
          package.mainPart,
          limits: package.limits,
        ),
      );
    }

    test('a bad entity inside an opaque inline is a DocxReadException', () {
      expect(
        () => readPackage(
          '<w:document $_decls><w:body><w:p><w:ins w:id="1"><w:r>'
          '<w:t>a&bogus;</w:t></w:r></w:ins></w:p></w:body></w:document>',
        ),
        throwsA(
          isA<DocxReadException>()
              .having(
                (DocxReadException e) => e.reason,
                'reason',
                DocxReadFailure.malformedXml,
              )
              .having(
                (DocxReadException e) => e.part,
                'part',
                '/word/document.xml',
              ),
        ),
      );
    });

    test('nesting past maxDepth inside an opaque inline is limitExceeded', () {
      expect(
        () => readPackage(
          '<w:document $_decls><w:body><w:p><w:ins>'
          '${'<w:smartTag>' * 20}${'</w:smartTag>' * 20}'
          '</w:ins></w:p></w:body></w:document>',
          limits: const DocxReadLimits(maxDepth: 16),
        ),
        throwsA(
          isA<DocxReadException>()
              .having(
                (DocxReadException e) => e.reason,
                'reason',
                DocxReadFailure.limitExceeded,
              )
              .having(
                (DocxReadException e) => e.message,
                'message',
                contains('maxDepth (16)'),
              ),
        ),
      );
    });

    test('a well-formed document reads', () {
      final DocumentPart part = readPackage(
        '<w:document $_decls><w:body><w:p><w:r><w:t>hi</w:t></w:r></w:p>'
        '</w:body></w:document>',
      );
      expect(_p(part).text, 'hi');
    });
  });

  group('maxTextLength', () {
    DocxReadException refused(String body) {
      try {
        _read(body, limits: const DocxReadLimits(maxTextLength: 4));
      } on DocxReadException catch (e) {
        return e;
      }
      fail('no DocxReadException');
    }

    test('a w:t of the limit reads', () {
      expect(
        _p(
          _read(
            '<w:p><w:r><w:t>abcd</w:t></w:r></w:p>',
            limits: const DocxReadLimits(maxTextLength: 4),
          ),
        ).text,
        'abcd',
      );
    });

    test('a longer w:t names the limit and the paragraph', () {
      final DocxReadException e = refused(
        '<w:p/><w:tbl/><w:p><w:r><w:t>ab&amp;cd</w:t></w:r></w:p>',
      );
      expect(e.reason, DocxReadFailure.limitExceeded);
      expect(e.part, '/word/document.xml');
      // Paragraphs only, as in a warning's location: the table does not
      // count.
      expect(e.message, 'Limit maxTextLength (4) exceeded by body/p[1].');
    });

    test('a content control and a mid-body w:sectPr do not count', () {
      final DocxReadException e = refused(
        '<w:sdt/><w:sectPr/><w:p/><w:p><w:r><w:t>abcde</w:t></w:r></w:p>',
      );
      expect(e.message, 'Limit maxTextLength (4) exceeded by body/p[1].');
    });

    test('the visible text of an opaque inline counts too', () {
      final DocxReadException e = refused(
        '<w:p><w:ins><w:r><w:t>abc</w:t></w:r><w:r><w:t>de</w:t></w:r>'
        '</w:ins></w:p>',
      );
      expect(e.reason, DocxReadFailure.limitExceeded);
      expect(e.message, contains('maxTextLength (4)'));
    });

    test('deleted text inside an opaque inline does not count', () {
      expect(
        _p(
          _read(
            '<w:p><w:del><w:r><w:delText>abcdefgh</w:delText></w:r>'
            '</w:del></w:p>',
            limits: const DocxReadLimits(maxTextLength: 4),
          ),
        ).text,
        '',
      );
    });
  });
}
