import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';

void main() {
  test('the 65,531st link throws before its cell is written', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet('S');
    for (int i = 0; i < XlsxLimits.maxHyperlinksPerSheet; i++) {
      sheet.row(<Object?>[XlsxHyperlink.location('A1')]);
    }
    expect(sheet.rowCount, 65530);
    expect(
      () => sheet.row(<Object?>['kept?', XlsxHyperlink.location('A1')]),
      throwsA(
        isA<XlsxLimitError>()
            .having((XlsxLimitError e) => e.limit, 'limit', 'hyperlinks')
            .having((XlsxLimitError e) => e.max, 'max', 65530),
      ),
    );
    // The row counts; the cell before the failing one stays.
    expect(sheet.rowCount, 65531);
    final String xml = readXlsx(
      book.close().bytes,
    )['xl/worksheets/sheet1.xml']!;
    expect(
      RegExp('<hyperlink ').allMatches(xml).length,
      XlsxLimits.maxHyperlinksPerSheet,
    );
    expect(xml, contains('<c r="A65531" t="s">'));
    expect(xml, isNot(contains('r="B65531"')));
  });
}
