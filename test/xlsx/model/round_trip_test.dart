import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart'
    show cellStoreOf, sheetIsWorksheet;
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/producers.dart';
import '../read/support/zip_builder.dart';

/// Repairs the model makes on load, applied to the expected package: the
/// producer file repeats a cell on purpose, and the later one wins with
/// `cellDuplicated` (as in the reader), so the saved part has only the
/// later one.
const Map<String, (String, String, String)> _repaired =
    <String, (String, String, String)>{
      'erp_export': (
        'worksheets/data.xml',
        '<c r="A3" t="str"><v>FT-2026-0002</v></c>',
        '',
      ),
    };

/// [bytes] with the repair of [name], if it has one.
Uint8List _expected(String name, Uint8List bytes) {
  final (String, String, String)? repair = _repaired[name];
  if (repair == null) return bytes;
  final Map<String, Uint8List> parts = readXlsxBytes(bytes);
  final String text = utf8.decode(parts[repair.$1]!);
  expect(text, contains(repair.$2));
  return buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> p in parts.entries)
      (
        p.key,
        p.key == repair.$1
            ? utf8.encode(text.replaceFirst(repair.$2, repair.$3))
            : p.value,
      ),
  ]);
}

/// Opens [bytes], loads every sheet and saves.
Uint8List _roundTrip(Uint8List bytes) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  for (final XlsxSheet sheet in book.sheets) {
    sheet.rows.toList();
  }
  return book.save().bytes;
}

/// Sets on [sheet] everything it reads: every cell's style, every row's
/// format, every column, the default sizes, the view, the tab colour, the
/// outline summary and the merges, unmerged and merged back in order.
///
/// The cells and rows are the store's, so a styled empty cell and a row of
/// attributes alone are set too. A cell the file lacks is left out: `styleAt`
/// gives it its row's or column's style, and `setStyle` would create it.
void _setWhatWasRead(XlsxSheet sheet) {
  if (!sheetIsWorksheet(sheet)) return;
  final CellStore store = cellStoreOf(sheet)!;
  final List<int> rows = store.rowIndexes.toList();
  final List<(int, int)> cells = <(int, int)>[];
  int lastColumn = 0;
  for (final int row in rows) {
    store.forEachInRow(row, (int column, RawCell _) {
      cells.add((row, column));
      if (column > lastColumn) lastColumn = column;
    });
  }
  for (final (int row, int column) in cells) {
    sheet.setStyle(row, column, sheet.styleAt(row, column));
  }
  for (final int row in rows) {
    sheet.setRowFormat(row, sheet.rowFormat(row));
  }
  for (int i = 0; i <= lastColumn; i++) {
    sheet.setColumn(i, sheet.column(i));
  }
  final ({double? rowHeight, double? columnWidth}) sizes = sheet.defaultSizes;
  sheet.setDefaultSizes(
    rowHeight: sizes.rowHeight,
    columnWidth: sizes.columnWidth,
  );
  sheet.view = sheet.view;
  sheet.tabColor = sheet.tabColor;
  final ({bool below, bool right}) outline = sheet.outlineSummary;
  sheet.setOutlineSummary(below: outline.below, right: outline.right);
  final List<XlsxRange> merges = sheet.merges.toList();
  merges.forEach(sheet.unmerge);
  merges.forEach(sheet.merge);
}

/// The differences between saving [bytes] unchanged and saving it after
/// [_setWhatWasRead] on every sheet.
List<String> _resetDifferences(Uint8List bytes) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  for (final XlsxSheet sheet in book.sheets) {
    sheet.rows.toList();
    _setWhatWasRead(sheet);
  }
  return comparePackages(
    _roundTrip(bytes),
    book.save().bytes,
    ignoreBookkeeping: true,
  );
}

void main() {
  // Owner files (test/fixtures/owner/manifest.json) join this test when
  // the owner supplies XLSX workbooks; today the manifest lists none.
  group('every writer fixture round-trips', () {
    for (final Fixture f in allFixtures()) {
      test(f.name, () {
        final Uint8List input = f.build();
        // dimension and spans are recomputed on save (spec 4.4).
        expect(
          comparePackages(input, _roundTrip(input), ignoreBookkeeping: true),
          isEmpty,
        );
      });
    }
  });

  group('every producer file round-trips', () {
    for (final ProducerFile p in producerFiles()) {
      test(p.name, () {
        expect(
          comparePackages(
            _expected(p.name, p.bytes),
            _roundTrip(p.bytes),
            ignoreBookkeeping: true,
          ),
          isEmpty,
        );
      });
    }
  });

  group('re-setting what was read changes nothing', () {
    for (final Fixture f in allFixtures()) {
      test(f.name, () => expect(_resetDifferences(f.build()), isEmpty));
    }
    for (final ProducerFile p in producerFiles()) {
      test(p.name, () => expect(_resetDifferences(p.bytes), isEmpty));
    }
  });

  test('an unloaded workbook round-trips too', () {
    for (final Fixture f in allFixtures()) {
      final Uint8List input = f.build();
      expect(
        comparePackages(input, XlsxWorkbook.open(input).save().bytes),
        isEmpty,
        reason: f.name,
      );
    }
  });
}
