import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

void main() {
  group('FormatDecimal', () {
    test('keeps the digits as written', () {
      expect(FormatDecimal('1234.50').digits, '1234.50');
      expect(FormatDecimal('-0.10').digits, '-0.10');
      expect(FormatDecimal('007').digits, '007');
    });

    test('toDouble rounds to the nearest double', () {
      expect(FormatDecimal('1234.50').toDouble(), 1234.5);
      expect(FormatDecimal('-3').toDouble(), -3.0);
      expect(FormatDecimal('0.30000000000000004').toDouble(), 0.1 + 0.2);
    });

    test('throws an ArgumentError for digits it does not accept', () {
      for (final String bad in <String>['', '1,5', '1e3', '+1', '.5']) {
        expect(
          () => FormatDecimal(bad),
          throwsA(
            isA<ArgumentError>()
                .having((ArgumentError e) => e.name, 'name', 'digits')
                .having(
                  (ArgumentError e) => e.message,
                  'message',
                  'Expected an optional minus sign, digits and an optional '
                      '".digits" fraction, such as "-1234.50".',
                ),
          ),
          reason: 'for "$bad"',
        );
      }
    });

    test('is equal by its digits', () {
      expect(FormatDecimal('1.5'), FormatDecimal('1.5'));
      expect(FormatDecimal('1.5').hashCode, FormatDecimal('1.5').hashCode);
      expect(FormatDecimal('1.5'), isNot(FormatDecimal('1.50')));
      expect(FormatDecimal('1.5') == Object(), isFalse);
    });

    test('toString names the type and the digits', () {
      expect(FormatDecimal('-1.5').toString(), 'FormatDecimal(-1.5)');
    });
  });

  group('FormatErrorValue', () {
    test('keeps the code as written', () {
      expect(const FormatErrorValue('#N/A').code, '#N/A');
      expect(const FormatErrorValue('#SPILL!').code, '#SPILL!');
    });

    test('is equal by its code', () {
      expect(const FormatErrorValue('#N/A'), const FormatErrorValue('#N/A'));
      expect(
        const FormatErrorValue('#N/A').hashCode,
        const FormatErrorValue('#N/A').hashCode,
      );
      expect(
        const FormatErrorValue('#N/A'),
        isNot(const FormatErrorValue('#REF!')),
      );
      expect(const FormatErrorValue('#N/A') == Object(), isFalse);
    });

    test('toString names the type and the code', () {
      expect(
        const FormatErrorValue('#N/A').toString(),
        'FormatErrorValue(#N/A)',
      );
    });
  });
}
