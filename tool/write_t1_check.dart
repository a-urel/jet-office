/// Writes the documents the owner opens in the T1 Word check (DOCX template
/// fill of values, decision 0024), to a directory that is created.
///
/// ```bash
/// dart run tool/write_t1_check.dart build/t1
/// ```
///
/// - `t1_values.docx` and `t1_merge_fields.docx`: the templates of the T1
///   fixtures filled by `DocxTemplate` with [fillDocxData], in the locale
///   `FormatLocale.trTR`.
/// - `t1_template.docx` and `t1_merge_fields_template.docx`: the same
///   templates unfilled, as Word for Mac would write them, to compare with.
/// - `owner/`: each `template_*.docx` of `test/fixtures/owner/docx/` (the
///   owner's templates, made in Word for Mac) filled with [fillDocxData]. When
///   the folder holds none, the tool says so and still succeeds.
///
/// The steps are in `docs/word-checks.md`, "T1"; the results go there, from
/// the owner only. Run from the repository root. Exit code 2 on unusable
/// arguments, 1 on any error.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../test/fixtures/docx_fixtures.dart';
import 'src/fill_data.dart';

/// The folder of the owner's Word files.
const String _ownerFolder = 'test/fixtures/owner/docx';

/// The fixtures written as built, in order.
const List<String> _fixtureNames = <String>[
  't1_values',
  't1_merge_fields',
  't1_template',
  't1_merge_fields_template',
];

void main(List<String> args) {
  exitCode = runT1Check(args, out: stdout, err: stderr);
}

/// Runs the tool with [args], printing each file written to [out] and
/// problems to [err]; returns the exit code. [ownerDir] is where the owner's
/// templates are looked for.
int runT1Check(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  String ownerDir = _ownerFolder,
}) {
  if (args.length != 1) {
    err.writeln('usage: dart run tool/write_t1_check.dart <outDir>');
    return 2;
  }
  try {
    writeT1Check(args.single, ownerDir: ownerDir).forEach(out.writeln);
    if (_ownerTemplates(ownerDir).isEmpty) {
      out.writeln('$ownerDir has no template_*.docx: owner/ is not written');
    }
  } on Object catch (e) {
    err.writeln('write_t1_check failed: $e');
    return 1;
  }
  return 0;
}

/// Writes the T1 check's files to [dir] and returns their paths, in the order
/// of the library comment.
List<String> writeT1Check(String dir, {String ownerDir = _ownerFolder}) {
  final Map<String, DocxFixture> fixtures = <String, DocxFixture>{
    for (final DocxFixture f in docxFixtures()) f.name: f,
  };
  final List<String> paths = <String>[
    for (final String name in _fixtureNames)
      _write('$dir/$name.docx', fixtures[name]!.build().bytes),
  ];
  for (final File file in _ownerTemplates(ownerDir)) {
    final String name = file.uri.pathSegments.last;
    final DocxResult filled = DocxTemplate(file.readAsBytesSync()).fill(
      fillDocxData(),
      options: const DocxTemplateOptions(locale: FormatLocale.trTR),
    );
    paths.add(_write('$dir/owner/$name', filled.bytes));
  }
  return paths;
}

/// The owner's `template_*.docx` files of [ownerDir], by name; a Word lock
/// file (`~$name`) is not one.
List<File> _ownerTemplates(String ownerDir) {
  final Directory dir = Directory(ownerDir);
  if (!dir.existsSync()) return <File>[];
  final List<File> files = <File>[
    for (final FileSystemEntity e in dir.listSync())
      if (e is File &&
          e.uri.pathSegments.last.startsWith('template_') &&
          e.path.endsWith('.docx'))
        e,
  ]..sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

String _write(String path, Uint8List bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  return path;
}
