// Tests the case list parser and the workbook builder behind
// tool/write_format_oracle.dart on synthetic case lists.
//
// They read no files, so they run on the web as well as the VM.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/format_oracle.dart';

Map<String, Object?> _case(
  String id, [
  Map<String, Object?> fields = const {},
]) => <String, Object?>{
  'id': id,
  'checks': <String>['C4a'],
  'unknown': 4,
  'workbook': 'main',
  'dateSystem': '1900',
  'value': <String, Object?>{'n': '46083'},
  'code': 'mmm',
  'eyeOnly': false,
  'note': 'month name',
  ...fields,
};

String _doc(
  List<Map<String, Object?>> cases, {
  Map<String, Object?>? workbooks,
}) => jsonEncode(<String, Object?>{
  'version': 1,
  'workbooks':
      workbooks ??
      <String, Object?>{
        'main': <String, Object?>{
          'file': 'format_oracle.xlsx',
          'dateSystem': '1900',
          'numFmts': <String, Object?>{},
        },
        'date1904': <String, Object?>{
          'file': 'format_oracle_1904.xlsx',
          'dateSystem': '1904',
          'numFmts': <String, Object?>{'14': 'yyyy-mm-dd'},
        },
      },
  'cases': cases,
});

Matcher _throwsAt(String path) => throwsA(
  isA<FormatException>().having(
    (FormatException e) => e.message,
    'message',
    startsWith('$path:'),
  ),
);

/// The values of columns A to D of each row of [sheet].
List<List<Object?>> _rows(XlsxReader reader, String sheet) => <List<Object?>>[
  for (final XlsxReadRow row in reader.rows(sheet))
    <Object?>[
      for (int column = 0; column < 4; column++)
        row.cells
            .where((XlsxReadCell c) => c.column == column)
            .firstOrNull
            ?.value,
    ],
];

XlsxReadCell _cellA(XlsxReader reader, String sheet, int rowIndex) => reader
    .rows(sheet)
    .singleWhere((XlsxReadRow r) => r.index == rowIndex)
    .cells
    .singleWhere((XlsxReadCell c) => c.column == 0);

