import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart'
    show cellStoreOf, sheetIsWorksheet;
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../fixtures/m4_fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/producers.dart';
import '../read/support/workbook_builder.dart';
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

/// The cells of [sheet] that hold a string, by row and column.
Iterable<(int, int)> _stringCells(XlsxSheet sheet) sync* {
  for (final XlsxReadRow row in sheet.rows) {
    for (final XlsxReadCell cell in row.cells) {
      if (cell.value is String) yield (row.index, cell.column);
    }
  }
}

/// Opens [bytes], loads every sheet, reads its objects and saves.
Uint8List _roundTrip(Uint8List bytes) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  for (final XlsxSheet sheet in book.sheets) {
    sheet.rows.toList();
    for (final (int row, int column) in _stringCells(sheet)) {
      sheet.richTextAt(row, column);
    }
    sheet.notes.toList();
    sheet.pictures.toList();
    sheet.tables.toList();
  }
  return book.save().bytes;
}

/// Sets on [sheet] everything it reads: every cell's style, every row's
/// format, every column, the default sizes, the view, the tab colour, the
/// outline summary, the merges, unmerged and merged back in order, the
/// sheet's features (protection, page setup, headers and footers, auto
/// filter, print area and print titles) and its objects: every rich text,
/// every note, every picture's anchor and every table's style.
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
  sheet.protection = sheet.protection;
  sheet.pageSetup = sheet.pageSetup;
  sheet.headerFooter = sheet.headerFooter;
  sheet.autoFilter = sheet.autoFilter;
  sheet.printArea = sheet.printArea;
  final ({(int, int)? rows, (int, int)? columns}) titles = sheet.printTitles;
  sheet.setPrintTitles(rows: titles.rows, columns: titles.columns);
  for (final (int row, int column) in _stringCells(sheet).toList()) {
    final XlsxRichText? rich = sheet.richTextAt(row, column);
    if (rich != null) sheet.setCell(row, column, rich);
  }
  for (final XlsxCellNote n in sheet.notes) {
    sheet.setNote(n.row, n.column, n.note);
  }
  final List<XlsxPicture> pictures = sheet.pictures;
  for (int i = 0; i < pictures.length; i++) {
    sheet.movePicture(i, pictures[i].anchor);
  }
  for (final XlsxTable table in sheet.tables) {
    sheet.setTableStyle(table.name, table.style);
  }
}

/// The differences between saving [bytes] unchanged and saving it after
/// [_setWhatWasRead] on every sheet and setting the workbook's protection
/// and properties to what it read.
List<String> _resetDifferences(Uint8List bytes) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  for (final XlsxSheet sheet in book.sheets) {
    sheet.rows.toList();
    _setWhatWasRead(sheet);
  }
  book.protection = book.protection;
  book.properties = book.properties;
  return comparePackages(
    _roundTrip(bytes),
    book.save().bytes,
    ignoreBookkeeping: true,
  );
}

/// Removes every validation and conditional format of every sheet of
/// [bytes] and adds each back: [_reads] gives what it gave, and so it does
/// from the saved file.
void _expectRemovedAndAddedBack(Uint8List bytes) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  final List<List<Object>> before = _reads(book);
  for (final XlsxSheet sheet in book.sheets) {
    if (!sheetIsWorksheet(sheet)) continue;
    final List<XlsxDataValidation> validations = sheet.dataValidations.toList();
    validations.forEach(sheet.removeDataValidation);
    expect(sheet.dataValidations, isEmpty);
    validations.forEach(sheet.addDataValidation);
    final List<XlsxConditionalFormat> formats = sheet.conditionalFormats
        .toList();
    formats.forEach(sheet.removeConditionalFormat);
    expect(sheet.conditionalFormats, isEmpty);
    formats.forEach(sheet.addConditionalFormat);
  }
  expect(_reads(book), before);
  expect(_reads(XlsxWorkbook.open(book.save().bytes)), before);
}

/// The validations and the conditional formats of every worksheet of
/// [book], in order.
List<List<Object>> _reads(XlsxWorkbook book) => <List<Object>>[
  for (final XlsxSheet sheet in book.sheets)
    if (sheetIsWorksheet(sheet)) ...<List<Object>>[
      sheet.dataValidations.toList(),
      sheet.conditionalFormats.toList(),
    ],
];

