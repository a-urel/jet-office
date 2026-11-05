/// Round-trips every document of a directory through `DocxDocument` and
/// compares the saved package with the input.
///
/// ```bash
/// dart run tool/round_trip_docx.dart build/resaved-docx build/model-docx
/// ```
///
/// For every `*.docx` in the first directory it opens the document with
/// `DocxDocument.open`, reads the body (so the main part goes through the
/// model, not only the copy of an unloaded part), reads every typed property
/// of every paragraph, run, style and list level, which loads the styles and
/// numbering parts, saves it and writes the bytes to `<outDir>/<name>.docx`.
/// It then compares the saved package with the input by `comparePackages`
/// from `tool/src/part_compare.dart`. A model that changes nothing must
/// leave nothing different, so every difference is a defect.
///
/// A styles or numbering part that is loaded and not changed is saved as it
/// was read, byte for byte, so loading it does not run the encoder. The tool
/// therefore also reads each of the two parts into its model, encodes it and
/// compares that with the part in the input by `encodedPartDifferences` from
/// `tool/src/docx_serialize.dart`, so CI's round trips serialize both parts
/// on every fixture, every LibreOffice re-save and every owner file. A Word
/// lock file (`~$name.docx`, which Word leaves beside an open document) is
/// skipped.
///
/// Each difference is printed as `<file>: <line>`, one per line, and a file
/// that cannot be opened or saved as `<file>: <error>`. The exit code is 1
/// on any difference or error, 2 when the arguments are unusable or the
/// input directory holds no `.docx`, and 0 otherwise, as
/// `tool/round_trip_model.dart` does for workbooks.
///
/// CI runs it on the DOCX fixtures, on LibreOffice's re-save of them and on
/// the owner's Word files, then validates the output with
/// `tool/ooxml_validate`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import 'src/docx_serialize.dart';
import 'src/part_compare.dart';

void main(List<String> args) {
  exitCode = roundTripDocx(args, out: stdout, err: stderr);
}

/// Runs the tool on [args] (`<inDir> <outDir>`), writing differences to [out]
/// and usage problems to [err], and returns the exit code.
int roundTripDocx(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 2) {
    err.writeln('Usage: dart run tool/round_trip_docx.dart <inDir> <outDir>');
    return 2;
  }
  final Directory input = Directory(args[0]);
  if (!input.existsSync()) {
    err.writeln('No such directory: ${input.path}');
    return 2;
  }
  final List<File> files = input.listSync().whereType<File>().where((File f) {
    final String name = f.uri.pathSegments.last;
    return name.endsWith('.docx') && !name.startsWith(r'~$');
  }).toList()..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    err.writeln('Nothing to round-trip: no .docx in ${input.path}.');
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
        ? 'All ${files.length} documents round-trip.'
        : '$failed of ${files.length} documents differ.',
  );
  return failed == 0 ? 0 : 1;
}

/// The differences between [file] and its round trip, which is also written
/// to [output]; one line when the model refuses or fails on [file].
List<String> _roundTrip(File file, Directory output, String name) {
  final Uint8List input = file.readAsBytesSync();
  final Uint8List saved;
  try {
    final DocxDocument doc = DocxDocument.open(input);
    doc.body.blocks.length;
    readTypedProperties(doc);
    saved = doc.save().bytes;
  } on DocxReadException catch (e) {
    return <String>['the model refused the document: $e'];
  } on Object catch (e) {
    return <String>['the round trip failed: $e'];
  }
  File('${output.path}/$name').writeAsBytesSync(saved);
  // Encoding the parts of the input is what the unchanged copy of a loaded
  // part does not do (see the library comment).
  try {
    return <String>[
      ...comparePackages(input, saved),
      ...encodedPartDifferences(input),
    ];
  } on Object catch (e) {
    return <String>['the encoded parts failed: $e'];
  }
}
