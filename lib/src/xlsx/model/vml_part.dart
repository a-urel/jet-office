/// A VML drawing part (`xl/drawings/vmlDrawingN.vml`): the boxes of a
/// sheet's notes, kept as the text it was written as.
///
/// Not ported from Quds; written for jet_office.
///
/// Excel's VML is not always XML, and it holds form controls and shapes
/// beside notes, so the part is kept as text cut at its `<v:shape>`
/// elements: the `head` before the first shape, each `VmlShape` with the
/// text after it, and the `tail`. Joined again the pieces are the source,
/// character for character. Only what a note needs is read from a shape:
/// the row and column of an `ObjectType="Note"` and whether it has
/// `<x:Visible/>`. A later edit adds and removes shapes in `shapes`; the
/// rest of the part stays as written.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/package.dart';
import '../../xml/xml_pull_reader.dart';

/// One `<v:shape>` directly under the root of a VML part.
final class VmlShape {
  /// Creates a shape of [source], followed by [after]. [row], [column] and
  /// [visible] are given for a note's box and `null` or `false` otherwise.
  VmlShape({
    required this.source,
    required this.after,
    this.isNote = false,
    this.row,
    this.column,
    this.visible = false,
  });

  /// The shape as written, from `<` to the end of its closing tag.
  final String source;

  /// The text from the end of the shape to the start of the next shape; for
  /// the last shape the part's tail has the rest, so this is empty.
  final String after;

  /// Whether the shape's `<x:ClientData>` has `ObjectType="Note"`.
  final bool isNote;

  /// The zero-based row of a note's cell (`<x:Row>`); `null` for another
  /// shape or when it cannot be read.
  final int? row;

  /// The zero-based column of a note's cell (`<x:Column>`); `null` as for
  /// [row].
  final int? column;

  /// Whether the shape has `<x:Visible/>`, so its note is always shown.
  final bool visible;
}

/// A VML part cut at its shapes.
final class VmlPart implements PartContent {
  VmlPart._(this.head, this.shapes, this.tail, this.blocks);

  /// Reads [source], or returns `null` when it is not well formed XML,
  /// which Excel's older VML often is; the model then leaves the part as
  /// written and reads no visibility from it.
  static VmlPart? read(String source) {
    try {
      return _read(source);
    } on XmlParseException {
      return null;
    }
  }

  /// The text before the first shape (the whole part when it has none).
  final String head;

  /// The shapes in file order; an edit adds and removes entries.
  final List<VmlShape> shapes;

  /// The text after the last shape.
  final String tail;

  /// The drawing blocks `<o:idmap data="...">` lists: each block holds 1,024
  /// shape ids, and a new shape's id must come from a block listed here.
  final Set<int> blocks;

  @override
  List<Uint8List> encode() {
    final StringBuffer out = StringBuffer(head);
    for (final VmlShape shape in shapes) {
      out
        ..write(shape.source)
        ..write(shape.after);
    }
    out.write(tail);
    return <Uint8List>[Uint8List.fromList(utf8.encode(out.toString()))];
  }
}

VmlPart _read(String source) {
  final XmlPullReader r = XmlPullReader(source);
  final Set<int> blocks = <int>{};
  final List<(int, int, bool, bool, int?, int?)> found =
      <(int, int, bool, bool, int?, int?)>[];
  while (r.next()) {
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth == 1) continue;
    if (r.localName == 'idmap' && r.namespaceUri == Ns.vmlOffice) {
      for (final String id
          in (r.getAttribute('data', namespaceUri: '') ?? '').split(',')) {
        final int? block = int.tryParse(id.trim());
        if (block != null) blocks.add(block);
      }
      continue;
    }
    if (r.depth == 2 && r.localName == 'shape' && r.namespaceUri == Ns.vml) {
      final int start = r.eventStart;
      final _Client client = _Client();
      final int depth = r.depth;
      if (r.isEmptyElement) {
        r.skip();
      } else {
        while (r.next()) {
          if (r.eventType == XmlEventType.endElement && r.depth < depth) {
            break;
          }
          if (r.eventType != XmlEventType.startElement) continue;
          if (r.depth == depth + 1 &&
              r.localName == 'ClientData' &&
              r.namespaceUri == Ns.vmlExcel) {
            client.read(r);
          } else {
            r.skip();
          }
        }
      }
      found.add((
        start,
        r.eventEnd,
        client.isNote,
        client.visible,
        client.row,
        client.column,
      ));
    }
  }
  if (found.isEmpty) return VmlPart._(source, <VmlShape>[], '', blocks);
  final List<VmlShape> shapes = <VmlShape>[];
  for (int i = 0; i < found.length; i++) {
    final (int start, int end, bool isNote, bool visible, int? row, int? col) =
        found[i];
    final int next = i + 1 < found.length ? found[i + 1].$1 : end;
    shapes.add(
      VmlShape(
        source: source.substring(start, end),
        after: source.substring(end, next),
        isNote: isNote,
        row: row,
        column: col,
        visible: visible,
      ),
    );
  }
  return VmlPart._(
    source.substring(0, found.first.$1),
    shapes,
    source.substring(found.last.$2),
    blocks,
  );
}

/// What a note needs from a shape's `<x:ClientData>`.
final class _Client {
  bool isNote = false;
  bool visible = false;
  int? row;
  int? column;

  /// Reads the `<x:ClientData>` [r] is on, leaving [r] on its end.
  void read(XmlPullReader r) {
    isNote = r.getAttribute('ObjectType', namespaceUri: '') == 'Note';
    if (r.isEmptyElement) {
      r.skip();
      return;
    }
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType != XmlEventType.startElement) continue;
      final bool direct = r.depth == depth + 1 && r.namespaceUri == Ns.vmlExcel;
      if (direct && r.localName == 'Visible') {
        visible = true;
        r.skip();
      } else if (direct && (r.localName == 'Row' || r.localName == 'Column')) {
        final bool isRow = r.localName == 'Row';
        final StringBuffer text = StringBuffer();
        if (!r.isEmptyElement) {
          final int own = r.depth;
          while (r.next()) {
            if (r.eventType == XmlEventType.endElement && r.depth < own) {
              break;
            }
            if (r.eventType == XmlEventType.characters) text.write(r.text);
          }
        }
        final int? parsed = int.tryParse(text.toString().trim());
        final int? value = parsed != null && parsed >= 0 ? parsed : null;
        if (isRow) {
          row ??= value;
        } else {
          column ??= value;
        }
      } else {
        r.skip();
      }
    }
  }
}
