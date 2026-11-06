/// A comments part (`xl/commentsN.xml`): the text and author of a sheet's
/// notes, each `<comment>` kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// The part is read, not rewritten: every `<comment>` keeps its source
/// ([OpaqueXml]) beside the typed cell, text and author, so a note nobody
/// edits is written back character for character. The `<authors>` strings,
/// the root and every other child of the root (an `<extLst>`, a second
/// `<commentList>`) are kept as well. A later edit changes `entries` and
/// `authors`, which are mutable lists, and `encode` writes the part from them.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../cell_ref.dart';
import '../limits.dart';
import '../read/read_limits.dart';
import '../rich_text.dart';
import 'item_group.dart' show checkListRoom, readerOf;

/// Reports a problem with an entry the part could not read, by detail:
/// `comment` for a `<comment>` whose cell or author cannot be read and
/// `rPr` for a run font the model cannot hold.
typedef WarnFn = void Function(String detail);

/// One `<comment>`: where it is, what it says, who wrote it and the element
/// as written.
final class CommentEntry {
  /// Creates an entry; [row] and [column] are `null` for an entry that sits
  /// on no readable, free cell.
  CommentEntry({
    required this.row,
    required this.column,
    required this.text,
    required this.author,
    required this.source,
  });

  /// The zero-based row of the cell, or `null` when the `ref` cannot be read
  /// or the cell already has an entry.
  int? row;

  /// The zero-based column of the cell, or `null` as for [row].
  int? column;

  /// The note's text, in runs. Plain `<t>` text is one run with no font.
  XlsxRichText text;

  /// The author the entry's `authorId` names; empty when it names none.
  String author;

  /// The `<comment>` as written.
  OpaqueXml source;
}

/// A comments part with its authors and entries typed and every other
/// element kept as written.
final class CommentsPart implements PartContent {
  CommentsPart._(
    this.root,
    this.authors,
    this.entries,
    this.trailing,
    this._authorsWritten,
  );

  /// Reads the comments part [r] is positioned before, or returns `null`
  /// when the root is not a SpreadsheetML `<comments>`.
  ///
  /// Only the first `<authors>` and the first `<commentList>` are typed;
  /// any other child of the root is kept in [trailing]. A `<comment>` whose
  /// `ref` cannot be read, or that repeats a cell, is kept with a `null`
  /// [CommentEntry.row] and reported to [warn] as `comment`; so is a
  /// missing, unreadable or out-of-range `authorId`, which reads author
  /// `''`. A run font the model cannot hold is reported as `rPr`.
  ///
  /// Throws an `XlsxReadException` (`limitExceeded`, naming `maxMerges` and
  /// [part]) when the part holds more authors, comments or other children
  /// than [limits] allows, and XML errors as [r] reads.
  static CommentsPart? read(
    XmlPullReader r, {
    required WarnFn warn,
    XlsxReadLimits limits = const XlsxReadLimits(),
    String part = '',
  }) {
    XmlRoot? root;
    final List<String> authors = <String>[];
    final List<OpaqueXml> raws = <OpaqueXml>[];
    final List<OpaqueXml> trailing = <OpaqueXml>[];
    bool authorsRead = false;
    bool listRead = false;
    bool authorsWritten = false;
    int count = 0;
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.depth == 1) {
        if (r.localName != 'comments' || r.namespaceUri != Ns.main) {
          return null;
        }
        root = XmlRoot.capture(r);
        continue;
      }
      if (r.depth != 2) continue;
      if (r.namespaceUri == Ns.main &&
          r.localName == 'authors' &&
          !authorsRead) {
        authorsRead = true;
        authorsWritten = true;
        _readAuthors(r, authors, () => checkListRoom(count++, limits, part));
      } else if (r.namespaceUri == Ns.main &&
          r.localName == 'commentList' &&
          !listRead) {
        listRead = true;
        if (!r.isEmptyElement) {
          final int depth = r.depth;
          while (r.next()) {
            if (r.eventType == XmlEventType.endElement && r.depth < depth) {
              break;
            }
            if (r.eventType != XmlEventType.startElement) continue;
            checkListRoom(count++, limits, part);
            if (r.depth == depth + 1 &&
                r.localName == 'comment' &&
                r.namespaceUri == Ns.main) {
              raws.add(OpaqueXml.capture(r));
            } else {
              r.skip();
            }
          }
        } else {
          r.skip();
        }
      } else {
        checkListRoom(count++, limits, part);
        trailing.add(OpaqueXml.capture(r));
      }
    }
    if (root == null) return null;
    final Set<int> taken = <int>{};
    final List<CommentEntry> entries = <CommentEntry>[
      for (final OpaqueXml raw in raws) _entry(raw, authors, taken, warn),
    ];
    return CommentsPart._(root, authors, entries, trailing, authorsWritten);
  }

  /// The start tag of the root, kept as written.
  final XmlRoot root;

  /// The `<author>` strings, decoded, in file order.
  final List<String> authors;

  /// Every `<comment>` of the first `<commentList>`, in file order, listed
  /// or not.
  final List<CommentEntry> entries;

  /// The other children of the root, kept as written, written after the
  /// comment list.
  final List<OpaqueXml> trailing;

  final bool _authorsWritten;

  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    root.writeStart(w);
    final int colon = root.qualifiedName.indexOf(':');
    final String prefix = colon < 0
        ? ''
        : root.qualifiedName.substring(0, colon + 1);
    if (_authorsWritten || authors.isNotEmpty) {
      w.start('${prefix}authors');
      for (final String author in authors) {
        w
          ..start('${prefix}author')
          ..text(escapeXstring(author))
          ..end();
      }
      w.end();
    }
    w.start('${prefix}commentList');
    for (final CommentEntry e in entries) {
      e.source.writeTo(w, declaredAbove: root.namespaces);
    }
    w.end();
    for (final OpaqueXml child in trailing) {
      child.writeTo(w, declaredAbove: root.namespaces);
    }
    w.end();
    return buffer.takeChunks();
  }
}

