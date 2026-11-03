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
    expect(edited.sheets.last.name, 'Model edit');
    final int lastRow = original.rowsAt(0).last.index;
    final XlsxReadRow row = edited
        .rowsAt(0)
        .firstWhere((XlsxReadRow r) => r.index > lastRow);
    final List<Object?> values = <Object?>[
      for (final XlsxReadCell c in row.cells) c.value,
    ];
    expect(values, hasLength(4));
    expect(values[0], isA<DateTime>());
    expect(values[1], isA<DateTime>());
    expect(row.cells[2].formula, 'SUM(1,2)');
    expect(values[3], 'edited by the model');
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
      final int row = file.value + 1;
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
