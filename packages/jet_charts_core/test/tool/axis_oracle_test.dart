// Tests the axis oracle's case list, workbook writer, CSV checks and analysis
// (tool/src/axis_oracle.dart).
//
// Every row of a CSV here is hand-made to exercise the checks. The rows are
// not evidence of what Excel gives, even where one looks like a plausible
// answer. They read no files, so they run on the web as well as the VM.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show provisionalMaxIntervals;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/src/axis_oracle.dart';
import 'support/axis_cases.dart';
import 'support/axis_full_cases.dart';

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

  _fullTests();
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

final AxisFullCases _full = parseAxisFullCases(
  jsonEncode(axisFullCasesDocument()),
);

/// The plot box of a hand-made row: inside the chart, not Excel's.
String _plotFields(AxisFullCase kase) =>
    '10,10,${kase.width * 0.8},${kase.height * 0.8}';

/// A well-formed version 2 CSV of hand-made rows, not Excel's.
List<String> _goodFullLines() => <String>[
  axisFullCsvHeader,
  for (final AxisFullCase kase in _full.cases)
    '${kase.id},${kase.width}.0,${kase.height}.0,${kase.font},0.0,10.0,2.0,'
        '${_plotFields(kase)},${kase.categories == null ? '' : '1'}',
];

List<String> _fullProblems(List<String> lines) =>
    readAxisFullCsv(_full, lines.join('\n')).problems;