/// Puts one of each object on a free spot of [sheet], far from anything a
/// fixture holds: a rich text, a note, a picture and a table named [table].
void _addOneOfEach(XlsxSheet sheet, String table) {
  sheet
    ..setCell(
      1999,
      30,
      XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('Rich', font: XlsxFont(bold: true)),
        XlsxTextRun(' text'),
      ]),
    )
    ..setNote(1999, 30, XlsxNote.plain('A new note', author: 'Proof'))
    ..addPicture(
      XlsxPicture(
        OfficeImage(jpeg3x5),
        const XlsxOneCellAnchor(XlsxAnchorPoint(1999, 31)),
      ),
    )
    ..addTable(
      XlsxTable(
        table,
        XlsxRange.parse('AK2000:AL2002'),
        const <XlsxTableColumn>[XlsxTableColumn('One'), XlsxTableColumn('Two')],
      ),
    );
}

/// Removes every object of [sheet] that it allows to go: every note but a
/// thread's, every picture, every table no formula uses.
void _removeEveryObject(XlsxSheet sheet) {
  for (final XlsxCellNote n in sheet.notes) {
    if (!n.note.author.startsWith('tc=')) sheet.setNote(n.row, n.column, null);
  }
  for (int i = sheet.pictures.length - 1; i >= 0; i--) {
    sheet.removePicture(i);
  }
  for (final XlsxTable table in sheet.tables) {
    try {
      sheet.removeTable(table.name);
    } on StateError catch (e) {
      expect(e.message, contains('uses it'));
    }
  }
}

/// The differences between saving [bytes] unchanged and saving it after
/// [edit] of every worksheet, all in one change, is undone.
List<String> _undoneDifferences(
  Uint8List bytes,
  void Function(XlsxSheet sheet, int index) edit,
) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  final ChangeLog log = changeLogOf(book);
  final ChangeSet set = log.transaction(() {
    for (int i = 0; i < book.sheets.length; i++) {
      if (sheetIsWorksheet(book.sheets[i])) edit(book.sheets[i], i);
    }
  });
  log.revertSet(set);
  return comparePackages(
    _roundTrip(bytes),
    book.save().bytes,
    ignoreBookkeeping: true,
  );
}

/// The edits of the structural round trip each file refuses (a
/// `StateError`, as Excel refuses them): the edit's label and a fragment of
/// the message, in the order the edits run.
const Map<String, List<(String, String)>> _expectedRefusals =
    <String, List<(String, String)>>{
      // Its notes sit on the last column and the last row on purpose: an
      // insert before them would push them off the sheet.
      'm4_notes': <(String, String)>[
        ('Right insertColumns', 'push the note on cell XFD1'),
        ('Bottom insertRows', 'push the note on cell A1048576'),
      ],
      // Row 1 is the header of a table with body rows; Excel keeps a
      // header while the table has rows, so deleting row 1 is refused.
      'm4_tables': <(String, String)>[
        ('Sales deleteRows', 'header row of the table "Sales"'),
      ],
      'excel_objects': <(String, String)>[
        ('Objects deleteRows', 'header row of the table "Stock"'),
      ],
    };

/// Runs [edit] as a transaction of [book]; the set when it was allowed,
/// `null` when Excel refuses it (a [StateError]: an array formula or a table
/// in the way), which changes nothing.
XlsxChangeSet? _tryEdit(XlsxWorkbook book, void Function() edit) {
  try {
    return book.transaction(edit);
  } on StateError {
    return null;
  }
}

/// The worksheets of [book].
List<XlsxSheet> _worksheets(XlsxWorkbook book) => <XlsxSheet>[
  for (final XlsxSheet s in book.sheets)
    if (sheetIsWorksheet(s)) s,
];

/// The lines of `comparePackages` a structural edit causes on purpose, each
/// a part's child count going from `n` to `n + delta` (`delta` is signed):
/// the content type override and the relationship of the dropped calculation
/// chain (one child fewer) and, in a workbook without `calcPr`, the one it
/// gains for `fullCalcOnLoad` (one child more).
final List<(RegExp, int)> _countLines = <(RegExp, int)>[
  (RegExp(r'^\[Content_Types\]\.xml: /Types: (\d+) children vs (\d+)$'), -1),
  (
    RegExp(
      r'^xl/_rels/workbook\.xml\.rels: /Relationships: '
      r'(\d+) children vs (\d+)$',
    ),
    -1,
  ),
  (RegExp(r'^xl/workbook\.xml: /workbook: (\d+) children vs (\d+)$'), 1),
];

