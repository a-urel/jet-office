/// The styles part of a workbook, typed as far as the model needs.
///
/// Not ported from Quds; written for jet_office.
///
/// A loaded part is always written from this model (spec §4.3). What the model
/// types is the `<numFmts>` group (each `<numFmt>` as its id and code) and the
/// `<cellXfs>` group (each `<xf>` as its `numFmtId` plus the element itself
/// as [OpaqueXml]). Everything else, such as fonts, fills, borders, cell
/// styles and extensions, is an [OpaqueXml] child at its original position,
/// and the root keeps its namespace declarations and `mc:Ignorable`.
///
/// `<cellXfs>` is append-only (spec §4.4): while a sheet is unloaded its
/// cells point at style indexes, so an existing `<xf>` never moves.
/// [StylesPart.withNumberFormat] appends a copy of an `<xf>` with another
/// number format, or reuses one it already made.
///
/// Only the first `<numFmts>` and the first `<cellXfs>` of the part are typed,
/// as in `readStyles`; a repeated group is kept opaque, so style indexes mean
/// the same in the reader and in the model.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../read/package_reader.dart'
    show strictSpreadsheetNs, strictUnsupported;
import '../read/read_exception.dart';
import '../read/read_limits.dart';
import '../read/styles_reader.dart';

/// The elements that follow `<cellXfs>` in the schema's sequence; a new
/// `<cellXfs>` goes before the first of them.
const Set<String> _afterCellXfs = <String>{
  'cellStyles',
  'dxfs',
  'tableStyles',
  'colors',
  'extLst',
};

/// A `<numFmt>` with a usable id and a `formatCode`.
final class _NumFmt {
  _NumFmt(
    this.qualifiedName,
    this.namespaces,
    this.id,
    this.rawCode,
    this.attributes,
  );

  final String qualifiedName;
  final Map<String, String> namespaces;
  final int id;

  /// The `formatCode` attribute as the XML parser gave it, so it is written
  /// back unchanged; [decodeXstring] gives the format code.
  final String rawCode;
  final List<KeptAttribute> attributes;

  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    _writeDeclarations(w, namespaces);
    w.attribute('numFmtId', '$id');
    w.attribute('formatCode', scrubXmlText(rawCode).text);
    writeKeptAttributes(
      w,
      attributes,
      declaredAbove: _merge(above, namespaces),
    );
    w.end();
  }
}

/// An `<xf>` of `<cellXfs>`: as read ([_opaque]) or as made by
/// [StylesPart.withNumberFormat] ([_text], already well-formed where it goes).
final class _Xf {
  _Xf.read(this.numFmtId, OpaqueXml this._opaque) : _text = null;
  _Xf.made(this.numFmtId, String this._text) : _opaque = null;

  /// The `numFmtId`, or `null` when it is unreadable.
  final int? numFmtId;
  final OpaqueXml? _opaque;
  final String? _text;

  void writeTo(XmlWriter w, Map<String, String> above) {
    final OpaqueXml? o = _opaque;
    if (o != null) {
      o.writeTo(w, declaredAbove: above);
    } else {
      w.raw(_text!);
    }
  }

  /// The element's text as written where it goes.
  String render(Map<String, String> above) {
    final StringBuffer b = StringBuffer();
    writeTo(XmlWriter(b), above);
    return b.toString();
  }
}

/// A typed group: `<numFmts>` or `<cellXfs>`, with its items in order. An item
/// is a [_NumFmt], an [_Xf] or an [OpaqueXml] the model does not type.
final class _Group {
  _Group(
    this.itemName,
    this.qualifiedName,
    this.namespaces,
    this.attributes,
    this.hasCount,
    this.items,
  );

  /// The local name of the group's items, `numFmt` or `xf`.
  final String itemName;
  final String qualifiedName;
  final Map<String, String> namespaces;
  final List<KeptAttribute> attributes;

