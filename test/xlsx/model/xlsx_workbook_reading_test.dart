import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

void main() {
  test('cellAt and rows show what the reader shows', () {
    final Uint8List input = buildWorkbook(
      <String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" s="1">'
          '<v>46328</v></c><c r="C1" t="b"><v>1</v></c></row>'
          '<row r="3" hidden="1"/>'
          '<row r="4"><c r="A4" t="e"><v>#N/A</v></c><c r="B4" s="1"/>'
          '</row>',
        ),
      },
      sharedStrings: '<sst xmlns="$mainNs"><si><t>a</t></si></sst>',
      styles: stylesPart('<xf numFmtId="0"/><xf numFmtId="14"/>'),
    );
    final XlsxSheet sheet = XlsxWorkbook.open(input).sheets.single;
    final List<XlsxReadRow> expected = XlsxReader(input).rowsAt(0).toList();
    expect(sheet.rows.toList(), expected);
    expect(sheet.cellAt(0, 1), expected[0].cells[1]);
    expect(sheet.cellAt(3, 1), isNull);
  });

  test('reading the rows again reports nothing twice', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><f>1+1</f></c><c r="B1" t="s"><v>7</v></c>'
          '</row>',
        ),
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    List<(XlsxWarningCode, int)> seen() => <(XlsxWarningCode, int)>[
      for (final XlsxWarning w in book.warnings) (w.code, w.count),
    ];
    sheet.rows.toList();
    final List<(XlsxWarningCode, int)> first = seen();
    expect(first, hasLength(2));
    sheet.rows.toList();
    sheet.cellAt(0, 0);
    expect(seen(), first);
    // A new value is read afresh.
    sheet
      ..setCell(0, 0, const XlsxFormula('2+2'))
      ..rows.toList();
    expect(
      seen().firstWhere(
        ((XlsxWarningCode, int) w) =>
            w.$1 == XlsxWarningCode.formulaWithoutValue,
      ),
      (XlsxWarningCode.formulaWithoutValue, 2),
    );
  });

  test('cellAt reports a reading problem once, shared with rows', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet('<row r="1"><c r="A1" t="s"><v>7</v></c></row>'),
      }, sharedStrings: '<sst xmlns="$mainNs"><si><t>a</t></si></sst>'),
    );
    final XlsxSheet sheet = book.sheets.single;
    List<(XlsxWarningCode, int)> seen() => <(XlsxWarningCode, int)>[
      for (final XlsxWarning w in book.warnings) (w.code, w.count),
    ];
    const List<(XlsxWarningCode, int)> once = <(XlsxWarningCode, int)>[
      (XlsxWarningCode.sharedStringInvalid, 1),
    ];
    expect(sheet.cellAt(0, 0)?.value, isNull);
    expect(seen(), once);
    sheet.cellAt(0, 0);
    sheet.rows.toList();
    expect(seen(), once);
  });
}
