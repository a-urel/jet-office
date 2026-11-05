import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/edit_sink.dart';
import 'package:jet_office/src/docx/model/inlines.dart';
import 'package:jet_office/src/docx/model/property_set.dart';
import 'package:jet_office/src/docx/model/run_content.dart';
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/run_property_codecs.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

/// Captures the first child of a `w:p` that declares `w` and `w14` and holds
/// [inner].
OpaqueXml _capture(String inner) {
  final XmlPullReader r = XmlPullReader(
    '<w:p xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}">$inner</w:p>',
  );
  r.nextTag();
  r.nextTag();
  return OpaqueXml.capture(r);
}

/// The visible text of the opaque inline [inner].
String _visible(String inner) => visibleText(_capture(inner));

/// A run of the given [content], built as the reader builds it.
DocxRun _runOf(List<DocxRunContent> content) => readRun(
  properties: const PropertyContainer.empty(),
  attributes: const <KeptAttribute>[],
  content: content,
);

/// Records every call it receives, as text.
final class _RecordingSink implements DocxEditSink {
  final List<String> calls = <String>[];

  @override
  void inlineInserted(DocxParagraph paragraph, int index, DocxInline inline) =>
      calls.add('insert $index');

  @override
  void inlineRemoved(DocxParagraph paragraph, int index, DocxInline inline) =>
      calls.add('remove $index');

  @override
  void inlineReplaced(
    DocxParagraph paragraph,
    int index,
    DocxInline previous,
    DocxInline replacement,
  ) => calls.add('replace $index');

  @override
  void runTextSet(DocxRun run, DocxRunText previous) =>
      calls.add('text ${previous.content.length} ${previous.removed}');

  @override
  void propertySet(
    PropertySet properties,
    String localName,
    PropertyState previous,
  ) => calls.add('$localName ${previous.value}');

  @override
  void atomically(void Function() body) => body();

  @override
  String resolveStyleId(String id, DocxStyleType type) => id;

  @override
  bool isForeign(DocxEditSink? readIn) => false;
}