  /// Whether the group is written with a `count`.
  final bool hasCount;
  final List<Object> items;

  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    _writeDeclarations(w, namespaces);
    final Map<String, String> inner = _merge(above, namespaces);
    if (hasCount) {
      var n = 0;
      for (final Object item in items) {
        if (item is _NumFmt ||
            item is _Xf ||
            (item is OpaqueXml &&
                item.localName == itemName &&
                item.namespaceUri == Ns.main)) {
          n++;
        }
      }
      w.attribute('count', '$n');
    }
    writeKeptAttributes(w, attributes, declaredAbove: inner);
    for (final Object item in items) {
      switch (item) {
        case _NumFmt():
          item.writeTo(w, inner);
        case _Xf():
          item.writeTo(w, inner);
        case OpaqueXml():
          item.writeTo(w, declaredAbove: inner);
      }
    }
    w.end();
  }
}

/// The styles of a workbook: its number formats and cell formats, typed, and
/// the rest of the part kept as written.
final class StylesPart implements PartContent {
  StylesPart._(
    this._root,
    this._children,
    this._numFmts,
    this._cellXfs,
    this._xfs,
  );

  /// Reads a styles part from [r], which must not have been advanced.
  ///
  /// Throws an [XlsxReadException] of reason `unsupportedFormat` for a Strict
  /// root, `malformedXml` for a root that is not a SpreadsheetML
  /// `<styleSheet>` (a part written from the model could not keep it), and
  /// `limitExceeded` when a group lists more than
  /// [XlsxReadLimits.maxCellFormats] `<numFmt>` or `<xf>` entries or a
  /// `formatCode` is longer than [XlsxReadLimits.maxTextLength] characters
  /// after decoding. An `XmlParseException` for XML that cannot be read
  /// passes through.
  ///
  /// A `<numFmt>` without a usable id or a `formatCode` is kept opaque and
  /// ignored, as in `readStyles`; the children of a `<numFmt>` (the schema
  /// has none) are not kept.
  factory StylesPart.read(XmlPullReader r, XlsxReadLimits limits) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement) {
      throw XlsxReadException(
        XlsxReadFailure.malformedXml,
        'The styles part has no root element.',
      );
    }
    if (r.namespaceUri == strictSpreadsheetNs) throw strictUnsupported();
    if (r.localName != 'styleSheet' || r.namespaceUri != Ns.main) {
      throw XlsxReadException(
        XlsxReadFailure.malformedXml,
        'The root of the styles part is not a styleSheet.',
      );
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<Object> children = <Object>[];
    _Group? numFmts;
    _Group? cellXfs;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < 1) break;
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.namespaceUri == Ns.main &&
          r.localName == 'numFmts' &&
          numFmts == null) {
        numFmts = _readGroup(r, limits, 'numFmt', _readNumFmt);
        children.add(numFmts);
      } else if (r.namespaceUri == Ns.main &&
          r.localName == 'cellXfs' &&
          cellXfs == null) {
        cellXfs = _readGroup(r, limits, 'xf', _readXf);
        children.add(cellXfs);
      } else {
        children.add(OpaqueXml.capture(r));
      }
    }
    final List<_Xf> xfs = <_Xf>[
      if (cellXfs != null) ...cellXfs.items.whereType<_Xf>(),
    ];
    return StylesPart._(root, children, numFmts, cellXfs, xfs);
  }

  final XmlRoot _root;
  final List<Object> _children;
  final _Group? _numFmts;
  _Group? _cellXfs;
  final List<_Xf> _xfs;
  StyleTable? _table;

  /// The cell formats by style index, as `readStyles` gives them for the same
  /// part. It reflects every `<xf>` [withNumberFormat] appended.
  StyleTable get table => _table ??= _buildTable();

  StyleTable _buildTable() {
    final Map<int, String> codes = <int, String>{};
    final _Group? group = _numFmts;
    if (group != null) {
      for (final _NumFmt n in group.items.whereType<_NumFmt>()) {
        codes[n.id] = decodeXstring(n.rawCode);
      }
    }
    final Map<int, CellFormat> shared = <int, CellFormat>{};
    return StyleTable.fromFormats(<CellFormat>[
      for (final _Xf xf in _xfs)
        if (xf.numFmtId == null)
          CellFormat.broken
        else
          shared.putIfAbsent(
            xf.numFmtId!,
            () => cellFormatFor(xf.numFmtId, codes),
          ),
    ]);
  }

  /// The index of an `<xf>` equal to that of [style] with its `numFmtId`
  /// replaced by [numFmtId] (and `applyNumberFormat="1"`).
  ///
  /// A [style] that is `null` or not an index of `<cellXfs>` stands for the
  /// first `<xf>`, as a broken style counts as General. An `<xf>` that
  /// already is the result is reused; otherwise one is appended, so no
  /// existing index moves. A part without any `<xf>` (or without
  /// `<cellXfs>`) gets a plain one first to copy from. Throws a
  /// [RangeError] for a negative [numFmtId].
  int withNumberFormat(int? style, int numFmtId) {
    RangeError.checkNotNegative(numFmtId, 'numFmtId');
    final _Group group = _cellXfs ??= _createCellXfs();
    final Map<String, String> above = _merge(
      _root.namespaces,
      group.namespaces,
    );
    final String baseText = style != null && style >= 0 && style < _xfs.length
        ? _xfs[style].render(above)
        : _xfs.isNotEmpty
        ? _xfs[0].render(above)
        : _plainXf(group.qualifiedName);
    final String made = _withNumFmt(baseText, numFmtId);
    for (var i = 0; i < _xfs.length; i++) {
      if (_xfs[i].numFmtId == numFmtId &&
          _withNumFmt(_xfs[i].render(above), numFmtId) == made) {
        return i;
      }
    }
    final _Xf xf = _Xf.made(numFmtId, made);
    group.items.add(xf);
    _xfs.add(xf);
    _table = null;
    return _xfs.length - 1;
  }

  _Group _createCellXfs() {
    final String qn = _root.qualifiedName;
    final int colon = qn.indexOf(':');
    final String prefix = colon < 0 ? '' : qn.substring(0, colon + 1);
    final _Group group = _Group(
      'xf',
      '${prefix}cellXfs',
      const <String, String>{},
      const <KeptAttribute>[],
      true,
      <Object>[],
    );
    var at = _children.length;
    for (var i = 0; i < _children.length; i++) {
      final Object c = _children[i];
      if (c is OpaqueXml &&
          c.namespaceUri == Ns.main &&
          _afterCellXfs.contains(c.localName)) {
        at = i;
        break;
      }
    }
    _children.insert(at, group);
    return group;
  }

  String _plainXf(String groupName) {
    final int colon = groupName.indexOf(':');
    final String prefix = colon < 0 ? '' : groupName.substring(0, colon + 1);
    return '<${prefix}xf numFmtId="0" fontId="0" fillId="0" borderId="0" '
        'xfId="0"/>';
  }

  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    w.start(_root.qualifiedName);
    _writeDeclarations(w, _root.namespaces);
    writeKeptAttributes(w, _root.attributes, declaredAbove: _root.namespaces);
    for (final Object c in _children) {
      switch (c) {
        case _Group():
          c.writeTo(w, _root.namespaces);
        case OpaqueXml():
          c.writeTo(w, declaredAbove: _root.namespaces);
      }
    }
    w.end();
    return buffer.takeChunks();
  }
}

