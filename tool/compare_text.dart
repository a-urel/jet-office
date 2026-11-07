/// Compares LibreOffice's text export of every DOCX fixture with its
/// expected text.
///
/// ```bash
/// LC_ALL=C.UTF-8 soffice --headless --convert-to 'txt:Text (encoded):UTF8' \
///   --outdir build/fixtures build/fixtures/*.docx
/// dart run tool/compare_text.dart build/fixtures
/// ```
///
/// For every `<name>.expected.txt` in the directory (written by
/// `tool/write_fixtures.dart`) it reads LibreOffice's `<name>.txt` and
/// compares it with the expected text, or with `<name>.libreoffice.txt` when
/// that exists: the text LibreOffice writes for a document with lists, whose
/// labels (`    • Bullet one`) the model's text does not have. The
/// comparison is by `textDifferences` from `tool/src/text_compare.dart`,
/// whose library comment states the contract: a leading BOM and one
/// trailing newline are ignored, everything else must be equal. The filter
/// `Text (encoded):UTF8` writes UTF-8 with a BOM and ends every paragraph
/// with a line feed; `LC_ALL=C.UTF-8` keeps the locale from changing that.
///
/// A document with a `<name>.libreoffice-skip.txt` (its reason, written by
/// `tool/write_fixtures.dart` from `DocxFixture.libreOfficeTextSkip`) is not
/// compared: the tool prints `<name>: skipped: <reason>` and counts it apart.
/// Its re-save is still compared by `tool/compare_resaved_docx.dart`.
///
/// Each difference is printed as `<name>: <line>`, a missing export as
/// `<name>: missing <file>`. The exit code is 1 on any difference, 2 when
/// the arguments are unusable or the directory holds no `.expected.txt`,
/// and 0 otherwise.
library;

import 'dart:io';

import 'src/text_compare.dart';

void main(List<String> args) {
  exitCode = compareText(args, out: stdout, err: stderr);
}

/// Runs the tool on [args] (`<dir>`), writing differences to [out] and
/// usage problems to [err], and returns the exit code.
int compareText(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 1) {
    err.writeln('Usage: dart run tool/compare_text.dart <dir>');
    return 2;
  }
  final Directory dir = Directory(args.single);
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
  int skipped = 0;
  for (final String name in names) {
    final File skip = File('${dir.path}/$name.libreoffice-skip.txt');
    if (skip.existsSync()) {
      out.writeln('$name: skipped: ${skip.readAsStringSync().trim()}');
      skipped++;
      continue;
    }
    final File pinned = File('${dir.path}/$name.libreoffice.txt');
    final String expected = readExpectedText(
      (pinned.existsSync() ? pinned : File('${dir.path}/$name.expected.txt'))
          .readAsStringSync(),
    );
    final File exported = File('${dir.path}/$name.txt');
    final List<String> problems = exported.existsSync()
        ? textDifferences(
            expected,
            readExpectedText(exported.readAsStringSync()),
          )
        : <String>['missing ${exported.path}'];
    for (final String line in problems) {
      out.writeln('$name: $line');
    }
    if (problems.isNotEmpty) failed++;
  }
  final String note = skipped == 0 ? '' : ' ($skipped skipped)';
  out.writeln(
    failed == 0
        ? 'All ${names.length - skipped} documents export the expected '
              'text$note.'
        : '$failed of ${names.length - skipped} documents differ$note.',
  );
  return failed == 0 ? 0 : 1;
}

/// The stems of the `<stem>.expected.txt` files in [dir], sorted.
List<String> expectedTextNames(Directory dir) {
  const String suffix = '.expected.txt';
  return <String>[
    for (final File f in dir.listSync().whereType<File>())
      if (f.uri.pathSegments.last.endsWith(suffix))
        f.uri.pathSegments.last.substring(
          0,
          f.uri.pathSegments.last.length - suffix.length,
        ),
  ]..sort();
}
