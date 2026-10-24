import 'package:jet_office/src/xlsx/limits.dart';
import 'package:test/test.dart';

void main() {
  test('limit error text', () {
    expect(
      XlsxLimitError('rows', 1048576).toString(),
      "XlsxLimitError: rows exceeds Excel's maximum of 1048576.",
    );
  });
  test('limits match Microsoft\'s published figures', () {
    expect(XlsxLimits.maxRows, 1048576);
    expect(XlsxLimits.maxColumns, 16384);
    expect(XlsxLimits.maxCellTextLength, 32767);
    expect(XlsxLimits.maxSheetNameLength, 31);
    expect(XlsxLimits.maxCellFormats, 65490);
    expect(XlsxLimits.maxHyperlinksPerSheet, 65530);
  });
}
