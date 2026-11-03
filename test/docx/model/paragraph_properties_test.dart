// Tests the paragraph properties of the DOCX model: each member sets,
// reads back and writes the element the plan names, children of a Word file
// stay in place, values a file holds that the model cannot type read null
// and save unchanged, and a set is one change that reverts with its
// transaction. They build documents in memory, so they run on the web as
// well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';

/// A document whose only paragraph has the `w:pPr` holding [pPr] (none
/// when it is null).
DocxDocument _open([String? pPr]) => DocxDocument.open(
  buildDocx(
    document:
        '<w:document xmlns:w="${Ns.w}" '
        'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">'
        '<w:body><w:p>${pPr == null ? '' : '<w:pPr>$pPr</w:pPr>'}'
        '<w:r><w:t>a</w:t></w:r></w:p></w:body></w:document>',
  ),
);

DocxParagraph _paragraph(DocxDocument doc) =>
    doc.body.blocks.single as DocxParagraph;

/// The `w:pPr` of the saved document, as written.
String _pPr(DocxDocument doc) {
  final String xml = readXlsx(doc.save().bytes)['word/document.xml']!;
  final RegExpMatch? m = RegExp(r'<w:pPr>(.*?)</w:pPr>').firstMatch(xml);
  return m == null ? '' : m.group(1)!;
}

/// Sets a property on a new paragraph and returns the `w:pPr` it saves.
String _written(void Function(DocxParagraphProperties p) set) {
  final DocxDocument doc = _open();
  set(_paragraph(doc).properties);
  return _pPr(doc);
}

