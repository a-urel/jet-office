/// Writes the fixtures for the CI validation job.
///
/// ```bash
/// dart run tool/write_fixtures.dart build/fixtures [--corrupt]
/// ```
///
/// For every fixture of `allFixtures()` it writes `<dir>/<name>.xlsx` and
/// `<dir>/<name>.expected.json`, the fixture's `expectedValues` as a JSON
/// object of sheet name to rows (strings, numbers, booleans and `null`).
/// `tool/ooxml_validate` validates the `.xlsx` files and
/// `tool/compare_csv.dart` compares LibreOffice's CSV export of them with the
/// `.expected.json` files.
///
/// For every fixture of `docxFixtures()` it writes `<dir>/<name>.docx` and
/// `<dir>/<name>.expected.txt`, the fixture's `expectedText` and a final
/// newline. `tool/ooxml_validate` validates the `.docx` files too,
/// `tool/compare_text.dart` compares LibreOffice's text export of them with
/// the `.expected.txt` files, and `tool/compare_resaved_docx.dart` compares
/// LibreOffice's re-save of them. A fixture whose text LibreOffice writes
/// differently (a list's labels, which the model's text does not have) also
/// gets `<dir>/<name>.libreoffice.txt`, that text, which
/// `tool/compare_text.dart` prefers. A fixture with a `libreOfficeTextSkip`
/// reason gets `<dir>/<name>.libreoffice-skip.txt`, the reason. A fixture with
/// a `headerFooterText` gets `<dir>/<name>.stories.txt`, that text, which
/// `tool/compare_resaved_docx.dart` compares with what the re-save's headers
/// and footers show.
///
/// `--corrupt` also writes `m1_corrupt.xlsx` and its `.expected.json`, to
/// prove that both checks fail on a bad file. It is `m1_values` with two
/// faults: a cell after `</sheetData>`, which the Open XML SDK rejects, and
/// its `42` stored as `41`, which the CSV comparison rejects. CI passes the
/// flag with a separate directory, `build/corrupt`, as a standing negative
/// control and requires both checks to reject that file.
///
/// It also writes `c1_corrupt.xlsx` and its `.expected.json`: `c1_kinds`
/// whose first chart part holds two `c16r3:dispNaAsBlank` in Excel's
/// `c16r3:dataDisplayOptions16` extension. `tool/ooxml_validate` ignores the
/// two errors the Open XML SDK gives on that extension only when it holds
/// exactly one, so it must reject this file; CI validates it alone, in
/// `build/corrupt-chart`, as the negative control of that ignore.
///
/// And `c1_corrupt_labels.xlsx`: `c1_options` whose line chart
/// (`xl/charts/chart2.xml`) holds two `c15:showLeaderLines` in the first
/// series' data label leader line extension, which `tool/ooxml_validate`
/// ignores only in Excel's exact form; CI validates it beside `c1_corrupt`,
/// as the negative control of that ignore.
///
/// It writes `d1_corrupt.docx` with the `.expected.txt` of `d1_paragraphs`
/// as well, for the same purpose: `d1_paragraphs` with a `w:r` directly
/// under `w:body`, which the Open XML SDK rejects, and `first` spelled
/// `firzt`, which the text comparisons reject.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/src/zip/archive_adapter.dart';

