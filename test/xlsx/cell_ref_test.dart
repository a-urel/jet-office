import 'package:jet_office/src/xlsx/cell_ref.dart';
import 'package:test/test.dart';

void main() {
  test('column names', () {
    expect(columnName(0), 'A');
    expect(columnName(25), 'Z');
    expect(columnName(26), 'AA');
    expect(columnName(701), 'ZZ');
    expect(columnName(702), 'AAA');
    expect(columnName(16383), 'XFD');
    expect(() => columnName(16384), throwsRangeError);
    expect(() => columnName(-1), throwsRangeError);
  });
  test('cell references', () {
    expect(cellRef(0, 0), 'A1');
    expect(cellRef(1048575, 16383), 'XFD1048576');
  });
  test('cell reference rejects rows outside the sheet', () {
    expect(() => cellRef(-1, 0), throwsRangeError);
    expect(() => cellRef(1048576, 0), throwsRangeError);
  });
}
