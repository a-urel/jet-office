/// The styles part of a workbook, typed into the style value types.
///
/// Not ported from Quds; written for jet_office.
///
/// A loaded part is always written from this model (spec §4.3). What the model
/// types is the `<numFmts>` group (each `<numFmt>` as its id and code), the
/// `<fonts>`, `<fills>` and `<borders>` groups (each entry kept as written
/// and read into an [XlsxFont], [XlsxFill] or [XlsxBorder] on first use) and
/// the `<cellXfs>` group (each `<xf>` as its `numFmtId` plus the element
/// itself, read into an [XlsxStyle] on first use). Everything else, such as
/// cell styles, differential formats, the palette and extensions, is an
/// [OpaqueXml] child at its original position, and the root keeps its
/// namespace declarations and `mc:Ignorable`.
///
/// Every group is append-only (spec §4.4): while a sheet is unloaded its
/// cells point at style indexes, so an existing entry never moves.
/// [StylesPart.idFor] appends what a new style needs through a
/// [StyleRegistry] seeded from the part, and [StylesPart.withNumberFormat]
/// appends a copy of an `<xf>` with another number format. An entry read
/// from the file is written back from what was kept, so an unchanged part is
/// saved as it came; an appended one is written as the registry renders it.
///
/// Only the first of each typed group is typed, as in `readStyles`; a
/// repeated group is kept opaque, so style indexes mean the same in the
/// reader and in the model.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../alignment.dart';
import '../border.dart';
import '../fill.dart';
import '../font.dart';
import '../number_format.dart';
import '../read/package_reader.dart'
    show strictSpreadsheetNs, strictUnsupported;
import '../read/read_exception.dart';
import '../read/read_limits.dart';
import '../read/styles_reader.dart';
import '../style.dart';
import '../style_registry.dart';
import '../warnings.dart';
import 'palette.dart';
import 'style_elements.dart';

/// The children of `<styleSheet>` in the schema's sequence; a new group goes
/// before the first child that comes after it.
const List<String> _schemaOrder = <String>[
  'numFmts',
  'fonts',
  'fills',
  'borders',
  'cellStyleXfs',
  'cellXfs',
  'cellStyles',
  'dxfs',
  'tableStyles',
  'colors',
  'extLst',
];

/// Receives a problem found reading a style entry: the code and the
/// detail that names the entry, such as `font 3: …`.
typedef StyleWarn = void Function(XlsxWarningCode code, String detail);

/// The counts [StylesPart.mark] records and [StylesPart.rollBack] restores.
typedef StylesMark = ({int fonts, int fills, int borders, int codes, int xfs});

/// The typed groups of entries read into a value of their own.
enum _Kind {
  font('font', 'fonts'),
  fill('fill', 'fills'),
  border('border', 'borders');

  const _Kind(this.item, this.group);

  /// The local name of an entry, which also names it in a warning.
  final String item;

  /// The local name of the group.
  final String group;
}

/// A `<font>`, `<fill>` or `<border>`: as read ([_opaque]) or as appended
/// from the registry's rendering ([_text], already well-formed where it
/// goes).
final class _Entry {
  _Entry.read(OpaqueXml this._opaque) : _text = null;
  _Entry.made(String this._text) : _opaque = null;

  final OpaqueXml? _opaque;
  final String? _text;

  /// The entry read into its value, once it has been read.
  ReadStyleValue<Object>? value;

  void writeTo(XmlWriter w, Map<String, String> above) {
    final OpaqueXml? o = _opaque;
    if (o != null) {
      o.writeTo(w, declaredAbove: above);
    } else {
      w.raw(_text!);
    }
  }
}

