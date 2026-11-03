import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/alignment.dart'
    show alignmentXml, protectionXml;
import 'package:jet_office/src/xlsx/font.dart' show resolveFont;
import 'package:jet_office/src/xlsx/model/palette.dart';
import 'package:jet_office/src/xlsx/model/styles_part.dart';
import 'package:jet_office/src/xlsx/read/package_reader.dart';
import 'package:jet_office/src/xlsx/read/styles_reader.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../fixtures/m2_fixtures.dart';
import '../read/support/producers.dart';
import '../read/support/workbook_builder.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const XlsxReadLimits _limits = XlsxReadLimits();

/// The styles part of [package] as text, and its name; `null` without one.
String? _stylesXml(Uint8List package) {
  final Archive zip = ZipDecoder().decodeBytes(package);
  for (final ArchiveFile f in zip.files) {
    if (f.name.endsWith('styles.xml')) {
      return utf8.decode(f.content as List<int>);
    }
  }
  return null;
}

/// Every styles part of the writer fixtures and the producer files.
Map<String, String> _allStyles() {
  final Map<String, String> out = <String, String>{};
  for (final Fixture f in allFixtures()) {
    final String? xml = _stylesXml(f.build());
    if (xml != null) out[f.name] = xml;
  }
  for (final ProducerFile p in producerFiles()) {
    final String? xml = _stylesXml(p.bytes);
    if (xml != null) out['producer ${p.name}'] = xml;
  }
  return out;
}

StylesPart _read(
  String xml, {
  XlsxReadLimits limits = _limits,
  void Function(XlsxWarningCode code, String detail)? warn,
}) => StylesPart.read(XmlPullReader(xml), limits, warn: warn);

String _encode(PartContent part) =>
    utf8.decode(<int>[for (final Uint8List c in part.encode()) ...c]);

String _sheet(String body, {String attrs = ''}) =>
    '<styleSheet xmlns="$_main"$attrs>$body</styleSheet>';

final List<int> _defaultTail = defaultIndexedColors.sublist(2);

