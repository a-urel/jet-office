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
    expect(formatXmlDouble(big), '1e+21');
    expect(formatXmlDouble(1e20), '100000000000000000000');
    expect(formatXmlDouble(123456789012345680000.0), '123456789012345680000');
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

  test('describeDouble prints like formatXmlDouble and never throws', () {
    expect(describeDouble(12.0), '12');
    expect(describeDouble(0.5), '0.5');
    expect(describeDouble(double.nan), 'NaN');
    expect(describeDouble(double.infinity), 'Infinity');
    expect(describeDouble(double.negativeInfinity), '-Infinity');
  });
}
