/// The document model: open a DOCX file, read and edit its body, and save
/// with nothing lost.
///
/// Not ported from Quds; written for jet_office. It follows the workbook
/// model (`lib/src/xlsx/model/xlsx_workbook.dart`) without sharing its code.
///
/// [DocxDocument.open] reads the package skeleton only: the content types,
/// the root relationships and the main document part's name
/// ([DocxPackage]). It checks every other entry's size and CRC-32 without
/// keeping or parsing it, so a damaged entry is refused at `open` instead of
/// at save. The main document part and its relationships load on the first
/// access to [DocxDocument.body] (spec §4.3).
///
/// Saving writes every part of the package in its order (spec §4.3): a part
/// the model never loaded from its original bytes (layer 1), so a body never
/// accessed is copied as it was, even when it would not parse; a loaded
/// part from the model (layer 2), with what the model does not type kept as
/// written inside it (layer 3).
///
/// Every edit runs in a transaction of the document's `ChangeLog`
/// (`primitives.dart`), so an edit that fails leaves the body as it was.
/// Everything that leaves [DocxDocument.open], [DocxDocument.body],
/// [DocxDocument.save] or [DocxDocument.saveTo] because of the file's
/// content is a [DocxReadException].
///
/// @docImport 'model/inlines.dart';
library;

import 'dart:collection';
import 'dart:typed_data';

import '../opc/change_log.dart';
import '../opc/ooxml.dart' show ContentType, RelType;
import '../xml/xml_pull_reader.dart';
import '../zip/archive_adapter.dart';
import 'blank_document.dart';
import 'document_part.dart';
import 'docx_package.dart';
import 'model/blocks.dart';
import 'model/numbering.dart';
import 'model/primitives.dart' as primitives;
import 'model/primitives.dart' show DocxEdits;
import 'model/styles.dart';
import 'numbering_part.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'related_part.dart';
import 'styles_part.dart';
import 'warnings.dart';

/// The edits of [document]: its change log and the sink of its body's
/// paragraphs, for tests (`DocxEdits.afterRecord` is the hook that makes an
/// edit fail).
DocxEdits editsOf(DocxDocument document) => document._edits;

/// The change log of [document], for tests.
ChangeLog changeLogOf(DocxDocument document) => document._edits.log;

/// Whether the body of [document] has been loaded, for tests.
bool isBodyLoaded(DocxDocument document) => document._body != null;

/// Whether the styles of [document] have been loaded, for tests.
bool isStylesLoaded(DocxDocument document) => document._styles != null;

/// Whether the numbering of [document] has been loaded, for tests.
bool isNumberingLoaded(DocxDocument document) => document._numbering != null;

/// A Word document held in memory: opened from a DOCX file, read and
/// changed block by block, and saved.
///
/// ```dart
/// final DocxDocument doc = DocxDocument.open(bytes);
/// doc.body.addParagraph('Toplam: 1.234,50 ₺');
/// final DocxResult result = doc.save();
/// ```
///
/// Opening then saving with no change gives a file whose every part means
/// what the input's did; a change touches only what it changes. Every call
/// is synchronous.
final class DocxDocument {
  /// A new document like Word for Mac's blank one: one empty paragraph, an
  /// A4 portrait section, Aptos at 12 pt through the theme, and Word's
  /// default styles (spec 4.5).
  ///
  /// It carries no locale: the theme font language and every default
  /// language are `en-US`, and the decimal symbol and list separator are
  /// left to the reader's system. It has no document properties.
  factory DocxDocument() => DocxDocument.open(blankDocumentBytes());

  /// Opens the DOCX file [bytes] within [limits].
  ///
  /// Reads only the package skeleton and finds the main document part; the
  /// body loads on first access to [body]. Every other entry is inflated
  /// once and checked against its declared size and CRC-32, then dropped,
  /// so that saving cannot meet a damaged part. Throws an [ArgumentError]
  /// when a limit is below 1, and a [DocxReadException] when the file is
  /// not a readable DOCX: not a ZIP, damaged, encrypted, a legacy `.doc`,
  /// Strict OOXML, a workbook or a presentation, without a main document
  /// part, or past one of the [DocxReadLimits].
  factory DocxDocument.open(
    Uint8List bytes, {
    DocxReadLimits limits = const DocxReadLimits(),
  }) {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final DocxPackage package = DocxPackage(bytes, limits, warnings);
    package.guard(package.mainPart, package.package.verifyEntries);
    return DocxDocument._(package, warnings);
  }

  DocxDocument._(this._package, this._loadWarnings)
    : _warnings = _loadWarnings.warnings {
    _edits.styleResolver = (String id, DocxStyleType type) =>
        resolveStyleId(styles, id, type);
  }

  final DocxPackage _package;

  /// What was repaired while opening and loading parts.
  final DocxWarningCollector _loadWarnings;

  final DocxEdits _edits = DocxEdits();

  /// The main document part, once the body is loaded.
  DocumentPart? _part;
  DocxBody? _body;