import '../test/docx/support/docx_builder.dart' show rewriteDocxPart;
import '../test/fixtures/docx_fixtures.dart';
import '../test/fixtures/fixtures.dart';
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
  final List<Fixture> fixtures = allFixtures();
  for (final Fixture fixture in fixtures) {
    _write(dir, fixture.name, fixture.build(), json, fixture.expectedValues);
  }
  final List<DocxFixture> documents = docxFixtures();
  for (final DocxFixture fixture in documents) {
    _writeDocx(
      dir,
      fixture.name,
      fixture.build().bytes,
      fixture.expectedText,
      libreOfficeText: fixture.libreOfficeText,
      libreOfficeTextSkip: fixture.libreOfficeTextSkip,
      headerFooterText: fixture.headerFooterText,
    );
  }
  if (corrupt) {
    final DocxFixture paragraphs = documents.singleWhere(
      (DocxFixture f) => f.name == 'd1_paragraphs',
    );
    _writeDocx(
      dir,
      'd1_corrupt',
      _corruptDocx(paragraphs.build().bytes),
      paragraphs.expectedText,
    );
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
    final Fixture kinds = fixtures.singleWhere(
      (Fixture f) => f.name == 'c1_kinds',
    );
    _write(
      dir,
      'c1_corrupt',
      _corruptChart(kinds.build()),
      json,
      kinds.expectedValues,
    );
    final Fixture options = fixtures.singleWhere(
      (Fixture f) => f.name == 'c1_options',
    );
    _write(
      dir,
      'c1_corrupt_labels',
      _corruptLabels(options.build()),
      json,
      options.expectedValues,
    );
  }
  stdout.writeln(
    'Wrote ${fixtures.length + documents.length + (corrupt ? 4 : 0)} '
    'fixtures to ${dir.path}.',
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

void _writeDocx(
  Directory dir,
  String name,
  Uint8List bytes,
  String text, {
  String? libreOfficeText,
  String? libreOfficeTextSkip,
  String? headerFooterText,
}) {
  File('${dir.path}/$name.docx').writeAsBytesSync(bytes);
  File('${dir.path}/$name.expected.txt').writeAsStringSync('$text\n');
  if (libreOfficeText != null && libreOfficeText != text) {
    File(
      '${dir.path}/$name.libreoffice.txt',
    ).writeAsStringSync('$libreOfficeText\n');
  }
  if (libreOfficeTextSkip != null) {
    File(
      '${dir.path}/$name.libreoffice-skip.txt',
    ).writeAsStringSync('$libreOfficeTextSkip\n');
  }
  if (headerFooterText != null) {
    File(
      '${dir.path}/$name.stories.txt',
    ).writeAsStringSync('$headerFooterText\n');
  }
}

/// [bytes] (the `d1_paragraphs` document) with an empty `w:r` directly
/// under `w:body` and `first` spelled `firzt`.
Uint8List _corruptDocx(Uint8List bytes) => rewriteDocxPart(
  bytes,
  'word/document.xml',
  (String xml) => _replaceOnce(
    _replaceOnce(xml, '<w:body>', '<w:body><w:r/>'),
    'The first paragraph.',
    'The firzt paragraph.',
  ),
);

/// [bytes] (the `m1_values` workbook) with a cell after `</sheetData>` and
/// its `42` stored as `41`.
Uint8List _corrupt(Uint8List bytes) => _rewritePart(
  bytes,
  'xl/worksheets/sheet1.xml',
  (String xml) => _replaceOnce(
    _replaceOnce(xml, '</sheetData>', '</sheetData><c r="A3"><v>1</v></c>'),
    '<v>42</v>',
    '<v>41</v>',
  ),
);

/// [bytes] (the `c1_kinds` workbook) with a second `c16r3:dispNaAsBlank` in
/// the display options extension of its first chart part.
Uint8List _corruptLabels(Uint8List bytes) {
  const String show = '<c15:showLeaderLines val="1"/>';
  return _rewritePart(
    bytes,
    'xl/charts/chart2.xml',
    (String xml) => _replaceOnce(xml, show, '$show$show'),
  );
}

Uint8List _corruptChart(Uint8List bytes) {
  const String blank = '<c16r3:dispNaAsBlank val="1"/>';
  return _rewritePart(
    bytes,
    'xl/charts/chart1.xml',
    (String xml) => _replaceOnce(xml, blank, '$blank$blank'),
  );
}

/// [bytes], an XLSX file without media parts, with the part [name] replaced
/// by [rewrite] of its text.
Uint8List _rewritePart(
  Uint8List bytes,
  String name,
  String Function(String xml) rewrite,
) {
  final Map<String, String> parts = readXlsx(bytes);
  final String bad = rewrite(parts[name]!);
  final ZipWriter zip = ZipWriter();
  parts.forEach((String part, String text) {
    zip.add(part, utf8.encode(part == name ? bad : text));
  });
  return zip.close()!;
}

String _replaceOnce(String text, String from, String to) {
  final int at = text.indexOf(from);
  if (at < 0 || text.indexOf(from, at + 1) >= 0) {
    throw StateError('Expected exactly one "$from" in the part.');
  }
  return text.replaceRange(at, at + from.length, to);
}
