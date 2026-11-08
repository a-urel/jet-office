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
/// access to [DocxDocument.body] (spec §4.3), and a header or footer part on
/// the first access to its blocks.
///
/// Saving writes every part of the package in its order (spec §4.3): a part
/// the model never loaded from its original bytes (layer 1), so a body never
/// accessed is copied as it was, even when it would not parse; a loaded
/// part from the model (layer 2), with what the model does not type kept as
/// written inside it (layer 3). A loaded part with nothing to write is
/// written from its original bytes too: the main part while the document's
/// `ChangeLog` has no changes, a styles, numbering, header or footer part
/// while the model writes what it wrote when read. A new header or footer
/// part is added first, so the main part writes the id of its relationship.
/// So is each relationship of a hyperlink the API built, in the part the
/// hyperlink is in (`save_plan.dart`); it is this save's alone, and leaves
/// the package once the file is written, as nothing a save allocates is
/// stored in the model (plan D5, Ruling A).
///
/// Every edit runs in a transaction of the document's `ChangeLog`
/// (`primitives.dart`), so an edit that fails leaves the body as it was.
/// Everything that leaves [DocxDocument.open], [DocxDocument.body],
/// [DocxDocument.sections], [DocxStory.blocks], [DocxDocument.save] or
/// [DocxDocument.saveTo] because of the file's content is a
/// [DocxReadException].
///
/// @docImport 'model/inlines.dart';
library;

import 'dart:collection';
import 'dart:typed_data';

import '../common/image.dart' show OfficeImage;
import '../common/properties.dart';
import '../common/properties_parts.dart';
import '../drawingml/media.dart' show DrawingMediaIndex;
import '../opc/change_log.dart';
import '../opc/ooxml.dart' show ContentType, RelType;
import '../opc/package.dart' show OpcPackage, OpcRelationship, PartContent;
import '../xml/xml_pull_reader.dart';
import '../zip/archive_adapter.dart';
import 'blank_document.dart';
import 'builtin_styles.dart' show DocxBuiltInStyle;
import 'document_part.dart';
import 'docx_package.dart';
import 'model/blocks.dart';
import 'model/edit_sink.dart';
import 'model/inlines.dart' show DocxBookmarkStart;
import 'model/numbering.dart';
import 'model/primitives.dart' as primitives;
import 'model/primitives.dart' show DocxEdits;
import 'model/run_content.dart' show DocxPicture;
import 'model/section_formatting.dart' show DocxSectionStart;
import 'model/sections.dart';
import 'model/styles.dart';
import 'numbering_part.dart';
import 'numbering_schemas.dart' show maxListLevel;
import 'properties_source.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'related_part.dart';
import 'save_ids.dart';
import 'save_plan.dart';
import 'section_property_codecs.dart'
    show AddedSectionReference, SectionReference, SectionReferenceType;
import 'settings_part.dart';
import 'story_part.dart';
import 'story_writer.dart' show listSetOf;
import 'styles_part.dart';
import 'warnings.dart';

part 'model/header_footer.dart';

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

