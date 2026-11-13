import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/m4_fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/zip_builder.dart';

/// A workbook of one sheet `S` whose `[Content_Types].xml` declares the
/// part [name] (an override of [type]) that the ZIP lacks.
Uint8List _declaring(String name, String type) {
  final XlsxWorkbook source = XlsxWorkbook();
  source.addSheet('S').setCell(0, 0, 1);
  final Map<String, Uint8List> parts = readXlsxBytes(source.save().bytes);
  expect(parts.containsKey(name.substring(1)), isFalse);
  parts['[Content_Types].xml'] = utf8.encode(
    utf8
        .decode(parts['[Content_Types].xml']!)
        .replaceFirst(
          '</Types>',
          '<Override PartName="$name" ContentType="$type"/></Types>',
        ),
  );
  return buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> e in parts.entries) (e.key, e.value),
  ], store: true);
}

/// Opens [input], applies [edit] to its workbook and returns the part names
/// the saved file has and [input] lacks; then undoes the edit and requires
/// the saved package to equal [input], declarations included, and redoes
/// and undoes it again.
Set<String> _addedThenUndone(
  Uint8List input,
  void Function(XlsxWorkbook book) edit,
) {
  final XlsxWorkbook book = XlsxWorkbook.open(input);
  final ChangeLog log = changeLogOf(book);
  final ChangeSet set = log.transaction(() => edit(book));
  final Uint8List edited = book.save().bytes;
  final Set<String> added = readXlsxBytes(edited).keys.toSet()
    ..removeAll(readXlsxBytes(input).keys);
  log.revertSet(set);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  log.reapplySet(set);
  expect(
    comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  log.revertSet(set);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  return added;
}

const String _ns = 'application/vnd.openxmlformats-officedocument';

XlsxPicture _picture() => XlsxPicture(
  OfficeImage(png4x2),
  const XlsxOneCellAnchor(XlsxAnchorPoint(1, 2), width: 8, height: 4),
);

void main() {
  group('a new part takes no name an override of no part declares', () {
    test('a drawing', () {
      final Uint8List input = _declaring(
        '/xl/drawings/drawing1.xml',
        '$_ns.drawing+xml',
      );
      expect(
        _addedThenUndone(
          input,
          (XlsxWorkbook book) => book.sheets.first.addPicture(_picture()),
        ),
        <String>{
          'xl/drawings/drawing2.xml',
          'xl/drawings/_rels/drawing2.xml.rels',
          'xl/media/image1.png',
          'xl/worksheets/_rels/sheet1.xml.rels',
        },
      );
    });

    test('a media part', () {
      final Uint8List input = _declaring('/xl/media/image1.png', 'image/png');
      expect(
        _addedThenUndone(
          input,
          (XlsxWorkbook book) => book.sheets.first.addPicture(_picture()),
        ),
        <String>{
          'xl/drawings/drawing1.xml',
          'xl/drawings/_rels/drawing1.xml.rels',
          'xl/media/image2.png',
          'xl/worksheets/_rels/sheet1.xml.rels',
        },
      );
    });

    test('a table', () {
      final Uint8List input = _declaring(
        '/xl/tables/table1.xml',
        '$_ns.spreadsheetml.table+xml',
      );
      expect(
        _addedThenUndone(
          input,
          (XlsxWorkbook book) => book.sheets.first.addTable(
            XlsxTable('New', XlsxRange.parse('C1:D3'), const <XlsxTableColumn>[
              XlsxTableColumn('P'),
              XlsxTableColumn('Q'),
            ]),
          ),
        ),
        <String>{'xl/tables/table2.xml', 'xl/worksheets/_rels/sheet1.xml.rels'},
      );
    });

    test('a comments part', () {
      final Uint8List input = _declaring(
        '/xl/comments1.xml',
        '$_ns.spreadsheetml.comments+xml',
      );
      expect(
        _addedThenUndone(
          input,
          (XlsxWorkbook book) =>
              book.sheets.first.setNote(2, 2, XlsxNote.plain('Checked.')),
        ),
        <String>{
          'xl/comments2.xml',
          'xl/drawings/vmlDrawing1.vml',
          'xl/worksheets/_rels/sheet1.xml.rels',
        },
      );
    });

    test('a VML drawing', () {
      final Uint8List input = _declaring(
        '/xl/drawings/vmlDrawing1.vml',
        '$_ns.vmlDrawing',
      );
      expect(
        _addedThenUndone(
          input,
          (XlsxWorkbook book) =>
              book.sheets.first.setNote(2, 2, XlsxNote.plain('Checked.')),
        ),
        <String>{
          'xl/comments1.xml',
          'xl/drawings/vmlDrawing2.vml',
          'xl/worksheets/_rels/sheet1.xml.rels',
        },
      );
    });

    test('a worksheet', () {
      final Uint8List input = _declaring(
        '/xl/worksheets/sheet2.xml',
        '$_ns.spreadsheetml.worksheet+xml',
      );
      expect(
        _addedThenUndone(input, (XlsxWorkbook book) => book.addSheet('T')),
        <String>{'xl/worksheets/sheet3.xml'},
      );
    });
  });
}