void _fullTests() {
  group('version 2', () {
    test('version 2 cases are unique and complete', () {
      final Map<String, int> byGroup = <String, int>{};
      for (final AxisFullCase kase in _full.cases) {
        byGroup[kase.group] = (byGroup[kase.group] ?? 0) + 1;
      }
      // ignore: avoid_print
      print('axis oracle (full): ${_full.cases.length} cases, $byGroup');
      expect(byGroup, <String, int>{
        'L': 94,
        'W': 20,
        'B': 80,
        'M': 19,
        'G': 12,
        'F': 5,
        'C': 9,
      });
      expect(_full.cases, hasLength(239));
      expect(_full.cases.map((AxisFullCase c) => c.id).toSet(), hasLength(239));
      expect(_full.cases.first.id, 'L05-w360-h60-f10');
      expect(_full.cases.last.id, 'C03-w720-h300-f10');
      for (final String kind in <String>['column', 'bar', 'line', 'area']) {
        expect(_full.cases.any((AxisFullCase c) => c.kind == kind), isTrue);
      }
      for (final String grouping in <String>[
        'clustered',
        'stacked',
        'percentStacked',
      ]) {
        expect(
          _full.cases.any((AxisFullCase c) => c.grouping == grouping),
          isTrue,
        );
      }
    });

    test('each L set has as many intervals as its number', () {
      for (final MapEntry<String, List<String>> set
          in axisFullLengthSets.entries) {
        final ({double min, double max}) extent = dataExtent(<List<double?>>[
          set.value.map(double.parse).toList(),
        ], ChartGrouping.clustered);
        final ValueScale scale = autoValueScale(
          dataMin: extent.min,
          dataMax: extent.max,
          maxIntervals: 10,
        );
        expect(
          ((scale.max - scale.min) / scale.majorUnit).round(),
          int.parse(set.key),
          reason: 'L${set.key}',
        );
        final AxisFullCase kase = _full.cases.firstWhere(
          (AxisFullCase c) => c.id.startsWith('L${set.key}-'),
        );
        expect(kase.series, <List<String>>[set.value]);
      }
    });

    test('the C labels are 3, 12 and 30 characters', () {
      expect(
        <int>[for (final List<String> l in axisFullLabels) l.first.length],
        <int>[3, 12, 30],
      );
      for (final List<String> labels in axisFullLabels) {
        expect(labels, hasLength(12));
        expect(labels.map((String l) => l.length).toSet(), hasLength(1));
      }
    });

    test('a case id that does not match its size is refused', () {
      final Map<String, Object?> doc = axisFullCasesDocument();
      final List<Object?> cases = doc['cases']! as List<Object?>;
      (cases.first! as Map<String, Object?>)['height'] = 61;
      expect(() => parseAxisFullCases(jsonEncode(doc)), throwsFormatException);
    });

    test('an unknown kind or a value that is no number is refused', () {
      for (final void Function(Map<String, Object?>) change
          in <void Function(Map<String, Object?>)>[
            (Map<String, Object?> c) => c['kind'] = 'pie',
            (Map<String, Object?> c) => c['grouping'] = 'standard',
            (Map<String, Object?> c) => c['series'] = <Object?>[
              <String>['1,5'],
            ],
            (Map<String, Object?> c) => c['series'] = <Object?>[],
            (Map<String, Object?> c) => c['fixedMin'] = '0',
          ]) {
        final Map<String, Object?> doc = axisFullCasesDocument();
        change((doc['cases']! as List<Object?>).first! as Map<String, Object?>);
        expect(
          () => parseAxisFullCases(jsonEncode(doc)),
          throwsFormatException,
        );
      }
    });

    test('version 1 and version 2 do not read as each other', () {
      expect(
        () => parseAxisFullCases(jsonEncode(axisCasesDocument())),
        throwsFormatException,
      );
      expect(
        () => parseAxisCases(jsonEncode(axisFullCasesDocument())),
        throwsFormatException,
      );
    });

    group('the workbook', () {
      final Archive archive = ZipDecoder().decodeBytes(
        buildAxisFullWorkbook(_full),
      );
      XmlDocument part(String name) =>
          XmlDocument.parse(utf8.decode(archive.findFile(name)!.readBytes()!));

      test('the workbook holds a version 2 chart per case', () {
        final List<XmlElement> sheets = part(
          'xl/workbook.xml',
        ).findAllElements('sheet').toList();
        expect(sheets.map((XmlElement s) => s.getAttribute('name')), <String>[
          'length',
          'width',
          'bar',
          'minmax',
          'grouping',
          'fixed',
          'labels',
        ]);
        final Map<String, AxisFullCase> byId = <String, AxisFullCase>{
          for (final AxisFullCase kase in _full.cases) kase.id: kase,
        };
        final Set<String> seen = <String>{};
        for (int i = 1; i <= sheets.length; i++) {
          final String sheetName = sheets[i - 1].getAttribute('name')!;
          final XmlDocument drawing = part('xl/drawings/drawing$i.xml');
          final XmlDocument rels = part('xl/drawings/_rels/drawing$i.xml.rels');
          int bottom = 0;
          for (final XmlElement anchor in drawing.findAllElements(
            'absoluteAnchor',
            namespaceUri: _xdr,
          )) {
            final String name = anchor
                .findAllElements('cNvPr', namespaceUri: _xdr)
                .single
                .getAttribute('name')!;
            final AxisFullCase kase = byId[name]!;
            expect(seen.add(name), isTrue);
            final XmlElement pos = anchor.getElement('xdr:pos')!;
            final XmlElement ext = anchor.getElement('xdr:ext')!;
            expect(ext.getAttribute('cx'), '${kase.width * 12700}');
            expect(ext.getAttribute('cy'), '${kase.height * 12700}');
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
            _checkFullChart(
              part('xl/charts/${target.split('/').last}'),
              kase,
              sheetName,
            );
          }
        }
        expect(seen, hasLength(239));
      });

      test('a blank value is an empty cell', () {
        final XmlDocument sheet = part('xl/worksheets/sheet4.xml');
        final List<AxisFullCase> minMax = <AxisFullCase>[
          for (final AxisFullCase kase in _full.cases)
            if (kase.group == 'M') kase,
        ];
        expect(
          minMax
              .singleWhere((AxisFullCase c) => c.id == 'M11-w360-h300-f10')
              .series
              .single,
          <String>['1', '', '3'],
        );
        expect(
          sheet
              .findAllElements('c')
              .where((XmlElement c) => c.getAttribute('r')!.startsWith('B'))
              .length,
          minMax
              .expand((AxisFullCase c) => c.series.first)
              .where((String v) => v.isNotEmpty)
              .length,
        );
        expect(
          sheet.findAllElements('v').where((XmlElement v) => v.innerText == ''),
          isEmpty,
        );
      });

      test('the same cases give the same bytes', () {
        expect(buildAxisFullWorkbook(_full), buildAxisFullWorkbook(_full));
      });
    });

    group('version 2 results are well formed', () {
      test('a good CSV gives no problems', () {
        final AxisFullCsv csv = readAxisFullCsv(
          _full,
          _goodFullLines().join('\n'),
        );
        expect(csv.problems, isEmpty);
        expect(csv.rows, hasLength(239));
        final AxisFullRow c = csv.rows.last;
        expect(c.labelSpacing, 1);
        expect(c.plotWidth, 720 * 0.8);
        expect(csv.rows.first.labelSpacing, isNull);
      });

      test('a BOM and CRLF line ends are accepted', () {
        expect(
          readAxisFullCsv(
            _full,
            '﻿${_goodFullLines().join('\r\n')}\r\n',
          ).problems,
          isEmpty,
        );
      });

      const String id = 'C01-w180-h300-f10';
      final Map<String, String> accepted = <String, String>{
        'a width and height within 1 pt':
            '$id,179.2,300.9,10,0,10,2,10,10,144,240,1',
        'a plot box to the edge plus 1 pt':
            '$id,180,300,10,0,10,2,-1,0,182,301,1',
        'exponent forms': '$id,180,300,10,0,1.0E+2,2.5E+1,10,10,144,240,3',
      };
      accepted.forEach((String name, String row) {
        test('$name is accepted', () {
          expect(_fullProblems(_withRow(_goodFullLines(), id, row)), isEmpty);
        });
      });

      test('an empty labelSpacing is accepted on a case without labels', () {
        const String m01 = 'M01-w360-h300-f10';
        expect(
          _fullProblems(
            _withRow(
              _goodFullLines(),
              m01,
              '$m01,360,300,10,0,120,20,10,10,288,240,',
            ),
          ),
          isEmpty,
        );
      });

      const String f05 = 'F05-w360-h300-f10';
      test('max equal to min is accepted where both are fixed equal', () {
        expect(
          _fullProblems(
            _withRow(
              _goodFullLines(),
              f05,
              '$f05,360,300,10,5,5,1,10,10,288,240,',
            ),
          ),
          isEmpty,
        );
      });

      test('max below min gives one problem even where both are fixed', () {
        expect(
          _fullProblems(
            _withRow(
              _goodFullLines(),
              f05,
              '$f05,360,300,10,5,4,1,10,10,288,240,',
            ),
          ),
          hasLength(1),
        );
      });

      final Map<String, List<String> Function(List<String>)> bad =
          <String, List<String> Function(List<String>)>{
            'a missing case': (List<String> l) => <String>[
              for (final String line in l)
                if (!line.startsWith('$id,')) line,
            ],
            'an unknown case': (List<String> l) => <String>[
              ...l,
              'C09-w180-h300-f10,180,300,10,0,10,2,10,10,144,240,1',
            ],
            'a duplicate': (List<String> l) => <String>[
              ...l,
              '$id,180,300,10,0,10,2,10,10,144,240,1',
            ],
            'a field too few': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,10,144,240'),
            'a field too many': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,10,144,240,1,1'),
            'a non-number scale field': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,abc,10,2,10,10,144,240,1'),
            'a non-number plot field': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,,144,240,1'),
            'max not above min': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,10,10,2,10,10,144,240,1'),
            'a zero major': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,0,10,10,144,240,1'),
            'a width off by more than 1 pt': (List<String> l) =>
                _withRow(l, id, '$id,181.5,300,10,0,10,2,10,10,144,240,1'),
            'a height off by more than 1 pt': (List<String> l) =>
                _withRow(l, id, '$id,180,298.5,10,0,10,2,10,10,144,240,1'),
            'a font not the case': (List<String> l) =>
                _withRow(l, id, '$id,180,300,8,0,10,2,10,10,144,240,1'),
            'a plot box past the right edge': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,40,10,144,240,1'),
            'a plot box past the bottom edge': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,70,144,240,1'),
            'a plot box left of the chart': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,-2,10,144,240,1'),
            'a negative plot height': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,10,144,-5,1'),
            'a zero labelSpacing': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,10,144,240,0'),
            'a fractional labelSpacing': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,10,144,240,1.5'),
            'a labelSpacing that is no number': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,10,144,240,x'),
            'an empty labelSpacing on a case with labels': (List<String> l) =>
                _withRow(l, id, '$id,180,300,10,0,10,2,10,10,144,240,'),
            'max equal to min where nothing is fixed': (List<String> l) =>
                _withRow(
                  l,
                  'F01-w360-h300-f10',
                  'F01-w360-h300-f10,360,300,10,5,5,1,10,10,288,240,',
                ),
            'a version 1 header': (List<String> l) => <String>[
              axisCsvHeader,
              ...l.skip(1),
            ],
          };
      bad.forEach((String name, List<String> Function(List<String>) change) {
        test('$name gives one problem', () {
          expect(_fullProblems(change(_goodFullLines())), hasLength(1));
        });
      });
    });

    test('a full manifest names axis_oracle_full CSVs', () {
      Map<String, Object?> entry(String csv) => <String, Object?>{
        'region': 'tr-TR',
        'appleLocale': 'tr_TR',
        'excelLanguage': 'Türkçe',
        'excel': 'hand-made',
        'macos': 'hand-made',
        'confirmedBy': 'owner',
        'csv': csv,
        'notes': '',
      };
      expect(
        parseAxisManifest(
          jsonEncode(<Object?>[entry('axis_oracle_full.tr-TR.csv')]),
          csvStem: 'axis_oracle_full',
        ).single.csv,
        'axis_oracle_full.tr-TR.csv',
      );
      expect(
        () => parseAxisManifest(
          jsonEncode(<Object?>[entry('axis_oracle.tr-TR.csv')]),
          csvStem: 'axis_oracle_full',
        ),
        throwsFormatException,
      );
    });

    group('analyze --full reports each group', () {
      // Hand-made rows, not Excel values. L05 coarsens below height 120, W06
      // at height 300 changes its major at width 720, and C01 spaces its
      // labels by 3 at width 180.
      List<AxisFullRow> rows() => <AxisFullRow>[
        for (final AxisFullCase kase in _full.cases)
          AxisFullRow(
            id: kase.id,
            width: kase.width.toDouble(),
            height: kase.height.toDouble(),
            font: kase.font.toDouble(),
            min: 0,
            max: kase.id.startsWith('L05-') && kase.height < 120 ? 30 : 10,
            major: kase.id.startsWith('L05-') && kase.height < 120
                ? 10
                : kase.id.startsWith('L05-')
                ? 5
                : kase.id == 'W06-w720-h300-f10'
                ? 5
                : 2,
            plotLeft: 10,
            plotTop: 10,
            plotWidth: kase.width * 0.8,
            plotHeight: kase.height * 0.8,
            labelSpacing: kase.categories == null
                ? null
                : kase.id == 'C01-w180-h300-f10'
                ? 3
                : 1,
          ),
      ];
      late List<String> lines;
      setUp(() {
        lines = axisFullReport(_full, <String, List<AxisFullRow>>{
          'tr-TR': rows(),
        }).trim().split('\n');
      });

      test('L and B give the plot length of each unit', () {
        expect(lines.first, 'tr-TR');
        expect(
          lines,
          contains(
            'L05 f10: plot 48-220: 0 to 30 by 10 at 48-80, '
            '0 to 10 by 5 at 96-220',
          ),
        );
        expect(lines, contains('L10 f10: plot 48-640: 0 to 10 by 2'));
        expect(lines, contains('L06 f18: plot 80-120: 0 to 10 by 2'));
        expect(lines, contains('B05 f10: plot 64-480: 0 to 10 by 2'));
      });

      test('W says whether width changed anything', () {
        expect(lines, contains('W05 h150: across width: same'));
        expect(lines, contains('W06 h300: across width: major'));
      });

      test('M, G and F stand beside the provisional rule', () {
        final String m01 = lines.singleWhere(
          (String l) => l.startsWith('M01-w360-h300-f10:'),
        );
        expect(m01, startsWith('M01-w360-h300-f10: Excel 0 to 10 by 2; '));
        expect(m01, contains('provisional'));
        expect(m01, endsWith('at plot 240: differs'));
        final ValueScale g09 = autoValueScale(
          dataMin: 0,
          dataMax: 9,
          maxIntervals: provisionalMaxIntervals(288),
          percent: true,
        );
        expect(
          lines.singleWhere((String l) => l.startsWith('G08-')),
          'G08-w360-h300-f10: Excel 0 to 10 by 2; provisional 0 to 1 by '
          '${g09.majorUnit} at plot 288: differs',
        );
        expect(lines.where((String l) => l.startsWith('F')), hasLength(5));
      });

      test('C gives the label spacing per width', () {
        expect(lines, contains('C01 (3 characters): w180 3; w360 1; w720 1'));
        expect(lines, contains('C03 (30 characters): w180 1; w360 1; w720 1'));
      });

      test('no results says so', () {
        expect(
          axisFullReport(_full, const <String, List<AxisFullRow>>{}).trim(),
          'no results',
        );
      });
    });
  });
}