/// Whether the settings of [document] have been loaded, for tests.
bool isSettingsLoaded(DocxDocument document) => document._settings != null;

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
    _edits.styleEnsurer = (DocxBuiltInStyle style) => styles.ensure(style);
    _edits.headerFooterResolver = _headerFooterOf;
    _edits.headerFooterOwner = _ownHeaderFooterOf;
    _edits.headerFooterRemover = _removeHeaderFooterOf;
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

  /// The settings part and where it is, once the settings are loaded.
  SettingsPart? _settings;
  RelatedPart? _settingsSlot;

  /// The stories of the header and footer parts references named so far, by
  /// the part's canonical name.
  final Map<String, _Story> _stories = <String, _Story>{};

  /// The stories of no part, by what a section asked for: reading one
  /// creates nothing in the file.
  final Map<_EmptyStoryKey, _Story> _emptyStories = <_EmptyStoryKey, _Story>{};

  /// The new stories this save creates a part for, from before it checks
  /// their blocks until it has.
  List<_Story> _storiesToCreate = const <_Story>[];

  List<DocxWarning> _warnings;

  /// The document's body, the content of `w:body`.
  ///
  /// The main document part loads on the first access, with its
  /// relationships. Throws a [DocxReadException] when it cannot be read
  /// (malformed XML, a damaged relationships part, or text past
  /// [DocxReadLimits.maxTextLength]); nothing is loaded then, so the next
  /// access throws again and a save copies the part as it was.
  DocxBody get body => _body ?? _loadBody();

  /// The document's sections, in order: one for each paragraph of the body
  /// with a section break, then the last, which every document has. A
  /// document with no final `w:sectPr` has a last section of no values, which
  /// is written once one is set.
  ///
  /// A `w:sectPr` in a table cell, in a content control or between the
  /// body's blocks stays as read and starts no section. Removing a paragraph
  /// with a break removes its section.
  ///
  /// The list cannot be changed and does not follow later edits; its
  /// sections do. It loads the body, and throws what [body] throws.
  List<DocxSection> get sections {
    final DocxBody body = this.body;
    return List<DocxSection>.unmodifiable(<DocxSection>[
      for (final DocxBlock block in body._blocks)
        if (block is DocxParagraph && block.section != null) block.section!,
      _part!.finalSection,
    ]);
  }

  /// The document's styles and document defaults, from the styles part.
  ///
  /// The part, found through the main part's relationship wherever it
  /// lives, loads on the first access, or when a style is set on content of
  /// the document (the id set is resolved against it, and such a set or
  /// insertion throws what this does); until then, and for as long as
  /// nothing in it changed, a save copies it byte for byte. A document
  /// without one has empty styles, and gains the part at save once a style
  /// or a default is set in it. Throws a
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
  /// numbering was set (to report a list the document lacks); until then,
  /// and for as long as nothing in it changed, a save copies it byte for
  /// byte. A document without one has an empty
  /// numbering, and gains the part at save once it holds a definition.
  /// Throws a [DocxReadException] naming the part when it cannot be read
  /// (malformed XML, a root that is not `w:numbering`, or a damaged
  /// relationships part of the main part); nothing is loaded then, so the
  /// next access throws again and a save copies the part as it was.
  DocxNumbering get numbering => _numbering ?? _loadNumbering();

  /// Whether the document has odd and even headers
  /// (`w:evenAndOddHeaders` of `word/settings.xml`): the even header and
  /// footer of each section show on its even pages when it is `true`.
  ///
  /// It is `false` for a document without a settings part, with no such
  /// child, with one whose `w:val` is false or does not parse, or with two.
  /// Setting `true` writes `<w:evenAndOddHeaders/>` at its place in the
  /// schema, replacing what was read, and `false` removes the child; the
  /// part is added at save for a document without one, holding only this
  /// child, and every other child of a part read stays as it was. The first
  /// content of an even header or footer, and [DocxSection.ownHeader] of the
  /// even type, set it to `true` in the same edit; removing one sets nothing.
  ///
  /// The part loads on the first access, through the main part's
  /// relationship wherever it lives; until then a save copies it as it was,
  /// and so it does for as long as the model writes what it wrote when read.
  /// A part that cannot be read makes this throw a [DocxReadException] naming
  /// it, nothing is loaded then, and a save copies it as it was. The set is
  /// one edit of the change log.
  bool get evenAndOddHeaders => _settingsPart().evenAndOddHeaders;

  set evenAndOddHeaders(bool value) {
    final SettingsPart part = _settingsPart();
    _edits.transaction(() => part.evenAndOddHeaders = value);
  }

  /// The document properties: core (`docProps/core.xml`), extended
  /// (`docProps/app.xml`) and custom (`docProps/custom.xml`), each found by
  /// its relationship in the package root.
  ///
  /// They load on first use. A new document has none and reads
  /// `OfficeProperties()`. A value that cannot be read (a `cp:revision`
  /// that is not a number) reads `null`, stays in the file as it is, and
  /// [save] reports it as [DocxWarningCode.propertyValueInvalid]. Throws a
  /// [DocxReadException] when a properties part cannot be read.
  OfficeProperties get properties => _propertiesState().parts.merged;

  /// Sets the document properties to [value].
  ///
  /// Only the fields that differ from [properties] change, each in its own
  /// element of its part; every other element of the part stays as it is, and
  /// a part nothing changed is saved byte for byte. A document without the
  /// parts gets them at [save], with their relationships and content types,
  /// once a property is set (an empty `DocxDocument()` saves none). The change
  /// is one entry of the log, and an undo of it leaves no part behind. Sets
  /// nothing for a [value] equal to [properties]. Throws an [ArgumentError]
  /// for a value XML cannot hold (see [OfficeProperties]) and a
  /// [DocxReadException] when a part cannot be read, or of
  /// [DocxReadFailure.malformedXml] naming a part whose root is not the
  /// properties element of its namespace when a value it would hold changes
  /// (such a part reads no values); nothing has changed then.
  set properties(OfficeProperties value) {
    final PropertiesState state = _propertiesState();
    if (value == state.parts.merged) return;
    checkProperties(value);
    final PropertyKind? untyped = state.parts.untypedChange(value);
    if (untyped != null) {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The document properties part has no properties root element, so it '
        'cannot be changed.',
        part: state.partName(untyped),
      );
    }
    _edits.transaction(() => setProperties(_edits.log, state, value));
  }

  PropertiesState? _properties;

  PropertiesState _propertiesState() => _properties ??= PropertiesState.load(
    DocxPropertiesSource(_package),
    (String element) {},
    encodeOnLoad: false,
    warnInPart: (String part, String element) => _loadWarnings.add(
      DocxWarningCode.propertyValueInvalid,
      part: part,
      detail: element,
    ),
  );

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
  /// A part never loaded is copied from the file, and so, byte for byte, is
  /// a loaded one with nothing new to write, comments and out-of-order
  /// properties included: the main part until the document has an edit (of
  /// any part, since they share one change log; an edit that failed is
  /// none, one undone still is), and a styles, numbering, header or footer
  /// part for as long as the model writes what it wrote when read. Any other
  /// part is written from the model, which keeps every element, in schema
  /// order, but no comment between the children it reads. Throws a
  /// [DocxReadException] if a part of the file cannot be read after all, and a
  /// [StateError] naming a table [DocxBody.addTable] left without rows, before
  /// anything is written.
  ///
  /// A header or footer a section refers to gets its part and its relationship
  /// here, at `/word/header<n>.xml` or `/word/footer<n>.xml`, with the first
  /// `n` no part or relationship has; one no section refers to any more gets
  /// neither. It keeps them from then on, so saving again gives the same names
  /// and ids.
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
        resolveUrl: _urlResolverOf(main),
        resolveImage: _imageResolverOf(main),
      ),
    );
    final DocxBody body = DocxBody._(_edits, part.blocks, this);
    primitives.adoptBlocks(_edits, body, part.blocks);
    _adoptLastSection(part.finalSection);
    package.package.setContent(
      main,
      _MainPart(part, _edits.log, () => package.package.originalBytes(main)),
    );
    _part = part;
    return _body = body;
  }

  /// What a hyperlink read from [part] asks for its url: the target of the
  /// relationship of [part] that an id names, when it is of the hyperlink
  /// type and external, else `null` (plan D5, Ruling 8).
  ///
  /// The relationships are peeked, never registered for rewriting, so a
  /// story's stay unread and every part's are copied as read (Ruling 12); the
  /// main part's were read with the body. A relationships part that cannot be
  /// read gives `null`: the hyperlink still writes as read, and the failure
  /// is remembered, so the part is not parsed again for each hyperlink. Of
  /// two relationships with one id, the first counts.
  String? Function(String id) _urlResolverOf(String part) {
    final OpcRelationship? Function(String) lookup = _relationshipLookupOf(
      part,
    );
    return (String id) {
      final OpcRelationship? rel = lookup(id);
      return rel != null && rel.type == RelType.hyperlink && rel.external
          ? rel.target
          : null;
    };
  }

  /// What a picture read from [part] asks for its image: the image of the
  /// media part the relationship of [part] that an id names points at, when
  /// it is of the image type, internal and its target is a part of the file;
  /// else `null`, as for a media part that cannot be read (Ruling 12). It
  /// peeks at the relationships as [_urlResolverOf] does, and the images come
  /// from the document's one [DrawingMediaIndex], so pictures of one media
  /// part share one [OfficeImage].
  OfficeImage? Function(String id) _imageResolverOf(String part) {
    final OpcRelationship? Function(String) lookup = _relationshipLookupOf(
      part,
    );
    return (String id) {
      final OpcRelationship? rel = lookup(id);
      if (rel == null || rel.type != RelType.image || rel.external) {
        return null;
      }
      final OpcPackage package = _package.package;
      final String target = package.resolve(part, rel.target);
      if (!package.hasPart(target)) return null;
      try {
        return _package.guard(target, () => _mediaIndex.imageOf(target));
      } on DocxReadException {
        return null;
      }
    };
  }

  /// The document's media index: the images of its media parts, read as a
  /// picture asks for them.
  late final DrawingMediaIndex _mediaIndex = DrawingMediaIndex(
    _package.package,
  );

  final Map<String, OpcRelationship? Function(String)> _relationshipLookups =
      <String, OpcRelationship? Function(String)>{};

  /// The relationship of [part] an id names (the first of several), peeked
  /// and not registered for rewriting, `null` for none; the lookup is the
  /// same for a part however often it is asked for, and a relationships part
  /// that cannot be read answers `null` for every id, remembered so it is
  /// not parsed again.
  OpcRelationship? Function(String id) _relationshipLookupOf(String part) =>
      _relationshipLookups[part] ??= () {
        bool unreadable = false;
        return (String id) {
          if (unreadable) return null;
          final List<OpcRelationship> relationships;
          try {
            relationships = _package.guard(
              relationshipsPartOf(part),
              () => _package.package.peekRelationships(part),
            );
          } on DocxReadException {
            unreadable = true;
            return null;
          }
          for (final OpcRelationship rel in relationships) {
            if (rel.id == id) return rel;
          }
          return null;
        };
      }();

  /// Makes [section] the document's last section: it reports to [_edits].
  void _adoptLastSection(DocxSection section) {
    bindSection(section, () => _edits);
    setSectionHome(section, _edits);
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

  SettingsPart _settingsPart() => _settings ?? _loadSettings();

  SettingsPart _loadSettings() {
    final RelatedPart slot = RelatedPart.find(
      _package,
      source: _package.mainPart,
      relationshipType: RelType.settings,
      defaultName: '/word/settings.xml',
      contentType: ContentType.wmlSettings,
    );
    final SettingsPart part = slot.exists
        ? slot.load(
            (XmlPullReader r) => SettingsPart.read(r, slot.name, _edits),
          )
        : SettingsPart.empty(_edits, slot.name);
    _settingsSlot = slot;
    return _settings = part;
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

  /// The header or footer of [type] that [section] reads (plan Ruling 5):
  /// its own, else the nearest previous section's, else an empty one. A
  /// section that left the document has no previous section.
  DocxHeaderFooter _headerFooterOf(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) {
    final _Story? Function(DocxSection) ownOf = _ownStories(
      type,
      isHeader: isHeader,
    );
    final _Story? own = ownOf(section);
    if (own != null) return own.handle(type, inherited: false);
    final List<DocxSection> all = sections;
    for (int i = all.indexOf(section) - 1; i >= 0; i--) {
      final _Story? story = ownOf(all[i]);
      if (story != null) return story.handle(type, inherited: true);
    }
    return _emptyStoryOf(
      section,
      type,
      isHeader,
    ).handle(type, inherited: false);
  }

  /// The empty story [section] gets for [type].
  _Story _emptyStoryOf(
    DocxSection section,
    DocxHeaderFooterType type,
    bool isHeader,
  ) {
    final _EmptyStoryKey key = (section, isHeader, type);
    return _emptyStories[key] ??= _Story.empty(this, isHeader, key);
  }

  /// The story of its own of [type] [section] gets (plan Ruling 5): the one it
  /// has, else a new one, which [_Story.turnOn] attaches.
  DocxHeaderFooter _ownHeaderFooterOf(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) {
    final _Story story =
        _ownStories(type, isHeader: isHeader)(section) ??
        _emptyStoryOf(section, type, isHeader);
    _edits.transaction(() => story.turnOnFor(section, type));
    return story.handle(type, inherited: false);
  }

  /// Drops every reference of [type] of [section] that names a story, so the
  /// section inherits again; one that names nothing stays.
  void _removeHeaderFooterOf(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) {
    final _Story? Function(SectionReference) storyOf = _referenceStories(
      isHeader: isHeader,
    );
    _edits.transaction(
      () => removeSectionReferences(
        section,
        (SectionReference ref) =>
            ref.type == type._reference && storyOf(ref) != null,
        isHeader: isHeader,
      ),
    );
  }

  /// What gives a section's own story of [type]: that of its first reference
  /// of [type] that names one, or `null`.
  _Story? Function(DocxSection) _ownStories(
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) {
    final _Story? Function(SectionReference) storyOf = _referenceStories(
      isHeader: isHeader,
    );
    return (DocxSection section) {
      for (final SectionReference ref in sectionReferencesOf(
        section,
        isHeader: isHeader,
      )) {
        if (ref.type != type._reference) continue;
        final _Story? story = storyOf(ref);
        if (story != null) return story;
      }
      return null;
    };
  }

  /// What gives the story a reference names, to a header when [isHeader] and
  /// to a footer otherwise, or `null` when it names none.
  _Story? Function(SectionReference) _referenceStories({
    required bool isHeader,
  }) {
    final OpcPackage opc = _package.package;
    final String main = _package.mainPart;
    final String otherKind = isHeader ? RelType.footer : RelType.header;
    final Map<String, OpcRelationship> relationships =
        <String, OpcRelationship>{};
    final Set<String> namedAsOther = <String>{};
    for (final OpcRelationship rel in opc.relationshipsOf(main)) {
      relationships.putIfAbsent(rel.id, () => rel);
      if (!rel.external && rel.type == otherKind) {
        final String? name = opc.canonicalPartName(
          opc.resolve(main, rel.target),
        );
        if (name != null) namedAsOther.add(name);
      }
    }
    return (SectionReference ref) => ref is AddedSectionReference
        ? ref.story as _Story
        : _storyOf(relationships[ref.relId], isHeader, namedAsOther);
  }

  /// The story of the part [rel] names, for a reference of a header when
  /// [isHeader] and of a footer otherwise, or `null` when it names none
  /// (see `model/header_footer.dart`). [namedAsOther] holds the parts a
  /// relationship of the other kind names: only its content type could tell
  /// what a part is, so a generic one among them is neither.
  _Story? _storyOf(
    OpcRelationship? rel,
    bool isHeader,
    Set<String> namedAsOther,
  ) {
    if (rel == null ||
        rel.external ||
        rel.type != (isHeader ? RelType.header : RelType.footer)) {
      return null;
    }
    final OpcPackage opc = _package.package;
    final String main = _package.mainPart;
    final String? name = opc.canonicalPartName(opc.resolve(main, rel.target));
    if (name == null || name == main) return null;
    final String? type = opc.contentTypeOf(name);
    final bool generic = type == ContentType.xml || type == 'text/xml';
    if (generic
        ? namedAsOther.contains(name)
        : type != (isHeader ? ContentType.wmlHeader : ContentType.wmlFooter)) {
      return null;
    }
    return _stories.putIfAbsent(
      name,
      () => _Story(this, isHeader, RelatedPart.named(_package, name)),
    );
  }

  /// The header and footer parts loaded so far, and those this save creates.
  Iterable<StoryPart> get _storyParts => <_Story>[
    ..._stories.values,
    ..._storiesToCreate,
  ].map((_Story s) => s.part).nonNulls;

  /// The ids of the save running now, made on first use and dropped when
  /// it ends, so two saves never share one (plan Ruling A).
  SaveIds? _saveIdsOfSave;

  /// The ids of this save: drawing and bookmark ids for what the model
  /// built, and new relationships that take no id the file's parts name.
  /// Only [_write] may ask.
  SaveIds get _saveIds => _saveIdsOfSave ??= SaveIds(_package);

  /// The relationship ids the main part names in the file, which a new
  /// relationship of it must not take ([SaveIds.fileReferenceIds]): one
  /// that names nothing, such as a header reference with no relationship,
  /// would come to name the new part. Those the model does not type count,
  /// wherever they are, and so does one replaced, which an undo brings back.
  Set<String> get _mainReferenceIds =>
      _saveIds.fileReferenceIds(_package.mainPart);

  /// Finds the new stories a section of the document refers to and names
  /// their parts, without touching the package, so that a save that stops at
  /// a check creates nothing.
  ///
  /// A name is free when no part has it and no relationship of the main part
  /// targets it: a part there would give a relationship read, and any
  /// reference through it, a target they never had. A folder `/word` that
  /// cannot hold a part, because a part has that name, leaves the root.
  void _nameNewStories() {
    final OpcPackage opc = _package.package;
    final String main = _package.mainPart;
    final Set<String> taken = <String>{
      for (final OpcRelationship rel in opc.relationshipsOf(main))
        if (!rel.external) opc.resolve(main, rel.target).toLowerCase(),
    };
    final String folder = opc.isNewPartName('/word/_') ? '/word/' : '/';
    final List<_Story> stories = <_Story>[];
    for (final DocxSection section in sections) {
      for (final bool isHeader in const <bool>[true, false]) {
        for (final SectionReference ref in sectionReferencesOf(
          section,
          isHeader: isHeader,
        )) {
          if (ref is! AddedSectionReference) continue;
          final _Story story = ref.story as _Story;
          if (!story.needsPart) continue;
          final String kind = isHeader ? 'header' : 'footer';
          int n = 1;
          while (!opc.isNewPartName('$folder$kind$n.xml') ||
              !taken.add('$folder$kind$n.xml')) {
            n++;
          }
          story.part!.partName = '$folder$kind$n.xml';
          stories.add(story);
        }
      }
    }
    _storiesToCreate = stories;
  }

  /// The ids a new relationship of [slot] must not take: those the main
  /// part names, as [_mainReferenceIds]. None when the part exists; those
  /// read up to the point of failure when the main part cannot be read
  /// ([SaveIds]): it is copied as it is, and a failure to read it is not
  /// this part's to report.
  Set<String> _reservedFor(RelatedPart slot) =>
      slot.exists ? const <String>{} : _mainReferenceIds;

  /// Creates the parts [_nameNewStories] named, so that the main part, which
  /// the package writes after this, knows the ids.
  void _createNewStories() {
    if (_storiesToCreate.isEmpty) return;
    for (final _Story story in _storiesToCreate) {
      story.create(_mainReferenceIds);
      _stories[story.part!.partName] = story;
    }
    _storiesToCreate = const <_Story>[];
  }

  /// Whether the document defines a list instance, for the check of the
  /// lists paragraphs were put in through the API (plan Ruling 8); `null`
  /// when no paragraph of the body, of a story or of their tables was, or the
  /// numbering part cannot be read (nothing is reported then).
  bool Function(int numId)? _listCheck() {
    final DocxBody? body = _body;
    if (body == null ||
        !(_holdsListSet(body._blocks) ||
            _storyParts.any((StoryPart p) => _holdsListSet(p.blocks)))) {
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

  /// The plan of the save running now, from [_planBuilt]; `null` outside
  /// a save and in a save that built nothing.
  SavePlan? _planOfSave;

  void _write(ZipWriter zip) {
    _saveIdsOfSave = null;
    _planOfSave = null;
    try {
      _writeParts(zip);
    } finally {
      // What the save related and added for what the model built leaves the
      // package with it (plan Ruling A): the relationships first, then the
      // media parts they pointed at.
      _saveIdsOfSave?.restoreRelationships();
      _saveIdsOfSave = null;
      _planOfSave?.restore();
      _planOfSave = null;
      // Nor does a part keep what the save told it about ids.
      final DocumentPart? main = _part;
      if (main != null) {
        main
          ..bookmarkId = null
          ..drawingId = null
          ..relationshipId = null;
      }
      for (final StoryPart story in _storyParts) {
        story
          ..bookmarkId = null
          ..drawingId = null
          ..relationshipId = null;
      }
    }
  }

  /// Relates what the API built in every part this save writes from the
  /// model, the main part and each header and footer, new ones included, and
  /// tells each part's writer the ids. It comes after the new parts are
  /// created and before the package writes the relationships parts. Without
  /// an edit nothing was built, and no part learns an id.
  void _planBuilt(DocumentPart main) {
    final SavePlan? plan = _planOfSave = _edits.log.hasChanges
        ? SavePlan(_package, _saveIds, _mediaIndex)
        : null;
    plan?.planPart(main.partName, main.blocks);
    main.relationshipId = plan?.relationshipIdsOf(main.partName);
    for (final StoryPart story in _storyParts) {
      plan?.planPart(story.partName, story.blocks);
      story.relationshipId = plan?.relationshipIdsOf(story.partName);
    }
  }

  void _writeParts(ZipWriter zip) {
    final DocxPackage package = _package;
    final DocumentPart? main = _part;
    if (main != null) {
      // Only an edit leaves a table without rows, and the check comes before
      // anything is written, to the part or to the sink.
      if (_edits.log.hasChanges) {
        _nameNewStories();
        main.checkBuiltTables();
        for (final StoryPart story in _storyParts) {
          story.checkBuiltTables();
        }
      }
      final bool Function(int)? listDefined = _listCheck();
      // Only a style set through the API is reported, and setting one
      // loaded the styles.
      final DocxStyles? styles = _styles;
      final bool Function(String, DocxStyleType)? styleDefined = styles == null
          ? null
          : (String id, DocxStyleType type) => definesStyle(styles, id, type);
      // A built bookmark's id is allocated here, once for its start and its
      // end, and stored nowhere else (plan Ruling A).
      final Map<DocxBookmarkStart, int> bookmarkIds =
          Map<DocxBookmarkStart, int>.identity();
      int bookmarkId(DocxBookmarkStart start) =>
          bookmarkIds.putIfAbsent(start, () => _saveIds.nextBookmarkId());
      // So is a built picture's wp:docPr id, which its default name repeats.
      final Map<DocxPicture, int> drawingIds = Map<DocxPicture, int>.identity();
      int drawingId(DocxPicture picture) =>
          drawingIds.putIfAbsent(picture, () => _saveIds.nextDrawingId());
      main
        ..listDefined = listDefined
        ..styleDefined = styleDefined
        ..bookmarkId = bookmarkId
        ..drawingId = drawingId;
      for (final StoryPart story in _storyParts) {
        story
          ..listDefined = listDefined
          ..styleDefined = styleDefined
          ..bookmarkId = bookmarkId
          ..drawingId = drawingId;
      }
    }
    // A styles part the document lacked is added once it holds something
    // (plan Ruling 7); after that it is a part like the others.
    final StylesPart? stylesPart = _stylesPart;
    if (stylesPart != null && stylesPart.holdsSomething) {
      final RelatedPart slot = _stylesSlot!;
      slot.create(stylesPart, reservedIds: _reservedFor(slot));
    }
    final NumberingPart? numbering = _numberingPart;
    if (numbering != null && numbering.holdsSomething) {
      final RelatedPart slot = _numberingSlot!;
      slot.create(numbering, reservedIds: _reservedFor(slot));
    }
    final SettingsPart? settings = _settings;
    if (settings != null && settings.holdsSomething) {
      final RelatedPart slot = _settingsSlot!;
      slot.create(settings, reservedIds: _reservedFor(slot));
    }
    _createNewStories();
    // Every part the save keeps (the stories, the slots above, the
    // properties) is added before the parts it takes back after the write
    // (media), so the next save finds them in the same order.
    final PropertiesState? properties = _properties;
    if (properties != null) {
      package.guard(package.mainPart, properties.sync);
    }
    if (main != null) _planBuilt(main);
    package.guard(package.mainPart, () => package.package.writeTo(zip));
    final DocumentPart? part = _part;
    _warnings = List<DocxWarning>.unmodifiable(<DocxWarning>[
      ..._loadWarnings.warnings,
      if (part != null) ...part.encodeWarnings.warnings,
      for (final StoryPart story in _storyParts)
        ...story.encodeWarnings.warnings,
    ]);
  }
}

/// The content of a loaded main part: the file's bytes until [_log] has a
/// change, then what [_part] writes. No edit means nothing to report either:
/// what the part warns about at save was put there through the API.
final class _MainPart implements PartContent {
  _MainPart(this._part, this._log, this._original);

  final DocumentPart _part;
  final ChangeLog _log;

  /// The part's bytes in the file.
  final Uint8List Function() _original;

  @override
  List<Uint8List> encode() =>
      _log.hasChanges ? _part.encode() : <Uint8List>[_original()];
}

/// The blocks of a story: the run of paragraphs and tables a part holds under
/// its root, as `w:body` does in the main part.
///
/// Paragraphs ([DocxParagraph]) and tables ([DocxTable]) are typed; every
/// other block, such as a content control, is a [DocxOpaqueBlock] kept as
/// written. A block is in at most one story at a time. Each edit is atomic: one
/// that throws changes nothing.
///
/// [DocxBody] is the story of the main part, and [DocxHeaderFooter] that of a
/// header or footer part, which loads on the first access to [blocks] or edit
/// and throws a [DocxReadException] naming the part when it cannot be read.
///
/// The checks only the body needs, such as a section break's references,
/// belong to [DocxBody] and reach the edits here through [_checkBlock].
abstract base class DocxStory {
  DocxStory._(this._edits, this._document);

  final DocxEdits _edits;
  final DocxDocument _document;

  /// The list of blocks, which a header or footer part loads.
  List<DocxBlock> get _blocks;

  /// What holds the blocks: [DocxHeaderFooter]s of one part share it.
  Object get _container => this;

  late final List<DocxBlock> _blocksView = UnmodifiableListView<DocxBlock>(
    _blocks,
  );

  /// Checks that [block] may go into this story, before it is inserted: the
  /// body's section break check. The story's own edits check nothing more.
  void _checkBlock(DocxBlock block) {}

  /// The twips [columns] new columns share: what Word's Insert Table takes of
  /// the last section, or `null` for the page of a blank document when that
  /// does not read or gives a column less than a twip.
  int? _tableWidthTwips(int columns) {
    final double? pt = _document._part!.finalSection.textWidthPt;
    if (pt == null) return null;
    final int twips = (pt * 20).round() - _insertTableInsetTwips;
    return twips >= columns ? twips : null;
  }

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

  /// Appends a paragraph that holds [text] as an item of [list], at [level]
  /// (0 to 8), and returns it.
  ///
  /// The paragraph has the style `List Paragraph`, as Word gives the items
  /// of its toolbar lists: the document's own style of that name, or Word's
  /// definition added when the document lacks it ([DocxStyles.ensure]). The
  /// label (the bullet or the number) is not part of [DocxParagraph.text].
  ///
  /// A [list] that is not an instance of this document's numbering throws
  /// [ArgumentError], and a [level] outside 0 to 8 [RangeError]; nothing
  /// changes then. When the styles or the numbering part cannot be read,
  /// this throws a [DocxReadException] naming it, and nothing changes. The
  /// add is one transaction.
  DocxParagraph addListItem(
    DocxNumberingInstance list,
    String text, {
    int level = 0,
  }) {
    RangeError.checkValueInInterval(level, 0, maxListLevel, 'level');
    if (!ownsInstance(_document.numbering, list)) {
      throw ArgumentError.value(list, 'list', 'Not a list of this document');
    }
    final DocxStyles styles = _document.styles;
    final DocxParagraph paragraph = DocxParagraph.text(text);
    _edits.transaction(() {
      paragraph.style = styles.ensure(DocxBuiltInStyle.listParagraph);
      paragraph.properties.numbering = list.ref(level: level);
      insertBlock(_blocks.length, paragraph);
    });
    return paragraph;
  }

  /// Appends a new table of [columns] columns as Word's Insert Table writes it
  /// and returns it, with no rows yet: add them with [DocxTable.addRow].
  ///
  /// The table has the style `Table Grid`: the document's own style of that
  /// name, or Word's definition added when the document lacks it, with `Normal
  /// Table` ([DocxStyles.ensure]). Its width is automatic, and its look turns
  /// on the first row and the first column and turns off the column bands.
  ///
  /// [columnWidthsPt] gives the width of each column, in points, from 0 to
  /// 1584. Without it the columns share what Word's Insert Table takes of the
  /// last section's [DocxSection.textWidthPt], 10 twips less, rounded down to
  /// whole twips: 9062 twips on a blank A4 page. A section whose text width
  /// does not read, or would give a column less than a twip, shares 9062 too.
  ///
  /// A table with no rows is not a table Word opens: a [DocxDocument.save] or
  /// [DocxDocument.saveTo] of one left that way throws [StateError] naming it.
  /// A table of a file with no rows is kept as read.
  ///
  /// The model adds no block: two tables added one after the other join in
  /// Word, unless a paragraph is put between them, and a body that ends in a
  /// table is saved so.
  ///
  /// A [columns] outside 1 to 63, or a width out of range, throws [RangeError];
  /// [columnWidthsPt] of another length, or a width that is not finite, throws
  /// [ArgumentError]. When the styles part cannot be read, this throws a
  /// [DocxReadException] naming it. Nothing changes then; otherwise the add is
  /// one transaction.
  DocxTable addTable({required int columns, List<double>? columnWidthsPt}) {
    final DocxTable table = newTable(
      columns,
      columnWidthsPt,
      widthTwips: _tableWidthTwips(columns),
    );
    _edits.transaction(() {
      table.properties.style = _document.styles.ensure(
        DocxBuiltInStyle.tableGrid,
      );
      insertBlock(_blocks.length, table);
    });
    return table;
  }

  /// Inserts [block] at [index], from 0 to the number of blocks.
  ///
  /// An [index] out of that range throws [RangeError]. A [block] that is
  /// already in a story, this one or another, or in a table cell, throws
  /// [StateError]: remove it there first. Phase 4 neither moves nor copies a
  /// block implicitly. A table nested past 80 deep, which only a file can
  /// hold, throws [ArgumentError]: what the API builds opens again under the
  /// default read limits. So does a paragraph with a section break of another
  /// document: the ids of its references mean nothing here. A paragraph with
  /// a section break, from anywhere, throws it going in a [DocxHeaderFooter],
  /// which has no sections. In a table cell such a break starts no section,
  /// and goes in as read.
  ///
  /// The styles set on a paragraph, on its runs and on a table, and on
  /// everything in the cells of a table, nested tables included, are resolved
  /// against the document's ([DocxParagraph.style] has the rules). When one is
  /// set and the styles part cannot be read, this throws a [DocxReadException]
  /// naming it, on a document that opened; nothing changes then.
  ///
  /// A paragraph or a table read in another document counts as set here, with
  /// what its cells hold: a paragraph's `w:pStyle` and `w:numPr`, the
  /// `w:rStyle` of its runs and a table's `w:tblStyle` are resolved by id, and
  /// a save reports the ones this document lacks, each at its own location
  /// ([DocxWarningCode.styleNotFound], [DocxWarningCode.numberingNotFound]).
  /// A row or a cell going into a table here does the same. Moved within one
  /// document they stay as read. A move carries nothing else over:
  ///
  /// * The style's `w:name` stays behind, so a built-in style under a
  ///   localized id (`Balk1`) does not map to this document's by its name;
  ///   it is reported instead.
  /// * A `w:numId` this document has too joins that list, unreported, even
  ///   when it is another list; ids are not remapped.
  /// * A read opaque inline or block that holds an `r:id` (a hyperlink, a
  ///   picture) keeps an id this document may lack or mean otherwise. Ids are
  ///   per part, so the same holds, unreported, for one moved between the
  ///   body, a header and a footer of one document.
  /// * A reference the model does not type, and one in the paragraph mark's
  ///   `w:rPr`, stay as read, unreported.
  void insertBlock(int index, DocxBlock block) {
    _checkBlock(block);
    primitives.insertBlock(_edits, _container, _blocks, index, block);
  }

  /// Removes the block at [index]. The block is then in no story and can be
  /// inserted again.
  ///
  /// An [index] that is not one of a block throws [RangeError].
  void removeBlockAt(int index) =>
      primitives.removeBlock(_edits, _container, _blocks, index);

  /// Puts [block] in place of the block at [index]. The block replaced is
  /// then in no story.
  ///
  /// An [index] that is not one of a block throws [RangeError], and a
  /// [block] already in a story or a cell throws [StateError]. The styles set
  /// on [block] are resolved as [insertBlock] does, which may throw the same
  /// [DocxReadException], and what was read in another document counts as set
  /// as it says. A section break of another document, or any going in a
  /// [DocxHeaderFooter], throws [ArgumentError], as there.
  void replaceBlockAt(int index, DocxBlock block) {
    _checkBlock(block);
    primitives.replaceBlock(_edits, _container, _blocks, index, block);
  }
}

/// The body of a document, the content of `w:body`: its blocks, in order.
///
/// Paragraphs ([DocxParagraph]) and tables ([DocxTable]) are typed; every
/// other block, such as a content control, is a [DocxOpaqueBlock] kept as
/// written. The last section belongs to the body, not to its blocks
/// ([DocxDocument.sections]); the others are in the paragraphs that end them.
///
/// A block is in at most one body at a time. Each edit is atomic: one that
/// throws changes nothing.
final class DocxBody extends DocxStory {
  DocxBody._(DocxEdits edits, this._blocks, DocxDocument document)
    : super._(edits, document);

  @override
  final List<DocxBlock> _blocks;

  @override
  void _checkBlock(DocxBlock block) => checkBreakFits(block, _edits);

  /// Ends the last section after the last block and returns the new last
  /// section, which [start] says how to start.
  ///
  /// As in Word, the last block takes the break when it is a paragraph with
  /// none; otherwise a new empty paragraph is added for it. The section that
  /// was last stays the same object, as a section held keeps pointing at its
  /// page, and is now the [DocxParagraph.section] of that paragraph.
  ///
  /// The new section copies its page size, margins, columns, line numbering,
  /// vertical alignment, page number format and `w:docGrid`. It has no header
  /// or footer references, so it inherits them, no [DocxSection.titlePage],
  /// and no first page number. A `w:pgNumType` the model cannot type is not
  /// copied, as it may hold a first page number.
  ///
  /// The model adds no block after the break: a body whose last block carries
  /// it is saved so, until something is added after it. The add is one
  /// transaction.
  DocxSection addSection({DocxSectionStart start = DocxSectionStart.nextPage}) {
    final DocumentPart part = _document._part!;
    final DocxSection held = part.finalSection;
    final DocxSection next = nextSection(held, start);
    _edits.transaction(() {
      final DocxBlock? last = _blocks.lastOrNull;
      final DocxParagraph paragraph =
          last is DocxParagraph && !paragraphHasBreak(last)
          ? last
          : addParagraph();
      _edits.apply(_SectionAdded(_document, part, paragraph, held, next));
    });
    return next;
  }
}

/// Whether a paragraph of [blocks], or in one of their tables, was put in a
/// list through the API.
bool _holdsListSet(List<DocxBlock> blocks) {
  bool found = false;
  for (final DocxBlock block in blocks) {
    visitBlocks(block, (DocxBlock b) {
      found = found || (b is DocxParagraph && listSetOf(b) != null);
    });
    if (found) return true;
  }
  return false;
}

/// What Word's Insert Table leaves of the text width, less: 9062 of the 9072
/// twips of a blank A4 page, as `builtins.docx` holds them.
const int _insertTableInsetTwips = 10;

/// The swap of [DocxBody.addSection]: [_held], the last section, moves to
/// [_paragraph] and [_next] becomes the last.
final class _SectionAdded implements Change {
  _SectionAdded(
    this._document,
    this._part,
    this._paragraph,
    this._held,
    this._next,
  );

  final DocxDocument _document;
  final DocumentPart _part;
  final DocxParagraph _paragraph;
  final DocxSection _held;
  final DocxSection _next;

  @override
  void revert() {
    setParagraphSection(_paragraph, null);
    bindSection(_next, () => DocxEditSink.none);
    _part.finalSection = _held;
    _document._adoptLastSection(_held);
  }

  @override
  void reapply() {
    setParagraphSection(_paragraph, _held);
    _part.finalSection = _next;
    _document._adoptLastSection(_next);
  }
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
