import 'package:jet_office/jet_office.dart' show XlsxErrorValue;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/format/format_kind.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:jet_office/src/xlsx/read/cell_decoder.dart';
import 'package:jet_office/src/xlsx/read/styles_reader.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_escape.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

/// The arguments of one decoder call.
typedef _Case = ({
  String? type,
  String? value,
  String? formula,
  bool hasFormula,
  String? inlineText,
  List<String>? shared,
  CellFormat format,
  bool date1904,
});

_Case _case({
  String? type,
  String? value,
  String? formula,
  bool hasFormula = false,
  String? inlineText,
  List<String>? shared,
  CellFormat format = CellFormat.general,
  bool date1904 = false,
}) => (
  type: type,
  value: value,
  formula: formula,
  hasFormula: hasFormula || formula != null,
  inlineText: inlineText,
  shared: shared,
  format: format,
  date1904: date1904,
);

DecodedCell _decodeCase(_Case c) => decodeCell(
  type: c.type,
  value: c.value,
  formula: c.formula,
  hasFormula: c.hasFormula,
  inlineText: c.inlineText,
  sharedStrings: c.shared,
  format: c.format,
  date1904: c.date1904,
);

/// [c] through the raw step: the [RawCell] the row walk would store, decoded
/// by [decodeRawCell].
DecodedCell _decodeRawCase(_Case c) {
  final RawCellKind kind = decodeRawKind(c.type);
  final RawCell raw = RawCell(
    kind: kind,
    value: c.value,
    typeText: kind == RawCellKind.unknown ? c.type : null,
    formula: c.hasFormula
        ? RawFormula(
            type: FormulaType.normal,
            text: c.formula == null ? null : decodeXstring(c.formula!),
          )
        : null,
    // The reader reads an inline text only for an inline string cell.
    inline: c.inlineText == null ? null : _inline(c.inlineText!),
  );
  return decodeRawCell(
    raw,
    sharedStrings: c.shared,
    format: c.format,
    date1904: c.date1904,
  );
}

/// Decodes one case; each call also checks that the raw step agrees.
DecodedCell _decode({
  String? type,
  String? value,
  String? formula,
  bool hasFormula = false,
  String? inlineText,
  List<String>? shared,
  CellFormat format = CellFormat.general,
  bool date1904 = false,
}) {
  final _Case c = _case(
    type: type,
    value: value,
    formula: formula,
    hasFormula: hasFormula,
    inlineText: inlineText,
    shared: shared,
    format: format,
    date1904: date1904,
  );
  final DecodedCell decoded = _decodeCase(c);
  expect(_same(decoded, _decodeRawCase(c)), isTrue, reason: '$c');
  return decoded;
}

final String _longDigits = '1' * 100000;

const CellFormat _brokenLocale = CellFormat(
  27,
  null,
  FormatKind.number,
  invalid: true,
);

const CellFormat _brokenDate = CellFormat(
  14,
  'm/d/yyyy',
  FormatKind.date,
  invalid: true,
);

