/// The parts of a workbook the model does not type but that hold references,
/// and what a structural edit does to them (decision 0018: fixed when a text
/// rewrite can fix them, otherwise warned about, never silently left).
///
/// This file is new in jet_office; Quds has no equivalent.
///
/// Fixed: x14 sparklines (`xm:f`, `xm:sqref` in the worksheet's `extLst`),
/// threaded comments (`ref`, the comment of a deleted cell going with its
/// note), form control properties (`fmlaLink`, `fmlaRange`, `fmlaGroup`,
/// `fmlaTxbx`), a pivot cache's `worksheetSource` (`ref` on an edit of its
/// sheet, `sheet` on a rename) and a pivot table's `location` (moved by an
/// edit wholly outside it; an edit through it throws a [StateError], as
/// Excel refuses it). Warned (`referenceNotShifted`, once per part per edit):
/// a slicer cache naming a table the edit removed or resized; a comments,
/// VML or drawing part of the edited sheet the model could not type; an
/// unreadable part of the edited sheet; and any other part under `xl/` with
/// a `ref`, `sqref` or `f` attribute, or an `f` or `sqref` element, that the
/// edit would change. External link parts name another workbook's sheets:
/// no edit here touches them.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../opc/change_log.dart';
import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../cell_ref.dart';
import '../formula/formula_rewrite.dart';
import '../formula/reference_shift.dart';
import '../formula/structured_reference.dart';
import '../range.dart';
import '../read/package_reader.dart';
import '../read/read_exception.dart';
import 'element_node.dart';
import 'item_group.dart' show readerOf;
import 'primitives.dart' show applyChange, editLayout, originalPartContent;
import 'reference_holders.dart';
import 'worksheet_part.dart';
import 'xlsx_sheet.dart';

const String _x15 =
    'http://schemas.microsoft.com/office/spreadsheetml/2010/11/main';
const String _threaded =
    'http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments';
const String _sparklineUri = '{05C60535-1F16-4FD2-B633-F4F36F0B64E0}';

/// The sheet a structural edit is on: the edited sheet, the renamed sheet's
/// old name, or `''` for a sheet moved.
String editedSheetOf(ReferenceMapper mapper) => switch (mapper) {
  final ReferenceShift s => s.sheet,
  final SheetRename r => r.from,
  final StructuredRename r => r.table.sheet,
  final TableToRange r => r.table.sheet,
  _ => '',
};

/// The edit of [mapper] as a warning's detail names it: `insert S!3:4`,
/// `delete S!B:C`, `rename S to T` or `move`.
String describeEdit(ReferenceMapper mapper) {
  switch (mapper) {
    case final ReferenceShift s:
      final int n = s.count.abs();
      final String verb = s.count > 0 ? 'insert' : 'delete';
      final String span = s.axis == ShiftAxis.rows
          ? '${s.index}:${s.index + n - 1}'
          : '${columnName(s.index - 1)}:${columnName(s.index + n - 2)}';
      return '$verb ${s.sheet}!$span';
    case final SheetRename r:
      return 'rename ${r.from} to ${r.to}';
    case final StructuredRename r:
      return r.newName != null
          ? 'rename table ${r.table.name} to ${r.newName}'
          : 'rename column ${r.oldColumn} of ${r.table.name} to ${r.newColumn}';
    case final TableToRange r:
      return 'remove table ${r.table.name}';
    default:
      return 'move';
  }
}

String _key(String name) {
  final String plain = name.startsWith('/') ? name.substring(1) : name;
  return plain.toLowerCase();
}

/// What the `charts` and `opaqueParts` holders share: the package, the
/// sheets, which sheet each part belongs to, and the writing of a part's new
/// text as a change.
final class OpaqueScan {
  /// A scan of [_reader]'s package for the sheets [_sheets], recording in
  /// [_log] and reporting a part that holds a reference an edit could not
  /// fix to [_warnPart] (a part name as stored, without a leading `/`).
  OpaqueScan(this._log, this._reader, this._sheets, this._warnPart);