  /// The styles part and where it is, once the styles are loaded.
  StylesPart? _stylesPart;
  RelatedPart? _stylesSlot;
  DocxStyles? _styles;

  /// The numbering part and where it is, once the numbering is loaded.
  NumberingPart? _numberingPart;
  RelatedPart? _numberingSlot;
  DocxNumbering? _numbering;

  List<DocxWarning> _warnings;

  /// The document's body, the content of `w:body`.
  ///
  /// The main document part loads on the first access, with its
  /// relationships. Throws a [DocxReadException] when it cannot be read
  /// (malformed XML, a damaged relationships part, or text past
  /// [DocxReadLimits.maxTextLength]); nothing is loaded then, so the next
  /// access throws again and a save copies the part as it was.
  DocxBody get body => _body ?? _loadBody();

  /// The document's styles and document defaults, from the styles part.
  ///
  /// The part, found through the main part's relationship wherever it
  /// lives, loads on the first access, or when a style is set on content of
  /// the document (the id set is resolved against it, and such a set or
  /// insertion throws what this does); until then a save copies it byte for
  /// byte. A document without one has empty styles, and gains the part at
  /// save once a style or a default is set in it. Throws a
  /// [DocxReadException] naming the part when it cannot be read (malformed
  /// XML, a root that is not `w:styles`, or a damaged relationships part of
  /// the main part); nothing is loaded then, so the next access throws
  /// again and a save copies the part as it was.
  DocxStyles get styles => _styles ?? _loadStyles();

  /// The document's lists, from the numbering part: the abstract
  /// definitions and the instances paragraphs name.
  ///
  /// The part, found through the main part's relationship wherever it
  /// lives, loads on the first access, or at save when a paragraph's
  /// numbering was set (to report a list the document lacks); until then a
  /// save copies it byte for byte. A document without one has an empty
  /// numbering, and gains the part at save once it holds a definition.
  /// Throws a [DocxReadException] naming the part when it cannot be read
  /// (malformed XML, a root that is not `w:numbering`, or a damaged
  /// relationships part of the main part); nothing is loaded then, so the
  /// next access throws again and a save copies the part as it was.
  DocxNumbering get numbering => _numbering ?? _loadNumbering();

  /// What was repaired while opening and loading the document, followed by
  /// what the last [save] or [saveTo] repaired, in first-occurrence order.
  ///
  /// Before the first save it holds what opening and loading repaired, such
  /// as a main part without a content type. A save reports again what it
  /// repairs, such as the characters removed from a run's text, so the list
  /// reflects the document as last saved. Unmodifiable.
  List<DocxWarning> get warnings => _warnings;

  /// Saves the document and returns the file with the warnings of this
  /// save, which [warnings] then holds too.
  ///
  /// A part never loaded is copied from the file, and a loaded one is
  /// written from the model. Throws a [DocxReadException] if a part of the
  /// file cannot be read after all.
  DocxResult save() {
    final ZipWriter zip = ZipWriter();
    _write(zip);
    return DocxResult._(zip.close()!, _warnings);
  }

  /// Saves the document to [sink], as [save] does, and closes it.
  ///
  /// The chunks are those of [save]'s bytes. Throws as [save] does, and
  /// rethrows what the sink throws; the sink holds an incomplete file then.
  void saveTo(Sink<List<int>> sink) {
    final ZipWriter zip = ZipWriter(sink: sink);
    _write(zip);
    zip.close();
  }

  DocxBody _loadBody() {
    final DocxPackage package = _package;
    final String main = package.mainPart;
    // The relationships load with the part, so that a damaged one is
    // reported as the body's failure; a relationship whose target is
    // missing (a header, say) is kept as written.
    package.guard(
      relationshipsPartOf(main),
      () => package.package.relationshipsOf(main),
    );
    final DocumentPart part = package.guard(
      main,
      () => DocumentPart.read(
        package.openXml(main),
        _loadWarnings,
        main,
        limits: package.limits,
      ),
    );
    final DocxBody body = DocxBody._(_edits, part.blocks);
    primitives.adoptBlocks(_edits, body, part.blocks);
    package.package.setContent(main, part);
    _part = part;
    return _body = body;
  }

  DocxStyles _loadStyles() {
    final RelatedPart slot = RelatedPart.find(
      _package,
      source: _package.mainPart,
      relationshipType: RelType.styles,
      defaultName: '/word/styles.xml',
      contentType: ContentType.wmlStyles,
    );
    final StylesPart part = slot.exists
        ? slot.load((XmlPullReader r) => StylesPart.read(r, slot.name, _edits))
        : StylesPart.empty(_edits);
    _stylesSlot = slot;
    _stylesPart = part;
    return _styles = part.styles;
  }

