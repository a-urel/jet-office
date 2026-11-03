// Tests the run properties of the DOCX model: each member sets, reads back
// and writes the element the plan names, the complex-script variants and
// other children of a Word file stay in place, values a file holds that the
// model cannot type read null and save unchanged, and a set is one change
// that reverts with its transaction. They build documents in memory, so
// they run on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';

/// A document whose only run has the `w:rPr` holding [rPr] (none when it is
/// null).
DocxDocument _open([String? rPr]) => DocxDocument.open(
  buildDocx(
    document:
        '<w:document xmlns:w="${Ns.w}" '
        'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">'
        '<w:body><w:p><w:r>${rPr == null ? '' : '<w:rPr>$rPr</w:rPr>'}'
        '<w:t>a</w:t></w:r></w:p></w:body></w:document>',
  ),
);

DocxRun _run(DocxDocument doc) =>
    (doc.body.blocks.single as DocxParagraph).inlines.single as DocxRun;

/// The `w:rPr` of the saved document, as written.
String _rPr(DocxDocument doc) {
  final String xml = readXlsx(doc.save().bytes)['word/document.xml']!;
  final RegExpMatch? m = RegExp(r'<w:rPr>(.*?)</w:rPr>').firstMatch(xml);
  return m == null ? '' : m.group(1)!;
}

/// Sets a property on a new run and returns the `w:rPr` it saves.
String _written(void Function(DocxRunProperties p) set) {
  final DocxDocument doc = _open();
  set(_run(doc).properties);
  return _rPr(doc);
}

