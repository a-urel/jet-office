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
/// for the main part, and [encodedStoryDifferences] for the header and footer
/// parts, and [encodedPropertiesDifferences] for the document properties
/// parts. [readTypedProperties] reads every typed property of every paragraph,
/// run, picture, hyperlink, bookmark, style, list level, section and story and
/// the document properties, so a value the model cannot read throws here and
/// not in a user's program.
///
/// Used by `tool/round_trip_docx.dart` and by the round-trip tests
/// (`test/docx/round_trip_test.dart`, `test/docx/owner_files_test.dart`).
/// Web-safe: no `dart:io`.
///
/// The parts are looked up by their usual names, `word/document.xml`,
/// `word/styles.xml` and `word/numbering.xml`; a package that keeps one
/// elsewhere has it round-tripped as a copy, which the package comparison
/// covers. Header and footer parts are the ones the relationships of
/// `word/document.xml` name; the properties parts are the ones the package's
/// relationships (`_rels/.rels`) name, as the model finds them.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/common/properties_parts.dart';
import 'package:jet_office/src/docx/document_part.dart';
import 'package:jet_office/src/docx/model/inlines.dart' show visitInlines;
import 'package:jet_office/src/docx/model/primitives.dart' show DocxEdits;
import 'package:jet_office/src/docx/numbering_part.dart';
import 'package:jet_office/src/docx/story_part.dart';
import 'package:jet_office/src/docx/styles_part.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:jet_office/src/opc/package.dart' show OpcPackage;
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:xml/xml.dart';

import 'part_compare.dart';

const String _mainName = 'word/document.xml';
const String _stylesName = 'word/styles.xml';
const String _numberingName = 'word/numbering.xml';
const String _mainRelsName = 'word/_rels/document.xml.rels';

/// The elements whose children the model writes in schema order, so a
/// comparison takes them in any order.
const Set<String> _propertyElements = <String>{
  'pPr',
  'rPr',
  'tblPr',
  'trPr',
  'tcPr',
  'sectPr',
};

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
/// The children of each `w:pPr`, `w:rPr`, `w:tblPr`, `w:trPr`, `w:tcPr` and
/// `w:sectPr` compare in any order: the model writes them in schema order, and
/// a document with no edit keeps the file's bytes, so a file whose properties
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
    unordered: _propertyElements,
  );
}

/// The differences between each header and footer part of [docx] and the same
/// part read into the model and encoded, one line each, `'<part>: <what>'`;
/// empty when they mean the same.
///
/// The parts are those the relationships of the main part name as a header or
/// a footer; properties compare in any order, as [encodedMainDifferences] has
/// them. A part the model cannot read is one line, not an exception.
List<String> encodedStoryDifferences(Uint8List docx) {
  final Map<String, Uint8List> entries = _entries(docx);
  final List<String> out = <String>[];
  _storyParts(entries).forEach((String name, bool isHeader) {
    final Uint8List? original = entries[name];
    if (original == null) return;
    final Uint8List encoded;
    try {
      encoded = _join(
        StoryPart.read(
          XmlPullReader(utf8.decode(original)),
          '/$name',
          isHeader: isHeader,
          limits: const DocxReadLimits(),
        ).encode(),
      );
    } on Object catch (e) {
      out.add('$name: the model cannot read the part: $e');
      return;
    }
    out.addAll(
      compareXmlParts(name, original, encoded, unordered: _propertyElements),
    );
  });
  return out;
}

/// The document properties parts of [docx] that are properties parts (their
/// root is the one the model types), by part name (without a leading `/`),
/// each read into its model and encoded again: what the model writes for the
/// part when a property changes. Core, extended and custom, in that order;
/// each is the part the package relationship of its kind names.
///
/// A part that cannot be read throws, as the model would.
Map<String, Uint8List> encodedPropertiesParts(Uint8List docx) {
  final Map<String, Uint8List> entries = _entries(docx);
  return <String, Uint8List>{
    for (final (String name, _PropertiesReader read) in _propertiesParts(
      entries,
    ))
      if (entries[name] case final Uint8List original)
        if (read(name, original) case final Uint8List encoded) name: encoded,
  };
}