  DocxNumbering _loadNumbering() {
    final RelatedPart slot = RelatedPart.find(
      _package,
      source: _package.mainPart,
      relationshipType: RelType.numbering,
      defaultName: '/word/numbering.xml',
      contentType: ContentType.wmlNumbering,
    );
    final NumberingPart part = slot.exists
        ? slot.load(
            (XmlPullReader r) => NumberingPart.read(r, slot.name, _edits),
          )
        : NumberingPart.empty(_edits);
    _numberingSlot = slot;
    _numberingPart = part;
    return _numbering = part.numbering;
  }

  /// Whether the document defines a list instance, for the check of the
  /// lists paragraphs were put in through the API (plan Ruling 8); `null`
  /// when no paragraph of the body was, or the numbering part cannot be
  /// read (nothing is reported then).
  bool Function(int numId)? _listCheck() {
    final DocxBody? body = _body;
    if (body == null ||
        !body._blocks.any(
          (DocxBlock b) => b is DocxParagraph && listSetOf(b) != null,
        )) {
      return null;
    }
    final DocxNumbering numbering;
    try {
      numbering = this.numbering;
    } on DocxReadException {
      // A broken part is copied as it was, and its lists are unknown.
      return null;
    }
    return numberingInstanceIds(numbering).contains;
  }

  void _write(ZipWriter zip) {
    final DocxPackage package = _package;
    final DocumentPart? main = _part;
    if (main != null) {
      main.listDefined = _listCheck();
      // Only a style set through the API is reported, and setting one
      // loaded the styles.
      final DocxStyles? styles = _styles;
      main.styleDefined = styles == null
          ? null
          : (String id, DocxStyleType type) => definesStyle(styles, id, type);
    }
    // A styles part the document lacked is added once it holds something
    // (plan Ruling 7); after that it is a part like the others.
    final StylesPart? stylesPart = _stylesPart;
    if (stylesPart != null && stylesPart.holdsSomething) {
      _stylesSlot!.create(stylesPart);
    }
    final NumberingPart? numbering = _numberingPart;
    if (numbering != null && numbering.holdsSomething) {
      _numberingSlot!.create(numbering);
    }
    package.guard(package.mainPart, () => package.package.writeTo(zip));
    final DocumentPart? part = _part;
    _warnings = List<DocxWarning>.unmodifiable(<DocxWarning>[
      ..._loadWarnings.warnings,
      if (part != null) ...part.encodeWarnings.warnings,
    ]);
  }
}

/// The body of a document, the content of `w:body`: its blocks, in order.
///
/// Paragraphs ([DocxParagraph]) are typed; every other block, such as a
/// table or a content control, is a [DocxOpaqueBlock] kept as written. The
/// section properties of the last section belong to the body, not to its
/// blocks, and are kept as written.
///
/// A block is in at most one body at a time. Each edit is atomic: one that
/// throws changes nothing.
final class DocxBody {
  DocxBody._(this._edits, this._blocks);

  final DocxEdits _edits;
  final List<DocxBlock> _blocks;
  late final List<DocxBlock> _blocksView = UnmodifiableListView<DocxBlock>(
    _blocks,
  );

  /// The blocks in order. The list cannot be modified, and shows later
  /// edits; use [addParagraph], [insertBlock], [removeBlockAt] and
  /// [replaceBlockAt].
  List<DocxBlock> get blocks => _blocksView;

  /// Appends a new paragraph that holds [text] and returns it. The text is
  /// split and scrubbed as [DocxRun.text] is when set; the empty text gives
  /// a paragraph without runs.
  DocxParagraph addParagraph([String text = '']) {
    final DocxParagraph paragraph = DocxParagraph.text(text);
    insertBlock(_blocks.length, paragraph);
    return paragraph;
  }

  /// Inserts [block] at [index], from 0 to the number of blocks.
  ///
  /// An [index] out of that range throws [RangeError]. A [block] that is
  /// already in a body, this one or another, throws [StateError]: remove it
  /// there first. Phase 4 neither moves nor copies a block implicitly.
  void insertBlock(int index, DocxBlock block) => _edits.transaction(
    () => primitives.insertBlock(_edits, this, _blocks, index, block),
  );

  /// Removes the block at [index]. The block is then in no body and can be
  /// inserted again.
  ///
  /// An [index] that is not one of a block throws [RangeError].
  void removeBlockAt(int index) => _edits.transaction(
    () => primitives.removeBlock(_edits, this, _blocks, index),
  );

  /// Puts [block] in place of the block at [index]. The block replaced is
  /// then in no body.
  ///
  /// An [index] that is not one of a block throws [RangeError], and a
  /// [block] already in a body throws [StateError].
  void replaceBlockAt(int index, DocxBlock block) => _edits.transaction(
    () => primitives.replaceBlock(_edits, this, _blocks, index, block),
  );
}

/// A saved DOCX file and what the save had to repair to produce it.
final class DocxResult {
  DocxResult._(this.bytes, this.warnings);

  /// The DOCX file.
  final Uint8List bytes;

  /// What opening, loading and this save repaired, in first-occurrence
  /// order; empty when the document was saved exactly as given.
  /// Unmodifiable.
  final List<DocxWarning> warnings;
}
