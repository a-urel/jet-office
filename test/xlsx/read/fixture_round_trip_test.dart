// The reader against the writer: every phase 1 fixture is read back and
// compared with what its file stores (`Fixture.storedValues`), not with what
// a spreadsheet program shows (`expectedValues`, spec section 8).
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/cell_ref.dart';
import 'package:jet_office/src/xlsx/date_serial.dart';
import 'package:jet_office/src/xml/xml_escape.dart' show decodeXstring;
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';

/// Whether [text] is a number without an exponent.
bool _plain(String text) => !text.contains(RegExp('[eE]'));

/// Half a millisecond in days: the reader rounds a date or a time to the
/// nearest millisecond.
const double _halfMillisecond = 0.5 / 86400000;

/// Compares the read [value] with the [stored] text of its cell.
///
/// [isDate] is the cell's `isDate`: a number in a date or time format must
/// read as a `DateTime` or a `Duration`. The only warning a fixture may
/// have is `formulaWithoutValue`, which leaves no value, so no warning can
/// explain a date-formatted serial that fell back to a number.
void _compare(
  String where,
  Object? value,
  String stored, {
  required bool isDate,
}) {
  if (value is XlsxDecimal && isDate) {
    fail('$where: a date or time format read as the number $value.');
  }
  if (value == null) {
    expect(stored, '', reason: '$where: no value');
  } else if (value is String) {
    // A rich text's stored text is its runs joined; decoding the join
    // equals decoding run by run only when no escape spans two runs, which
    // the dedicated rich-text round trip below covers.
    expect(value, decodeXstring(stored), reason: where);
  } else if (value is bool) {
    expect(value ? '1' : '0', stored, reason: where);
  } else if (value is XlsxDecimal) {
    expect(
      double.parse(value.digits),
      double.parse(stored),
      reason: '$where: as a number',
    );
    if (_plain(stored)) {
      expect(value.digits, stored, reason: '$where: digit for digit');
    }
  } else if (value is DateTime) {
    expect(
      dateTimeSerial(value),
      closeTo(double.parse(stored), _halfMillisecond),
      reason: '$where: as a serial',
    );
  } else if (value is Duration) {
    expect(
      value.inMilliseconds / 86400000,
      closeTo(double.parse(stored), _halfMillisecond),
      reason: '$where: as days',
    );
  } else {
    fail('$where: unexpected value type ${value.runtimeType}.');
  }
}

void main() {
  test('there are fixtures to read', () => expect(allFixtures(), isNotEmpty));

  // The fixtures above compare a cell with its runs joined and then
  // decoded, which cannot tell per-run decoding from decoding the join.
  // This round trip pins the per-run rule with escapes split across runs.
  test('reads rich text back run by run, escapes and all', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('S').row(<Object?>[
      XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('_x00'),
        XlsxTextRun('41_'),
      ]),
      XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('_x0041_', font: XlsxFont(bold: true)),
        XlsxTextRun('_x'),
        XlsxTextRun('0042_'),
      ]),
      '_x0041_',
    ]);
    final XlsxReader reader = XlsxReader(writer.close().bytes);
    expect(
      reader.rowsAt(0).single.cells.map((XlsxReadCell c) => c.value),
      <Object?>['_x0041_', '_x0041__x0042_', '_x0041_'],
    );
    expect(reader.warnings, isEmpty);
  });

  for (final Fixture fixture in allFixtures()) {
    test('reads ${fixture.name} back as the writer stored it', () {
      final XlsxReader reader = XlsxReader(fixture.build());
      expect(
        reader.sheets.map((XlsxReadSheet s) => s.name).toSet(),
        fixture.storedValues.keys.toSet(),
      );
      // Per sheet, the cells holding a formula without a value, in file
      // order: the only cells that may have a warning.
      final Map<String, List<String>> formulaCells = <String, List<String>>{};
      int compared = 0;
      for (final MapEntry<String, List<List<String>>> sheet
          in fixture.storedValues.entries) {
        final List<List<String>> stored = sheet.value;
        final Map<int, XlsxReadRow> byIndex = <int, XlsxReadRow>{
          for (final XlsxReadRow row in reader.rows(sheet.key)) row.index: row,
        };
        for (final int index in byIndex.keys) {
          expect(
            index,
            lessThan(stored.length),
            reason: '${sheet.key}: row ${index + 1} is outside the fixture',
          );
        }
        for (int r = 0; r < stored.length; r++) {
          final Map<int, XlsxReadCell> cells = <int, XlsxReadCell>{
            for (final XlsxReadCell cell
                in byIndex[r]?.cells ?? const <XlsxReadCell>[])
              cell.column: cell,
          };
          for (final int column in cells.keys) {
            expect(
              column,
              lessThan(stored[r].length),
              reason: '${sheet.key}: column $column is outside the fixture',
            );
          }
          for (int c = 0; c < stored[r].length; c++) {
            final XlsxReadCell? cell = cells[c];
            final String where =
                '${fixture.name}/${sheet.key} R${r + 1}C${c + 1}';
            if (cell == null) {
              expect(stored[r][c], '', reason: '$where: missing cell');
              continue;
            }
            _compare(where, cell.value, stored[r][c], isDate: cell.isDate);
            if (cell.value != null) compared++;
            if (cell.formula != null && cell.value == null) {
              (formulaCells[sheet.key] ??= <String>[]).add(cellRef(r, c));
            }
          }
        }
      }
      expect(compared, greaterThan(0), reason: 'no value was compared');
      for (final XlsxWarning w in reader.warnings) {
        expect(
          w.code,
          XlsxWarningCode.formulaWithoutValue,
          reason: 'only formulaWithoutValue may be reported (${w.sheet})',
        );
      }
      for (final XlsxReadSheet sheet in reader.sheets) {
        final List<String> cells = formulaCells[sheet.name] ?? <String>[];
        final List<XlsxWarning> warned = <XlsxWarning>[
          for (final XlsxWarning w in reader.warnings)
            if (w.sheet == sheet.name) w,
        ];
        if (cells.isEmpty) {
          expect(warned, isEmpty, reason: sheet.name);
          continue;
        }
        expect(warned, hasLength(1), reason: sheet.name);
        expect(warned.single.cells, cells.take(10), reason: sheet.name);
        expect(warned.single.count, cells.length, reason: sheet.name);
      }
    });
  }
}
