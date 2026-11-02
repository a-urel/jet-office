// Tests tool/round_trip_model.dart: the model round trip of a directory of
// workbooks, its exit codes and its messages. It reads and writes files, so
// it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/round_trip_model.dart';
import '../../tool/write_fixtures.dart' as write_fixtures;

void main() {
  late Directory temp;
  late Directory input;
  late Directory output;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('round_trip_model_test');
    input = Directory('${temp.path}/in')..createSync();
    output = Directory('${temp.path}/out');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// Writes every fixture (and the corrupt one) to [dir], then deletes all
  /// but the `.xlsx` files named in [keep].
  void writeOnly(Directory dir, Set<String> keep, {bool corrupt = false}) {
    write_fixtures.main(<String>[dir.path, if (corrupt) '--corrupt']);
    for (final FileSystemEntity e in dir.listSync()) {
      final String name = e.uri.pathSegments.last;
      if (!keep.contains(name)) e.deleteSync();
    }
  }

  test('round-trips two writer fixtures: exit 0 and two outputs', () {
    writeOnly(input, <String>{'m1_values.xlsx', 'm1_sheets.xlsx'});
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    final int code = roundTripModel(
      <String>[input.path, output.path],
      out: out,
      err: err,
    );
    expect(code, 0, reason: '$out$err');
    expect(
      output.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
      unorderedEquals(<String>['m1_values.xlsx', 'm1_sheets.xlsx']),
    );
    expect(err.toString(), isEmpty);
  });

  test('a truncated workbook is refused: exit 1 and a message', () {
    writeOnly(input, <String>{'m1_values.xlsx'});
    final File file = File('${input.path}/m1_values.xlsx');
    final Uint8List bytes = file.readAsBytesSync();
    file.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    final StringBuffer out = StringBuffer();
    final int code = roundTripModel(
      <String>[input.path, output.path],
      out: out,
      err: StringBuffer(),
    );
    expect(code, 1);
    expect(out.toString(), contains('m1_values.xlsx: '));
  });

  test('the --corrupt workbook keeps its fault, so validation rejects it', () {
    // The model preserves what it does not understand: a cell after
    // </sheetData> comes back unchanged, so the round trip finds no
    // difference and the Open XML SDK step is what rejects the output.
    writeOnly(input, <String>{'m1_corrupt.xlsx'}, corrupt: true);
    final int code = roundTripModel(
      <String>[input.path, output.path],
      out: StringBuffer(),
      err: StringBuffer(),
    );
    expect(code, 0);
    expect(File('${output.path}/m1_corrupt.xlsx').existsSync(), isTrue);
  });

  test('a difference is printed as <file>: <line>', () {
    // A workbook the model does not reproduce is hard to build from the
    // writer, so an unreadable file stands in: the tool names it.
    File('${input.path}/broken.xlsx').writeAsBytesSync(<int>[1, 2, 3]);
    final StringBuffer out = StringBuffer();
    final int code = roundTripModel(
      <String>[input.path, output.path],
      out: out,
      err: StringBuffer(),
    );
    expect(code, 1);
    expect(out.toString(), startsWith('broken.xlsx: '));
  });

  test('unusable arguments: exit 2', () {
    final StringBuffer err = StringBuffer();
    expect(
      roundTripModel(<String>['only-one'], out: StringBuffer(), err: err),
      2,
    );
    expect(err.toString(), contains('Usage:'));
    expect(
      roundTripModel(
        <String>['${temp.path}/missing', output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      2,
    );
  });

  test('a directory without a workbook: exit 2', () {
    expect(
      roundTripModel(
        <String>[input.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      2,
    );
  });
}
