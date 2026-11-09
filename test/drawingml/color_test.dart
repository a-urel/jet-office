import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/common/theme_colors.dart';
import 'package:jet_office/src/drawingml/color.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

/// [color] written in [mode], without the namespace declaration.
String _write(ChartColor color, ChartExportColors mode) {
  final StringBuffer out = StringBuffer();
  writeDrawingColor(XmlWriter(out), color, mode);
  return out.toString();
}

/// Reads the first element inside a root that declares `a:`, and checks the
/// reader stands on that element's end afterwards.
ChartColor? _read(String colorXml, {ThemeColors? theme}) {
  final XmlPullReader r = XmlPullReader(
    '<root xmlns:a="$_a">$colorXml<after/></root>',
  );
  r.nextTag(); // root
  r.nextTag(); // the colour element
  final String name = r.localName;
  final int depth = r.depth;
  final ChartColor? color = readDrawingColor(r, theme: theme);
  expect(r.eventType, XmlEventType.endElement, reason: 'consumes $name');
  expect(r.localName, name);
  expect(r.depth, depth - 1);
  r.nextTag();
  expect(r.localName, 'after');
  return color;
}

ThemeColors _themeWithAccent1(String hex) => ThemeColors.read(
  XmlPullReader(
    '<a:theme xmlns:a="$_a"><a:themeElements><a:clrScheme name="x">'
    '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
    '<a:accent1><a:srgbClr val="$hex"/></a:accent1>'
    '</a:clrScheme></a:themeElements></a:theme>',
  ),
)!;

