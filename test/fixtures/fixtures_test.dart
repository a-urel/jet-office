import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/src/csv_compare.dart' show decodeXstring;
import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';
import 'fixtures.dart';

/// What a sheet stores: its rectangle of cell text and the cells that hold a
/// formula, as (row, column) pairs counted from 1.
typedef _Sheet = ({List<List<String>> rows, Set<(int, int)> formulas});

/// Every sheet in [bytes], as stored, keyed by decoded sheet name. Empty
/// cells are `''`.
Map<String, _Sheet> _readSheets(Uint8List bytes) {
  final Map<String, String> parts = readXlsx(bytes);
  final List<String> strings = <String>[
    for (final XmlElement si in XmlDocument.parse(
      parts['xl/sharedStrings.xml']!,
    ).findAllElements('si'))
      si.findAllElements('t').map((XmlElement t) => t.innerText).join(),
  ];
  final Map<String, String> targets = <String, String>{
    for (final XmlElement r in XmlDocument.parse(
      parts['xl/_rels/workbook.xml.rels']!,
    ).findAllElements('Relationship'))
      r.getAttribute('Id')!: 'xl/${r.getAttribute('Target')!}',
  };
  final Map<String, _Sheet> result = <String, _Sheet>{};
  for (final XmlElement sheet in XmlDocument.parse(
    parts['xl/workbook.xml']!,
  ).findAllElements('sheet')) {
    final XmlDocument doc = XmlDocument.parse(
      parts[targets[sheet.getAttribute('r:id')!]]!,
    );
    final Map<(int, int), String> cells = <(int, int), String>{};
    final Set<(int, int)> formulas = <(int, int)>{};
    int rows = 0;
    int columns = 0;
    for (final XmlElement row in doc.findAllElements('row')) {
      final int r = int.parse(row.getAttribute('r')!);
      for (final XmlElement c in row.findElements('c')) {
        final String letters = c
            .getAttribute('r')!
            .replaceAll(RegExp(r'\d'), '');
        int column = 0;
        for (final int unit in letters.codeUnits) {
          column = column * 26 + unit - 0x40;
        }
        final String v = c.getElement('v')?.innerText ?? '';
        cells[(r, column)] = c.getAttribute('t') == 's'
            ? strings[int.parse(v)]
            : v;
        if (c.getElement('f') != null) formulas.add((r, column));
        if (r > rows) rows = r;
        if (column > columns) columns = column;
      }
    }
    // A reader decodes `_xHHHH_` in sheet names too (ruling R22).
    result[decodeXstring(sheet.getAttribute('name')!)] = (
      rows: <List<String>>[
        for (int r = 1; r <= rows; r++)
          <String>[for (int c = 1; c <= columns; c++) cells[(r, c)] ?? ''],
      ],
      formulas: formulas,
    );
  }
  return result;
}

void main() {
  final List<Fixture> fixtures = allFixtures();

  test('fixture names are unique', () {
    final List<String> names = <String>[
      for (final Fixture f in fixtures) f.name,
    ];
    expect(names.toSet(), hasLength(names.length));
  });

  for (final Fixture f in fixtures) {
    group(f.name, () {
      test('passes the consistency checker', () {
        expect(checkXlsx(f.build()), isEmpty);
      });

      test('is deterministic', () {
        expect(f.build(), f.build());
      });

      test('storedValues describe what the file stores', () {
        final Map<String, _Sheet> sheets = _readSheets(f.build());
        expect(<String, List<List<String>>>{
          for (final MapEntry<String, _Sheet> e in sheets.entries)
            e.key: e.value.rows,
        }, f.storedValues);
      });

      test('expectedValues agree with storedValues', () {
        final Map<String, _Sheet> sheets = _readSheets(f.build());
        expect(
          f.expectedValues.keys.toSet(),
          f.storedValues.keys.toSet(),
          reason: 'same sheets',
        );
        f.expectedValues.forEach((String sheet, List<List<Object?>> rows) {
          final List<List<String>> stored = f.storedValues[sheet]!;
          final int height = rows.length > stored.length
              ? rows.length
              : stored.length;
          for (int r = 0; r < height; r++) {
            final List<Object?> want = r < rows.length ? rows[r] : <Object?>[];
            final List<String> raw = r < stored.length ? stored[r] : <String>[];
            final int width = want.length > raw.length
                ? want.length
                : raw.length;
            for (int c = 0; c < width; c++) {
              // A formula cell holds the value a reader computes, which the
              // file may not store, so only its cell is exempt.
              if (sheets[sheet]!.formulas.contains((r + 1, c + 1))) continue;
              final Object? e = c < want.length ? want[c] : null;
              final String s = c < raw.length ? raw[c] : '';
              final String at = '$sheet r${r + 1} c${c + 1}';
              switch (e) {
                case null:
                  expect(s, '', reason: at);
                case bool():
                  expect(s, e ? '1' : '0', reason: at);
                case num():
                  final double got = double.parse(s);
                  final double scale = e.abs() > got.abs()
                      ? e.abs().toDouble()
                      : got.abs();
                  expect(
                    (got - e).abs(),
                    lessThanOrEqualTo(1e-12 * scale),
                    reason: at,
                  );
                case String():
                  // A reader decodes the `_xHHHH_` escapes of stored text.
                  expect(decodeXstring(s), e, reason: at);
                default:
                  fail('$at: unsupported expected type ${e.runtimeType}');
              }
            }
          }
        });
      });

      test('produces the expected warnings', () {
        final Map<XlsxWarningCode, int> counts = <XlsxWarningCode, int>{};
        for (final XlsxWarning w in f.warnings()) {
          counts.update(
            w.code,
            (int n) => n + w.count,
            ifAbsent: () => w.count,
          );
        }
        expect(counts, f.expectedWarnings);
      });
    });
  }

  Fixture named(String name) =>
      fixtures.firstWhere((Fixture f) => f.name == name);

  test('m1_sheets orders the tabs and picks the active one', () {
    final Map<String, String> parts = readXlsx(named('m1_sheets').build());
    final XmlDocument book = XmlDocument.parse(parts['xl/workbook.xml']!);
    final List<String> names = <String>[
      for (final XmlElement s in book.findAllElements('sheet'))
        s.getAttribute('name')!,
    ];
    expect(names.first, 'Başlangıç');
    expect(names.last, '_x005F_x0041_'); // the sheet `_x0041_`, escaped
    expect(
      names[int.parse(
        book.findAllElements('workbookView').single.getAttribute('activeTab')!,
      )],
      'şube (2)',
    );
  });

  test('m1_properties writes the title and creator', () {
    final Map<String, String> parts = readXlsx(named('m1_properties').build());
    final XmlDocument core = XmlDocument.parse(parts['docProps/core.xml']!);
    expect(
      core.findAllElements('dc:title').single.innerText,
      'Quarterly report',
    );
    expect(core.findAllElements('dc:creator').single.innerText, 'Ahmet Urel');
  });
}
