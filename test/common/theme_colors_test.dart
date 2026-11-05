import 'package:jet_office/src/common/theme_colors.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

const String _ns = 'http://schemas.openxmlformats.org/drawingml/2006/main';

String _theme(String slots, {String root = 'a:theme'}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<$root xmlns:a="$_ns" name="Office"><a:themeElements>'
    '<a:clrScheme name="Office">$slots</a:clrScheme>'
    '</a:themeElements></$root>';

void main() {
  test('reads the Office scheme', () {
    final ThemeColors? theme = ThemeColors.read(
      XmlPullReader(
        _theme(
          '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
          '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
          '<a:accent1><a:srgbClr val="4472C4"/></a:accent1>'
          '<a:hlink><a:scrgbClr r="0" g="0" b="0"/></a:hlink>',
        ),
      ),
    );
    expect(theme, isNotNull);
    expect(theme!.argbOf('dk1'), 0xFF000000);
    expect(theme.argbOf('lt1'), 0xFFFFFFFF);
    expect(theme.argbOf('accent1'), 0xFF4472C4);
    expect(theme.argbOf('accent9'), isNull);
    expect(theme.argbOf('hlink'), isNull);
    expect(theme.argbOf('dk2'), isNull);
  });

  test('a root that is not a theme reads as null', () {
    expect(
      ThemeColors.read(XmlPullReader(_theme('', root: 'a:other'))),
      isNull,
    );
    expect(
      ThemeColors.read(XmlPullReader('<theme><clrScheme/></theme>')),
      isNull,
    );
  });

  test('a theme without a scheme reads as null', () {
    expect(
      ThemeColors.read(XmlPullReader('<a:theme xmlns:a="$_ns"/>')),
      isNull,
    );
  });

  test('malformed XML passes through as XmlParseException', () {
    expect(
      () => ThemeColors.read(XmlPullReader('<a:theme xmlns:a="$_ns">')),
      throwsA(isA<XmlParseException>()),
    );
  });

  test('tint matches Excel', () {
    const int accent1 = 0xFF4472C4;
    expect(applyTint(accent1, 0.7999816888943144), 0xFFD9E1F2);
    expect(applyTint(accent1, 0.5999938962981048), 0xFFB4C6E7);
    expect(applyTint(accent1, 0.3999755851924192), 0xFF8EA9DB);
    expect(applyTint(accent1, -0.249977111117893), 0xFF305496);
    expect(applyTint(accent1, -0.499984740745262), 0xFF203764);
    expect(applyTint(0xFFFFFFFF, -0.1499984740745262), 0xFFD9D9D9);
  });

  test('a zero tint returns the color and alpha is kept', () {
    expect(applyTint(0x804472C4, 0), 0x804472C4);
    expect(applyTint(0x804472C4, 0.5) ~/ 0x1000000, 0x80);
  });
}