void _writeDeclarations(XmlWriter w, Map<String, String> namespaces) {
  namespaces.forEach((String prefix, String uri) {
    w.attribute(prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix', uri);
  });
}

Map<String, String> _merge(Map<String, String> a, Map<String, String> b) =>
    b.isEmpty ? a : <String, String>{...a, ...b};

/// Reads the group the reader is on, calling [readItem] for each [name]
/// child (which returns the typed item and leaves the reader on its end) and
/// keeping every other child as [OpaqueXml].
_Group _readGroup(
  XmlPullReader r,
  XlsxReadLimits limits,
  String name,
  Object Function(XmlPullReader, XlsxReadLimits) readItem,
) {
  final String qualifiedName = r.qualifiedName;
  final Map<String, String> namespaces = Map<String, String>.of(
    r.declaredNamespaces,
  );
  final bool hasCount = r.getAttribute('count') != null;
  final List<KeptAttribute> attributes = keepAttributes(
    r,
    except: const <String>{'count'},
  );
  final List<Object> items = <Object>[];
  final _Group group = _Group(
    name,
    qualifiedName,
    namespaces,
    attributes,
    hasCount,
    items,
  );
  if (r.isEmptyElement) return group;
  final int groupDepth = r.depth;
  var count = 0;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < groupDepth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth == groupDepth + 1 &&
        r.localName == name &&
        r.namespaceUri == Ns.main) {
      if (count >= limits.maxCellFormats) {
        throw XlsxReadException(
          XlsxReadFailure.limitExceeded,
          'Limit maxCellFormats (${limits.maxCellFormats}) exceeded.',
        );
      }
      count++;
      items.add(readItem(r, limits));
    } else {
      items.add(OpaqueXml.capture(r));
    }
  }
  return group;
}

