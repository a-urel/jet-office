import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/table_part.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

const String _head =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:xr="http://schemas.microsoft.com/office/spreadsheetml/2014/'
    'revision" xr:uid="{T}"';

TablePart _read(String xml) => TablePart.read(XmlPullReader(xml))!;

String _text(TablePart part) =>
    utf8.decode(<int>[for (final Uint8List b in part.encode()) ...b]);

void main() {
  group('TablePart typed fields', () {
    const String full =
        '$_head id="7" name="Sales" displayName="Sales" ref="A1:C5" '
        'totalsRowCount="1"><autoFilter ref="A1:C4"><sortState ref="A2:C4">'
        '<sortCondition ref="A2:A4"/></sortState></autoFilter>'
        '<tableColumns count="3">'
        '<tableColumn id="1" name="Region" totalsRowLabel="Total"/>'
        '<tableColumn id="2" name="Amount" totalsRowFunction="sum"/>'
        '<tableColumn id="3" name="Spread" totalsRowFunction="var"/>'
        '</tableColumns>'
        '<tableStyleInfo name="TableStyleLight9" showFirstColumn="1" '
        'showLastColumn="0" showRowStripes="1" showColumnStripes="1"/>'
        '</table>';

    test('reads the id, totals, filter, sort state and style', () {
      final TablePart part = _read(full);
      expect(part.id, 7);
      expect(part.hasSortState, isTrue);
      expect(part.problems, isEmpty);
      expect(
        part.value,
        XlsxTable(
          'Sales',
          XlsxRange.parse('A1:C5'),
          const <XlsxTableColumn>[
            XlsxTableColumn('Region', totalsLabel: 'Total'),
            XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
            XlsxTableColumn(
              'Spread',
              totalsFunction: XlsxTotalsFunction.variance,
            ),
          ],
          totalsRow: true,
          style: const XlsxTableStyle(
            'TableStyleLight9',
            showFirstColumn: true,
            showColumnStripes: true,
          ),
        ),
      );
    });

    test('a table without a header, style or filter reads so', () {
      final TablePart part = _read(
        '$_head id="1" name="N" displayName="N" ref="A1:B2" '
        'headerRowCount="0" totalsRowShown="0"><tableColumns count="2">'
        '<tableColumn id="1" name="X"/><tableColumn id="2" name="Y"/>'
        '</tableColumns></table>',
      );
      expect(part.hasSortState, isFalse);
      final XlsxTable table = part.value;
      expect(table.headerRow, isFalse);
      expect(table.totalsRow, isFalse);
      expect(table.autoFilter, isFalse);
      expect(table.style, isNull);
    });

    test('a calculated column and xr:uid stay in the source', () {
      const String xml =
          '$_head id="1" name="T" displayName="T" ref="A1:B3">'
          '<autoFilter ref="A1:B3"/><tableColumns count="2">'
          '<tableColumn id="1" name="A" dataDxfId="3"/>'
          '<tableColumn id="2" xr:uid="{C}" name="B">'
          '<calculatedColumnFormula>T[[#This Row],[A]]*2'
          '</calculatedColumnFormula><totalsRowFormula>SUM(1,2)'
          '</totalsRowFormula></tableColumn></tableColumns></table>';
      final TablePart part = _read(xml);
      expect(
        part.value.columns[1],
        const XlsxTableColumn('B', totalsFormula: 'SUM(1,2)'),
      );
      expect(_text(part), xml);
      part.setColumnName(0, 'Z');
      expect(
        _text(part),
        xml.replaceFirst('name="A"', 'name="Z"'),
        reason: 'only the name changes; uid, dxf and formula stay',
      );
      expect(part.value.columns[0].name, 'Z');
    });

    test('a bad function warns and reads none', () {
      final TablePart part = _read(
        full.replaceFirst('totalsRowFunction="sum"', 'totalsRowFunction="x"'),
      );
      expect(part.problems, <String>['table']);
      expect(part.value.columns[1].totalsFunction, XlsxTotalsFunction.none);
    });

    test('xstring names decode', () {
      final TablePart part = _read(
        '$_head id="1" name="_x0041_b" displayName="_x0041_b" ref="A1:A2">'
        '<tableColumns count="1"><tableColumn id="1" name="a_x0020_b" '
        'totalsRowLabel="_x0054_ot"/></tableColumns></table>',
      );
      expect(part.displayName, 'Ab');
      expect(part.value.name, 'Ab');
      expect(part.value.columns.single.name, 'a b');
      expect(part.value.columns.single.totalsLabel, 'Tot');
    });
  });
}
