// Tests the axis oracle's case list, workbook writer, CSV checks and analysis
// (tool/src/axis_oracle.dart).
//
// Every row of a CSV here is hand-made to exercise the checks. The rows are
// not evidence of what Excel gives, even where one looks like a plausible
// answer. They read no files, so they run on the web as well as the VM.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/src/axis_oracle.dart';
import 'support/axis_cases.dart';

const String _c = 'http://schemas.openxmlformats.org/drawingml/2006/chart';
const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _xdr =
    'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing';

final AxisOracleCases _cases = parseAxisCases(jsonEncode(axisCasesDocument()));

/// A well-formed CSV of hand-made rows, not Excel's.
List<String> _goodLines() => <String>[
  axisCsvHeader,
  for (final AxisCase kase in _cases.cases)
    '${kase.id},${kase.height}.0,${kase.font},0.0,10.0,2.0',
];

List<String> _problems(List<String> lines) =>
    readAxisCsv(_cases, lines.join('\n')).problems;

/// [lines] with the row of [id] replaced by [row].
List<String> _withRow(List<String> lines, String id, String row) => <String>[
  for (final String line in lines) line.startsWith('$id,') ? row : line,
];

void main() {
  group('the case list', () {
    test('the cases are 60 and unique', () {
      expect(_cases.cases, hasLength(60));
      expect(_cases.cases.map((AxisCase c) => c.id).toSet(), hasLength(60));
      expect(_cases.sets, hasLength(12));
      expect(_cases.cases.first.id, 'd01-h150-f10');
      expect(_cases.cases.last.id, 'd12-h300-f18');
      expect(_cases.chartWidth, 360);
    });

    test('a value that is no number is refused', () {
      final Map<String, Object?> doc = axisCasesDocument();
      doc['sets'] = <Object?>[
        <String, Object?>{
          'id': 'd01',
          'values': <String>['1,5'],
        },
      ];
      expect(() => parseAxisCases(jsonEncode(doc)), throwsFormatException);
    });
  });

  group('the workbook', () {
    final Archive archive = ZipDecoder().decodeBytes(buildAxisWorkbook(_cases));
    XmlDocument part(String name) =>
        XmlDocument.parse(utf8.decode(archive.findFile(name)!.readBytes()!));
    Iterable<String> names(String prefix) => archive.files
        .map((ArchiveFile f) => f.name)
        .where((String n) => n.startsWith(prefix) && n.endsWith('.xml'));

    test('the workbook holds a chart per case', () {
      final List<XmlElement> sheets = part(
        'xl/workbook.xml',
      ).findAllElements('sheet').toList();
      expect(sheets.map((XmlElement s) => s.getAttribute('name')), <String>[
        ...axisCaseSets.keys,
      ]);
      expect(names('xl/worksheets/sheet'), hasLength(12));
      expect(names('xl/charts/chart'), hasLength(60));
      expect(archive.findFile('xl/theme/theme1.xml'), isNull);

      final Map<String, AxisCase> byId = <String, AxisCase>{
        for (final AxisCase kase in _cases.cases) kase.id: kase,
      };
      final Set<String> seen = <String>{};
      for (int i = 1; i <= 12; i++) {
        final XmlDocument drawing = part('xl/drawings/drawing$i.xml');
        final XmlDocument rels = part('xl/drawings/_rels/drawing$i.xml.rels');
        final List<XmlElement> anchors = drawing
            .findAllElements('absoluteAnchor', namespaceUri: _xdr)
            .toList();
        expect(anchors, hasLength(5));
        int bottom = 0;
        for (final XmlElement anchor in anchors) {
          final String name = anchor
              .findAllElements('cNvPr', namespaceUri: _xdr)
              .single
              .getAttribute('name')!;
          final AxisCase kase = byId[name]!;
          seen.add(name);
          expect(kase.set.id, 'd${'$i'.padLeft(2, '0')}');

          final XmlElement pos = anchor.getElement('xdr:pos')!;
          final XmlElement ext = anchor.getElement('xdr:ext')!;
          expect(ext.getAttribute('cy'), '${kase.height * 12700}');
          expect(ext.getAttribute('cx'), '${360 * 12700}');
          final int top = int.parse(pos.getAttribute('y')!);
          expect(top, greaterThanOrEqualTo(bottom), reason: 'no overlap');
          bottom = top + kase.height * 12700;

          final String id = anchor
              .findAllElements('chart', namespaceUri: _c)
              .single
              .getAttribute(
                'id',
                namespaceUri:
                    'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
              )!;
          final String target = rels
              .findAllElements('Relationship')
              .singleWhere((XmlElement r) => r.getAttribute('Id') == id)
              .getAttribute('Target')!;
          _checkChart(part('xl/charts/${target.split('/').last}'), kase);
        }
      }
      expect(seen, hasLength(60));
    });

    test('a sheet holds its values exactly as the case does', () {
      final XmlDocument sheet = part('xl/worksheets/sheet11.xml');
      expect(
        sheet.findAllElements('v').map((XmlElement v) => v.innerText),
        <String>['1E-7', '3E-7'],
      );
      expect(sheet.findAllElements('c').first.getAttribute('r'), 'A1');
      expect(sheet.findAllElements('drawing'), hasLength(1));
    });

    test('the same cases give the same bytes', () {
      final Uint8List first = buildAxisWorkbook(_cases);
      expect(buildAxisWorkbook(_cases), first);
    });
  });

  group('results are well formed', () {
    test('a good CSV gives no problems', () {
      final AxisCsv csv = readAxisCsv(_cases, _goodLines().join('\n'));
      expect(csv.problems, isEmpty);
      expect(csv.rows, hasLength(60));
    });

    test('a BOM, CR or CRLF line ends and a last empty line are accepted', () {
      for (final String end in <String>['\r', '\r\n']) {
        final String text = '\uFEFF${_goodLines().join(end)}$end';
        expect(readAxisCsv(_cases, text).problems, isEmpty);
      }
    });

    test('exponent forms are numbers', () {
      final AxisCsv csv = readAxisCsv(
        _cases,
        _withRow(
          _goodLines(),
          'd01-h150-f10',
          'd01-h150-f10,150,10,0.0,4.3E-7,6.1E-8',
        ).join('\n'),
      );
      expect(csv.problems, isEmpty);
      expect(csv.rows.first.max, 4.3e-7);
      expect(
        _problems(
          _withRow(
            _goodLines(),
            'd01-h150-f10',
            'd01-h150-f10,150,10,1.3E+9,9.1E+9,1.3E+9',
          ),
        ),
        isEmpty,
      );
    });

    test('a height within 1 pt is accepted', () {
      expect(
        _problems(
          _withRow(
            _goodLines(),
            'd01-h150-f10',
            'd01-h150-f10,149.0,10,0,10,2',
          ),
        ),
        isEmpty,
      );
    });

    const String id = 'd03-h300-f8';
    final Map<String, List<String> Function(List<String>)> bad =
        <String, List<String> Function(List<String>)>{
          'a missing case': (List<String> l) => <String>[
            for (final String line in l)
              if (!line.startsWith('$id,')) line,
          ],
          'an unknown case': (List<String> l) => <String>[
            ...l,
            'd99-h300-f8,300,8,0,10,2',
          ],
          'a duplicate': (List<String> l) => <String>[...l, '$id,300,8,0,10,2'],
          'a non-number': (List<String> l) =>
              _withRow(l, id, '$id,300,8,abc,10,2'),
          'a comma decimal split into a field too many': (List<String> l) =>
              _withRow(l, id, '$id,300,8,0,10,2,5'),
          'NaN as a number': (List<String> l) =>
              _withRow(l, id, '$id,300,8,0,NaN,2'),
          'max below min': (List<String> l) =>
              _withRow(l, id, '$id,300,8,10,0,2'),
          'max equal to min': (List<String> l) =>
              _withRow(l, id, '$id,300,8,10,10,2'),
          'a zero major': (List<String> l) =>
              _withRow(l, id, '$id,300,8,0,10,0'),
          'a negative major': (List<String> l) =>
              _withRow(l, id, '$id,300,8,0,10,-1'),
          'a height off by more than 1 pt': (List<String> l) =>
              _withRow(l, id, '$id,301.5,8,0,10,2'),
          'a font not the case': (List<String> l) =>
              _withRow(l, id, '$id,300,10,0,10,2'),
          'a wrong header': (List<String> l) => <String>[
            'case,height,font,minimum,max,major',
            ...l.skip(1),
          ],
        };
    bad.forEach((String name, List<String> Function(List<String>) change) {
      test('$name gives one problem', () {
        expect(_problems(change(_goodLines())), hasLength(1));
      });
    });

    test('an empty file gives one problem', () {
      expect(readAxisCsv(_cases, '').problems, hasLength(1));
    });
  });

  group('the manifest', () {
    Map<String, Object?> entry() => <String, Object?>{
      'region': 'tr-TR',
      'appleLocale': 'tr_TR',
      'excelLanguage': 'Türkçe',
      'excel': 'Microsoft Excel for Mac (a hand-made entry)',
      'macos': 'hand-made',
      'confirmedBy': 'owner',
      'csv': 'axis_oracle.tr-TR.csv',
      'notes': '',
    };

    test('an entry reads', () {
      final List<AxisManifestEntry> entries = parseAxisManifest(
        jsonEncode(<Object?>[entry()]),
      );
      expect(entries.single.region, 'tr-TR');
      expect(entries.single.csv, 'axis_oracle.tr-TR.csv');
    });

    test('an empty list reads', () {
      expect(parseAxisManifest('[]'), isEmpty);
    });

    final Map<String, void Function(Map<String, Object?>)> bad =
        <String, void Function(Map<String, Object?>)>{
          'an unknown region': (Map<String, Object?> e) =>
              e['region'] = 'fr-FR',
          'a CSV of another name': (Map<String, Object?> e) =>
              e['csv'] = 'axis_oracle.de-DE.csv',
          'a missing field': (Map<String, Object?> e) => e.remove('macos'),
          'an unknown field': (Map<String, Object?> e) => e['eye'] = 'x',
          'an entry not confirmed by the owner': (Map<String, Object?> e) =>
              e['confirmedBy'] = 'agent',
          'a field left empty': (Map<String, Object?> e) => e['excel'] = '',
          'a placeholder left in': (Map<String, Object?> e) =>
              e['appleLocale'] = '<AppleLocale>',
        };
    bad.forEach((String name, void Function(Map<String, Object?>) change) {
      test('$name is refused', () {
        final Map<String, Object?> e = entry();
        change(e);
        expect(
          () => parseAxisManifest(jsonEncode(<Object?>[e])),
          throwsFormatException,
        );
      });
    });

    test('a region twice is refused', () {
      expect(
        () => parseAxisManifest(jsonEncode(<Object?>[entry(), entry()])),
        throwsFormatException,
      );
    });
  });

  group('analyze reports what differs', () {
    // Hand-made rows, not Excel values. d01 differs across height, d02 across
    // font, and d03 and the rest in neither.
    List<AxisRow> rows() => <AxisRow>[
      for (final AxisCase kase in _cases.cases)
        AxisRow(
          id: kase.id,
          height: kase.height.toDouble(),
          font: kase.font.toDouble(),
          min: 0,
          max: kase.set.id == 'd02' && kase.font == 18 ? 20 : 10,
          major: kase.set.id == 'd01' && kase.height == 150 ? 5 : 2,
        ),
    ];

    test('per data set', () {
      final List<AxisSetFinding> findings = analyzeAxisRows(_cases, rows());
      expect(findings, hasLength(12));
      expect(findings[0].acrossHeight, <String>['major']);
      expect(findings[0].acrossFont, isEmpty);
      expect(findings[1].acrossHeight, isEmpty);
      expect(findings[1].acrossFont, <String>['max']);
      expect(findings[2].acrossHeight, isEmpty);
      expect(findings[2].acrossFont, isEmpty);
    });

    test('the report ends with the answer', () {
      final List<String> lines = axisOracleReport(
        <String, List<AxisSetFinding>>{
          'tr-TR': analyzeAxisRows(_cases, rows()),
        },
      ).trim().split('\n');
      expect(lines.first, 'tr-TR');
      expect(lines[1], 'd01: across height: major; across font: same');
      expect(lines[2], 'd02: across height: same; across font: max');
      expect(lines[3], 'd03: across height: same; across font: same');
      expect(
        lines.last,
        'answer: across height: yes (tr-TR d01); '
        'across font: yes (tr-TR d02)',
      );
    });

    test('nothing differing answers no', () {
      final List<AxisRow> same = <AxisRow>[
        for (final AxisRow row in rows())
          AxisRow(
            id: row.id,
            height: row.height,
            font: row.font,
            min: 0,
            max: 10,
            major: 2,
          ),
      ];
      expect(
        axisOracleReport(<String, List<AxisSetFinding>>{
          'tr-TR': analyzeAxisRows(_cases, same),
        }).trim().split('\n').last,
        'answer: across height: no; across font: no',
      );
    });

    test('no results says so', () {
      expect(
        axisOracleReport(const <String, List<AxisSetFinding>>{}).trim(),
        'no results',
      );
    });
  });
}

