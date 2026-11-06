/// What a DOCX round trip must do to prove the model serializes the main,
/// styles and numbering parts, and reads the typed properties of a document.
///
/// New in jet_office. A loaded part that nothing changed is saved as it was
/// read, byte for byte (`DocxDocument.save`), so opening the part in a round
/// trip no longer runs the encoder that writes it. These helpers do run it:
/// [encodedParts] reads the styles and numbering parts of a file into their
/// models and encodes them, and [encodedPartDifferences] compares that with
/// the part in the file by `compareXmlParts`, the meaning-based comparison
/// of `tool/src/part_compare.dart`; [encodedMainDifferences] does the same
/// for the main part. [readTypedProperties] reads
/// every typed property of every paragraph, run, style and list level, so a
/// value the model cannot read throws here and not in a user's program.
///
/// Used by `tool/round_trip_docx.dart` and by the round-trip tests
/// (`test/docx/round_trip_test.dart`, `test/docx/owner_files_test.dart`).
/// Web-safe: no `dart:io`.
///
/// The parts are looked up by their usual names, `word/document.xml`,
/// `word/styles.xml` and `word/numbering.xml`; a package that keeps one
/// elsewhere has it round-tripped as a copy, which the package comparison
/// covers.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/document_part.dart';
import 'package:jet_office/src/docx/model/primitives.dart' show DocxEdits;
import 'package:jet_office/src/docx/numbering_part.dart';
import 'package:jet_office/src/docx/styles_part.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:jet_office/src/xml/xml_pull_reader.dart';

import 'part_compare.dart';

const String _mainName = 'word/document.xml';
const String _stylesName = 'word/styles.xml';
const String _numberingName = 'word/numbering.xml';

/// The styles and numbering parts of the DOCX file [docx] that it has,
/// by part name (without a leading `/`), each read into its model and
/// encoded again: what the model writes for the part when it is changed.
///
/// A part that cannot be read throws, as the model would.
Map<String, Uint8List> encodedParts(Uint8List docx) {
  final Map<String, Uint8List> entries = _entries(docx);
  return <String, Uint8List>{
    for (final String name in _partNames)
      if (entries[name] case final Uint8List original)
        name: _encode(name, original),
  };
}

const List<String> _partNames = <String>[_stylesName, _numberingName];

/// [original], the bytes of the part [name], read into its model and encoded.
Uint8List _encode(String name, Uint8List original) {
  final XmlPullReader reader = XmlPullReader(utf8.decode(original));
  final DocxEdits edits = DocxEdits();
  return _join(
    (name == _stylesName
        ? StylesPart.read(reader, '/$name', edits).encode()
        : NumberingPart.read(reader, '/$name', edits).encode()),
  );
}

/// The differences between the styles and numbering parts of [docx] and the
/// same parts read into the model and encoded ([encodedParts]), one line
/// each, `'<part>: <what>'`; empty when they mean the same.
///
/// A part the model cannot read is one line, not an exception.
List<String> encodedPartDifferences(Uint8List docx) {
  final Map<String, Uint8List> entries = _entries(docx);
  final List<String> out = <String>[];
  for (final String name in _partNames) {
    final Uint8List? original = entries[name];
    if (original == null) continue;
    final Uint8List encoded;
    try {
      encoded = _encode(name, original);
    } on Object catch (e) {
      out.add('$name: the model cannot read the part: $e');
      continue;
    }
    out.addAll(compareXmlParts(name, original, encoded));
  }
  return out;
}