/// An `<xf>` read into a style: `style` is what [StylesPart.styleOf] gives,
/// and `seed` is the entry the registry is seeded with.
typedef _XfInfo = ({
  XlsxStyle style,
  ({
    int numFmtId,
    int fontId,
    int fillId,
    int borderId,
    String? alignment,
    String? protection,
    bool exact,
  })
  seed,
});

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
    writeNamespaceDeclarations(w, namespaces);
    w.attribute('numFmtId', '$id');
    w.attribute('formatCode', scrubXmlText(rawCode).text);
    writeKeptAttributes(
      w,
      attributes,
      declaredAbove: mergeNamespaces(above, namespaces),
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

  /// The element read into a style, once it has been read.
  _XfInfo? info;

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

/// A typed group: `<numFmts>`, `<fonts>`, `<fills>`, `<borders>` or
/// `<cellXfs>`, with its items in order. An item is a [_NumFmt], an [_Entry],
/// an [_Xf] or an [OpaqueXml] the model does not type.
final class _Group {
  _Group(
    this.localName,
    this.itemName,
    this.qualifiedName,
    this.namespaces,
    this.attributes,
    this.hasCount,
    this.items, {
    this.created = false,
  });

  /// The group's local name, such as `fonts`.
  final String localName;

  /// The local name of the group's items, such as `font`.
  final String itemName;
  final String qualifiedName;
  final Map<String, String> namespaces;
  final List<KeptAttribute> attributes;

  /// Whether the group is written with a `count`.
  final bool hasCount;
  final List<Object> items;

  /// Whether the model added the group, so that rolling back every entry
  /// removes it again.
  final bool created;

  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final Map<String, String> inner = mergeNamespaces(above, namespaces);
    if (hasCount) {
      var n = 0;
      for (final Object item in items) {
        if (item is _NumFmt ||
            item is _Entry ||
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
        case _Entry():
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

/// The styles of a workbook: its number formats, fonts, fills, borders and
/// cell formats, typed, and the rest of the part kept as written.
final class StylesPart implements PartContent {
  StylesPart._(
    this._root,
    this._children,
    this._numFmts,
    this._groups,
    this._cellXfs,
    this._warn,
  ) : _untypedText = null {
    for (final _NumFmt n
        in _numFmts?.items.whereType<_NumFmt>() ?? const <_NumFmt>[]) {
      _numFmtList.add(n);
    }
    for (final _Kind k in _Kind.values) {
      _entries[k.index].addAll(
        _groups[k.index]?.items.whereType<_Entry>() ?? const <_Entry>[],
      );
      _fileCounts[k.index] = _entries[k.index].length;
    }
    _xfs.addAll(_cellXfs?.items.whereType<_Xf>() ?? const <_Xf>[]);
    _fileCounts[_codesAt] = _numFmtList.length;
    _fileCounts[_xfsAt] = _xfs.length;
  }

  /// Reads a styles part from [r], which must not have been advanced.
  ///
  /// A part with no root element, or whose root is not a SpreadsheetML
  /// `<styleSheet>`, is *untyped*, as `readStyles` treats it: [table] is
  /// `StyleTable.empty`, [encode] writes the part's text unchanged,
  /// [withNumberFormat] adds nothing and [idFor] throws.
  ///
  /// [warn] receives an [XlsxWarningCode.styleEntryInvalid] for each font,
  /// fill, border or cell format that cannot be read exactly, when it is
  /// first read (see [styleOf]).
  ///
  /// Throws an [XlsxReadException] of reason `unsupportedFormat` for a Strict
  /// root and `limitExceeded` when a group lists more than
  /// [XlsxReadLimits.maxCellFormats] `<numFmt>` or `<xf>` entries or a
  /// `formatCode` is longer than [XlsxReadLimits.maxTextLength] characters
  /// after decoding. An `XmlParseException` for XML that cannot be read
  /// passes through.
  ///
  /// A `<numFmt>` without a usable id or a `formatCode` is kept opaque and
  /// ignored, as in `readStyles`; the children of a `<numFmt>` (the schema
  /// has none) are not kept.
  factory StylesPart.read(
    XmlPullReader r,
    XlsxReadLimits limits, {
    StyleWarn? warn,
  }) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement) {
      return StylesPart._untyped(r.sourceText(0, r.sourceLength));
    }
    if (r.namespaceUri == strictSpreadsheetNs) throw strictUnsupported();
    if (r.localName != 'styleSheet' || r.namespaceUri != Ns.main) {
      return StylesPart._untyped(r.sourceText(0, r.sourceLength));
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<Object> children = <Object>[];
    _Group? numFmts;
    _Group? cellXfs;
    final List<_Group?> groups = List<_Group?>.filled(
      _Kind.values.length,
      null,
    );
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < 1) break;
      if (r.eventType != XmlEventType.startElement) continue;
      final _Kind? kind = r.namespaceUri == Ns.main
          ? _kindOf(r.localName)
          : null;
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
      } else if (kind != null && groups[kind.index] == null) {
        final _Group group = _readGroup(
          r,
          limits,
          kind.item,
          _readEntry,
          limited: false,
        );
        groups[kind.index] = group;
        children.add(group);
      } else {
        children.add(OpaqueXml.capture(r));
      }
    }
    return StylesPart._(root, children, numFmts, groups, cellXfs, warn);
  }

  StylesPart._untyped(this._untypedText)
    : _root = null,
      _children = <Object>[],
      _numFmts = null,
      _groups = List<_Group?>.filled(_Kind.values.length, null),
      _cellXfs = null,
      _warn = null;

  static _Kind? _kindOf(String localName) => switch (localName) {
    'fonts' => _Kind.font,
    'fills' => _Kind.fill,
    'borders' => _Kind.border,
    _ => null,
  };

  /// The positions of the number format and cell format counts in
  /// [_fileCounts], after those of the [_Kind]s.
  static const int _codesAt = 3;
  static const int _xfsAt = 4;

  /// The text of a part that is not a SpreadsheetML `<styleSheet>`, written
  /// back unchanged; `null` for a typed part.
  final String? _untypedText;
  final XmlRoot? _root;
  final List<Object> _children;
  _Group? _numFmts;

  /// The typed `<fonts>`, `<fills>` and `<borders>`, by [_Kind.index].
  final List<_Group?> _groups;
  _Group? _cellXfs;
  final StyleWarn? _warn;

  /// The typed `<numFmt>`s, `<font>`s, `<fill>`s, `<border>`s and `<xf>`s,
  /// in order, the appended ones included.
  final List<_NumFmt> _numFmtList = <_NumFmt>[];
  final List<List<_Entry>> _entries = <List<_Entry>>[
    for (final _Kind _ in _Kind.values) <_Entry>[],
  ];
  final List<_Xf> _xfs = <_Xf>[];

  /// How many fonts, fills, borders, number formats and cell formats the
  /// file had: [rollBack] never goes below them, and a cell format of the
  /// file is checked against the file's entries only.
  final List<int> _fileCounts = List<int>.filled(5, 0);

  StyleTable? _table;
  Map<int, String>? _codes;

  /// The registry [idFor] uses, seeded from the part on first use and
  /// dropped when the part changes other than through it.
  StyleRegistry? _registry;

  /// How far into the registry's lists the part holds entries; the
  /// registry's defaults for a group the file lacks come after.
  StylesMark? _written;

  /// Whether the part is a SpreadsheetML `<styleSheet>`; an untyped part
  /// cannot take a new `<xf>` ([withNumberFormat] adds nothing to it).
  bool get isTyped => _untypedText == null;

  /// The cell formats by style index, as `readStyles` gives them for the
  /// same part ([StyleTable.empty] for an untyped one). It reflects every
  /// `<xf>` [withNumberFormat] and [idFor] appended.
  StyleTable get table =>
      _table ??= _untypedText != null ? StyleTable.empty : _buildTable();

  /// The custom number format codes by id; a later `<numFmt>` of an id wins,
  /// as in `readStyles`.
  Map<int, String> get _codeMap => _codes ??= <int, String>{
    for (final _NumFmt n in _numFmtList) n.id: decodeXstring(n.rawCode),
  };

  StyleTable _buildTable() {
    final Map<int, String> codes = _codeMap;
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

  // -- Reading entries -------------------------------------------------------

  Map<String, String> _above(_Group group) =>
      mergeNamespaces(_root!.namespaces, group.namespaces);

  /// A reader on the item [write] writes, as it stands in [group]: the item
  /// inside an element that declares what is in scope there.
  XmlPullReader _openItem(
    _Group group,
    void Function(XmlWriter w, Map<String, String> above) write,
  ) {
    final Map<String, String> above = _above(group);
    final StringBuffer out = StringBuffer();
    final XmlWriter w = XmlWriter(out)..start('_');
    writeNamespaceDeclarations(w, above);
    write(w, above);
    w.end();
    final XmlPullReader r = XmlPullReader(out.toString())..next();
    while (r.next() && r.eventType != XmlEventType.startElement) {}
    return r;
  }

  /// The entry [index] of [kind] read into its value, reading it on first
  /// use (and warning about a problem then).
  ReadStyleValue<Object> _valueOf(_Kind kind, int index) {
    final _Entry entry = _entries[kind.index][index];
    final ReadStyleValue<Object>? known = entry.value;
    if (known != null) return known;
    final XmlPullReader r = _openItem(_groups[kind.index]!, entry.writeTo);
    final ReadStyleValue<Object> value = switch (kind) {
      _Kind.font => readFont(r),
      _Kind.fill => readFill(r),
      _Kind.border => readBorder(r),
    };
    final String? problem = value.problem;
    if (problem != null) {
      _warn?.call(
        XlsxWarningCode.styleEntryInvalid,
        '${kind.item} $index: $problem',
      );
    }
    return entry.value = value;
  }

  /// The `<xf>` at [index] read into a style, reading it on first use (and
  /// warning about a problem then).
  _XfInfo _xfInfo(int index) {
    final _Xf xf = _xfs[index];
    final _XfInfo? known = xf.info;
    if (known != null) return known;
    final XmlPullReader r = _openItem(_cellXfs!, xf.writeTo);
    String? problem;
    for (final String name in const <String>[
      'numFmtId',
      'fontId',
      'fillId',
      'borderId',
      'xfId',
    ]) {
      final String? raw = r.getAttribute(name, namespaceUri: '');
      if (raw != null && readStyleId(raw) == null) {
        problem ??= '$name "$raw" is not a style index.';
      }
    }
    final read = readXf(r);
    problem ??= read.alignment.problem ?? read.protection.problem;
    var exact = read.exact;
    final bool fromFile = index < _fileCounts[_xfsAt];
    Object? part(_Kind kind, int id) {
      final int count = fromFile
          ? _fileCounts[kind.index]
          : _entries[kind.index].length;
      if (id < count) return _valueOf(kind, id).value;
      exact = false;
      problem ??= '${kind.item}Id $id points to no ${kind.item}.';
      return null;
    }

    final Object? font = part(_Kind.font, read.fontId);
    final Object? fill = part(_Kind.fill, read.fillId);
    final Object? border = part(_Kind.border, read.borderId);
    final XlsxNumFmt? numFmt = _numFmtOf(read.numFmtId);
    if (numFmt == null) exact = false;
    final String? found = problem;
    if (found != null) {
      _warn?.call(
        XlsxWarningCode.styleEntryInvalid,
        'cell format $index: $found',
      );
    }
    final _XfInfo info = (
      style: XlsxStyle(
        numFmt: numFmt,
        font: font as XlsxFont?,
        fill: fill as XlsxFill?,
        border: border as XlsxBorder?,
        alignment: read.alignment.value,
        protection: read.protection.value,
      ),
      seed: (
        numFmtId: read.numFmtId,
        fontId: read.fontId,
        fillId: read.fillId,
        borderId: read.borderId,
        alignment: alignmentXml(read.alignment.value),
        protection: protectionXml(read.protection.value),
        exact: exact,
      ),
    );
    return xf.info = info;
  }

  /// The number format of [id]: the file's code when it has one the writer
  /// can write, else the built-in format for an id up to 163, else `null`.
  XlsxNumFmt? _numFmtOf(int id) {
    final String? code = _codeMap[id];
    if (code != null && code.isNotEmpty && scrubXmlText(code).removed == 0) {
      return XlsxNumFmt.custom(code);
    }
    return id <= 163 ? XlsxNumFmt.builtin(id) : null;
  }

  /// The cell format at [index] as a style.
  ///
  /// Each part is the value the `<xf>` points at, read from the file: the
  /// number format (built-in, or custom with the file's code), the font, the
  /// fill and the border, and the alignment and protection, `null` when the
  /// `<xf>` has none. A part the `<xf>` points at but the file lacks, or a
  /// custom number format id without a code, is `null`. An [index] outside
  /// `<cellXfs>` gives index 0's style; a part without any `<xf>`, or an
  /// untyped part, gives the default style, `XlsxStyle()`.
  ///
  /// Reading a font, fill, border or cell format for the first time reports
  /// any value in it that cannot be read (see [StylesPart.read]); such a
  /// value takes its default, or `null`.
  XlsxStyle styleOf(int index) {
    if (!isTyped || _xfs.isEmpty) return const XlsxStyle();
    return _xfInfo(index >= 0 && index < _xfs.length ? index : 0).style;
  }

  /// Whether [styleOf] gives everything the cell format at [index] holds:
  /// the `<xf>`, its font, its fill and its border are read exactly, with
  /// nothing the value types cannot hold (such as a named cell style's
  /// `xfId` or a `quotePrefix`). An inexact entry is still written back as
  /// it was read. False for an index outside `<cellXfs>` and on an untyped
  /// part.
  bool isExact(int index) {
    if (!isTyped || index < 0 || index >= _xfs.length) return false;
    final _XfInfo info = _xfInfo(index);
    if (!info.seed.exact) return false;
    return _valueOf(_Kind.font, info.seed.fontId).exact &&
        _valueOf(_Kind.fill, info.seed.fillId).exact &&
        _valueOf(_Kind.border, info.seed.borderId).exact;
  }

  /// The colours of `<colors><indexedColors>`: 64 ARGB values, the file's
  /// `rgbColor`s in order and [defaultIndexedColors] for each one the file
  /// lacks or that is not 8 hex digits. `null` when the part has no
  /// `<indexedColors>` (the default palette applies) and on an untyped part.
  /// Unmodifiable.
  List<int>? get indexedColors => isTyped ? _palette : null;

  late final List<int>? _palette = _readPalette();

  List<int>? _readPalette() {
    for (final Object c in _children) {
      if (c is! OpaqueXml ||
          c.namespaceUri != Ns.main ||
          c.localName != 'colors') {
        continue;
      }
      final StringBuffer out = StringBuffer();
      final XmlWriter w = XmlWriter(out)..start('_');
      writeNamespaceDeclarations(w, _root!.namespaces);
      c.writeTo(w, declaredAbove: _root.namespaces);
      w.end();
      final XmlPullReader r = XmlPullReader(out.toString())..next();
      while (r.next() && r.eventType != XmlEventType.startElement) {}
      final int top = r.depth;
      int? at;
      List<int?>? read;
      while (r.next()) {
        if (r.eventType == XmlEventType.endElement) {
          if (r.depth < top || (at != null && r.depth < at)) break;
          continue;
        }
        if (r.eventType != XmlEventType.startElement ||
            r.namespaceUri != Ns.main) {
          continue;
        }
        if (at == null) {
          if (r.depth == top + 1 && r.localName == 'indexedColors') {
            at = r.depth;
            read = <int?>[];
          }
        } else if (r.depth == at + 1 && r.localName == 'rgbColor') {
          final String? rgb = r.getAttribute('rgb', namespaceUri: '');
          read!.add(
            rgb != null && _hex8.hasMatch(rgb)
                ? int.parse(rgb, radix: 16)
                : null,
          );
        }
      }
      if (read == null) return null;
      return List<int>.unmodifiable(<int>[
        for (var i = 0; i < defaultIndexedColors.length; i++)
          (i < read.length ? read[i] : null) ?? defaultIndexedColors[i],
      ]);
    }
    return null;
  }

  // -- Adding styles ---------------------------------------------------------

  /// The cell format index of [style], appending what it needs.
  ///
  /// A style that looks like a cell format of the part read exactly, or
  /// like one appended before, gets its index; `null` gives 0. Otherwise
  /// the new fonts, fills, borders, number format codes and cell format are
  /// appended to their groups, as the writer's [StyleRegistry] makes them,
  /// so no existing index moves. A group the file lacks is created in the
  /// schema's order, holding the writer's default entries before the new
  /// one (a font, the `none` and `gray125` fills, an empty border, a plain
  /// cell format), so the new indexes mean what the registry gave them.
  ///
  /// Throws as [StyleRegistry.idFor] does ([ArgumentError] naming the
  /// field, `XlsxLimitError`), also when the file's own entries are past
  /// the writer's limits; a throw changes nothing. Throws [StateError] on
  /// an untyped part (see [isTyped]).
  int idFor(XlsxStyle? style) {
    if (!isTyped) {
      throw StateError('The styles part is not a SpreadsheetML styleSheet.');
    }
    final StyleRegistry registry = _registry ??= _seeded();
    final int before = registry.xfCount;
    final int id = registry.idFor(style);
    if (registry.xfCount != before) _appendFrom(registry);
    return id;
  }

  /// A registry seeded with the part's entries, and [_written] set to them.
  StyleRegistry _seeded() {
    List<({String? key})> keys(
      _Kind kind,
      String? Function(Object value) keyOf,
      List<String> defaults,
    ) {
      final int count = _entries[kind.index].length;
      return <({String? key})>[
        for (var i = 0; i < count; i++)
          (
            key: switch (_valueOf(kind, i)) {
              (value: final Object v, exact: true, problem: _) => keyOf(v),
              _ => null,
            },
          ),
        for (var i = count; i < defaults.length; i++) (key: defaults[i]),
      ];
    }

    final StyleRegistry registry = StyleRegistry.seeded(
      StyleSeed(
        fonts: keys(_Kind.font, (Object v) {
          final XlsxFont font = v as XlsxFont;
          // The registry resolves a font first; one without a name or a size
          // is not what it would write.
          return font.name != null && font.size != null
              ? StyleRegistry.fontKey(font)
              : null;
        }, <String>[StyleRegistry.fontKey(null)]),
        fills: keys(
          _Kind.fill,
          (Object v) => StyleRegistry.fillKey(v as XlsxFill),
          <String>[
            StyleRegistry.fillKey(const XlsxFill.pattern(XlsxPatternType.none)),
            StyleRegistry.fillKey(
              const XlsxFill.pattern(XlsxPatternType.gray125),
            ),
          ],
        ),
        borders: keys(
          _Kind.border,
          (Object v) => StyleRegistry.borderKey(v as XlsxBorder),
          <String>[StyleRegistry.borderKey(const XlsxBorder())],
        ),
        customCodes: Map<int, String>.of(_codeMap),
        xfs:
            <
              ({
                int numFmtId,
                int fontId,
                int fillId,
                int borderId,
                String? alignment,
                String? protection,
                bool exact,
              })
            >[
              for (var i = 0; i < _xfs.length; i++) _xfInfo(i).seed,
              if (_xfs.isEmpty)
                (
                  numFmtId: 0,
                  fontId: 0,
                  fillId: 0,
                  borderId: 0,
                  alignment: null,
                  protection: null,
                  exact: true,
                ),
            ],
      ),
    );
    _written = (
      fonts: _entries[_Kind.font.index].length,
      fills: _entries[_Kind.fill.index].length,
      borders: _entries[_Kind.border.index].length,
      codes: _codeMap.length,
      xfs: _xfs.length,
    );
    return registry;
  }

  /// Appends to the part what [registry] holds past [_written].
  void _appendFrom(StyleRegistry registry) {
    final StylesMark written = _written!;
    final List<({int id, String code})> codes = registry.customCodesFrom(
      written.codes,
    );
    if (codes.isNotEmpty) {
      final _Group group = _numFmts ??= _createGroup('numFmts', 'numFmt');
      final Map<String, String> ns = _above(group)[''] == Ns.main
          ? const <String, String>{}
          : const <String, String>{'': Ns.main};
      for (final ({int id, String code}) c in codes) {
        final _NumFmt n = _NumFmt('numFmt', ns, c.id, c.code, const []);
        group.items.add(n);
        _numFmtList.add(n);
      }
      _codes = null;
    }
    for (final _Kind kind in _Kind.values) {
      final List<String> made = switch (kind) {
        _Kind.font => registry.fontsFrom(written.fonts),
        _Kind.fill => registry.fillsFrom(written.fills),
        _Kind.border => registry.bordersFrom(written.borders),
      };
      if (made.isEmpty) continue;
      final _Group group = _groups[kind.index] ??= _createGroup(
        kind.group,
        kind.item,
      );
      for (final String xml in made) {
        final _Entry entry = _Entry.made(_inMain(xml, group));
        group.items.add(entry);
        _entries[kind.index].add(entry);
      }
    }
    final List<String> xfs = registry.xfsFrom(written.xfs);
    if (xfs.isNotEmpty) {
      final _Group group = _cellXfs ??= _createGroup('cellXfs', 'xf');
      for (final String xml in xfs) {
        final int id = int.parse(_numFmtIdOf.firstMatch(xml)!.group(1)!);
        final _Xf xf = _Xf.made(id, _inMain(xml, group));
        group.items.add(xf);
        _xfs.add(xf);
      }
    }
    _written = (
      fonts: registry.fontCount,
      fills: registry.fillCount,
      borders: registry.borderCount,
      codes: written.codes + codes.length,
      xfs: registry.xfCount,
    );
    _table = null;
  }

  static final RegExp _numFmtIdOf = RegExp('numFmtId="([0-9]+)"');

  /// [xml], an element the registry rendered without a prefix, as it goes
  /// in [group]: with the SpreadsheetML namespace declared on it when the
  /// default namespace there is another.
  String _inMain(String xml, _Group group) {
    if (_above(group)[''] == Ns.main) return xml;
    var end = 1;
    while (end < xml.length && !' />'.contains(xml[end])) {
      end++;
    }
    return '${xml.substring(0, end)} xmlns="${escapeXmlAttribute(Ns.main)}"'
        '${xml.substring(end)}';
  }

  /// The counts of the part's typed entries, for [rollBack]: fonts, fills,
  /// borders, `<numFmt>`s and cell formats (all zero on an untyped part).
  StylesMark mark() => (
    fonts: _entries[_Kind.font.index].length,
    fills: _entries[_Kind.fill.index].length,
    borders: _entries[_Kind.border.index].length,
    codes: _numFmtList.length,
    xfs: _xfs.length,
  );

  /// Removes every entry appended since [mark] was taken, by [idFor] or
  /// [withNumberFormat], and a group made for them, so the part encodes as
  /// it did then.
  ///
  /// Throws [ArgumentError] for a mark that is not an earlier [StylesPart.mark]
  /// of this part: a count above the current one or below the file's.
  void rollBack(StylesMark mark) {
    final List<int> target = <int>[
      mark.fonts,
      mark.fills,
      mark.borders,
      mark.codes,
      mark.xfs,
    ];
    final List<int> current = <int>[
      for (final List<_Entry> e in _entries) e.length,
      _numFmtList.length,
      _xfs.length,
    ];
    for (var i = 0; i < target.length; i++) {
      if (target[i] < _fileCounts[i] || target[i] > current[i]) {
        throw ArgumentError.value(mark, 'mark', 'Not a mark of this part.');
      }
    }
    var changed = false;
    for (final _Kind kind in _Kind.values) {
      final int drop = current[kind.index] - target[kind.index];
      if (drop == 0) continue;
      changed = true;
      _entries[kind.index].removeRange(target[kind.index], current[kind.index]);
      if (_shrink(_groups[kind.index]!, drop)) _groups[kind.index] = null;
    }
    final int codes = current[_codesAt] - mark.codes;
    if (codes > 0) {
      changed = true;
      _numFmtList.removeRange(mark.codes, current[_codesAt]);
      if (_shrink(_numFmts!, codes)) _numFmts = null;
      _codes = null;
    }
    final int xfs = current[_xfsAt] - mark.xfs;
    if (xfs > 0) {
      changed = true;
      _xfs.removeRange(mark.xfs, current[_xfsAt]);
      if (_shrink(_cellXfs!, xfs)) _cellXfs = null;
    }
    if (changed) _dropRegistry();
  }

  /// Removes the last [count] items of [group], which were appended, and
  /// the group itself when the model created it and it is now empty;
  /// returns whether it did.
  bool _shrink(_Group group, int count) {
    group.items.removeRange(group.items.length - count, group.items.length);
    if (!group.created || group.items.isNotEmpty) return false;
    _children.remove(group);
    return true;
  }

  /// Forgets the registry after the part changed other than through it; the
  /// next [idFor] seeds a new one from the part.
  void _dropRegistry() {
    _registry = null;
    _written = null;
    _table = null;
  }

  /// The index of an `<xf>` equal to that of [style] with its `numFmtId`
  /// replaced by [numFmtId] (and `applyNumberFormat="1"`).
  ///
  /// A [style] that is `null` or not an index of `<cellXfs>` stands for the
  /// first `<xf>`, as a broken style counts as General. An `<xf>` that
  /// already is the result is reused; otherwise one is appended, so no
  /// existing index moves; an untyped part returns `style ?? 0` unchanged
  /// (see [isTyped]). A part without any `<xf>` (or without `<cellXfs>`)
  /// gets a plain one first to copy from. Throws a
  /// [RangeError] for a negative [numFmtId].
  ///
  /// The `<xf>` is a copy of the element's text, so it keeps what the value
  /// types cannot hold. An appended one takes the next cell format index,
  /// and [idFor] numbers after it.
  int withNumberFormat(int? style, int numFmtId) {
    RangeError.checkNotNegative(numFmtId, 'numFmtId');
    if (_untypedText != null) return style ?? 0;
    final _Group group = _cellXfs ??= _createGroup('cellXfs', 'xf');
    final Map<String, String> above = _above(group);
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
    // The registry does not know this xf: the next idFor seeds a new one.
    _dropRegistry();
    return _xfs.length - 1;
  }

  /// A new, empty group [localName] of [itemName]s, put among the root's
  /// children in the schema's order.
  _Group _createGroup(String localName, String itemName) {
    final String qn = _root!.qualifiedName;
    final int colon = qn.indexOf(':');
    final String prefix = colon < 0 ? '' : qn.substring(0, colon + 1);
    final _Group group = _Group(
      localName,
      itemName,
      '$prefix$localName',
      const <String, String>{},
      const <KeptAttribute>[],
      true,
      <Object>[],
      created: true,
    );
    final int rank = _schemaOrder.indexOf(localName);
    var at = _children.length;
    for (var i = 0; i < _children.length; i++) {
      final Object c = _children[i];
      final String? name = switch (c) {
        _Group() => c.localName,
        OpaqueXml() when c.namespaceUri == Ns.main => c.localName,
        _ => null,
      };
      if (name != null && _schemaOrder.indexOf(name) > rank) {
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
    final String? untyped = _untypedText;
    if (untyped != null) return (buffer..write(untyped)).takeChunks();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final XmlRoot root = _root!;
    w.start(root.qualifiedName);
    writeNamespaceDeclarations(w, root.namespaces);
    writeKeptAttributes(w, root.attributes, declaredAbove: root.namespaces);
    for (final Object c in _children) {
      switch (c) {
        case _Group():
          c.writeTo(w, root.namespaces);
        case OpaqueXml():
          c.writeTo(w, declaredAbove: root.namespaces);
      }
    }
    w.end();
    return buffer.takeChunks();
  }
}

final RegExp _hex8 = RegExp(r'^[0-9A-Fa-f]{8}$');

/// Reads the group the reader is on, calling [readItem] for each [name]
/// child (which returns the typed item and leaves the reader on its end) and
/// keeping every other child as [OpaqueXml].
_Group _readGroup(
  XmlPullReader r,
  XlsxReadLimits limits,
  String name,
  Object Function(XmlPullReader, XlsxReadLimits) readItem, {
  bool limited = true,
}) {
  final String localName = r.localName;
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
    localName,
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
      if (limited && count >= limits.maxCellFormats) {
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

/// A `<font>`, `<fill>` or `<border>`, kept as written; it is read into its
/// value on first use.
Object _readEntry(XmlPullReader r, XlsxReadLimits limits) =>
    _Entry.read(OpaqueXml.capture(r));

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
