import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/model/table_part.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import 'support/workbook_support.dart';

/// A workbook with the table `Sales` over A1:C3 (header `Region`, `Amount`,
/// `Note`) on its first sheet, as the writer makes it.
Uint8List _salesBook({bool headerRow = true}) {
  final XlsxWriter writer = XlsxWriter();
  final XlsxSheetWriter sheet = writer.addSheet('S');
  sheet.table(
    XlsxTable('Sales', XlsxRange.parse('A1:C3'), const <XlsxTableColumn>[
      XlsxTableColumn('Region'),
      XlsxTableColumn('Amount'),
      XlsxTableColumn('Note'),
    ], headerRow: headerRow),
  );
  if (headerRow) sheet.row(<Object?>[null, null, null]);
  sheet.row(<Object?>['North', 120, 'a']);
  sheet.row(<Object?>['South', 80, 'b']);
  return writer.close().bytes;
}

String _table(Uint8List bytes) => partText(bytes, 'xl/tables/table1.xml');

List<String> _columnNames(String tableXml) => <String>[
  for (final RegExpMatch m in RegExp(
    r'<tableColumn [^>]*name="([^"]*)"',
  ).allMatches(tableXml))
    m[1]!,
];

TablePart _part(String xml) => TablePart.read(XmlPullReader(xml))!;

