// Tests the logic behind tool/compare_format_libreoffice.dart: which CSV
// file holds a workbook's `cases` sheet, and the report over every
// workbook LibreOffice exported.
//
// They read no files, so they run on the web as well as the VM.
import 'package:test/test.dart';

import '../../tool/src/format_libreoffice.dart';
import '../../tool/src/format_oracle.dart';

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
  <int, String>{},
);

OracleCase _case(
  String id, {
  String code = '#,##0.00',
  String workbook = 'main',
  bool eyeOnly = false,
}) => OracleCase(
  id: id,
  checks: const <String>[],
  unknown: null,
  workbook: workbook,
  date1904: workbook == 'date1904',
  value: const OracleNumber('1234.5'),
  code: code,
  builtinId: null,
  eyeOnly: eyeOnly,
  note: 'a note',
);

final OracleCases _cases = OracleCases(
  const <String, OracleWorkbook>{'main': _main, 'date1904': _date1904},
  <OracleCase>[
    _case('a-01'),
    _case('a-02', code: '0.0'),
    _case('a-03', eyeOnly: true),
    _case('b-01', workbook: 'date1904'),
  ],
);

void main() {
  group('libreOfficeCsvName', () {
    test('prefers the cases sheet export, <stem>-cases.csv', () {
      expect(
        libreOfficeCsvName('format_oracle.xlsx', <String>{
          'format_oracle.csv',
          'format_oracle-cases.csv',
        }),
        'format_oracle-cases.csv',
      );
    });

    test('takes <stem>.csv, the first sheet, when there is no -cases', () {
      expect(
        libreOfficeCsvName('format_oracle.xlsx', <String>{'format_oracle.csv'}),
        'format_oracle.csv',
      );
    });

    test('ignores another workbook whose stem starts the same', () {
      expect(
        libreOfficeCsvName('format_oracle.xlsx', <String>{
          'format_oracle_1904.csv',
          'format_oracle_1904-cases.csv',
          'format_oracle-eye.csv',
        }),
        isNull,
      );
    });
  });

  group('libreOfficeReport', () {
    test('reports each workbook with a CSV, then a total line', () {
      final String report = libreOfficeReport(_cases, 'en-US', <String, String>{
        'main': 'value,code,case,note\n9,0.0,a-02,\n',
        'date1904': 'value,code,case,note\n"1,234.50",x,b-01,\n',
      });
      expect(report.split('\n'), <String>[
        'number format oracle: LibreOffice en-US format_oracle.xlsx',
        'a-01  #,##0.00  1234.5  missing row',
        'a-02  0.0  1234.5  excel=«9»  ours=«1234.5»',
        'a-03  #,##0.00  1234.5  by eye: a note',
        'match 0, mismatch 1, by eye 1, missing row 1',
        'number format oracle: LibreOffice en-US format_oracle_1904.xlsx',
        'match 1, mismatch 0, by eye 0, missing row 0',
        'total: match 1, mismatch 1, by eye 1, missing row 1 '
            '(2 workbooks)',
      ]);
    });

    test('skips a workbook without a CSV', () {
      final String report = libreOfficeReport(_cases, 'en-US', <String, String>{
        'date1904': 'value,code,case,note\n"1,234.50",x,b-01,\n',
      });
      expect(report, isNot(contains('format_oracle.xlsx')));
      expect(
        report,
        endsWith(
          'total: match 1, mismatch 0, by eye 0, missing row 0 '
          '(1 workbook)',
        ),
      );
    });

    test('uses the locale of the region', () {
      final String report = libreOfficeReport(_cases, 'de-DE', <String, String>{
        'date1904': 'value;code;case;note\r\n1.234,50;x;b-01;\r\n',
      });
      expect(report, contains('match 1, mismatch 0'));
    });

    test('throws FormatException naming the file of a bad CSV', () {
      expect(
        () => libreOfficeReport(_cases, 'en-US', <String, String>{
          'main': 'A,B,C\n',
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            startsWith('format_oracle.xlsx: '),
          ),
        ),
      );
    });

    test('throws FormatException on a CSV with no case rows', () {
      expect(
        () => libreOfficeReport(_cases, 'en-US', <String, String>{
          'main': 'value,code,case,note\n',
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'format_oracle.xlsx: no case rows',
          ),
        ),
      );
    });

    test('throws ArgumentError for an unknown workbook key or region', () {
      expect(
        () => libreOfficeReport(_cases, 'en-US', <String, String>{'x': ''}),
        throwsArgumentError,
      );
      expect(
        () => libreOfficeReport(_cases, 'fr-FR', <String, String>{}),
        throwsArgumentError,
      );
    });
  });
}