void main() {
  group('run text', () {
    test('tab and newline split the text into content', () {
      final DocxRun run = DocxParagraph().addRun('a\tb\nc');
      expect(run.content, <DocxRunContent>[
        const DocxText('a'),
        const DocxTab(),
        const DocxText('b'),
        const DocxBreak(),
        const DocxText('c'),
      ]);
    });

    test('CR LF is one break', () {
      final DocxRun run = DocxParagraph().addRun('a\r\nb');
      expect(run.content, <DocxRunContent>[
        const DocxText('a'),
        const DocxBreak(),
        const DocxText('b'),
      ]);
    });

    test('a lone CR is one break', () {
      final DocxRun run = DocxParagraph().addRun('a\rb\r');
      expect(run.content, <DocxRunContent>[
        const DocxText('a'),
        const DocxBreak(),
        const DocxText('b'),
        const DocxBreak(),
      ]);
    });

    test('reading text maps tab, every break and CR, opaque gives none', () {
      final DocxRun run = _runOf(<DocxRunContent>[
        const DocxText('a'),
        const DocxTab(),
        const DocxBreak(),
        const DocxBreak(DocxBreakType.page),
        const DocxBreak(DocxBreakType.column),
        const DocxCarriageReturn(),
        opaqueRunContent(_capture('<w:sym w:char="F04A"/>')),
        const DocxText('b'),
      ]);
      expect(run.text, 'a\t\n\n\n\nb');
    });

    test('text reads back what was set', () {
      final DocxRun run = DocxParagraph().addRun();
      run.text = 'x\ty\r\nz';
      expect(run.text, 'x\ty\nz');
    });

    test('the empty text has no content', () {
      expect(DocxParagraph().addRun().content, isEmpty);
    });

    test('forbidden characters are removed when set and counted', () {
      final DocxRun run = DocxParagraph().addRun('a\u0001b\uFFFF');
      expect(run.text, 'ab');
      expect(removedCharactersOf(run), 2);
      run.text = 'clean';
      expect(removedCharactersOf(run), 0);
    });

    test('U+FFFE is removed when set and counted', () {
      final DocxRun run = DocxRun('a\uFFFEb');
      expect(run.text, 'ab');
      expect(removedCharactersOf(run), 1);
    });

    test('a lone high surrogate is removed when set and counted', () {
      final DocxRun run = DocxRun('a\uD800b');
      expect(run.text, 'ab');
      expect(removedCharactersOf(run), 1);
    });

    test('a lone low surrogate is removed when set and counted', () {
      final DocxRun run = DocxRun('a\uDC00b');
      expect(run.text, 'ab');
      expect(removedCharactersOf(run), 1);
    });

    test('a supplementary character is kept, nothing removed', () {
      final DocxRun run = DocxRun('a\u{1F600}b');
      expect(run.text, 'a\u{1F600}b');
      expect(removedCharactersOf(run), 0);
    });

    test('content view is unmodifiable', () {
      final DocxRun run = DocxParagraph().addRun('a');
      expect(() => run.content.add(const DocxTab()), throwsUnsupportedError);
      expect(run.content.clear, throwsUnsupportedError);
    });

    test('the default break is a line break', () {
      expect(const DocxBreak().type, DocxBreakType.line);
      expect(const DocxBreak(), isNot(const DocxBreak(DocxBreakType.page)));
    });
  });

  group('paragraph text', () {
    test('paragraph text joins inline texts', () {
      final DocxParagraph p = DocxParagraph();
      p.addRun('one ');
      p.insertInline(
        1,
        opaqueInline(_capture('<w:ins><w:r><w:t>two</w:t></w:r></w:ins>')),
      );
      p.addRun(' three');
      expect(p.text, 'one two three');
    });

    test('DocxParagraph.text holds one run with the text', () {
      final DocxParagraph p = DocxParagraph.text('a\tb');
      expect(p.inlines, hasLength(1));
      expect(p.text, 'a\tb');
      expect(DocxParagraph.text('').inlines, isEmpty);
    });

    test('a new paragraph has no inlines, no style and empty pPr', () {
      final DocxParagraph p = DocxParagraph();
      expect(p.inlines, isEmpty);
      expect(p.style, isNull);
      expect(p.text, '');
      expect(paragraphPropertiesOf(p).isEmpty, isTrue);
    });
  });

  group('visible text of an opaque inline', () {
    test('visibleText parses the slice within maxDepth', () {
      final String deep =
          '<w:ins>${'<w:smartTag>' * 300}<w:r><w:t>x</w:t></w:r>'
          '${'</w:smartTag>' * 300}</w:ins>';
      final XmlPullReader r = XmlPullReader(
        '<w:p xmlns:w="${Ns.w}">$deep</w:p>',
        maxDepth: 1000,
      );
      r.nextTag();
      r.nextTag();
      final OpaqueXml node = OpaqueXml.capture(r);
      expect(visibleText(node, maxDepth: 400), 'x');
      expect(() => visibleText(node), throwsA(isA<XmlParseException>()));
    });

    test('ins contributes its runs', () {
      expect(_visible('<w:ins><w:r><w:t>a</w:t></w:r></w:ins>'), 'a');
    });

    test('moveTo contributes its runs', () {
      expect(_visible('<w:moveTo><w:r><w:t>a</w:t></w:r></w:moveTo>'), 'a');
    });

    test('hyperlink contributes its runs in order', () {
      expect(
        _visible(
          '<w:hyperlink><w:r><w:t>a</w:t></w:r>'
          '<w:r><w:tab/><w:t>b</w:t><w:br/></w:r></w:hyperlink>',
        ),
        'a\tb\n',
      );
    });

    test('sdt contributes sdtContent only, never sdtPr placeholders', () {
      expect(
        _visible(
          '<w:sdt><w:sdtPr><w:placeholder><w:docPart w:val="x"/>'
          '</w:placeholder><w:r><w:t>hint</w:t></w:r></w:sdtPr>'
          '<w:sdtEndPr><w:r><w:t>end</w:t></w:r></w:sdtEndPr>'
          '<w:sdtContent><w:r><w:t>value</w:t></w:r></w:sdtContent></w:sdt>',
        ),
        'value',
      );
    });

    test('smartTag contributes its runs', () {
      expect(
        _visible(
          '<w:smartTag w:element="x"><w:r><w:t>a</w:t></w:r></w:smartTag>',
        ),
        'a',
      );
    });

    test('customXml contributes its runs', () {
      expect(
        _visible(
          '<w:customXml w:element="x"><w:r><w:t>a</w:t></w:r></w:customXml>',
        ),
        'a',
      );
    });

    test('fldSimple contributes its runs', () {
      expect(
        _visible(
          '<w:fldSimple w:instr=" PAGE "><w:r><w:t>3</w:t></w:r></w:fldSimple>',
        ),
        '3',
      );
    });

    test('containers nest recursively', () {
      expect(
        _visible(
          '<w:hyperlink><w:ins><w:smartTag><w:r><w:t>a</w:t></w:r>'
          '</w:smartTag></w:ins><w:r><w:t>b</w:t></w:r></w:hyperlink>',
        ),
        'ab',
      );
    });

    test('del contributes nothing', () {
      expect(
        _visible('<w:del><w:r><w:delText>a</w:delText></w:r></w:del>'),
        '',
      );
    });

    test('moveFrom contributes nothing', () {
      expect(_visible('<w:moveFrom><w:r><w:t>a</w:t></w:r></w:moveFrom>'), '');
    });

    test('a del inside an ins is deleted', () {
      expect(
        _visible(
          '<w:ins><w:r><w:t>a</w:t></w:r><w:del><w:r><w:t>b</w:t></w:r>'
          '</w:del><w:r><w:t>c</w:t></w:r></w:ins>',
        ),
        'ac',
      );
    });

    test('a moveFrom inside a hyperlink is not visible', () {
      expect(
        _visible(
          '<w:hyperlink><w:moveFrom><w:r><w:t>b</w:t></w:r></w:moveFrom>'
          '</w:hyperlink>',
        ),
        '',
      );
    });

    test('delText and delInstrText outside a del contribute nothing', () {
      expect(
        _visible(
          '<w:ins><w:r><w:t>a</w:t><w:delText>x</w:delText>'
          '<w:delInstrText>y</w:delInstrText></w:r></w:ins>',
        ),
        'a',
      );
    });

    test('instrText and drawings in a run are not text', () {
      expect(
        _visible(
          '<w:ins><w:r><w:instrText> PAGE </w:instrText></w:r>'
          '<w:r><w:drawing><w:p><w:r><w:t>box</w:t></w:r></w:p></w:drawing>'
          '<w:t>a</w:t></w:r></w:ins>',
        ),
        'a',
      );
    });

    test('entities and CDATA in w:t are decoded', () {
      expect(
        _visible('<w:ins><w:r><w:t>a&amp;b<![CDATA[<c>]]></w:t></w:r></w:ins>'),
        'a&b<c>',
      );
    });

    test('a default namespace reads as the w prefix does', () {
      expect(
        _visible(
          '<ins xmlns="${Ns.w}"><r><t>a</t></r><del><r><t>b</t></r></del>'
          '</ins>',
        ),
        'a',
      );
    });

    test('an element in another namespace contributes nothing', () {
      expect(_visible('<w14:x><w:r><w:t>a</w:t></w:r></w14:x>'), '');
    });

    test('opaqueInline computes its text from the XML', () {
      final DocxOpaqueInline o = opaqueInline(
        _capture('<w:ins><w:r><w:t>a</w:t></w:r></w:ins>'),
      );
      expect(o.text, 'a');
    });
  });

  group('opaque kinds', () {
    test('opaque kinds expose only their name', () {
      final OpaqueXml table = _capture('<w:tbl/>');
      final DocxOpaqueBlock block = opaqueBlock(table);
      expect(block.localName, 'tbl');
      expect(block.namespaceUri, Ns.w);
      expect(opaqueBlockXml(block), same(table));

      final OpaqueXml proof = _capture('<w:proofErr w:type="spellStart"/>');
      final DocxOpaqueInline inline = opaqueInline(proof);
      expect(inline.localName, 'proofErr');
      expect(inline.namespaceUri, Ns.w);
      expect(inline.text, '');
      expect(opaqueInlineXml(inline), same(proof));

      final OpaqueXml sym = _capture('<w:sym w:char="F04A"/>');
      final DocxOpaqueRunContent content = opaqueRunContent(sym);
      expect(content.localName, 'sym');
      expect(content.namespaceUri, Ns.w);
      expect(opaqueRunContentXml(content), same(sym));
    });

    test('a precomputed text is kept', () {
      final DocxOpaqueInline o = opaqueInline(
        _capture('<w:ins/>'),
        text: 'given',
      );
      expect(o.text, 'given');
    });
  });

  group('inline edits', () {
    test('inlines view is unmodifiable', () {
      final DocxParagraph p = DocxParagraph.text('a');
      expect(() => p.inlines.add(DocxRun()), throwsUnsupportedError);
      expect(() => p.inlines.removeAt(0), throwsUnsupportedError);
    });

    test('insertInline and removeInlineAt edit in place', () {
      final DocxParagraph p = DocxParagraph();
      final DocxRun a = p.addRun('a');
      final DocxRun c = p.addRun('c');
      final DocxRun b = DocxRun('b');
      p.insertInline(1, b);
      expect(p.inlines, <DocxInline>[a, b, c]);
      expect(p.text, 'abc');
      p.removeInlineAt(0);
      expect(p.inlines, <DocxInline>[b, c]);
      p.insertInline(2, a);
      expect(p.text, 'bca');
    });

    test('a bad index throws RangeError', () {
      final DocxParagraph p = DocxParagraph.text('a');
      expect(() => p.insertInline(2, DocxRun()), throwsRangeError);
      expect(() => p.insertInline(-1, DocxRun()), throwsRangeError);
      expect(() => p.removeInlineAt(1), throwsRangeError);
      expect(() => p.removeInlineAt(-1), throwsRangeError);
      expect(p.text, 'a');
    });

    test('an inline already in a paragraph throws StateError', () {
      final DocxParagraph p = DocxParagraph();
      final DocxRun run = p.addRun('a');
      expect(() => p.insertInline(0, run), throwsStateError);
      expect(() => DocxParagraph().insertInline(0, run), throwsStateError);
      p.removeInlineAt(0);
      DocxParagraph().insertInline(0, run);
    });

    test('replaceInlineAt swaps one inline', () {
      final DocxParagraph p = DocxParagraph.text('a');
      final DocxRun old = p.inlines.single as DocxRun;
      replaceInlineAt(p, 0, DocxRun('b'));
      expect(p.text, 'b');
      DocxParagraph().insertInline(0, old);
      expect(() => replaceInlineAt(p, 1, DocxRun()), throwsRangeError);
    });
  });

  group('style', () {
    test('paragraph and run style read and write', () {
      final DocxParagraph p = DocxParagraph();
      p.style = 'Heading1';
      expect(p.style, 'Heading1');
      p.style = null;
      expect(p.style, isNull);
      final DocxRun r = p.addRun('a');
      expect(r.style, isNull);
      r.style = 'Strong';
      expect(r.style, 'Strong');
    });

    test('an empty style id throws ArgumentError', () {
      expect(() => DocxParagraph().style = '', throwsArgumentError);
      expect(() => DocxRun().style = '', throwsArgumentError);
    });

    test('a style id with characters XML forbids throws ArgumentError', () {
      final DocxParagraph p = DocxParagraph()..style = 'Body';
      final DocxRun r = p.addRun('a')..style = 'Strong';
      expect(() => p.style = 'Bad\u0001', throwsArgumentError);
      expect(() => r.style = 'Bad\uFFFF', throwsArgumentError);
      expect(() => r.style = 'Bad\uD800', throwsArgumentError);
      expect(p.style, 'Body');
      expect(r.style, 'Strong');
    });

    test('a read run keeps its style and rPr', () {
      final XmlPullReader reader = XmlPullReader(
        '<w:rPr xmlns:w="${Ns.w}"><w:rStyle w:val="Strong"/></w:rPr>',
      );
      reader.nextTag();
      final DocxRun r = readRun(
        properties: PropertyContainer.read(reader, runPropertiesSchema),
        attributes: const <KeptAttribute>[],
        content: const <DocxRunContent>[DocxText('a')],
      );
      expect(r.style, 'Strong');
      expect(r.text, 'a');
      expect(runPropertiesOf(r).kept, isEmpty);
    });
  });

  group('edit sink', () {
    test('every edit is reported to the attached sink', () {
      final DocxParagraph p = DocxParagraph();
      final _RecordingSink sink = _RecordingSink();
      attachEditSink(p, sink);
      final DocxRun run = p.addRun('a');
      run.text = 'b\tc';
      run.style = 'S';
      p.style = 'P';
      replaceInlineAt(p, 0, DocxRun());
      p.insertInline(0, run);
      p.removeInlineAt(1);
      expect(sink.calls, <String>[
        'insert 0',
        'text 1 0',
        'rStyle null',
        'pStyle null',
        'replace 0',
        'insert 0',
        'remove 1',
      ]);
    });

    test('a removed run no longer reports to the sink', () {
      final DocxParagraph p = DocxParagraph();
      final _RecordingSink sink = _RecordingSink();
      attachEditSink(p, sink);
      final DocxRun run = p.addRun('a');
      p.removeInlineAt(0);
      sink.calls.clear();
      run.text = 'b';
      expect(sink.calls, isEmpty);
    });

    test('restoreRunText puts content and count back silently', () {
      final DocxParagraph p = DocxParagraph();
      final DocxRun run = p.addRun('a\u0001');
      final _RecordingSink sink = _RecordingSink();
      attachEditSink(p, sink);
      final DocxRunText before = runTextOf(run);
      run.text = 'b';
      restoreRunText(run, before);
      expect(run.text, 'a');
      expect(removedCharactersOf(run), 1);
      expect(sink.calls, <String>['text 1 1']);
    });

    test('a text set that changes nothing is not reported', () {
      final DocxParagraph p = DocxParagraph();
      final DocxRun run = p.addRun('a\tb\u0001');
      final _RecordingSink sink = _RecordingSink();
      attachEditSink(p, sink);
      final List<DocxRunContent> before = run.content.toList();
      run.text = 'a\tb\u0002';
      expect(sink.calls, isEmpty);
      expect(run.content, before);
      run.text = 'a\tb';
      expect(sink.calls, <String>['text 3 1']);
    });

    test('setting a read run its own text keeps the read content', () {
      final DocxParagraph p = readParagraph(
        properties: const PropertyContainer.empty(),
        attributes: const <KeptAttribute>[],
        inlines: <DocxInline>[
          _runOf(<DocxRunContent>[
            readText(' a', const <KeptAttribute>[
              (
                qualifiedName: 'xml:space',
                namespaceUri: 'http://www.w3.org/XML/1998/namespace',
                value: 'preserve',
              ),
            ]),
          ]),
        ],
      );
      final DocxRun run = p.inlines.single as DocxRun;
      final DocxRunContent read = run.content.single;
      final _RecordingSink sink = _RecordingSink();
      attachEditSink(p, sink);
      run.text = ' a';
      expect(sink.calls, isEmpty);
      expect(run.content.single, same(read));
    });

    test('the default sink accepts every call', () {
      final DocxParagraph p = DocxParagraph();
      expect(editSinkOf(p), same(DocxEditSink.none));
      p.addRun('a').text = 'b';
    });
  });

  group('run content values', () {
    test('equal kinds are equal', () {
      expect(const DocxText('a'), const DocxText('a'));
      expect(const DocxText('a').hashCode, const DocxText('a').hashCode);
      expect(const DocxText('a'), isNot(const DocxText('b')));
      expect(const DocxTab(), const DocxTab());
      expect(const DocxCarriageReturn(), const DocxCarriageReturn());
      expect(const DocxTab(), isNot(const DocxCarriageReturn()));
    });

    test('read kinds keep their attributes', () {
      const List<KeptAttribute> attrs = <KeptAttribute>[
        (qualifiedName: 'xml:space', namespaceUri: '', value: 'preserve'),
      ];
      final DocxText t = readText(' a', attrs);
      expect(t, const DocxText(' a'));
      expect(contentAttributesOf(t), attrs);
      expect(contentAttributesOf(const DocxTab()), isEmpty);
      expect(contentAttributesOf(readBreak(DocxBreakType.page, attrs)), attrs);
      expect(contentAttributesOf(readTab(attrs)), attrs);
      expect(contentAttributesOf(readCarriageReturn(attrs)), attrs);
    });
  });
}