void main() {
  group('applyDrawingLuminance', () {
    test('gives the Office theme text and line greys from black', () {
      expect(applyDrawingLuminance(0x000000, .65, .35), 0x595959);
      expect(applyDrawingLuminance(0x000000, .15, .85), 0xD9D9D9);
    });

    test('is the identity at lumMod 1 and lumOff 0', () {
      for (final int rgb in <int>[
        0x000000,
        0xFFFFFF,
        0x156082,
        0xE97132,
        0x0F9ED5,
        0x123456,
      ]) {
        expect(applyDrawingLuminance(rgb, 1, 0), rgb);
      }
    });

    test("agrees with the core's colour cycle on the Office accents", () {
      // jet_charts_core repeats this calculation for seriesColor, as it
      // cannot import jet_office: every variation of colors1 on the six
      // accents must give the same RGB value here and there.
      final ChartTheme office = ChartTheme.office;
      for (int i = 0; i < 54; i++) {
        final ChartColor base = office.palette[i % 6];
        final ChartColor varied = office.seriesColor(i);
        expect(
          varied.rgb,
          applyDrawingLuminance(base.rgb, varied.lumMod, varied.lumOff),
          reason: 'series $i',
        );
      }
    });

    test('clamps the luminance to 0 and 1', () {
      expect(applyDrawingLuminance(0xFFFFFF, 1, 1), 0xFFFFFF);
      expect(applyDrawingLuminance(0x808080, 1, 1), 0xFFFFFF);
      expect(applyDrawingLuminance(0x156082, 0, 0), 0x000000);
    });

    test('keeps hue and saturation', () {
      // Accent 1 at 50 % luminance: L 0.2961 becomes 0.1480, so every
      // channel halves (S and H are unchanged and L < 0.5 throughout).
      expect(applyDrawingLuminance(0x156082, .5, 0), 0x0B3041);
    });
  });

  group('writeDrawingColor', () {
    test('writes a bound colour as schemeClr with the chart names', () {
      expect(
        _write(
          ChartColor.scheme(ChartSchemeColor.dark1, rgb: 0),
          ChartExportColors.fileTheme,
        ),
        '<a:schemeClr val="tx1"/>',
      );
      expect(
        _write(
          ChartColor.scheme(ChartSchemeColor.light2, rgb: 0xE8E8E8),
          ChartExportColors.fileTheme,
        ),
        '<a:schemeClr val="bg2"/>',
      );
      expect(
        _write(
          ChartColor.scheme(ChartSchemeColor.accent4, rgb: 0x0F9ED5),
          ChartExportColors.fileTheme,
        ),
        '<a:schemeClr val="accent4"/>',
      );
    });

    test('writes lumMod and lumOff as Excel does', () {
      expect(
        _write(ChartTheme.office.axisLabels.color, ChartExportColors.fileTheme),
        '<a:schemeClr val="tx1"><a:lumMod val="65000"/>'
        '<a:lumOff val="35000"/></a:schemeClr>',
      );
      expect(
        _write(
          ChartColor.scheme(
            ChartSchemeColor.accent1,
            rgb: 0x0B3041,
            lumMod: .5,
          ),
          ChartExportColors.fileTheme,
        ),
        '<a:schemeClr val="accent1"><a:lumMod val="50000"/></a:schemeClr>',
      );
    });

    test('writes srgbClr in upper case for fixed or unbound colours', () {
      expect(
        _write(ChartTheme.office.axisLabels.color, ChartExportColors.fixed),
        '<a:srgbClr val="595959"/>',
      );
      expect(
        _write(ChartColor.rgb(0x0f9ed5), ChartExportColors.fileTheme),
        '<a:srgbClr val="0F9ED5"/>',
      );
      expect(
        _write(ChartColor.rgb(0x00000a), ChartExportColors.fixed),
        '<a:srgbClr val="00000A"/>',
      );
    });
  });

  group('drawingOfficeSchemeRgb', () {
    test('holds the Office theme accents', () {
      for (final ChartColor color in ChartTheme.office.palette) {
        expect(drawingOfficeSchemeRgb[color.slot], color.rgb);
      }
      expect(drawingOfficeSchemeRgb[ChartSchemeColor.dark1], 0x000000);
      expect(drawingOfficeSchemeRgb[ChartSchemeColor.light1], 0xFFFFFF);
      expect(drawingOfficeSchemeRgb[ChartSchemeColor.dark2], 0x0E2841);
      expect(drawingOfficeSchemeRgb[ChartSchemeColor.light2], 0xE8E8E8);
      expect(drawingOfficeSchemeRgb.keys, ChartSchemeColor.values);
    });
  });

  group('readDrawingColor', () {
    test('round-trips every slot written with the file theme', () {
      for (final ChartSchemeColor slot in ChartSchemeColor.values) {
        final ChartColor color = ChartColor.scheme(
          slot,
          rgb: drawingOfficeSchemeRgb[slot]!,
        );
        expect(
          _read(_write(color, ChartExportColors.fileTheme)),
          color,
          reason: slot.name,
        );
      }
    });

    test('round-trips the Office theme text, line and background', () {
      final ChartTheme office = ChartTheme.office;
      for (final ChartColor color in <ChartColor>[
        office.axisLabels.color,
        office.gridLine,
        office.background,
      ]) {
        expect(_read(_write(color, ChartExportColors.fileTheme)), color);
      }
    });

    test('round-trips srgbClr', () {
      for (final int rgb in <int>[0, 0xFFFFFF, 0x0F9ED5, 0xABCDEF]) {
        final ChartColor color = ChartColor.rgb(rgb);
        expect(_read(_write(color, ChartExportColors.fixed)), color);
      }
      expect(_read('<a:srgbClr val="abcdef"/>'), ChartColor.rgb(0xABCDEF));
    });

    test('reads dk1, lt1, dk2 and lt2 as the same slots as tx1 to bg2', () {
      expect(
        _read('<a:schemeClr val="dk1"/>'),
        ChartColor.scheme(ChartSchemeColor.dark1, rgb: 0),
      );
      expect(
        _read('<a:schemeClr val="lt1"/>'),
        ChartColor.scheme(ChartSchemeColor.light1, rgb: 0xFFFFFF),
      );
      expect(
        _read('<a:schemeClr val="dk2"/>'),
        ChartColor.scheme(ChartSchemeColor.dark2, rgb: 0x0E2841),
      );
      expect(
        _read('<a:schemeClr val="lt2"/>'),
        ChartColor.scheme(ChartSchemeColor.light2, rgb: 0xE8E8E8),
      );
    });

    test('reads sysClr by its lastClr', () {
      expect(
        _read('<a:sysClr val="windowText" lastClr="000000"/>'),
        ChartColor.rgb(0),
      );
      expect(_read('<a:sysClr val="windowText"/>'), isNull);
    });

    test('applies lumMod and lumOff to a fixed colour', () {
      expect(
        _read(
          '<a:srgbClr val="000000"><a:lumMod val="65000"/>'
          '<a:lumOff val="35000"/></a:srgbClr>',
        ),
        ChartColor.rgb(0x595959),
      );
    });

    test('takes a scheme colour from the file theme', () {
      final ThemeColors theme = _themeWithAccent1('FF0000');
      expect(
        _read('<a:schemeClr val="accent1"/>', theme: theme),
        ChartColor.scheme(ChartSchemeColor.accent1, rgb: 0xFF0000),
      );
      // A slot the theme lacks falls back to the Office theme.
      expect(
        _read('<a:schemeClr val="accent2"/>', theme: theme),
        ChartColor.scheme(ChartSchemeColor.accent2, rgb: 0xE97132),
      );
      expect(
        _read(
          '<a:schemeClr val="tx1"><a:lumMod val="65000"/>'
          '<a:lumOff val="35000"/></a:schemeClr>',
          theme: theme,
        ),
        ChartTheme.office.axisLabels.color,
      );
    });

    test('gives null for any other modifier', () {
      expect(
        _read(
          '<a:schemeClr val="accent1"><a:alpha val="50000"/></a:schemeClr>',
        ),
        isNull,
      );
      expect(
        _read('<a:srgbClr val="FF0000"><a:shade val="50000"/></a:srgbClr>'),
        isNull,
      );
    });

    test('gives null for values it cannot express', () {
      for (final String xml in <String>[
        '<a:schemeClr val="phClr"/>',
        '<a:schemeClr val="hlink"/>',
        '<a:schemeClr/>',
        '<a:srgbClr val="FF00"/>',
        '<a:srgbClr val="GG0000"/>',
        '<a:srgbClr/>',
        '<a:schemeClr val="tx1"><a:lumMod val="abc"/></a:schemeClr>',
        '<a:schemeClr val="tx1"><a:lumMod val="120000"/></a:schemeClr>',
        '<a:schemeClr val="tx1"><a:lumOff val="-1"/></a:schemeClr>',
        '<a:schemeClr val="tx1"><a:lumMod/></a:schemeClr>',
        '<a:srgbClr val="000000">x</a:srgbClr>',
      ]) {
        expect(_read(xml), isNull, reason: xml);
      }
    });

    test('gives null for any other colour element and consumes it', () {
      expect(_read('<a:prstClr val="black"/>'), isNull);
      expect(_read('<a:hslClr hue="0" sat="0" lum="0"/>'), isNull);
      expect(
        _read('<a:scrgbClr r="0" g="0" b="0"><a:alpha val="1"/></a:scrgbClr>'),
        isNull,
      );
      expect(
        _read('<other xmlns="urn:x"><a:srgbClr val="000000"/></other>'),
        isNull,
      );
    });
  });
}
