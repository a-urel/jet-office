/// Writes the M1 fixtures for the CI validation job.
///
/// ```bash
/// dart run tool/write_fixtures.dart build/fixtures [--corrupt]
/// ```
///
/// For every fixture of `m1Fixtures()` it writes `<dir>/<name>.xlsx` and
/// `<dir>/<name>.expected.json`, the fixture's `expectedValues` as a JSON
/// object of sheet name to rows (strings, numbers, booleans and `null`).
/// `tool/ooxml_validate` validates the `.xlsx` files and
/// `tool/compare_csv.dart` compares LibreOffice's CSV export of them with the
/// `.expected.json` files.
///
/// `--corrupt` also writes `m1_corrupt.xlsx` and its `.expected.json`, to
/// prove that both checks fail on a bad file. It is `m1_values` with two
/// faults: a cell after `</sheetData>`, which the Open XML SDK rejects, and
/// its `42` stored as `41`, which the CSV comparison rejects. CI never
/// passes the flag.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/src/zip/archive_adapter.dart';

import '../test/fixtures/m1_fixtures.dart';
import '../test/support/read_xlsx.dart';

void main(List<String> args) {
  final bool corrupt = args.contains('--corrupt');
  final List<String> paths = <String>[
    for (final String arg in args)
      if (arg != '--corrupt') arg,
  ];
  if (paths.length != 1 || paths.single.startsWith('-')) {
    stderr.writeln(
      'Usage: dart run tool/write_fixtures.dart <dir> [--corrupt]',
    );
    exitCode = 64;
    return;
  }
  final Directory dir = Directory(paths.single)..createSync(recursive: true);
  const JsonEncoder json = JsonEncoder.withIndent('  ');
  final List<Fixture> fixtures = m1Fixtures();
  for (final Fixture fixture in fixtures) {
    _write(dir, fixture.name, fixture.build(), json, fixture.expectedValues);
  }
  if (corrupt) {
    final Fixture values = fixtures.singleWhere(
      (Fixture f) => f.name == 'm1_values',
    );
    _write(
      dir,
      'm1_corrupt',
      _corrupt(values.build()),
      json,
      values.expectedValues,
    );
  }
  stdout.writeln(
    'Wrote ${fixtures.length + (corrupt ? 1 : 0)} fixtures to ${dir.path}.',
  );
}

void _write(
  Directory dir,
  String name,
  Uint8List bytes,
  JsonEncoder json,
  Map<String, List<List<Object?>>> expected,
) {
  File('${dir.path}/$name.xlsx').writeAsBytesSync(bytes);
  File(
    '${dir.path}/$name.expected.json',
  ).writeAsStringSync('${json.convert(expected)}\n');
}

/// [bytes] (the `m1_values` workbook) with a cell after `</sheetData>` and
/// its `42` stored as `41`.
Uint8List _corrupt(Uint8List bytes) {
  const String sheet = 'xl/worksheets/sheet1.xml';
  final Map<String, String> parts = readXlsx(bytes);
  final String xml = parts[sheet]!;
  final String bad = _replaceOnce(
    _replaceOnce(xml, '</sheetData>', '</sheetData><c r="A3"><v>1</v></c>'),
    '<v>42</v>',
    '<v>41</v>',
  );
  final ZipWriter zip = ZipWriter();
  parts.forEach((String name, String text) {
    zip.add(name, utf8.encode(name == sheet ? bad : text));
  });
  return zip.close()!;
}

String _replaceOnce(String text, String from, String to) {
  final int at = text.indexOf(from);
  if (at < 0 || text.indexOf(from, at + 1) >= 0) {
    throw StateError('Expected exactly one "$from" in the sheet.');
  }
  return text.replaceRange(at, at + from.length, to);
}