  final ChangeLog _log;
  final PackageReader Function() _reader;
  final List<XlsxSheet> Function() _sheets;

  final void Function(String part) _warnPart;

  /// Reports the part [part] (a key) as holding a reference the edit could
  /// not fix, by its name as stored.
  void warn(String part) {
    final String name = reader.package.canonicalPartName(part) ?? part;
    _warnPart(name.startsWith('/') ? name.substring(1) : name);
  }

  /// The content this scan last gave each part it rewrote, by key.
  final Map<String, PartContent> _written = <String, PartContent>{};

  /// The package's reader.
  PackageReader get reader => _reader();

  /// What one edit has read: the parts, their roots and owners, shared by
  /// the holders of the edit.
  List<String>? _parts;
  Map<String, String>? _owners;
  final Map<String, ({String ns, String name})?> _roots =
      <String, ({String ns, String name})?>{};

  /// Starts an edit: forgets what the last one read.
  void begin() {
    _parts = null;
    _owners = null;
    _roots.clear();
  }

  /// The sheets with a part: their name and part name (a key).
  List<({String name, String part})> sheets() => <({String name, String part})>[
    for (final XlsxSheet s in _sheets())
      if (sheetPartNameOf(s) case final String part)
        (name: s.name, part: _key(part)),
  ];

  /// The comments, VML and drawing parts of the sheet [name] the model could
  /// not type, as far as the sheet's holders have read them (keys).
  Set<String> untypedOf(String name) => <String>{
    for (final XlsxSheet s in _sheets())
      if (s.name.toLowerCase() == name.toLowerCase()) ...untypedObjectParts(s),
  };

  /// The sheet each part belongs to, by key: the parts a worksheet relates
  /// to, and the parts those relate to (a drawing's charts, a table's query
  /// table). A part of two sheets belongs to the first. Relationships are
  /// peeked, never registered, so the package writes them as read.
  Map<String, String> owners() => _owners ??= _readOwners();

  Map<String, String> _readOwners() {
    final PackageReader reader = this.reader;
    final Map<String, String> owners = <String, String>{};
    for (final XlsxSheet sheet in _sheets()) {
      final String? part = sheetPartNameOf(sheet);
      if (part == null) continue;
      for (final String first in _targets(reader, _key(part))) {
        owners.putIfAbsent(first, () => sheet.name);
        for (final String second in _targets(reader, first)) {
          owners.putIfAbsent(second, () => sheet.name);
        }
      }
    }
    return owners;
  }

  /// The internal targets of [part]'s relationships, read without
  /// registering them for rewriting, so the package writes them as read.
  static List<String> _targets(PackageReader reader, String part) {
    final OpcPackage package = reader.package;
    try {
      return <String>[
        for (final OpcRelationship r in package.peekRelationships(part))
          if (!r.external) _key(package.resolve(part, r.target)),
      ];
    } on OpcFormatException {
      return const <String>[];
    } on XmlParseException {
      return const <String>[];
    }
  }

  /// The XML parts under `xl/` (not relationships), by key.
  /// Parts an earlier holder of the edit removed are left out.
  List<String> xmlParts() => <String>[
    for (final String part in _parts ??= _readParts())
      if (reader.hasPart(part)) part,
  ];

  List<String> _readParts() => <String>[
    for (final String name in reader.package.partNames)
      if (_key(name) case final String k
          when k.startsWith('xl/') &&
              (k.endsWith('.xml') || k.endsWith('.vml')) &&
              !k.contains('_rels/'))
        k,
  ];

  /// The namespace and local name of [part]'s root element, or `null` when
  /// the part is not readable XML.
  ({String ns, String name})? rootOf(String part) => _roots.containsKey(part)
      ? _roots[part]
      : (_roots[part] = _readRoot(part));