void _checkFullChart(XmlDocument chart, AxisFullCase kase, String sheet) {
  final XmlElement space = chart.rootElement;
  expect(
    space
        .getElement('c:txPr')!
        .findAllElements('defRPr', namespaceUri: _a)
        .single
        .getAttribute('sz'),
    '${kase.font * 100}',
  );
  final XmlElement plot = chart
      .findAllElements('plotArea', namespaceUri: _c)
      .single;
  final String kindElement = switch (kase.kind) {
    'column' || 'bar' => 'barChart',
    'line' => 'lineChart',
    _ => 'areaChart',
  };
  final XmlElement group = plot.getElement('c:$kindElement')!;
  expect(
    plot.childElements
        .where((XmlElement e) => e.localName.endsWith('Chart'))
        .toList(),
    <XmlElement>[group],
  );
  if (kindElement == 'barChart') {
    expect(
      group.getElement('c:barDir')!.getAttribute('val'),
      kase.kind == 'bar' ? 'bar' : 'col',
    );
    final XmlElement? overlap = group.getElement('c:overlap');
    if (kase.grouping == 'clustered') {
      expect(overlap, isNull);
    } else {
      expect(overlap!.getAttribute('val'), '100');
    }
    expect(
      plot.getElement('c:valAx')!.getElement('c:axPos')!.getAttribute('val'),
      kase.kind == 'bar' ? 'b' : 'l',
    );
  }
  final String grouping = group.getElement('c:grouping')!.getAttribute('val')!;
  expect(
    grouping,
    kase.grouping == 'clustered' && kindElement != 'barChart'
        ? 'standard'
        : kase.grouping,
  );

  final List<XmlElement> sers = group.findElements('c:ser').toList();
  expect(sers, hasLength(kase.series.length));
  for (int s = 0; s < sers.length; s++) {
    final List<String> values = kase.series[s];
    final XmlElement val = sers[s].getElement('c:val')!;
    final String column = String.fromCharCode('B'.codeUnitAt(0) + s);
    expect(
      val.findAllElements('f', namespaceUri: _c).single.innerText,
      matches(RegExp("^'$sheet'!\\\$$column\\\$\\d+:\\\$$column\\\$\\d+\$")),
    );
    expect(
      val
          .findAllElements('ptCount', namespaceUri: _c)
          .single
          .getAttribute('val'),
      '${values.length}',
    );
    expect(
      <String, String>{
        for (final XmlElement p in val.findAllElements('pt', namespaceUri: _c))
          p.getAttribute('idx')!: p.getElement('c:v')!.innerText,
      },
      <String, String>{
        for (int i = 0; i < values.length; i++)
          if (values[i].isNotEmpty) '$i': values[i],
      },
    );
    final XmlElement? cat = sers[s].getElement('c:cat');
    if (kase.categories == null) {
      expect(cat, isNull);
    } else {
      final RegExpMatch rows = RegExp(r'\$(\d+):\$[A-Z]\$(\d+)$').firstMatch(
        val.findAllElements('f', namespaceUri: _c).single.innerText,
      )!;
      final int first = int.parse(rows.group(1)!);
      final int last = int.parse(rows.group(2)!);
      expect(last - first + 1, values.length);
      expect(
        cat!.getElement('c:strRef')!.getElement('c:f')!.innerText,
        "'$sheet'!\$A\$$first:\$A\$$last",
      );
      expect(
        cat
            .getElement('c:strRef')!
            .findAllElements('v', namespaceUri: _c)
            .map((XmlElement v) => v.innerText),
        kase.categories,
      );
    }
  }

  final XmlElement valAx = plot.getElement('c:valAx')!;
  final XmlElement scaling = valAx.getElement('c:scaling')!;
  String? fixed(XmlElement parent, String name) =>
      parent.getElement('c:$name')?.getAttribute('val');
  String? text(double? value) => value == null
      ? null
      : value == value.roundToDouble()
      ? '${value.toInt()}'
      : '$value';
  expect(fixed(scaling, 'min'), text(kase.fixedMin));
  expect(fixed(scaling, 'max'), text(kase.fixedMax));
  expect(fixed(valAx, 'majorUnit'), text(kase.fixedMajor));
}
