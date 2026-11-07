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
///
/// A section with no story of a type gets an empty one, kept by the document
/// for that section and type, with a [StoryPart] of no name. Its first block,
/// or `own…`, attaches it: it leaves the empty ones, and the section gets an
/// [AddedSectionReference] that names it, both undoable and in the transaction
/// of the edit. Nothing of it reaches the package then, so an edit undone or
/// failed leaves no trace. A save creates the part and the relationship of each
/// story a section of the document still refers to, and fills the reference's
/// id, before the main part is written; the story is then a part like any
/// other, and stays one: an undo leaves it with no reference, which a package
/// may hold.
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
/// The first block of an empty one gives the section a reference to it in the
/// same transaction, and the part is added at save; the section's next
/// sections inherit it. The first block of a story of the first page sets
/// [DocxSection.titlePage] on the sections that have it as their own. Empty
/// paragraphs are no content, as Word writes one in a header nobody filled: a
/// block added after them is a first block too.
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
  void insertBlock(int index, DocxBlock block) {
    _checkBlock(block);
    _edits.transaction(() {
      final bool hadNoContent = _blocks.every(_isBlank);
      primitives.insertBlock(_edits, _container, _blocks, index, block);
      if (hadNoContent) _story.turnOn(type);
    });
  }

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

/// What a section asked for when it got an empty story: the section, whether
/// it is a header, and the type.
typedef _EmptyStoryKey = (DocxSection, bool, DocxHeaderFooterType);

/// The blocks of a header or a footer, shared by the handles on it. A story
/// with no [_slot] has no part in the package: it reads as its blocks, and
/// writes nothing until a save finds a section that refers to it.
final class _Story {
  /// The story of the part [_slot] names.
  _Story(this._document, this.isHeader, RelatedPart this._slot) : _key = null;

  /// A new empty story of what [_key] says.
  _Story.empty(this._document, this.isHeader, _EmptyStoryKey this._key)
    : part = StoryPart.create(isHeader: isHeader) {
    _blocks = part!.blocks;
  }

  final DocxDocument _document;

  /// Whether the story is a header's; otherwise it is a footer's.
  final bool isHeader;

  /// Where the part is, or `null` for a story that has none yet.
  RelatedPart? _slot;

  /// What the story was made for, when it was made empty.
  final _EmptyStoryKey? _key;

  /// Whether a section was given a reference to this new story.
  bool _attached = false;

  /// The one reference to this new story.
  late final AddedSectionReference _reference = AddedSectionReference(
    _key!.$3._reference,
    this,
  );

  /// The part, once it is loaded; a new story's from the start.
  StoryPart? part;

  /// Whether the save has a part to create for this story.
  bool get needsPart => _slot == null;

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

  /// Gives a new story its reference, once.
  void _attach() {
    final _EmptyStoryKey? key = _key;
    if (key != null && !_attached) {
      _document._edits.apply(_StoryAttached(_document, this, key));
      putSectionReference(key.$1, _reference, isHeader: isHeader);
    }
  }

  /// Records that [section] asked for this story as its own of [type]: a new
  /// story gets its reference, and a first story sets the title page of
  /// [section] alone (plan Ruling 6). Call it inside a transaction.
  void turnOnFor(DocxSection section, DocxHeaderFooterType type) {
    _attach();
    if (type == DocxHeaderFooterType.first) section.titlePage = true;
  }

  /// Records that the story got its first content through a handle of [type],
  /// which any section using the story may hold: a new story gets its
  /// reference, and a first story sets the title page of the sections it is
  /// the own story of (plan Ruling 6). Call it inside a transaction.
  void turnOn(DocxHeaderFooterType type) {
    _attach();
    if (type == DocxHeaderFooterType.first) {
      final _Story? Function(DocxSection) ownOf = _document._ownStories(
        type,
        isHeader: isHeader,
      );
      for (final DocxSection section in _document.sections) {
        if (identical(ownOf(section), this)) section.titlePage = true;
      }
    }
  }

  /// Adds the part at the name its [StoryPart] holds, with a relationship
  /// whose id is not in [reservedIds], and fills the reference.
  void create(Set<String> reservedIds) {
    final StoryPart content = part!;
    final RelatedPart slot = RelatedPart.added(
      _document._package,
      content.partName,
      relationshipType: isHeader ? RelType.header : RelType.footer,
      contentType: isHeader ? ContentType.wmlHeader : ContentType.wmlFooter,
    )..create(content, reservedIds: reservedIds);
    _slot = slot;
    _reference.relId = slot.relationshipId!;
  }

  /// Reads the part. Nothing is loaded when it throws.
  List<DocxBlock> _load() {
    final RelatedPart slot = _slot!;
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

/// Whether [block] is a paragraph that holds nothing, which is no content.
bool _isBlank(DocxBlock block) =>
    block is DocxParagraph && block.inlines.isEmpty;

/// The move of a new story out of the empty ones: a section refers to it now.
final class _StoryAttached implements Change {
  _StoryAttached(this._document, this._story, this._key);

  final DocxDocument _document;
  final _Story _story;
  final _EmptyStoryKey _key;

  @override
  void revert() {
    _story._attached = false;
    _document._emptyStories[_key] = _story;
  }

  @override
  void reapply() {
    _story._attached = true;
    _document._emptyStories.remove(_key);
  }
}