  ({String ns, String name})? _readRoot(String part) {
    if (!reader.hasPart(part)) return null;
    try {
      final XmlPullReader r = reader.openXml(part);
      return reader.guardXml(part, () {
        while (r.next()) {
          if (r.eventType == XmlEventType.startElement) {
            return (ns: r.namespaceUri, name: r.localName);
          }
        }
        return null;
      });
    } on XlsxReadException {
      return null;
    }
  }

  /// [part] with each start element edited as [edit] says, written as a
  /// change when anything changed. Returns `false` when the part is not
  /// readable XML (nothing changes then).
  bool splice(String part, SpliceEdit? Function(XmlPullReader r) edit) {
    final String? next;
    try {
      final XmlPullReader r = reader.openXml(part);
      next = reader.guardXml(part, () => spliceDocument(r, edit));
    } on XlsxReadException {
      return false;
    }
    if (next != null) _write(part, next);
    return true;
  }

  void _write(String part, String text) {
    final OpcPackage package = reader.package;
    final String name = package.canonicalPartName(part) ?? part;
    final String key = _key(name);
    PartContent? before = _written[key];
    // What this scan wrote last is stale once another edit (a chart
    // replaced, say) gave the part other content since.
    if (before != null && !identical(before, package.contentOf(name))) {
      before = null;
    }
    if (before == null && package.isLoaded(name)) {
      final XmlPullReader r = package.openXml(name);
      before = _TextContent(r.sourceText(0, r.sourceLength));
    }
    applyChange(
      _log,
      _PartTextChange(package, _written, name, key, before, _TextContent(text)),
    );
  }
}

/// A part's text, as UTF-8.
final class _TextContent implements PartContent {
  _TextContent(String text) : _bytes = Uint8List.fromList(utf8.encode(text));

  final Uint8List _bytes;

  @override
  List<Uint8List> encode() => <Uint8List>[_bytes];
}

/// The change of a part's text: undone, the part writes what it wrote
/// before, its file bytes when nothing had changed it.
final class _PartTextChange implements Change {
  _PartTextChange(
    this.package,
    this.written,
    this.name,
    this.key,
    this.before,
    this.after,
  );

  final OpcPackage package;
  final Map<String, PartContent> written;
  final String name;
  final String key;
  final PartContent? before;
  final PartContent after;

  @override
  void reapply() {
    package.setContent(name, after);
    written[key] = after;
  }

  @override
  void revert() {
    final PartContent? b = before;
    if (b == null) {
      package.setContent(name, originalPartContent(package, name));
      written.remove(key);
    } else {
      package.setContent(name, b);
      written[key] = b;
    }
  }
}

/// Whether [value], a `ref`, `sqref` ([list]) or formula of a part on
/// [host], is one [mapper] would change.
bool _wouldChange(
  String value,
  ReferenceMapper mapper,
  String host, {
  required bool list,
}) {
  if (list) {
    bool unlexable = false;
    final String? next = rewriteSqref(
      value,
      mapper,
      host,
      onUnlexable: (_) => unlexable = true,
    );
    // A sheet-qualified range is not an sqref item: read it as a formula.
    if (!unlexable) return next != null;
  }
  return rewriteFormula(value, mapper, host) != null;
}

/// The `opaqueParts` holder of a workbook: the parts this library's doc
/// comment lists, fixed or warned about.
final class OpaqueReferences implements PreparingReferenceHolder {
  /// The holder over [_scan].
  OpaqueReferences(this._scan);

  final OpaqueScan _scan;

  /// The tables before the edit, by part key: their `id`, rows and columns.
  Map<String, ({String? id, int rows, int columns})> _tablesBefore =
      const <String, ({String? id, int rows, int columns})>{};

  @override
  String get holderName => 'opaqueParts';

  @override
  void prepare(ReferenceMapper mapper, ReferenceShift? edit) {
    _tablesBefore = edit == null
        ? const <String, ({String? id, int rows, int columns})>{}
        : _tables();
    if (edit != null) _refusePivotEdits(edit);
  }