/// The differences between the document properties parts of [docx] and the
/// same parts read into the model and encoded ([encodedPropertiesParts]), one
/// line each, `'<part>: <what>'`; empty when they mean the same.
///
/// A part whose root is not a properties part is never written from the
/// model, so it has nothing to compare. A part the model cannot read is one
/// line, not an exception.
List<String> encodedPropertiesDifferences(Uint8List docx) {
  final Map<String, Uint8List> entries = _entries(docx);
  final List<String> out = <String>[];
  for (final (String name, _PropertiesReader read) in _propertiesParts(
    entries,
  )) {
    final Uint8List? original = entries[name];
    if (original == null) continue;
    final Uint8List? encoded;
    try {
      encoded = read(name, original);
    } on Object catch (e) {
      out.add('$name: the model cannot read the part: $e');
      continue;
    }
    if (encoded != null) out.addAll(compareXmlParts(name, original, encoded));
  }
  return out;
}

/// Reads the properties part [name], whose bytes are [original], and encodes
/// it; `null` for a part whose root the model does not type.
typedef _PropertiesReader =
    Uint8List? Function(String name, Uint8List original);

/// The properties parts the package relationships of [entries] name, each
/// with its reader: the first relationship of each kind, as the model takes.
List<(String, _PropertiesReader)> _propertiesParts(
  Map<String, Uint8List> entries,
) {
  final Uint8List? rels = entries['_rels/.rels'];
  if (rels == null) return const <(String, _PropertiesReader)>[];
  final List<XmlElement> relationships = XmlDocument.parse(
    utf8.decode(rels),
  ).rootElement.childElements.toList();
  final Uri root = Uri.parse('/');
  void warn(String element) {}
  final List<(String, _PropertiesReader)> kinds = <(String, _PropertiesReader)>[
    (
      PropertyKind.core.relationshipType,
      (String name, Uint8List bytes) {
        final CoreProperties part = CoreProperties.read(
          _reader(bytes),
          const _Limits(),
          name,
          warn,
        );
        return part.isTyped ? _join(part.encode()) : null;
      },
    ),
    (
      PropertyKind.app.relationshipType,
      (String name, Uint8List bytes) {
        final AppProperties part = AppProperties.read(
          _reader(bytes),
          const _Limits(),
          name,
          warn,
        );
        return part.isTyped ? _join(part.encode()) : null;
      },
    ),
    (
      PropertyKind.custom.relationshipType,
      (String name, Uint8List bytes) {
        final CustomProperties part = CustomProperties.read(
          _reader(bytes),
          const _Limits(),
          name,
          warn,
        );
        return part.isTyped ? _join(part.encode()) : null;
      },
    ),
  ];
  return <(String, _PropertiesReader)>[
    for (final (String type, _PropertiesReader read) in kinds)
      if (relationships
              .where(
                (XmlElement r) =>
                    r.getAttribute('Type') == type &&
                    r.getAttribute('TargetMode') != 'External',
              )
              .firstOrNull
          case final XmlElement r)
        (root.resolve(r.getAttribute('Target') ?? '').path.substring(1), read),
  ];
}

XmlPullReader _reader(Uint8List bytes) => XmlPullReader(utf8.decode(bytes));

/// The bounds a properties part is read within: none a real file reaches.
final class _Limits implements PropertiesSource {
  const _Limits();

  @override
  OpcPackage get package =>
      throw UnsupportedError('A part is read here without its package.');

  @override
  int get maxChildren => 1 << 30;

  @override
  int get maxTextLength => 1 << 30;

  @override
  T guard<T>(String part, T Function() body) => body();

  @override
  XmlPullReader openXml(String part) =>
      throw UnsupportedError('A part is read here without its package.');

  @override
  Never limitExceeded(String part, String message) =>
      throw StateError('$part: $message');
}

/// The parts the main part's relationships name as a header (`true`) or a
/// footer (`false`), by part name.
Map<String, bool> _storyParts(Map<String, Uint8List> entries) {
  final Uint8List? rels = entries[_mainRelsName];
  if (rels == null) return const <String, bool>{};
  final Uri main = Uri.parse('/$_mainName');
  return <String, bool>{
    for (final XmlElement r in XmlDocument.parse(
      utf8.decode(rels),
    ).rootElement.childElements)
      if (r.getAttribute('Type') case final String type
          when type.endsWith('/header') || type.endsWith('/footer'))
        main.resolve(r.getAttribute('Target') ?? '').path.substring(1): type
            .endsWith('/header'),
  };
}

