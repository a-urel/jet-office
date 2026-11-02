// Tests the semantic comparer for XLSX packages (phase 3, W1): the
// yardstick the round-trip tests use to say that opening and saving a file
// keeps every part. They build small ZIPs in memory and read no files, so
// they run on the web as well as the VM.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../xlsx/read/support/zip_builder.dart';

const String _types =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
    '</Types>';

const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

Uint8List _zip(Map<String, Object> parts) => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(_types),
  for (final MapEntry<String, Object> p in parts.entries)
    p.key: p.value is String
        ? utf8.encode(p.value as String)
        : p.value as List<int>,
});

String _sheet(List<String> cells) =>
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetData><row r="1">${cells.join()}</row></sheetData></worksheet>';

String _sst(List<String> strings) =>
    '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'count="9" uniqueCount="${strings.length}">'
    '${strings.map((String s) => '<si><t>$s</t></si>').join()}</sst>';

void main() {
  test('equal packages compare equal', () {
    final Uint8List a = _zip(<String, Object>{'xl/a.xml': '<a x="1"/>'});
    expect(comparePackages(a, a), isEmpty);
  });

  test('attribute order, prefixes and whitespace are ignored', () {
    final Uint8List e = _zip(<String, Object>{
      'xl/a.xml': '<a xmlns="u" x="1" y="2"/>',
    });
    final Uint8List a = _zip(<String, Object>{
      'xl/a.xml': '<p:a xmlns:p="u" y="2" x="1"></p:a>',
    });
    expect(comparePackages(e, a), isEmpty);
    expect(compareXml('xl/a.xml', '<r>\n  <b/>\n</r>', '<r><b/></r>'), isEmpty);
  });

  test('a changed attribute is reported', () {
    final Uint8List e = _zip(<String, Object>{'xl/a.xml': '<a x="1"/>'});
    final Uint8List a = _zip(<String, Object>{'xl/a.xml': '<a x="2"/>'});
    final List<String> diff = comparePackages(e, a);
    expect(diff, hasLength(1));
    expect(
      diff.single,
      allOf(contains('xl/a.xml'), contains('attribute x'), contains('"2"')),
    );
  });

  test('a missing part is reported', () {
    final Uint8List e = _zip(<String, Object>{
      'xl/a.xml': '<a/>',
      'xl/b.xml': '<b/>',
    });
    final Uint8List a = _zip(<String, Object>{'xl/a.xml': '<a/>'});
    final List<String> diff = comparePackages(e, a);
    expect(diff, hasLength(1));
    expect(diff.single, contains('xl/b.xml'));
    expect(comparePackages(e, a, ignoreParts: <String>{'xl/b.xml'}), isEmpty);
  });

  test('an added part is reported unless allowed', () {
    final Uint8List e = _zip(<String, Object>{'xl/a.xml': '<a/>'});
    final Uint8List a = _zip(<String, Object>{
      'xl/a.xml': '<a/>',
      'xl/b.xml': '<b/>',
    });
    final List<String> diff = comparePackages(e, a);
    expect(diff, hasLength(1));
    expect(diff.single, contains('xl/b.xml'));
    expect(comparePackages(e, a, allowAdded: <String>{'xl/b.xml'}), isEmpty);
  });

  group('shared strings', () {
    Uint8List pkg(List<String> strings, List<int> indexes) =>
        _zip(<String, Object>{
          'xl/sharedStrings.xml': _sst(strings),
          'xl/worksheets/sheet1.xml': _sheet(<String>[
            for (int i = 0; i < indexes.length; i++)
              '<c r="${'AB'[i]}2" t="s"><v>${indexes[i]}</v></c>',
          ]),
        });

    test('compare by text, not index', () {
      final Uint8List e = pkg(<String>['x', 'y'], <int>[0, 1]);
      final Uint8List a = pkg(<String>['y', 'x'], <int>[1, 0]);
      expect(comparePackages(e, a), isEmpty);
    });

    test('a changed cell text is reported at the cell', () {
      final Uint8List e = pkg(<String>['x', 'y'], <int>[0, 1]);
      final Uint8List a = pkg(<String>['x', 'z'], <int>[0, 1]);
      final List<String> diff = comparePackages(e, a);
      expect(
        diff.where((String l) => l.contains('xl/worksheets/sheet1.xml: B2')),
        hasLength(1),
        reason: '$diff',
      );
    });
  });

  test('relationship ids compare through targets', () {
    String wb(String first, String second) =>
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="$_rel"><sheets>'
        '<sheet name="A" sheetId="1" r:id="$first"/>'
        '<sheet name="B" sheetId="2" r:id="$second"/></sheets></workbook>';
    String rels(String first, String second) =>
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="$first" Type="$_rel/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="$second" Type="$_rel/worksheet" Target="worksheets/sheet2.xml"/>'
        '</Relationships>';
    final Uint8List e = _zip(<String, Object>{
      'xl/workbook.xml': wb('rId1', 'rId2'),
      'xl/_rels/workbook.xml.rels': rels('rId1', 'rId2'),
    });
    final Uint8List a = _zip(<String, Object>{
      'xl/workbook.xml': wb('rId2', 'rId1'),
      'xl/_rels/workbook.xml.rels': rels('rId2', 'rId1'),
    });
    expect(comparePackages(e, a), isEmpty);

    final Uint8List wrong = _zip(<String, Object>{
      'xl/workbook.xml': wb('rId2', 'rId1'),
      'xl/_rels/workbook.xml.rels': rels('rId1', 'rId2'),
    });
    expect(comparePackages(e, wrong), isNotEmpty);
  });

  test('binary parts compare byte for byte', () {
    final Uint8List e = _zip(<String, Object>{
      'xl/media/image1.png': <int>[1, 2, 3, 4],
    });
    final Uint8List a = _zip(<String, Object>{
      'xl/media/image1.png': <int>[1, 2, 9, 4],
    });
    final List<String> diff = comparePackages(e, a);
    expect(diff, hasLength(1));
    expect(diff.single, contains('xl/media/image1.png'));
  });

  test('significant whitespace is kept', () {
    final List<String> diff = compareXml(
      'xl/sharedStrings.xml',
      '<t xml:space="preserve"> a</t>',
      '<t xml:space="preserve">a</t>',
    );
    expect(diff, hasLength(1));
  });

  test('preserved whitespace reaches the descendants', () {
    final List<String> diff = compareXml(
      'xl/a.xml',
      '<a xml:space="preserve"><b> x</b></a>',
      '<a xml:space="preserve"><b>x</b></a>',
    );
    expect(diff, hasLength(1));
  });

  test('the spaces around a leaf text are kept', () {
    expect(
      compareXml(
        'xl/workbook.xml',
        '<definedName> A</definedName>',
        '<definedName>A</definedName>',
      ),
      hasLength(1),
    );
    expect(
      compareXml('xl/a.xml', '<r>\n  <b> </b>\n</r>', '<r><b> </b></r>'),
      isEmpty,
    );
  });

  test('bytes that are not a ZIP are reported, not thrown', () {
    final Uint8List good = _zip(<String, Object>{'xl/a.xml': '<a/>'});
    final Uint8List bad = Uint8List.fromList(utf8.encode('not a zip at all'));
    expect(comparePackages(good, bad), hasLength(1));
    expect(comparePackages(bad, good), hasLength(1));
  });

  test('an undecodable part is reported, not thrown', () {
    final Uint8List good = _zip(<String, Object>{'xl/a.xml': '<a/>'});
    final Uint8List bad = _zip(<String, Object>{
      'xl/a.xml': <int>[0x3c, 0x61, 0x3e, 0xff, 0xfe, 0x3c, 0x2f, 0x61, 0x3e],
    });
    final List<String> diff = comparePackages(good, bad);
    expect(diff, hasLength(1));
    expect(diff.single, contains('xl/a.xml'));
  });
}