void main() {
  _typedTests();

  group('read then encode', () {
    final Map<String, String> all = _allStyles();

    test('there are styles parts to check', () {
      expect(all.length, greaterThan(10));
    });

    for (final MapEntry<String, String> e in all.entries) {
      test('is semantically equal: ${e.key}', () {
        final String out = _encode(_read(e.value));
        expect(compareXml('xl/styles.xml', e.value, out), isEmpty);
      });
    }

    test('keeps the root declarations and mc:Ignorable', () {
      const String xml =
          '<styleSheet xmlns="$_main" '
          'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
          'xmlns:x14ac="http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac" '
          'mc:Ignorable="x14ac">'
          '<fonts count="1" x14ac:knownFonts="1"><font/></fonts>'
          '<cellXfs count="1"><xf numFmtId="0" fontId="0"/></cellXfs>'
          '</styleSheet>';
      final String out = _encode(_read(xml));
      expect(compareXml('s', xml, out), isEmpty);
      expect(out, contains('mc:Ignorable="x14ac"'));
    });

    test('keeps unknown children in their position', () {
      final String xml = _sheet(
        '<fonts count="1"><font/></fonts>'
        '<cellXfs count="1"><xf numFmtId="0"/><extra a="1"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0"/></cellStyles>',
      );
      final String out = _encode(_read(xml));
      expect(compareXml('s', xml, out), isEmpty);
      expect(out.indexOf('<fonts'), lessThan(out.indexOf('<cellXfs')));
      expect(out.indexOf('<cellXfs'), lessThan(out.indexOf('<cellStyles')));
    });

    test('keeps a numFmt with an unusable id or no code as written', () {
      final String xml = _sheet(
        '<numFmts count="3"><numFmt numFmtId="x" formatCode="0"/>'
        '<numFmt numFmtId="170"/><numFmt numFmtId="171" formatCode="0.0"/>'
        '</numFmts>',
      );
      expect(compareXml('s', xml, _encode(_read(xml))), isEmpty);
    });

    test('recomputes count', () {
      final String xml = _sheet(
        '<cellXfs count="9"><xf numFmtId="0"/><xf numFmtId="1"/></cellXfs>',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('count="2"'));
    });
  });

  group('table', () {
    for (final MapEntry<String, String> e in _allStyles().entries) {
      test('matches readStyles: ${e.key}', () {
        final PackageReader p = PackageReader(
          _packageWithStyles(e.value),
          _limits,
        );
        final StyleTable expected = readStyles(p, 'xl/styles.xml', _limits);
        final StyleTable actual = _read(e.value).table;
        for (int s = 0; s < 400; s++) {
          final CellFormat a = actual.formatOf('$s');
          final CellFormat x = expected.formatOf('$s');
          expect(a.id, x.id, reason: 's=$s');
          expect(a.code, x.code, reason: 's=$s');
          expect(a.kind, x.kind, reason: 's=$s');
          expect(a.invalid, x.invalid, reason: 's=$s');
        }
        expect(actual.formatOf(null).id, expected.formatOf(null).id);
        expect(actual.formatOf('x').invalid, expected.formatOf('x').invalid);
      });
    }

    test('reflects a custom format and a broken xf', () {
      final StylesPart part = _read(
        _sheet(
          '<numFmts count="1"><numFmt numFmtId="164" formatCode="0.0%"/>'
          '</numFmts><cellXfs count="3"><xf numFmtId="164"/><xf/>'
          '<xf numFmtId="zz"/></cellXfs>',
        ),
      );
      expect(part.table.formatOf('0').code, '0.0%');
      expect(part.table.formatOf('1').id, 0);
      expect(part.table.formatOf('2').invalid, isTrue);
    });
  });

  group('withNumberFormat', () {
    const String body =
        '<fonts count="2"><font/><font/></fonts>'
        '<cellXfs count="2">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="3" xfId="0" '
        'applyFont="1"><alignment horizontal="center"/></xf>'
        '</cellXfs>';

    test('appends once and reuses', () {
      final StylesPart part = _read(_sheet(body));
      final int a = part.withNumberFormat(1, 22);
      final int b = part.withNumberFormat(1, 22);
      expect(a, 2);
      expect(b, a);
      final String out = _encode(part);
      expect(out, contains('count="3"'));
      expect(RegExp('<xf ').allMatches(out).length, 3);
      final String added = RegExp(
        r'<xf [^>]*numFmtId="22"[^>]*>.*?</xf>',
      ).firstMatch(out)!.group(0)!;
      expect(added, contains('fontId="1"'));
      expect(added, contains('fillId="2"'));
      expect(added, contains('borderId="3"'));
      expect(added, contains('applyNumberFormat="1"'));
      expect(added, contains('applyFont="1"'));
      expect(added, contains('<alignment horizontal="center"/>'));
      expect(part.table.formatOf('$a').id, 22);
      expect(part.table.formatOf('$a').code, isNotNull);
    });

    test('keeps existing indexes and reuses an equal xf', () {
      final StylesPart part = _read(_sheet(body));
      expect(part.withNumberFormat(0, 14), 2);
      expect(part.withNumberFormat(0, 14), 2);
      expect(part.withNumberFormat(2, 14), 2);
      expect(part.table.formatOf('0').id, 0);
      expect(part.table.formatOf('1').id, 0);
    });

    test('reuses an existing xf that already is the result', () {
      final StylesPart part = _read(
        _sheet(
          '<cellXfs count="2"><xf numFmtId="0" fontId="1"/>'
          '<xf numFmtId="14" fontId="1" applyNumberFormat="1"/></cellXfs>',
        ),
      );
      expect(part.withNumberFormat(0, 14), 1);
      expect(_encode(part), contains('count="2"'));
    });

    test('a null or out-of-range style is xf 0', () {
      final StylesPart part = _read(_sheet(body));
      final int a = part.withNumberFormat(null, 14);
      expect(part.withNumberFormat(99, 14), a);
      expect(part.withNumberFormat(-1, 14), a);
      final String out = _encode(part);
      expect(
        RegExp(r'<xf [^>]*numFmtId="14"[^>]*/>').firstMatch(out)!.group(0)!,
        contains('fontId="0"'),
      );
    });

    test('adds an xf when the part has none, and a cellXfs when missing', () {
      for (final String xml in <String>[
        _sheet('<cellXfs count="0"/>'),
        _sheet('<fonts count="1"><font/></fonts>'),
      ]) {
        final StylesPart part = _read(xml);
        expect(part.withNumberFormat(null, 22), 0);
        final String out = _encode(part);
        expect(out, contains('<cellXfs count="1">'));
        expect(part.table.formatOf('0').id, 22);
        expect(compareXml('s', out, _encode(_read(out))), isEmpty);
      }
    });

    test('puts a new cellXfs before cellStyles', () {
      final StylesPart part = _read(
        _sheet('<cellStyles count="0"/><dxfs count="0"/>'),
      );
      part.withNumberFormat(null, 14);
      final String out = _encode(part);
      expect(out.indexOf('<cellXfs'), lessThan(out.indexOf('<cellStyles')));
    });

    test('handles single quotes, prefixes and a missing attribute', () {
      final StylesPart part = _read(
        '<s:styleSheet xmlns:s="$_main" '
        'xmlns:v="urn:v"><s:cellXfs count="1">'
        '<s:xf numFmtId=\'5\' v:numFmtId="keep" note="a numFmtId=\'9\'"/>'
        '</s:cellXfs></s:styleSheet>',
      );
      final int i = part.withNumberFormat(0, 22);
      final String out = _encode(part);
      expect(i, 1);
      expect(out, contains('<s:xf '));
      expect(out, contains('v:numFmtId="keep"'));
      expect(out, contains('note="a numFmtId=\'9\'"'));
      expect(part.table.formatOf('0').id, 5);
      expect(part.table.formatOf('1').id, 22);
      expect(compareXml('s', out, _encode(_read(out))), isEmpty);
    });
  });

  group('an untyped part', () {
    const Map<String, String> inputs = <String, String>{
      'foreign root':
          '<other xmlns="$_main"><cellXfs><xf numFmtId="14"/>'
          '</cellXfs></other>',
      'root in another namespace':
          '<styleSheet xmlns="urn:other"><cellXfs><xf numFmtId="14"/>'
          '</cellXfs></styleSheet>',
      'no root element': '<?xml version="1.0"?><!-- nothing -->',
      'empty': '',
    };
    for (final MapEntry<String, String> e in inputs.entries) {
      test('${e.key} loads like readStyles', () {
        final PackageReader p = PackageReader(
          _packageWithStyles(e.value),
          _limits,
        );
        final StyleTable expected = readStyles(p, 'xl/styles.xml', _limits);
        final StylesPart part = _read(e.value);
        for (final String? s in <String?>[null, '0', '1', '3', 'x', '99']) {
          final CellFormat a = part.table.formatOf(s);
          final CellFormat x = expected.formatOf(s);
          expect(a.id, x.id, reason: 's=$s');
          expect(a.code, x.code, reason: 's=$s');
          expect(a.invalid, x.invalid, reason: 's=$s');
        }
        expect(_encode(part), e.value);
        expect(part.withNumberFormat(3, 22), 3);
        expect(part.withNumberFormat(null, 22), 0);
        expect(_encode(part), e.value);
      });
    }
  });

  group('kept attributes', () {
    test('survive on numFmt, numFmts and cellXfs', () {
      final String xml = _sheet(
        '<numFmts count="1" foo="a" xmlns:q="urn:q" q:bar="b">'
        '<numFmt numFmtId="164" formatCode="0.0" baz="c" q:qux="d"/>'
        '</numFmts>'
        '<cellXfs count="1" foo="e" q:bar="f"><xf numFmtId="164"/></cellXfs>',
      );
      final String out = _encode(_read(xml));
      expect(compareXml('s', xml, out), isEmpty);
      for (final String a in <String>[
        'foo="a"',
        'q:bar="b"',
        'baz="c"',
        'q:qux="d"',
        'foo="e"',
        'q:bar="f"',
      ]) {
        expect(out, contains(a));
      }
    });
  });

  group('limits and failures', () {
    test('more xfs than maxCellFormats is a limit error', () {
      final String xml = _sheet('<cellXfs count="3"><xf/><xf/><xf/></cellXfs>');
      expect(
        () => _read(xml, limits: const XlsxReadLimits(maxCellFormats: 2)),
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.limitExceeded,
          ),
        ),
      );
    });

    test('a Strict root is unsupported', () {
      expect(
        () => _read(
          '<styleSheet xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main"/>',
        ),
        throwsA(isA<XlsxReadException>()),
      );
    });
  });
}