void main() {
  group('members', () {
    test('style sets and reads back, and DocxParagraph.style delegates', () {
      final DocxDocument doc = _open();
      final DocxParagraph p = _paragraph(doc);
      p.properties.style = 'Title';
      expect(p.style, 'Title');
      p.style = 'Heading1';
      expect(p.properties.style, 'Heading1');
      expect(_pPr(doc), '<w:pStyle w:val="Heading1"/>');
    });

    test('alignment sets and reads back', () {
      expect(
        _written(
          (DocxParagraphProperties p) => p.alignment = DocxAlignment.center,
        ),
        '<w:jc w:val="center"/>',
      );
      expect(
        _written(
          (DocxParagraphProperties p) => p.alignment = DocxAlignment.justify,
        ),
        '<w:jc w:val="both"/>',
      );
      for (final DocxAlignment a in DocxAlignment.values) {
        final DocxDocument doc = _open();
        _paragraph(doc).properties.alignment = a;
        expect(
          _paragraph(DocxDocument.open(doc.save().bytes)).properties.alignment,
          a,
        );
      }
    });

    test('indentation sets and reads back', () {
      final DocxDocument doc = _open();
      _paragraph(doc).properties.indentation = DocxIndentation(
        leftPt: 36,
        hangingPt: 18,
      );
      expect(_pPr(doc), '<w:ind w:left="720" w:hanging="360"/>');
      final DocxIndentation read = _paragraph(
        DocxDocument.open(doc.save().bytes),
      ).properties.indentation!;
      expect(read.leftPt, 36);
      expect(read.hangingPt, 18);
      expect(read.rightPt, isNull);
      expect(read.firstLinePt, isNull);
      expect(read, DocxIndentation(leftPt: 36, hangingPt: 18));
      expect(
        _written(
          (DocxParagraphProperties p) =>
              p.indentation = DocxIndentation(rightPt: 7.5, firstLinePt: 10),
        ),
        '<w:ind w:right="150" w:firstLine="200"/>',
      );
    });

    test('firstLinePt with hangingPt throws ArgumentError', () {
      expect(
        () => DocxIndentation(firstLinePt: 1, hangingPt: 1),
        throwsArgumentError,
      );
      expect(() => DocxIndentation(leftPt: 1585), throwsRangeError);
      expect(() => DocxIndentation(hangingPt: -1), throwsRangeError);
      expect(() => DocxIndentation(leftPt: double.nan), throwsArgumentError);
    });

    test('spacing sets and reads back', () {
      final DocxDocument doc = _open();
      _paragraph(doc).properties.spacing = DocxSpacing(
        afterPt: 8,
        line: DocxLineSpacing.multiple(1.16),
      );
      expect(
        _pPr(doc),
        '<w:spacing w:after="160" w:line="278" w:lineRule="auto"/>',
      );
      final DocxSpacing read = _paragraph(
        DocxDocument.open(doc.save().bytes),
      ).properties.spacing!;
      expect(read.afterPt, 8);
      expect(read.beforePt, isNull);
      expect(read.line, DocxLineSpacing.multiple(1.16));
      expect(read.line!.rule, DocxLineRule.auto);
      expect(read.line!.value, closeTo(1.1583, 0.001));
    });

    test('spacing before, auto spacing and exact and at-least lines', () {
      expect(
        _written(
          (DocxParagraphProperties p) => p.spacing = DocxSpacing(
            beforePt: 6,
            beforeAuto: true,
            afterAuto: true,
            line: DocxLineSpacing.exactly(14),
          ),
        ),
        '<w:spacing w:before="120" w:beforeAutospacing="1" '
        'w:afterAutospacing="1" w:line="280" w:lineRule="exact"/>',
      );
      expect(
        _written(
          (DocxParagraphProperties p) =>
              p.spacing = DocxSpacing(line: DocxLineSpacing.atLeast(12.5)),
        ),
        '<w:spacing w:line="250" w:lineRule="atLeast"/>',
      );
      final DocxLineSpacing exact = DocxLineSpacing.exactly(14);
      expect(exact.rule, DocxLineRule.exact);
      expect(exact.value, 14);
      expect(DocxLineSpacing.atLeast(12).rule, DocxLineRule.atLeast);
    });

    test('line multiple 133 throws RangeError', () {
      expect(() => DocxLineSpacing.multiple(133), throwsRangeError);
      expect(() => DocxLineSpacing.multiple(0), throwsRangeError);
      expect(
        () => DocxLineSpacing.multiple(double.infinity),
        throwsArgumentError,
      );
      expect(() => DocxLineSpacing.exactly(1585), throwsRangeError);
      expect(() => DocxLineSpacing.atLeast(-1), throwsRangeError);
      expect(() => DocxSpacing(beforePt: 1585), throwsRangeError);
      expect(DocxLineSpacing.multiple(132).value, 132);
    });

    test('keepWithNext, keepLines, pageBreakBefore, widowControl write', () {
      expect(
        _written((DocxParagraphProperties p) {
          p.widowControl = false;
          p.pageBreakBefore = true;
          p.keepLines = true;
          p.keepWithNext = true;
        }),
        '<w:keepNext/><w:keepLines/><w:pageBreakBefore/>'
        '<w:widowControl w:val="0"/>',
      );
      final DocxDocument doc = _open(
        '<w:keepNext/><w:widowControl w:val="0"/>',
      );
      final DocxParagraphProperties p = _paragraph(doc).properties;
      expect(p.keepWithNext, isTrue);
      expect(p.widowControl, isFalse);
      expect(p.keepLines, isNull);
      expect(p.pageBreakBefore, isNull);
    });

    test('outlineLevel sets and reads back', () {
      expect(
        _written((DocxParagraphProperties p) => p.outlineLevel = 2),
        '<w:outlineLvl w:val="2"/>',
      );
      expect(
        _written((DocxParagraphProperties p) => p.outlineLevel = 9),
        '<w:outlineLvl w:val="9"/>',
      );
      final DocxDocument doc = _open('<w:outlineLvl w:val="0"/>');
      expect(_paragraph(doc).properties.outlineLevel, 0);
      expect(
        () => _paragraph(doc).properties.outlineLevel = 10,
        throwsRangeError,
      );
      expect(
        () => _paragraph(doc).properties.outlineLevel = -1,
        throwsRangeError,
      );
    });

    test('borders sets and reads back', () {
      final DocxDocument doc = _open();
      final DocxParagraphBorders borders = DocxParagraphBorders(
        bottom: DocxBorder(
          widthPt: 1,
          spacePt: 1,
          color: DocxColor.rgb('FF0000'),
        ),
        top: DocxBorder(style: DocxBorderStyle.double),
      );
      _paragraph(doc).properties.borders = borders;
      expect(
        _pPr(doc),
        '<w:pBdr><w:top w:val="double" w:sz="4" w:space="0"/>'
        '<w:bottom w:val="single" w:sz="8" w:space="1" w:color="FF0000"/>'
        '</w:pBdr>',
      );
      final DocxParagraphBorders read = _paragraph(
        DocxDocument.open(doc.save().bytes),
      ).properties.borders!;
      expect(read, borders);
      expect(read.left, isNull);
      expect(read.top!.style, DocxBorderStyle.double);
    });

    test('shading sets and reads back', () {
      expect(
        _written(
          (DocxParagraphProperties p) =>
              p.shading = DocxShading(fill: DocxColor.rgb('FFFF00')),
        ),
        '<w:shd w:val="clear" w:fill="FFFF00"/>',
      );
    });

    test('tabs sets and reads back', () {
      final DocxDocument doc = _open();
      _paragraph(doc).properties.tabs = <DocxTabStop>[
        DocxTabStop(
          453.1,
          alignment: DocxTabAlignment.right,
          leader: DocxTabLeader.dot,
        ),
        DocxTabStop(36),
      ];
      expect(
        _pPr(doc),
        '<w:tabs><w:tab w:val="right" w:leader="dot" w:pos="9062"/>'
        '<w:tab w:val="left" w:pos="720"/></w:tabs>',
      );
      final List<DocxTabStop> read = _paragraph(
        DocxDocument.open(doc.save().bytes),
      ).properties.tabs!;
      expect(read, hasLength(2));
      expect(read[0].positionPt, 453.1);
      expect(read[0].alignment, DocxTabAlignment.right);
      expect(read[0].leader, DocxTabLeader.dot);
      expect(read[1], DocxTabStop(36));
      expect(() => read.add(DocxTabStop(1)), throwsUnsupportedError);
    });

    test('an empty tabs list removes w:tabs and tab values range', () {
      final DocxDocument doc = _open(
        '<w:tabs><w:tab w:val="center" '
        'w:pos="100"/></w:tabs>',
      );
      final DocxParagraphProperties p = _paragraph(doc).properties;
      expect(p.tabs, <DocxTabStop>[
        DocxTabStop(5, alignment: DocxTabAlignment.center),
      ]);
      p.tabs = <DocxTabStop>[];
      expect(p.tabs, isNull);
      expect(_pPr(doc), '');
      expect(() => DocxTabStop(1585), throwsRangeError);
      expect(() => DocxTabStop(-1585), throwsRangeError);
      expect(() => DocxTabStop(double.nan), throwsArgumentError);
      expect(DocxTabStop(-5).positionPt, -5);
    });

    test('every tab alignment and leader round trips', () {
      final DocxDocument doc = _open();
      final List<DocxTabStop> stops = <DocxTabStop>[
        for (final DocxTabAlignment a in DocxTabAlignment.values)
          for (final DocxTabLeader l in DocxTabLeader.values)
            DocxTabStop(10, alignment: a, leader: l),
      ];
      _paragraph(doc).properties.tabs = stops;
      expect(
        _paragraph(DocxDocument.open(doc.save().bytes)).properties.tabs,
        stops,
      );
    });

    test('numbering sets and reads back', () {
      final DocxDocument doc = _open();
      _paragraph(doc).properties.numbering = DocxNumberingRef(3, level: 1);
      expect(
        _pPr(doc),
        '<w:numPr><w:ilvl w:val="1"/><w:numId w:val="3"/></w:numPr>',
      );
      final DocxNumberingRef read = _paragraph(
        DocxDocument.open(doc.save().bytes),
      ).properties.numbering!;
      expect(read, DocxNumberingRef(3, level: 1));
      expect(read.numId, 3);
      expect(read.level, 1);
      expect(
        _written(
          (DocxParagraphProperties p) => p.numbering = DocxNumberingRef(0),
        ),
        '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="0"/></w:numPr>',
      );
    });

    test('level 9 throws RangeError', () {
      expect(() => DocxNumberingRef(1, level: 9), throwsRangeError);
      expect(() => DocxNumberingRef(1, level: -1), throwsRangeError);
      expect(() => DocxNumberingRef(-1), throwsRangeError);
    });

    test('a member set to null is removed', () {
      final DocxDocument doc = _open('<w:keepNext/><w:jc w:val="left"/>');
      final DocxParagraphProperties p = _paragraph(doc).properties;
      p.alignment = null;
      expect(_pPr(doc), '<w:keepNext/>');
      p.keepWithNext = null;
      expect(_pPr(doc), '');
    });

    test('every member is written in schema order', () {
      final DocxDocument doc = _open();
      final DocxParagraphProperties p = _paragraph(doc).properties;
      p.outlineLevel = 1;
      p.alignment = DocxAlignment.left;
      p.indentation = DocxIndentation(leftPt: 1);
      p.spacing = DocxSpacing(afterPt: 1);
      p.tabs = <DocxTabStop>[DocxTabStop(1)];
      p.shading = const DocxShading();
      p.borders = DocxParagraphBorders(top: DocxBorder());
      p.numbering = DocxNumberingRef(1);
      p.widowControl = true;
      p.pageBreakBefore = true;
      p.keepLines = true;
      p.keepWithNext = true;
      p.style = 'A';
      final List<String> names = RegExp(
        r'<w:(\w+)',
      ).allMatches(_pPr(doc)).map((Match m) => m.group(1)!).toList();
      expect(
        names.where(
          (String n) => const <String>{
            'pStyle',
            'keepNext',
            'keepLines',
            'pageBreakBefore',
            'widowControl',
            'numPr',
            'pBdr',
            'shd',
            'tabs',
            'spacing',
            'ind',
            'jc',
            'outlineLvl',
          }.contains(n),
        ),
        <String>[
          'pStyle',
          'keepNext',
          'keepLines',
          'pageBreakBefore',
          'widowControl',
          'numPr',
          'pBdr',
          'shd',
          'tabs',
          'spacing',
          'ind',
          'jc',
          'outlineLvl',
        ],
      );
    });

    test('a new paragraph has empty properties and the same object', () {
      final DocxParagraph p = DocxParagraph();
      expect(identical(p.properties, p.properties), isTrue);
      expect(p.properties.alignment, isNull);
      expect(p.properties.tabs, isNull);
      expect(p.properties.numbering, isNull);
      expect(p.properties.borders, isNull);
    });
  });

  group('what a Word file keeps', () {
    test('setting alignment keeps pPr/rPr and sectPr in place', () {
      final DocxDocument doc = _open(
        '<w:pStyle w:val="A"/><w:spacing w:after="160"/>'
        '<w:rPr><w:b/></w:rPr>'
        '<w:sectPr><w:pgSz w:w="100"/></w:sectPr>',
      );
      _paragraph(doc).properties.alignment = DocxAlignment.right;
      expect(
        _pPr(doc),
        '<w:pStyle w:val="A"/><w:spacing w:after="160"/>'
        '<w:jc w:val="right"/><w:rPr><w:b/></w:rPr>'
        '<w:sectPr><w:pgSz w:w="100"/></w:sectPr>',
      );
    });

    test('the paragraph mark rPr is never typed', () {
      final DocxDocument doc = _open('<w:rPr><w:b/><w:sz w:val="40"/></w:rPr>');
      final DocxParagraphProperties p = _paragraph(doc).properties;
      expect(p.alignment, isNull);
      p.keepLines = true;
      expect(
        _pPr(doc),
        '<w:keepLines/><w:rPr><w:b/><w:sz w:val="40"/></w:rPr>',
      );
      // No member of the class exposes the paragraph mark's rPr.
      expect(
        DocxParagraphProperty.values.map((DocxParagraphProperty v) => v.name),
        isNot(contains('rPr')),
      );
    });

    test('w14 and kept children stay in place when one is set', () {
      final DocxDocument doc = _open(
        '<w:suppressAutoHyphens/><w14:x w14:val="1"/><w:contextualSpacing/>',
      );
      _paragraph(doc).properties.keepWithNext = true;
      expect(
        _pPr(doc),
        '<w:keepNext/><w:suppressAutoHyphens/><w14:x w14:val="1"/>'
        '<w:contextualSpacing/>',
      );
    });

    test('jc start reads start, jc lowKashida reads null and saves '
        'unchanged', () {
      expect(
        _paragraph(_open('<w:jc w:val="start"/>')).properties.alignment,
        DocxAlignment.start,
      );
      for (final String v in <String>[
        'lowKashida',
        'mediumKashida',
        'highKashida',
        'numTab',
        'thaiDistribute',
        'LEFT',
        '',
      ]) {
        final DocxDocument doc = _open('<w:jc w:val="$v"/>');
        expect(_paragraph(doc).properties.alignment, isNull, reason: v);
        expect(_pPr(doc), '<w:jc w:val="$v"/>', reason: v);
      }
    });

    test('ind left 1in and leftChars read null and save unchanged', () {
      for (final String ind in <String>[
        '<w:ind w:left="1in"/>',
        '<w:ind w:leftChars="100"/>',
        '<w:ind w:left="720" w:leftChars="100"/>',
        '<w:ind w:start="720"/>',
        '<w:ind w:end="720"/>',
        '<w:ind w:firstLine="1" w:hanging="1"/>',
        '<w:ind w:left="99999999999999999999"/>',
        '<w:ind w:left="100000"/>',
        '<w:ind w:firstLine="-5"/>',
      ]) {
        final DocxDocument doc = _open(ind);
        expect(_paragraph(doc).properties.indentation, isNull, reason: ind);
        expect(_pPr(doc), ind, reason: ind);
      }
      final DocxDocument ok = _open('<w:ind w:left="-720"/>');
      expect(_paragraph(ok).properties.indentation!.leftPt, -36);
    });

    test('spacing with Lines, a bad rule or number reads null and saves '
        'unchanged', () {
      for (final String s in <String>[
        '<w:spacing w:beforeLines="100"/>',
        '<w:spacing w:afterLines="100" w:after="20"/>',
        '<w:spacing w:line="240" w:lineRule="weird"/>',
        '<w:spacing w:line="abc"/>',
        '<w:spacing w:lineRule="auto"/>',
        '<w:spacing w:before="1in"/>',
        '<w:spacing w:line="0" w:lineRule="auto"/>',
        '<w:spacing w:beforeAutospacing="maybe"/>',
      ]) {
        final DocxDocument doc = _open(s);
        expect(_paragraph(doc).properties.spacing, isNull, reason: s);
        expect(_pPr(doc), s, reason: s);
      }
      final DocxDocument doc = _open(
        '<w:spacing w:before="240" w:beforeAutospacing="on" w:line="360"/>',
      );
      final DocxSpacing s = _paragraph(doc).properties.spacing!;
      expect(s.beforePt, 12);
      expect(s.beforeAuto, isTrue);
      expect(s.afterAuto, isFalse);
      expect(s.line, DocxLineSpacing.multiple(1.5));
    });

    test('borders, tabs and numPr the model cannot type read null and save '
        'unchanged', () {
      for (final String x in <String>[
        '<w:pBdr><w:top w:val="apples"/></w:pBdr>',
        '<w:pBdr><w:top w:val="single"/><w:top w:val="single"/></w:pBdr>',
        '<w:pBdr><w:other w:val="single"/></w:pBdr>',
        '<w:pBdr><w14:top w14:val="single"/></w:pBdr>',
        '<w:pBdr w:val="x"/>',
        '<w:tabs/>',
        '<w:tabs><w:tab w:val="right"/></w:tabs>',
        '<w:tabs><w:tab w:val="wide" w:pos="1"/></w:tabs>',
        '<w:tabs><w:tab w:val="left" w:pos="1" w:leader="x"/></w:tabs>',
        '<w:tabs><w:other w:val="left" w:pos="1"/></w:tabs>',
        '<w:numPr><w:ilvl w:val="1"/></w:numPr>',
        '<w:numPr><w:numId w:val="1"/><w:numberingChange w:original="x"/>'
            '</w:numPr>',
        '<w:numPr><w:numId w:val="1"/><w:ins w:id="1"/></w:numPr>',
        '<w:numPr><w:ilvl w:val="9"/><w:numId w:val="1"/></w:numPr>',
        '<w:numPr><w:ilvl w:val="1"/><w:numId w:val="-1"/></w:numPr>',
        '<w:numPr><w:numId w:val="abc"/></w:numPr>',
        '<w:numPr><w:numId w:val="1"/><w:numId w:val="2"/></w:numPr>',
        '<w:outlineLvl w:val="10"/>',
        '<w:outlineLvl w:val="x"/>',
      ]) {
        final DocxDocument doc = _open(x);
        final DocxParagraphProperties p = _paragraph(doc).properties;
        expect(p.borders, isNull, reason: x);
        expect(p.tabs, isNull, reason: x);
        expect(p.numbering, isNull, reason: x);
        expect(p.outlineLevel, isNull, reason: x);
        expect(_pPr(doc), x, reason: x);
      }
    });

    test('numPr without ilvl reads level 0', () {
      final DocxDocument doc = _open('<w:numPr><w:numId w:val="7"/></w:numPr>');
      expect(_paragraph(doc).properties.numbering, DocxNumberingRef(7));
    });

    test('clear removes an untyped child that setting null keeps', () {
      final DocxDocument doc = _open('<w:jc w:val="lowKashida"/>');
      final DocxParagraphProperties p = _paragraph(doc).properties;
      p.alignment = null;
      expect(_pPr(doc), '<w:jc w:val="lowKashida"/>');
      p.clear(DocxParagraphProperty.alignment);
      expect(_pPr(doc), '');
    });

    test('clear removes a typed child and keeps its neighbours', () {
      final DocxDocument doc = _open(
        '<w:keepNext/><w:ind w:left="1in"/><w:jc w:val="center"/>',
      );
      final DocxParagraphProperties p = _paragraph(doc).properties;
      p.clear(DocxParagraphProperty.indentation);
      p.clear(DocxParagraphProperty.numbering);
      expect(_pPr(doc), '<w:keepNext/><w:jc w:val="center"/>');
    });
  });

  group('edits', () {
    test('setting a value equal to the current one records nothing', () {
      final DocxDocument doc = _open(
        '<w:keepNext w:val="on"/><w:jc w:val="both"/>'
        '<w:ind w:left="720"/>'
        '<w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs>'
        '<w:spacing w:after="160" w:line="276"/>'
        '<w:numPr><w:numId w:val="3"/></w:numPr>',
      );
      final DocxParagraphProperties p = _paragraph(doc).properties;
      p.keepWithNext = true;
      p.alignment = DocxAlignment.justify;
      p.indentation = DocxIndentation(leftPt: 36);
      p.tabs = <DocxTabStop>[DocxTabStop(36)];
      p.spacing = DocxSpacing(afterPt: 8, line: DocxLineSpacing.multiple(1.15));
      p.numbering = DocxNumberingRef(3);
      p.keepLines = null;
      p.borders = null;
      p.tabs = p.tabs;
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(_pPr(doc), contains('w:val="on"'));
      expect(_pPr(doc), contains('<w:numPr><w:numId w:val="3"/></w:numPr>'));
    });

    test('an alignment set on a paragraph of an opened document reverts '
        'with the transaction', () {
      final DocxDocument doc = _open('<w:keepNext/>');
      final DocxParagraphProperties p = _paragraph(doc).properties;
      final ChangeSet set = changeLogOf(doc).transaction(() {
        p.alignment = DocxAlignment.center;
        p.tabs = <DocxTabStop>[DocxTabStop(10)];
      });
      expect(set.changes, hasLength(2));
      expect(
        _pPr(doc),
        '<w:keepNext/><w:tabs><w:tab w:val="left" w:pos="200"/></w:tabs>'
        '<w:jc w:val="center"/>',
      );
      changeLogOf(doc).revertSet(set);
      expect(_pPr(doc), '<w:keepNext/>');
      expect(p.alignment, isNull);
      changeLogOf(doc).reapplySet(set);
      expect(p.alignment, DocxAlignment.center);
    });

    test('an invalid value throws before anything changes', () {
      final DocxDocument doc = _open('<w:keepNext/>');
      final DocxParagraphProperties p = _paragraph(doc).properties;
      expect(() => p.style = '', throwsArgumentError);
      expect(() => p.outlineLevel = 10, throwsRangeError);
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(_pPr(doc), '<w:keepNext/>');
    });

    test('values compare by stored units', () {
      expect(
        DocxLineSpacing.multiple(1.16),
        DocxLineSpacing.multiple(278 / 240),
      );
      expect(
        DocxLineSpacing.multiple(1.16).hashCode,
        DocxLineSpacing.multiple(278 / 240).hashCode,
      );
      expect(DocxLineSpacing.exactly(12), isNot(DocxLineSpacing.atLeast(12)));
      expect(DocxIndentation(leftPt: 1.01), DocxIndentation(leftPt: 1));
      expect(DocxTabStop(1.01), DocxTabStop(1));
      expect(
        DocxParagraphBorders(top: DocxBorder()),
        DocxParagraphBorders(top: DocxBorder()),
      );
      expect(
        DocxParagraphBorders(top: DocxBorder()),
        isNot(DocxParagraphBorders(bottom: DocxBorder())),
      );
      expect(DocxSpacing(beforeAuto: true), isNot(DocxSpacing()));
    });
  });
}
