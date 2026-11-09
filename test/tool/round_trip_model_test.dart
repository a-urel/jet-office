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
import '../support/read_xlsx.dart';

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

  test('--corrupt adds c1_corrupt.xlsx: c1_kinds with two dispNaAsBlank', () {
    // The Open XML SDK negative control of tool/ooxml_validate's narrow
    // ignore of Excel's chart display options: only the first chart part
    // differs from c1_kinds, and only by a second dispNaAsBlank.
    write_fixtures.main(<String>[input.path, '--corrupt']);
    final Map<String, String> kinds = readXlsx(
      File('${input.path}/c1_kinds.xlsx').readAsBytesSync(),
    );
    final Map<String, String> corrupt = readXlsx(
      File('${input.path}/c1_corrupt.xlsx').readAsBytesSync(),
    );
    expect(corrupt.keys, kinds.keys);
    for (final String name in kinds.keys) {
      if (name != 'xl/charts/chart1.xml') {
        expect(corrupt[name], kinds[name], reason: name);
      }
    }
    const String blank = '<c16r3:dispNaAsBlank val="1"/>';
    expect(
      corrupt['xl/charts/chart1.xml'],
      kinds['xl/charts/chart1.xml']!.replaceFirst(blank, '$blank$blank'),
    );
    expect(kinds['xl/charts/chart1.xml'], contains(blank));
    expect(File('${input.path}/c1_corrupt.expected.json').existsSync(), isTrue);
  });

  test('--corrupt adds c1_corrupt_labels.xlsx: c1_options with two '
      'showLeaderLines', () {
    // The negative control of tool/ooxml_validate's narrow ignore of
    // Excel's data label leader lines: only the line chart's part differs
    // from c1_options, and only by a second showLeaderLines.
    write_fixtures.main(<String>[input.path, '--corrupt']);
    final Map<String, String> options = readXlsx(
      File('${input.path}/c1_options.xlsx').readAsBytesSync(),
    );
    final Map<String, String> corrupt = readXlsx(
      File('${input.path}/c1_corrupt_labels.xlsx').readAsBytesSync(),
    );
    expect(corrupt.keys, options.keys);
    for (final String name in options.keys) {
      if (name != 'xl/charts/chart2.xml') {
        expect(corrupt[name], options[name], reason: name);
      }
    }
    const String show = '<c15:showLeaderLines val="1"/>';
    expect(options['xl/charts/chart2.xml'], contains(show));
    expect(
      corrupt['xl/charts/chart2.xml'],
      options['xl/charts/chart2.xml']!.replaceFirst(show, '$show$show'),
    );
    expect(
      File('${input.path}/c1_corrupt_labels.expected.json').existsSync(),
      isTrue,
    );
  });

  test('an unreadable file is printed as <file>: <error>', () {
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
