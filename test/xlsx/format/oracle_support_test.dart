import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/oracle.dart';

void main() {
  group('parseCsv', () {
    test('reads plain fields separated by the separator', () {
      expect(parseCsv('a,b,c\nd,e,f\n', separator: ','), <List<String>>[
        <String>['a', 'b', 'c'],
        <String>['d', 'e', 'f'],
      ]);
    });

    test('unquotes quoted fields and reads "" as one quote', () {
      expect(parseCsv('"a","say ""hi""",c', separator: ','), <List<String>>[
        <String>['a', 'say "hi"', 'c'],
      ]);
    });

    test('keeps a separator inside quotes', () {
      expect(parseCsv('"#,##0;(#,##0)";1,5\n', separator: ';'), <List<String>>[
        <String>['#,##0;(#,##0)', '1,5'],
      ]);
    });

    test('keeps a line break inside quotes', () {
      expect(parseCsv('"a\r\nb",c', separator: ','), <List<String>>[
        <String>['a\r\nb', 'c'],
      ]);
    });

    test('ends rows at CRLF and at LF alike', () {
      expect(parseCsv('a;b\r\nc;d\ne;f', separator: ';'), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
        <String>['e', 'f'],
      ]);
    });

    test('keeps an empty trailing field', () {
      expect(parseCsv('a,\r\nb,""\r\n', separator: ','), <List<String>>[
        <String>['a', ''],
        <String>['b', ''],
      ]);
    });

    test('a trailing newline adds no empty last row', () {
      expect(parseCsv('a\r\n', separator: ','), <List<String>>[
        <String>['a'],
      ]);
      expect(parseCsv('a\n', separator: ','), <List<String>>[
        <String>['a'],
      ]);
    });

    test('keeps a blank line inside the text as one empty field', () {
      expect(parseCsv('a\n\nb\n', separator: ','), <List<String>>[
        <String>['a'],
        <String>[''],
        <String>['b'],
      ]);
    });

    test('drops a leading UTF-8 BOM', () {
      expect(parseCsv('﻿a;b\r\n', separator: ';'), <List<String>>[
        <String>['a', 'b'],
      ]);
    });

    test('keeps spaces exactly, trailing ones included', () {
      expect(parseCsv(' 1,234 ; "5 "\n', separator: ';'), <List<String>>[
        <String>[' 1,234 ', ' "5 "'],
      ]);
    });

    test('empty text has no rows', () {
      expect(parseCsv('', separator: ','), isEmpty);
      expect(parseCsv('﻿', separator: ','), isEmpty);
    });

    test('throws FormatException on an unterminated quote', () {
      expect(
        () => parseCsv('a,"b\n', separator: ','),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws ArgumentError on a separator that is not one character', () {
      expect(() => parseCsv('a', separator: ''), throwsArgumentError);
      expect(() => parseCsv('a', separator: ';;'), throwsArgumentError);
      expect(() => parseCsv('a', separator: '"'), throwsArgumentError);
    });
  });

  group('sniffSeparator', () {
    test('picks ; for a BOM and ; file (Excel for Mac, de-DE)', () {
      expect(sniffSeparator('﻿1.234,50;x;y\r\n2;3;4\r\n'), ';');
    });

    test('picks , when the commas are inside quotes on a , file', () {
      expect(sniffSeparator('"#,##0;(#,##0)",1\n"0;0;0",2\n'), ',');
    });

    test('looks at the first line only', () {
      expect(sniffSeparator('a,b\nc;d;e;f\n'), ',');
    });

    test('picks , on a tie and on empty text', () {
      expect(sniffSeparator('a;b,c'), ',');
      expect(sniffSeparator(''), ',');
    });
  });

  group('compareOracle', () {
    final OracleCase thousands = OracleCase(
      id: 'thousands',
      row: 0,
      code: '#,##0.00',
      value: XlsxDecimal('1234.5'),
    );

    test('a row with the same text matches', () {
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[thousands],
        <List<String>>[
          <String>['1,234.50'],
        ],
        XlsxFormatLocale.enUS,
      );
      expect(outcomes, hasLength(1));
      final OracleOutcome outcome = outcomes.single;
      expect(outcome, isA<OracleMatch>());
      expect(outcome.kase, same(thousands));
      expect((outcome as OracleMatch).text, '1,234.50');
    });

    test('uses the locale it is given', () {
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[thousands],
        <List<String>>[
          <String>['1.234,50'],
        ],
        XlsxFormatLocale.deDE,
      );
      expect(outcomes.single, isA<OracleMatch>());
    });

    test('a different text is a mismatch with both texts', () {
      final OracleOutcome outcome = compareOracle(
        <OracleCase>[thousands],
        <List<String>>[
          <String>['1,234.5'],
        ],
        XlsxFormatLocale.enUS,
      ).single;
      expect(outcome, isA<OracleMismatch>());
      final OracleMismatch mismatch = outcome as OracleMismatch;
      expect(mismatch.kase, same(thousands));
      expect(mismatch.expected, '1,234.5');
      expect(mismatch.actual, '1,234.50');
    });

    test('a trailing space difference is a mismatch, either side', () {
      final OracleCase padded = OracleCase(
        id: 'padded',
        row: 0,
        code: '#,##0_);(#,##0)',
        value: XlsxDecimal('5'),
      );
      final OracleCase plain = OracleCase(
        id: 'plain',
        row: 1,
        code: '0',
        value: XlsxDecimal('5'),
      );
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[padded, plain],
        <List<String>>[
          <String>['5'],
          <String>['5 '],
        ],
        XlsxFormatLocale.enUS,
      );
      expect(outcomes[0], isA<OracleMismatch>());
      expect((outcomes[0] as OracleMismatch).actual, '5 ');
      expect(outcomes[1], isA<OracleMismatch>());
      expect((outcomes[1] as OracleMismatch).expected, '5 ');
    });

    test('reads the column it is given', () {
      final OracleOutcome outcome = compareOracle(
        <OracleCase>[thousands],
        <List<String>>[
          <String>['thousands', '#,##0.00', '1,234.50'],
        ],
        XlsxFormatLocale.enUS,
        column: 2,
      ).single;
      expect(outcome, isA<OracleMatch>());
    });

    test('a by-eye case is not compared', () {
      final OracleCase red = OracleCase(
        id: 'red',
        row: 0,
        code: '[Red]0',
        value: XlsxDecimal('5'),
        byEye: 'colour',
      );
      final OracleOutcome outcome = compareOracle(
        <OracleCase>[red],
        <List<String>>[
          <String>['anything'],
        ],
        XlsxFormatLocale.enUS,
      ).single;
      expect(outcome, isA<OracleByEye>());
      expect(outcome.kase, same(red));
    });

    test('a by-eye case needs no row', () {
      final OracleCase red = OracleCase(
        id: 'red',
        row: 7,
        code: '[Red]0',
        value: XlsxDecimal('5'),
        byEye: 'colour',
      );
      expect(
        compareOracle(
          <OracleCase>[red],
          const <List<String>>[],
          XlsxFormatLocale.enUS,
        ).single,
        isA<OracleByEye>(),
      );
    });

    test('a case whose row the CSV lacks is a missing row', () {
      final OracleCase late = OracleCase(
        id: 'late',
        row: 3,
        code: '0',
        value: XlsxDecimal('5'),
      );
      final OracleOutcome outcome = compareOracle(
        <OracleCase>[late],
        <List<String>>[
          <String>['5'],
        ],
        XlsxFormatLocale.enUS,
      ).single;
      expect(outcome, isA<OracleMissingRow>());
      expect(outcome.kase, same(late));
    });

    test('a row without the column is a missing row', () {
      final OracleOutcome outcome = compareOracle(
        <OracleCase>[thousands],
        <List<String>>[
          <String>['thousands'],
        ],
        XlsxFormatLocale.enUS,
        column: 2,
      ).single;
      expect(outcome, isA<OracleMissingRow>());
    });

    test('rowCountMismatch: each case past the last row is missing', () {
      final List<OracleCase> cases = <OracleCase>[
        for (int i = 0; i < 5; i++)
          OracleCase(id: 'c$i', row: i, code: '0', value: XlsxDecimal('$i')),
      ];
      final List<OracleOutcome> outcomes = compareOracle(cases, <List<String>>[
        <String>['0'],
        <String>['1'],
      ], XlsxFormatLocale.enUS);
      expect(outcomes, hasLength(5));
      expect(outcomes.take(2), everyElement(isA<OracleMatch>()));
      expect(outcomes.skip(2), everyElement(isA<OracleMissingRow>()));
      expect(outcomes.skip(2).map((OracleOutcome o) => o.kase.id), <String>[
        'c2',
        'c3',
        'c4',
      ]);
    });

    test('a 1904 case formats in the 1904 date system', () {
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[
          OracleCase(
            id: 'neg1904',
            row: 0,
            code: 'h:mm',
            value: XlsxDecimal('-0.25'),
            date1904: true,
          ),
        ],
        <List<String>>[
          <String>['-6:00'],
        ],
        XlsxFormatLocale.enUS,
      );
      expect(outcomes.single, isA<OracleMatch>());
    });

    test('a 1900 case of the same value does not match -6:00', () {
      final OracleOutcome outcome = compareOracle(
        <OracleCase>[
          OracleCase(
            id: 'neg1900',
            row: 0,
            code: 'h:mm',
            value: XlsxDecimal('-0.25'),
          ),
        ],
        <List<String>>[
          <String>['-6:00'],
        ],
        XlsxFormatLocale.enUS,
      ).single;
      expect(outcome, isA<OracleMismatch>());
    });

    test('a builtinId case formats with numberFormatId', () {
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[
          OracleCase(
            id: 'builtin14',
            row: 0,
            builtinId: 14,
            value: XlsxDecimal('46000'),
          ),
          OracleCase(
            id: 'builtin4',
            row: 1,
            builtinId: 4,
            value: XlsxDecimal('1234.5'),
          ),
        ],
        <List<String>>[
          <String>['09.12.2025'],
          <String>['1.234,50'],
        ],
        XlsxFormatLocale.deDE,
      );
      expect(outcomes, everyElement(isA<OracleMatch>()));
    });

    test('formats non-number values', () {
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[
          const OracleCase(id: 'bool', row: 0, code: 'General', value: true),
          const OracleCase(id: 'text', row: 1, code: '"Name: "@', value: 'Ada'),
          const OracleCase(
            id: 'error',
            row: 2,
            code: '0.00',
            value: XlsxErrorValue.div0,
          ),
        ],
        <List<String>>[
          <String>['TRUE'],
          <String>['Name: Ada'],
          <String>['#DIV/0!'],
        ],
        XlsxFormatLocale.enUS,
      );
      expect(outcomes, everyElement(isA<OracleMatch>()));
    });

    test('returns one outcome per case, in case order', () {
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[
          OracleCase(id: 'b', row: 1, code: '0', value: XlsxDecimal('2')),
          OracleCase(id: 'a', row: 0, code: '0', value: XlsxDecimal('1')),
        ],
        <List<String>>[
          <String>['1'],
          <String>['2'],
        ],
        XlsxFormatLocale.enUS,
      );
      expect(outcomes.map((OracleOutcome o) => o.kase.id), <String>['b', 'a']);
      expect(outcomes, everyElement(isA<OracleMatch>()));
    });
  });

  group('oracleReport', () {
    test('lists mismatches and missing rows, then the counts', () {
      final List<OracleOutcome> outcomes = compareOracle(
        <OracleCase>[
          OracleCase(id: 'ok', row: 0, code: '0', value: XlsxDecimal('1')),
          OracleCase(id: 'pad', row: 1, code: '0_)', value: XlsxDecimal('2')),
          OracleCase(
            id: 'red',
            row: 2,
            code: '[Red]0',
            value: XlsxDecimal('3'),
            byEye: 'colour',
          ),
          const OracleCase(id: 'gone', row: 9, builtinId: 14, value: true),
        ],
        <List<String>>[
          <String>['1'],
          <String>['2'],
          <String>['3'],
        ],
        XlsxFormatLocale.enUS,
      );
      final String report = oracleReport('en-US', outcomes);
      final List<String> lines = report.split('\n');
      expect(lines.first, contains('en-US'));
      expect(report, contains('pad  0_)  2  excel=«2»  ours=«2 »'));
      expect(report, contains('gone  builtin 14  true  missing row'));
      expect(report, isNot(contains('ok  ')));
      expect(report, isNot(contains('red  ')));
      expect(report, contains('match 1, mismatch 1, by eye 1, missing row 1'));
      expect(
        lines.indexWhere((String l) => l.startsWith('pad  ')),
        lessThan(lines.indexWhere((String l) => l.startsWith('gone  '))),
      );
    });

    test('says so when nothing differs', () {
      final String report = oracleReport(
        'de-DE',
        compareOracle(
          <OracleCase>[
            OracleCase(id: 'ok', row: 0, code: '0', value: XlsxDecimal('1')),
          ],
          <List<String>>[
            <String>['1'],
          ],
          XlsxFormatLocale.deDE,
        ),
      );
      expect(report, contains('match 1, mismatch 0, by eye 0, missing row 0'));
    });
  });
}
