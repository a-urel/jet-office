/// Fills every document of a directory with `DocxTemplate`, so that CI can
/// validate what the template fill saves (decision 0024, T1).
///
/// ```bash
/// dart run tool/fill_docx.dart build/fixtures build/filled-docx-fixtures
/// ```
///
/// For every `*.docx` in the first directory (a Word lock file, `~$name`, is
/// skipped) it opens the bytes with `DocxTemplate`, lists its tags
/// (`DocxTemplate.tags`) and fills it with [fillDocxData], the fixed Turkish
/// data (`firma.unvan`, `firma.adres`, `tarih`, `musteri.ad`, `tutar`,
/// `miktar` and the merge field keys `Ad`, `Müşteri Adı` and `Tarih`), in the
/// locale `FormatLocale.trTR`. It writes the result to `<outDir>/<name>.docx`
/// and reads it back with `DocxDocument`:
///
/// * no fillable tag (a value tag the fill can fill, `problem` `null`, in the
///   body, a header or a footer) whose name the data has is left: none is
///   listed by `DocxTemplate.tagsOf` in the saved file, and its text is in
///   no paragraph of its part, unless a tag the fill cannot fill there has
///   the same text;
/// * every fillable value tag and merge field whose name the data lacks is
///   still there, its text in its part (a merge field listed again), and the
///   fill warned `templateValueMissing` with the tag's text;
/// * no `MERGEFIELD` is left whose name the data has;
/// * `comparePackages` (`tool/src/part_compare.dart`) finds differences only
///   in the main part and in the header and footer parts that held a tag
///   the fill fills (a fillable one whose name the data has; a tag it
///   cannot fill, such as one in a tracked insertion, allows nothing): never
///   in `[Content_Types].xml`, nor in any other part;
/// * and `fill({})`, data that names nothing, gives the input back:
///   `comparePackages` finds no difference at all.
///
/// Each problem is printed as `<file>: <problem>`. The exit code is 1 on any
/// problem (a file that cannot be read is one), 2 when the arguments are
/// unusable or the input directory holds no `.docx`, and 0 otherwise, as
/// `tool/edit_docx.dart` does. The fill's warnings are not problems.
///
/// CI runs it on the DOCX fixtures and on the owner's Word files, and
/// validates both output directories with `tool/ooxml_validate`.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show docxPackageOf, storyPartNameOf;

import 'src/fill_data.dart';
import 'src/part_compare.dart';

export 'src/fill_data.dart' show dataHasPath, fillDocxData;

void main(List<String> args) {
  exitCode = runFillDocx(args, out: stdout, err: stderr);
}

/// The options of every fill: Turkish values, missing tags left as written.
const DocxTemplateOptions fillDocxOptions = DocxTemplateOptions(
  locale: FormatLocale.trTR,
);

/// Runs the tool on [args] (`<inDir> <outDir>`), writing problems to [out]
/// and usage problems to [err], and returns the exit code.
///
/// [corruptForTest], when given, changes the filled bytes of the file it is
/// called with before they are written and checked; the tests use it to
/// prove that the checks fail.
int runFillDocx(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  Uint8List Function(String name, Uint8List saved)? corruptForTest,
}) {
  if (args.length != 2) {
    err.writeln('Usage: dart run tool/fill_docx.dart <inDir> <outDir>');
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
    err.writeln('Nothing to fill: no .docx in ${input.path}.');
    return 2;
  }
  final Directory output = Directory(args[1])..createSync(recursive: true);
  int failed = 0;
  for (final File file in files) {
    final String name = file.uri.pathSegments.last;
    final List<String> problems = _fill(file, output, name, corruptForTest);
    for (final String line in problems) {
      out.writeln('$name: $line');
    }
    if (problems.isNotEmpty) failed++;
  }
  out.writeln(
    failed == 0
        ? 'All ${files.length} documents filled.'
        : '$failed of ${files.length} documents failed.',
  );
  return failed == 0 ? 0 : 1;
}

/// Fills [file], writes the result to [output], and returns the problems.
List<String> _fill(
  File file,
  Directory output,
  String name,
  Uint8List Function(String name, Uint8List saved)? corruptForTest,
) {
  final Uint8List input = file.readAsBytesSync();
  final Map<String, Object?> data = fillDocxData();
  final DocxTemplate template;
  final DocxResult result;
  final DocxResult empty;
  try {
    template = DocxTemplate(input);
    result = template.fill(data, options: fillDocxOptions);
    empty = template.fill(<String, Object?>{}, options: fillDocxOptions);
  } on Object catch (e) {
    return <String>['filling failed: $e'];
  }
  final Uint8List saved = corruptForTest == null
      ? result.bytes
      : corruptForTest(name, result.bytes);
  File('${output.path}/$name').writeAsBytesSync(saved);
  final List<String> problems = <String>[
    for (final String d in comparePackages(input, empty.bytes))
      'fill({}) changed the document: $d',
  ];
  final DocxDocument doc;
  final Map<String, List<String>> texts;
  final List<DocxTemplateTag> left;
  final String mainPart;
  try {
    doc = DocxDocument.open(saved);
    mainPart = docxPackageOf(doc).mainPart;
    texts = _partTexts(doc, mainPart);
    left = DocxTemplate.tagsOf(doc);
  } on Object catch (e) {
    return <String>[...problems, 'reading the filled file failed: $e'];
  }
  problems.addAll(_tagProblems(template.tags, left, texts, result, data));
  problems.addAll(_partProblems(input, saved, template.tags, mainPart, data));
  return problems;
}