void main() {
  group('members', () {
    test('style sets and reads back', () {
      expect(
        _written((DocxRunProperties p) => p.style = 'Strong'),
        '<w:rStyle w:val="Strong"/>',
      );
    });

    test('fonts sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.fonts = DocxFonts(
        ascii: 'Arial',
        eastAsia: 'MS Mincho',
      );
      expect(_rPr(doc), '<w:rFonts w:ascii="Arial" w:eastAsia="MS Mincho"/>');
      final DocxFonts read = _run(
        DocxDocument.open(doc.save().bytes),
      ).properties.fonts!;
      expect(read.ascii, 'Arial');
      expect(read.hAnsi, isNull);
      expect(read.eastAsia, 'MS Mincho');
      expect(read.asciiTheme, isNull);
      expect(
        _written((DocxRunProperties p) => p.fonts = DocxFonts.all('X')),
        ('<w:rFonts w:ascii="X" w:hAnsi="X" w:eastAsia="X"/>'),
      );
    });

    test('a font name that is empty or holds a forbidden character throws', () {
      expect(() => DocxFonts(ascii: ''), throwsArgumentError);
      expect(() => DocxFonts.all('a\u0001b'), throwsArgumentError);
      expect(() => DocxFonts(hAnsi: '￾'), throwsArgumentError);
    });

    test('bold sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.bold = true;
      expect(_rPr(doc), '<w:b/>');
      expect(_run(doc).properties.bold, isTrue);
      expect(
        _written((DocxRunProperties p) => p.bold = false),
        ('<w:b w:val="0"/>'),
      );
    });

    test('italic, caps, smallCaps, strike and doubleStrike write', () {
      final DocxDocument doc = _open();
      final DocxRunProperties p = _run(doc).properties;
      p
        ..italic = true
        ..caps = true
        ..smallCaps = false
        ..strike = true
        ..doubleStrike = true;
      expect(p.italic, isTrue);
      expect(p.caps, isTrue);
      expect(p.smallCaps, isFalse);
      expect(p.strike, isTrue);
      expect(p.doubleStrike, isTrue);
      expect(
        _rPr(doc),
        '<w:i/><w:caps/><w:smallCaps w:val="0"/><w:strike/><w:dstrike/>',
      );
      final DocxRunProperties q = _run(
        DocxDocument.open(doc.save().bytes),
      ).properties;
      expect(q.smallCaps, isFalse);
      expect(q.doubleStrike, isTrue);
    });

    test('color sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.color = DocxColor.rgb('ff0000');
      expect(_rPr(doc), '<w:color w:val="FF0000"/>');
      expect(_run(doc).properties.color, DocxColor.rgb('FF0000'));
    });

    test('characterSpacingPt sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.characterSpacingPt = 1.5;
      expect(_rPr(doc), '<w:spacing w:val="30"/>');
      expect(_run(doc).properties.characterSpacingPt, 1.5);
      expect(
        _written((DocxRunProperties p) => p.characterSpacingPt = -0.25),
        '<w:spacing w:val="-5"/>',
      );
    });

    test('characterSpacingPt out of range throws RangeError', () {
      final DocxRunProperties p = _run(_open()).properties;
      expect(() => p.characterSpacingPt = 1585, throwsRangeError);
      expect(() => p.characterSpacingPt = -1585, throwsRangeError);
      expect(() => p.characterSpacingPt = double.nan, throwsArgumentError);
      p.characterSpacingPt = 1584;
      expect(p.characterSpacingPt, 1584);
    });

    test('sizePt sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.sizePt = 10.5;
      expect(_rPr(doc), '<w:sz w:val="21"/>');
      expect(_run(doc).properties.sizePt, 10.5);
    });

    test('sizePt 0.5 and 1638.5 throw RangeError', () {
      final DocxRunProperties p = _run(_open()).properties;
      expect(() => p.sizePt = 0.5, throwsRangeError);
      expect(() => p.sizePt = 1638.5, throwsRangeError);
      expect(() => p.sizePt = double.infinity, throwsArgumentError);
      p.sizePt = 1;
      expect(p.sizePt, 1);
      p.sizePt = 1638;
      expect(p.sizePt, 1638);
    });

    test('sizePt 11.3 reads back 11.5', () {
      final DocxRunProperties p = _run(_open()).properties;
      p.sizePt = 11.3;
      expect(p.sizePt, 11.5);
    });

    test('highlight sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.highlight = DocxHighlight.darkYellow;
      expect(_rPr(doc), '<w:highlight w:val="darkYellow"/>');
      expect(_run(doc).properties.highlight, DocxHighlight.darkYellow);
      expect(DocxHighlight.values, hasLength(17));
    });

    test('underline sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.underline = DocxUnderline(
        DocxUnderlineStyle.wavyHeavy,
        color: DocxColor.rgb('00ff00'),
      );
      expect(_rPr(doc), '<w:u w:val="wavyHeavy" w:color="00FF00"/>');
      expect(
        _run(doc).properties.underline,
        DocxUnderline(
          DocxUnderlineStyle.wavyHeavy,
          color: DocxColor.rgb('00FF00'),
        ),
      );
      expect(
        _written(
          (DocxRunProperties p) =>
              p.underline = const DocxUnderline(DocxUnderlineStyle.single),
        ),
        '<w:u w:val="single"/>',
      );
      expect(DocxUnderlineStyle.values, hasLength(18));
    });

    test('shading sets and reads back', () {
      final DocxDocument doc = _open();
      final DocxShading shading = DocxShading(
        pattern: DocxShadingPattern.clear,
        fill: DocxColor.rgb('FFFF00'),
      );
      _run(doc).properties.shading = shading;
      expect(_rPr(doc), '<w:shd w:val="clear" w:fill="FFFF00"/>');
      expect(_run(doc).properties.shading, shading);
    });

    test('verticalAlign sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.verticalAlign = DocxVerticalAlign.superscript;
      expect(_rPr(doc), '<w:vertAlign w:val="superscript"/>');
      expect(_run(doc).properties.verticalAlign, DocxVerticalAlign.superscript);
    });

    test('language sets and reads back', () {
      final DocxDocument doc = _open();
      _run(doc).properties.language = 'tr-TR';
      expect(_rPr(doc), '<w:lang w:val="tr-TR"/>');
      expect(_run(doc).properties.language, 'tr-TR');
    });

    test('language that is not a language tag throws ArgumentError', () {
      final DocxRunProperties p = _run(_open()).properties;
      for (final String bad in <String>['', 't', 'tr_TR', 'tr-', 'x y']) {
        expect(() => p.language = bad, throwsArgumentError, reason: bad);
      }
      p.language = 'de';
      p.language = 'zh-Hant-TW';
    });

    test('a member set to null is removed', () {
      final DocxDocument doc = _open('<w:b/><w:i/>');
      _run(doc).properties.bold = null;
      expect(_rPr(doc), '<w:i/>');
    });

    test('every member is written in schema order', () {
      final DocxDocument doc = _open();
      final DocxRunProperties p = _run(doc).properties;
      p
        ..language = 'en'
        ..verticalAlign = DocxVerticalAlign.subscript
        ..shading = const DocxShading(pattern: DocxShadingPattern.clear)
        ..underline = const DocxUnderline(DocxUnderlineStyle.single)
        ..highlight = DocxHighlight.red
        ..sizePt = 12
        ..characterSpacingPt = 1
        ..color = DocxColor.auto
        ..doubleStrike = true
        ..strike = true
        ..smallCaps = true
        ..caps = true
        ..italic = true
        ..bold = true
        ..fonts = DocxFonts.all('A')
        ..style = 'S';
      final List<String> names = <String>[
        for (final RegExpMatch m in RegExp(r'<w:(\w+)').allMatches(_rPr(doc)))
          m.group(1)!,
      ];
      expect(names, <String>[
        'rStyle',
        'rFonts',
        'b',
        'i',
        'caps',
        'smallCaps',
        'strike',
        'dstrike',
        'color',
        'spacing',
        'sz',
        'highlight',
        'u',
        'shd',
        'vertAlign',
        'lang',
      ]);
    });

    test('a new run has empty properties and the same object each call', () {
      final DocxRun run = DocxRun('x');
      expect(identical(run.properties, run.properties), isTrue);
      expect(run.properties.bold, isNull);
      run.style = 'Strong';
      expect(run.properties.style, 'Strong');
      run.properties.style = 'Emph';
      expect(run.style, 'Emph');
    });
  });

  group('what a Word file keeps', () {
    test('setting bold keeps bCs, setting sizePt keeps szCs', () {
      final DocxDocument doc = _open('<w:bCs/><w:szCs w:val="24"/>');
      _run(doc).properties
        ..bold = true
        ..sizePt = 11;
      expect(_rPr(doc), '<w:b/><w:bCs/><w:sz w:val="22"/><w:szCs w:val="24"/>');
    });

    test('setting fonts keeps cs, cstheme and hint and drops asciiTheme', () {
      final DocxDocument doc = _open(
        '<w:rFonts w:asciiTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi" '
        'w:cstheme="minorBidi"/>',
      );
      final DocxFonts read = _run(doc).properties.fonts!;
      expect(read.asciiTheme, 'minorHAnsi');
      expect(read.hAnsiTheme, 'minorHAnsi');
      expect(read.eastAsiaTheme, isNull);
      _run(doc).properties.fonts = DocxFonts.all('Arial');
      expect(
        _rPr(doc),
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" '
        'w:cstheme="minorBidi"/>',
      );
    });

    test('a Word file with cs, cstheme and hint reads its fonts', () {
      final DocxDocument doc = _open(
        '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Arial" '
        'w:hint="eastAsia" w:cstheme="minorBidi"/>',
      );
      final DocxFonts fonts = _run(doc).properties.fonts!;
      expect(fonts.ascii, 'Calibri');
      expect(fonts.hAnsi, 'Calibri');
      _run(doc).properties.fonts = DocxFonts(ascii: 'Arial');
      expect(
        _rPr(doc),
        '<w:rFonts w:ascii="Arial" w:cs="Arial" w:hint="eastAsia" '
        'w:cstheme="minorBidi"/>',
      );
    });

    test('setting fonts keeps an attribute of another namespace', () {
      final DocxDocument doc = _open('<w:rFonts w:ascii="A" w14:x="1"/>');
      expect(_run(doc).properties.fonts?.ascii, 'A');
      _run(doc).properties.fonts = DocxFonts(ascii: 'B');
      expect(_rPr(doc), contains('w14:x="1"'));
      expect(_rPr(doc), contains('w:ascii="B"'));
      expect(
        XmlDocument.parse(
          readXlsx(doc.save().bytes)['word/document.xml']!,
        ).rootElement.name.local,
        'document',
      );
    });

    test('setting language keeps eastAsia and bidi', () {
      final DocxDocument doc = _open(
        '<w:lang w:val="en-US" w:eastAsia="ja-JP" w:bidi="ar-SA"/>',
      );
      expect(_run(doc).properties.language, 'en-US');
      _run(doc).properties.language = 'tr-TR';
      expect(
        _rPr(doc),
        '<w:lang w:val="tr-TR" w:eastAsia="ja-JP" w:bidi="ar-SA"/>',
      );
    });

    test('w:lang with only eastAsia reads language null', () {
      final DocxDocument doc = _open('<w:lang w:eastAsia="ja-JP"/>');
      expect(_run(doc).properties.language, isNull);
      _run(doc).properties.language = 'tr';
      expect(_rPr(doc), '<w:lang w:val="tr" w:eastAsia="ja-JP"/>');
    });

    test('a w14:ligatures child stays after kern when bold is set', () {
      final DocxDocument doc = _open(
        '<w:kern w:val="2"/><w14:ligatures w14:val="standard"/>',
      );
      _run(doc).properties.bold = true;
      expect(
        _rPr(doc),
        '<w:b/><w:kern w:val="2"/><w14:ligatures w14:val="standard"/>',
      );
    });

    test('sz abc, sz of twenty digits, b maybe and two w:b read null and '
        'save unchanged', () {
      for (final String rPr in <String>[
        '<w:sz w:val="abc"/>',
        '<w:sz w:val="99999999999999999999"/>',
        '<w:sz w:val="1in"/>',
        '<w:b w:val="maybe"/>',
        '<w:b/><w:b w:val="0"/>',
        '<w:color w:val="red"/>',
        '<w:highlight w:val="orange"/>',
        '<w:vertAlign w:val="up"/>',
        '<w:lang w:val="not a tag"/>',
      ]) {
        final DocxDocument doc = _open(rPr);
        final DocxRunProperties p = _run(doc).properties;
        expect(p.sizePt, isNull, reason: rPr);
        expect(p.bold, isNull, reason: rPr);
        expect(p.color, isNull, reason: rPr);
        expect(p.highlight, isNull, reason: rPr);
        expect(p.verticalAlign, isNull, reason: rPr);
        expect(p.language, isNull, reason: rPr);
        expect(_rPr(doc), rPr);
      }
    });

    test('b on reads true and survives until bold is set', () {
      final DocxDocument doc = _open('<w:b w:val="on"/>');
      expect(_run(doc).properties.bold, isTrue);
      _run(doc).properties.bold = true;
      expect(_rPr(doc), '<w:b w:val="on"/>');
      _run(doc).properties.bold = false;
      expect(_rPr(doc), '<w:b w:val="0"/>');
    });

    test('clear removes an untyped child that setting null keeps', () {
      final DocxDocument doc = _open('<w:sz w:val="1in"/><w:i/>');
      final DocxRunProperties p = _run(doc).properties;
      p.sizePt = null;
      expect(_rPr(doc), '<w:i/><w:sz w:val="1in"/>');
      p.clear(DocxRunProperty.sizePt);
      expect(_rPr(doc), '<w:i/>');
      p.clear(DocxRunProperty.sizePt);
      p.clear(DocxRunProperty.bold);
      expect(_rPr(doc), '<w:i/>');
    });

    test('clear removes a typed child too', () {
      final DocxDocument doc = _open('<w:b/><w:i/>');
      _run(doc).properties.clear(DocxRunProperty.bold);
      expect(_rPr(doc), '<w:i/>');
      expect(_run(doc).properties.bold, isNull);
    });
  });

  group('edits', () {
    test('setting a value equal to the current one records nothing', () {
      final DocxDocument doc = _open(
        '<w:b w:val="on"/><w:sz w:val="22"/><w:color w:val="ff0000"/>',
      );
      final DocxRunProperties p = _run(doc).properties;
      p.bold = true;
      p.sizePt = 11;
      p.color = DocxColor.rgb('FF0000');
      p.italic = null;
      p.fonts = null;
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(_rPr(doc), contains('w:val="on"'));
      expect(_rPr(doc), contains('w:val="ff0000"'));
    });

    test('a bold set on a run of an opened document reverts with the '
        'transaction', () {
      final DocxDocument doc = _open('<w:i/>');
      final DocxRunProperties p = _run(doc).properties;
      final ChangeSet set = changeLogOf(doc).transaction(() {
        p.bold = true;
        p.sizePt = 9;
      });
      expect(set.changes, hasLength(2));
      expect(_rPr(doc), '<w:b/><w:i/><w:sz w:val="18"/>');
      changeLogOf(doc).revertSet(set);
      expect(_rPr(doc), '<w:i/>');
      expect(p.bold, isNull);
      changeLogOf(doc).reapplySet(set);
      expect(_rPr(doc), '<w:b/><w:i/><w:sz w:val="18"/>');
    });

    test('an invalid value throws before anything changes', () {
      final DocxDocument doc = _open('<w:i/>');
      final DocxRunProperties p = _run(doc).properties;
      expect(() => p.sizePt = 0, throwsRangeError);
      expect(() => p.style = '', throwsArgumentError);
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(_rPr(doc), '<w:i/>');
    });
  });
}
