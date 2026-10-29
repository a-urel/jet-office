import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/format/builtin_formats.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String _stylesXml(StyleRegistry r) {
  final StringBuffer out = StringBuffer();
  r.writeStylesXml(XmlWriter(out));
  return out.toString();
}

String _dxfs(StyleRegistry r) {
  final String xml = _stylesXml(r);
  final int start = xml.indexOf('<dxfs');
  final int end = xml.indexOf('<tableStyles');
  return xml.substring(start, end);
}

void main() {
  final XlsxStyle red = XlsxStyle(
    font: XlsxFont(bold: true, color: XlsxColor.hex('9C0006')),
    fill: XlsxFill.solid(XlsxColor.hex('FFC7CE')),
  );

  test('a dxf writes only what is set, solid fill as bgColor', () {
    final StyleRegistry r = StyleRegistry();
    expect(r.dxfIdFor(red), 0);
    expect(
      _dxfs(r),
      '<dxfs count="1"><dxf><font><b/><color rgb="FF9C0006"/></font>'
      '<fill><patternFill><bgColor rgb="FFFFC7CE"/></patternFill></fill>'
      '</dxf></dxfs>',
    );
  });

  test('no dxf writes the empty table', () {
    expect(_dxfs(StyleRegistry()), '<dxfs count="0"/>');
  });

  test('an empty style is an empty dxf', () {
    final StyleRegistry r = StyleRegistry();
    expect(r.dxfIdFor(const XlsxStyle()), 0);
    expect(_dxfs(r), '<dxfs count="1"><dxf/></dxfs>');
  });

  test('a non-solid pattern is written as in cellXfs', () {
    final StyleRegistry r = StyleRegistry()
      ..dxfIdFor(
        XlsxStyle(
          fill: XlsxFill.pattern(
            XlsxPatternType.darkGrid,
            foreground: XlsxColor.hex('FF0000'),
            background: XlsxColor.hex('00FF00'),
          ),
        ),
      );
    expect(
      _dxfs(r),
      contains(
        '<fill><patternFill patternType="darkGrid">'
        '<fgColor rgb="FFFF0000"/><bgColor rgb="FF00FF00"/>'
        '</patternFill></fill>',
      ),
    );
  });

  test('a gradient fill is allowed', () {
    final StyleRegistry r = StyleRegistry();
    r.dxfIdFor(
      XlsxStyle(
        fill: XlsxGradientFill.linear(
          stops: <XlsxGradientStop>[
            XlsxGradientStop(0, XlsxColor.hex('FF0000')),
            XlsxGradientStop(1, XlsxColor.hex('0000FF')),
          ],
        ),
      ),
    );
    expect(_dxfs(r), contains('<gradientFill>'));
  });

  test('the same style spelled differently gives the same id', () {
    final StyleRegistry r = StyleRegistry();
    final int a = r.dxfIdFor(red);
    final int b = r.dxfIdFor(
      XlsxStyle(
        font: const XlsxFont(color: XlsxColor.rgb(0x9C0006), bold: true),
        fill: XlsxFill.solid(XlsxColor.hex('FFC7CE')),
      ),
    );
    expect(b, a);
    expect(r.dxfIdFor(const XlsxStyle(font: XlsxFont(italic: true))), 1);
    expect(r.dxfIdFor(red), a);
  });

  test('font children keep CT_Font order', () {
    final StyleRegistry r = StyleRegistry()
      ..dxfIdFor(
        XlsxStyle(
          font: XlsxFont(
            color: XlsxColor.hex('FF0000'),
            script: XlsxFontScript.superscript,
            underline: XlsxUnderline.single,
            strike: true,
            italic: true,
            bold: true,
          ),
        ),
      );
    expect(
      _dxfs(r),
      contains(
        '<font><b/><i/><strike/><u/><vertAlign val="superscript"/>'
        '<color rgb="FFFF0000"/></font>',
      ),
    );
  });

  test('explicit off switches are written, null inherits', () {
    final StyleRegistry r = StyleRegistry();
    expect(r.dxfIdFor(const XlsxStyle(font: XlsxFont(bold: false))), 0);
    expect(r.dxfIdFor(const XlsxStyle()), 1);
    r.dxfIdFor(
      const XlsxStyle(
        font: XlsxFont(
          bold: false,
          italic: false,
          strike: false,
          condense: false,
          extend: false,
          outline: false,
          shadow: false,
          underline: XlsxUnderline.none,
        ),
      ),
    );
    final String d = _dxfs(r);
    expect(d, contains('<dxf><font><b val="0"/></font></dxf>'));
    expect(
      d,
      contains(
        '<dxf><font><b val="0"/><i val="0"/><strike val="0"/>'
        '<condense val="0"/><extend val="0"/><outline val="0"/>'
        '<shadow val="0"/><u val="none"/></font></dxf>',
      ),
    );
  });

  test('border writes the four sides', () {
    final StyleRegistry r = StyleRegistry()
      ..dxfIdFor(
        const XlsxStyle(
          border: XlsxBorder(left: XlsxBorderSide(style: XlsxBorderStyle.thin)),
        ),
      );
    expect(_dxfs(r), contains('<border><left style="thin"/>'));
  });

  test('numFmt: custom shares its id with cellXfs, built-in writes code', () {
    final StyleRegistry r = StyleRegistry();
    final int cell = r.idFor(
      const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')),
    );
    expect(cell, 1);
    r.dxfIdFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')));
    r.dxfIdFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0000')));
    r.dxfIdFor(const XlsxStyle(numFmt: XlsxNumFmt.thousands2));
    final String xml = _stylesXml(r);
    expect(xml, contains('<numFmts count="2">'));
    expect(
      _dxfs(r),
      '<dxfs count="3">'
      '<dxf><numFmt numFmtId="164" formatCode="0.000"/></dxf>'
      '<dxf><numFmt numFmtId="165" formatCode="0.0000"/></dxf>'
      '<dxf><numFmt numFmtId="4" formatCode="#,##0.00"/></dxf>'
      '</dxfs>',
    );
    // A later cell format reuses the id the dxf made.
    r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0000')));
    expect(_stylesXml(r), contains('numFmtId="165" fontId="0"'));
  });

  test('dxf children follow CT_Dxf order', () {
    final StyleRegistry r = StyleRegistry()
      ..dxfIdFor(
        XlsxStyle(
          border: const XlsxBorder(
            top: XlsxBorderSide(style: XlsxBorderStyle.thin),
          ),
          fill: XlsxFill.solid(XlsxColor.hex('FFFFFF')),
          numFmt: XlsxNumFmt.integer,
          font: const XlsxFont(bold: true),
        ),
      );
    final String d = _dxfs(r);
    expect(d.indexOf('<font>'), lessThan(d.indexOf('<numFmt ')));
    expect(d.indexOf('<numFmt '), lessThan(d.indexOf('<fill>')));
    expect(d.indexOf('<fill>'), lessThan(d.indexOf('<border>')));
  });

  group('invalid dxf styles throw and register nothing', () {
    final Map<String, XlsxStyle> bad = <String, XlsxStyle>{
      'font.name': const XlsxStyle(font: XlsxFont(name: 'Arial')),
      'font.size': const XlsxStyle(font: XlsxFont(size: 12)),
      'font.family': const XlsxStyle(font: XlsxFont(family: 2)),
      'font.charset': const XlsxStyle(font: XlsxFont(charset: 1)),
      'font.scheme': const XlsxStyle(
        font: XlsxFont(scheme: XlsxFontScheme.minor),
      ),
      'alignment': const XlsxStyle(
        alignment: XlsxAlignment(horizontal: XlsxHorizontalAlignment.center),
      ),
      'protection': const XlsxStyle(protection: XlsxProtection(locked: false)),
      'border.diagonal': const XlsxStyle(
        border: XlsxBorder(
          diagonal: XlsxBorderSide(style: XlsxBorderStyle.thin),
        ),
      ),
      'border.vertical': const XlsxStyle(
        border: XlsxBorder(
          vertical: XlsxBorderSide(style: XlsxBorderStyle.thin),
        ),
      ),
      'border.horizontal': const XlsxStyle(
        border: XlsxBorder(
          horizontal: XlsxBorderSide(style: XlsxBorderStyle.thin),
        ),
      ),
      'border.diagonalUp': const XlsxStyle(
        border: XlsxBorder(diagonalUp: true),
      ),
      'border.diagonalDown': const XlsxStyle(
        border: XlsxBorder(diagonalDown: true),
      ),
      'numFmt': const XlsxStyle(numFmt: XlsxNumFmt.builtin(30)),
    };
    for (final MapEntry<String, XlsxStyle> e in bad.entries) {
      test(e.key, () {
        final StyleRegistry r = StyleRegistry();
        expect(
          () => r.dxfIdFor(e.value),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError a) => a.name,
              'name',
              e.key,
            ),
          ),
        );
        expect(_dxfs(r), '<dxfs count="0"/>');
        expect(_stylesXml(r), isNot(contains('<numFmts')));
      });
    }

    test('an invalid color throws', () {
      expect(
        () => StyleRegistry().dxfIdFor(
          const XlsxStyle(font: XlsxFont(color: XlsxColor.theme(99))),
        ),
        throwsArgumentError,
      );
    });
  });

  group('dxfIdsFor', () {
    test('an empty list gives an empty list', () {
      expect(StyleRegistry().dxfIdsFor(<XlsxStyle>[]), isEmpty);
    });

    test('gives ids in order, repeating a style repeats its id', () {
      final StyleRegistry r = StyleRegistry();
      expect(
        r.dxfIdsFor(<XlsxStyle>[
          red,
          const XlsxStyle(font: XlsxFont(italic: true)),
          red,
        ]),
        <int>[0, 1, 0],
      );
    });

    test('an invalid third style registers none of the first two', () {
      final StyleRegistry r = StyleRegistry();
      r.dxfIdFor(const XlsxStyle(font: XlsxFont(strike: true)));
      final String before = _stylesXml(r);
      expect(
        () => r.dxfIdsFor(<XlsxStyle>[
          red,
          const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0%%')),
          const XlsxStyle(font: XlsxFont(name: 'Arial')),
        ]),
        throwsArgumentError,
      );
      expect(_stylesXml(r), before);
      expect(r.dxfIdFor(red), 1);
    });

    test('the number format limit rolls back dxf codes', () {
      final StyleRegistry r = StyleRegistry();
      for (var i = 0; i < XlsxLimits.maxNumberFormats - 1; i++) {
        r.idFor(XlsxStyle(numFmt: XlsxNumFmt.custom('0.${'0' * 3}#$i')));
      }
      final String before = _stylesXml(r);
      expect(
        () => r.dxfIdsFor(<XlsxStyle>[
          const XlsxStyle(numFmt: XlsxNumFmt.custom('A')),
          const XlsxStyle(numFmt: XlsxNumFmt.custom('B')),
        ]),
        throwsA(isA<XlsxLimitError>()),
      );
      expect(_stylesXml(r), before);
    });
  });

  group('builtinNumberFormatCode', () {
    test('known ids', () {
      expect(builtinNumberFormatCode(0), 'General');
      expect(builtinNumberFormatCode(4), '#,##0.00');
      expect(builtinNumberFormatCode(14), 'mm-dd-yy');
      expect(builtinNumberFormatCode(22), 'm/d/yy h:mm');
      expect(builtinNumberFormatCode(37), '#,##0 ;(#,##0)');
      expect(builtinNumberFormatCode(49), '@');
    });

    test('ids without a code', () {
      for (final int id in <int>[-1, 23, 36, 50, 163, 164]) {
        expect(builtinNumberFormatCode(id), isNull, reason: '$id');
      }
      for (final int id in <int>[
        ...List<int>.generate(23, (int i) => i),
        ...List<int>.generate(13, (int i) => 37 + i),
      ]) {
        expect(builtinNumberFormatCode(id), isNotNull, reason: '$id');
      }
    });
  });
}
