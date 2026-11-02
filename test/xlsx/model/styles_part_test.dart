import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/model/styles_part.dart';
import 'package:jet_office/src/xlsx/read/package_reader.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/read/styles_reader.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
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

StylesPart _read(String xml, {XlsxReadLimits limits = _limits}) =>
    StylesPart.read(XmlPullReader(xml), limits);

String _encode(PartContent part) =>
    utf8.decode(<int>[for (final Uint8List c in part.encode()) ...c]);

String _sheet(String body, {String attrs = ''}) =>
    '<styleSheet xmlns="$_main"$attrs>$body</styleSheet>';

void main() {
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