/// The differences between the main part of [docx] and the same part read
/// into the model and encoded, one line each, `'<part>: <what>'`; empty when
/// they mean the same.
///
/// The children of each `w:pPr`, `w:rPr`, `w:tblPr`, `w:trPr` and `w:tcPr`
/// compare in any order: the model writes them in schema order, and a
/// document with no edit keeps the file's bytes, so a file whose properties
/// are out of order loses nothing. A part the model cannot read is one line,
/// not an exception.
List<String> encodedMainDifferences(Uint8List docx) {
  final Uint8List? original = _entries(docx)[_mainName];
  if (original == null) return const <String>[];
  final Uint8List encoded;
  try {
    encoded = _join(
      DocumentPart.read(
        XmlPullReader(utf8.decode(original)),
        DocxWarningCollector(),
        '/$_mainName',
        limits: const DocxReadLimits(),
      ).encode(),
    );
  } on Object catch (e) {
    return <String>['$_mainName: the model cannot read the part: $e'];
  }
  return compareXmlParts(
    _mainName,
    original,
    encoded,
    unordered: const <String>{'pPr', 'rPr', 'tblPr', 'trPr', 'tcPr'},
  );
}

/// Reads every typed property of [doc]: of each paragraph of the body, in the
/// cells of its tables too, and each of its runs, of the document defaults and each style, and of each
/// level of each abstract list definition. Returns how many were set.
///
/// A value the model cannot read throws. The styles and numbering parts are
/// loaded by this.
int readTypedProperties(DocxDocument doc) {
  int set = _blocks(doc.body.blocks);
  final DocxStyles styles = doc.styles;
  set += _paragraph(styles.defaults.paragraphProperties);
  set += _run(styles.defaults.runProperties);
  for (final DocxStyle style in styles.styles) {
    set += _count(<Object?>[
      style.name,
      style.basedOn,
      style.next,
      style.link,
      style.uiPriority,
      style.quickFormat ? true : null,
    ]);
    set += _paragraph(style.paragraphProperties);
    set += _run(style.runProperties);
  }
  final DocxNumbering numbering = doc.numbering;
  for (final DocxAbstractNumbering abstract in numbering.abstractNumberings) {
    for (final DocxNumberingLevel level in abstract.levels) {
      set += _count(<Object?>[
        level.format,
        level.text,
        level.start,
        level.alignment,
        level.indentation,
        level.bulletFont,
      ]);
    }
  }
  for (final DocxNumberingInstance instance in numbering.instances) {
    for (final DocxLevelOverride o in instance.overrides) {
      set += _count(<Object?>[o.startOverride]);
    }
  }
  return set;
}

/// Reads every typed property of the paragraphs of [blocks], and of those in
/// the cells of its tables.
int _blocks(List<DocxBlock> blocks) {
  int set = 0;
  for (final DocxBlock block in blocks) {
    switch (block) {
      case DocxParagraph():
        set += _paragraph(block.properties);
        for (final DocxInline inline in block.inlines) {
          if (inline is DocxRun) set += _run(inline.properties);
        }
      case DocxTable():
        for (final DocxTableRow row in block.rows) {
          for (final DocxTableCell cell in row.cells) {
            set += _blocks(cell.blocks);
          }
        }
      case DocxOpaqueBlock():
        break;
    }
  }
  return set;
}

int _paragraph(DocxParagraphProperties p) => _count(<Object?>[
  p.style,
  p.alignment,
  p.indentation,
  p.spacing,
  p.keepWithNext,
  p.keepLines,
  p.pageBreakBefore,
  p.widowControl,
  p.outlineLevel,
  p.borders,
  p.shading,
  p.tabs,
  p.numbering,
]);

int _run(DocxRunProperties r) => _count(<Object?>[
  r.style,
  r.fonts,
  r.bold,
  r.italic,
  r.caps,
  r.smallCaps,
  r.strike,
  r.doubleStrike,
  r.color,
  r.characterSpacingPt,
  r.sizePt,
  r.highlight,
  r.underline,
  r.shading,
  r.verticalAlign,
  r.language,
]);

int _count(List<Object?> values) =>
    values.where((Object? v) => v != null).length;

Map<String, Uint8List> _entries(Uint8List docx) => <String, Uint8List>{
  for (final ArchiveFile file in ZipDecoder().decodeBytes(docx).files)
    if (file.isFile) file.name: Uint8List.fromList(file.content),
};

Uint8List _join(List<Uint8List> chunks) =>
    Uint8List.fromList(<int>[for (final Uint8List c in chunks) ...c]);
