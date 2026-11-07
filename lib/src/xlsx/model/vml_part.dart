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
/// `<x:Visible/>`. An edit adds, removes and swaps shapes through `swapShape`
/// and swaps the `frame` around them; the rest of the part stays as written.
/// A new shape is the writer's (`vmlShape`) and goes after the last one.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/package.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../note.dart';
import '../read/read_limits.dart';
import 'item_group.dart' show checkListRoom;

/// One `<v:shape>` directly under the root of a VML part.
final class VmlShape {
  /// Creates a shape of [source], followed by [after]. [row], [column] and
  /// [visible] are given for a note's box and `null` or `false` otherwise.
  /// [tagEnd], [clientEnd], [visibleStart] and [visibleEnd] are offsets into
  /// [source], -1 for none.
  VmlShape({
    required this.source,
    required this.after,
    this.isNote = false,
    this.row,
    this.column,
    this.visible = false,
    this.tagEnd = -1,
    this.clientEnd = -1,
    this.clientPrefix = '',
    this.visibleStart = -1,
    this.visibleEnd = -1,
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

  /// Where the shape's start tag ends.
  final int tagEnd;

  /// Where the end tag of the `<x:ClientData>` starts.
  final int clientEnd;

  /// The prefix of the `<x:ClientData>`, with its colon.
  final String clientPrefix;

  /// Where the `<x:Visible/>` starts.
  final int visibleStart;

  /// Where the `<x:Visible/>` ends.
  final int visibleEnd;

  /// This shape followed by [text] instead of [after].
  VmlShape withAfter(String text) => VmlShape(
    source: source,
    after: text,
    isNote: isNote,
    row: row,
    column: column,
    visible: visible,
    tagEnd: tagEnd,
    clientEnd: clientEnd,
    clientPrefix: clientPrefix,
    visibleStart: visibleStart,
    visibleEnd: visibleEnd,
  );
}

/// What surrounds the shapes of a VML part. An edit that touches it swaps
/// the whole value, so an undo restores it.
final class VmlFrame {
  /// A frame of [head] and [tail] whose part uses [blocks].
  const VmlFrame({
    required this.head,
    required this.tail,
    required this.blocks,
    required this.rootEnd,
    required this.selfClosed,
    required this.idmapStart,
    required this.idmapEnd,
    required this.hasNoteType,
  });

  /// The text before the first shape. A part with no shape has all of it
  /// here, up to the root's end tag.
  final String head;

  /// The text after the last shape.
  final String tail;

  /// The drawing blocks `<o:idmap data="...">` lists: each block holds 1,024
  /// shape ids, and a new shape's id must come from a block listed here.
  final Set<int> blocks;

  /// Where the root's start tag ends in [head].
  final int rootEnd;

  /// Whether the root is an empty element, which cannot hold a shape yet.
  final bool selfClosed;

  /// Where the first `<o:idmap>` tag starts in [head], or -1 when [head] has
  /// none.
  final int idmapStart;

  /// Where that tag ends in [head].
  final int idmapEnd;

  /// Whether the part has the `<v:shapetype>` a note's box names.
  final bool hasNoteType;

  /// This frame with [text] added to the end of [head].
  VmlFrame withHeadEnding(String text) => _copy(head: '$head$text');

  VmlFrame _copy({
    String? head,
    String? tail,
    Set<int>? blocks,
    int? rootEnd,
    bool? selfClosed,
    int? idmapStart,
    int? idmapEnd,
    bool? hasNoteType,
  }) => VmlFrame(
    head: head ?? this.head,
    tail: tail ?? this.tail,
    blocks: blocks ?? this.blocks,
    rootEnd: rootEnd ?? this.rootEnd,
    selfClosed: selfClosed ?? this.selfClosed,
    idmapStart: idmapStart ?? this.idmapStart,
    idmapEnd: idmapEnd ?? this.idmapEnd,
    hasNoteType: hasNoteType ?? this.hasNoteType,
  );
}

/// A new note's box for the end of a part's shapes, and the frame the part
/// needs around it.
typedef VmlPlan = ({VmlFrame frame, VmlShape shape});

/// A VML part cut at its shapes.
final class VmlPart implements PartContent {
  VmlPart._(
    this.frame,
    this.shapes,
    this._rootStart,
    this._rootOpen,
    this._rootName,
    this._namespaces,
    this.holdsOther,
  );

  /// Reads [source], or returns `null` when it is not well formed XML,
  /// which Excel's older VML often is; the model then leaves the part as
  /// written and reads no visibility from it.
  ///
  /// Throws a `limitExceeded` `XlsxReadException` naming `maxMerges` and
  /// [partName] when the source holds more shapes than [limits] allows, as the
  /// comments part does for its entries.
  static VmlPart? read(
    String source, {
    XlsxReadLimits limits = const XlsxReadLimits(),
    String partName = '',
  }) {
    try {
      final VmlPart read = _read(source, limits, partName);
      return read._rootName.isEmpty ? null : read;
    } on XmlParseException {
      return null;
    }
  }

  /// A new part without shapes that lists [block], as the writer starts one.
  factory VmlPart.empty(int block) {
    final StringBuffer out = StringBuffer();
    writeVmlDrawing(XmlWriter(out), const <WorksheetNote>[], block);
    return _read(out.toString(), const XlsxReadLimits(), '');
  }

  /// What surrounds the shapes.
  VmlFrame frame;

  /// The text before the first shape; a part with no shape has all of it
  /// here, up to the root's end tag.
  String get head => frame.head;

  /// The shapes in file order; an edit changes them through [swapShape].
  final List<VmlShape> shapes;

  /// The text after the last shape.
  String get tail => frame.tail;

  /// The drawing blocks `<o:idmap data="...">` lists: each block holds 1,024
  /// shape ids, and a new shape's id must come from a block listed here.
  Set<int> get blocks => frame.blocks;

  /// Whether the root holds an element beside its shapes that draws
  /// something (a `<v:rect>`, a `<v:group>`), so the part outlives its last
  /// shape.
  final bool holdsOther;

  /// Where the root's start tag starts; what comes before it never changes.
  final int _rootStart;

  /// The root's start tag, as a tag that opens it.
  final String _rootOpen;

  /// The root's name as written.
  final String _rootName;

  /// The namespaces the root declares.
  final Map<String, String> _namespaces;

  /// The highest shape id and z-index in the part, once asked for; a removal
  /// forgets them.
  ({int id, int z})? _top;

  ({int id, int z}) get _highest {
    final ({int id, int z})? known = _top;
    if (known != null) return known;
    ({int id, int z}) top = _higher(_topOf(head), _topOf(tail));
    for (final VmlShape shape in shapes) {
      top = _higher(_higher(top, _topOf(shape.source)), _topOf(shape.after));
    }
    return _top = top;
  }

  /// The indexes in [shapes] of the boxes of the note on the cell at [row],
  /// [column].
  List<int> noteShapes(int row, int column) => <int>[
    for (int i = 0; i < shapes.length; i++)
      if (shapes[i].isNote &&
          shapes[i].row == row &&
          shapes[i].column == column)
        i,
  ];

  /// Replaces [from] at [index] of [shapes] by [to]; a `null` [from] inserts
  /// [to] there, a `null` [to] removes [from].
  void swapShape(int index, VmlShape? from, VmlShape? to) {
    if (to == null) {
      shapes.removeAt(index);
      _top = null;
    } else if (from != null) {
      shapes[index] = to;
    } else {
      shapes.insert(index, to);
      final ({int id, int z})? top = _top;
      if (top != null) _top = _higher(top, _topOf(to.source));
    }
  }

  /// The box of [note] for the end of [shapes], with the frame it needs: an
  /// id one above the part's highest and a z-index likewise, the root opened
  /// when it was empty, the shape type added when the part has none and,
  /// past the part's blocks, a block from [takeBlock] added to `o:idmap`.
  /// The part does not change.
  VmlPlan plan(WorksheetNote note, int Function() takeBlock) {
    final ({int id, int z}) top = _highest;
    VmlFrame next = frame;
    if (next.selfClosed) {
      next = next._copy(
        head: '${next.head.substring(0, _rootStart)}$_rootOpen',
        tail: '</$_rootName>${next.head.substring(next.rootEnd)}',
        rootEnd: _rootStart + _rootOpen.length,
        selfClosed: false,
      );
    }
    int id = top.id == 0 && next.blocks.isNotEmpty
        ? vmlBlockSize * _lowest(next.blocks) + 1
        : top.id + 1;
    if (!next.blocks.contains(id ~/ vmlBlockSize)) {
      final int block = takeBlock();
      if (id ~/ vmlBlockSize != block) id = vmlBlockSize * block + 1;
      next = _listed(next, block);
    }
    final String declarations = _declarations();
    if (!next.hasNoteType) {
      next = next
          .withHeadEnding(vmlNoteShapeType(declarations: declarations))
          ._copy(hasNoteType: true);
    }
    return (
      frame: next,
      shape: _parse(
        vmlShape(id, top.z + 1, note, declarations: declarations),
        '',
      ),
    );
  }

  /// [shape] shown all the time or only on hover, as [visible] says: the
  /// `visibility:` of its style and its `<x:Visible/>` changed, the rest as
  /// written.
  VmlShape withVisible(VmlShape shape, bool visible) {
    final String source = shape.source;
    final int tagEnd = shape.tagEnd;
    String body = source.substring(tagEnd);
    if (visible && shape.clientEnd >= 0 && shape.visibleStart < 0) {
      final int at = shape.clientEnd - tagEnd;
      body =
          '${body.substring(0, at)}<${shape.clientPrefix}Visible/>'
          '${body.substring(at)}';
    } else if (!visible && shape.visibleStart >= 0) {
      body =
          '${body.substring(0, shape.visibleStart - tagEnd)}'
          '${body.substring(shape.visibleEnd - tagEnd)}';
    }
    final String word = visible ? 'visible' : 'hidden';
    return _parse(
      '${_styled(source.substring(0, tagEnd), word)}$body',
      shape.after,
    );
  }

  /// [text] as a shape followed by [after], read under the part's root.
  VmlShape _parse(String text, String after) => _read(
    '$_rootOpen$text</$_rootName>',
    const XlsxReadLimits(),
    '',
  ).shapes.single.withAfter(after);

  /// The declarations a new element needs for the prefixes `v`, `o` and `x`:
  /// those the root does not bind to the VML namespaces.
  String _declarations() {
    final StringBuffer out = StringBuffer();
    const Map<String, String> wanted = <String, String>{
      'v': Ns.vml,
      'o': Ns.vmlOffice,
      'x': Ns.vmlExcel,
    };
    wanted.forEach((String prefix, String uri) {
      if (_namespaces[prefix] != uri) out.write(' xmlns:$prefix="$uri"');
    });
    return out.toString();
  }

  /// [frame] with [block] listed in its `o:idmap`, or in a new
  /// `<o:shapelayout>` when its head has none.
  VmlFrame _listed(VmlFrame frame, int block) {
    final Set<int> blocks = <int>{...frame.blocks, block};
    final String head = frame.head;
    if (frame.idmapStart < 0) {
      final String layout = vmlShapeLayout(<int>[
        block,
      ], declarations: _declarations());
      final int at = frame.rootEnd;
      return frame._copy(
        head: '${head.substring(0, at)}$layout${head.substring(at)}',
        blocks: blocks,
        idmapStart: at + layout.indexOf('<o:idmap'),
        idmapEnd: at + layout.indexOf('/>') + 2,
      );
    }
    final String listed = _withBlock(
      head.substring(frame.idmapStart, frame.idmapEnd),
      block,
    );
    return frame._copy(
      head:
          '${head.substring(0, frame.idmapStart)}$listed'
          '${head.substring(frame.idmapEnd)}',
      blocks: blocks,
      idmapEnd: frame.idmapStart + listed.length,
    );
  }

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

/// A shape id or block longer than this is no number VML means: it is left
/// out, which also keeps every id exact on the web.
const int _maxDigits = 12;

final RegExp _shapeIdPattern = RegExp(r'_x0000_s(\d+)');
final RegExp _zIndexPattern = RegExp(r'z-index:\s*(\d+)');
final RegExp _idmapPattern = RegExp(
  r'''idmap\b[^>]*?(?<![\w:.-])data\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);
final RegExp _dataAttribute = RegExp(
  r'''(?<![\w:.-])data\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);
final RegExp _styleAttribute = RegExp(
  r'''(?<![\w:.-])style\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);
final RegExp _visibilityPattern = RegExp(r'visibility\s*:[^;]*');

int? _number(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > _maxDigits) return null;
  final int? value = int.tryParse(trimmed);
  return value == null || value < 0 ? null : value;
}

/// The blocks the `o:idmap` value [data] lists.
Iterable<int> _blocksOf(String data) => data.split(',').map(_number).nonNulls;

/// The VML id blocks [text], a `.vml` part that need not be XML, uses: those
/// its `o:idmap`s list and those its shape ids lie in.
Set<int> vmlBlocksIn(String text) => <int>{
  for (final Match m in _idmapPattern.allMatches(text))
    ..._blocksOf(m[1] ?? m[2] ?? ''),
  for (final Match m in _shapeIdPattern.allMatches(text))
    if (_number(m[1]!) case final int id) id ~/ vmlBlockSize,
};

int _lowest(Set<int> blocks) => blocks.reduce((int a, int b) => a < b ? a : b);

/// The highest shape id and z-index [text] names, 0 for none.
({int id, int z}) _topOf(String text) {
  int id = 0;
  int z = 0;
  for (final Match m in _shapeIdPattern.allMatches(text)) {
    final int? value = _number(m[1]!);
    if (value != null && value > id) id = value;
  }
  for (final Match m in _zIndexPattern.allMatches(text)) {
    final int? value = _number(m[1]!);
    if (value != null && value > z) z = value;
  }
  return (id: id, z: z);
}

({int id, int z}) _higher(({int id, int z}) a, ({int id, int z}) b) =>
    (id: a.id > b.id ? a.id : b.id, z: a.z > b.z ? a.z : b.z);

/// The `<o:idmap>` [tag] with [block] added to its `data`.
String _withBlock(String tag, int block) {
  final Match? data = _dataAttribute.firstMatch(tag);
  if (data == null) {
    final int at = tag.length - (tag.endsWith('/>') ? 2 : 1);
    return '${tag.substring(0, at)} data="$block"${tag.substring(at)}';
  }
  final String value = data[1] ?? data[2]!;
  final int end = data.end - 1;
  return '${tag.substring(0, end - value.length)}'
      '${value.trim().isEmpty ? '$block' : '$value,$block'}'
      '${tag.substring(end)}';
}

/// The shape's start [tag] with `visibility:` [word] in its style.
String _styled(String tag, String word) {
  final Match? style = _styleAttribute.firstMatch(tag);
  if (style == null) {
    final int at = tag.length - 1;
    return '${tag.substring(0, at)} style="visibility:$word"'
        '${tag.substring(at)}';
  }
  final String value = style[1] ?? style[2]!;
  final String next = _visibilityPattern.hasMatch(value)
      ? value.replaceFirst(_visibilityPattern, 'visibility:$word')
      : value.isEmpty
      ? 'visibility:$word'
      : '$value;visibility:$word';
  final int end = style.end - 1;
  return '${tag.substring(0, end - value.length)}$next${tag.substring(end)}';
}

VmlPart _read(String source, XlsxReadLimits limits, String partName) {
  final XmlPullReader r = XmlPullReader(source);
  final Set<int> blocks = <int>{};
  final List<_Found> found = <_Found>[];
  int rootStart = 0;
  int rootEnd = 0;
  int rootClose = -1;
  String rootName = '';
  bool selfClosed = false;
  Map<String, String> namespaces = const <String, String>{};
  int idmapStart = -1;
  int idmapEnd = -1;
  bool hasNoteType = false;
  bool holdsOther = false;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth == 0) {
      rootClose = r.eventStart;
    }
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth == 1) {
      rootStart = r.eventStart;
      rootEnd = r.eventEnd;
      rootName = r.qualifiedName;
      selfClosed = r.isEmptyElement;
      namespaces = Map<String, String>.of(r.declaredNamespaces);
      continue;
    }
    if (r.localName == 'idmap' && r.namespaceUri == Ns.vmlOffice) {
      blocks.addAll(_blocksOf(r.getAttribute('data', namespaceUri: '') ?? ''));
      if (idmapStart < 0) {
        idmapStart = r.eventStart;
        idmapEnd = r.eventEnd;
      }
      continue;
    }
    if (r.depth != 2) continue;
    if (r.localName == 'shape' && r.namespaceUri == Ns.vml) {
      final int start = r.eventStart;
      final int tagEnd = r.eventEnd;
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
      checkListRoom(found.length, limits, partName);
      found.add(_Found(start, tagEnd, r.eventEnd, client));
    } else if (r.localName == 'shapetype' && r.namespaceUri == Ns.vml) {
      if (r.getAttribute('id', namespaceUri: '') == '_x0000_t202') {
        hasNoteType = true;
      }
    } else if (r.localName != 'shapelayout' || r.namespaceUri != Ns.vmlOffice) {
      holdsOther = true;
    }
  }
  final int headEnd = found.isNotEmpty
      ? found.first.start
      : selfClosed || rootClose < 0
      ? source.length
      : rootClose;
  final List<VmlShape> shapes = <VmlShape>[];
  for (int i = 0; i < found.length; i++) {
    final _Found f = found[i];
    final int next = i + 1 < found.length ? found[i + 1].start : f.end;
    final _Client c = f.client;
    int offset(int at) => at < 0 ? -1 : at - f.start;
    shapes.add(
      VmlShape(
        source: source.substring(f.start, f.end),
        after: source.substring(f.end, next),
        isNote: c.isNote,
        row: c.row,
        column: c.column,
        visible: c.visible,
        tagEnd: f.tagEnd - f.start,
        clientEnd: offset(c.end),
        clientPrefix: c.prefix,
        visibleStart: offset(c.visibleStart),
        visibleEnd: offset(c.visibleEnd),
      ),
    );
  }
  final bool idmapInHead = idmapEnd >= 0 && idmapEnd <= headEnd;
  final String rootTag = source.substring(rootStart, rootEnd);
  return VmlPart._(
    VmlFrame(
      head: source.substring(0, headEnd),
      tail: source.substring(found.isEmpty ? headEnd : found.last.end),
      blocks: blocks,
      rootEnd: rootEnd,
      selfClosed: selfClosed,
      idmapStart: idmapInHead ? idmapStart : -1,
      idmapEnd: idmapInHead ? idmapEnd : -1,
      hasNoteType: hasNoteType,
    ),
    shapes,
    rootStart,
    selfClosed ? '${rootTag.substring(0, rootTag.length - 2)}>' : rootTag,
    rootName,
    namespaces,
    holdsOther,
  );
}

/// Where a shape lies in the source, and what its `<x:ClientData>` says.
final class _Found {
  _Found(this.start, this.tagEnd, this.end, this.client);

  final int start;
  final int tagEnd;
  final int end;
  final _Client client;
}

/// What a note needs from a shape's `<x:ClientData>`.
final class _Client {
  bool isNote = false;
  bool visible = false;
  int? row;
  int? column;

  /// Where its end tag starts, or -1 for an empty element.
  int end = -1;

  /// Its prefix, with the colon.
  String prefix = '';

  /// Where the `<x:Visible>` starts, or -1.
  int visibleStart = -1;

  /// Where the `<x:Visible>` ends, or -1.
  int visibleEnd = -1;

  /// Reads the `<x:ClientData>` [r] is on, leaving [r] on its end.
  void read(XmlPullReader r) {
    isNote = r.getAttribute('ObjectType', namespaceUri: '') == 'Note';
    final String name = r.qualifiedName;
    prefix = name.substring(0, name.indexOf(':') + 1);
    if (r.isEmptyElement) {
      r.skip();
      return;
    }
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) {
        end = r.eventStart;
        break;
      }
      if (r.eventType != XmlEventType.startElement) continue;
      final bool direct = r.depth == depth + 1 && r.namespaceUri == Ns.vmlExcel;
      if (direct && r.localName == 'Visible') {
        final int start = r.eventStart;
        visible = true;
        r.skip();
        if (visibleStart < 0) {
          visibleStart = start;
          visibleEnd = r.eventEnd;
        }
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