/// Every case the tests below decode, for the replay through
/// [decodeRawCell].
final List<_Case> _table = <_Case>[
  _case(value: '1234.50'),
  _case(value: '42'),
  _case(value: '007'),
  _case(value: '  12.5 '),
  _case(value: '-3.25'),
  _case(type: 'n', value: '1'),
  _case(value: '+5'),
  _case(value: '5.'),
  _case(value: '.5'),
  _case(value: '+.5'),
  _case(value: '-.5'),
  _case(value: '-0'),
  _case(value: '-0.0'),
  _case(value: '-0.00e5'),
  _case(value: '-0.5'),
  _case(value: '1.2E-5'),
  _case(value: '1E+3'),
  _case(value: '1.50E1'),
  _case(value: '12E-1'),
  _case(value: '1e0'),
  _case(value: '-2.5e2'),
  _case(value: '.5e1'),
  _case(value: '0.001E3'),
  _case(value: '100e-2'),
  _case(value: '007E0'),
  _case(value: '0012E1'),
  _case(value: '1E999999999'),
  _case(value: '1E-999999999'),
  _case(value: '1E401'),
  _case(value: '1E-401'),
  _case(value: '0E0000000000000000000009'),
  _case(value: '1E400'),
  _case(value: ''),
  _case(value: ' '),
  _case(value: 'abc'),
  _case(value: '1,5'),
  _case(value: '1e'),
  _case(value: 'e5'),
  _case(value: '.'),
  _case(value: '+'),
  _case(value: '--1'),
  _case(value: '1.2.3'),
  _case(value: 'NaN'),
  _case(value: 'INF'),
  _case(value: '0x10'),
  _case(value: '1 2'),
  _case(value: null),
  _case(type: 'n', value: null),
  _case(type: 's', value: '1', shared: <String>['a', 'b']),
  _case(type: 's', value: '3', shared: <String>['a', 'b']),
  _case(type: 's', value: '2', shared: <String>['a', 'b']),
  _case(type: 's', value: '-1', shared: <String>['a', 'b']),
  _case(type: 's', value: 'x', shared: <String>['a', 'b']),
  _case(type: 's', value: '1.5', shared: <String>['a', 'b']),
  _case(type: 's', value: '', shared: <String>['a', 'b']),
  _case(type: 's', value: null, shared: <String>['a', 'b']),
  _case(type: 's', value: '99999999999999999999', shared: <String>['a', 'b']),
  _case(type: 's', value: '0'),
  _case(type: 'b', value: '0'),
  _case(type: 'b', value: '1'),
  _case(type: 'b', value: '2'),
  _case(type: 'b', value: 'true'),
  _case(type: 'b', value: ''),
  _case(type: 'b', value: null),
  _case(type: 'str', value: 'a_x0042_c'),
  _case(type: 'str', value: 'plain'),
  _case(type: 'str', value: null),
  _case(type: 'str', value: '#NULL!', formula: 'NA()', hasFormula: true),
  _case(type: 'str', value: '#DIV/0!', formula: 'NA()', hasFormula: true),
  _case(type: 'str', value: '#VALUE!', formula: 'NA()', hasFormula: true),
  _case(type: 'str', value: '#REF!', formula: 'NA()', hasFormula: true),
  _case(type: 'str', value: '#NAME?', formula: 'NA()', hasFormula: true),
  _case(type: 'str', value: '#NUM!', formula: 'NA()', hasFormula: true),
  _case(type: 'str', value: '#N/A', formula: 'NA()', hasFormula: true),
  _case(type: 'str', value: '#N/A'),
  _case(type: 'str', value: '#n/a', formula: 'A1', hasFormula: true),
  _case(type: 'str', value: ' #N/A', formula: 'A1', hasFormula: true),
  _case(type: 'str', value: '#ERROR!', formula: 'A1', hasFormula: true),
  _case(type: 'zz', value: '1'),
  _case(type: 'N', value: '1'),
  _case(type: 'E', value: '1'),
  _case(type: 'inlinestr', value: '1'),
  _case(type: 'e', value: '#N/A'),
  _case(type: 'e', value: ' #DIV/0! '),
  _case(type: 'e', value: '#SPILL!'),
  _case(type: 'e', value: ''),
  _case(type: 'e', value: '  '),
  _case(type: 'e', value: null),
  _case(type: 'e', value: '_x0023_N/A'),
  _case(type: 'inlineStr', value: null, inlineText: 'a'),
  _case(type: 'inlineStr', value: 'b'),
  _case(type: 'inlineStr', value: 'a_x0042_'),
  _case(type: 'inlineStr', value: null),
  _case(type: 'inlineStr', value: 'b', inlineText: 'a'),
  _case(type: 'd', value: '2026-10-28T10:00:00Z'),
  _case(type: 'd', value: ' 2026-10-28 '),
  _case(type: 'd', value: 'x'),
  _case(type: 'd', value: ''),
  _case(type: 'd', value: '10:00'),
  _case(type: 'd', value: null),
  _case(value: '45000.25', format: _date),
  _case(value: '45000.25', format: _date, date1904: true),
  _case(type: 'n', value: '45000.25', format: _date),
  _case(value: '45000.25'),
  _case(value: '0.5', format: _time),
  _case(value: '45000.5', format: _time),
  _case(value: '60', format: _date),
  _case(value: '-1', format: _date),
  _case(value: '100000', format: _time),
  _case(value: '45000', format: _locale),
  _case(type: 's', value: '0', shared: <String>['a'], format: _locale),
  _case(type: 'b', value: '1', format: _locale),
  _case(type: 'e', value: '#N/A', format: _locale),
  _case(type: 'd', value: '2026-10-28', format: _locale),
  _case(type: 'str', value: 'x', format: _locale),
  _case(type: 'inlineStr', value: 'x', format: _locale),
  _case(value: '45000', format: CellFormat.broken),
  _case(value: 'x', format: CellFormat.broken),
  _case(value: '1', format: _brokenLocale),
  _case(value: '60', format: _brokenDate),
  _case(
    type: null,
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'n',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 's',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'b',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'str',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'e',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'd',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'inlineStr',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'zz',
    value: null,
    formula: 'A1+1',
    hasFormula: true,
    format: CellFormat.broken,
  ),
  _case(
    type: 'inlineStr',
    value: null,
    formula: '"a"',
    hasFormula: true,
    inlineText: 'a',
  ),
  _case(value: null, hasFormula: true),
  _case(value: '2', formula: 'A_x0031_+1', hasFormula: true),
  _case(value: '2'),
  _case(value: '${_longDigits}x'),
  _case(value: '$_longDigits.5x'),
  _case(value: '${_longDigits}e5x'),
  _case(value: '${_longDigits}e'),
  _case(value: _longDigits),
];

