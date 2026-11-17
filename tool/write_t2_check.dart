/// Writes the documents the owner opens in the T2 Word check (DOCX template
/// fill of sections, decision 0024), to a directory that is created.
///
/// ```bash
/// dart run tool/write_t2_check.dart build/t2
/// ```
///
/// - `t2_values.docx`, `t2_empty.docx` and `t2_nested.docx`: the T2
///   fixtures, the templates filled by `DocxTemplate` with [fillDocxData]
///   and [fillDocxEmptyData], in the locale `FormatLocale.trTR`.
/// - `t2_template.docx` and `t2_nested_template.docx`: the same templates
///   unfilled, to compare with.
/// - `t2_lines_1.docx` and `t2_lines_40.docx`: the invoice template filled
///   with [fillDocxLines] of 1 line, paid, and of 40 lines, unpaid, whose
///   table runs over two pages.
/// - `owner/`: each `template_invoice*.docx` of `test/fixtures/owner/docx/`
///   (the owner's templates, made in Word for Mac) filled three times, with
///   1 line paid, 40 lines unpaid and no line ([fillDocxEmptyData]), as
///   `<name>_1.docx`, `<name>_40.docx` and `<name>_0.docx`, and each other
///   `template_*.docx` filled once with [fillDocxData]. When the folder holds
///   none, the tool says so and still succeeds.
///
/// The steps are in `docs/word-checks.md`, "T2"; the results go there, from
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
  't2_values',
  't2_empty',
  't2_template',
  't2_nested',
  't2_nested_template',
];

/// The options of every fill: Turkish values.
const DocxTemplateOptions _options = DocxTemplateOptions(
  locale: FormatLocale.trTR,
);

void main(List<String> args) {
  exitCode = runT2Check(args, out: stdout, err: stderr);
}

/// Runs the tool with [args], printing each file written to [out] and
/// problems to [err]; returns the exit code. [ownerDir] is where the owner's
/// templates are looked for.
int runT2Check(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  String ownerDir = _ownerFolder,
}) {
  if (args.length != 1) {
    err.writeln('usage: dart run tool/write_t2_check.dart <outDir>');
    return 2;
  }
  try {
    writeT2Check(args.single, ownerDir: ownerDir).forEach(out.writeln);
    if (_ownerTemplates(ownerDir).isEmpty) {
      out.writeln('$ownerDir has no template_*.docx: owner/ is not written');
    }
  } on Object catch (e) {
    err.writeln('write_t2_check failed: $e');
    return 1;
  }
  return 0;
}

/// Writes the T2 check's files to [dir] and returns their paths, in the order
/// of the library comment.
List<String> writeT2Check(String dir, {String ownerDir = _ownerFolder}) {
  final Map<String, DocxFixture> fixtures = <String, DocxFixture>{
    for (final DocxFixture f in docxFixtures()) f.name: f,
  };
  final DocxTemplate invoice = DocxTemplate(t2ValuesTemplate());
  final List<String> paths = <String>[
    for (final String name in _fixtureNames)
      _write('$dir/$name.docx', fixtures[name]!.build().bytes),
    _write(
      '$dir/t2_lines_1.docx',
      invoice.fill(fillDocxLines(1, paid: true), options: _options).bytes,
    ),
    _write(
      '$dir/t2_lines_40.docx',
      invoice.fill(fillDocxLines(40, paid: false), options: _options).bytes,
    ),
  ];
  for (final File file in _ownerTemplates(ownerDir)) {
    final String name = file.uri.pathSegments.last;
    final String stem = name.substring(0, name.length - '.docx'.length);
    final DocxTemplate template = DocxTemplate(file.readAsBytesSync());
    if (stem.startsWith('template_invoice')) {
      for (final (String suffix, Map<String, Object?> data)
          in <(String, Map<String, Object?>)>[
            ('1', fillDocxLines(1, paid: true)),
            ('40', fillDocxLines(40, paid: false)),
            ('0', fillDocxEmptyData()),
          ]) {
        paths.add(
          _write(
            '$dir/owner/${stem}_$suffix.docx',
            template.fill(data, options: _options).bytes,
          ),
        );
      }
    } else {
      paths.add(
        _write(
          '$dir/owner/$name',
          template.fill(fillDocxData(), options: _options).bytes,
        ),
      );
    }
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
