import 'package:jet_office/jet_office.dart' show XlsxErrorValue;
import 'package:jet_office/src/xlsx/format/format_kind.dart';
import 'package:jet_office/src/xlsx/read/cell_decoder.dart';
import 'package:jet_office/src/xlsx/read/styles_reader.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

DecodedCell _decode({
  String? type,
  String? value,
  String? formula,
  bool hasFormula = false,
  String? inlineText,
  List<String>? shared,
  CellFormat format = CellFormat.general,
  bool date1904 = false,
}) => decodeCell(
  type: type,
  value: value,
  formula: formula,
  hasFormula: hasFormula || formula != null,
  inlineText: inlineText,
  sharedStrings: shared,
  format: format,
  date1904: date1904,
);

const CellFormat _date = CellFormat(164, 'dd.mm.yyyy', FormatKind.date);

const CellFormat _time = CellFormat(165, 'h:mm', FormatKind.time);

const CellFormat _locale = CellFormat(27, null, FormatKind.number);

XmlPullReader _at(String xml) {
  final XmlPullReader r = XmlPullReader(xml);
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) {
      break;
    }
  }
  return r;
}

/// The digits of the decoded number, or the warning when it is not one.
Object? _num(String text, {String? type}) {
  final DecodedCell cell = _decode(type: type, value: text);
  if (cell.warning != null) {
    return cell.warning;
  }
  return (cell.value! as XlsxDecimal).digits;
}

