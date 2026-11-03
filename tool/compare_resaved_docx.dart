/// Opens LibreOffice's re-save of every DOCX fixture with `DocxDocument`
/// and compares its text with the fixture's expected text.
///
/// ```bash
/// LC_ALL=C.UTF-8 soffice --headless --convert-to 'docx:MS Word 2007 XML' \
///   --outdir build/resaved-docx build/fixtures/*.docx
/// dart run tool/compare_resaved_docx.dart build/fixtures build/resaved-docx
/// ```
///
/// For every `<name>.expected.txt` in the first directory (written by
/// `tool/write_fixtures.dart`) it opens `<resaved>/<name>.docx`, reads the
/// body and compares `docxBodyText` (each paragraph's text, joined by
/// `\n`) with the expected text by `textDifferences`
/// (`tool/src/text_compare.dart`). Every warning opening and reading the
/// re-save reports is a mismatch unless `docxResaveAllowedWarnings` in
/// `tool/src/read_compare.dart` names the fixture and the code. A missing
/// or unreadable re-save is a mismatch. This is spec 9's "DOCX re-save
/// opened with `DocxDocument` and compared".
///
/// Each mismatch is printed as `<name>: <line>`. The exit code is 1 on any
/// mismatch, 2 when the arguments are unusable or the first directory
/// holds no `.expected.txt`, and 0 otherwise, as `tool/compare_text.dart`.
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';

import 'compare_text.dart' show expectedTextNames;
import 'src/read_compare.dart' show docxResaveAllowedWarnings;
import 'src/text_compare.dart';

void main(List<String> args) {
  exitCode = compareResavedDocx(args, out: stdout, err: stderr);
}

/// Runs the tool on [args] (`<fixtures dir> <resaved dir>`), writing
/// mismatches to [out] and usage problems to [err], and returns the exit
/// code.
int compareResavedDocx(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 2) {
    err.writeln(
      'Usage: dart run tool/compare_resaved_docx.dart <fixtures dir> '
      '<resaved dir>',
    );
    return 2;
  }
  final Directory dir = Directory(args[0]);
  if (!dir.existsSync()) {
    err.writeln('No such directory: ${dir.path}');
    return 2;
  }
  final List<String> names = expectedTextNames(dir);
  if (names.isEmpty) {
    err.writeln('Nothing to compare: no .expected.txt in ${dir.path}.');
    return 2;
  }
  int failed = 0;
  for (final String name in names) {
    final String expected = readExpectedText(
      File('${dir.path}/$name.expected.txt').readAsStringSync(),
    );
    final List<String> problems = _compare(
      name,
      expected,
      File('${args[1]}/$name.docx'),
    );
    for (final String line in problems) {
      out.writeln('$name: $line');
    }
    if (problems.isNotEmpty) failed++;
  }
  out.writeln(
    failed == 0
        ? 'All ${names.length} re-saved documents match.'
        : '$failed of ${names.length} re-saved documents differ.',
  );
  return failed == 0 ? 0 : 1;
}

/// The mismatches of the re-saved [file] of fixture [name] against its
/// [expected] text.
List<String> _compare(String name, String expected, File file) {
  if (!file.existsSync()) return <String>['missing ${file.path}'];
  final DocxDocument doc;
  final String text;
  try {
    doc = DocxDocument.open(file.readAsBytesSync());
    text = docxBodyText(doc);
  } on DocxReadException catch (e) {
    return <String>['the model refused the re-save: $e'];
  }
  final Map<DocxWarningCode, String> allowed =
      docxResaveAllowedWarnings[name] ?? const <DocxWarningCode, String>{};
  return <String>[
    ...textDifferences(expected, text),
    for (final DocxWarning w in doc.warnings)
      if (!allowed.containsKey(w.code))
        'warning ${w.code.name} in ${w.part}: ${w.message()}',
  ];
}