void main() {
  group('TablePart', () {
    const String excelTable =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/'
        'main" xmlns:xr3="http://schemas.microsoft.com/office/spreadsheetml/'
        '2016/revision3" id="1" name="Tablo1" displayName="Tablo1" '
        'ref="B2:D4"><autoFilter ref="B2:D4"/><tableColumns count="3">'
        '<tableColumn id="1" xr3:uid="{A}" name="&#220;r&amp;n"/>'
        "<tableColumn id='2' name='Adet' dataDxfId='2'/>"
        '<tableColumn id="3" name="_x005F_x0041_">'
        '<calculatedColumnFormula>Tablo1[[#This Row],[Adet]]*2'
        '</calculatedColumnFormula></tableColumn></tableColumns>'
        '<tableStyleInfo name="TableStyleMedium2" showRowStripes="1"/>'
        '</table>';

    test('reads the range, the header and the decoded column names', () {
      final TablePart part = _part(excelTable);
      expect(part.displayName, 'Tablo1');
      expect(part.range, XlsxRange.parse('B2:D4'));
      expect(part.hasHeader, isTrue);
      expect(part.columnCount, 3);
      expect(
        <String>[for (int i = 0; i < 3; i++) part.columnName(i)],
        <String>['Ür&n', 'Adet', '_x0041_'],
      );
    });

    test('writes its source unchanged until a name changes', () {
      expect(utf8.decode(_bytes(_part(excelTable))), excelTable);
    });

    test('a renamed column changes only that name, escaped', () {
      final TablePart part = _part(excelTable);
      part.setColumnName(1, 'a "b" & <c> _x0042_\nd');
      final String written = _text(part);
      expect(
        written,
        excelTable.replaceFirst(
          "name='Adet'",
          'name="a &quot;b&quot; &amp; &lt;c&gt; _x005F_x0042_&#10;d"',
        ),
      );
      expect(_part(written).columnName(1), 'a "b" & <c> _x0042_\nd');
    });

    test('headerRowCount="0" has no header', () {
      final TablePart part = _part(
        excelTable.replaceFirst(
          'ref="B2:D4">',
          'ref="B2:D4" headerRowCount="0">',
        ),
      );
      expect(part.hasHeader, isFalse);
    });

    test('a part it cannot type is null', () {
      expect(TablePart.read(XmlPullReader('<other/>')), isNull);
      expect(
        TablePart.read(
          XmlPullReader(excelTable.replaceFirst('B2:D4"', 'B2:C4"')),
        ),
        isNull,
        reason: 'two columns in the range, three listed',
      );
      expect(
        TablePart.read(
          XmlPullReader(excelTable.replaceFirst('ref="B2:D4">', 'ref="nope">')),
        ),
        isNull,
      );
    });
  });

  group('setting a table header cell', () {
    test('renames the column, as Excel requires', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_salesBook());
      book.sheets.single.setCell(0, 1, 'Tutar');
      final Uint8List output = book.save().bytes;
      expect(_columnNames(_table(output)), <String>['Region', 'Tutar', 'Note']);
      expect(XlsxReader(output).rowsAt(0).first.cells[1].value, 'Tutar');
      final XlsxWarning warning = book.warnings.single;
      expect(warning.code, XlsxWarningCode.tableColumnRenamed);
      expect(warning.cells, <String>['B1']);
    });

    test('the same text renames nothing and warns nothing', () {
      final Uint8List input = _salesBook();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single.setCell(0, 0, 'Region');
      expect(_table(book.save().bytes), _table(input));
      expect(book.warnings, isEmpty);
    });

    test('a cell below the header leaves the table part unloaded', () {
      final Uint8List input = _salesBook();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single
        ..setCell(1, 0, 'East')
        ..setCell(0, 3, 'beside');
      final OpcPackage package = packageOf(book);
      expect(package.isLoaded('/xl/tables/table1.xml'), isFalse);
      expect(_table(book.save().bytes), _table(input));
    });

    test('a name another column has, ignoring case, gets a number', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_salesBook());
      book.sheets.single.setCell(0, 2, 'amount');
      final Uint8List output = book.save().bytes;
      expect(_columnNames(_table(output)), <String>[
        'Region',
        'Amount',
        'amount2',
      ]);
      expect(XlsxReader(output).rowsAt(0).first.cells[2].value, 'amount2');
      expect(
        book.warnings.map((XlsxWarning w) => w.code).toSet(),
        <XlsxWarningCode>{
          XlsxWarningCode.tableColumnRenamed,
          XlsxWarningCode.tableHeaderAdjusted,
        },
      );
    });

    test('clearing or emptying a header cell names the column ColumnN', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_salesBook());
      book.sheets.single
        ..setCell(0, 0, null)
        ..setCell(0, 2, '');
      final Uint8List output = book.save().bytes;
      expect(_columnNames(_table(output)), <String>[
        'Column1',
        'Amount',
        'Column3',
      ]);
      final List<XlsxReadCell> header = XlsxReader(
        output,
      ).rowsAt(0).first.cells;
      expect(header[0].value, 'Column1');
      expect(header[2].value, 'Column3');
    });

    test('a value other than text throws and changes nothing', () {
      final Uint8List input = _salesBook();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      for (final Object value in <Object>[
        5,
        true,
        DateTime.utc(2026),
        const XlsxFormula('1+1'),
      ]) {
        expect(() => sheet.setCell(0, 1, value), throwsStateError);
      }
      expect(() => sheet.setCell(0, 1, 'x' * 256), throwsArgumentError);
      expect(sheet.cellAt(0, 1)?.value, 'Amount');
      expect(book.warnings, isEmpty);
      expect(_table(book.save().bytes), _table(input));
    });

    test('undo and redo restore the name with the cell', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_salesBook());
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => book.sheets.single.setCell(0, 1, 'Tutar'),
      );
      log.revertSet(set);
      expect(_columnNames(_table(book.save().bytes)), <String>[
        'Region',
        'Amount',
        'Note',
      ]);
      expect(book.sheets.single.cellAt(0, 1)?.value, 'Amount');
      log.reapplySet(set);
      expect(_columnNames(_table(book.save().bytes)), <String>[
        'Region',
        'Tutar',
        'Note',
      ]);
    });

    test('a table without a header row has no header cell', () {
      final Uint8List input = _salesBook(headerRow: false);
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single.setCell(0, 1, 7);
      expect(_table(book.save().bytes), _table(input));
      expect(book.warnings, isEmpty);
    });
  });
}

Uint8List _bytes(TablePart part) {
  final BytesBuilder builder = BytesBuilder(copy: false);
  part.encode().forEach(builder.add);
  return builder.takeBytes();
}

String _text(TablePart part) => utf8.decode(_bytes(part));