/// Whether [data] has the value [tag] names: a value tag's path, or a merge
/// field's whole name.
bool _named(DocxTemplateTag tag, Map<String, Object?> data) {
  final String? name = tag.name;
  if (name == null) return false;
  return switch (tag.kind) {
    DocxTemplateTagKind.mergeField => data.containsKey(name),
    DocxTemplateTagKind.value => dataHasPath(data, name),
    _ => false,
  };
}

/// Whether the fill can fill [tag]: a value tag or merge field of the body,
/// a header or a footer whose form raises no warning.
bool _fillable(DocxTemplateTag tag) =>
    tag.problem == null &&
    tag.location != null &&
    (tag.kind == DocxTemplateTagKind.value ||
        tag.kind == DocxTemplateTagKind.mergeField);

/// The problems of the tags: [before] the template's, [left] the filled
/// file's, [texts] its paragraphs' text per part.
List<String> _tagProblems(
  List<DocxTemplateTag> before,
  List<DocxTemplateTag> left,
  Map<String, List<String>> texts,
  DocxResult result,
  Map<String, Object?> data,
) {
  final List<String> problems = <String>[];
  bool inText(DocxTemplateTag tag) => (texts[tag.part] ?? const <String>[]).any(
    (String text) => text.contains(tag.text),
  );
  // A tag the fill cannot fill keeps its text, which may be a filled one's.
  final Set<(String, String)> kept = <(String, String)>{
    for (final DocxTemplateTag t in before)
      if (!_fillable(t) || !_named(t, data)) (t.part, t.text),
  };
  for (final DocxTemplateTag tag in before) {
    if (!_fillable(tag)) continue;
    if (_named(tag, data)) {
      if (tag.kind == DocxTemplateTagKind.value &&
          !kept.contains((tag.part, tag.text)) &&
          inText(tag)) {
        problems.add('${tag.text} in ${tag.part} was not filled');
      }
    } else {
      final bool warned = result.warnings.any(
        (DocxWarning w) =>
            w.code == DocxWarningCode.templateValueMissing &&
            w.detail == tag.text,
      );
      if (!warned) problems.add('${tag.text} is missing but was not warned');
      final bool present = tag.kind == DocxTemplateTagKind.mergeField
          ? left.any(
              (DocxTemplateTag t) => t.part == tag.part && t.text == tag.text,
            )
          : inText(tag);
      if (!present) {
        problems.add('${tag.text} is missing but is gone from ${tag.part}');
      }
    }
  }
  for (final DocxTemplateTag tag in left) {
    if (!_named(tag, data) || tag.problem != null) continue;
    if (tag.kind == DocxTemplateTagKind.mergeField) {
      problems.add('a MERGEFIELD the data has is left: ${tag.text.trim()}');
    } else if (tag.kind == DocxTemplateTagKind.value &&
        !kept.contains((tag.part, tag.text))) {
      problems.add('a tag the data has is left: ${tag.text} in ${tag.part}');
    }
  }
  return problems;
}

/// The problems of the parts: `comparePackages` of [input] and [saved] may
/// find differences only in [mainPart] and in the parts of [tags] the fill
/// fills: fillable ones whose name the data has.
List<String> _partProblems(
  Uint8List input,
  Uint8List saved,
  List<DocxTemplateTag> tags,
  String mainPart,
  Map<String, Object?> data,
) {
  String entry(String part) => part.startsWith('/') ? part.substring(1) : part;
  final Set<String> allowed = <String>{
    entry(mainPart),
    for (final DocxTemplateTag t in tags)
      if (_fillable(t) && _named(t, data)) entry(t.part),
  };
  return <String>[
    for (final String d in comparePackages(input, saved))
      if (!allowed.contains(_partOf(d))) 'a part outside the allowed set: $d',
  ];
}

/// The part a `comparePackages` line names.
String _partOf(String difference) {
  final int colon = difference.indexOf(': ');
  return colon < 0 ? difference : difference.substring(0, colon);
}

/// The text of every paragraph of the body (under [mainPart]) and of every
/// header and footer part of [doc], by absolute part name; a table's cells'
/// paragraphs are paragraphs too.
Map<String, List<String>> _partTexts(DocxDocument doc, String mainPart) {
  final Map<String, List<String>> texts = <String, List<String>>{
    mainPart: _paragraphTexts(doc.body.blocks),
  };
  for (final DocxSection section in doc.sections) {
    for (final DocxHeaderFooter story in <DocxHeaderFooter>[
      section.header,
      section.firstHeader,
      section.evenHeader,
      section.footer,
      section.firstFooter,
      section.evenFooter,
    ]) {
      final String? part = storyPartNameOf(story);
      if (part == null || texts.containsKey(part)) continue;
      texts[part] = _paragraphTexts(story.blocks);
    }
  }
  return texts;
}

/// The text of every paragraph of [blocks], tables' cells included.
List<String> _paragraphTexts(Iterable<DocxBlock> blocks) => <String>[
  for (final DocxBlock block in blocks)
    ...switch (block) {
      DocxParagraph() => <String>[block.text],
      DocxTable() => <String>[
        for (final DocxTableRow row in block.rows)
          for (final DocxTableCell cell in row.cells)
            ..._paragraphTexts(cell.blocks),
      ],
      _ => const <String>[],
    },
];