/// A typed `<numFmt>`, or the element as [OpaqueXml] when it has no usable
/// id or `formatCode`.
Object _readNumFmt(XmlPullReader r, XlsxReadLimits limits) {
  final int? id = readStyleId(r.getAttribute('numFmtId'));
  final String? raw = r.getAttribute('formatCode');
  if (id == null || raw == null) return OpaqueXml.capture(r);
  if (decodeXstring(raw).length > limits.maxTextLength) {
    throw XlsxReadException(
      XlsxReadFailure.limitExceeded,
      'Limit maxTextLength (${limits.maxTextLength}) exceeded by the '
      'format code of number format $id.',
    );
  }
  final _NumFmt n = _NumFmt(
    r.qualifiedName,
    Map<String, String>.of(r.declaredNamespaces),
    id,
    raw,
    keepAttributes(r, except: const <String>{'numFmtId', 'formatCode'}),
  );
  r.skip();
  return n;
}

/// A typed `<xf>`: its `numFmtId` and the element kept as written.
Object _readXf(XmlPullReader r, XlsxReadLimits limits) {
  final int? id = readStyleId(r.getAttribute('numFmtId'), orElse: 0);
  return _Xf.read(id, OpaqueXml.capture(r));
}

final RegExp _attribute = RegExp(
  r'''\s([^\s=/>"']+)\s*=\s*("[^"]*"|'[^']*')''',
);

/// The element [xml] with `numFmtId` set to [id] and `applyNumberFormat` to
/// `1` on its start tag, each replaced where present and added otherwise.
/// A prefixed attribute of the same local name is another attribute.
String _withNumFmt(String xml, int id) {
  var i = 1;
  int quote = 0;
  while (i < xml.length) {
    final int c = xml.codeUnitAt(i);
    if (quote != 0) {
      if (c == quote) quote = 0;
    } else if (c == 0x22 || c == 0x27) {
      quote = c;
    } else if (c == 0x3E) {
      break;
    }
    i++;
  }
  final int attributesEnd = xml.codeUnitAt(i - 1) == 0x2F ? i - 1 : i;
  final String head = xml.substring(0, attributesEnd);
  final StringBuffer out = StringBuffer();
  var at = 0;
  var sawId = false;
  var sawApply = false;
  for (final RegExpMatch m in _attribute.allMatches(head)) {
    final String? name = m.group(1);
    final String? replacement = switch (name) {
      'numFmtId' => ' numFmtId="$id"',
      'applyNumberFormat' => ' applyNumberFormat="1"',
      _ => null,
    };
    if (replacement == null) continue;
    if (name == 'numFmtId') sawId = true;
    if (name == 'applyNumberFormat') sawApply = true;
    out
      ..write(head.substring(at, m.start))
      ..write(replacement);
    at = m.end;
  }
  out.write(head.substring(at));
  if (!sawId) out.write(' numFmtId="$id"');
  if (!sawApply) out.write(' applyNumberFormat="1"');
  out.write(xml.substring(attributesEnd));
  return out.toString();
}
