/// Drafts the expected values of a real Excel or Google Sheets file.
///
/// ```bash
/// dart run tool/draft_expected.dart test/fixtures/owner/excel_products.xlsx
/// ```
///
/// Reads the file with `XlsxReader` and writes `<file>.expected.json` beside
/// it, in the format of `test/support/owner_expected.dart`, with
/// `"confirmedBy": null` and an empty `"producer"`. It prints a review
/// table, `Sheet!Cell  type  value  format  formula`, for the owner to tick
/// cell by cell against the program that made the file. The draft is the
/// reader's own opinion: only after the owner has checked every cell and
/// set `producer` and `"confirmedBy": "owner"` is it an expectation, and
/// `test/xlsx/read/owner_files_test.dart` refuses any other. The tool never
/// overwrites an existing `.expected.json` (exit 1) so a confirmed file
/// cannot be lost. See `test/fixtures/owner/README.md`.
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';

import '../test/support/owner_expected.dart';

void main(List<String> args) {
  if (args.length != 1 || !args.single.endsWith('.xlsx')) {
    stderr.writeln('Usage: dart run tool/draft_expected.dart <file.xlsx>');
    exitCode = 64;
    return;
  }
  final File input = File(args.single);
  if (!input.existsSync()) {
    stderr.writeln('No such file: ${input.path}');
    exitCode = 66;
    return;
  }
  final File output = File(
    '${input.path.substring(0, input.path.length - 5)}.expected.json',
  );
  if (output.existsSync()) {
    stderr.writeln(
      '${output.path} exists; delete it first if you mean to draft again.',
    );
    exitCode = 1;
    return;
  }
  final XlsxReader reader;
  final String draft;
  final String table;
  try {
    reader = XlsxReader(input.readAsBytesSync());
    draft = draftOwnerExpected(reader, file: input.uri.pathSegments.last);
    table = reviewTable(reader);
  } on XlsxReadException catch (e) {
    stderr.writeln('The reader refused ${input.path}: $e');
    exitCode = 1;
    return;
  }
  output.writeAsStringSync(draft);
  stdout
    ..writeln(table)
    ..writeln('Wrote ${output.path}: check every cell above in the program,')
    ..writeln('set "producer" and "confirmedBy": "owner", then add the file')
    ..writeln('to test/fixtures/owner/manifest.json.');
}
