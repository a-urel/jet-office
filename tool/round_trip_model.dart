/// Round-trips every workbook of a directory through `XlsxWorkbook` and
/// compares the saved package with the input.
///
/// ```bash
/// dart run tool/round_trip_model.dart build/fixtures build/model
/// ```
///
/// For every `*.xlsx` in the first directory it opens the workbook with
/// `XlsxWorkbook.open`, loads every sheet by reading its rows, reads its
/// objects (the rich text of every string cell, its notes, pictures and
/// tables), saves it and writes the bytes to `<outDir>/<name>.xlsx`. It then compares the saved
/// package with the input by `comparePackages` from `tool/src/part_compare.dart`
/// with `ignoreBookkeeping`, because the model recomputes `dimension/@ref` and
/// `row/@spans` on save by design. A model that changes nothing must leave
/// nothing else different, so every other difference is a defect.
///
/// Each difference is printed as `<file>: <line>`, one per line, and a file
/// that cannot be opened or saved as `<file>: <error>`. The exit code is 1 on
/// any difference or error, 2 when the arguments are unusable or the input
/// directory holds no `.xlsx`, and 0 otherwise.
///
/// CI runs it on the writer fixtures and on LibreOffice's re-save of them,
/// then validates the output with `tool/ooxml_validate`, so the model's
/// output is held to the same standard as the writer's.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import 'src/part_compare.dart';

void main(List<String> args) {
  exitCode = roundTripModel(args, out: stdout, err: stderr);
}

/// Runs the tool on [args] (`<inDir> <outDir>`), writing differences to [out]
/// and usage problems to [err], and returns the exit code.
int roundTripModel(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 2) {
    err.writeln('Usage: dart run tool/round_trip_model.dart <inDir> <outDir>');
    return 2;
  }
  final Directory input = Directory(args[0]);
  if (!input.existsSync()) {
    err.writeln('No such directory: ${input.path}');
    return 2;
  }
  final List<File> files =
      input
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.xlsx'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    err.writeln('Nothing to round-trip: no .xlsx in ${input.path}.');
    return 2;
  }
  final Directory output = Directory(args[1])..createSync(recursive: true);
  int failed = 0;
  for (final File file in files) {
    final String name = file.uri.pathSegments.last;
    final List<String> problems = _roundTrip(file, output, name);
    for (final String line in problems) {
      out.writeln('$name: $line');
    }
    if (problems.isNotEmpty) failed++;
  }
  out.writeln(
    failed == 0
        ? 'All ${files.length} workbooks round-trip.'
        : '$failed of ${files.length} workbooks differ.',
  );
  return failed == 0 ? 0 : 1;
}

/// The differences between [file] and its round trip, which is also written
/// to [output]; one line when the model refuses or fails on [file].
List<String> _roundTrip(File file, Directory output, String name) {
  final Uint8List input = file.readAsBytesSync();
  final Uint8List saved;
  try {
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    for (final XlsxSheet sheet in book.sheets) {
      _readObjects(sheet);
    }
    saved = book.save().bytes;
  } on XlsxReadException catch (e) {
    return <String>['the model refused the workbook: $e'];
  } on Object catch (e) {
    return <String>['the round trip failed: $e'];
  }
  File('${output.path}/$name').writeAsBytesSync(saved);
  return comparePackages(input, saved, ignoreBookkeeping: true);
}

/// Loads [sheet] and reads its rows and objects, which must change nothing.
void _readObjects(XlsxSheet sheet) {
  for (final XlsxReadRow row in sheet.rows) {
    for (final XlsxReadCell cell in row.cells) {
      if (cell.value is String) sheet.richTextAt(row.index, cell.column);
    }
  }
  sheet.notes.toList();
  sheet.pictures.toList();
  sheet.tables.toList();
}