  /// Throws a [StateError] when [edit] would resize or delete a pivot table
  /// of its sheet, as Excel refuses it, before any holder changes anything.
  void _refusePivotEdits(ReferenceShift edit) {
    final String edited = edit.sheet.toLowerCase();
    final PackageReader reader = _scan.reader;
    _scan.owners().forEach((String part, String owner) {
      if (owner.toLowerCase() != edited || !reader.hasPart(part)) return;
      if (!part.endsWith('.xml')) return;
      final ({String ns, String name})? root = _scan.rootOf(part);
      if (root == null ||
          root.ns != Ns.main ||
          root.name != 'pivotTableDefinition') {
        return;
      }
      String? name;
      XlsxRange? range;
      try {
        final XmlPullReader r = reader.openXml(part);
        reader.guardXml(part, () {
          while (r.next()) {
            if (r.eventType != XmlEventType.startElement ||
                r.namespaceUri != Ns.main) {
              continue;
            }
            if (r.localName == 'pivotTableDefinition') {
              name = r.getAttribute('name');
            } else if (r.localName == 'location') {
              range = _range(r.getAttribute('ref', namespaceUri: ''));
              return;
            }
          }
        });
      } on XlsxReadException {
        return;
      }
      final XlsxRange? was = range;
      if (was == null) return;
      final XlsxRange? moved = edit.shiftRange(was);
      if (moved == null ||
          moved.lastRow - moved.firstRow != was.lastRow - was.firstRow ||
          moved.lastColumn - moved.firstColumn !=
              was.lastColumn - was.firstColumn) {
        throw StateError(
          'The edit would change part of the PivotTable "${name ?? ''}" on '
          'sheet "$owner" (${was.ref}).',
        );
      }
    });
  }

  Map<String, ({String? id, int rows, int columns})> _tables() {
    final Map<String, ({String? id, int rows, int columns})> tables =
        <String, ({String? id, int rows, int columns})>{};
    for (final String part in _scan.xmlParts()) {
      final PackageReader reader = _scan.reader;
      try {
        final XmlPullReader r = reader.openXml(part);
        reader.guardXml(part, () {
          if (!r.nextTag() || r.namespaceUri != Ns.main) return;
          if (r.localName != 'table') return;
          final XlsxRange? range = _range(r.getAttribute('ref'));
          if (range == null) return;
          tables[part] = (
            id: r.getAttribute('id'),
            rows: range.lastRow - range.firstRow,
            columns: range.lastColumn - range.firstColumn,
          );
        });
      } on XlsxReadException {
        continue;
      }
    }
    return tables;
  }