/// Whether [line] of `comparePackages` is one of the five a structural edit
/// causes on purpose: the calculation chain part gone, its content type
/// override and its relationship gone, and `calcPr` gained with
/// `fullCalcOnLoad="1"`. Nothing broader.
bool _isRecalcBookkeeping(String line) {
  if (line == 'xl/calcChain.xml: missing from the actual package' ||
      line ==
          'xl/workbook.xml: /workbook/calcPr: '
              'attribute fullCalcOnLoad missing vs "1"') {
    return true;
  }
  for (final (RegExp pattern, int delta) in _countLines) {
    final RegExpMatch? m = pattern.firstMatch(line);
    if (m != null && int.parse(m.group(2)!) == int.parse(m.group(1)!) + delta) {
      return true;
    }
  }
  return false;
}

/// The parts that differ between [before] and [after], by name.
Set<String> _partsChanged(Uint8List before, Uint8List after) => <String>{
  for (final String line in comparePackages(
    before,
    after,
    ignoreBookkeeping: true,
  ))
    line.substring(0, line.indexOf(':')),
};

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

  group('removing and re-adding keeps the meaning', () {
    for (final Fixture f in allFixtures()) {
      test(f.name, () => _expectRemovedAndAddedBack(f.build()));
    }
    for (final ProducerFile p in producerFiles()) {
      test(p.name, () => _expectRemovedAndAddedBack(p.bytes));
    }
  });

  group('undoing object edits restores the file', () {
    final Map<String, Uint8List Function()> files =
        <String, Uint8List Function()>{
          for (final Fixture f in m4Fixtures()) f.name: f.build,
          'excel_objects': () => excelObjectsFile().bytes,
        };
    files.forEach((String name, Uint8List Function() build) {
      test('$name: one of each added', () {
        expect(
          _undoneDifferences(
            build(),
            (XlsxSheet sheet, int i) => _addOneOfEach(sheet, 'Proof$i'),
          ),
          isEmpty,
        );
      });
      test('$name: every object removed', () {
        expect(
          _undoneDifferences(
            build(),
            (XlsxSheet sheet, int _) => _removeEveryObject(sheet),
          ),
          isEmpty,
        );
      });
    });
    test('the first of each on a sheet without any', () {
      final Uint8List input = allFixtures()
          .firstWhere((Fixture f) => f.name == 'm1_values')
          .build();
      expect(
        _undoneDifferences(
          input,
          (XlsxSheet sheet, int i) => _addOneOfEach(sheet, 'Proof$i'),
        ),
        isEmpty,
      );
    });
  });

  group('structural edits', () {
    final Map<String, Uint8List Function()> files =
        <String, Uint8List Function()>{
          for (final Fixture f in allFixtures()) f.name: f.build,
          for (final ProducerFile p in producerFiles()) p.name: () => p.bytes,
        };
    files.forEach((String name, Uint8List Function() build) {
      test(
        '$name: insert, delete, rename, move, undo all equals the input',
        () {
          final Uint8List input = build();
          final XlsxWorkbook book = XlsxWorkbook.open(input);
          final List<XlsxChangeSet> sets = <XlsxChangeSet>[];
          final List<String> refusals = <String>[];
          void run(String label, void Function() edit) {
            try {
              final XlsxChangeSet set = book.transaction(edit);
              if (!set.isEmpty) sets.add(set);
            } on StateError catch (e) {
              refusals.add('$label: ${e.message}');
            }
          }

          for (final XlsxSheet sheet in _worksheets(book)) {
            final String at = sheet.name;
            run('$at insertRows', () => sheet.insertRows(1, 2));
            run('$at insertColumns', () => sheet.insertColumns(1, 2));
            run('$at deleteRows', () => sheet.deleteRows(0));
            run('$at deleteColumns', () => sheet.deleteColumns(0));
          }
          for (int i = 0; i < book.sheets.length; i++) {
            final XlsxSheet sheet = book.sheets[i];
            run('renameSheet $i', () => book.renameSheet(sheet, 'Renamed$i'));
          }
          if (book.sheets.length > 1) {
            run(
              'moveSheet',
              () => book.moveSheet(book.sheets.first, book.sheets.length - 1),
            );
          }
          final List<(String, String)> expected =
              _expectedRefusals[name] ?? const <(String, String)>[];
          expect(refusals, hasLength(expected.length), reason: '$refusals');
          for (int i = 0; i < expected.length; i++) {
            expect(refusals[i], startsWith('${expected[i].$1}: '));
            expect(refusals[i], contains(expected[i].$2));
          }
          for (final XlsxChangeSet set in sets.reversed) {
            book.undo(set);
          }
          expect(
            comparePackages(
              _roundTrip(input),
              book.save().bytes,
              ignoreBookkeeping: true,
            ),
            isEmpty,
          );
        },
      );

      /// Inserts [count] rows at [at] on every worksheet, deletes them again
      /// and compares with the input but for the recalculation bookkeeping.
      void insertThenDelete(String label, int at, int count) {
        test('$name: $label equals the input but for calcChain and '
            'fullCalcOnLoad', () {
          final Uint8List input = build();
          final XlsxWorkbook book = XlsxWorkbook.open(input);
          for (final XlsxSheet sheet in _worksheets(book)) {
            // A refused insert changes nothing.
            if (_tryEdit(book, () => sheet.insertRows(at, count)) == null) {
              continue;
            }
            book.transaction(() => sheet.deleteRows(at, count));
          }
          final List<String> differences = comparePackages(
            _roundTrip(input),
            book.save().bytes,
            ignoreBookkeeping: true,
          ).where((String line) => !_isRecalcBookkeeping(line)).toList();
          expect(differences, isEmpty);
        });
      }

      // Past every fixture's data: nothing moves. Inside the data region:
      // references move out and back.
      insertThenDelete(
        'insert then delete the same rows past the data',
        1500,
        3,
      );
      insertThenDelete('insert then delete the same rows in the data', 0, 3);
    });
  });

  group('a file with more than the model types', () {
    late Uint8List input;
    late XlsxWorkbook book;
    late XlsxSheet sheet;
    const String sheetPart = 'xl/worksheets/sheet1.xml';
    const String sheetRels = 'xl/worksheets/_rels/sheet1.xml.rels';
    const String vml = 'xl/drawings/vmlDrawing1.vml';

    setUp(() {
      input = excelObjectsFile().bytes;
      book = XlsxWorkbook.open(input);
      sheet = book.sheets.single;
    });

    test('reads what the model types beside what it does not', () {
      expect(sheet.richTextAt(2, 0)!.text, 'Nut M8');
      expect(sheet.pictures.single.description, 'A small picture');
      expect(sheet.notes.map((XlsxCellNote n) => n.note.author), <Object>[
        'Ahmet',
        startsWith('tc='),
      ]);
      expect(sheet.tables.single.name, 'Stock');
      // Excel's own runs in a note are `<color indexed="81"/>`, past the
      // palette the writer accepts: read without the colour, kept as written.
      expect(sheet.notes.first.note.text.runs.first.font?.color, isNull);
      expect(book.warnings, isEmpty);
    });

    test('a note added touches the comments and the box alone', () {
      sheet.setNote(9, 0, XlsxNote.plain('New', author: 'Ahmet'));
      expect(_partsChanged(input, book.save().bytes), <String>{
        'xl/comments1.xml',
        vml,
      });
    });

    test('a visibility-only setNote leaves the comments part as written', () {
      final XlsxNote note = sheet.noteAt(4, 0)!;
      sheet.setNote(
        4,
        0,
        XlsxNote(note.text, author: note.author, visible: true),
      );
      expect(sheet.noteAt(4, 0)!.visible, isTrue);
      expect(_partsChanged(input, book.save().bytes), <String>{vml});
    });

    test('a note of a thread cannot be copied to a cell without one', () {
      final XlsxNote thread = sheet.noteAt(4, 1)!;
      expect(
        () => sheet.setNote(9, 9, thread),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'author',
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      sheet.setNote(4, 1, thread);
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('the plain note removed leaves the thread and the control', () {
      sheet.setNote(4, 0, null);
      final Uint8List saved = book.save().bytes;
      expect(_partsChanged(input, saved), <String>{'xl/comments1.xml', vml});
      final String box = readXlsx(saved)[vml]!;
      expect(box, contains('ObjectType="Checkbox"'));
      expect(box, contains('<x:Column>1</x:Column>'));
      expect(box, isNot(contains('<x:Column>0</x:Column>')));
    });

    test('the thread\'s note cannot be set or removed', () {
      expect(() => sheet.setNote(4, 1, null), throwsStateError);
      expect(() => sheet.setNote(4, 1, XlsxNote.plain('x')), throwsStateError);
    });

    test('a picture added touches the drawing alone', () {
      sheet.addPicture(
        XlsxPicture(
          OfficeImage(png4x2),
          const XlsxOneCellAnchor(XlsxAnchorPoint(20, 0)),
        ),
      );
      expect(_partsChanged(input, book.save().bytes), <String>{
        'xl/drawings/drawing1.xml',
      });
    });

    test('the picture removed leaves the chart and the shape', () {
      sheet.removePicture(0);
      final Uint8List saved = book.save().bytes;
      expect(_partsChanged(input, saved), <String>{
        'xl/drawings/drawing1.xml',
        'xl/drawings/_rels/drawing1.xml.rels',
        'xl/media/image1.png',
      });
      final String drawing = readXlsx(saved)['xl/drawings/drawing1.xml']!;
      expect(drawing, contains('Chart 2'));
      expect(drawing, contains('Rectangle 3'));
      expect(readXlsx(saved), contains('xl/charts/chart1.xml'));
    });

    test('a table added keeps <tableParts> after the controls', () {
      sheet.addTable(
        XlsxTable('More', XlsxRange.parse('E10:F12'), const <XlsxTableColumn>[
          XlsxTableColumn('One'),
          XlsxTableColumn('Two'),
        ]),
      );
      final Uint8List saved = book.save().bytes;
      // The workbook part asks Excel to recalculate, as any cell set does.
      expect(_partsChanged(input, saved), <String>{
        '[Content_Types].xml',
        'xl/workbook.xml',
        sheetPart,
        sheetRels,
        'xl/sharedStrings.xml',
        'xl/tables/table2.xml',
      });
      final String text = readXlsx(saved)[sheetPart]!;
      expect(
        text.indexOf('<tableParts'),
        greaterThan(text.indexOf('</mc:AlternateContent>')),
      );
      expect(readXlsx(saved)['xl/tables/table1.xml'], contains('xr:uid'));
    });

    test('the table its own formulas use is removed, its users ranges', () {
      sheet.removeTable('Stock');
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts.keys, isNot(contains('xl/tables/table1.xml')));
      expect(parts[sheetPart], isNot(contains('Stock[')));
    });

    test('restyling and resizing the table keep its calculated column', () {
      sheet
        ..setTableStyle('Stock', XlsxTableStyle.light(1))
        ..resizeTable('Stock', XlsxRange.parse('A1:C4'));
      final Uint8List saved = book.save().bytes;
      // The resize asks for recalculation: `fullCalcOnLoad` in the workbook.
      expect(_partsChanged(input, saved), <String>{
        'xl/tables/table1.xml',
        'xl/workbook.xml',
      });
      final String table = readXlsx(saved)['xl/tables/table1.xml']!;
      expect(table, contains('<calculatedColumnFormula>'));
      expect(table, contains('dataDxfId="0"'));
      expect(table, contains('xr3:uid'));
    });
  });

  test('outline levels without a sheetFormatPr round-trip', () {
    const String rows =
        '<sheetData><row r="1" outlineLevel="2"><c r="A1"><v>1</v></c></row>'
        '</sheetData>';
    const String cols =
        '<cols><col min="1" max="1" width="9" outlineLevel="2"/></cols>'
        '<sheetData/>';
    String sheet(String body) => '<worksheet xmlns="$mainNs">$body</worksheet>';
    final Map<String, String> sheets = <String, String>{
      'rows': sheet(rows),
      'columns': sheet(cols),
      'rows, attribute missing': sheet(
        '<sheetFormatPr defaultRowHeight="15"/>$rows',
      ),
      'columns, attribute missing': sheet(
        '<sheetFormatPr defaultRowHeight="15"/>$cols',
      ),
      'rows, attribute lower': sheet(
        '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="1"/>$rows',
      ),
      'columns, attribute lower': sheet(
        '<sheetFormatPr defaultRowHeight="15" outlineLevelCol="1"/>$cols',
      ),
    };
    sheets.forEach((String name, String xml) {
      final Uint8List input = buildWorkbook(<String, String>{'S': xml});
      expect(
        comparePackages(input, _roundTrip(input), ignoreBookkeeping: true),
        isEmpty,
        reason: name,
      );
    });
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
