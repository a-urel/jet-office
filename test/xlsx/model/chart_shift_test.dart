// The chart holder of a structural edit (W5, Ruling 10): every `c:f` (and
// chartex `cx:f`) follows the edit through the formula rewriter, and the
// caches stay as read for Excel to refresh.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/formula/formula_rewrite.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';

final RegExp _f = RegExp('<c:f>([^<]*)</c:f>');

List<XlsxWarning> _apply(
  XlsxWorkbook book,
  ReferenceMapper mapper, [
  ReferenceShift? edit,
]) {
  late List<XlsxWarning> warnings;
  changeLogOf(
    book,
  ).transaction(() => warnings = referenceRegistryOf(book).apply(mapper, edit));
  return warnings;
}

Map<String, String> _charts(Map<String, String> parts) => <String, String>{
  for (final MapEntry<String, String> e in parts.entries)
    if (RegExp(r'^xl/charts/chart\d+\.xml$').hasMatch(e.key)) e.key: e.value,
};

/// [reference] (`Data!$A$2:$A$5`) with every row number one higher.
String _rowDown(String reference) => reference.replaceAllMapped(
  RegExp(r'(\$?[A-Z]+\$?)(\d+)'),
  (Match m) => '${m[1]}${int.parse(m[2]!) + 1}',
);

void main() {
  test('every series formula of c1_kinds shifts and caches stay', () {
    final Uint8List bytes = allFixtures()
        .firstWhere((Fixture f) => f.name == 'c1_kinds')
        .build();
    final Map<String, String> before = _charts(readXlsx(bytes));
    expect(before, hasLength(12));
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    final ReferenceShift edit = ReferenceShift.insert(
      'Data',
      ShiftAxis.rows,
      1,
      1,
    );
    expect(_apply(book, edit, edit), isEmpty);
    final Map<String, String> after = _charts(readXlsx(book.save().bytes));
    for (final String name in before.keys) {
      final String was = before[name]!;
      final String now = after[name]!;
      expect(_f.allMatches(was), isNotEmpty, reason: name);
      // Each formula moved one row down; everything else, caches included,
      // is as read.
      expect(
        now,
        was.replaceAllMapped(_f, (Match m) => '<c:f>${_rowDown(m[1]!)}</c:f>'),
        reason: name,
      );
    }
  });

  test("the owner's chart_reference.xlsx: a rename rewrites every c:f", () {
    final Uint8List bytes = File(
      'test/fixtures/owner/charts/chart_reference.xlsx',
    ).readAsBytesSync();
    final Map<String, String> before = _charts(readXlsx(bytes));
    final int count = before.values
        .map((String t) => _f.allMatches(t).length)
        .fold(0, (int a, int b) => a + b);
    expect(count, 138);
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    expect(_apply(book, SheetRename('Veri', 'Yeni Veri')), isEmpty);
    final Map<String, String> after = _charts(readXlsx(book.save().bytes));
    int renamed = 0;
    for (final String name in before.keys) {
      final String now = after[name]!;
      for (final Match m in _f.allMatches(now)) {
        expect(m[1], startsWith("'Yeni Veri'!"), reason: name);
        renamed++;
      }
      expect(
        now,
        before[name]!.replaceAll('<c:f>Veri!', "<c:f>'Yeni Veri'!"),
        reason: name,
      );
    }
    expect(renamed, 138);
  });

  group('parts built by hand', () {
    const String cNs = 'http://schemas.openxmlformats.org/drawingml/2006/chart';
    const String cxNs =
        'http://schemas.microsoft.com/office/drawing/2014/chartex';

    Uint8List withParts(Map<String, String> parts) {
      final Map<String, Uint8List> all = readXlsxBytes(
        buildWorkbook(<String, String>{'S': worksheet('')}),
      );
      parts.forEach((String name, String xml) {
        all[name] = Uint8List.fromList(utf8.encode(xml));
      });
      return buildZip(<String, List<int>>{...all});
    }

    test('a chartex cx:f follows the edit too', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        withParts(<String, String>{
          'xl/charts/chartEx1.xml':
              '<cx:chartSpace xmlns:cx="$cxNs"><cx:chartData><cx:data id="0">'
              '<cx:numDim type="val"><cx:f dir="row">S!\$A\$2:\$A\$5</cx:f>'
              '</cx:numDim></cx:data></cx:chartData></cx:chartSpace>',
        }),
      );
      final ReferenceShift edit = ReferenceShift.delete(
        'S',
        ShiftAxis.rows,
        1,
        1,
      );
      expect(_apply(book, edit, edit), isEmpty);
      expect(
        readXlsx(book.save().bytes)['xl/charts/chartEx1.xml'],
        contains(r'<cx:f dir="row">S!$A$1:$A$4</cx:f>'),
      );
    });

    test('an unreadable chart part warns and is kept', () {
      const String broken = '<c:chartSpace xmlns:c="$cNs"><c:f>S!A1</c:f>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        withParts(<String, String>{'xl/charts/chart1.xml': broken}),
      );
      final ReferenceShift edit = ReferenceShift.insert(
        'S',
        ShiftAxis.rows,
        1,
        1,
      );
      final List<XlsxWarning> warnings = _apply(book, edit, edit);
      expect(warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
        XlsxWarningCode.referenceNotShifted,
      ]);
      expect(warnings.single.detail, startsWith('/xl/charts/chart1.xml: '));
      expect(readXlsx(book.save().bytes)['xl/charts/chart1.xml'], broken);
    });

    test('undo puts the chart part back as read', () {
      const String chart =
          '<c:chartSpace xmlns:c="$cNs"><c:f>S!\$B\$3</c:f></c:chartSpace>';
      final Uint8List bytes = withParts(<String, String>{
        'xl/charts/chart1.xml': chart,
      });
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      final ReferenceShift edit = ReferenceShift.insert(
        'S',
        ShiftAxis.rows,
        1,
        2,
      );
      final set = changeLogOf(
        book,
      ).transaction(() => referenceRegistryOf(book).apply(edit, edit));
      expect(
        readXlsx(book.save().bytes)['xl/charts/chart1.xml'],
        contains(r'S!$B$5'),
      );
      changeLogOf(book).revertSet(set);
      expect(readXlsx(book.save().bytes)['xl/charts/chart1.xml'], chart);
      changeLogOf(book).reapplySet(set);
      expect(
        readXlsx(book.save().bytes)['xl/charts/chart1.xml'],
        contains(r'S!$B$5'),
      );
    });
  });
}