  static XlsxRange? _range(String? ref) {
    if (ref == null) return null;
    try {
      return XlsxRange.parse(ref);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    if (mapper is SheetMove) return;
    final String edited = editedSheetOf(mapper).toLowerCase();
    final Map<String, String> owners = _scan.owners();
    final Set<String> untyped = edit == null
        ? const <String>{}
        : _scan.untypedOf(edit.sheet);
    final Set<String> sheetParts = <String>{
      for (final s in _scan.sheets()) s.part,
    };
    final Set<String> reshaped = edit == null ? const <String>{} : _reshaped();
    for (final String part in _scan.xmlParts()) {
      if (sheetParts.contains(part)) continue;
      final String? owner = owners[part];
      final bool ownedByEdited = owner?.toLowerCase() == edited;
      if (untyped.contains(part)) {
        _scan.warn(part);
        continue;
      }
      final ({String ns, String name})? root = _scan.rootOf(part);
      if (root == null) {
        if (ownedByEdited && edit != null) _scan.warn(part);
        continue;
      }
      final String host = owner ?? '';
      final String ns = root.ns;
      final String name = root.name;
      if (ns == Ns.main && name == 'pivotCacheDefinition') {
        _pivotCache(part, mapper);
      } else if (ns == Ns.main && name == 'pivotTableDefinition') {
        if (ownedByEdited && edit != null) _pivotTable(part, edit);
      } else if (ns == _threaded && name == 'ThreadedComments') {
        if (ownedByEdited && edit != null) _threadedComments(part, edit);
      } else if (ns == Ns.x14 && name == 'formControlPr') {
        _formControl(part, mapper, host);
      } else if (ns == Ns.x14 && name == 'slicerCacheDefinition') {
        if (reshaped.isNotEmpty) _slicerCache(part, reshaped);
      } else if (!_skipped(ns, name)) {
        _scanUnknown(part, mapper, host);
      }
    }
  }

  /// Whether the root [ns] [name] is a part the model types, one that holds
  /// no reference a structural edit changes, or another holder's.
  static bool _skipped(String ns, String name) =>
      (ns == Ns.main && _typedRoots.contains(name)) ||
      ((ns == chartNamespace || ns == chartExNamespace) &&
          name == 'chartSpace') ||
      ns == Ns.xdr ||
      (ns.isEmpty && name == 'xml');

  static const Set<String> _typedRoots = <String>{
    'worksheet',
    'chartsheet',
    'dialogsheet',
    'workbook',
    'styleSheet',
    'sst',
    'table',
    'comments',
    'calcChain',
    'pivotCacheRecords',
    'externalLink',
    'metadata',
    'volTypes',
  };

  /// The ids of the tables the edit removed or resized.
  Set<String> _reshaped() {
    final Map<String, ({String? id, int rows, int columns})> now = _tables();
    return <String>{
      for (final MapEntry<String, ({String? id, int rows, int columns})> e
          in _tablesBefore.entries)
        if (e.value.id case final String id
            when now[e.key] == null ||
                now[e.key]!.rows != e.value.rows ||
                now[e.key]!.columns != e.value.columns)
          id,
    };
  }

  void _pivotCache(String part, ReferenceMapper mapper) {
    bool unfixed = false;
    final bool read = _scan.splice(part, (XmlPullReader r) {
      if (r.namespaceUri != Ns.main || r.localName != 'worksheetSource') {
        return null;
      }
      final String? sheet = r.getAttribute('sheet', namespaceUri: '');
      if (sheet == null || r.getAttribute('id', namespaceUri: Ns.rel) != null) {
        return null;
      }
      switch (mapper) {
        case final SheetRename rename:
          final String? to = rename.mapSheetName(sheet);
          return to == null
              ? null
              : SpliceEdit(attributes: <String, String>{'sheet': to});
        case final ReferenceShift shift:
          final String? ref = r.getAttribute('ref', namespaceUri: '');
          if (ref == null || sheet.toLowerCase() != shift.sheet.toLowerCase()) {
            return null;
          }
          final String? next = rewriteSqref(ref, mapper, sheet);
          if (next == null) return null;
          if (next.isEmpty) {
            unfixed = true;
            return null;
          }
          return SpliceEdit(attributes: <String, String>{'ref': next});
        default:
          return null;
      }
    });
    if (!read || unfixed) _scan.warn(part);
  }

  /// Moves a pivot table's `location`; [prepare] has refused an edit
  /// through it.
  void _pivotTable(String part, ReferenceShift edit) {
    bool unfixed = false;
    final bool read = _scan.splice(part, (XmlPullReader r) {
      if (r.namespaceUri != Ns.main || r.localName != 'location') return null;
      final XlsxRange? range = _range(r.getAttribute('ref', namespaceUri: ''));
      if (range == null) {
        unfixed = true;
        return null;
      }
      final XlsxRange? moved = edit.shiftRange(range);
      if (moved == null || moved == range) return null;
      return SpliceEdit(attributes: <String, String>{'ref': moved.ref});
    });
    if (!read || unfixed) _scan.warn(part);
  }

  void _threadedComments(String part, ReferenceShift edit) {
    bool unfixed = false;
    final bool read = _scan.splice(part, (XmlPullReader r) {
      if (r.namespaceUri != _threaded || r.localName != 'threadedComment') {
        return null;
      }
      final XlsxRange? cell = _range(r.getAttribute('ref', namespaceUri: ''));
      if (cell == null) {
        unfixed = true;
        return null;
      }
      final XlsxRange? moved = edit.shiftRange(cell);
      if (moved == null) return SpliceEdit.removal;
      if (moved == cell) return null;
      return SpliceEdit(attributes: <String, String>{'ref': moved.ref});
    });
    if (!read || unfixed) _scan.warn(part);
  }

  static const List<String> _linkAttributes = <String>[
    'fmlaLink',
    'fmlaRange',
    'fmlaGroup',
    'fmlaTxbx',
  ];

  void _formControl(String part, ReferenceMapper mapper, String host) {
    bool unfixed = false;
    final bool read = _scan.splice(part, (XmlPullReader r) {
      if (r.namespaceUri != Ns.x14 || r.localName != 'formControlPr') {
        return null;
      }
      final Map<String, String> next = <String, String>{};
      for (final String name in _linkAttributes) {
        final String? value = r.getAttribute(name, namespaceUri: '');
        if (value == null) continue;
        final String? rewritten = rewriteFormula(
          value,
          mapper,
          host,
          onUnlexable: (_) => unfixed = true,
        );
        if (rewritten != null) next[name] = rewritten;
      }
      return next.isEmpty ? null : SpliceEdit(attributes: next);
    });
    if (!read || unfixed) _scan.warn(part);
  }

  void _slicerCache(String part, Set<String> reshaped) {
    final PackageReader reader = _scan.reader;
    try {
      final XmlPullReader r = reader.openXml(part);
      final bool names = reader.guardXml(part, () {
        while (r.next()) {
          if (r.eventType == XmlEventType.startElement &&
              r.namespaceUri == _x15 &&
              r.localName == 'tableSlicerCache' &&
              reshaped.contains(r.getAttribute('tableId'))) {
            return true;
          }
        }
        return false;
      });
      if (names) _scan.warn(part);
    } on XlsxReadException {
      _scan.warn(part);
    }
  }

  void _scanUnknown(String part, ReferenceMapper mapper, String host) {
    final PackageReader reader = _scan.reader;
    bool changes = false;
    try {
      final XmlPullReader r = reader.openXml(part);
      reader.guardXml(part, () {
        while (!changes && r.next()) {
          if (r.eventType != XmlEventType.startElement) continue;
          for (int i = 0; i < r.attributeCount && !changes; i++) {
            final String name = r.attributeLocalName(i);
            if (name != 'ref' && name != 'sqref' && name != 'f') continue;
            changes = _wouldChange(
              r.attributeValue(i),
              mapper,
              host,
              list: name != 'f',
            );
          }
          final String local = r.localName;
          if (changes || (local != 'f' && local != 'sqref')) continue;
          if (r.isEmptyElement) continue;
          final StringBuffer text = StringBuffer();
          final int depth = r.depth;
          while (r.next()) {
            if (r.eventType == XmlEventType.endElement && r.depth < depth) {
              break;
            }
            if (r.eventType == XmlEventType.characters ||
                r.eventType == XmlEventType.cdata) {
              text.write(r.text);
            }
          }
          changes = _wouldChange(
            text.toString(),
            mapper,
            host,
            list: local == 'sqref',
          );
        }
      });
    } on XlsxReadException {
      return;
    }
    if (changes) _scan.warn(part);
  }
}

/// The DrawingML chart namespace.
const String chartNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/chart';

/// The chartex namespace (Excel 2016 charts).
const String chartExNamespace =
    'http://schemas.microsoft.com/office/drawing/2014/chartex';

/// The `sparklines` holder of a sheet: each `x14:sparkline`'s `xm:f`
/// (rewritten as a formula on the sheet) and `xm:sqref` (the cell it is
/// drawn in), in the `extLst`; a sparkline whose cell is deleted goes, and
/// a group left with none goes too. A formula that cannot be read is kept
/// and reported to [_unlexable].
final class SparklineHolder implements ReferenceHolder {
  /// The holder of [_part], the part of the sheet named by [_sheetName].
  SparklineHolder(this._log, this._part, this._sheetName, this._unlexable);