/// Reads every typed property of [doc]: of each paragraph of the body, in the
/// cells of its tables too, and each of its runs and fields, of each table
/// (and its grid), row and cell, of each section and of the blocks of each
/// story it has as its own, of the document defaults and each style, of
/// each level of each abstract list definition, and the document properties.
/// The typed members of each picture, hyperlink and bookmark count too.
/// Returns how many were set.
///
/// A value the model cannot read throws. The styles, numbering and settings
/// parts and every story a section names are loaded by this.
int readTypedProperties(DocxDocument doc) {
  int set = _blocks(doc.body.blocks) + _properties(doc.properties);
  set += _count(<Object?>[doc.evenAndOddHeaders ? true : null]);
  for (final DocxSection section in doc.sections) {
    set += _section(section);
  }
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
          set += _inline(inline);
          visitInlines(inline, (DocxInline held) {
            if (held is DocxRun) {
              set += _run(held.properties);
              for (final DocxRunContent content in held.content) {
                if (content is DocxPicture) set += _picture(content);
              }
            }
          });
        }
      case DocxTable():
        set +=
            _table(block.properties) + _count(<Object?>[block.gridColumnsPt]);
        for (final DocxTableRow row in block.rows) {
          set += _row(row.properties);
          for (final DocxTableCell cell in row.cells) {
            set += _cell(cell.properties) + _blocks(cell.blocks);
          }
        }
      case DocxOpaqueBlock():
        break;
    }
  }
  return set;
}

/// Reads the typed members of [inline] when it is a field, a hyperlink or a
/// bookmark mark, and of the fields and hyperlinks it holds.
int _inline(DocxInline inline) => switch (inline) {
  DocxField() =>
    _count(<Object?>[inline.instruction, inline.text]) +
        inline.result.fold(0, (int n, DocxInline i) => n + _inline(i)),
  DocxHyperlink() =>
    _count(<Object?>[inline.url, inline.anchor, inline.tooltip, inline.text]) +
        inline.inlines.fold(0, (int n, DocxInline i) => n + _inline(i)),
  DocxBookmarkStart() => _count(<Object?>[inline.id, inline.name]),
  DocxBookmarkEnd() => _count(<Object?>[inline.id]),
  DocxRun() || DocxOpaqueInline() => 0,
};

/// Reads the typed members of [picture], its image too.
int _picture(DocxPicture picture) => _count(<Object?>[
  picture.widthPt,
  picture.heightPt,
  picture.name,
  picture.description,
  picture.image,
]);

/// Reads the document properties [p]: every field, and each custom one.
int _properties(OfficeProperties p) =>
    _count(<Object?>[
      p.title,
      p.subject,
      p.creator,
      p.keywords,
      p.description,
      p.lastModifiedBy,
      p.revision,
      p.category,
      p.company,
      p.manager,
      p.contentStatus,
      p.application,
      p.created,
      p.modified,
    ]) +
    p.custom.length;

/// Reads the values of [s] and the blocks of the stories it has as its own.
int _section(DocxSection s) {
  int set = _count(<Object?>[
    s.pageSize,
    s.margins,
    s.columns,
    s.start,
    s.titlePage ? true : null,
    s.verticalAlignment,
    s.pageNumbering,
    s.lineNumbering,
    s.textWidthPt,
  ]);
  for (final DocxHeaderFooter story in <DocxHeaderFooter>[
    s.header,
    s.firstHeader,
    s.evenHeader,
    s.footer,
    s.firstFooter,
    s.evenFooter,
  ]) {
    if (!story.isInherited) set += _blocks(story.blocks);
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

int _table(DocxTableProperties t) => _count(<Object?>[
  t.style,
  t.width,
  t.layout,
  t.alignment,
  t.indentationPt,
  t.borders,
  t.cellMargins,
  t.look,
]);

int _row(DocxTableRowProperties r) =>
    _count(<Object?>[r.height, r.cantSplit, r.repeatAsHeader]);

int _cell(DocxTableCellProperties c) => _count(<Object?>[
  c.width,
  c.gridSpan,
  c.verticalMerge,
  c.verticalAlignment,
  c.shading,
  c.borders,
  c.textDirection,
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
