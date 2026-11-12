// Tests tool/edit_model.dart: the model edits every workbook of a directory
// and writes a generated one, for the Open XML SDK to validate. It reads and
// writes files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/edit_model.dart';
import '../../tool/write_fixtures.dart' as write_fixtures;
import '../fixtures/m4_fixtures.dart' show png4x2;

/// How far below the input's last row the new row is: the last row moves
/// two rows down, and the probe takes the row after it.
const int _newRowOffset = 4;

void main() {
  late Directory temp;
  late Directory input;
  late Directory output;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('edit_model_test');
    input = Directory('${temp.path}/in')..createSync();
    output = Directory('${temp.path}/out');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// Writes every fixture to [dir], then deletes all but the `.xlsx` files
  /// named in [keep].
  void writeOnly(Directory dir, Set<String> keep) {
    write_fixtures.main(<String>[dir.path]);
    for (final FileSystemEntity e in dir.listSync()) {
      if (!keep.contains(e.uri.pathSegments.last)) e.deleteSync();
    }
  }

  List<String> names(Directory dir) => <String>[
    for (final FileSystemEntity e in dir.listSync()) e.uri.pathSegments.last,
  ];

  test('edits two fixtures and writes the generated workbook: exit 0', () {
    writeOnly(input, <String>{'m1_values.xlsx', 'm1_sheets.xlsx'});
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    final int code = editModel(
      <String>[input.path, output.path],
      out: out,
      err: err,
    );
    expect(code, 0, reason: '$out$err');
    expect(err.toString(), isEmpty);
    expect(
      names(output),
      unorderedEquals(<String>[
        'm1_values.xlsx',
        'm1_sheets.xlsx',
        'w1_generated.xlsx',
        'w2_generated.xlsx',
        'w3_generated.xlsx',
        'w4_generated.xlsx',
        'w5_generated.xlsx',
      ]),
    );
    expect(out.toString(), contains('All 2 workbooks edited'));
  });

  test('an edited workbook holds the edits and one more sheet', () {
    writeOnly(input, <String>{'m1_values.xlsx'});
    final Uint8List before = File(
      '${input.path}/m1_values.xlsx',
    ).readAsBytesSync();
    expect(
      editModel(
        <String>[input.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      0,
    );
    final XlsxReader original = XlsxReader(before);
    final XlsxReader edited = XlsxReader(
      File('${output.path}/m1_values.xlsx').readAsBytesSync(),
    );
    expect(edited.sheets, hasLength(original.sheets.length + 1));
    expect(edited.sheets.first.name, 'Model edit');
    expect(edited.sheets.last.name, 'Model edit 2');
    final int lastRow = original.rowsAt(0).last.index;
    final XlsxReadRow row = edited
        .rowsAt(0)
        .firstWhere((XlsxReadRow r) => r.index == lastRow + _newRowOffset);
    final List<Object?> values = <Object?>[
      for (final XlsxReadCell c in row.cells) c.value,
    ];
    expect(values, hasLength(5));
    expect(values[0], isA<DateTime>());
    expect(values[1], isA<DateTime>());
    expect(row.cells[2].formula, 'SUM(1,2)');
    expect(values[3], 'edited by the model');
    expect(values[4], 'Rich text');
    expect(
      edited.rowsAt(edited.sheets.length - 1).single.cells.single.value,
      'added sheet',
    );
  });

  test('an edited workbook holds the style and layout edits', () {
    writeOnly(input, <String>{'m1_values.xlsx', 'm2_columns_rows.xlsx'});
    final Map<String, int> lastRows = <String, int>{
      for (final String name in <String>[
        'm1_values.xlsx',
        'm2_columns_rows.xlsx',
      ])
        name: XlsxReader(
          File('${input.path}/$name').readAsBytesSync(),
        ).rowsAt(0).last.index,
    };
    expect(
      editModel(
        <String>[input.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      0,
    );
    for (final MapEntry<String, int> file in lastRows.entries) {
      final Uint8List bytes = File(
        '${output.path}/${file.key}',
      ).readAsBytesSync();
      final int row = file.value + _newRowOffset;
      final XlsxSheet sheet = XlsxWorkbook.open(bytes).sheets.first;
      for (int column = 0; column < 4; column++) {
        final XlsxStyle? style = sheet.styleAt(row, column);
        expect(style?.font?.bold, isTrue, reason: file.key);
        expect(
          style?.fill,
          const XlsxFill.solid(XlsxColor.rgb(0xFF0000)),
          reason: file.key,
        );
      }
      expect(sheet.column(1)?.width, 30, reason: file.key);
      expect(sheet.rowFormat(row).height, 24, reason: file.key);
      final XlsxRange merged = XlsxRange(row, 4, row, 5);
      expect(sheet.merges, contains(merged), reason: file.key);
      expect(sheet.view.pane, const XlsxPane.frozen(rows: 1), reason: file.key);
      expect(sheet.tabColor, isNotNull, reason: file.key);

      final XlsxReader reader = XlsxReader(bytes);
      expect(reader.mergesAt(0), contains(merged), reason: file.key);
      final XlsxReadRow read = reader
          .rowsAt(0)
          .firstWhere((XlsxReadRow r) => r.index == row);
      // The dates keep their number format under the new style.
      expect(read.cells[0].isDate, isTrue, reason: file.key);
      expect(read.cells[1].isDate, isTrue, reason: file.key);
      expect(read.cells[3].numberFormatId, 0, reason: file.key);
    }
  });

  /// Edits [name] of the fixtures with the tool and opens the result.
  XlsxWorkbook editedBook(String name) {
    expect(
      editModel(
        <String>[input.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      0,
    );
    return XlsxWorkbook.open(File('${output.path}/$name').readAsBytesSync());
  }

  test('an edited workbook holds the sheet and workbook features', () {
    writeOnly(input, <String>{'m1_values.xlsx'});
    final int row =
        XlsxReader(
          File('${input.path}/m1_values.xlsx').readAsBytesSync(),
        ).rowsAt(0).last.index +
        _newRowOffset;
    final XlsxWorkbook book = editedBook('m1_values.xlsx');
    final XlsxSheet sheet = book.sheets.first;
    expect(
      book.definedNames.map((XlsxDefinedName n) => n.name),
      contains('Model_edit'),
    );
    final XlsxHyperlink? link = sheet.hyperlinkAt(row, 3);
    expect(link?.address, startsWith('https://'));
    expect(link?.text, 'edited by the model');
    expect(sheet.cellAt(row, 3)?.value, 'edited by the model');
    expect(sheet.dataValidations.single.type, XlsxValidationType.list);
    expect(sheet.dataValidations.single.ranges, <XlsxRange>[XlsxRange(row, 6)]);
    final List<XlsxConditionalFormat> formats = sheet.conditionalFormats;
    expect(formats, hasLength(2));
    expect(formats[0].rules.single, isA<XlsxCellValueRule>());
    expect(formats[0].ranges, <XlsxRange>[XlsxRange(row, 7)]);
    expect(formats[1].rules.single, isA<XlsxDataBar>());
    expect(formats[1].ranges, <XlsxRange>[XlsxRange(row, 8)]);
    final XlsxPageSetup? setup = sheet.pageSetup;
    expect(setup?.orientation, XlsxOrientation.landscape);
    expect(setup?.paperSize, XlsxPaperSize.a4);
    expect(setup?.fitToWidth, 1);
    expect(setup?.fitToHeight, isNull);
    expect(sheet.headerFooter?.oddFooter, isNotNull);
    expect(sheet.autoFilter, XlsxRange(row, 0, row, 3));
    expect(book.properties.title, 'Edited by jet_office');
    expect(book.warnings, isEmpty);
  });

  /// The new row of [name]: after the input's last row, the probe and the
  /// two rows inserted above that last row.
  int newRow(String name) =>
      XlsxReader(
        File('${input.path}/$name').readAsBytesSync(),
      ).rowsAt(0).last.index +
      _newRowOffset;

  test(
    'an edited workbook holds a rich text, a note, a picture and a table',
    () {
      writeOnly(input, <String>{'m1_values.xlsx', 'm4_notes.xlsx'});
      for (final String name in <String>['m1_values.xlsx', 'm4_notes.xlsx']) {
        final int row = newRow(name);
        final XlsxSheet sheet = editedBook(name).sheets.first;
        final XlsxRichText? rich = sheet.richTextAt(row, 9);
        expect(rich?.text, 'Rich text', reason: name);
        expect(rich?.runs.first.text, 'Rich ', reason: name);
        expect(rich?.runs.first.font?.bold, isTrue, reason: name);
        expect(rich?.runs.last.text, 'text', reason: name);
        expect(rich?.runs.last.font?.bold, isNot(true), reason: name);
        final XlsxNote? note = sheet.noteAt(row, 10);
        expect(note?.author, 'jet_office', reason: name);
        expect(note?.text.text, isNotEmpty, reason: name);
        final XlsxPicture picture = sheet.pictures.last;
        expect(picture.image, OfficeImage(png4x2), reason: name);
        expect(picture.anchor, isA<XlsxOneCellAnchor>(), reason: name);
        expect(picture.anchor.from, XlsxAnchorPoint(row, 11), reason: name);
        final XlsxTable table = sheet.tables.last;
        expect(table.name, 'Model_table', reason: name);
        expect(table.headerRow, isTrue, reason: name);
        expect(table.columns, hasLength(2), reason: name);
        expect(table.range, XlsxRange(row + 1, 0, row + 2, 1), reason: name);
      }
    },
  );

  test('the structural edits move the probe and its formula follows', () {
    writeOnly(input, <String>{'m1_values.xlsx'});
    final XlsxReader original = XlsxReader(
      File('${input.path}/m1_values.xlsx').readAsBytesSync(),
    );
    final int lastRow = original.rowsAt(0).last.index;
    final List<Object?> lastValues = <Object?>[
      for (final XlsxReadCell c in original.rowsAt(0).last.cells) c.value,
    ];
    expect(
      editModel(
        <String>[input.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      0,
    );
    final XlsxReader edited = XlsxReader(
      File('${output.path}/m1_values.xlsx').readAsBytesSync(),
    );
    expect(edited.sheets.first.name, 'Model edit');
    final List<XlsxReadRow> rows = edited.rowsAt(0).toList();
    // The last row moved two rows down; its column A stayed, the rest moved
    // one column right.
    final XlsxReadRow moved = rows.firstWhere(
      (XlsxReadRow r) => r.index == lastRow + 2,
    );
    expect(moved.cells.first.value, lastValues.first);
    expect(moved.cells.map((XlsxReadCell c) => c.column), isNot(contains(1)));
    final XlsxReadRow probe = rows.firstWhere(
      (XlsxReadRow r) => r.index == lastRow + 3,
    );
    expect(probe.cells.first.formula, 'D${lastRow + 4}&"!"');
    expect(probe.cells.last.column, 3);
    expect(probe.cells.last.value, 'moved by the model');
  });

  test('an edited workbook holds a column chart over data the model wrote, '
      'moved by the structural edits and bound to the renamed sheet', () {
    writeOnly(input, <String>{'m1_values.xlsx'});
    final int row = newRow('m1_values.xlsx');
    final XlsxSheet sheet = editedBook('m1_values.xlsx').sheets.first;
    final XlsxSheetChart chart = sheet.charts.single;
    expect(chart.name, 'Model column chart');
    // Written two rows below the probe from column N before the structural
    // edits: two rows and a column later, the row after the new row from O.
    expect(chart.anchor.from, XlsxAnchorPoint(row + 1, 18));
    final XlsxChart? typed = chart.typed;
    expect(typed, isNotNull);
    expect(typed!.chart.kind, ChartKind.column);
    final List<ChartSeries> series = typed.chart.series;
    expect(series, hasLength(2));
    String rows(String column) =>
        "'Model edit'!\$$column\$${row + 3}:\$$column\$${row + 5}";
    expect(series[0].name.reference, "'Model edit'!\$P\$${row + 2}");
    expect(series[0].categories.reference, rows('O'));
    expect(series[0].values.reference, rows('P'));
    expect(series[1].name.reference, "'Model edit'!\$Q\$${row + 2}");
    expect(series[1].values.reference, rows('Q'));
    expect(sheet.cellAt(row + 1, 15)?.value, series[0].name.values.single);
    expect(sheet.cellAt(row + 2, 14)?.value, series[0].categories.values[0]);
    // A number the model reads keeps its decimal digits.
    expect(
      (sheet.cellAt(row + 3, 16)?.value as XlsxDecimal?)?.toDouble(),
      series[1].values.values[1],
    );
  });

  test('the first typed chart of the first sheet takes a title and moves one '
      'row down', () {
    writeOnly(input, <String>{'c1_kinds.xlsx'});
    final File file = File('${input.path}/c1_kinds.xlsx');
    // The tool's structural edits alone, for where the chart is before the
    // move.
    final XlsxWorkbook shifted = XlsxWorkbook.open(file.readAsBytesSync());
    final XlsxSheet first = shifted.sheets.first;
    final int index = first.charts.indexWhere(
      (XlsxSheetChart c) => c.typed != null,
    );
    expect(index, 0);
    first
      ..insertRows(first.rows.last.index, 2)
      ..insertColumns(1);
    final XlsxTwoCellAnchor before =
        first.charts[index].anchor as XlsxTwoCellAnchor;
    final XlsxSheet sheet = editedBook('c1_kinds.xlsx').sheets.first;
    final List<XlsxSheetChart> charts = sheet.charts;
    expect(charts, hasLength(13));
    expect(charts[index].view?.title?.text, 'Model chart');
    expect(charts[index].typed?.chart.title?.text, 'Model chart');
    expect(
      charts[index].anchor,
      XlsxTwoCellAnchor(
        XlsxAnchorPoint(before.from.row + 1, before.from.column),
        XlsxAnchorPoint(before.to.row + 1, before.to.column),
        resize: before.resize,
      ),
    );
    expect(charts[1].view?.title?.text, isNot('Model chart'));
  });

  test('the table takes a number when its name is taken', () {
    final XlsxWorkbook source = XlsxWorkbook();
    source.addSheet('One').setCell(0, 0, 'x');
    source
        .addSheet('Two')
        .addTable(
          XlsxTable(
            'MODEL_table',
            const XlsxRange(0, 3, 1, 4),
            <XlsxTableColumn>[
              const XlsxTableColumn('P'),
              const XlsxTableColumn('Q'),
            ],
          ),
        );
    File('${input.path}/taken.xlsx').writeAsBytesSync(source.save().bytes);
    final XlsxSheet sheet = editedBook('taken.xlsx').sheets.first;
    expect(sheet.tables.single.name, 'Model_table2');
  });

  test('the defined name takes a number when its name is taken', () {
    final XlsxWorkbook source = XlsxWorkbook();
    source.addSheet('One').setCell(0, 0, 'x');
    source.defineName(const XlsxDefinedName('model_EDIT', 'One!\$A\$1'));
    File('${input.path}/taken.xlsx').writeAsBytesSync(source.save().bytes);
    final XlsxWorkbook book = editedBook('taken.xlsx');
    expect(book.definedNames.map((XlsxDefinedName n) => n.name), <String>[
      'model_EDIT',
      'Model_edit2',
    ]);
  });

  test('an auto filter in the way is left alone by the features', () {
    writeOnly(input, <String>{'m2_merges_filter.xlsx'});
    final XlsxRange? before = XlsxWorkbook.open(
      File('${input.path}/m2_merges_filter.xlsx').readAsBytesSync(),
    ).sheets.first.autoFilter;
    expect(before, isNotNull);
    // Only the structural edits move it: two rows inserted above the last
    // row inside it and a column at B.
    expect(
      editedBook('m2_merges_filter.xlsx').sheets.first.autoFilter,
      XlsxRange(
        before!.firstRow,
        before.firstColumn,
        before.lastRow + 2,
        before.lastColumn + 1,
      ),
    );
  });

  test('setting a width keeps what the column already had', () {
    writeOnly(input, <String>{'m2_columns_rows.xlsx'});
    final File file = File('${input.path}/m2_columns_rows.xlsx');
    final XlsxColumn? before = XlsxWorkbook.open(
      file.readAsBytesSync(),
    ).sheets.first.column(1);
    expect(
      editModel(
        <String>[input.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      0,
    );
    final XlsxColumn? after = XlsxWorkbook.open(
      File('${output.path}/m2_columns_rows.xlsx').readAsBytesSync(),
    ).sheets.first.column(1);
    expect(after?.width, 30);
    expect(after?.style, before?.style);
    expect(after?.hidden, before?.hidden ?? false);
    expect(after?.outlineLevel, before?.outlineLevel ?? 0);
  });

  test('showsNoDate is true only for a number format without a date', () {
    bool shows(XlsxNumFmt format) => showsNoDate(XlsxStyle(numFmt: format));
    expect(showsNoDate(null), isFalse);
    expect(showsNoDate(const XlsxStyle()), isFalse);
    expect(shows(XlsxNumFmt.general), isFalse);
    expect(shows(XlsxNumFmt.localeShortDate), isFalse);
    expect(shows(const XlsxNumFmt.custom('yyyy-mm-dd')), isFalse);
    expect(shows(const XlsxNumFmt.custom('#,##0.00')), isTrue);
    expect(shows(XlsxNumFmt.money(symbol: '€')), isTrue);
  });

  test('every fixture takes every edit: exit 0', () {
    write_fixtures.main(<String>[input.path]);
    final StringBuffer out = StringBuffer();
    final int code = editModel(
      <String>[input.path, output.path],
      out: out,
      err: StringBuffer(),
    );
    expect(code, 0, reason: '$out');
  });

  test('a truncated workbook is reported: exit 1', () {
    writeOnly(input, <String>{'m1_values.xlsx'});
    final File file = File('${input.path}/m1_values.xlsx');
    final Uint8List bytes = file.readAsBytesSync();
    file.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    final StringBuffer out = StringBuffer();
    final int code = editModel(
      <String>[input.path, output.path],
      out: out,
      err: StringBuffer(),
    );
    expect(code, 1);
    expect(out.toString(), contains('m1_values.xlsx: '));
  });

  test('unusable arguments or no workbook: exit 2', () {
    final StringBuffer err = StringBuffer();
    expect(editModel(<String>['one'], out: StringBuffer(), err: err), 2);
    expect(err.toString(), contains('Usage:'));
    expect(
      editModel(
        <String>['${temp.path}/missing', output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      2,
    );
    expect(
      editModel(
        <String>[input.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      2,
    );
  });
}
