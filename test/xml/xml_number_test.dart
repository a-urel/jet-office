import 'package:jet_office/src/xml/xml_number.dart';
import 'package:test/test.dart';

void main() {
  test('whole values have no fraction', () {
    expect(formatXmlDouble(12.0), '12');
    expect(formatXmlDouble(-3.0), '-3');
    expect(formatXmlDouble(-0.0), '0');
    expect(formatXmlDouble(0.0), '0');
  });

  test('whole values up to 2^53 print as integers on every platform', () {
    expect(formatXmlDouble(255.0), '255');
    expect(formatXmlDouble(9007199254740992.0), '9007199254740992');
    expect(formatXmlDouble(-9007199254740992.0), '-9007199254740992');
  });

  test('whole values beyond 2^53 use the shortest round-trip text', () {
    const double big = 1e21;
    expect(double.parse(formatXmlDouble(big)), big);
  });

  test('fractions round-trip', () {
    expect(formatXmlDouble(10.5), '10.5');
    expect(formatXmlDouble(0.1), '0.1');
    expect(formatXmlDouble(9.140625), '9.140625');
    expect(double.parse(formatXmlDouble(1e-7)), 1e-7);
  });

  test('non-finite throws', () {
    expect(() => formatXmlDouble(double.nan), throwsArgumentError);
    expect(() => formatXmlDouble(double.infinity), throwsArgumentError);
    expect(() => formatXmlDouble(double.negativeInfinity), throwsArgumentError);
  });
}
