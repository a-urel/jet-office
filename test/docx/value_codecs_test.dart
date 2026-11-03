// Tests the codecs of colour, shading and border: what each reads of an
// element, what it refuses, and the exact attributes it writes. They need no
// file, so they run on the web as well.
import 'package:jet_office/src/docx/model/formatting.dart';
import 'package:jet_office/src/docx/property_codec.dart';
import 'package:jet_office/src/docx/value_codecs.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

PropertyElement _element(String xml) {
  final XmlPullReader r = XmlPullReader(
    '<w:document xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}">$xml</w:document>',
  );
  r.nextTag();
  r.nextTag();
  final PropertyElementBuilder builder = PropertyElementBuilder();
  OpaqueXml.capture(r, onEvent: builder.add);
  return builder.element!;
}

String _written<T extends Object>(PropertyCodec<T> codec, T value) {
  final StringBuffer b = StringBuffer();
  codec.write(XmlWriter(b), 'w', value, null);
  return b.toString();
}

void main() {
  const ColorCodec color = ColorCodec('color');

  group('ColorCodec', () {
    test('color reads rgb, auto and theme with tint', () {
      expect(
        color.parse(_element('<w:color w:val="ff8a0b"/>')),
        DocxColor.rgb('FF8A0B'),
      );
      expect(color.parse(_element('<w:color w:val="auto"/>')), DocxColor.auto);
      expect(
        color.parse(
          _element(
            '<w:color w:val="4472C4" w:themeColor="accent1" '
            'w:themeTint="BF" w:themeShade="0a"/>',
          ),
        ),
        DocxColor.theme(DocxThemeColor.accent1, tint: 0xBF, shade: 10),
      );
      expect(
        color.parse(_element('<w:color w:val="auto" w:themeColor="text1"/>')),
        DocxColor.theme(DocxThemeColor.text1),
      );
    });

    test('color FF00 and red have no view', () {
      for (final String bad in <String>[
        '<w:color w:val="FF00"/>',
        '<w:color w:val="red"/>',
        '<w:color/>',
        '<w:color w:val="auto" w:themeColor="purple"/>',
        '<w:color w:val="auto" w:themeColor="accent1" w:themeTint="100"/>',
        '<w:color w:val="auto" w:themeColor="accent1" w:themeShade="x"/>',
        '<w:color w:val="FF0000"><w:x/></w:color>',
        '<w:color w:val="FF0000">text</w:color>',
      ]) {
        expect(color.parse(_element(bad)), isNull, reason: bad);
      }
    });

    test('a color writes its attributes', () {
      expect(
        _written(color, DocxColor.rgb('ff0000')),
        '<w:color w:val="FF0000"/>',
      );
      expect(_written(color, DocxColor.auto), '<w:color w:val="auto"/>');
      expect(
        _written(
          color,
          DocxColor.theme(DocxThemeColor.accent2, tint: 10, shade: 255),
        ),
        '<w:color w:val="auto" w:themeColor="accent2" w:themeTint="0A" '
        'w:themeShade="FF"/>',
      );
      expect(color.attributes, <String>{
        'val',
        'themeColor',
        'themeTint',
        'themeShade',
      });
    });

    test('a color written reads back', () {
      for (final DocxColor c in <DocxColor>[
        DocxColor.auto,
        DocxColor.rgb('0A0B0C'),
        DocxColor.theme(DocxThemeColor.followedHyperlink, tint: 1, shade: 2),
      ]) {
        expect(color.parse(_element(_written(color, c))), c);
      }
    });
  });

  group('ShadingCodec', () {
    const ShadingCodec shd = ShadingCodec();

    test('shading reads clear with fill auto', () {
      expect(
        shd.parse(
          _element('<w:shd w:val="clear" w:color="auto" w:fill="auto"/>'),
        ),
        const DocxShading(color: DocxColor.auto, fill: DocxColor.auto),
      );
      expect(
        shd.parse(_element('<w:shd w:val="solid" w:fill="ffff00"/>')),
        DocxShading(
          pattern: DocxShadingPattern.solid,
          fill: DocxColor.rgb('FFFF00'),
        ),
      );
      expect(
        shd.parse(
          _element(
            '<w:shd w:val="pct25" w:color="auto" w:fill="auto" '
            'w:themeFill="accent3" w:themeFillShade="80"/>',
          ),
        ),
        DocxShading(
          pattern: DocxShadingPattern.pct25,
          color: DocxColor.auto,
          fill: DocxColor.theme(DocxThemeColor.accent3, shade: 0x80),
        ),
      );
    });

    test('a shading without a known pattern or with a bad colour has no '
        'view', () {
      for (final String bad in <String>[
        '<w:shd/>',
        '<w:shd w:val="pct99"/>',
        '<w:shd w:val="clear" w:fill="12"/>',
        '<w:shd w:val="clear" w:color="blue"/>',
        '<w:shd w:val="clear" w:themeFill="nope"/>',
        '<w:shd w:val="clear"><w:x/></w:shd>',
      ]) {
        expect(shd.parse(_element(bad)), isNull, reason: bad);
      }
    });

    test('a shading writes color and fill with their theme attributes', () {
      expect(_written(shd, const DocxShading()), '<w:shd w:val="clear"/>');
      expect(
        _written(
          shd,
          DocxShading(
            pattern: DocxShadingPattern.diagStripe,
            color: DocxColor.rgb('112233'),
            fill: DocxColor.theme(DocxThemeColor.accent3, tint: 0x40),
          ),
        ),
        '<w:shd w:val="diagStripe" w:color="112233" w:fill="auto" '
        'w:themeFill="accent3" w:themeFillTint="40"/>',
      );
    });
  });

  group('BorderCodec', () {
    const BorderCodec top = BorderCodec('top');

    test('a border reads style, width, space, color, shadow and frame', () {
      expect(
        top.parse(
          _element(
            '<w:top w:val="double" w:sz="12" w:space="4" w:color="ff0000" '
            'w:shadow="1" w:frame="true"/>',
          ),
        ),
        DocxBorder(
          style: DocxBorderStyle.double,
          widthPt: 1.5,
          spacePt: 4,
          color: DocxColor.rgb('FF0000'),
          shadow: true,
          frame: true,
        ),
      );
      expect(top.parse(_element('<w:top w:val="single"/>')), DocxBorder());
    });

    test('a border that is not drawn reads with sz 0', () {
      expect(
        top.parse(
          _element('<w:top w:val="nil" w:sz="0" w:space="0" w:color="auto"/>'),
        ),
        DocxBorder(style: DocxBorderStyle.nil, color: DocxColor.auto),
      );
    });

    test('an art border has no view', () {
      expect(top.parse(_element('<w:top w:val="apples" w:sz="12"/>')), isNull);
    });

    test('a border out of range or with a bad attribute has no view', () {
      for (final String bad in <String>[
        '<w:top/>',
        '<w:top w:val="single" w:sz="0"/>',
        '<w:top w:val="single" w:sz="97"/>',
        '<w:top w:val="single" w:sz="x"/>',
        '<w:top w:val="single" w:space="32"/>',
        '<w:top w:val="single" w:color="bad"/>',
        '<w:top w:val="single" w:shadow="maybe"/>',
        '<w:top w:val="single"><w:x/></w:top>',
      ]) {
        expect(top.parse(_element(bad)), isNull, reason: bad);
      }
    });

    test('a border writes val, sz, space, color, shadow and frame', () {
      expect(
        _written(top, DocxBorder()),
        '<w:top w:val="single" w:sz="4" w:space="0"/>',
      );
      expect(
        _written(
          const BorderCodec('bdr'),
          DocxBorder(
            style: DocxBorderStyle.dotted,
            widthPt: 0.3,
            spacePt: 2,
            color: DocxColor.theme(DocxThemeColor.dark1),
            shadow: true,
            frame: true,
          ),
        ),
        '<w:bdr w:val="dotted" w:sz="2" w:space="2" w:color="auto" '
        'w:themeColor="dark1" w:shadow="1" w:frame="1"/>',
      );
    });
  });

  group('enums', () {
    PropertyElement e(String name, String val) =>
        _element('<w:$name w:val="$val"/>');

    test('each enum writes its ST_ spelling', () {
      const List<String> themes = <String>[
        'dark1', 'light1', 'dark2', 'light2', 'accent1', 'accent2', //
        'accent3', 'accent4', 'accent5', 'accent6', 'hyperlink',
        'followedHyperlink', 'none', 'background1', 'text1', 'background2',
        'text2',
      ];
      expect(<String>[
        for (final DocxThemeColor t in DocxThemeColor.values) t.name,
      ], themes);
      for (final String t in themes) {
        final DocxColor c = color.parse(
          _element('<w:color w:val="auto" w:themeColor="$t"/>'),
        )!;
        expect(_written(color, c), contains('w:themeColor="$t"'));
      }

      const List<String> patterns = <String>[
        'nil',
        'clear',
        'solid',
        'horzStripe',
        'vertStripe',
        'reverseDiagStripe',
        'diagStripe',
        'horzCross',
        'diagCross',
        'thinHorzStripe',
        'thinVertStripe',
        'thinReverseDiagStripe',
        'thinDiagStripe',
        'thinHorzCross',
        'thinDiagCross',
        'pct5',
        'pct10',
        'pct12',
        'pct15',
        'pct20',
        'pct25',
        'pct30',
        'pct35',
        'pct37',
        'pct40',
        'pct45',
        'pct50',
        'pct55',
        'pct60',
        'pct62',
        'pct65',
        'pct70',
        'pct75',
        'pct80',
        'pct85',
        'pct87',
        'pct90',
        'pct95',
      ];
      expect(<String>[
        for (final DocxShadingPattern p in DocxShadingPattern.values) p.name,
      ], patterns);
      for (final String p in patterns) {
        final DocxShading s = const ShadingCodec().parse(e('shd', p))!;
        expect(_written(const ShadingCodec(), s), '<w:shd w:val="$p"/>');
      }

      const List<String> borders = <String>[
        'nil',
        'none',
        'single',
        'thick',
        'double',
        'dotted',
        'dashed',
        'dotDash',
        'dotDotDash',
        'triple',
        'thinThickSmallGap',
        'thickThinSmallGap',
        'thinThickThinSmallGap',
        'thinThickMediumGap',
        'thickThinMediumGap',
        'thinThickThinMediumGap',
        'thinThickLargeGap',
        'thickThinLargeGap',
        'thinThickThinLargeGap',
        'wave',
        'doubleWave',
        'dashSmallGap',
        'dashDotStroked',
        'threeDEmboss',
        'threeDEngrave',
        'outset',
        'inset',
      ];
      expect(<String>[
        for (final DocxBorderStyle s in DocxBorderStyle.values) s.name,
      ], borders);
      for (final String b in borders) {
        final DocxBorder v = const BorderCodec('top').parse(e('top', b))!;
        expect(v.style.name, b);
        expect(
          _written(const BorderCodec('top'), v),
          startsWith('<w:top w:val="$b" '),
        );
      }
    });
  });
}