Uint8List _packageWithStyles(String xml) =>
    buildWorkbook(<String, String?>{}, styles: xml);

/// The `styles.xml` the writer writes for [styles], registered in order.
String _writerStyles(List<XlsxStyle?> styles) {
  final StyleRegistry registry = StyleRegistry();
  styles.forEach(registry.idFor);
  final StringBuffer out = StringBuffer();
  registry.writeStylesXml(XmlWriter(out));
  return out.toString();
}

/// What the registry makes of [s]: two styles with the same key get the
/// same cell format.
List<Object?> _key(XlsxStyle s) {
  final XlsxFill? fill = s.fill;
  final bool none =
      fill == null ||
      (fill is XlsxPatternFill && fill.type == XlsxPatternType.none);
  return <Object?>[
    s.numFmt ?? XlsxNumFmt.general,
    StyleRegistry.fontKey(s.font),
    StyleRegistry.fillKey(
      none ? const XlsxFill.pattern(XlsxPatternType.none) : fill,
    ),
    StyleRegistry.borderKey(s.border ?? const XlsxBorder()),
    alignmentXml(s.alignment),
    protectionXml(s.protection),
  ];
}

int _count(String xml, String element) =>
    RegExp('<$element[ />]').allMatches(xml).length;

String? _countOf(String xml, String group) =>
    RegExp('<$group count="(\\d+)"').firstMatch(xml)?.group(1);

