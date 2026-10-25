import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/sheet_writer.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

/// Gives [sheet] every trailer setting and a row with two links.
void _fill(XlsxSheetWriter sheet) {
  sheet
    ..columns(<XlsxColumn?>[const XlsxColumn(width: 12)])
    ..row(<Object?>[
      XlsxHyperlink.url('https://example.com/a'),
      XlsxHyperlink.sheet('S1', text: 'Top'),
      'x',
    ])
    ..merge(XlsxRange.parse('D1:E1'))
    ..autoFilter(XlsxRange.parse('A1:C1'))
    ..defineName(const XlsxDefinedName('Local', '1'))
    ..printArea(<XlsxRange>[XlsxRange.parse('A1:C1')])
    ..printTitles(rows: (0, 0))
    ..dataValidation(
      XlsxDataValidation.list(
        <XlsxRange>[XlsxRange.parse('C2')],
        <String>['a'],
      ),
    )
    ..conditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('C1')],
        <XlsxConditionalRule>[
          const XlsxExpressionRule(
            'TRUE',
            style: XlsxStyle(font: XlsxFont(bold: true)),
          ),
        ],
      ),
    )
    ..pageSetup(const XlsxPageSetup(scale: 50))
    ..headerFooter(const XlsxHeaderFooter(oddHeader: 'H'))
    ..protect(const XlsxSheetProtection());
}

void main() {
  group('a finished sheet', () {
    test('drops what its trailer was rendered from and keeps what close() '
        'needs', () {
      final XlsxWriter book = XlsxWriter();
      final WorksheetWriter s1 = book.addSheet('S1') as WorksheetWriter;
      _fill(s1);
      expect(s1.holdsTrailerData, isTrue);

      book.addSheet('S2');

      expect(s1.holdsTrailerData, isFalse);
      expect(s1.name, 'S1');
      expect(s1.number, 1);
      expect(s1.visibility, XlsxSheetVisibility.visible);
      expect(s1.rowCount, 1);
      expect(s1.autoFilterRange, XlsxRange.parse('A1:C1'));
      expect(s1.sheetNames.printArea, <XlsxRange>[XlsxRange.parse('A1:C1')]);
      expect(s1.sheetNames.printTitleRows, (0, 0));
      expect(s1.sheetNames.defined, <XlsxDefinedName>[
        const XlsxDefinedName('Local', '1'),
      ]);

      final XlsxResult out = book.close();
      expect(checkXlsx(out.bytes), isEmpty);
      final Map<String, String> parts = readXlsx(out.bytes);
      final String sheet1 = parts['xl/worksheets/sheet1.xml']!;
      for (final String element in <String>[
        '<hyperlinks>',
        '<mergeCells',
        '<dataValidations',
        '<conditionalFormatting',
        '<pageSetup',
        '<headerFooter>',
        '<sheetProtection',
      ]) {
        expect(sheet1, contains(element));
      }
      final String workbook = parts['xl/workbook.xml']!;
      expect(workbook, contains('_xlnm._FilterDatabase'));
      expect(workbook, contains('_xlnm.Print_Area'));
      expect(workbook, contains('_xlnm.Print_Titles'));
      expect(workbook, contains('name="Local" localSheetId="0"'));
    });

    test('is written the same as a sheet finished by close()', () {
      Map<String, String> build({required bool finishEarly}) {
        final XlsxWriter book = XlsxWriter();
        _fill(book.addSheet('S1'));
        if (finishEarly) book.addSheet('S2');
        return readXlsx(book.close().bytes);
      }

      expect(
        build(finishEarly: true)['xl/worksheets/sheet1.xml'],
        build(finishEarly: false)['xl/worksheets/sheet1.xml'],
      );
    });
  });
}
