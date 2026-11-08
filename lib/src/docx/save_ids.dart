/// The ids a save gives what the model built: drawing ids, bookmark ids and
/// relationship ids (plan D5, Rulings 7, 11 and 12).
///
/// Not ported from Quds; written for jet_office.
///
/// A built picture or bookmark holds no id in the model: each save allocates
/// one here and stores nothing back, so a save stays a function of the model
/// (Ruling A). One [SaveIds] serves one save; it is made only when something
/// new needs an id, and it reads the package only on the first question of
/// each kind.
///
/// The ids already used are found in the original bytes of the parts, with
/// the pull parser and without loading any part as a model (spec §4.5): an id
/// a file holds counts even where the model does not type it, in a part the
/// model never loaded, and in a block an edit removed, which an undo brings
/// back. Each scan stops at the end of the part's root, as the part's reader
/// does, so what a file holds after it does not fail a save.
///
/// A part that cannot be read keeps the ids found before it broke, and the
/// rest are unknown: a load of that part is what reports it, and a save of a
/// document whose broken part is copied as read must not fail on it. So
/// nothing here throws a [DocxReadException].
library;

import '../opc/ooxml.dart' show ContentType, Ns, RelType;
import '../opc/package.dart' show OpcPackage, OpcRelationship;
import '../xml/xml_pull_reader.dart';
import 'docx_package.dart';
import 'read_exception.dart';

/// The ids of one save, found in the package of a [DocxPackage].
final class SaveIds {
  /// Ids for a save of the package of a document; nothing is read until
  /// asked.
  SaveIds(DocxPackage package) : _package = package;

  final DocxPackage _package;

  int? _drawing;
  int? _bookmark;
  final Map<String, Set<String>> _references = <String, Set<String>>{};

  /// The content types of the WordprocessingML story parts: the main part
  /// in each of its four types, headers, footers, footnotes, endnotes and
  /// comments. A drawing or a bookmark id is unique across all of them.
  static const Set<String> storyTypes = <String>{
    ContentType.wmlDocument,
    ContentType.wmlTemplate,
    ContentType.wmlMacroDocument,
    ContentType.wmlMacroTemplate,
    ContentType.wmlHeader,
    ContentType.wmlFooter,
    ContentType.wmlFootnotes,
    ContentType.wmlEndnotes,
    ContentType.wmlComments,
  };

  /// A new `wp:docPr/@id` (which a picture's `pic:cNvPr/@id` repeats): one
  /// more than the highest in the original bytes of every story part and
  /// than any this save gave before, and at least 1.
  int nextDrawingId() {
    if (_drawing == null) _scanIds();
    return _drawing = _drawing! + 1;
  }

  /// A new bookmark id (`w:id` of `w:bookmarkStart` and its `w:bookmarkEnd`):
  /// one more than the highest in the original bytes of every story part and
  /// than any this save gave before, and at least 0.
  int nextBookmarkId() {
    if (_bookmark == null) _scanIds();
    return _bookmark = _bookmark! + 1;
  }

  /// Every relationship id the original bytes of [part] name: the value of
  /// each attribute in the relationships namespace (`r:id`, `r:embed`,
  /// `r:link` and the like) of any element, whether a relationship answers
  /// it or not. A new relationship of [part] takes none of them, or a
  /// reference that names nothing would come to name it.
  ///
  /// Empty for a part the file does not have, such as one this save adds.
  Set<String> fileReferenceIds(String part) {
    final OpcPackage opc = _package.package;
    final String key = opc.canonicalPartName(part) ?? part;
    final Set<String>? known = _references[key];
    if (known != null) return known;
    final Set<String> ids = <String>{};
    _references[key] = ids;
    _scan(key, (XmlPullReader r) {
      for (int i = 0; i < r.attributeCount; i++) {
        if (r.attributeNamespace(i) == Ns.rel) ids.add(r.attributeValue(i));
      }
    });
    return ids;
  }

  /// Adds a relationship of [type] to [target] to [part] (a part name) and
  /// returns its id: `rId<n>` with the lowest `n` that the part's
  /// relationships and [fileReferenceIds] leave free. With [external] the
  /// target is an outside address (`TargetMode="External"`).
  ///
  /// It parses the part's relationships, which the package then writes
  /// anew; call it only for a part that gets something new.
  String addRelationship(
    String part, {
    required String type,
    required String target,
    bool external = false,
  }) => _package.package.addRelationship(
    part,
    type: type,
    target: target,
    external: external,
    reservedIds: fileReferenceIds(part),
  );

  /// Finds the highest drawing and bookmark ids of every story part.
  void _scanIds() {
    int drawing = 0;
    int bookmark = -1;
    final OpcPackage opc = _package.package;
    final String main = _package.mainPart;
    // D4 accepts a header or footer part of any content type when a
    // relationship of the main part names it, so its ids count too.
    final Set<String> named = <String>{};
    for (final OpcRelationship rel in opc.relationshipsOf(main)) {
      if (rel.external ||
          (rel.type != RelType.header && rel.type != RelType.footer)) {
        continue;
      }
      final String? name = opc.canonicalPartName(opc.resolve(main, rel.target));
      if (name != null) named.add(name);
    }
    for (final String part in opc.partNames) {
      // The main part is read as a Word main part whatever its type.
      if (part != main &&
          !storyTypes.contains(opc.contentTypeOf(part)) &&
          !named.contains(part)) {
        continue;
      }
      _scan(part, (XmlPullReader r) {
        final String ns = r.namespaceUri;
        final String name = r.localName;
        if (ns == Ns.wp && name == 'docPr') {
          final int? id = parseOfficeId(r.getAttribute('id', namespaceUri: ''));
          if (id != null && id > drawing) drawing = id;
        } else if (ns == Ns.w &&
            (name == 'bookmarkStart' || name == 'bookmarkEnd')) {
          final int? id = parseOfficeId(
            r.getAttribute('id', namespaceUri: Ns.w),
          );
          if (id != null && id > bookmark) bookmark = id;
        }
      });
    }
    _drawing ??= drawing;
    _bookmark ??= bookmark;
  }

  /// Calls [onStart] on every start element of the original bytes of
  /// [part] up to the end of its root. A part the file lacks has none; one
  /// that breaks stops there (see the library comment).
  void _scan(String part, void Function(XmlPullReader r) onStart) {
    final OpcPackage opc = _package.package;
    if (!opc.hasPart(part)) return;
    try {
      _package.guard(part, () {
        final XmlPullReader r = XmlPullReader.fromBytes(
          opc.originalBytes(part),
          maxDepth: _package.limits.maxDepth,
        );
        while (r.next()) {
          if (r.eventType == XmlEventType.endElement && r.depth == 0) break;
          if (r.eventType == XmlEventType.startElement) onStart(r);
        }
      });
    } on DocxReadException {
      // Unknown from here on: see the library comment.
    }
  }
}

/// The largest id the model reads or counts: 15 decimal digits, which keeps
/// every value exact on the web. Reading a bookmark's id and reserving ids at
/// save use this one bound, so an id the model reads is an id a save avoids.
const int maxOfficeId = 999999999999999;

/// The id [value] states: decimal digits, surrounding white space allowed as
/// XML Schema collapses it, at most [maxOfficeId]; `null` for anything else.
int? parseOfficeId(String? value) {
  if (value == null) return null;
  final String digits = value.trim();
  if (digits.isEmpty || digits.length > 15) return null;
  for (int i = 0; i < digits.length; i++) {
    final int unit = digits.codeUnitAt(i);
    if (unit < 0x30 || unit > 0x39) return null;
  }
  return int.parse(digits);
}