/// An `<is>` element holding [text] in one `<t>`, captured as opaque XML.
OpaqueXml _inline(String text) {
  final XmlPullReader r = _at(
    '<is xmlns="$_main"><t xml:space="preserve">${escapeXmlText(text)}</t></is>',
  );
  return OpaqueXml.capture(r);
}

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// Whether [a] and [b] decoded alike.
bool _same(DecodedCell a, DecodedCell b) =>
    a.value == b.value && a.formula == b.formula && a.warning == b.warning;

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

    test('a formula str whose text is a classic error code is that error', () {
      // Google Sheets writes =NA() as t="str" with <v>#N/A</v>; Excel
      // writes t="e". Both show an error.
      for (final XlsxErrorValue error in XlsxErrorValue.classic) {
        final DecodedCell cell = _decode(
          type: 'str',
          value: error.code,
          formula: 'NA()',
        );
        expect(cell.value, error);
        expect(cell.formula, 'NA()');
        expect(cell.warning, isNull);
      }
    });

    test('a str error code without a formula, or not exact, stays text', () {
      expect(_decode(type: 'str', value: '#N/A').value, '#N/A');
      expect(_decode(type: 'str', value: '#n/a', formula: 'A1').value, '#n/a');
      expect(
        _decode(type: 'str', value: ' #N/A', formula: 'A1').value,
        ' #N/A',
      );
      expect(
        _decode(type: 'str', value: '#ERROR!', formula: 'A1').value,
        '#ERROR!',
      );
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

  group('raw kinds', () {
    const Map<String?, RawCellKind> kinds = <String?, RawCellKind>{
      null: RawCellKind.number,
      'n': RawCellKind.number,
      's': RawCellKind.sharedString,
      'b': RawCellKind.boolean,
      'e': RawCellKind.error,
      'str': RawCellKind.string,
      'inlineStr': RawCellKind.inlineString,
      'd': RawCellKind.isoDate,
      'x': RawCellKind.unknown,
      '': RawCellKind.unknown,
      'S': RawCellKind.unknown,
    };

    test('decodeRawKind maps every t', () {
      kinds.forEach((String? type, RawCellKind kind) {
        expect(decodeRawKind(type), kind, reason: '$type');
      });
    });

    test('encodeRawKind is its inverse', () {
      for (final String? type in <String?>[
        null,
        's',
        'b',
        'e',
        'str',
        'inlineStr',
        'd',
      ]) {
        expect(
          encodeRawKind(RawCell(kind: decodeRawKind(type))),
          type,
          reason: '$type',
        );
      }
      expect(encodeRawKind(RawCell(kind: decodeRawKind('n'))), isNull);
      expect(
        encodeRawKind(const RawCell(kind: RawCellKind.unknown, typeText: 'x')),
        'x',
      );
      expect(
        encodeRawKind(const RawCell(kind: RawCellKind.unknown, typeText: '')),
        '',
      );
    });
  });

  group('raw cells', () {
    test('isEmpty means no value, formula or inline', () {
      expect(const RawCell(kind: RawCellKind.number, style: 3).isEmpty, isTrue);
      expect(
        const RawCell(kind: RawCellKind.number, value: '').isEmpty,
        isFalse,
      );
      expect(
        const RawCell(
          kind: RawCellKind.number,
          formula: RawFormula(type: FormulaType.normal),
        ).isEmpty,
        isFalse,
      );
      expect(
        RawCell(kind: RawCellKind.inlineString, inline: _inline('a')).isEmpty,
        isFalse,
      );
    });

    test('decodeRawCell reads the inline text from the <is>', () {
      final DecodedCell cell = decodeRawCell(
        RawCell(kind: RawCellKind.inlineString, inline: _inline('a & b')),
        sharedStrings: null,
        format: CellFormat.general,
        date1904: false,
      );
      expect(cell.value, 'a & b');
    });

    test('decodeRawCell does not decode a formula text twice', () {
      final DecodedCell cell = decodeRawCell(
        const RawCell(
          kind: RawCellKind.number,
          value: '1',
          formula: RawFormula(type: FormulaType.normal, text: '_x0041_'),
        ),
        sharedStrings: null,
        format: CellFormat.general,
        date1904: false,
      );
      expect(cell.formula, '_x0041_');
    });

    test('an unknown kind without its t text is unsupported', () {
      final DecodedCell cell = decodeRawCell(
        const RawCell(kind: RawCellKind.unknown, value: '1'),
        sharedStrings: null,
        format: CellFormat.general,
        date1904: false,
      );
      expect(cell.warning, XlsxWarningCode.cellTypeUnsupported);
    });
  });

  test('decodeRawCell equals decodeCell for every case of the existing '
      'table', () {
    final List<String> differ = <String>[
      for (final _Case c in _table)
        if (!_same(_decodeCase(c), _decodeRawCase(c))) '$c',
    ];
    expect(_table, hasLength(greaterThan(100)));
    expect(differ, isEmpty);
  });
}
