// The literal 9007199254740993 does not compile for the web: JavaScript
// numbers cannot represent it, so these tests live in their own VM-only file.
@TestOn('vm')
library;

import 'package:jet_office/src/xlsx/cell_encoder.dart';
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  late WarningCollector warnings;
  late CellEncoder encoder;

  setUp(() {
    warnings = WarningCollector();
    encoder = CellEncoder(
      strings: SharedStrings(),
      styles: StyleRegistry(),
      warnings: warnings,
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

  test('int beyond 2^53 warns', () {
    expect(enc(9007199254740993), '<c r="A1"><v>9007199254740993</v></c>');
    expect(warnings.warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
      XlsxWarningCode.intPrecisionLost,
    ]);
  });

  test('a cached int beyond 2^53 warns like a plain int', () {
    expect(
      enc(const XlsxFormula('A2', cached: 9007199254740993)),
      '<c r="A1"><f>A2</f><v>9007199254740993</v></c>',
    );
    expect(enc(const XlsxFormula('A2', cached: 9007199254740992)), isNotEmpty);
    expect(warnings.warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
      XlsxWarningCode.intPrecisionLost,
    ]);
  });

  test('the int64 minimum warns (its abs() overflows)', () {
    expect(
      enc(-9223372036854775808),
      '<c r="A1"><v>-9223372036854775808</v></c>',
    );
    expect(warnings.warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
      XlsxWarningCode.intPrecisionLost,
    ]);
  });

  test('int at 2^53 does not warn', () {
    enc(9007199254740992);
    enc(-9007199254740992);
    expect(warnings.warnings, isEmpty);
  });
}
