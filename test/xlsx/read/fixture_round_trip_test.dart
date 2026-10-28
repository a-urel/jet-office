// The reader against the writer: every phase 1 fixture is read back and
// compared with what its file stores (`Fixture.storedValues`), not with what
// a spreadsheet program shows (`expectedValues`, spec section 8).
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xml/xml_escape.dart' show decodeXstring;
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';

/// Whether [text] is a number without an exponent.
bool _plain(String text) => !text.contains(RegExp('[eE]'));

void _compare(String where, Object? value, String stored) {
  if (value == null) {
    expect(stored, '', reason: '$where: no value');
  } else if (value is String) {
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
  } else {
    fail('$where: unexpected value type ${value.runtimeType}.');
  }
}

void main() {
  for (final Fixture fixture in allFixtures()) {
    test('reads ${fixture.name} back as the writer stored it', () {
      final XlsxReader reader = XlsxReader(fixture.build());
      expect(
        reader.sheets.map((XlsxReadSheet s) => s.name).toSet(),
        fixture.storedValues.keys.toSet(),
      );
      int formulaCells = 0;
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
            _compare(where, cell.value, stored[r][c]);
            if (cell.formula != null && cell.value == null) formulaCells++;
          }
        }
      }
      final Set<XlsxWarningCode> codes = reader.warnings
          .map((XlsxWarning w) => w.code)
          .toSet();
      expect(
        codes.difference(<XlsxWarningCode>{
          XlsxWarningCode.formulaWithoutValue,
        }),
        isEmpty,
        reason: 'only formulaWithoutValue may be reported',
      );
      final int warned = reader.warnings.fold<int>(
        0,
        (int sum, XlsxWarning w) => sum + w.count,
      );
      expect(
        warned,
        formulaCells,
        reason:
            'one warning per formula without '
            'a value, and no other cell has one',
      );
    });
  }
}