void main() {
  group('numbers', () {
    test('keep the digits the file wrote', () {
      expect(_num('1234.50'), '1234.50');
      expect(_num('42'), '42');
      expect(_num('007'), '007');
      expect(_num('  12.5 '), '12.5');
      expect(_num('-3.25'), '-3.25');
      expect(_num('1', type: 'n'), '1');
    });

    test('drop a leading plus and a trailing point, add a leading zero', () {
      expect(_num('+5'), '5');
      expect(_num('5.'), '5');
      expect(_num('.5'), '0.5');
      expect(_num('+.5'), '0.5');
      expect(_num('-.5'), '-0.5');
    });

    test('negative zero loses its sign and keeps its digits', () {
      expect(_num('-0'), '0');
      expect(_num('-0.0'), '0.0');
      expect(_num('-0.00e5'), '0');
      expect(_num('-0.5'), '-0.5');
    });

    test('expand an exponent, keeping the written significant digits', () {
      expect(_num('1.2E-5'), '0.000012');
      expect(_num('1E+3'), '1000');
      expect(_num('1.50E1'), '15.0');
      expect(_num('12E-1'), '1.2');
      expect(_num('1e0'), '1');
      expect(_num('-2.5e2'), '-250');
      expect(_num('.5e1'), '5');
      expect(_num('0.001E3'), '1');
      expect(_num('100e-2'), '1.00');
    });

    test('canonicalize the integer part only after an exponent', () {
      expect(_num('007E0'), '7');
      expect(_num('0012E1'), '120');
      expect(_num('007'), '007');
    });

    test('an exponent beyond 400 is numberInvalid, never a huge string', () {
      expect(_num('1E999999999'), XlsxWarningCode.numberInvalid);
      expect(_num('1E-999999999'), XlsxWarningCode.numberInvalid);
      expect(_num('1E401'), XlsxWarningCode.numberInvalid);
      expect(_num('1E-401'), XlsxWarningCode.numberInvalid);
      expect(_num('0E0000000000000000000009'), '0');
      expect(_num('1E400'), '1${'0' * 400}');
    });

    test('anything else is numberInvalid', () {
      for (final String text in <String>[
        '',
        ' ',
        'abc',
        '1,5',
        '1e',
        'e5',
        '.',
        '+',
        '--1',
        '1.2.3',
        'NaN',
        'INF',
        '0x10',
        '1 2',
      ]) {
        final DecodedCell cell = _decode(value: text);
        expect(cell.warning, XlsxWarningCode.numberInvalid, reason: text);
        expect(cell.value, isNull, reason: text);
      }
    });

    test('a very long digit run is decided in linear time', () {
      final String digits = '1' * 100000;
      final Stopwatch watch = Stopwatch()..start();
      for (final String tail in <String>['x', '.5x', 'e5x', 'e']) {
        expect(_num('$digits$tail'), XlsxWarningCode.numberInvalid);
      }
      expect(_num(digits), digits);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a missing value is numberInvalid', () {
      expect(_decode().warning, XlsxWarningCode.numberInvalid);
      expect(_decode(type: 'n').warning, XlsxWarningCode.numberInvalid);
    });
  });

  group('shared strings', () {
    test('an index in range gives the string', () {
      final DecodedCell cell = _decode(
        type: 's',
        value: '1',
        shared: <String>['a', 'b'],
      );
      expect(cell.value, 'b');
      expect(cell.warning, isNull);
    });

    test('a bad index is sharedStringInvalid', () {
      for (final String? text in <String?>[
        '3',
        '2',
        '-1',
        'x',
        '1.5',
        '',
        null,
        '99999999999999999999',
      ]) {
        final DecodedCell cell = _decode(
          type: 's',
          value: text,
          shared: <String>['a', 'b'],
        );
        expect(cell.warning, XlsxWarningCode.sharedStringInvalid);
        expect(cell.value, isNull);
      }
    });

    test('no shared strings at all is sharedStringInvalid', () {
      final DecodedCell cell = _decode(type: 's', value: '0');
      expect(cell.warning, XlsxWarningCode.sharedStringInvalid);
      expect(cell.value, isNull);
    });
  });

  group('booleans', () {
    test('0 and 1', () {
      expect(_decode(type: 'b', value: '0').value, false);
      expect(_decode(type: 'b', value: '1').value, true);
    });

    test('anything else is booleanInvalid', () {
      for (final String? text in <String?>['2', 'true', '', null]) {
        final DecodedCell cell = _decode(type: 'b', value: text);
        expect(cell.warning, XlsxWarningCode.booleanInvalid);
        expect(cell.value, isNull);
      }
    });
  });

  group('formula strings', () {
    test('str decodes the text', () {
      expect(_decode(type: 'str', value: 'a_x0042_c').value, 'aBc');
      expect(_decode(type: 'str', value: 'plain').warning, isNull);
    });

    test('str without a value reads as the empty string', () {
      final DecodedCell cell = _decode(type: 'str');
      expect(cell.value, '');
      expect(cell.warning, isNull);
    });
  });

  group('unsupported types', () {
    test('unknown types warn and read null', () {
      for (final String type in <String>['zz', 'N', 'E', 'inlinestr']) {
        final DecodedCell cell = _decode(type: type, value: '1');
        expect(cell.warning, XlsxWarningCode.cellTypeUnsupported);
        expect(cell.value, isNull);
      }
    });
  });

  group('error values', () {
    test('a classic code is its constant', () {
      final DecodedCell cell = _decode(type: 'e', value: '#N/A');
      expect(cell.value, XlsxErrorValue.na);
      expect(cell.warning, isNull);
      expect(_decode(type: 'e', value: ' #DIV/0! ').value, XlsxErrorValue.div0);
    });

    test('an unknown code is kept', () {
      final DecodedCell cell = _decode(type: 'e', value: '#SPILL!');
      expect(cell.value, const XlsxErrorValue('#SPILL!'));
      expect((cell.value! as XlsxErrorValue).isClassic, isFalse);
      expect(cell.warning, isNull);
    });

    test('an empty or missing code is errorValueInvalid', () {
      for (final String? text in <String?>['', '  ', null]) {
        final DecodedCell cell = _decode(type: 'e', value: text);
        expect(cell.value, isNull, reason: '$text');
        expect(cell.warning, XlsxWarningCode.errorValueInvalid);
      }
    });

    test('the code is XML-string decoded', () {
      expect(_decode(type: 'e', value: '_x0023_N/A').value, XlsxErrorValue.na);
    });
  });

  group('inline strings', () {
    test('the inline text is the value', () {
      final DecodedCell cell = _decode(type: 'inlineStr', inlineText: 'a');
      expect(cell.value, 'a');
      expect(cell.warning, isNull);
    });

    test('without inline text the <v> text is read, decoded', () {
      final DecodedCell cell = _decode(type: 'inlineStr', value: 'b');
      expect(cell.value, 'b');
      expect(cell.warning, isNull);
      expect(_decode(type: 'inlineStr', value: 'a_x0042_').value, 'aB');
    });

    test('with neither it is the empty string', () {
      final DecodedCell cell = _decode(type: 'inlineStr');
      expect(cell.value, '');
      expect(cell.warning, isNull);
    });

    test('the inline text wins over <v>', () {
      expect(
        _decode(type: 'inlineStr', inlineText: 'a', value: 'b').value,
        'a',
      );
    });
  });

  group('t="d"', () {
    test('ISO text is a UTC date and time', () {
      final DecodedCell cell = _decode(
        type: 'd',
        value: '2026-10-28T10:00:00Z',
      );
      expect(cell.value, DateTime.utc(2026, 10, 28, 10));
      expect(cell.warning, isNull);
      expect(
        _decode(type: 'd', value: ' 2026-10-28 ').value,
        DateTime.utc(2026, 10, 28),
      );
    });

    test('other text is dateTextInvalid', () {
      for (final String? text in <String?>['x', '', '10:00', null]) {
        final DecodedCell cell = _decode(type: 'd', value: text);
        expect(cell.value, isNull, reason: '$text');
        expect(cell.warning, XlsxWarningCode.dateTextInvalid);
      }
    });
  });

  group('dates by format', () {
    test('a serial in a date format is a DateTime', () {
      final DecodedCell cell = _decode(value: '45000.25', format: _date);
      expect(cell.value, DateTime.utc(2023, 3, 15, 6));
      expect(cell.warning, isNull);
    });

    test('the 1904 system moves the date', () {
      final DecodedCell cell = _decode(
        value: '45000.25',
        format: _date,
        date1904: true,
      );
      expect(cell.value, DateTime.utc(2027, 3, 16, 6));
      expect(cell.warning, isNull);
    });

    test('t="n" maps too', () {
      expect(
        _decode(type: 'n', value: '45000.25', format: _date).value,
        DateTime.utc(2023, 3, 15, 6),
      );
    });

    test('a General number stays a decimal', () {
      expect(_decode(value: '45000.25').value, XlsxDecimal('45000.25'));
    });
  });

  group('durations by format', () {
    test('a serial in a time format is a Duration', () {
      final DecodedCell cell = _decode(value: '0.5', format: _time);
      expect(cell.value, const Duration(hours: 12));
      expect(cell.warning, isNull);
    });

    test('a timestamp in a time-only format is a long Duration', () {
      final DecodedCell cell = _decode(value: '45000.5', format: _time);
      expect(cell.value, const Duration(days: 45000, hours: 12));
      expect(cell.warning, isNull);
    });
  });

  group('range warnings keep the decimal', () {
    test('serial 60 is phantomLeapDay', () {
      final DecodedCell cell = _decode(value: '60', format: _date);
      expect(cell.value, XlsxDecimal('60'));
      expect(cell.warning, XlsxWarningCode.phantomLeapDay);
    });

    test('a negative serial is serialOutOfRange', () {
      final DecodedCell cell = _decode(value: '-1', format: _date);
      expect(cell.value, XlsxDecimal('-1'));
      expect(cell.warning, XlsxWarningCode.serialOutOfRange);
    });

    test('a duration too long is serialOutOfRange', () {
      final DecodedCell cell = _decode(value: '100000', format: _time);
      expect(cell.value, XlsxDecimal('100000'));
      expect(cell.warning, XlsxWarningCode.serialOutOfRange);
    });
  });

  group('locale ids', () {
    test('a number in a format without a code warns and stays a decimal', () {
      final DecodedCell cell = _decode(value: '45000', format: _locale);
      expect(cell.value, XlsxDecimal('45000'));
      expect(cell.warning, XlsxWarningCode.unresolvedNumberFormat);
    });

    test('a string cell in it has no warning', () {
      final DecodedCell cell = _decode(
        type: 's',
        value: '0',
        shared: <String>['a'],
        format: _locale,
      );
      expect(cell.value, 'a');
      expect(cell.warning, isNull);
    });

    test('nor do booleans, errors, dates and formula strings', () {
      for (final (String type, String text) in <(String, String)>[
        ('b', '1'),
        ('e', '#N/A'),
        ('d', '2026-10-28'),
        ('str', 'x'),
        ('inlineStr', 'x'),
      ]) {
        final DecodedCell cell = _decode(
          type: type,
          value: text,
          format: _locale,
        );
        expect(cell.warning, isNull, reason: type);
      }
    });
  });

  group('a broken style', () {
    test('keeps the decimal and warns styleInvalid', () {
      final DecodedCell cell = _decode(
        value: '45000',
        format: CellFormat.broken,
      );
      expect(cell.value, XlsxDecimal('45000'));
      expect(cell.warning, XlsxWarningCode.styleInvalid);
    });

    test('an invalid number wins over it', () {
      final DecodedCell cell = _decode(value: 'x', format: CellFormat.broken);
      expect(cell.value, isNull);
      expect(cell.warning, XlsxWarningCode.numberInvalid);
    });

    test('wins over a missing code and a date mapping', () {
      const CellFormat brokenLocale = CellFormat(
        27,
        null,
        FormatKind.number,
        invalid: true,
      );
      const CellFormat brokenDate = CellFormat(
        14,
        'm/d/yyyy',
        FormatKind.date,
        invalid: true,
      );
      expect(
        _decode(value: '1', format: brokenLocale).warning,
        XlsxWarningCode.styleInvalid,
      );
      final DecodedCell cell = _decode(value: '60', format: brokenDate);
      expect(cell.value, XlsxDecimal('60'));
      expect(cell.warning, XlsxWarningCode.styleInvalid);
    });
  });

  group('formulas', () {
    test('a formula without a value wins over every type', () {
      for (final String? type in <String?>[
        null,
        'n',
        's',
        'b',
        'str',
        'e',
        'd',
        'inlineStr',
        'zz',
      ]) {
        final DecodedCell cell = _decode(
          type: type,
          formula: 'A1+1',
          format: CellFormat.broken,
        );
        expect(cell.value, isNull, reason: '$type');
        expect(cell.warning, XlsxWarningCode.formulaWithoutValue);
        expect(cell.formula, 'A1+1');
      }
    });

    test('inline text counts as the value of a formula', () {
      final DecodedCell cell = _decode(
        type: 'inlineStr',
        formula: '"a"',
        inlineText: 'a',
      );
      expect(cell.value, 'a');
      expect(cell.formula, '"a"');
      expect(cell.warning, isNull);
    });

    test('a formula without text still warns', () {
      final DecodedCell cell = _decode(hasFormula: true);
      expect(cell.warning, XlsxWarningCode.formulaWithoutValue);
      expect(cell.formula, isNull);
    });

    test('a formula with a value keeps both, decoded', () {
      final DecodedCell cell = _decode(value: '2', formula: 'A_x0031_+1');
      expect(cell.value, XlsxDecimal('2'));
      expect(cell.formula, 'A1+1');
      expect(cell.warning, isNull);
    });

    test('no formula leaves formula null', () {
      expect(_decode(value: '2').formula, isNull);
    });
  });

  test('decodeCellType reads the t attribute without a namespace', () {
    expect(decodeCellType(_at('<c r="A1" t="s"/>')), 's');
    expect(decodeCellType(_at('<c r="A1"/>')), isNull);
  });

  test('decodeCellType does not read a prefixed t', () {
    expect(decodeCellType(_at('<c xmlns:x="urn:x" r="A1" x:t="s"/>')), isNull);
  });

  group('decodeFormulaType', () {
    test('reads shared, array and dataTable', () {
      expect(decodeFormulaType(_at('<f t="shared"/>')), FormulaType.shared);
      expect(decodeFormulaType(_at('<f t="array"/>')), FormulaType.array);
      expect(
        decodeFormulaType(_at('<f t="dataTable"/>')),
        FormulaType.dataTable,
      );
    });

    test('absent or unknown is normal', () {
      expect(decodeFormulaType(_at('<f>A1</f>')), FormulaType.normal);
      expect(decodeFormulaType(_at('<f t="normal"/>')), FormulaType.normal);
      expect(decodeFormulaType(_at('<f t="foo"/>')), FormulaType.normal);
      expect(decodeFormulaType(_at('<f t="Shared"/>')), FormulaType.normal);
    });

    test('a prefixed t is not read', () {
      expect(
        decodeFormulaType(_at('<f xmlns:x="urn:x" x:t="shared"/>')),
        FormulaType.normal,
      );
    });
  });
}
