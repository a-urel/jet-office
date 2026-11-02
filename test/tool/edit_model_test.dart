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