const XlsxStyle _boldRed = XlsxStyle(
  font: XlsxFont(bold: true, color: XlsxColor.rgb(0xFF0000)),
);

void _typedTests() {
  group('typed styles', () {
    test('styles read into values', () {
      final List<XlsxStyle> styles = m2StyleRowStyles();
      final StyleRegistry registry = StyleRegistry();
      final Map<int, XlsxStyle> byId = <int, XlsxStyle>{0: const XlsxStyle()};
      for (final XlsxStyle s in styles) {
        byId.putIfAbsent(registry.idFor(s), () => s);
      }
      final Fixture fixture = m2Fixtures().firstWhere(
        (Fixture f) => f.name == 'm2_styles',
      );
      final StylesPart part = _read(_stylesXml(fixture.build())!);
      expect(byId.length, greaterThan(50));
      for (final MapEntry<int, XlsxStyle> e in byId.entries) {
        expect(
          _key(part.styleOf(e.key)),
          _key(e.value),
          reason: 'id ${e.key}: ${e.value}',
        );
        expect(part.isExact(e.key), isTrue, reason: 'id ${e.key}');
      }
    });

    test('an inexact xf reads but stays as written', () {
      final String xml = _sheet(
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/>'
        '<diagonal/></border></borders>'
        '<cellStyleXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" '
        'borderId="0"/><xf numFmtId="0" fontId="1" fillId="0" '
        'borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" '
        'borderId="0" xfId="0"/><xf numFmtId="14" fontId="1" fillId="0" '
        'borderId="0" xfId="1" quotePrefix="1"><alignment '
        'horizontal="center"/></xf></cellXfs>',
      );
      final List<String> warnings = <String>[];
      final StylesPart part = _read(
        xml,
        warn: (XlsxWarningCode c, String d) => warnings.add(d),
      );
      final XlsxStyle s = part.styleOf(1);
      expect(s.numFmt, XlsxNumFmt.localeShortDate);
      expect(s.font?.bold, isTrue);
      expect(s.alignment?.horizontal, XlsxHorizontalAlignment.center);
      expect(part.isExact(1), isFalse);
      expect(part.isExact(0), isTrue);
      expect(warnings, isEmpty);
      expect(_encode(part), _encode(_read(xml)));
      expect(compareXml('s', xml, _encode(part)), isEmpty);
      // The inexact xf is never reused for a style that looks like it.
      expect(part.idFor(s), 2);
    });

    test('an index outside cellXfs is index 0', () {
      final StylesPart part = _read(_writerStyles(<XlsxStyle>[_boldRed]));
      expect(_key(part.styleOf(9)), _key(part.styleOf(0)));
      expect(_key(part.styleOf(-1)), _key(part.styleOf(0)));
      expect(part.isExact(9), isFalse);
      expect(_key(part.styleOf(1)), _key(_boldRed));
    });

    test('a new style appends', () {
      final String xml = _writerStyles(<XlsxStyle>[
        const XlsxStyle(numFmt: XlsxNumFmt.integer),
        const XlsxStyle(font: XlsxFont(italic: true)),
        const XlsxStyle(fill: XlsxFill.pattern(XlsxPatternType.solid)),
        const XlsxStyle(
          border: XlsxBorder(left: XlsxBorderSide(style: XlsxBorderStyle.thin)),
        ),
      ]);
      final StylesPart part = _read(xml);
      final String before = _encode(part);
      expect(_count(before, 'xf') - 1, 5); // one in cellStyleXfs
      expect(part.idFor(_boldRed), 5);
      final String after = _encode(part);
      expect(_count(after, 'font'), _count(before, 'font') + 1);
      expect(_count(after, 'xf'), _count(before, 'xf') + 1);
      expect(_count(after, 'fill'), _count(before, 'fill'));
      expect(_count(after, 'border'), _count(before, 'border'));
      for (final String g in <String>['fonts', 'cellXfs']) {
        expect(
          int.parse(_countOf(after, g)!),
          int.parse(_countOf(before, g)!) + 1,
          reason: g,
        );
      }
      expect(part.idFor(_boldRed), 5);
      expect(_encode(part), after);
      expect(_key(part.styleOf(5)), _key(_boldRed));
      expect(part.isExact(5), isTrue);
      // The saved part reads back the same.
      final StylesPart again = _read(after);
      expect(_key(again.styleOf(5)), _key(_boldRed));
      expect(again.idFor(_boldRed), 5);
    });

    test('a style matching an exact entry reuses it', () {
      final String xml = _writerStyles(<XlsxStyle>[
        const XlsxStyle(numFmt: XlsxNumFmt.integer),
        _boldRed,
      ]);
      final StylesPart part = _read(xml);
      // Spelled differently, but the same cell format.
      expect(
        part.idFor(
          const XlsxStyle(
            font: XlsxFont(
              name: 'Calibri',
              size: 11,
              bold: true,
              color: XlsxColor.argb(0xFFFF0000),
            ),
          ),
        ),
        2,
      );
      expect(part.idFor(const XlsxStyle(numFmt: XlsxNumFmt.integer)), 1);
      expect(part.idFor(null), 0);
      expect(_encode(part), _encode(_read(xml)));
    });

    test('a new number format code appends a numFmt', () {
      final String xml = _writerStyles(<XlsxStyle>[
        const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')),
      ]);
      final StylesPart part = _read(xml);
      final int id = part.idFor(
        const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0000')),
      );
      expect(id, 2);
      final String out = _encode(part);
      expect(out, contains('<numFmts count="2">'));
      expect(out, contains('<numFmt numFmtId="165" formatCode="0.0000"/>'));
      expect(part.table.formatOf('2').code, '0.0000');
      expect(part.styleOf(2).numFmt, const XlsxNumFmt.custom('0.0000'));
      expect(part.styleOf(1).numFmt, const XlsxNumFmt.custom('0.000'));
    });

    test('rollBack removes appended entries', () {
      final String xml = _writerStyles(<XlsxStyle>[
        const XlsxStyle(numFmt: XlsxNumFmt.integer),
      ]);
      final StylesPart part = _read(xml);
      final String original = _encode(part);
      final ({int fonts, int fills, int borders, int codes, int xfs}) m = part
          .mark();
      expect(m, (fonts: 1, fills: 2, borders: 1, codes: 0, xfs: 2));
      part.idFor(_boldRed);
      part.idFor(
        const XlsxStyle(
          numFmt: XlsxNumFmt.custom('0.0'),
          fill: XlsxFill.pattern(XlsxPatternType.solid),
          border: XlsxBorder(top: XlsxBorderSide(style: XlsxBorderStyle.thin)),
        ),
      );
      final ({int fonts, int fills, int borders, int codes, int xfs}) m2 = part
          .mark();
      expect(m2, (fonts: 2, fills: 3, borders: 2, codes: 1, xfs: 4));
      part.withNumberFormat(1, 22);
      expect(part.mark().xfs, 5);
      part.rollBack(m2);
      expect(part.mark(), m2);
      part.rollBack(m);
      expect(_encode(part), original);
      expect(part.table.formatOf('2').invalid, isTrue);
      // The registry starts again from what is left.
      expect(part.idFor(_boldRed), 2);
      expect(part.idFor(const XlsxStyle(numFmt: XlsxNumFmt.integer)), 1);
    });

    test('rollBack refuses a mark of another state', () {
      final StylesPart part = _read(_writerStyles(const <XlsxStyle>[]));
      expect(
        () => part.rollBack((fonts: 2, fills: 2, borders: 1, codes: 0, xfs: 1)),
        throwsArgumentError,
      );
      expect(
        () => part.rollBack((fonts: 0, fills: 2, borders: 1, codes: 0, xfs: 1)),
        throwsArgumentError,
      );
    });

    test('withNumberFormat and idFor share the cell format indexes', () {
      final StylesPart part = _read(_writerStyles(const <XlsxStyle>[]));
      expect(part.idFor(_boldRed), 1);
      expect(part.withNumberFormat(1, 14), 2);
      expect(part.idFor(const XlsxStyle(font: XlsxFont(italic: true))), 3);
      expect(part.styleOf(2).numFmt, XlsxNumFmt.localeShortDate);
      expect(part.styleOf(2).font?.bold, isTrue);
      expect(part.idFor(_boldRed), 1);
      final String out = _encode(part);
      expect(_countOf(out, 'cellXfs'), '4');
    });

    test('a missing fonts group is created in schema order', () {
      final String xml = _sheet(
        '<fills count="2"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/>'
        '<diagonal/></border></borders>'
        '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
        'borderId="0" xfId="0"/></cellXfs>',
      );
      final List<String> warnings = <String>[];
      final StylesPart part = _read(
        xml,
        warn: (XlsxWarningCode c, String d) => warnings.add(d),
      );
      final ({int fonts, int fills, int borders, int codes, int xfs}) m = part
          .mark();
      expect(m.fonts, 0);
      expect(part.idFor(_boldRed), 1);
      final String out = _encode(part);
      expect(_countOf(out, 'fonts'), '2');
      expect(out.indexOf('<fonts'), lessThan(out.indexOf('<fills')));
      final StylesPart again = _read(out);
      expect(again.styleOf(0).font, resolveFont(null));
      expect(_key(again.styleOf(1)), _key(_boldRed));
      expect(again.isExact(0), isTrue);
      part.rollBack(m);
      expect(_encode(part), _encode(_read(xml)));
      expect(warnings, <String>['cell format 0: fontId 0 points to no font.']);
    });

    test('an empty part gets every group in schema order', () {
      final StylesPart part = _read(_sheet(''));
      expect(part.styleOf(0), const XlsxStyle());
      expect(part.idFor(_boldRed), 1);
      final String out = _encode(part);
      final List<int> at = <int>[
        for (final String g in <String>['fonts', 'fills', 'borders', 'cellXfs'])
          out.indexOf('<$g count='),
      ];
      expect(at, everyElement(greaterThan(0)));
      expect(at, orderedEquals(List<int>.of(at)..sort()));
      final StylesPart again = _read(out);
      expect(_key(again.styleOf(0)), _key(const XlsxStyle()));
      expect(_key(again.styleOf(1)), _key(_boldRed));
      expect(
        again.styleOf(0).fill,
        const XlsxFill.pattern(XlsxPatternType.none),
      );
      expect(_countOf(out, 'fills'), '2');
    });

    test('a fills group of one fill gets gray125 before a new fill', () {
      final StylesPart part = _read(
        _sheet(
          '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font>'
          '</fonts><fills count="1"><fill><patternFill patternType="none"/>'
          '</fill></fills><cellXfs count="1"><xf/></cellXfs>',
        ),
      );
      const XlsxStyle solid = XlsxStyle(
        fill: XlsxFill.pattern(
          XlsxPatternType.solid,
          foreground: XlsxColor.rgb(0x00FF00),
        ),
      );
      final int id = part.idFor(solid);
      final StylesPart again = _read(_encode(part));
      expect(again.styleOf(id).fill, solid.fill);
      expect(_countOf(_encode(part), 'fills'), '3');
    });

    test('a prefixed part takes new entries in its namespace', () {
      final StylesPart part = _read(
        '<s:styleSheet xmlns:s="$_main">'
        '<s:fonts count="1"><s:font><s:sz val="11"/><s:name val="Calibri"/>'
        '</s:font></s:fonts><s:cellXfs count="1"><s:xf/></s:cellXfs>'
        '</s:styleSheet>',
      );
      final int id = part.idFor(
        const XlsxStyle(
          numFmt: XlsxNumFmt.custom('0.0'),
          fill: XlsxFill.pattern(XlsxPatternType.solid),
          font: XlsxFont(bold: true),
        ),
      );
      final String out = _encode(part);
      final StylesPart again = _read(out);
      expect(again.styleOf(id).numFmt, const XlsxNumFmt.custom('0.0'));
      expect(again.styleOf(id).font?.bold, isTrue);
      expect(
        again.styleOf(id).fill,
        const XlsxFill.pattern(XlsxPatternType.solid),
      );
      expect(again.isExact(id), isTrue);
      expect(compareXml('s', out, _encode(again)), isEmpty);
    });

    test('a dangling fontId warns styleEntryInvalid once', () {
      final List<(XlsxWarningCode, String)> warnings =
          <(XlsxWarningCode, String)>[];
      final StylesPart part = _read(
        _sheet(
          '<fonts count="1"><font><sz val="abc"/><name val="Calibri"/></font>'
          '</fonts><fills count="1"><fill><patternFill/></fill></fills>'
          '<borders count="1"><border/></borders>'
          '<cellXfs count="3"><xf fontId="0"/><xf fontId="3"/>'
          '<xf fontId="x"/></cellXfs>',
        ),
        warn: (XlsxWarningCode c, String d) => warnings.add((c, d)),
      );
      expect(part.styleOf(1).font, isNull);
      expect(part.isExact(1), isFalse);
      part.styleOf(1);
      part.isExact(1);
      expect(warnings, <(XlsxWarningCode, String)>[
        (
          XlsxWarningCode.styleEntryInvalid,
          'cell format 1: fontId 3 points to no font.',
        ),
      ]);
      part.styleOf(0);
      part.styleOf(2);
      part.idFor(_boldRed);
      expect(warnings.map(((XlsxWarningCode, String) w) => w.$2), <String>[
        'cell format 1: fontId 3 points to no font.',
        'font 0: The font size "abc" is not a finite number.',
        'cell format 2: fontId "x" is not a style index.',
      ]);
    });

    test('a new code never takes a numFmt id the file uses', () {
      final String xml = _sheet(
        '<numFmts count="1"><numFmt numFmtId="164" formatCode="0.0"/>'
        '</numFmts>'
        '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font>'
        '</fonts><fills count="1"><fill><patternFill/></fill></fills>'
        '<borders count="1"><border/></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="168"/></cellStyleXfs>'
        '<cellXfs count="2"><xf/><xf numFmtId="166"/></cellXfs>'
        '<dxfs count="1"><dxf><numFmt numFmtId="170" formatCode="0"/></dxf>'
        '</dxfs>',
      );
      final StylesPart part = _read(xml);
      part.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.00')));
      part.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')));
      final String out = _encode(part);
      final String numFmts = RegExp(
        '<numFmts.*</numFmts>',
      ).firstMatch(out)!.group(0)!;
      for (final int id in <int>[165, 166, 167, 168, 169, 170]) {
        expect(
          numFmts,
          isNot(contains('numFmtId="$id" formatCode')),
          reason: '$id',
        );
      }
      expect(out, contains('<numFmt numFmtId="171" formatCode="0.00"/>'));
      expect(out, contains('<numFmt numFmtId="172" formatCode="0.000"/>'));
      expect(part.table.formatOf('1').code, isNull);
    });

    test('a file past the font limit reuses fonts and throws to add one', () {
      final StringBuffer fonts = StringBuffer(
        '<fonts count="${XlsxLimits.maxFonts + 1}">'
        '<font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font>',
      );
      for (var i = 2; i <= XlsxLimits.maxFonts; i++) {
        fonts.write('<font><sz val="$i"/><name val="Arial"/></font>');
      }
      fonts.write('</fonts>');
      final StylesPart part = _read(
        _sheet(
          '$fonts<fills count="2"><fill><patternFill patternType="none"/>'
          '</fill><fill><patternFill patternType="gray125"/></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/>'
          '<diagonal/></border></borders><cellXfs count="1"><xf numFmtId="0" '
          'fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>',
        ),
      );
      expect(part.idFor(const XlsxStyle(font: XlsxFont(bold: true))), 1);
      final String before = _encode(part);
      final StylesMark mark = part.mark();
      expect(
        () => part.idFor(const XlsxStyle(font: XlsxFont(italic: true))),
        throwsA(isA<XlsxLimitError>()),
      );
      expect(_encode(part), before);
      expect(part.mark(), mark);
      expect(part.idFor(const XlsxStyle(font: XlsxFont(bold: true))), 1);
    });

    test('an idFor that throws changes nothing', () {
      final StylesPart part = _read(_sheet(''));
      final String before = _encode(part);
      final StylesMark mark = part.mark();
      expect(
        () => part.idFor(const XlsxStyle(font: XlsxFont(name: ''))),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'font.name',
          ),
        ),
      );
      expect(_encode(part), before);
      expect(part.mark(), mark);
      expect(part.idFor(_boldRed), 1);
    });

    test('idFor after a rollBack to a mark taken before seeding', () {
      final String xml = _sheet(
        '<fills count="1"><fill><patternFill patternType="none"/></fill>'
        '</fills><cellXfs count="1"><xf/></cellXfs>',
      );
      final StylesPart fresh = _read(xml);
      expect(fresh.idFor(_boldRed), 1);
      final StylesPart part = _read(xml);
      final StylesMark mark = part.mark();
      expect(part.idFor(const XlsxStyle(font: XlsxFont(italic: true))), 1);
      expect(part.idFor(_boldRed), 2);
      part.rollBack(mark);
      expect(_encode(part), _encode(_read(xml)));
      expect(part.idFor(_boldRed), 1);
      expect(_encode(part), _encode(fresh));
    });

    test('indexedColors reads a custom palette', () {
      final StringBuffer colors = StringBuffer('<colors><indexedColors>');
      for (var i = 0; i < 64; i++) {
        colors.write(
          '<rgbColor rgb="${i == 10 ? 'FF00AA00' : 'FF0000${i.toRadixString(16).padLeft(2, '0').toUpperCase()}'}"/>',
        );
      }
      colors.write('</indexedColors></colors>');
      final StylesPart part = _read(_sheet('$colors'));
      final List<int> palette = part.indexedColors!;
      expect(palette, hasLength(64));
      expect(palette[10], 0xFF00AA00);
      expect(palette[63], 0xFF00003F);
      expect(() => palette[0] = 1, throwsUnsupportedError);
    });

    test('indexedColors fills missing entries from the default palette', () {
      final StylesPart part = _read(
        _sheet(
          '<colors><indexedColors><rgbColor rgb="FF123456"/>'
          '<rgbColor rgb="bad"/></indexedColors></colors>',
        ),
      );
      final List<int> palette = part.indexedColors!;
      expect(palette[0], 0xFF123456);
      expect(palette[1], 0xFFFFFFFF);
      expect(palette.sublist(2), List<int>.of(_defaultTail));
    });

    test('indexedColors is null without one', () {
      expect(_read(_sheet('')).indexedColors, isNull);
      expect(
        _read(
          _sheet(
            '<colors><mruColors><color rgb="FF000000"/></mruColors></colors>',
          ),
        ).indexedColors,
        isNull,
      );
      expect(_read('').indexedColors, isNull);
    });

    test('an untyped part', () {
      final StylesPart part = _read('<other xmlns="$_main"/>');
      expect(part.styleOf(0), const XlsxStyle());
      expect(part.styleOf(3), const XlsxStyle());
      expect(part.isExact(0), isFalse);
      expect(() => part.idFor(_boldRed), throwsStateError);
      expect(part.mark(), (fonts: 0, fills: 0, borders: 0, codes: 0, xfs: 0));
      part.rollBack(part.mark());
    });
  });
}
