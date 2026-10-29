// Tests the comparison core behind the number format oracle test
// (test/xlsx/format/oracle_test.dart): the CSV reader, the matching rules
// for Excel's CSV and the manifest parser.
//
// They read no files, so they run on the web as well as the VM.
import 'dart:convert';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/format_oracle.dart';
import '../../tool/src/format_oracle_compare.dart';

const OracleWorkbook _main = OracleWorkbook(
  'main',
  'format_oracle.xlsx',
  false,
  <int, String>{},
);

const OracleWorkbook _date1904 = OracleWorkbook(
  'date1904',
  'format_oracle_1904.xlsx',
  true,
  <int, String>{4: '0.000', 14: 'yyyy-mm-dd'},
);

OracleCase _case(
  String id, {
  OracleValue value = const OracleNumber('1234.5'),
  String? code = '#,##0.00',
  int? builtinId,
  String workbook = 'main',
  bool eyeOnly = false,
  String note = 'a note',
}) => OracleCase(
  id: id,
  checks: const <String>[],
  unknown: null,
  workbook: workbook,
  date1904: workbook == 'date1904',
  value: value,
  code: builtinId == null ? code : null,
  builtinId: builtinId,
  eyeOnly: eyeOnly,
  note: note,
);

OracleCases _cases(List<OracleCase> cases) => OracleCases(
  const <String, OracleWorkbook>{'main': _main, 'date1904': _date1904},
  cases,
);

List<OracleOutcome> _compare(
  List<OracleCase> cases,
  Map<String, String> csv, {
  String workbook = 'main',
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
  Map<String, String> eye = const <String, String>{},
}) => compareOracle(_cases(cases), workbook, locale, csv: csv, eye: eye);

