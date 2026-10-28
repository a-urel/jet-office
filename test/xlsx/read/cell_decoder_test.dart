import 'package:jet_office/src/xlsx/read/cell_decoder.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

DecodedCell _decode({
  String? type,
  String? value,
  String? formula,
  bool hasFormula = false,
  List<String>? shared,
}) => decodeCell(
  type: type,
  value: value,
  formula: formula,
  hasFormula: hasFormula || formula != null,
  sharedStrings: shared,
);

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
    test('inlineStr, e, d and unknown types warn and read null', () {
      for (final String type in <String>['inlineStr', 'e', 'd', 'zz', 'N']) {
        final DecodedCell cell = _decode(type: type, value: '1');
        expect(cell.warning, XlsxWarningCode.cellTypeUnsupported);
        expect(cell.value, isNull);
      }
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
        'zz',
      ]) {
        final DecodedCell cell = _decode(type: type, formula: 'A1+1');
        expect(cell.value, isNull, reason: '$type');
        expect(cell.warning, XlsxWarningCode.formulaWithoutValue);
        expect(cell.formula, 'A1+1');
      }
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
    XmlPullReader at(String xml) {
      final XmlPullReader r = XmlPullReader(xml);
      while (r.next()) {
        if (r.eventType == XmlEventType.startElement) {
          break;
        }
      }
      return r;
    }

    expect(decodeCellType(at('<c r="A1" t="s"/>')), 's');
    expect(decodeCellType(at('<c r="A1"/>')), isNull);
  });
}
