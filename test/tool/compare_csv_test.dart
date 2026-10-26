// Tests the comparison behind tool/compare_csv.dart on synthetic CSV text.
//
// They read no files, so they run on the web as well as the VM.
import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/src/csv_compare.dart';

void main() {
  group('parseCsv', () {
    test('splits rows and fields', () {
      expect(parseCsv('a,b\nc,d\n'), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
    });

    test('accepts CRLF and a last line without a newline', () {
      expect(parseCsv('a,b\r\nc,d'), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
    });

    test('quoted fields hold commas, newlines and doubled quotes', () {
      expect(
        parseCsv('"a,b","line1\nline2","say ""hi""",plain\n'),
        <List<String>>[
          <String>['a,b', 'line1\nline2', 'say "hi"', 'plain'],
        ],
      );
    });

    test('keeps empty fields and spaces', () {
      expect(parseCsv(',  x  ,\n\n'), <List<String>>[
        <String>['', '  x  ', ''],
        <String>[''],
      ]);
    });

    test(
      'a quote inside an unquoted field is kept, as LibreOffice writes it',
      () {
        expect(parseCsv('a"b,c\n'), <List<String>>[
          <String>['a"b', 'c'],
        ]);
      },
    );

    test('empty text has no rows', () {
      expect(parseCsv(''), isEmpty);
    });

    test('an unterminated quote is a FormatException', () {
      expect(() => parseCsv('"abc\n'), throwsFormatException);
    });
  });

  group('decodeCsv', () {
    test('decodes UTF-8 and drops a byte order mark', () {
      final List<int> bytes = <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('Şube Müdürü,Straße,\u{1F600}'),
      ];
      expect(decodeCsv(bytes), 'Şube Müdürü,Straße,\u{1F600}');
    });

    test('malformed UTF-8 is a FormatException', () {
      expect(() => decodeCsv(<int>[0x61, 0xFF, 0x62]), throwsFormatException);
    });
  });

  group('xlsxWithoutExpectations', () {
    test('names each .xlsx that has no .expected.json', () {
      expect(
        xlsxWithoutExpectations(<String>[
          'a.xlsx',
          'a.expected.json',
          'b.xlsx',
          'c.expected.json',
          'notes.txt',
        ]),
        <String>['no expectations for b.xlsx'],
      );
    });

    test('is empty when every .xlsx has expectations', () {
      expect(
        xlsxWithoutExpectations(<String>['a.xlsx', 'a.expected.json']),
        isEmpty,
      );
    });
  });

  group('assembleReport', () {
    test(
      'prints unexpected files first, then each sheet, then the verdict',
      () {
        final CsvReport report = assembleReport(
          fileNames: <String>['a.xlsx', 'a.expected.json', 'b.xlsx'],
          sheets: <SheetResult>[
            (name: 'a', sheet: 'S', note: 'renamed', messages: <String>[]),
            (name: 'a', sheet: 'T', note: null, messages: <String>['r1 c1: x']),
          ],
        );
        expect(report.lines, <String>[
          'FAIL  no expectations for b.xlsx',
          'note  renamed',
          'ok    a / S',
          'FAIL  a / T',
          '      r1 c1: x',
          '2 mismatch(es).',
        ]);
        expect(report.exitCode, 1);
        expect(report.error, isNull);
      },
    );

    test('prints the unexpected files before the nothing-to-compare stop', () {
      final CsvReport report = assembleReport(
        fileNames: <String>['b.xlsx'],
        sheets: <SheetResult>[],
      );
      expect(report.lines, <String>['FAIL  no expectations for b.xlsx']);
      expect(report.error, isNotNull);
      expect(report.exitCode, 2);
    });

    test('says all sheets match, with exit code 0', () {
      final CsvReport report = assembleReport(
        fileNames: <String>['a.xlsx', 'a.expected.json'],
        sheets: <SheetResult>[
          (name: 'a', sheet: 'S', note: null, messages: <String>[]),
        ],
      );
      expect(report.lines, <String>['ok    a / S', 'All sheets match.']);
      expect(report.exitCode, 0);
    });
  });

  group('decodeXstring', () {
    test('decodes _xHHHH_ escapes left to right', () {
      expect(decodeXstring('_x0041_'), 'A');
      expect(decodeXstring('a_x00e9_b'), 'aéb');
      expect(decodeXstring('_x005F_x0041_'), '_x0041_');
      expect(decodeXstring('_x005F_x0041_x005F_x0042_'), '_x0041_x0042_');
      expect(decodeXstring('_x0041_x0042_'), 'Ax0042_');
    });
    test('leaves everything else alone', () {
      expect(decodeXstring('plain'), 'plain');
      expect(decodeXstring('_x00G1_ _x041_ x0041_'), '_x00G1_ _x041_ x0041_');
    });
  });

  group('compareSheet', () {
    test('equal values give no mismatch', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['int', 'text', 'empty'],
          <Object?>[42, 'plain text', null],
        ], 'int,text,empty\n42,plain text,\n'),
        isEmpty,
      );
    });

    test('a bool matches TRUE/FALSE and 1/0', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[true, false, true, false],
        ], 'TRUE,FALSE,1,0\n'),
        isEmpty,
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[true],
        ], 'FALSE\n'),
        <String>['A1: expected TRUE, got "FALSE"'],
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[false],
        ], 'yes\n'),
        <String>['A1: expected FALSE, got "yes"'],
      );
    });

    test('numbers are equal within a relative tolerance of 1e-12', () {
      expect(
        compareSheet(
          <List<Object?>>[
            <Object?>[46319.572916666664, 3.14159, -0.25, 9007199254740992, 0],
          ],
          // 15 significant digits, as a reader that rounds would print them.
          '46319.5729166667,3.14159,-0.25,9.00719925474099E+15,0\n',
        ),
        isEmpty,
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[1],
        ], '1.0000001\n'),
        <String>['A1: expected 1, got "1.0000001"'],
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[0],
        ], '1e-300\n'),
        <String>['A1: expected 0, got "1e-300"'],
      );
    });

    test('a number is not matched by text', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[42],
        ], 'forty-two\n'),
        <String>['A1: expected 42, got "forty-two"'],
      );
    });

    test(
      'a date-formatted number matches its date text (1899-12-30 epoch)',
      () {
        expect(
          compareSheet(
            <List<Object?>>[
              <Object?>[
                46319,
                46319.572916666664,
                59,
                61,
                46319.99999998842,
                46319.5,
              ],
            ],
            '10/24/2026,10/24/2026 13:45:00,02/27/1900,03/01/1900,'
            '2026-10-24 23:59:59,10/24/2026 12:00:00 PM\n',
          ),
          isEmpty,
        );
      },
    );

    test('a date text one day off is a mismatch', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[46319],
        ], '10/25/2026\n'),
        <String>['A1: expected 46319, got "10/25/2026"'],
      );
    });

    test('an expected number matches its percent text (R9)', () {
      // The failing CI cases: 1234.5 and the date 46319 in `0%`.
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[1234.5, 46319, 1234.5, 0.125],
        ], '123450%,4631900%,123450.0%,12.5%\n'),
        isEmpty,
      );
    });

    test('percent text of another number is a mismatch', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[1234.5, 1234.5, 46319],
        ], '123451%,1234.5%,4631900\n'),
        <String>[
          'A1: expected 1234.5, got "123451%"',
          'B1: expected 1234.5, got "1234.5%"',
          'C1: expected 46319, got "4631900"',
        ],
      );
    });

    test('an expected number matches [h]:mm:ss text within a second (R9)', () {
      // The failing CI case: 1234.5 days are 29628 hours.
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[1234.5, 46319, 0.5, 1234.5, 46319.99999998842],
        ], '29628:00:00,1111656:00:00,12:00:00,29628:00:01,1111679:59:59\n'),
        isEmpty,
      );
    });

    test('elapsed time more than a second off is a mismatch', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[1234.5, 1234.5, 1234.5],
        ], '29628:00:02,29627:00:00,29628:60:00\n'),
        <String>[
          'A1: expected 1234.5, got "29628:00:02"',
          'B1: expected 1234.5, got "29627:00:00"',
          'C1: expected 1234.5, got "29628:60:00"',
        ],
      );
    });

    test('strings are equal exactly', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['  padded  ', 'Şube Müdürü', 'a,b', 'say "hi"', 'x\ny'],
        ], '  padded  ,Şube Müdürü,"a,b","say ""hi""","x\ny"\n'),
        isEmpty,
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['Straße'],
        ], 'Strasse\n'),
        <String>['A1: expected "Straße", got "Strasse"'],
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['42'],
        ], '42.0\n'),
        <String>['A1: expected "42", got "42.0"'],
      );
    });

    test('null matches only an empty field', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['a', null, 'b'],
        ], 'a,,b\n'),
        isEmpty,
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['a', null, 'b'],
        ], 'a,x,b\n'),
        <String>['B1: expected empty, got "x"'],
      );
    });

    test('trailing empty rows and cells are ignored on both sides', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['a', null],
          <Object?>[null, null],
          <Object?>[null, 'b'],
          <Object?>[null, null],
          <Object?>[''],
        ], 'a,,,\n,,,\n,b,,\n,,,\n\n'),
        isEmpty,
      );
      expect(compareSheet(<List<Object?>>[], ''), isEmpty);
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[''],
        ], ''),
        isEmpty,
      );
      expect(compareSheet(<List<Object?>>[], ',,\n,\n'), isEmpty);
    });

    test('missing and extra cells are reported where they are', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['a', 'b'],
        ], 'a\n'),
        <String>['B1: expected "b", got empty'],
      );
      expect(
        compareSheet(<List<Object?>>[
          <Object?>['a'],
        ], 'a\n,,extra\n'),
        <String>['C2: expected empty, got "extra"'],
      );
    });

    test('every mismatch is reported with its cell reference', () {
      expect(
        compareSheet(<List<Object?>>[
          <Object?>[1, 2],
          <Object?>[3, 'four'],
        ], '1,2\n3,five\n'),
        <String>['B2: expected "four", got "five"'],
      );
      final List<Object?> wide = <Object?>[
        ...List<Object?>.filled(27, null),
        'x',
      ];
      expect(compareSheet(<List<Object?>>[wide], '${',' * 27}y\n'), <String>[
        'AB1: expected "x", got "y"',
      ]);
    });

    test('long text is shortened in a message', () {
      final String long = 'a' * 32767;
      final List<String> messages = compareSheet(<List<Object?>>[
        <Object?>[long],
      ], '${long}b\n');
      expect(messages, hasLength(1));
      expect(messages.single, startsWith('A1: expected "aaaa'));
      expect(messages.single, contains('(32767 characters)'));
      expect(messages.single, contains('(32768 characters)'));
      expect(messages.single.length, lessThan(300));
    });

    test('an expected value of another type is an ArgumentError', () {
      expect(
        () => compareSheet(<List<Object?>>[
          <Object?>[DateTime(2026)],
        ], 'x\n'),
        throwsArgumentError,
      );
    });
  });
}
