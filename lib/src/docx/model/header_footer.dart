/// The headers and footers of a document: a story each, in a part of its own.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `docx_document.dart`, since a story reaches the private members
/// of [DocxStory] and of the document.
///
/// A part's blocks live in one [_Story], cached by the document under the
/// part's canonical name, so a part named by several references is one story
/// and loads once, on the first [DocxStory.blocks]; until then a save copies
/// the part as it was. Which section reads it, and whether it inherited it,
/// is not the part's: a [DocxHeaderFooter] is a light handle on the story, the
/// same object for the same type and inheritance. Blocks, edits and the
/// location of warnings all belong to the [_Story].
///
/// A reference counts when its relationship of the main part is internal, of
/// the header or the footer type as the reference is, and names a part of the
/// matching content type, or of the generic XML type when no relationship of
/// the other kind names it too, that is not the main part. Any other reference
/// stays as read and counts as none (plan Ruling 7), whichever is read first.
///
/// The part's own relationships are not read: a read of the package parses
/// them, and a parsed relationships part is written anew at save, which a
/// story only read must not do.
part of '../docx_document.dart';

/// Which pages of a section a header or a footer is for.
enum DocxHeaderFooterType {
  /// Every page no other type covers (`w:type="default"`).
  primary(SectionReferenceType.defaultPage),

  /// The section's first page, when it has a title page
  /// (`w:type="first"`, [DocxSection.titlePage]).
  first(SectionReferenceType.first),

  /// The even pages, when the document has odd and even headers
  /// (`w:type="even"`).
  even(SectionReferenceType.even);

  const DocxHeaderFooterType(this._reference);

  /// The `w:type` of the reference.
  final SectionReferenceType _reference;
}

/// A header or a footer of a section: blocks, as a body has.
///
/// Get one from [DocxSection.header], [DocxSection.footer] and their first and
/// even kin. It is the section's own, or the nearest previous section's
/// ([isInherited]), or, when no section up to this one has one, empty.
///
/// Reading one changes nothing, and its part loads on the first access to
/// [blocks] or edit: a [DocxReadException] names the part when it cannot be
/// read, nothing is loaded then, and a save copies the part as it was. An edit
/// reaches every section that uses the story, as
/// Word's "Link to Previous" does, and every reference that names its part.
///
/// A paragraph with a section break cannot go in one: [insertBlock] and
/// [replaceBlockAt] throw [ArgumentError], wherever the paragraph comes from.
final class DocxHeaderFooter extends DocxStory {
  DocxHeaderFooter._(this._story, this.type, {required this.isInherited})
    : super._(_story._document._edits, _story._document);

  final _Story _story;

  /// The pages it is for, as the section was asked for it.
  final DocxHeaderFooterType type;

  /// Whether it is a previous section's, which this section has none in
  /// place of.
  final bool isInherited;

  /// Whether it is a header; otherwise it is a footer.
  bool get isHeader => _story.isHeader;

  @override
  List<DocxBlock> get _blocks => _story.blocks;

  @override
  Object get _container => _story;

  @override
  void _checkBlock(DocxBlock block) {
    if (block is DocxParagraph && paragraphHasBreak(block)) {
      throw ArgumentError.value(
        block,
        'block',
        'must not bring a section break into a header or a footer',
      );
    }
  }
}

/// The blocks of a header or a footer, shared by the handles on it. A story
/// with no [_slot] has no part: it reads empty and writes nothing.
final class _Story {
  _Story(this._document, this.isHeader, this._slot);

  final DocxDocument _document;

  /// Whether the story is a header's; otherwise it is a footer's.
  final bool isHeader;

  /// Where the part is, or `null` for a story with none.
  final RelatedPart? _slot;

  /// The part, once it is loaded.
  StoryPart? part;

  List<DocxBlock>? _blocks;

  final Map<(DocxHeaderFooterType, bool), DocxHeaderFooter> _handles =
      <(DocxHeaderFooterType, bool), DocxHeaderFooter>{};

  /// The handle on this story of [type].
  DocxHeaderFooter handle(
    DocxHeaderFooterType type, {
    required bool inherited,
  }) => _handles[(type, inherited)] ??= DocxHeaderFooter._(
    this,
    type,
    isInherited: inherited,
  );

  /// The blocks, read on the first access.
  List<DocxBlock> get blocks => _blocks ??= _load();

  /// Reads the part. Nothing is loaded when it throws.
  List<DocxBlock> _load() {
    final RelatedPart? slot = _slot;
    if (slot == null) return <DocxBlock>[];
    final DocxPackage package = _document._package;
    final StoryPart read = slot.load(
      (XmlPullReader r) => StoryPart.read(
        r,
        slot.name,
        isHeader: isHeader,
        limits: package.limits,
      ),
    );
    primitives.adoptBlocks(_document._edits, this, read.blocks);
    part = read;
    return read.blocks;
  }
}
