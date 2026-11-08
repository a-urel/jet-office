// A large Word document made from a small one, for the benchmark
// (`benchmark/docx_model_benchmark_test.dart`) and `tool/write_large_docx.dart`.
// Not ported from Quds. It imports package:archive as the other test helpers
// do (the archive rule covers `lib/` only) and no `dart:io`, so it runs on the
// web.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart'
    show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
import 'package:jet_office/jet_office.dart';

/// The main part of a Word package.
const String largeDocumentMainPart = 'word/document.xml';

/// What [scaledLongDocx] made: the package bytes and the sizes the benchmark
/// prints.
typedef ScaledDocument = ({
  Uint8List bytes,
  int sourceParagraphs,
  int mainXmlBytes,
});

/// [longDocx], a Word file, with the children of its body, but for the final
/// `w:sectPr`, repeated until the body holds at least [paragraphs] paragraphs
/// (the paragraphs among the body's blocks, as the model counts them), by
/// string surgery on `word/document.xml`; every other part is as it was.
///
/// Word's markup is kept with two changes, so that no copy repeats what Word
/// makes unique: the `w:id` of every bookmark (shifted by 1,000 a copy) and
/// the number in each `_Toc` name (suffixed with the copy number, so the
/// `PAGEREF` fields and hyperlink anchors that point to them follow) differ
/// per copy, and the `w14:paraId` and `w14:textId` attributes are dropped (they
/// are optional). Other ids, such as `wp:docPr` ids and `_Ref` names, may
/// repeat across copies, which the model does not check.
///
/// Throws [ArgumentError] when [paragraphs] is below 1 or the file has no main
/// part, no `w:body` or no body paragraph, and [StateError] when the main
/// part has no final `w:sectPr` after the body's start.
ScaledDocument scaledLongDocx(Uint8List longDocx, {int paragraphs = 40000}) {
  if (paragraphs < 1) {
    throw ArgumentError.value(paragraphs, 'paragraphs', 'must be at least 1');
  }
  final Archive input = ZipDecoder().decodeBytes(longDocx);
  final ArchiveFile? main = input.findFile(largeDocumentMainPart);
  if (main == null) {
    throw ArgumentError.value(longDocx, 'longDocx', 'has no main part');
  }
  final String xml = utf8.decode(main.content);
  final int perCopy = DocxDocument.open(
    longDocx,
  ).body.blocks.whereType<DocxParagraph>().length;
  if (perCopy == 0) {
    throw ArgumentError.value(longDocx, 'longDocx', 'has no paragraph');
  }
  final int start = xml.indexOf('<w:body>') + '<w:body>'.length;
  final int end = xml.lastIndexOf('<w:sectPr');
  if (start < '<w:body>'.length || end < start) {
    throw StateError('The main part has no body with a final w:sectPr.');
  }
  final String children = xml.substring(start, end);
  final int copies = (paragraphs / perCopy).ceil();
  final StringBuffer out = StringBuffer(xml.substring(0, start));
  for (int k = 0; k < copies; k++) {
    out.write(_copy(children, k));
  }
  out.write(xml.substring(end));
  final String scaledXml = out.toString();
  final Archive output = Archive();
  for (final ArchiveFile file in input) {
    output.add(
      file.name == largeDocumentMainPart
          ? ArchiveFile.bytes(file.name, utf8.encode(scaledXml))
          : ArchiveFile.bytes(file.name, file.content),
    );
  }
  return (
    bytes: Uint8List.fromList(ZipEncoder().encode(output)),
    sourceParagraphs: perCopy,
    mainXmlBytes: utf8.encode(scaledXml).length,
  );
}

final RegExp _bookmarkId = RegExp(
  r'(<w:bookmark(?:Start|End) [^>]*?w:id=")(\d+)',
);
final RegExp _tocName = RegExp(r'_Toc(\d+)');
final RegExp _wordIds = RegExp(r' w14:(?:paraId|textId)="[^"]*"');

/// Copy number [k] of [children]: bookmark ids shifted by 1,000 a copy, `_Toc`
/// names suffixed with the copy number from the second copy on, and no
/// `w14:paraId` or `w14:textId`.
String _copy(String children, int k) {
  String text = children.replaceAll(_wordIds, '');
  if (k == 0) return text;
  text = text.replaceAllMapped(
    _bookmarkId,
    (Match m) => '${m[1]}${int.parse(m[2]!) + k * 1000}',
  );
  return text.replaceAllMapped(_tocName, (Match m) => '_Toc${m[1]}_$k');
}
