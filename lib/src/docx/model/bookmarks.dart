/// Bookmarks: [DocxBookmarkStart] and [DocxBookmarkEnd], and the rule that
/// repairs a name ([repairBookmarkName]).
///
/// Not ported from Quds; written for jet_office. It is a part of the inlines'
/// library because [DocxInline] is sealed.
///
/// A bookmark is two marks, `w:bookmarkStart` and `w:bookmarkEnd`, that
/// share an id and may sit in different paragraphs; nothing pairs them when
/// a file is read (plan D5, Ruling 10). A mark read from a file keeps its
/// element, so it is written as read, with every attribute it had. A mark the
/// API builds holds no id: each save allocates one and stores nothing back,
/// so a save stays a function of the model (Ruling A), and a built end takes
/// its start's id within that save.
part of 'inlines.dart';

/// The most characters Word allows in a bookmark's name.
const int maxBookmarkNameLength = 40;

final RegExp _bookmarkLetter = RegExp(r'\p{L}', unicode: true);
final RegExp _bookmarkNameCharacter = RegExp(r'[\p{L}\p{Nd}_]', unicode: true);

/// [name] as Word accepts it for a bookmark: at most 40 characters, a letter
/// first, then letters, digits and `_`.
///
/// Every character that is none of those becomes `_`; a first character that
/// is not a letter gets `B` in front of it (so `2 Totals!` becomes
/// `B2_Totals_`, and an empty name becomes `B`); the result is cut to 40
/// characters. A name that follows the rules comes back as it is.
String repairBookmarkName(String name) {
  final List<String> characters = <String>[];
  for (final int rune in name.runes) {
    final String c = String.fromCharCode(rune);
    characters.add(_bookmarkNameCharacter.hasMatch(c) ? c : '_');
  }
  if (characters.isEmpty || !_bookmarkLetter.hasMatch(characters.first)) {
    characters.insert(0, 'B');
  }
  if (characters.length > maxBookmarkNameLength) {
    characters.length = maxBookmarkNameLength;
  }
  return characters.join();
}

/// The start of a bookmark, `w:bookmarkStart`.
///
/// Build one with [DocxParagraph.addBookmarkStart]; a file's are read as they
/// are. Its end, [DocxBookmarkEnd], may be in another paragraph.
final class DocxBookmarkStart extends DocxInline {
  DocxBookmarkStart._read(this._xml, this.id, this.name)
    : _repairedFrom = null,
      super._();

  DocxBookmarkStart._built(this.name, this._repairedFrom)
    : _xml = null,
      id = null,
      super._();

  /// The element as read, written back as it is; `null` for one built.
  final OpaqueXml? _xml;

  /// The name as given when the API repaired it, or `null`.
  final String? _repairedFrom;

  /// The `w:id` the file gave, or `null` when it gave none that is a
  /// non-negative whole number, and for every start the API built: a save
  /// allocates the id of a built start and does not store it here.
  final int? id;

  /// The `w:name`, `''` when the file gave none. A name the API was given
  /// that breaks Word's rules is repaired ([repairBookmarkName]) and the
  /// save reports it (`DocxWarningCode.bookmarkNameRepaired`).
  final String name;

  /// A bookmark mark shows no text.
  @override
  String get text => '';

  @override
  String toString() => 'DocxBookmarkStart($name)';
}

/// The end of a bookmark, `w:bookmarkEnd`.
///
/// Build one with [DocxParagraph.addBookmarkEnd].
final class DocxBookmarkEnd extends DocxInline {
  DocxBookmarkEnd._read(this._xml, this.id) : start = null, super._();

  DocxBookmarkEnd._built(this.start) : _xml = null, id = null, super._();

  /// The element as read, written back as it is; `null` for one built.
  final OpaqueXml? _xml;

  /// The `w:id` the file gave, or `null` when it gave none that is a
  /// non-negative whole number, and for every end the API built: a save
  /// writes its [start]'s id.
  final int? id;

  /// The start this end was built for, or `null` for an end read from a
  /// file (nothing pairs the marks of a file when it is read).
  final DocxBookmarkStart? start;

  /// A bookmark mark shows no text.
  @override
  String get text => '';

  @override
  String toString() => 'DocxBookmarkEnd(${start?.name ?? id})';
}

/// A start the reader found: [xml] is the element, [id] and [name] its
/// attributes as read.
DocxBookmarkStart readBookmarkStart(OpaqueXml xml, int? id, String name) =>
    DocxBookmarkStart._read(xml, id, name);

/// An end the reader found.
DocxBookmarkEnd readBookmarkEnd(OpaqueXml xml, int? id) =>
    DocxBookmarkEnd._read(xml, id);

/// A start for [name], repaired by [repairBookmarkName].
DocxBookmarkStart newBookmarkStart(String name) {
  final String repaired = repairBookmarkName(name);
  return DocxBookmarkStart._built(repaired, repaired == name ? null : name);
}

/// An end for [start].
DocxBookmarkEnd newBookmarkEnd(DocxBookmarkStart start) =>
    DocxBookmarkEnd._built(start);

/// What the writer needs of a bookmark mark: the element it was read as, or
/// `null` for one the API built.
OpaqueXml? bookmarkXml(DocxInline mark) => mark is DocxBookmarkStart
    ? mark._xml
    : mark is DocxBookmarkEnd
    ? mark._xml
    : null;

/// The name [start] was given when the API repaired it, or `null`.
String? bookmarkRepairedFrom(DocxBookmarkStart start) => start._repairedFrom;