void main() {
  group('parseOracleCases', () {
    test('reads the workbooks and every field of a case', () {
      final OracleCases parsed = parseOracleCases(
        _doc(<Map<String, Object?>>[
          _case('c4-01'),
          _case('c20-01', <String, Object?>{
            'checks': <String>['C20'],
            'unknown': 20,
            'workbook': 'date1904',
            'dateSystem': '1904',
            'code': null,
            'builtinId': 14,
          }),
          _case('u14-01', <String, Object?>{
            'checks': <String>[],
            'unknown': 14,
            'value': <String, Object?>{'n': '0.000012345678'},
            'code': 'General',
            'eyeOnly': true,
          }),
        ]),
      );
      expect(parsed.workbooks.keys, <String>['main', 'date1904']);
      final OracleWorkbook w1904 = parsed.workbooks['date1904']!;
      expect(w1904.file, 'format_oracle_1904.xlsx');
      expect(w1904.date1904, isTrue);
      expect(w1904.numFmts, <int, String>{14: 'yyyy-mm-dd'});
      expect(parsed.workbooks['main']!.date1904, isFalse);

      final OracleCase first = parsed.cases[0];
      expect(first.id, 'c4-01');
      expect(first.checks, <String>['C4a']);
      expect(first.unknown, 4);
      expect(first.workbook, 'main');
      expect(first.date1904, isFalse);
      expect(first.value, isA<OracleNumber>());
      expect((first.value as OracleNumber).digits, '46083');
      expect(first.code, 'mmm');
      expect(first.builtinId, isNull);
      expect(first.eyeOnly, isFalse);
      expect(first.note, 'month name');

      expect(parsed.cases[1].builtinId, 14);
      expect(parsed.cases[1].code, isNull);
      expect(parsed.cases[1].date1904, isTrue);
      expect(parsed.cases[2].checks, isEmpty);
      expect(parsed.cases[2].eyeOnly, isTrue);
    });

    test('reads booleans, text and manual values', () {
      final OracleCases parsed = parseOracleCases(
        _doc(<Map<String, Object?>>[
          _case('a-01', <String, Object?>{
            'value': <String, Object?>{'b': true},
          }),
          _case('a-02', <String, Object?>{
            'value': <String, Object?>{'s': 'abc'},
          }),
          _case('a-03', <String, Object?>{
            'value': <String, Object?>{
              'manual': '=SEQUENCE(1,2)',
              'error': '#SPILL!',
            },
            'eyeOnly': true,
          }),
        ]),
      );
      expect((parsed.cases[0].value as OracleBool).value, isTrue);
      expect((parsed.cases[1].value as OracleText).text, 'abc');
      final OracleManual manual = parsed.cases[2].value as OracleManual;
      expect(manual.formula, '=SEQUENCE(1,2)');
      expect(manual.error, '#SPILL!');
    });

    test('a case without checks or unknown is allowed (an own rule)', () {
      final OracleCases parsed = parseOracleCases(
        _doc(<Map<String, Object?>>[
          _case('own-01', <String, Object?>{
            'checks': <String>[],
            'unknown': null,
          }),
        ]),
      );
      expect(parsed.cases.single.unknown, isNull);
    });

    test('rejects a version other than 1', () {
      final Map<String, Object?> doc =
          jsonDecode(_doc(<Map<String, Object?>>[])) as Map<String, Object?>;
      doc['version'] = 2;
      expect(() => parseOracleCases(jsonEncode(doc)), _throwsAt('version'));
    });

    test('rejects text that is not JSON', () {
      expect(() => parseOracleCases('{'), _throwsAt(r'$'));
    });

    test('rejects an unknown key, naming its path', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'extra': 1}),
          ]),
        ),
        _throwsAt('cases[0].extra'),
      );
    });

    test('rejects a duplicate id', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[_case('a-01'), _case('a-01')]),
        ),
        _throwsAt('cases[1].id'),
      );
    });

    test('rejects an id outside lower-case letters, digits and -', () {
      expect(
        () => parseOracleCases(_doc(<Map<String, Object?>>[_case('A 1')])),
        _throwsAt('cases[0].id'),
      );
    });

    test('rejects a check that is not C<n> with an optional letter', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{
              'checks': <String>['X4'],
            }),
          ]),
        ),
        _throwsAt('cases[0].checks[0]'),
      );
    });

    test('rejects an unknown outside 1 to 21', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'unknown': 22}),
          ]),
        ),
        _throwsAt('cases[0].unknown'),
      );
    });

    test('rejects a workbook the list does not define', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'workbook': 'other'}),
          ]),
        ),
        _throwsAt('cases[0].workbook'),
      );
    });

    test("rejects a date system other than the workbook's", () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'dateSystem': '1904'}),
          ]),
        ),
        _throwsAt('cases[0].dateSystem'),
      );
    });

    test('rejects a case with both code and builtinId, or neither', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'builtinId': 14}),
          ]),
        ),
        _throwsAt('cases[0]'),
      );
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'code': null}),
          ]),
        ),
        _throwsAt('cases[0]'),
      );
    });

    test('rejects a builtinId outside 0 to 163 and an empty code', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'code': null, 'builtinId': 164}),
          ]),
        ),
        _throwsAt('cases[0].builtinId'),
      );
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{'code': ''}),
          ]),
        ),
        _throwsAt('cases[0].code'),
      );
    });

    test('rejects a value that is not exactly one of n, b, s, manual', () {
      for (final Object? value in <Object?>[
        <String, Object?>{'n': 5},
        <String, Object?>{'n': '1,5'},
        <String, Object?>{'b': 'true'},
        <String, Object?>{'n': '1', 's': 'a'},
        <String, Object?>{'n': '1', 'error': '#N/A'},
        <String, Object?>{'manual': '=NA()'},
        <String, Object?>{'manual': '=NA()', 'error': 'N/A'},
        <String, Object?>{},
        'x',
      ]) {
        expect(
          () => parseOracleCases(
            _doc(<Map<String, Object?>>[
              _case('a-01', <String, Object?>{'value': value}),
            ]),
          ),
          _throwsAt('cases[0].value'),
          reason: '$value',
        );
      }
    });

    test('rejects a manual value on a case that is not eye only', () {
      expect(
        () => parseOracleCases(
          _doc(<Map<String, Object?>>[
            _case('a-01', <String, Object?>{
              'value': <String, Object?>{'manual': '=NA()', 'error': '#N/A'},
            }),
          ]),
        ),
        _throwsAt('cases[0].eyeOnly'),
      );
    });

    test('rejects a workbook file that is not .xlsx and a bad numFmts id', () {
      expect(
        () => parseOracleCases(
          _doc(
            <Map<String, Object?>>[],
            workbooks: <String, Object?>{
              'main': <String, Object?>{
                'file': 'oracle.csv',
                'dateSystem': '1900',
                'numFmts': <String, Object?>{},
              },
            },
          ),
        ),
        _throwsAt('workbooks.main.file'),
      );
      expect(
        () => parseOracleCases(
          _doc(
            <Map<String, Object?>>[],
            workbooks: <String, Object?>{
              'main': <String, Object?>{
                'file': 'oracle.xlsx',
                'dateSystem': '1900',
                'numFmts': <String, Object?>{'200': '0.0'},
              },
            },
          ),
        ),
        _throwsAt('workbooks.main.numFmts.200'),
      );
    });
  });

  group('buildOracleWorkbooks', () {
    final OracleCases cases = parseOracleCases(
      _doc(<Map<String, Object?>>[
        _case('c4-01'),
        _case('c6-01', <String, Object?>{
          'checks': <String>['C6'],
          'unknown': 6,
          'code': null,
          'builtinId': 14,
        }),
        _case('c16-01', <String, Object?>{
          'checks': <String>['C16'],
          'unknown': 16,
          'value': <String, Object?>{'b': true},
          'code': '0.00',
        }),
        _case('u19-01', <String, Object?>{
          'checks': <String>[],
          'unknown': 19,
          'value': <String, Object?>{'s': 'abc'},
          'code': '0;@',
        }),
        _case('u14-01', <String, Object?>{
          'checks': <String>[],
          'unknown': 14,
          'value': <String, Object?>{'n': '0.000012345678'},
          'code': 'General',
          'eyeOnly': true,
          'note': 'default width',
        }),
        _case('c17-01', <String, Object?>{
          'checks': <String>['C17'],
          'unknown': 17,
          'value': <String, Object?>{
            'manual': '=SEQUENCE(1,2)',
            'error': '#SPILL!',
          },
          'code': 'General',
          'eyeOnly': true,
          'note': 'spill',
        }),
        _case('c20-01', <String, Object?>{
          'checks': <String>['C20'],
          'unknown': 20,
          'workbook': 'date1904',
          'dateSystem': '1904',
          'code': null,
          'builtinId': 14,
        }),
      ]),
    );
    final Map<String, Uint8List> files = buildOracleWorkbooks(cases);

    test('writes one file per workbook that has cases', () {
      expect(files.keys, <String>[
        'format_oracle.xlsx',
        'format_oracle_1904.xlsx',
      ]);
    });

    test('the cases sheet holds value, code, id and note per row', () {
      final XlsxReader reader = XlsxReader(files['format_oracle.xlsx']!);
      expect(reader.sheets.map((XlsxReadSheet s) => s.name), <String>[
        'cases',
        'eye',
      ]);
      expect(reader.date1904, isFalse);
      final List<List<Object?>> rows = _rows(reader, 'cases');
      expect(rows[0], <Object?>['value', 'code', 'case', 'note']);
      expect(rows[1].sublist(1), <Object?>['mmm', 'c4-01', 'month name']);
      expect(rows[2].sublist(1), <Object?>[
        'builtin 14',
        'c6-01',
        'month name',
      ]);
      expect(rows[3], <Object?>[true, '0.00', 'c16-01', 'month name']);
      expect(rows[4], <Object?>['abc', '0;@', 'u19-01', 'month name']);
      expect(rows, hasLength(5));

      final XlsxReadCell date = _cellA(reader, 'cases', 1);
      expect(date.numberFormat, 'mmm');
      expect(date.isDate, isTrue);
      expect(_cellA(reader, 'cases', 2).numberFormatId, 14);
      expect(_cellA(reader, 'cases', 3).numberFormat, '0.00');
      expect(_cellA(reader, 'cases', 4).numberFormat, '0;@');
    });

    test('a number is written digit for digit', () {
      final OracleCases one = parseOracleCases(
        _doc(<Map<String, Object?>>[
          _case('a-01', <String, Object?>{
            'value': <String, Object?>{'n': '0.437268518518519'},
            'code': '0.000000000000000',
          }),
        ]),
      );
      final XlsxReader reader = XlsxReader(
        buildOracleWorkbooks(one)['format_oracle.xlsx']!,
      );
      expect(
        (_cellA(reader, 'cases', 1).value! as XlsxDecimal).digits,
        '0.437268518518519',
      );
    });

    test('the eye sheet holds the eye-only cases; a manual case has no '
        'value and says what to type', () {
      final XlsxReader reader = XlsxReader(files['format_oracle.xlsx']!);
      final List<List<Object?>> rows = _rows(reader, 'eye');
      expect(rows[0], <Object?>['value', 'code', 'case', 'note']);
      expect(rows[1].sublist(1), <Object?>[
        'General',
        'u14-01',
        'default width',
      ]);
      expect(
        (_cellA(reader, 'eye', 1).value! as XlsxDecimal).digits,
        '0.000012345678',
      );
      expect(rows[2], <Object?>[
        null,
        'General',
        'c17-01',
        'type =SEQUENCE(1,2) in A3; spill',
      ]);
    });

    test('a 1904 workbook says so and carries its own built-in codes', () {
      final XlsxReader reader = XlsxReader(files['format_oracle_1904.xlsx']!);
      expect(reader.date1904, isTrue);
      expect(reader.sheets.map((XlsxReadSheet s) => s.name), <String>['cases']);
      final XlsxReadCell cell = _cellA(reader, 'cases', 1);
      expect(cell.numberFormatId, 14);
      expect(cell.numberFormat, 'yyyy-mm-dd');
      expect(reader.warnings, isEmpty);
    });

    test('a workbook that has no cases is not written', () {
      final OracleCases only1904 = parseOracleCases(
        _doc(<Map<String, Object?>>[
          _case('a-01', <String, Object?>{
            'workbook': 'date1904',
            'dateSystem': '1904',
          }),
        ]),
      );
      expect(buildOracleWorkbooks(only1904).keys, <String>[
        'format_oracle_1904.xlsx',
      ]);
    });
  });
}
