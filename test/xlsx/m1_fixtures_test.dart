import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../fixtures/m1_fixtures.dart';
import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

/// The warning counts per code each fixture must produce, by fixture name.
const Map<String, Map<XlsxWarningCode, int>> _expectedWarnings =
    <String, Map<XlsxWarningCode, int>>{
      'm1_values': <XlsxWarningCode, int>{},
      'm1_dirty_text': <XlsxWarningCode, int>{
        XlsxWarningCode.invalidCharactersRemoved: 3,
        XlsxWarningCode.textTruncated: 2,
      },
      'm1_sheets': <XlsxWarningCode, int>{
        XlsxWarningCode.sheetNameChanged: 3,
        XlsxWarningCode.sheetNameDuplicated: 5,
      },
      'm1_formulas': <XlsxWarningCode, int>{},
      'm1_empty': <XlsxWarningCode, int>{},
      'm1_properties': <XlsxWarningCode, int>{},
      'm1_dates': <XlsxWarningCode, int>{
        XlsxWarningCode.dateOutsideExcelRange: 1,
        XlsxWarningCode.dateInNonDateFormat: 1,
      },
    };

/// The cell values of every sheet in [bytes], as stored, in a rectangle per
/// sheet (empty cells are `''`), keyed by sheet name.
Map<String, List<List<String>>> _storedValues(Uint8List bytes) {
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
  final Map<String, List<List<String>>> result = <String, List<List<String>>>{};
  for (final XmlElement sheet in XmlDocument.parse(
    parts['xl/workbook.xml']!,
  ).findAllElements('sheet')) {
    final XmlDocument doc = XmlDocument.parse(
      parts[targets[sheet.getAttribute('r:id')!]]!,
    );
    final Map<(int, int), String> cells = <(int, int), String>{};
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
        if (r > rows) rows = r;
        if (column > columns) columns = column;
      }
    }
    result[sheet.getAttribute('name')!] = <List<String>>[
      for (int r = 1; r <= rows; r++)
        <String>[for (int c = 1; c <= columns; c++) cells[(r, c)] ?? ''],
    ];
  }
  return result;
}

void main() {
  test('the seven M1 fixtures exist, under unique names', () {
    final List<String> names = <String>[
      for (final Fixture f in m1Fixtures()) f.name,
    ];
    expect(names, _expectedWarnings.keys.toList());
  });

  for (final Fixture f in m1Fixtures()) {
    group(f.name, () {
      test('passes the consistency checker', () {
        expect(checkXlsx(f.build()), isEmpty);
      });

      test('is deterministic', () {
        expect(f.build(), f.build());
      });

      test('storedValues describe what the file stores', () {
        expect(_storedValues(f.build()), f.storedValues);
      });

      test('expectedValues agree with storedValues', () {
        // Formula cells hold the computed value, which the file may not
        // store, so a sheet of formulas is exempt.
        final Set<String> formulaSheets = <String>{
          if (f.name == 'm1_formulas') 'Formulas',
        };
        expect(
          f.expectedValues.keys.toSet(),
          f.storedValues.keys.toSet(),
          reason: 'same sheets',
        );
        f.expectedValues.forEach((String sheet, List<List<Object?>> rows) {
          if (formulaSheets.contains(sheet)) return;
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
                  expect(s, e, reason: at);
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
        expect(counts, _expectedWarnings[f.name]);
      });
    });
  }

  test('m1_sheets orders the tabs and picks the active one', () {
    final Fixture f = m1Fixtures().firstWhere(
      (Fixture f) => f.name == 'm1_sheets',
    );
    final Map<String, String> parts = readXlsx(f.build());
    final XmlDocument book = XmlDocument.parse(parts['xl/workbook.xml']!);
    final List<String> names = <String>[
      for (final XmlElement s in book.findAllElements('sheet'))
        s.getAttribute('name')!,
    ];
    expect(names.first, 'Başlangıç');
    expect(
      names[int.parse(
        book.findAllElements('workbookView').single.getAttribute('activeTab')!,
      )],
      'şube (2)',
    );
  });
}