/// Reads the `<authors>` [r] is on into [authors], calling [room] before
/// each author.
void _readAuthors(XmlPullReader r, List<String> authors, void Function() room) {
  if (r.isEmptyElement) {
    r.skip();
    return;
  }
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    room();
    if (r.depth != depth + 1 ||
        r.localName != 'author' ||
        r.namespaceUri != Ns.main) {
      r.skip();
      continue;
    }
    final StringBuffer text = StringBuffer();
    if (!r.isEmptyElement) {
      final int own = r.depth;
      while (r.next()) {
        if (r.eventType == XmlEventType.endElement && r.depth < own) break;
        if (r.eventType == XmlEventType.characters ||
            r.eventType == XmlEventType.cdata) {
          text.write(r.text);
        }
      }
    }
    authors.add(decodeXstring(text.toString()));
  }
}

/// The typed [CommentEntry] of the `<comment>` [source].
CommentEntry _entry(
  OpaqueXml source,
  List<String> authors,
  Set<int> taken,
  WarnFn warn,
) {
  final XmlPullReader r = readerOf(source);
  final ({int row, int column})? cell = _cell(r.getAttribute('ref'));
  int? row;
  int? column;
  if (cell == null ||
      !taken.add(cell.row * XlsxLimits.maxColumns + cell.column)) {
    warn('comment');
  } else {
    row = cell.row;
    column = cell.column;
  }
  final int? id = int.tryParse(r.getAttribute('authorId')?.trim() ?? '');
  String author = '';
  if (id == null || id < 0 || id >= authors.length) {
    warn('comment');
  } else {
    author = authors[id];
  }
  XlsxRichText? text;
  if (!r.isEmptyElement) {
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.depth == depth + 1 &&
          r.localName == 'text' &&
          r.namespaceUri == Ns.main &&
          text == null) {
        text = readRichTextRuns(r, warn) ?? _plain(source);
      } else {
        r.skip();
      }
    }
  }
  return CommentEntry(
    row: row,
    column: column,
    text: text ?? XlsxRichText(const <XlsxTextRun>[]),
    author: author,
    source: source,
  );
}

/// The plain text of the `<text>` of the `<comment>` [source] as one run
/// without a font: its direct `<t>` children joined, decoded. Empty text
/// when it has none.
XlsxRichText _plain(OpaqueXml source) {
  final XmlPullReader r = readerOf(source);
  final StringBuffer text = StringBuffer();
  int textDepth = -1;
  while (r.next()) {
    if (r.eventType != XmlEventType.startElement) continue;
    if (textDepth < 0) {
      if (r.depth == 3 && r.localName == 'text' && r.namespaceUri == Ns.main) {
        if (r.isEmptyElement) break;
        textDepth = r.depth;
      }
      continue;
    }
    if (r.depth == textDepth + 1 &&
        r.localName == 't' &&
        r.namespaceUri == Ns.main &&
        !r.isEmptyElement) {
      final int own = r.depth;
      while (r.next()) {
        if (r.eventType == XmlEventType.endElement && r.depth < own) break;
        if (r.eventType == XmlEventType.characters ||
            r.eventType == XmlEventType.cdata) {
          text.write(r.text);
        }
      }
    } else {
      r.skip();
    }
  }
  final String value = decodeXstring(text.toString());
  return XlsxRichText(
    value.isEmpty ? const <XlsxTextRun>[] : <XlsxTextRun>[XlsxTextRun(value)],
  );
}

({int row, int column})? _cell(String? ref) {
  if (ref == null) return null;
  try {
    return parseCellRef(ref.trim());
  } on ArgumentError {
    return null;
  }
}
