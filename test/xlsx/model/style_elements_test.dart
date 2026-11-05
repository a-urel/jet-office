import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/alignment.dart';
import 'package:jet_office/src/xlsx/border.dart';
import 'package:jet_office/src/xlsx/fill.dart';
import 'package:jet_office/src/xlsx/font.dart';
import 'package:jet_office/src/xlsx/model/style_elements.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// A reader on the first element of [xml], which gets the SpreadsheetML
/// namespace unless it declares its own.
XmlPullReader _on(String xml) {
  final String text = xml.contains('xmlns="')
      ? xml
      : xml.replaceFirstMapped(
          RegExp(r'^<([A-Za-z0-9:]+)'),
          (Match m) => '<${m[1]} xmlns="$_main"',
        );
  final XmlPullReader r = XmlPullReader(text);
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) break;
  }
  return r;
}

/// Asserts that [r] was left on the end of the element it read.
void _atEnd(XmlPullReader r) {
  expect(r.eventType, XmlEventType.endElement);
  expect(r.depth, 0);
}

T _read<T>(String xml, T Function(XmlPullReader) read) {
  final XmlPullReader r = _on(xml);
  final T value = read(r);
  _atEnd(r);
  return value;
}

ReadStyleValue<XlsxFont> _font(String xml) => _read(xml, readFont);
ReadStyleValue<XlsxFill> _fill(String xml) => _read(xml, readFill);
ReadStyleValue<XlsxBorder> _border(String xml) => _read(xml, readBorder);
ReadStyleValue<XlsxColor?> _color(String xml) => _read(xml, readColor);

String _render(void Function(XmlWriter) write) {
  final StringBuffer b = StringBuffer();
  write(XmlWriter(b));
  return b.toString();
}