Map<String, Object?> _entry([Map<String, Object?> fields = const {}]) =>
    <String, Object?>{
      'region': 'de-DE',
      'appleLocale': 'de_DE',
      'excelLanguage': 'Deutsch',
      'excel': 'Microsoft Excel for Mac 16.102 (25101918)',
      'macos': '26.1',
      'confirmedBy': 'owner',
      'csv': <String, Object?>{
        'format_oracle.xlsx': 'format_oracle.de-DE.csv',
        'format_oracle_1904.xlsx': 'format_oracle_1904.de-DE.csv',
      },
      'eye': <String, Object?>{'u14-01': '1,23457E+11'},
      'notes': '',
      ...fields,
    };

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

    test('ends a row at a lone CR, but keeps a CR inside quotes', () {
      expect(parseCsv('a\rb', separator: ','), <List<String>>[
        <String>['a'],
        <String>['b'],
      ]);
      expect(parseCsv('"a\rb",c', separator: ','), <List<String>>[
        <String>['a\rb', 'c'],
      ]);
    });

    test('a blank line before the trailing newline is a blank row', () {
      expect(parseCsv('a\n\n', separator: ','), <List<String>>[
        <String>['a'],
        <String>[''],
      ]);
    });

    test('reads a quoted field at the end of text with no newline', () {
      expect(parseCsv('x,"a"', separator: ','), <List<String>>[
        <String>['x', 'a'],
      ]);
      expect(parseCsv('"a"', separator: ','), <List<String>>[
        <String>['a'],
      ]);
    });

    test('throws FormatException on text after a closing quote', () {
      expect(
        () => parseCsv('"a"b,c', separator: ','),
        throwsA(isA<FormatException>()),
      );
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

  group('oracleCsvSeparator', () {
    test('reads , or ; from the header row, after a BOM', () {
      expect(oracleCsvSeparator('value,code,case,note\r\n1,0,a,n'), ',');
      expect(oracleCsvSeparator('﻿value;code;case;note\r\n'), ';');
      expect(oracleCsvSeparator('value;code;case;note'), ';');
      expect(oracleCsvSeparator('value,code,case,note\n'), ',');
    });

    test('is not fooled by a ; in a code', () {
      expect(
        oracleCsvSeparator('value,code,case,note\n5,"0;-0;;@",a,n\n'),
        ',',
      );
    });

    test('throws FormatException on any other header', () {
      for (final String text in <String>[
        '',
        'value,code,case',
        'value,code,case,note,extra\n',
        'value\tcode\tcase\tnote\n',
        'Value,Code,Case,Note\n',
        'value,code;case,note\n',
        ' value,code,case,note\n',
        '1,0,a,n\nvalue,code,case,note\n',
      ]) {
        expect(
          () => oracleCsvSeparator(text),
          throwsFormatException,
          reason: text,
        );
      }
    });
  });

  group('parseOracleCsv', () {
    test('maps each case id to column A, after the header', () {
      expect(
        parseOracleCsv(
          '﻿value;code;case;note\r\n'
          '1.234,50;#,##0.00;c1-01;n\r\n'
          '"5 ";"0_);(0)";c1-02;"a; b"\r\n',
        ),
        <String, String>{'c1-01': '1.234,50', 'c1-02': '5 '},
      );
    });

    test('keeps the order of rows irrelevant', () {
      expect(
        parseOracleCsv('value,code,case,note\nb,0,x-2,n\na,0,x-1,n\n'),
        <String, String>{'x-1': 'a', 'x-2': 'b'},
      );
    });

    test('a header alone has no cases', () {
      expect(parseOracleCsv('value,code,case,note\r\n'), isEmpty);
    });

    test('throws FormatException on a duplicate case id', () {
      expect(
        () => parseOracleCsv('value,code,case,note\n1,0,a,n\n2,0,a,n\n'),
        throwsFormatException,
      );
    });

    test('throws FormatException on a row with no case id', () {
      expect(
        () => parseOracleCsv('value,code,case,note\n1,0\n'),
        throwsFormatException,
      );
      expect(
        () => parseOracleCsv('value,code,case,note\n1,0,,n\n'),
        throwsFormatException,
      );
    });

    test('throws FormatException on a bad header', () {
      expect(() => parseOracleCsv('a,b,c,d\n1,0,a,n\n'), throwsFormatException);
    });
  });

  group('oracleLocale', () {
    test('maps the three regions to their locales', () {
      expect(oracleLocale('en-US'), same(XlsxFormatLocale.enUS));
      expect(oracleLocale('de-DE'), same(XlsxFormatLocale.deDE));
      expect(oracleLocale('tr-TR'), same(XlsxFormatLocale.trTR));
      expect(oracleRegions, <String>['en-US', 'de-DE', 'tr-TR']);
    });

    test('throws ArgumentError on another region', () {
      expect(() => oracleLocale('fr-FR'), throwsArgumentError);
    });
  });

  group('oracleTextMatches', () {
    XlsxFormattedValue fmt(String code, String digits) => XlsxNumberFormatter(
      locale: XlsxFormatLocale.enUS,
    ).format(XlsxDecimal(digits), numberFormat: code);

    test('is exact for a plain result, spaces included', () {
      final XlsxFormattedValue padded = fmt('0_)', '5');
      expect(padded.text, '5 ');
      expect(oracleTextMatches('5 ', padded), isTrue);
      expect(oracleTextMatches('5', padded), isFalse);
      expect(oracleTextMatches(' 5 ', padded), isFalse);
      expect(oracleTextMatches('5 ', fmt('0', '5')), isFalse);
    });

    test('an all-# text of any length matches an overflow', () {
      final XlsxFormattedValue overflow = fmt('[>10]0;[<-10]0', '5');
      expect(overflow.overflow, isTrue);
      for (final String text in <String>['#', '##', '###########']) {
        expect(oracleTextMatches(text, overflow), isTrue, reason: text);
      }
      expect(oracleTextMatches('', overflow), isFalse);
      expect(oracleTextMatches('5', overflow), isFalse);
      expect(oracleTextMatches('#5', overflow), isFalse);
      expect(oracleTextMatches('# #', overflow), isFalse);
    });

    test('an all-# text does not match a result without overflow', () {
      expect(oracleTextMatches('#', fmt('"#"', '5')), isTrue);
      expect(oracleTextMatches('##', fmt('"#"', '5')), isFalse);
      expect(oracleTextMatches('####', fmt('0', '5')), isFalse);
    });

    test('a fill matches zero or more of its character', () {
      final XlsxFormattedValue filled = fmt('"a"*~0', '5');
      expect(filled.parts.whereType<XlsxFormatFill>(), hasLength(1));
      for (final String text in <String>['a5', 'a~5', 'a~~~~~5']) {
        expect(oracleTextMatches(text, filled), isTrue, reason: text);
      }
      for (final String text in <String>['a 5', 'a+5', 'a5~', '~a5', 'a~5 ']) {
        expect(oracleTextMatches(text, filled), isFalse, reason: text);
      }
    });

    test('a space fill with padding: padding is one space, exact', () {
      final XlsxFormattedValue accounting = XlsxNumberFormatter(
        locale: XlsxFormatLocale.enUS,
      ).format(XlsxDecimal('1234.5'), numberFormatId: 44);
      expect(accounting.parts.whereType<XlsxFormatFill>(), hasLength(1));
      expect(accounting.text, r' $1,234.50 ');
      expect(oracleTextMatches(r' $1,234.50 ', accounting), isTrue);
      expect(oracleTextMatches(r' $    1,234.50 ', accounting), isTrue);
      expect(oracleTextMatches(r'$1,234.50 ', accounting), isFalse);
      expect(oracleTextMatches(r' $1,234.50', accounting), isFalse);
    });

    test('a fill char that can be part of a number is exact', () {
      // 0*0 on 5: a 0 fill would hide 50000.
      final XlsxFormattedValue zeros = fmt('0*0', '5');
      expect(oracleTextMatches('5', zeros), isTrue);
      expect(oracleTextMatches('50000', zeros), isFalse);
      // 0*- on 5: a - fill would hide a sign.
      final XlsxFormattedValue dashes = fmt('0*-', '5');
      expect(oracleTextMatches('5', dashes), isTrue);
      expect(oracleTextMatches('5-----', dashes), isFalse);
      for (final String code in <String>['0*.', '#,##0*,', '0*#', '0*9']) {
        final XlsxFormattedValue value = fmt(code, '5');
        expect(oracleTextMatches('5', value), isTrue, reason: code);
        expect(
          oracleTextMatches('5${code[code.length - 1]}', value),
          isFalse,
          reason: code,
        );
      }
    });

    test('a fill char in an adjacent text is exact', () {
      final XlsxFormattedValue value = fmt('"ax"*x0', '5');
      expect(value.text, 'ax5');
      expect(oracleTextMatches('ax5', value), isTrue);
      expect(oracleTextMatches('axx5', value), isFalse);
      final XlsxFormattedValue after = fmt('0*x"xb"', '5');
      expect(oracleTextMatches('5xb', after), isTrue);
      expect(oracleTextMatches('5xxb', after), isFalse);
    });

    test('characters special to a regular expression are literal', () {
      final XlsxFormattedValue filled = fmt(r'"(.)"*?0', '5');
      expect(oracleTextMatches('(.)???5', filled), isTrue);
      expect(oracleTextMatches('(x)5', filled), isFalse);
      expect(oracleTextMatches('(.)..5', filled), isFalse);
    });
  });

  group('compareOracle', () {
    final OracleCase thousands = _case('thousands');

    test('a row with the same text matches', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[thousands],
        <String, String>{'thousands': '1,234.50'},
      );
      expect(outcomes, hasLength(1));
      expect(outcomes.single, isA<OracleMatch>());
      expect(outcomes.single.kase, same(thousands));
      expect((outcomes.single as OracleMatch).text, '1,234.50');
    });

    test('uses the locale it is given', () {
      expect(
        _compare(
          <OracleCase>[thousands],
          <String, String>{'thousands': '1.234,50'},
          locale: XlsxFormatLocale.deDE,
        ).single,
        isA<OracleMatch>(),
      );
    });

    test('a different text is a mismatch with both texts', () {
      final OracleOutcome outcome = _compare(
        <OracleCase>[thousands],
        <String, String>{'thousands': '1,234.5'},
      ).single;
      expect(outcome, isA<OracleMismatch>());
      expect((outcome as OracleMismatch).expected, '1,234.5');
      expect(outcome.actual, '1,234.50');
    });

    test('matches rows by case id, not by position', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[
          _case('b', value: const OracleNumber('2'), code: '0'),
          _case('a', value: const OracleNumber('1'), code: '0'),
        ],
        <String, String>{'a': '1', 'b': '2'},
      );
      expect(outcomes.map((OracleOutcome o) => o.kase.id), <String>['b', 'a']);
      expect(outcomes, everyElement(isA<OracleMatch>()));
    });

    test('a case whose id the CSV lacks is a missing row', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[
          for (int i = 0; i < 4; i++)
            _case('c$i', value: OracleNumber('$i'), code: '0'),
        ],
        <String, String>{'c0': '0', 'c1': '1'},
      );
      expect(outcomes.take(2), everyElement(isA<OracleMatch>()));
      expect(outcomes.skip(2), everyElement(isA<OracleMissingRow>()));
    });

    test('compares only the cases of the workbook it is given', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[
          _case('m', code: '0', value: const OracleNumber('1')),
          _case(
            'd',
            code: 'yyyy-mm-dd',
            value: const OracleNumber('1'),
            workbook: 'date1904',
          ),
        ],
        <String, String>{'d': '1904-01-02'},
        workbook: 'date1904',
      );
      expect(outcomes.map((OracleOutcome o) => o.kase.id), <String>['d']);
      expect(outcomes.single, isA<OracleMatch>());
    });

    test('throws ArgumentError on an unknown workbook', () {
      expect(
        () => _compare(<OracleCase>[thousands], const {}, workbook: 'nope'),
        throwsArgumentError,
      );
    });

    test('a 1904 case formats in the 1904 date system', () {
      final OracleOutcome outcome = _compare(
        <OracleCase>[
          _case(
            'neg',
            code: 'h:mm',
            value: const OracleNumber('-0.25'),
            workbook: 'date1904',
          ),
        ],
        <String, String>{'neg': '-6:00'},
        workbook: 'date1904',
      ).single;
      expect(outcome, isA<OracleMatch>());
    });

    test('a builtinId case passes the id, and the file code for it', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[
          _case(
            'id14',
            builtinId: 14,
            value: const OracleNumber('46323'),
            workbook: 'date1904',
          ),
          _case(
            'id4',
            builtinId: 4,
            value: const OracleNumber('1234.5'),
            workbook: 'date1904',
          ),
        ],
        <String, String>{'id14': '2030-10-29', 'id4': '1234,500'},
        workbook: 'date1904',
        locale: XlsxFormatLocale.deDE,
      );
      expect(outcomes, everyElement(isA<OracleMatch>()));
    });

    test('a builtinId case without a file code uses the locale', () {
      String id14(XlsxFormatLocale locale) => XlsxNumberFormatter(
        locale: locale,
      ).format(46000, numberFormatId: 14).text;
      expect(id14(XlsxFormatLocale.deDE), isNot(id14(XlsxFormatLocale.enUS)));
      final OracleOutcome outcome = _compare(
        <OracleCase>[
          _case('id14', builtinId: 14, value: const OracleNumber('46000')),
        ],
        <String, String>{'id14': id14(XlsxFormatLocale.deDE)},
        locale: XlsxFormatLocale.deDE,
      ).single;
      expect(outcome, isA<OracleMatch>());
    });

    test('formats booleans and texts', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[
          _case('b', value: const OracleBool(true), code: 'General'),
          _case('s', value: const OracleText('Ada'), code: '"Name: "@'),
        ],
        <String, String>{'b': 'WAHR', 's': 'Name: Ada'},
        locale: XlsxFormatLocale.deDE,
      );
      expect(outcomes, everyElement(isA<OracleMatch>()));
    });

    test('an overflow and a fill match by their tolerances', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[
          _case('over', code: '[>10]0;[<-10]0', value: const OracleNumber('5')),
          _case('fill', code: '"a"*~0', value: const OracleNumber('5')),
        ],
        <String, String>{'over': '#####', 'fill': 'a~~~5'},
      );
      expect(outcomes, everyElement(isA<OracleMatch>()));
      expect((outcomes[0] as OracleMatch).text, '#####');
    });

    group('eye-only cases', () {
      final OracleCase general = _case(
        'u14-01',
        code: 'General',
        value: const OracleNumber('123456789012'),
        eyeOnly: true,
        note: 'General at the default width',
      );
      final OracleCase spill = _case(
        'c17-01',
        code: 'General',
        value: const OracleManual('=SEQUENCE(1,2)', '#SPILL!'),
        eyeOnly: true,
        note: 'spill error',
      );
      final OracleCase calc = _case(
        'c17-02',
        code: 'General',
        value: const OracleManual('=FILTER(1,FALSE)', '#CALC!'),
        eyeOnly: true,
        note: 'calc error',
      );

      test('compare with the eye text, never with the CSV', () {
        final List<OracleOutcome> outcomes = _compare(
          <OracleCase>[general, spill, calc],
          <String, String>{'u14-01': 'wrong', 'c17-01': 'wrong'},
          eye: <String, String>{
            'u14-01': '1.2346E+11',
            'c17-01': '#SPILL!',
            'c17-02': '#CALC!',
          },
        );
        expect(outcomes, everyElement(isA<OracleMatch>()));
      });

      test('General uses the eye column width of 10', () {
        final OracleOutcome outcome = _compare(
          <OracleCase>[general],
          const <String, String>{},
          eye: <String, String>{'u14-01': '123456789012'},
        ).single;
        expect(outcome, isA<OracleMismatch>());
        expect((outcome as OracleMismatch).actual, '1.2346E+11');
      });

      test('a CSV-compared General case keeps the width of 11', () {
        final OracleOutcome outcome = _compare(
          <OracleCase>[
            _case(
              'g',
              code: 'General',
              value: const OracleNumber('123456789012'),
            ),
          ],
          const <String, String>{'g': 'x'},
        ).single;
        expect((outcome as OracleMismatch).actual, '1.23457E+11');
      });

      test('a different eye text is a mismatch', () {
        final OracleOutcome outcome = _compare(
          <OracleCase>[spill],
          const <String, String>{},
          eye: <String, String>{'c17-01': '#ÜBERLAUF!'},
        ).single;
        expect(outcome, isA<OracleMismatch>());
        expect((outcome as OracleMismatch).expected, '#ÜBERLAUF!');
        expect(outcome.actual, '#SPILL!');
      });

      test('without eye text they are by eye', () {
        final List<OracleOutcome> outcomes = _compare(
          <OracleCase>[general, spill],
          <String, String>{'u14-01': '1.23457E+11'},
        );
        expect(outcomes, everyElement(isA<OracleByEye>()));
      });

      test('a manual case shows its error in the locale', () {
        final OracleOutcome outcome = _compare(
          <OracleCase>[
            _case(
              'x',
              code: 'General',
              value: const OracleManual('=NA()', '#N/A'),
              eyeOnly: true,
            ),
          ],
          const <String, String>{},
          locale: XlsxFormatLocale.deDE,
          eye: <String, String>{'x': '#NV'},
        ).single;
        expect(outcome, isA<OracleMatch>());
      });
    });
  });

  group('oracleReport', () {
    test('lists mismatches, by-eye cases and missing rows, then counts', () {
      final List<OracleOutcome> outcomes = _compare(
        <OracleCase>[
          _case('ok', code: '0', value: const OracleNumber('1')),
          _case('pad', code: '0_)', value: const OracleNumber('2')),
          _case(
            'eye',
            code: 'General',
            value: const OracleManual('=SEQUENCE(1,2)', '#SPILL!'),
            eyeOnly: true,
            note: 'spill error',
          ),
          _case('gone', builtinId: 14, value: const OracleBool(true)),
          _case('txt', code: '@', value: const OracleText('a')),
        ],
        <String, String>{'ok': '1', 'pad': '2', 'txt': 'a'},
      );
      final String report = oracleReport('en-US', outcomes);
      final List<String> lines = report.split('\n');
      expect(lines.first, 'number format oracle: en-US');
      expect(report, contains('pad  0_)  2  excel=«2»  ours=«2 »'));
      expect(report, contains('gone  builtin 14  true  missing row'));
      expect(
        report,
        contains('eye  General  =SEQUENCE(1,2)  by eye: spill error'),
      );
      expect(report, isNot(contains('ok  ')));
      expect(report, isNot(contains('txt  ')));
      expect(lines.last, 'match 2, mismatch 1, by eye 1, missing row 1');
    });

    test('quotes a text value', () {
      final String report = oracleReport(
        'x',
        _compare(
          <OracleCase>[_case('t', code: '@', value: const OracleText('a'))],
          <String, String>{'t': 'b'},
        ),
      );
      expect(report, contains('t  @  "a"  excel=«b»  ours=«a»'));
    });
  });

  group('parseOracleManifest', () {
    test('an empty list has no entries', () {
      expect(parseOracleManifest('[]'), isEmpty);
    });

    test('reads every field', () {
      final List<OracleManifestEntry> entries = parseOracleManifest(
        jsonEncode(<Object?>[
          _entry(<String, Object?>{'notes': 'repaired'}),
        ]),
      );
      final OracleManifestEntry entry = entries.single;
      expect(entry.region, 'de-DE');
      expect(entry.appleLocale, 'de_DE');
      expect(entry.excelLanguage, 'Deutsch');
      expect(entry.excel, 'Microsoft Excel for Mac 16.102 (25101918)');
      expect(entry.macos, '26.1');
      expect(entry.confirmedBy, 'owner');
      expect(entry.csv, <String, String>{
        'format_oracle.xlsx': 'format_oracle.de-DE.csv',
        'format_oracle_1904.xlsx': 'format_oracle_1904.de-DE.csv',
      });
      expect(entry.eye, <String, String>{'u14-01': '1,23457E+11'});
      expect(entry.notes, 'repaired');
    });

    void rejects(Object? doc, String path) {
      expect(
        () => parseOracleManifest(jsonEncode(doc)),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            startsWith('$path:'),
          ),
        ),
        reason: path,
      );
    }

    test('throws FormatException with the path of the problem', () {
      expect(() => parseOracleManifest('{'), throwsA(isA<FormatException>()));
      rejects(<String, Object?>{}, r'$');
      rejects(<Object?>['x'], '[0]');
      rejects(<Object?>[
        _entry(<String, Object?>{'extra': 1}),
      ], '[0]');
      final Map<String, Object?> noNotes = _entry()..remove('notes');
      rejects(<Object?>[noNotes], '[0].notes');
      rejects(<Object?>[
        _entry(<String, Object?>{'region': 'fr-FR'}),
      ], '[0].region');
      rejects(<Object?>[
        _entry(<String, Object?>{'confirmedBy': 'Owner'}),
      ], '[0].confirmedBy');
      rejects(<Object?>[
        _entry(<String, Object?>{'confirmedBy': 'claude'}),
      ], '[0].confirmedBy');
      rejects(<Object?>[
        _entry(<String, Object?>{'macos': 26}),
      ], '[0].macos');
      rejects(<Object?>[
        _entry(<String, Object?>{'notes': null}),
      ], '[0].notes');
      rejects(<Object?>[
        _entry(<String, Object?>{'csv': <Object?>[]}),
      ], '[0].csv');
      rejects(<Object?>[
        _entry(<String, Object?>{
          'csv': <String, Object?>{'format_oracle.xlsx': 3},
        }),
      ], '[0].csv.format_oracle.xlsx');
      rejects(<Object?>[
        _entry(<String, Object?>{
          'eye': <String, Object?>{'a': 1},
        }),
      ], '[0].eye.a');
    });

    test('a CSV is named <workbook stem>.<region>.csv', () {
      rejects(<Object?>[
        _entry(<String, Object?>{
          'csv': <String, Object?>{
            'format_oracle.xlsx': 'format_oracle.en-US.csv',
          },
        }),
      ], '[0].csv.format_oracle.xlsx');
      rejects(<Object?>[
        _entry(<String, Object?>{
          'csv': <String, Object?>{
            'format_oracle.csv': 'format_oracle.de-DE.csv',
          },
        }),
      ], '[0].csv.format_oracle.csv');
      rejects(<Object?>[
        _entry(<String, Object?>{
          'csv': <String, Object?>{
            'a/format_oracle.xlsx': 'a/format_oracle.de-DE.csv',
          },
        }),
      ], '[0].csv.a/format_oracle.xlsx');
    });

    test('a region is run at most once', () {
      rejects(<Object?>[_entry(), _entry()], '[1].region');
    });
  });

  group('oracleManifestProblems', () {
    const OracleWorkbook invalid = OracleWorkbook(
      'invalid',
      'format_oracle_invalid.xlsx',
      false,
      <int, String>{},
    );
    final OracleCases cases = OracleCases(
      const <String, OracleWorkbook>{
        'main': _main,
        'date1904': _date1904,
        'invalid': invalid,
      },
      <OracleCase>[
        _case('m-1'),
        _case('e-1', eyeOnly: true),
        _case('e-2', eyeOnly: true),
        _case('e-3', eyeOnly: true, workbook: 'date1904'),
        _case('i-1', workbook: 'invalid'),
      ],
    );

    OracleManifestEntry entry({
      String region = 'de-DE',
      List<String> files = const <String>[
        'format_oracle.xlsx',
        'format_oracle_1904.xlsx',
      ],
      Map<String, String> eye = const <String, String>{
        'e-1': 'a',
        'e-2': 'b',
        'e-3': 'c',
      },
    }) => OracleManifestEntry(
      region: region,
      appleLocale: 'x',
      excelLanguage: 'x',
      excel: 'x',
      macos: 'x',
      confirmedBy: 'owner',
      csv: <String, String>{
        for (final String f in files)
          f: '${f.substring(0, f.length - 5)}.$region.csv',
      },
      eye: eye,
      notes: '',
    );

    test('a complete entry has none', () {
      expect(oracleManifestProblems(entry(), cases), isEmpty);
      expect(
        oracleManifestProblems(
          entry(
            region: 'en-US',
            files: <String>[
              'format_oracle.xlsx',
              'format_oracle_1904.xlsx',
              'format_oracle_invalid.xlsx',
            ],
          ),
          cases,
        ),
        isEmpty,
      );
    });

    test('every region runs the main and the 1904 workbook', () {
      expect(
        oracleManifestProblems(
          entry(
            files: <String>['format_oracle.xlsx'],
            eye: const <String, String>{'e-1': 'a', 'e-2': 'b'},
          ),
          cases,
        ),
        <String>['de-DE: format_oracle_1904.xlsx not run'],
      );
      expect(
        oracleManifestProblems(
          entry(
            files: <String>['format_oracle_1904.xlsx'],
            eye: const <String, String>{'e-3': 'c'},
          ),
          cases,
        ),
        <String>['de-DE: format_oracle.xlsx not run'],
      );
    });

    test('en-US runs the invalid workbook too', () {
      expect(oracleManifestProblems(entry(region: 'en-US'), cases), <String>[
        'en-US: format_oracle_invalid.xlsx not run',
      ]);
    });

    test('a CSV of no workbook is a problem', () {
      expect(
        oracleManifestProblems(
          entry(
            files: <String>[
              'format_oracle.xlsx',
              'format_oracle_1904.xlsx',
              'other.xlsx',
            ],
          ),
          cases,
        ),
        <String>['de-DE: other.xlsx is no workbook of the case list'],
      );
    });

    test('every eye-only case of a run workbook needs an eye text', () {
      expect(
        oracleManifestProblems(
          entry(eye: const <String, String>{'e-2': 'b'}),
          cases,
        ),
        <String>['de-DE: no eye text for e-1, e-3'],
      );
    });

    test('an eye text needs an eye-only case', () {
      expect(
        oracleManifestProblems(
          entry(
            eye: const <String, String>{
              'e-1': 'a',
              'e-2': 'b',
              'e-3': 'c',
              'm-1': 'd',
              'zz': 'e',
            },
          ),
          cases,
        ),
        <String>['de-DE: eye text for no eye-only case: m-1, zz'],
      );
    });
  });

  group('knownDifferenceProblems', () {
    final OracleCases cases = _cases(<OracleCase>[_case('c4-01')]);

    test('a key names a case id and a region', () {
      expect(
        knownDifferenceProblems(const <String, String>{
          'c4-01 de-DE': 'ruling 3',
        }, cases),
        isEmpty,
      );
      expect(
        knownDifferenceProblems(const <String, String>{
          'c4-02 de-DE': 'r',
          'c4-01 fr-FR': 'r',
          'c4-01': 'r',
          'c4-01  de-DE': 'r',
        }, cases),
        <String>[
          'c4-02 de-DE: no such case',
          'c4-01 fr-FR: no such region',
          'c4-01: expected <case id> <region>',
          'c4-01  de-DE: expected <case id> <region>',
        ],
      );
    });

    test('a known difference needs a reason', () {
      expect(
        knownDifferenceProblems(const <String, String>{
          'c4-01 de-DE': '',
        }, cases),
        <String>['c4-01 de-DE: no reason'],
      );
    });
  });
}
