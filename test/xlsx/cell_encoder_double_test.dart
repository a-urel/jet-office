// No @TestOn: this file runs on the VM and in Chrome, and both must give the
// same text. On the web every whole `double` is also an `int`, so the cell
// encoder cannot tell `5.0` from `5` and writes both as `5` (one spelling on every platform).
import 'package:jet_office/src/xlsx/cell_encoder.dart';
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  late CellEncoder encoder;

  setUp(() {
    encoder = CellEncoder(
      strings: SharedStrings(),
      styles: StyleRegistry(),
      warnings: WarningCollector(),
    );
  });

  String enc(Object? value) {
    final StringBuffer buffer = StringBuffer();
    encoder.encode(
      XmlWriter(buffer),
      sheet: 'S',
      row: 0,
      column: 0,
      value: value,
    );
    return buffer.toString();
  }

  // The shortest round-trip digits; a whole value has no `.0`; a value of
  // 1e21 or more, or below 1e-6, uses `e+NN` / `e-NN` with no padding.
  final List<(double, String)> spellings = <(double, String)>[
    (5.0, '5'),
    (-0.0, '0'),
    (0.0, '0'),
    (0.1, '0.1'),
    (1.5, '1.5'),
    (1e21, '1e+21'),
    (1.5e21, '1.5e+21'),
    (1e-7, '1e-7'),
    (123456789012345680000.0, '123456789012345680000'),
    (9007199254740992.0, '9007199254740992'),
    (1e20, '100000000000000000000'),
    (1e300, '1e+300'),
    (5e-324, '5e-324'),
    (-2.5e-10, '-2.5e-10'),
    (-7.0, '-7'),
    (0.30000000000000004, '0.30000000000000004'),
    (1 / 3, '0.3333333333333333'),
    (2 / 3, '0.6666666666666666'),
    (1e-5, '0.00001'),
    (123.456, '123.456'),
    (0.1 + 0.2, '0.30000000000000004'),
  ];

  for (final (double value, String text) in spellings) {
    test('the double $text is written <v>$text</v>', () {
      expect(enc(value), '<c r="A1"><v>$text</v></c>');
    });

    test('a cached double $text is written <v>$text</v>', () {
      expect(
        enc(XlsxFormula('A2', cached: value)),
        '<c r="A1"><f>A2</f><v>$text</v></c>',
      );
    });
  }
}
