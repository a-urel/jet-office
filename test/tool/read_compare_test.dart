// Tests the comparison behind tool/compare_resaved.dart on rows built by
// hand and by XlsxReader.
//
// They read no files, so they run on the web as well as the VM.
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/read_compare.dart';

/// A read row at the 0-based [index] holding [values] from column A.
XlsxReadRow _row(int index, List<Object?> values) =>
    XlsxReadRow(index, <XlsxReadCell>[
      for (int c = 0; c < values.length; c++) XlsxReadCell(c, values[c]),
    ]);

List<String> _compare(
  List<List<Object?>> expected,
  List<XlsxReadRow> read, {
  bool date1904 = false,
}) => compareReadSheet(expected, read, date1904: date1904);

void main() {
  group('compareReadSheet', () {
    test('equal values give no mismatch', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['a', 1, true],
            <Object?>[null, 2.5, false],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>['a', XlsxDecimal('1'), true]),
            _row(1, <Object?>[null, XlsxDecimal('2.5'), false]),
          ],
        ),
        isEmpty,
      );
    });

    test('a decimal matches within a relative 1e-12', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[1234.50],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[XlsxDecimal('1234.5')]),
          ],
        ),
        isEmpty,
      );
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[1234.6],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[XlsxDecimal('1234.5')]),
          ],
        ),
        <String>['A1: expected 1234.6, got 1234.5'],
      );
    });

    test('a DateTime matches its 1900 serial within one second', () {
      final DateTime date = DateTime.utc(2026, 10, 24, 13, 45);
      // 2026-10-24 13:45 is serial 46319.5729166...
      const double serial = 46319 + (13 * 60 + 45) / 1440;
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[serial],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[date]),
          ],
        ),
        isEmpty,
      );
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[serial],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[date.add(const Duration(seconds: 1))]),
          ],
        ),
        isEmpty,
      );
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[serial],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[date.add(const Duration(seconds: 2))]),
          ],
        ),
        hasLength(1),
      );
    });

    test('with date1904 a DateTime matches the 1904 serial', () {
      final DateTime date = DateTime.utc(2026, 10, 24);
      const double serial1900 = 46319;
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[serial1900 - 1462],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[date]),
          ],
          date1904: true,
        ),
        isEmpty,
      );
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[serial1900],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[date]),
          ],
          date1904: true,
        ),
        hasLength(1),
      );
    });

    test('a Duration matches expected days within one second', () {
      const Duration thirteenThirty = Duration(hours: 13, minutes: 30);
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[0.5625],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[thirteenThirty]),
          ],
        ),
        isEmpty,
      );
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[0.5625],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[thirteenThirty + const Duration(seconds: 2)]),
          ],
        ),
        hasLength(1),
      );
    });

    test('true matches true only', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[true],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[true]),
          ],
        ),
        isEmpty,
      );
      for (final Object? other in <Object?>[false, XlsxDecimal('1'), 'TRUE']) {
        expect(
          _compare(
            <List<Object?>>[
              <Object?>[true],
            ],
            <XlsxReadRow>[
              _row(0, <Object?>[other]),
            ],
          ),
          hasLength(1),
          reason: '$other',
        );
      }
    });

    test('a string matches exactly', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['Ünï'],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>['Ünï']),
          ],
        ),
        isEmpty,
      );
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['abc'],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>['abc ']),
          ],
        ),
        <String>['A1: expected "abc", got "abc "'],
      );
    });

    test(
      'a formula string matches its _xHHHH_-decoded form, a plain one does not',
      () {
        // LibreOffice writes a formula's string result in t="str" without
        // escaping it, so the reader's decoding changes a result that looks
        // like an escape. The rule covers formula cells only.
        final List<List<Object?>> expected = <List<Object?>>[
          <Object?>['_x005F_x0041_'],
        ];
        expect(
          _compare(expected, <XlsxReadRow>[
            XlsxReadRow(0, const <XlsxReadCell>[
              XlsxReadCell(0, '_x0041_', formula: '"_x005F_x0041_"'),
            ]),
          ]),
          isEmpty,
        );
        expect(
          _compare(expected, <XlsxReadRow>[
            _row(0, <Object?>['_x0041_']),
          ]),
          <String>['A1: expected "_x005F_x0041_", got "_x0041_"'],
        );
      },
    );

    test('an error value matches its code as a string', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['#DIV/0!'],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[XlsxErrorValue.div0]),
          ],
        ),
        isEmpty,
      );
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['#DIV/0!'],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>[XlsxErrorValue.na]),
          ],
        ),
        hasLength(1),
      );
    });

    test('null matches a missing cell and an empty text matches null', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['x', null, 'y'],
            <Object?>[''],
          ],
          <XlsxReadRow>[
            XlsxReadRow(0, const <XlsxReadCell>[
              XlsxReadCell(0, 'x'),
              XlsxReadCell(2, 'y'),
            ]),
            _row(1, <Object?>[null]),
          ],
        ),
        isEmpty,
      );
    });

    test('a missing cell that was expected is a mismatch', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['x', 5],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>['x']),
          ],
        ),
        <String>['B1: expected 5, got nothing'],
      );
    });

    test('trailing empty rows and cells are ignored on both sides', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['x', null, ''],
            <Object?>[],
            <Object?>[null],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>['x', null]),
            _row(4, <Object?>[null, null]),
          ],
        ),
        isEmpty,
      );
    });

    test('rows are matched by their index, not their position', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>[],
            <Object?>['b'],
          ],
          <XlsxReadRow>[
            _row(1, <Object?>['b']),
          ],
        ),
        isEmpty,
      );
    });

    test('an extra read cell is a mismatch naming its reference', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['x'],
            <Object?>[],
            <Object?>[],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>['x']),
            XlsxReadRow(3, <XlsxReadCell>[
              const XlsxReadCell(2, null),
              XlsxReadCell(3, XlsxDecimal('5')),
            ]),
          ],
        ),
        <String>['D4: expected nothing, got 5'],
      );
    });

    test('an empty expected sheet matches a sheet with no rows', () {
      expect(_compare(<List<Object?>>[], <XlsxReadRow>[]), isEmpty);
      expect(
        _compare(<List<Object?>>[], <XlsxReadRow>[
          _row(0, <Object?>[XlsxDecimal('1')]),
        ]),
        <String>['A1: expected nothing, got 1'],
      );
    });

    test('a wrong number names the cell, the want and the got', () {
      expect(
        _compare(
          <List<Object?>>[
            <Object?>['h'],
            <Object?>[42],
          ],
          <XlsxReadRow>[
            _row(0, <Object?>['h']),
            _row(1, <Object?>[XlsxDecimal('41')]),
          ],
        ),
        <String>['A2: expected 42, got 41'],
      );
    });

    test('an expected cell of another type is an ArgumentError', () {
      expect(
        () => _compare(<List<Object?>>[
          <Object?>[DateTime.utc(2026)],
        ], <XlsxReadRow>[]),
        throwsArgumentError,
      );
    });

    test('reads rows from XlsxReader on writer-made bytes', () {
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('S').row(<Object?>[
        'text',
        12.5,
        true,
        DateTime.utc(2026, 10, 24, 13, 45),
      ]);
      final XlsxReader reader = XlsxReader(writer.close().bytes);
      expect(
        compareReadSheet(
          <List<Object?>>[
            <Object?>['text', 12.5, true, 46319 + (13 * 60 + 45) / 1440],
          ],
          reader.rowsAt(0),
          date1904: reader.date1904,
        ),
        isEmpty,
      );
    });
  });

  group('resaveAllowedWarnings', () {
    test('every line has a reason', () {
      resaveAllowedWarnings.forEach((
        String fixture,
        Map<XlsxWarningCode, String> codes,
      ) {
        expect(codes, isNotEmpty, reason: fixture);
        for (final String reason in codes.values) {
          expect(reason.trim(), isNotEmpty, reason: fixture);
        }
      });
    });
  });

  group('decodeXstring', () {
    test('is shared with the CSV comparison', () {
      expect(decodeXstring('a_x0041_b'), 'aAb');
    });
  });
}
