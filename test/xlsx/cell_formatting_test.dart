import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/warnings.dart' show WarningCollector;
import 'package:test/test.dart';

final NumberFormatter formatter = NumberFormatter();
final NumberFormatter de = NumberFormatter(locale: FormatLocale.deDE);

/// The warning of [code] as the writer and the reader build it.
XlsxWarning sampleWarning(XlsxWarningCode code) =>
    (WarningCollector()..add(code, sheet: 'S', cell: 'A1')).warnings.single;

void main() {
  group('formatCell', () {
    test('on a reader date cell shows the locale\'s date', () {
      final XlsxReadCell cell = XlsxReadCell(
        0,
        DateTime.utc(2026, 10, 28),
        numberFormatId: 14,
        numberFormat: 'mm-dd-yy',
        isDate: true,
      );
      expect(formatter.formatCell(cell).text, '10/28/26');
      expect(de.formatCell(cell).text, '28.10.26');
    });

    test('formats the cell\'s value with its format', () {
      final XlsxReadCell cell = XlsxReadCell(
        2,
        XlsxDecimal('1234.5'),
        numberFormatId: 4,
        numberFormat: '#,##0.00',
      );
      expect(
        formatter.formatCell(cell, generalWidth: 8),
        formatter.format(
          cell.value,
          numberFormatId: 4,
          numberFormat: '#,##0.00',
          generalWidth: 8,
        ),
      );
      expect(formatter.formatCell(cell).text, '1,234.50');
    });

    test('shows an error cell as the error', () {
      const XlsxReadCell cell = XlsxReadCell(0, XlsxErrorValue.div0);
      expect(formatter.formatCell(cell).text, '#DIV/0!');
    });

    test('a generalWidth below 1 throws ArgumentError', () {
      const XlsxReadCell cell = XlsxReadCell(0, 1);
      expect(
        () => formatter.formatCell(cell, generalWidth: 0),
        throwsArgumentError,
      );
    });
  });

  group('the reader\'s values go to the engine unconverted', () {
    test('an XlsxDecimal rounds half away from zero in its digits', () {
      expect(
        formatter.format(XlsxDecimal('2.675'), numberFormat: '0.00').text,
        '2.68',
      );
      expect(
        formatter.format(XlsxDecimal('1.5'), numberFormat: '0.00').text,
        '1.50',
      );
    });

    test('an XlsxErrorValue shows as the locale\'s error name', () {
      expect(formatter.format(XlsxErrorValue.div0).text, '#DIV/0!');
      expect(
        formatter.format(XlsxErrorValue.na, numberFormat: '0.00').text,
        '#N/A',
      );
      expect(formatter.format(const XlsxErrorValue('#SPILL!')).text, '#SPILL!');
    });
  });

  group('XlsxDecimal is a FormatDecimal', () {
    test('equals one of the same digits both ways, with the same hash', () {
      final XlsxDecimal x = XlsxDecimal('1');
      final FormatDecimal f = FormatDecimal('1');
      expect(x == f, isTrue);
      expect(f == x, isTrue);
      expect(x.hashCode, f.hashCode);
      expect(x == FormatDecimal('2'), isFalse);
    });

    test('throws the same ArgumentError for bad digits', () {
      for (final String bad in <String>['', '1,5', '+1', '1e3', '.5', '1.']) {
        expect(() => XlsxDecimal(bad), throwsArgumentError, reason: bad);
        expect(() => FormatDecimal(bad), throwsArgumentError, reason: bad);
      }
    });

    test('keeps toIntOrNull, toDouble and its own toString', () {
      expect(XlsxDecimal('12.000').toIntOrNull(), 12);
      expect(XlsxDecimal('12.5').toIntOrNull(), isNull);
      expect(XlsxDecimal('0.1').toDouble(), 0.1);
      expect(XlsxDecimal('1').toString(), 'XlsxDecimal(1)');
    });
  });

  group('XlsxErrorValue is a FormatErrorValue', () {
    test('equals one of the same code both ways, with the same hash', () {
      const XlsxErrorValue x = XlsxErrorValue('#N/A');
      const FormatErrorValue f = FormatErrorValue('#N/A');
      expect(x == f, isTrue);
      expect(f == x, isTrue);
      expect(x.hashCode, f.hashCode);
      expect(XlsxErrorValue.na == const FormatErrorValue('#REF!'), isFalse);
    });

    test('keeps its constants, isClassic and toString', () {
      expect(XlsxErrorValue.classic, hasLength(7));
      expect(XlsxErrorValue.div0.isClassic, isTrue);
      expect(const XlsxErrorValue('#SPILL!').isClassic, isFalse);
      expect(XlsxErrorValue.na.toString(), 'XlsxErrorValue(#N/A)');
    });
  });

  group('FormatColor.xlsxColor', () {
    test('a named colour is an XlsxColor.rgb', () {
      expect(
        formatter.format(1, numberFormat: '[Red]0').color!.xlsxColor,
        const XlsxColor.rgb(0xFF0000),
      );
      expect(
        formatter.format(1, numberFormat: '[Blue]0').color!.xlsxColor,
        const XlsxColor.rgb(0x0000FF),
      );
    });

    test('a palette entry is an XlsxColor.indexed', () {
      expect(
        formatter.format(1, numberFormat: '[Color56]0').color!.xlsxColor,
        const XlsxColor.indexed(63),
      );
      expect(
        formatter.format(1, numberFormat: '[Color12]0').color!.xlsxColor,
        const XlsxColor.indexed(19),
      );
    });
  });

  group('FormatWarning.xlsxCode', () {
    const Map<FormatWarning, XlsxWarningCode> expected =
        <FormatWarning, XlsxWarningCode>{
          FormatWarning.invalidCode: XlsxWarningCode.numberFormatInvalid,
          FormatWarning.unsupported: XlsxWarningCode.numberFormatUnsupported,
          FormatWarning.localeDependent:
              XlsxWarningCode.numberFormatLocaleDependent,
          FormatWarning.unresolved: XlsxWarningCode.unresolvedNumberFormat,
        };

    test('names every FormatWarning', () {
      expect(expected.keys.toSet(), FormatWarning.values.toSet());
    });

    for (final MapEntry<FormatWarning, XlsxWarningCode> e in expected.entries) {
      test('${e.key.name} is ${e.value.name}', () {
        expect(e.key.xlsxCode, e.value);
      });
    }

    test('each has a message in every locale', () {
      for (final FormatWarning warning in FormatWarning.values) {
        final XlsxWarning w = sampleWarning(warning.xlsxCode);
        for (final OfficeLocale locale in OfficeLocale.values) {
          expect(
            w.message(locale),
            isNotEmpty,
            reason: '${warning.name}/${locale.name}',
          );
        }
      }
    });

    test('a result\'s warning maps to the code the engine used to give', () {
      expect(
        formatter.format(1, numberFormat: '0;0;0;0;0').warning!.xlsxCode,
        XlsxWarningCode.numberFormatInvalid,
      );
      expect(
        formatter.format(1, numberFormat: '[DBNum1]0').warning!.xlsxCode,
        XlsxWarningCode.numberFormatUnsupported,
      );
      expect(
        formatter.format(1, numberFormatId: 30).warning!.xlsxCode,
        XlsxWarningCode.numberFormatLocaleDependent,
      );
      expect(
        formatter.format(1, numberFormatId: 200).warning!.xlsxCode,
        XlsxWarningCode.unresolvedNumberFormat,
      );
    });
  });
}