  final ChangeLog _log;
  final WorksheetPart _part;
  final String Function() _sheetName;
  final void Function(String text) _unlexable;

  @override
  String get holderName => 'sparklines';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    final XmlNode? extLst = _part.layoutElement('extLst') as XmlNode?;
    if (extLst == null) return;
    final String host = _sheetName();
    XmlNode next = extLst;
    for (final Object e in extLst.children) {
      if (e is! XmlNode ||
          e.localName != 'ext' ||
          e.attribute('uri')?.toUpperCase() != _sparklineUri) {
        continue;
      }
      final List<Object> children = <Object>[];
      bool changed = false;
      for (final Object g in e.children) {
        final Object shifted =
            g is OpaqueXml &&
                g.namespaceUri == Ns.x14 &&
                g.localName == 'sparklineGroups'
            ? _shiftedGroups(g, mapper, host)
            : g;
        if (!identical(shifted, g)) changed = true;
        children.add(shifted);
      }
      if (changed) next = next.replacingChild(e, e.withChildren(children));
    }
    if (identical(next, extLst)) return;
    editLayout(
      _log,
      _part,
      'extLst',
      () => _part.swapLayout('extLst', extLst, next),
    );
  }

  /// [groups] shifted; the same object when nothing changes.
  OpaqueXml _shiftedGroups(
    OpaqueXml groups,
    ReferenceMapper mapper,
    String host,
  ) {
    // First pass: which sparklines lose their cell, and which groups all.
    final List<bool> gone = <bool>[];
    final List<bool> groupGone = <bool>[];
    final List<int> groupSize = <int>[];
    final XmlPullReader r = readerOf(groups);
    int sparklines = 0;
    int left = 0;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement &&
          r.namespaceUri == Ns.x14 &&
          r.localName == 'sparklineGroup') {
        groupGone.add(sparklines > 0 && left == 0);
        groupSize.add(sparklines);
        sparklines = left = 0;
      }
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.namespaceUri == Ns.x14 && r.localName == 'sparklineGroup') {
        if (r.isEmptyElement) {
          groupGone.add(false);
          groupSize.add(0);
        }
      }
      if (r.namespaceUri != Ns.xm || r.localName != 'sqref') continue;
      final String sqref = r.isEmptyElement ? '' : _textOf(r);
      final String? next = rewriteSqref(sqref, mapper, host);
      final bool emptied = next != null && next.isEmpty;
      gone.add(emptied);
      sparklines++;
      if (!emptied) left++;
    }
    int sparkline = 0;
    int group = 0;
    return spliceElement(groups, (XmlPullReader r, int level) {
      if (r.namespaceUri == Ns.x14 && r.localName == 'sparklineGroup') {
        final bool drop = group < groupGone.length && groupGone[group];
        if (drop) {
          // Its sparklines are skipped with it.
          sparkline += groupSize[group];
        }
        group++;
        return drop ? SpliceEdit.removal : null;
      }
      if (r.namespaceUri == Ns.x14 && r.localName == 'sparkline') {
        final bool drop = sparkline < gone.length && gone[sparkline];
        sparkline++;
        return drop ? SpliceEdit.removal : null;
      }
      if (r.namespaceUri != Ns.xm) return null;
      if (r.localName == 'f') {
        return SpliceEdit(
          text: (String text) {
            final String? next = rewriteFormula(
              text,
              mapper,
              host,
              onUnlexable: _unlexable,
            );
            return next == null ? null : escapeXmlText(next);
          },
        );
      }
      if (r.localName == 'sqref') {
        return SpliceEdit(
          text: (String text) {
            final String? next = rewriteSqref(text, mapper, host);
            return next == null || next.isEmpty ? null : escapeXmlText(next);
          },
        );
      }
      return null;
    });
  }

  static String _textOf(XmlPullReader r) {
    final StringBuffer text = StringBuffer();
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType == XmlEventType.characters ||
          r.eventType == XmlEventType.cdata) {
        text.write(r.text);
      }
    }
    return text.toString();
  }
}