void main() {
  group('writer elements read back exactly', () {
    test('every font, fill and border of m2_styles', () {
      final Fixture f = allFixtures().firstWhere(
        (Fixture f) => f.name == 'm2_styles',
      );
      final Archive zip = ZipDecoder().decodeBytes(f.build());
      final String xml = utf8.decode(
        zip.files
                .firstWhere((ArchiveFile a) => a.name.endsWith('styles.xml'))
                .content
            as List<int>,
      );
      final XmlPullReader r = XmlPullReader(xml);
      var fonts = 0, fills = 0, borders = 0;
      while (r.next()) {
        if (r.eventType != XmlEventType.startElement) continue;
        final String name = r.localName;
        if (name != 'font' && name != 'fill' && name != 'border') continue;
        if (r.depth != 3) continue;
        final int start = r.eventStart;
        final ReadStyleValue<Object> v = switch (name) {
          'font' => readFont(r),
          'fill' => readFill(r),
          _ => readBorder(r),
        };
        final String source = r.sourceText(start, r.eventEnd);
        expect(v.problem, isNull, reason: source);
        expect(v.exact, isTrue, reason: source);
        final String written = _render(
          (XmlWriter w) => switch (v.value) {
            final XlsxFont x => writeFontXml(w, x),
            final XlsxFill x => writeFillXml(w, x),
            final XlsxBorder x => writeBorderXml(w, x),
            _ => throw StateError('unreachable'),
          },
        );
        expect(compareXml(name, source, written), isEmpty, reason: source);
        switch (name) {
          case 'font':
            fonts++;
          case 'fill':
            fills++;
          default:
            borders++;
        }
      }
      expect(fonts, greaterThan(8));
      expect(fills, greaterThan(20));
      expect(borders, greaterThan(14));
    });

    test('values survive write then read', () {
      const List<XlsxFont> fonts = <XlsxFont>[
        XlsxFont(name: 'Calibri', size: 11),
        XlsxFont(
          name: 'Arial',
          size: 12.5,
          color: XlsxColor.theme(4, tint: -0.25),
          bold: true,
          italic: true,
          underline: XlsxUnderline.doubleLine,
          strike: true,
          script: XlsxFontScript.subscript,
          outline: true,
          shadow: true,
          condense: true,
          extend: true,
          family: 2,
          charset: 1,
          scheme: XlsxFontScheme.minor,
        ),
        XlsxFont(
          size: 9,
          color: XlsxColor.argb(0xFF1F4E79),
          underline: XlsxUnderline.singleAccounting,
        ),
        XlsxFont(underline: XlsxUnderline.single, color: XlsxColor.auto),
        XlsxFont(color: XlsxColor.indexed(10)),
      ];
      for (final XlsxFont font in fonts) {
        final ReadStyleValue<XlsxFont> v = _font(
          _render((XmlWriter w) => writeFontXml(w, font)),
        );
        expect(v.value, font);
        expect(v.exact, isTrue);
        expect(v.problem, isNull);
      }
      final List<XlsxFill> fills = <XlsxFill>[
        const XlsxFill.solid(XlsxColor.rgb(0xFFFF00)),
        const XlsxFill.pattern(XlsxPatternType.none),
        const XlsxFill.pattern(
          XlsxPatternType.gray125,
          foreground: XlsxColor.indexed(64),
          background: XlsxColor.auto,
        ),
        XlsxGradientFill.linear(
          degree: 45.5,
          stops: const <XlsxGradientStop>[
            XlsxGradientStop(0, XlsxColor.rgb(0)),
            XlsxGradientStop(0.5, XlsxColor.theme(1)),
            XlsxGradientStop(1, XlsxColor.rgb(0xFFFFFF)),
          ],
        ),
        XlsxGradientFill.path(
          left: 0.25,
          right: 0.75,
          top: 0.25,
          bottom: 0.75,
          stops: const <XlsxGradientStop>[
            XlsxGradientStop(0, XlsxColor.rgb(0)),
            XlsxGradientStop(1, XlsxColor.rgb(0xFFFFFF)),
          ],
        ),
      ];
      for (final XlsxFill fill in fills) {
        final ReadStyleValue<XlsxFill> v = _fill(
          _render((XmlWriter w) => writeFillXml(w, fill)),
        );
        expect(v.value, fill);
        expect(v.exact, isTrue, reason: '$fill');
        expect(v.problem, isNull);
      }
      const List<XlsxBorder> borders = <XlsxBorder>[
        XlsxBorder(),
        XlsxBorder.all(
          XlsxBorderSide(
            style: XlsxBorderStyle.doubleLine,
            color: XlsxColor.rgb(0x112233),
          ),
        ),
        XlsxBorder(
          diagonal: XlsxBorderSide(style: XlsxBorderStyle.hair),
          diagonalUp: true,
          diagonalDown: true,
          vertical: XlsxBorderSide(style: XlsxBorderStyle.thin),
          horizontal: XlsxBorderSide(style: XlsxBorderStyle.mediumDashDotDot),
          outline: false,
          left: XlsxBorderSide(style: XlsxBorderStyle.slantDashDot),
        ),
      ];
      for (final XlsxBorder border in borders) {
        final ReadStyleValue<XlsxBorder> v = _border(
          _render((XmlWriter w) => writeBorderXml(w, border)),
        );
        expect(v.value, border);
        expect(v.exact, isTrue, reason: '$border');
        expect(v.problem, isNull);
      }
    });

    test('alignment and protection of the writer read back exactly', () {
      const XlsxAlignment a = XlsxAlignment(
        horizontal: XlsxHorizontalAlignment.centerContinuous,
        vertical: XlsxVerticalAlignment.distributed,
        wrapText: true,
        indent: 3,
        textRotation: 255,
        shrinkToFit: true,
        readingOrder: XlsxReadingOrder.rightToLeft,
        justifyLastLine: true,
      );
      const XlsxProtection p = XlsxProtection(locked: false, hidden: true);
      final String xf =
          '<xf numFmtId="164" fontId="2" fillId="3" borderId="4" xfId="0" '
          'applyNumberFormat="1" applyAlignment="1" applyProtection="1">'
          '${alignmentXml(a)}${protectionXml(p)}</xf>';
      final xf0 = _read(xf, readXf);
      expect(xf0.numFmtId, 164);
      expect(xf0.fontId, 2);
      expect(xf0.fillId, 3);
      expect(xf0.borderId, 4);
      expect(xf0.xfId, 0);
      expect(xf0.alignment, (value: a, exact: true, problem: null));
      expect(xf0.protection, (value: p, exact: true, problem: null));
      expect(xf0.exact, isTrue);
    });
  });

  group('colours read every form', () {
    test('rgb', () {
      expect(_color('<color rgb="FF1F4E79"/>'), (
        value: const XlsxColor.argb(0xFF1F4E79),
        exact: true,
        problem: null,
      ));
    });

    test('theme with tint', () {
      expect(_color('<color theme="4" tint="-0.25"/>'), (
        value: const XlsxColor.theme(4, tint: -0.25),
        exact: true,
        problem: null,
      ));
      expect(_color('<color theme="4"/>').value, const XlsxColor.theme(4));
    });

    test('indexed and auto', () {
      expect(_color('<color indexed="10"/>'), (
        value: const XlsxColor.indexed(10),
        exact: true,
        problem: null,
      ));
      expect(_color('<color auto="1"/>'), (
        value: XlsxColor.auto,
        exact: true,
        problem: null,
      ));
    });

    test('spellings the writer does not use are read but inexact', () {
      for (final String xml in <String>[
        '<color rgb="ff1f4e79"/>',
        '<color rgb="1F4E79"/>',
        '<color theme="4" tint="0"/>',
        '<color theme="4" tint="0.50"/>',
        '<color indexed="10" tint="0.5"/>',
        '<color auto="true"/>',
        '<color rgb="FF000000" theme="1"/>',
      ]) {
        final ReadStyleValue<XlsxColor?> v = _color(xml);
        expect(v.value, isNotNull, reason: xml);
        expect(v.exact, isFalse, reason: xml);
        expect(v.problem, isNull, reason: xml);
      }
      expect(
        _color('<color rgb="1F4E79"/>').value,
        const XlsxColor.rgb(0x1F4E79),
      );
    });

    test('an element with no colour is null and inexact', () {
      expect(_color('<color/>'), (value: null, exact: false, problem: null));
      expect(_color('<color auto="0"/>').value, isNull);
    });
  });

  group('unknown children make an entry inexact', () {
    test('a font with an unknown child still reads its typed part', () {
      final ReadStyleValue<XlsxFont> v = _font(
        '<font xmlns="$_main" xmlns:x14="urn:x14"><b/><x14:foo/>'
        '<sz val="12"/></font>',
      );
      expect(v.exact, isFalse);
      expect(v.problem, isNull);
      expect(v.value, const XlsxFont(bold: true, size: 12));
    });

    test('a font with an unknown attribute or a main-namespace stranger', () {
      expect(_font('<font x="1"><b/></font>').exact, isFalse);
      expect(_font('<font><b/><blink/></font>').exact, isFalse);
      expect(_font('<font><b/><b/></font>').exact, isFalse);
      expect(_font('<font><sz val="11"/><b/></font>').exact, isFalse);
    });

    test('values the writer would spell differently', () {
      for (final String xml in <String>[
        '<font><b val="1"/></font>',
        '<font><b val="0"/></font>',
        '<font><sz val="11.0"/></font>',
        '<font><u val="single"/></font>',
        '<font><vertAlign val="baseline"/></font>',
        '<font><scheme val="none"/></font>',
      ]) {
        final ReadStyleValue<XlsxFont> v = _font(xml);
        expect(v.exact, isFalse, reason: xml);
        expect(v.problem, isNull, reason: xml);
      }
      expect(_font('<font><b val="0"/></font>').value.bold, isFalse);
      expect(
        _font('<font><u val="single"/></font>').value.underline,
        XlsxUnderline.single,
      );
    });

    test('an xf is inexact with xfId, quotePrefix or a foreign attribute', () {
      const String plain =
          '<xf numFmtId="1" fontId="0" fillId="0" borderId="0"/>';
      expect(_read(plain, readXf).exact, isTrue);
      final named = _read(
        '<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="3"/>',
        readXf,
      );
      expect(named.exact, isFalse);
      expect(named.xfId, 3);
      expect(
        _read('<xf numFmtId="1" quotePrefix="1"/>', readXf).exact,
        isFalse,
      );
      expect(
        _read(
          '<xf xmlns="$_main" xmlns:x14ac="urn:x14ac" x14ac:dyDescent="0.25"/>',
          readXf,
        ).exact,
        isFalse,
      );
      expect(_read('<xf><extLst/></xf>', readXf).exact, isFalse);
      expect(_read('<xf xfId="0"/>', readXf).xfId, 0);
    });

    test('an xf with an inexact alignment is inexact', () {
      final xf = _read(
        '<xf numFmtId="0"><alignment horizontal="general"/></xf>',
        readXf,
      );
      expect(xf.exact, isFalse);
      expect(xf.alignment.exact, isFalse);
      expect(
        xf.alignment.value,
        const XlsxAlignment(horizontal: XlsxHorizontalAlignment.general),
      );
    });

    test('a border with a missing side, an extra attribute or a bad order', () {
      expect(_border('<border/>').exact, isFalse);
      expect(
        _border(
          '<border><right/><left/><top/><bottom/><diagonal/></border>',
        ).exact,
        isFalse,
      );
      expect(
        _border(
          '<border><left/><right/><top/><bottom/><diagonal/></border>',
        ).exact,
        isTrue,
      );
      expect(
        _border(
          '<border><left/><right/><top/><bottom/><diagonal style="thin"/>'
          '</border>',
        ).exact,
        isFalse,
      );
    });

    test('a gradient spelled with defaults is inexact', () {
      const String stops =
          '<stop position="0"><color rgb="FF000000"/></stop>'
          '<stop position="1"><color rgb="FFFFFFFF"/></stop>';
      expect(
        _fill(
          '<fill><gradientFill type="linear">$stops</gradientFill></fill>',
        ).exact,
        isFalse,
      );
      expect(
        _fill('<fill><gradientFill>$stops</gradientFill></fill>').exact,
        isTrue,
      );
      expect(_fill('<fill><patternFill/></fill>').exact, isFalse);
    });
  });

  group('bad values are problems, not throws', () {
    test('a font size that is not a number', () {
      final ReadStyleValue<XlsxFont> v = _font(
        '<font><b/><sz val="abc"/></font>',
      );
      expect(v.value, const XlsxFont(bold: true));
      expect(v.problem, isNotNull);
      expect(v.exact, isFalse);
    });

    test('a font size, family or charset outside the limits', () {
      for (final String xml in <String>[
        '<font><sz val="0"/></font>',
        '<font><sz val="500"/></font>',
        '<font><sz val="1e400"/></font>',
        '<font><family val="15"/></font>',
        '<font><charset val="256"/></font>',
        '<font><name val=""/></font>',
        '<font><u val="wavy"/></font>',
      ]) {
        final ReadStyleValue<XlsxFont> v = _font(xml);
        expect(v.value, const XlsxFont(), reason: xml);
        expect(v.problem, isNotNull, reason: xml);
      }
    });

    test('an unknown pattern', () {
      final ReadStyleValue<XlsxFill> v = _fill(
        '<fill><patternFill patternType="zigzag"/></fill>',
      );
      expect(v.value, const XlsxFill.pattern(XlsxPatternType.none));
      expect(v.problem, isNotNull);
      expect(v.exact, isFalse);
    });

    test('a fill with a gradient of one stop, or none at all', () {
      final ReadStyleValue<XlsxFill> one = _fill(
        '<fill><gradientFill><stop position="0"><color rgb="FF000000"/></stop>'
        '</gradientFill></fill>',
      );
      expect(one.value, const XlsxFill.pattern(XlsxPatternType.none));
      expect(one.problem, isNotNull);
      expect(_fill('<fill/>').problem, isNotNull);
    });

    test(
      'theme colour 99, a tint outside -1..1 and a tint that is not finite',
      () {
        for (final String xml in <String>[
          '<color theme="99"/>',
          '<color theme="4" tint="2"/>',
          '<color theme="4" tint="NaN"/>',
          '<color theme="4" tint="Infinity"/>',
          '<color theme="4" tint="x"/>',
          '<color indexed="66"/>',
          '<color rgb="12"/>',
          '<color auto="maybe"/>',
        ]) {
          final ReadStyleValue<XlsxColor?> v = _color(xml);
          expect(v.value, isNull, reason: xml);
          expect(v.problem, isNotNull, reason: xml);
          expect(v.exact, isFalse, reason: xml);
        }
      },
    );

    test('a bad colour inside a font, a fill and a border', () {
      expect(_font('<font><color theme="99"/></font>').problem, isNotNull);
      expect(
        _fill(
          '<fill><patternFill patternType="solid"><fgColor theme="99"/>'
          '</patternFill></fill>',
        ).problem,
        isNotNull,
      );
      final ReadStyleValue<XlsxBorder> b = _border(
        '<border><left style="thin"><color indexed="99"/></left><right/><top/>'
        '<bottom/><diagonal/></border>',
      );
      expect(b.problem, isNotNull);
      expect(b.value.left, const XlsxBorderSide(style: XlsxBorderStyle.thin));
    });

    test('a border style, a flag and alignment values', () {
      expect(
        _border('<border><left style="wavy"/></border>').problem,
        isNotNull,
      );
      expect(_border('<border diagonalUp="x"/>').problem, isNotNull);
      for (final String xml in <String>[
        '<xf><alignment horizontal="sideways"/></xf>',
        '<xf><alignment indent="999"/></xf>',
        '<xf><alignment textRotation="181"/></xf>',
        '<xf><alignment readingOrder="7"/></xf>',
        '<xf><alignment wrapText="maybe"/></xf>',
        '<xf><protection hidden="maybe"/></xf>',
      ]) {
        final xf = _read(xml, readXf);
        final problem = xf.alignment.problem ?? xf.protection.problem;
        expect(problem, isNotNull, reason: xml);
        expect(xf.exact, isFalse, reason: xml);
      }
    });

    test('an unreadable id is 0 and inexact', () {
      final xf = _read('<xf numFmtId="abc" fontId="-1"/>', readXf);
      expect(xf.numFmtId, 0);
      expect(xf.fontId, 0);
      expect(xf.exact, isFalse);
    });
  });
}