void _checkChart(XmlDocument chart, AxisCase kase) {
  final XmlElement space = chart.rootElement;
  final XmlElement defRPr = space
      .getElement('c:txPr')!
      .findAllElements('defRPr', namespaceUri: _a)
      .single;
  expect(defRPr.getAttribute('sz'), '${kase.font * 100}');
  expect(
    defRPr.getElement('a:latin')!.getAttribute('typeface'),
    'Aptos Narrow',
  );

  expect(
    chart
        .findAllElements('barDir', namespaceUri: _c)
        .single
        .getAttribute('val'),
    'col',
  );
  expect(chart.findAllElements('barChart', namespaceUri: _c), hasLength(1));
  expect(chart.findAllElements('ser', namespaceUri: _c), hasLength(1));
  expect(
    chart
        .findAllElements('autoTitleDeleted', namespaceUri: _c)
        .single
        .getAttribute('val'),
    '1',
  );
  for (final String absent in <String>['min', 'max', 'majorUnit', 'legend']) {
    expect(chart.findAllElements(absent, namespaceUri: _c), isEmpty);
  }

  final XmlElement ser = chart.findAllElements('ser', namespaceUri: _c).single;
  expect(ser.childElements.map((XmlElement e) => e.localName).take(4), <String>[
    'idx',
    'order',
    'spPr',
    'invertIfNegative',
  ]);
  expect(
    ser
        .getElement('c:spPr')!
        .findAllElements('srgbClr', namespaceUri: _a)
        .single
        .getAttribute('val'),
    '156082',
  );

  final XmlElement val = chart.findAllElements('val', namespaceUri: _c).single;
  final int n = kase.set.values.length;
  expect(
    val.findAllElements('f', namespaceUri: _c).single.innerText,
    "'${kase.set.id}'!\$B\$1:\$B\$$n",
  );
  expect(
    val
        .findAllElements('pt', namespaceUri: _c)
        .map((XmlElement p) => p.getElement('c:v')!.innerText),
    kase.set.values,
  );
  final XmlElement cat = chart.findAllElements('cat', namespaceUri: _c).single;
  expect(
    cat.getElement('c:strRef')!.getElement('c:f')!.innerText,
    "'${kase.set.id}'!\$A\$1:\$A\$$n",
  );
}
