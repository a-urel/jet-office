// A series reference to a workbook name, `[0]!Tutarlar`, as Excel writes a
// series whose values are a defined name: listed, kept as written by a save
// and by the structural edits, and warned about by none of them.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../read/support/zip_builder.dart';

const String _part = 'xl/charts/chart23.xml';

/// The owner's `chart_reference.xlsx`, whose workbook defines `Tutarlar`
/// (`Veri!$B$2:$B$5`), with chart 23's first series reading its values
/// through that name.
Uint8List _withName() {
  final Map<String, Uint8List> parts = readXlsxBytes(
    File('test/fixtures/owner/charts/chart_reference.xlsx').readAsBytesSync(),
  );
  expect(
    utf8.decode(parts['xl/workbook.xml']!),
    contains(r'<definedName name="Tutarlar">Veri!$B$2:$B$5</definedName>'),
  );
  final String chart = utf8.decode(parts[_part]!);
  const String values = r'<c:f>Veri!$B$2:$B$5</c:f>';
  expect(chart, contains(values));
  parts[_part] = Uint8List.fromList(
    utf8.encode(chart.replaceFirst(values, '<c:f>[0]!Tutarlar</c:f>')),
  );
  return buildZip(<String, List<int>>{...parts});
}

void main() {
  late Uint8List bytes;
  setUpAll(() => bytes = _withName());

  test('lists, its view keeps [0]!Tutarlar and it saves unchanged', () {
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    final XlsxSheetChart chart = book.sheet('Veri').charts[22];
    expect(chart.name, 'Grafik 23');
    expect(chart.view!.series[0].values.reference, '[0]!Tutarlar');
    expect(chart.view!.series[1].values.reference, r'Veri!$C$2:$C$5');
    expect(book.warnings, isEmpty);
    expect(
      readXlsxBytes(book.save().bytes)[_part],
      readXlsxBytes(bytes)[_part],
    );
  });

  test('insertRows and renameSheet leave [0]!Tutarlar as written', () {
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    final XlsxSheet sheet = book.sheet('Veri');
    sheet.insertRows(0, 2);
    book.renameSheet(sheet, 'Veri 2026');
    final Chart view = sheet.charts[22].view!;
    expect(view.series[0].values.reference, '[0]!Tutarlar');
    expect(view.series[1].values.reference, r"'Veri 2026'!$C$4:$C$7");
    final String part = readXlsx(book.save().bytes)[_part]!;
    expect(part, contains('<c:f>[0]!Tutarlar</c:f>'));
    expect(part, contains(r"<c:f>'Veri 2026'!$C$4:$C$7</c:f>"));
    expect(book.warnings, isEmpty);
  });
}
