import 'package:jet_office/src/xlsx/cell_encoder.dart';
import 'package:jet_office/src/xlsx/number_format.dart';
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xlsx/style.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  late SharedStrings strings;
  late StyleRegistry styles;
  late WarningCollector warnings;
  late CellEncoder encoder;

  setUp(() {
    strings = SharedStrings();
    styles = StyleRegistry();
    warnings = WarningCollector();
    encoder = CellEncoder(strings: strings, styles: styles, warnings: warnings);
  });

  String enc(Object? value, {XlsxStyle? rowStyle}) {
    final StringBuffer buffer = StringBuffer();
    encoder.encode(
      XmlWriter(buffer),
      sheet: 'S',
      row: 0,
      column: 0,
      value: value,
      rowStyle: rowStyle,
    );
    return buffer.toString();
  }

  List<XlsxWarningCode> codes() =>
      warnings.warnings.map((XlsxWarning w) => w.code).toList();

  test('DateTime is a date serial with a date-time format (Quds wrote '
      'toString)', () {
    expect(
      enc(DateTime(2026, 10, 24, 12)),
      '<c r="A1" s="1"><v>46319.5</v></c>',
    );
    expect(styles.idFor(const XlsxStyle(numFmt: XlsxNumFmt.localeDateTime)), 1);
  });

  test('NaN and infinity are ArgumentErrors (Quds wrote them verbatim)', () {
    expect(() => enc(double.nan), throwsArgumentError);
    expect(() => enc(double.infinity), throwsArgumentError);
    expect(() => enc(double.negativeInfinity), throwsArgumentError);
  });

  test('scalars', () {
    expect(enc(null), '');
    expect(enc(42), '<c r="A1"><v>42</v></c>');
    expect(enc(0.1), '<c r="A1"><v>0.1</v></c>');
    expect(enc(1e-7), '<c r="A1"><v>1e-7</v></c>');
    expect(enc(true), '<c r="A1" t="b"><v>1</v></c>');
    expect(enc(false), '<c r="A1" t="b"><v>0</v></c>');
    expect(enc(XlsxDecimal('-1234.50')), '<c r="A1"><v>-1234.50</v></c>');
    expect(enc(''), '<c r="A1" t="s"><v>0</v></c>');
    expect(warnings.warnings, isEmpty);
  });

  test('a string cell with a style writes s before t', () {
    expect(
      enc('x', rowStyle: const XlsxStyle(numFmt: XlsxNumFmt.custom('@'))),
      '<c r="A1" s="1" t="s"><v>0</v></c>',
    );
  });

  test('the default style writes no s attribute', () {
    expect(enc(1, rowStyle: const XlsxStyle()), '<c r="A1"><v>1</v></c>');
  });

  test('an explicit general format is a style of its own', () {
    expect(
      enc(1, rowStyle: const XlsxStyle(numFmt: XlsxNumFmt.general)),
      '<c r="A1" s="1"><v>1</v></c>',
    );
  });

  test('strings are scrubbed and truncated with warnings', () {
    expect(enc('a\u0001b'), '<c r="A1" t="s"><v>0</v></c>');
    expect(strings.values.first, 'ab');
    final String long = '${'x' * 32766}😀tail';
    enc(long);
    expect(strings.values.last.length, 32766);
    expect(codes(), <XlsxWarningCode>[
      XlsxWarningCode.invalidCharactersRemoved,
      XlsxWarningCode.textTruncated,
    ]);
  });

  test(
    'truncation keeps a pair that fits and cuts plain text at the limit',
    () {
      enc('${'x' * 32765}😀tail');
      expect(strings.values.last.length, 32767);
      expect(strings.values.last.endsWith('😀'), isTrue);
      enc('y' * 40000);
      expect(strings.values.last.length, 32767);
      expect(warnings.warnings.single.count, 2);
    },
  );

  test('a text of exactly 32,767 units is not truncated', () {
    enc('z' * 32767);
    expect(strings.values.single.length, 32767);
    expect(warnings.warnings, isEmpty);
  });

  test('warnings name the sheet and cell', () {
    final StringBuffer buffer = StringBuffer();
    encoder.encode(
      XmlWriter(buffer),
      sheet: 'Data',
      row: 4,
      column: 2,
      value: 'a\u0000',
    );
    expect(warnings.warnings.single.sheet, 'Data');
    expect(warnings.warnings.single.cells, <String>['C5']);
  });

  test('date edge cases', () {
    expect(enc(const XlsxDate(1900, 3, 1)), '<c r="A1" s="1"><v>61</v></c>');
    expect(enc(DateTime(1899, 12, 31)), '<c r="A1" t="s"><v>0</v></c>');
    expect(strings.values.last, DateTime(1899, 12, 31).toIso8601String());
    expect(codes(), <XlsxWarningCode>[XlsxWarningCode.dateOutsideExcelRange]);
    enc(
      DateTime(2026),
      rowStyle: const XlsxStyle(numFmt: XlsxNumFmt.custom('#,##0.00')),
    );
    expect(warnings.warnings.last.code, XlsxWarningCode.dateInNonDateFormat);
  });

  test('a date before 1900 is ISO text with a warning', () {
    expect(enc(const XlsxDate(1850, 5, 7)), '<c r="A1" t="s"><v>0</v></c>');
    expect(strings.values.single, '1850-05-07');
    expect(codes(), <XlsxWarningCode>[XlsxWarningCode.dateOutsideExcelRange]);
  });

  test('a date after 9999 is ISO text with a warning', () {
    expect(enc(DateTime(10000)), '<c r="A1" t="s"><v>0</v></c>');
    expect(strings.values.single, DateTime(10000).toIso8601String());
    expect(codes(), <XlsxWarningCode>[XlsxWarningCode.dateOutsideExcelRange]);
    expect(enc(const XlsxDate(10000, 1, 2)), '<c r="A1" t="s"><v>1</v></c>');
    expect(strings.values.last, '10000-01-02');
  });

  test('XlsxDate years are zero-padded to four digits', () {
    expect(enc(const XlsxDate(999, 1, 2)), '<c r="A1" t="s"><v>0</v></c>');
    expect(strings.values.single, '0999-01-02');
  });

  test('the last and first dates Excel can store are numbers', () {
    expect(
      enc(const XlsxDate(9999, 12, 31)),
      '<c r="A1" s="1"><v>2958465</v></c>',
    );
    expect(enc(const XlsxDate(1900, 1, 1)), '<c r="A1" s="1"><v>1</v></c>');
    expect(warnings.warnings, isEmpty);
  });

  test('a date keeps a date format and uses the cell style over the row', () {
    const XlsxStyle iso = XlsxStyle(numFmt: XlsxNumFmt.custom('yyyy-mm-dd'));
    expect(enc(const XlsxDate(2026, 1, 1), rowStyle: iso), contains('s="1"'));
    expect(styles.idFor(iso), 1);
    expect(warnings.warnings, isEmpty);
  });

  test(
    'an explicit general format counts as a format: kept, with a warning',
    () {
      expect(
        enc(
          DateTime(2026),
          rowStyle: const XlsxStyle(numFmt: XlsxNumFmt.general),
        ),
        contains('<v>46023</v>'),
      );
      expect(
        warnings.warnings.single.code,
        XlsxWarningCode.dateInNonDateFormat,
      );
    },
  );

  test('formulas', () {
    expect(
      enc(const XlsxFormula('=SUM(A2:A9)')),
      '<c r="A1"><f>SUM(A2:A9)</f></c>',
    );
    expect(
      enc(const XlsxFormula('IF(A2<0,"x&y",1)', cached: 'x&y')),
      '<c r="A1" t="str"><f>IF(A2&lt;0,"x&amp;y",1)</f><v>x&amp;y</v></c>',
    );
    expect(
      enc(const XlsxFormula('A2>0', cached: true)),
      '<c r="A1" t="b"><f>A2&gt;0</f><v>1</v></c>',
    );
    expect(
      enc(const XlsxFormula('A2', cached: 2.5)),
      '<c r="A1"><f>A2</f><v>2.5</v></c>',
    );
    expect(encoder.wroteFormula, isTrue);
  });

  test('text that looks like an _xHHHH_ escape keeps its meaning', () {
    expect(enc('_x0041_'), '<c r="A1" t="s"><v>0</v></c>');
    expect(strings.values.single, '_x0041_');
    expect(
      enc(const XlsxFormula('A2', cached: 'a_x00e9_b')),
      '<c r="A1" t="str"><f>A2</f><v>a_x005F_x00e9_b</v></c>',
    );
  });

  test('only one leading equals sign is stripped', () {
    expect(enc(const XlsxFormula('==1')), '<c r="A1"><f>=1</f></c>');
  });

  test('wroteFormula stays false until a formula is written', () {
    enc(1);
    expect(encoder.wroteFormula, isFalse);
  });

  test('a formula cell takes the row style', () {
    expect(
      enc(
        const XlsxFormula('A2'),
        rowStyle: const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0')),
      ),
      '<c r="A1" s="1"><f>A2</f></c>',
    );
  });

  test('XlsxCell style replaces the row style', () {
    const XlsxStyle s1 = XlsxStyle(numFmt: XlsxNumFmt.custom('0.0'));
    const XlsxStyle s2 = XlsxStyle(numFmt: XlsxNumFmt.custom('0.00'));
    expect(
      enc(const XlsxCell(1, style: s1), rowStyle: s2),
      '<c r="A1" s="1"><v>1</v></c>',
    );
    expect(styles.idFor(s1), 1);
    expect(styles.idFor(s2), 2);
  });

  test('an XlsxCell without a style falls back to the row style', () {
    const XlsxStyle s2 = XlsxStyle(numFmt: XlsxNumFmt.custom('0.00'));
    expect(
      enc(const XlsxCell(1), rowStyle: s2),
      '<c r="A1" s="1"><v>1</v></c>',
    );
  });

  test('an XlsxCell holding null writes nothing', () {
    expect(enc(const XlsxCell(null)), '');
  });

  test('programmer errors', () {
    expect(() => XlsxDecimal('1.234,56'), throwsArgumentError);
    expect(() => XlsxDecimal('1e3'), throwsArgumentError);
    expect(() => XlsxDecimal(''), throwsArgumentError);
    expect(() => XlsxDecimal('+1'), throwsArgumentError);
    expect(() => enc(Object()), throwsArgumentError);
    expect(() => enc(const XlsxCell(XlsxCell(1))), throwsArgumentError);
    expect(() => enc(const XlsxDate(2026, 2, 30)), throwsArgumentError);
    expect(
      () => enc(const XlsxFormula('A1', cached: Object())),
      throwsArgumentError,
    );
  });

  test('the error for an unsupported type names the type and the cell', () {
    expect(
      () => enc(Object()),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.toString(),
          'message',
          allOf(contains('Object'), contains('A1')),
        ),
      ),
    );
  });

  test('a formula with characters XML forbids is an ArgumentError', () {
    expect(() => enc(const XlsxFormula('A1\u0001')), throwsArgumentError);
    expect(
      () => enc(const XlsxFormula('A1', cached: 'a\u0001')),
      throwsArgumentError,
    );
  });

  test('an empty formula is an ArgumentError naming the cell and sheet', () {
    final Matcher namesCell = throwsA(
      isA<ArgumentError>().having(
        (ArgumentError e) => e.toString(),
        'message',
        allOf(contains('A1'), contains('"S"'), contains('empty')),
      ),
    );
    expect(() => enc(const XlsxFormula('')), namesCell);
    expect(() => enc(const XlsxFormula('=')), namesCell);
    expect(encoder.wroteFormula, isFalse);
  });

  test('a formula longer than 8,192 characters is an ArgumentError', () {
    final String max = '1+' * 4095 + '11'; // 8,192 code units
    expect(max.length, 8192);
    expect(enc(XlsxFormula(max)), '<c r="A1"><f>$max</f></c>');
    expect(enc(XlsxFormula('=$max')), '<c r="A1"><f>$max</f></c>');
    expect(
      () => enc(XlsxFormula('${max}1')),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.toString(),
          'message',
          allOf(contains('A1'), contains('"S"'), contains('8192')),
        ),
      ),
    );
  });

  test('a cached string past the cell limit is truncated with a warning', () {
    final String out = enc(
      XlsxFormula('A2', cached: '${'x' * 32766}\u{1F600}tail'),
    );
    expect(out, '<c r="A1" t="str"><f>A2</f><v>${'x' * 32766}</v></c>');
    expect(codes(), <XlsxWarningCode>[XlsxWarningCode.textTruncated]);
    expect(warnings.warnings.single.cells, <String>['A1']);
  });

  test('a cached string of exactly 32,767 units is kept', () {
    enc(XlsxFormula('A2', cached: 'z' * 32767));
    expect(warnings.warnings, isEmpty);
  });

  test('a formula with a non-finite cached number is an ArgumentError', () {
    expect(
      () => enc(const XlsxFormula('A1', cached: double.nan)),
      throwsArgumentError,
    );
    expect(
      () => enc(const XlsxFormula('A1', cached: double.infinity)),
      throwsArgumentError,
    );
  });

  test('a failed encode leaves the writer untouched', () {
    final StringBuffer buffer = StringBuffer();
    expect(
      () => encoder.encode(
        XmlWriter(buffer),
        sheet: 'S',
        row: 0,
        column: 0,
        value: double.nan,
      ),
      throwsArgumentError,
    );
    expect(buffer.toString(), '');
  });

  group('a cell that throws records nothing', () {
    const XlsxStyle invalid = XlsxStyle(numFmt: XlsxNumFmt.builtin(200));

    String stylesXml() {
      final StringBuffer buffer = StringBuffer();
      styles.writeStylesXml(XmlWriter(buffer));
      return buffer.toString();
    }

    void expectUntouched() {
      expect(strings.count, 0);
      expect(strings.uniqueCount, 0);
      expect(warnings.warnings, isEmpty);
      expect(stylesXml(), contains('<cellXfs count="1">'));
    }

    test('a string with forbidden characters and an invalid style', () {
      expect(() => enc('a\u0001b', rowStyle: invalid), throwsArgumentError);
      expectUntouched();
    });

    test('a date outside Excel\'s range with an invalid style', () {
      expect(() => enc(DateTime(1850), rowStyle: invalid), throwsArgumentError);
      expectUntouched();
    });

    test('a date in an invalid, non-date format', () {
      expect(
        () => enc(const XlsxDate(2026, 1, 1), rowStyle: invalid),
        throwsArgumentError,
      );
      expectUntouched();
    });

    test('an invalid formula with a valid style registers no style', () {
      expect(
        () => enc(
          const XlsxFormula('A1\u0001'),
          rowStyle: const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0')),
        ),
        throwsArgumentError,
      );
      expectUntouched();
      expect(encoder.wroteFormula, isFalse);
    });
  });

  test('it closes an open row start tag first', () {
    final StringBuffer buffer = StringBuffer();
    final XmlWriter out = XmlWriter(buffer)
      ..start('row')
      ..attribute('r', '1');
    encoder.encode(out, sheet: 'S', row: 0, column: 1, value: 1);
    out.end();
    expect(buffer.toString(), '<row r="1"><c r="B1"><v>1</v></c></row>');
  });
}
