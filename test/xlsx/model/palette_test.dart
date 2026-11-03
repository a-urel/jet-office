import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/palette.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../read/support/workbook_builder.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

String _theme({String accent1 = '4472C4'}) =>
    '<a:theme xmlns:a="$_a"><a:themeElements><a:clrScheme name="Office">'
    '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
    '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="44546A"/></a:dk2>'
    '<a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
    '<a:accent1><a:srgbClr val="$accent1"/></a:accent1>'
    '<a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
    '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>'
    '<a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
    '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>'
    '<a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
    '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
    '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
    '</a:clrScheme></a:themeElements></a:theme>';

const String _sheet = '<worksheet xmlns="$mainNs"><sheetData/></worksheet>';

String _styles(String colors) =>
    '<styleSheet xmlns="$mainNs"><fonts count="1"><font/></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border/></borders>'
    '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
    '<cellXfs count="1"><xf/></cellXfs>$colors</styleSheet>';

XlsxWorkbook _open({String? theme, String? styles}) => XlsxWorkbook.open(
  buildWorkbook(<String, String?>{'S': _sheet}, theme: theme, styles: styles),
);

void main() {
  test('the default palette', () {
    expect(defaultIndexedColors, hasLength(64));
    expect(defaultIndexedColors[8], 0xFF000000);
    expect(defaultIndexedColors[10], 0xFFFF0000);
    expect(defaultIndexedColors[22], 0xFFC0C0C0);
    expect(defaultIndexedColors[63], 0xFF333333);
    for (var i = 0; i < 8; i++) {
      expect(
        defaultIndexedColors[i],
        defaultIndexedColors[i + 8],
        reason: '$i',
      );
    }
    for (final int c in defaultIndexedColors) {
      expect(c >>> 24, 0xFF);
    }
  });

  test('a custom palette wins', () {
    final List<String> rgb = <String>[
      for (int i = 0; i < 64; i++)
        '<rgbColor rgb="FF${(i + 1).toRadixString(16).padLeft(2, '0')}0000"/>',
    ];
    final XlsxWorkbook book = _open(
      styles: _styles(
        '<colors><indexedColors>${rgb.join()}</indexedColors>'
        '</colors>',
      ),
    );
    expect(book.indexedColors, hasLength(64));
    expect(book.indexedColors[0], 0xFF010000);
    expect(book.resolveColor(const XlsxColor.indexed(9)), 0xFF0A0000);
    expect(book.resolveColor(const XlsxColor.indexed(63)), 0xFF400000);
    expect(() => book.indexedColors[0] = 1, throwsUnsupportedError);
  });

  test('without a palette the default applies', () {
    for (final XlsxWorkbook book in <XlsxWorkbook>[
      _open(),
      _open(styles: _styles('')),
      XlsxWorkbook(),
    ]) {
      expect(book.indexedColors, defaultIndexedColors);
      expect(book.resolveColor(const XlsxColor.indexed(10)), 0xFFFF0000);
      expect(() => book.indexedColors[0] = 1, throwsUnsupportedError);
    }
  });

  test('indexed colours outside the palette resolve as null', () {
    final XlsxWorkbook book = _open();
    for (final int i in <int>[64, 65, 66, -1, 1000]) {
      expect(book.resolveColor(XlsxColor.indexed(i)), isNull, reason: '$i');
    }
  });

  test('rgb and auto', () {
    final XlsxWorkbook book = _open();
    expect(book.resolveColor(const XlsxColor.rgb(0x123456)), 0xFF123456);
    expect(book.resolveColor(const XlsxColor.argb(0x80123456)), 0x80123456);
    expect(book.resolveColor(XlsxColor.auto), isNull);
  });

  test('theme colours resolve with the swapped first four', () {
    final XlsxWorkbook book = _open(theme: _theme());
    expect(book.resolveColor(const XlsxColor.theme(1)), 0xFF000000);
    expect(book.resolveColor(const XlsxColor.theme(0)), 0xFFFFFFFF);
    expect(book.resolveColor(const XlsxColor.theme(2)), 0xFFE7E6E6);
    expect(book.resolveColor(const XlsxColor.theme(3)), 0xFF44546A);
    expect(book.resolveColor(const XlsxColor.theme(4)), 0xFF4472C4);
    expect(book.resolveColor(const XlsxColor.theme(9)), 0xFF70AD47);
    expect(book.resolveColor(const XlsxColor.theme(10)), 0xFF0563C1);
    expect(book.resolveColor(const XlsxColor.theme(11)), 0xFF954F72);
    expect(
      book.resolveColor(const XlsxColor.theme(4, tint: 0.5999938962981048)),
      0xFFB4C6E7,
    );
    expect(
      book.resolveColor(const XlsxColor.theme(4, tint: -0.249977111117893)),
      0xFF305496,
    );
  });

  test('a missing slot, an unknown index or no theme resolves as null', () {
    final XlsxWorkbook book = _open(theme: _theme());
    for (final int i in <int>[12, 99, -1]) {
      expect(book.resolveColor(XlsxColor.theme(i)), isNull, reason: '$i');
    }
    final XlsxWorkbook partial = _open(
      theme:
          '<a:theme xmlns:a="$_a"><a:themeElements><a:clrScheme name="x">'
          '<a:dk1><a:srgbClr val="010203"/></a:dk1></a:clrScheme>'
          '</a:themeElements></a:theme>',
    );
    expect(partial.resolveColor(const XlsxColor.theme(1)), 0xFF010203);
    expect(partial.resolveColor(const XlsxColor.theme(4)), isNull);
  });

  test('no theme part resolves theme colours as null', () {
    for (final XlsxWorkbook book in <XlsxWorkbook>[_open(), XlsxWorkbook()]) {
      expect(book.resolveColor(const XlsxColor.theme(1)), isNull);
      expect(book.resolveColor(const XlsxColor.theme(4, tint: 0.5)), isNull);
    }
  });

  test('a theme that cannot be parsed resolves as missing', () {
    for (final String bad in <String>[
      '',
      'not xml',
      '<a:theme xmlns:a="$_a"><a:themeElements><a:clrScheme>',
      '<other/>',
    ]) {
      final XlsxWorkbook book = _open(theme: bad);
      expect(book.resolveColor(const XlsxColor.theme(1)), isNull, reason: bad);
      expect(book.resolveColor(const XlsxColor.rgb(1)), 0xFF000001);
    }
  });

  test('a tint that is not finite or not in -1..1 is ignored', () {
    final XlsxWorkbook book = _open(theme: _theme());
    for (final double t in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1.5,
      -2,
    ]) {
      expect(
        book.resolveColor(XlsxColor.theme(4, tint: t)),
        0xFF4472C4,
        reason: '$t',
      );
    }
    expect(book.resolveColor(const XlsxColor.theme(4, tint: 1)), 0xFFFFFFFF);
    expect(book.resolveColor(const XlsxColor.theme(4, tint: -1)), 0xFF000000);
  });

  test('resolving does not load the theme', () {
    final Uint8List bytes = buildWorkbook(<String, String?>{
      'S': _sheet,
    }, theme: _theme());
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    expect(book.resolveColor(const XlsxColor.theme(4)), 0xFF4472C4);
    expect(book.resolveColor(const XlsxColor.theme(5)), 0xFFED7D31);
    final Uint8List saved = book.save().bytes;
    expect(comparePackages(bytes, saved), isEmpty);
    expect(utf8.decode(_partBytes(saved, 'xl/theme/theme1.xml')), _theme());
  });
}

List<int> _partBytes(Uint8List zip, String name) =>
    ZipDecoder().decodeBytes(zip).findFile(name)!.content as List<int>;
