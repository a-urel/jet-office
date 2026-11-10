/// The hyperlinks of an [XlsxSheet]: the members that read them, remove one,
/// and the plan `setCell` follows to set one.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetLinks] in, so these are members of the sheet.
///
/// A link is a `<hyperlink>` of the sheet's first `<hyperlinks>`, kept as an
/// [ItemGroup] of [LinkEntry]; an external address is the target of a
/// relationship of the sheet part, which the link names by `r:id`. A link a
/// cell is given is the element the sheet writer writes (`writeHyperlink`),
/// its text the cell's string and its font the writer's (`withHyperlinkFont`).
part of 'xlsx_sheet.dart';

/// What `setCell` does for a link, found before anything is recorded.
final class _LinkPlan {
  _LinkPlan(this.group, this.at, this.reuse, this.drop);

  /// The sheet's `<hyperlinks>` before the edit, or `null` when it has none.
  final ItemGroup<LinkEntry>? group;

  /// The index in [group] of the link on the cell, which the new one
  /// replaces, or `null` when the cell has none.
  final int? at;

  /// The id of the relationship the new link reuses, or `null` when it has
  /// none or needs a new one.
  final String? reuse;

  /// The id of the relationship the replaced link leaves unused, or `null`.
  final String? drop;
}

/// The hyperlink half of [XlsxSheet].
mixin _SheetLinks {
  // What the sheet gives its link half.
  SheetHost get _host;
  String get name;
  String? get _partName;
  Set<String> get _featureReported;
  WorksheetPart? _load();
  void _warn(XlsxWarningCode code, String? cell, {String? detail});
  XlsxReadCell? cellAt(int row, int column);

  /// The links of the sheet, with the cells they cover, in file order, as
  /// the sheet writer's `hyperlinks` writes them.
  ///
  /// A link's [XlsxHyperlink.address] is the target of the relationship its
  /// `r:id` names, as written; the text is the string of the first cell it
  /// covers, what Excel shows whatever `display` says, else its `display`,
  /// else empty. A `<hyperlink>` whose `ref` is not a range of cells is kept
  /// as written, left out here and reported once as `featureEntryInvalid`
  /// with the detail `hyperlink`; so is one whose `r:id` names no hyperlink
  /// relationship, which is listed with no address. Only the first
  /// `<hyperlinks>` is read. Unmodifiable. Loads the sheet. Throws an
  /// [XlsxReadException] when the sheet, or its relationships when a link
  /// names one, cannot be read.
  List<({XlsxRange range, XlsxHyperlink link})> get hyperlinks {
    final List<LinkEntry> entries =
        _load()?.hyperlinkGroup?.values ?? const <LinkEntry>[];
    final Map<String, String>? targets = _targetsFor(entries);
    return List<({XlsxRange range, XlsxHyperlink link})>.unmodifiable(
      <({XlsxRange range, XlsxHyperlink link})>[
        for (final LinkEntry e in entries)
          (range: e.range, link: _linkOf(e, targets)),
      ],
    );
  }

  /// The link that covers the cell at [row] and [column], or `null`; the
  /// first in file order when several do.
  ///
  /// Reads as [hyperlinks] does. Throws a [RangeError] outside Excel's grid
  /// and an [XlsxReadException] when the sheet cannot be read.
  XlsxHyperlink? hyperlinkAt(int row, int column) {
    XlsxSheet._checkCell(row, column);
    final ItemGroup<LinkEntry>? group = _load()?.hyperlinkGroup;
    if (group == null) return null;
    final int at = _linkIndex(group, row, column);
    if (at < 0) return null;
    final LinkEntry entry = group.items[at].value!;
    return _linkOf(entry, _targetsFor(<LinkEntry>[entry]));
  }

  /// Removes the link that covers the cell at [row] and [column], the whole
  /// of it when it covers several cells, and the relationship of its address
  /// when no other `<hyperlink>` of the sheet uses it. The cell keeps its
  /// value and style; the `<hyperlinks>` goes with its last link.
  ///
  /// Throws an [ArgumentError] when no link covers the cell, a [RangeError]
  /// outside Excel's grid and an [XlsxReadException] when the sheet, or its
  /// relationships when the link names one, cannot be read. Whatever it
  /// throws, nothing has changed.
  void removeHyperlink(int row, int column) => _recordSheetEdit(
    this,
    XlsxChangeKind.cellsSet,
    range: XlsxRange(row, column),
    () {
      XlsxSheet._checkCell(row, column);
      final WorksheetPart? part = _load();
      final ItemGroup<LinkEntry>? group = part?.hyperlinkGroup;
      final int at = group == null ? -1 : _linkIndex(group, row, column);
      if (part == null || group == null || at < 0) {
        throw ArgumentError.value(
          cellRef(row, column),
          'cell',
          'The cell has no hyperlink on the sheet "$name".',
        );
      }
      final String? id = group.items[at].value!.relationshipId;
      final String? drop = id == null ? null : _unusedId(group, at, id);
      final ChangeLog log = _host.log;
      final List<GroupItem<LinkEntry>> rest = <GroupItem<LinkEntry>>[
        ...group.items,
      ]..removeAt(at);
      log.transaction(() {
        editLayout(
          log,
          part,
          'hyperlinks',
          () => part.swapLayout(
            'hyperlinks',
            group,
            rest.isEmpty ? null : group.withItems(rest),
          ),
        );
        if (drop != null) {
          removeStoredRelationship(log, _host.reader.package, _partName!, drop);
        }
      });
    },
  );

  /// The checks and reads `setCell` makes of [link] for the cell at [row]
  /// and [column] of [part], before it records anything.
  ///
  /// Throws a [StateError] when a link covering several cells covers the
  /// cell, an [XlsxLimitError] for a link past the sheet's limit and an
  /// [XlsxReadException] when the sheet's relationships cannot be read.
  _LinkPlan _planLink(
    WorksheetPart part,
    int row,
    int column,
    XlsxHyperlink link,
  ) {
    final ItemGroup<LinkEntry>? group = part.hyperlinkGroup;
    int? at;
    if (group != null) {
      for (int i = 0; i < group.items.length; i++) {
        final LinkEntry? e = group.items[i].value;
        if (e == null || !_covers(e.range, row, column)) continue;
        if (e.range != XlsxRange(row, column)) {
          throw StateError(
            'The cell ${cellRef(row, column)} on sheet "$name" is covered by '
            'the hyperlink on ${e.range.ref}, which covers several cells; '
            'remove that link first.',
          );
        }
        at ??= i;
      }
      if (at == null &&
          group.items.where((GroupItem<LinkEntry> i) => i.counted).length >=
              XlsxLimits.maxHyperlinksPerSheet) {
        throw XlsxLimitError('hyperlinks', XlsxLimits.maxHyperlinksPerSheet);
      }
    }
    final String? oldId = at == null
        ? null
        : group!.items[at].value!.relationshipId;
    final String? address = link.address;
    String? reuse;
    if (address != null) {
      for (final OpcRelationship r in _readRelationships()) {
        if (r.type == RelType.hyperlink && r.external && r.target == address) {
          reuse = r.id;
          break;
        }
      }
    }
    final String? drop = oldId == null || oldId == reuse
        ? null
        : _unusedId(group!, at, oldId);
    return _LinkPlan(group, at, reuse, drop);
  }

  /// Gives the cell at [row] and [column] of [part] the link [link] as
  /// [plan] says: the relationship, the `<hyperlink>` and the old
  /// relationship's removal, each recorded in the workbook's change log.
  /// Must run inside its transaction.
  void _applyLink(
    WorksheetPart part,
    int row,
    int column,
    XlsxHyperlink link,
    _LinkPlan plan,
  ) {
    final ChangeLog log = _host.log;
    final String? address = link.address;
    final String? id = address == null
        ? null
        : plan.reuse ??
              addStoredRelationship(
                log,
                _host.reader.package,
                _partName!,
                type: RelType.hyperlink,
                target: address,
                external: true,
              );
    final String display = CellEncoder.truncateCellText(link.text);
    final GroupItem<LinkEntry> item = GroupItem<LinkEntry>(
      (
        range: XlsxRange(row, column),
        relationshipId: id,
        location: link.location,
        tooltip: link.tooltip,
        display: display,
      ),
      renderElements((XmlWriter w) {
        writeHyperlink(w, (
          ref: cellRef(row, column),
          relationshipId: id,
          location: link.location,
          tooltip: link.tooltip,
          display: display,
        ));
      }).single,
    );
    final ItemGroup<LinkEntry>? group = plan.group;
    final int? at = plan.at;
    final ItemGroup<LinkEntry> next = group == null
        ? ItemGroup<LinkEntry>(
            '${part.elementPrefix}hyperlinks',
            'hyperlinks',
            const <String, String>{},
            const <KeptAttribute>[],
            <GroupItem<LinkEntry>>[item],
            edited: true,
          )
        : group.withItems(<GroupItem<LinkEntry>>[
            for (int i = 0; i < group.items.length; i++)
              i == at ? item : group.items[i],
            if (at == null) item,
          ]);
    editLayout(
      log,
      part,
      'hyperlinks',
      () => part.swapLayout('hyperlinks', group, next),
    );
    final String? drop = plan.drop;
    if (drop != null) {
      removeStoredRelationship(log, _host.reader.package, _partName!, drop);
    }
  }

  /// The index in [group] of the first readable link covering the cell at
  /// [row] and [column], or -1.
  static int _linkIndex(ItemGroup<LinkEntry> group, int row, int column) {
    for (int i = 0; i < group.items.length; i++) {
      final LinkEntry? e = group.items[i].value;
      if (e != null && _covers(e.range, row, column)) return i;
    }
    return -1;
  }

  static bool _covers(XlsxRange range, int row, int column) =>
      row >= range.firstRow &&
      row <= range.lastRow &&
      column >= range.firstColumn &&
      column <= range.lastColumn;

  /// The sheet part's relationships, in file order. Throws an
  /// [XlsxReadException] when they cannot be read.
  List<OpcRelationship> _readRelationships() {
    final PackageReader reader = _host.reader;
    final String partName = _partName!;
    return reader.guardXml(
      partName.substring(1),
      () => reader.package.relationshipsOf(partName),
    );
  }

  /// The targets of the sheet's hyperlink relationships by id, the first of
  /// an id winning, which [entries] need: read only when one names a
  /// relationship, `null` otherwise.
  Map<String, String>? _targetsFor(List<LinkEntry> entries) {
    if (!entries.any((LinkEntry e) => e.relationshipId != null)) return null;
    final Map<String, String> targets = <String, String>{};
    for (final OpcRelationship r in _readRelationships()) {
      if (r.type == RelType.hyperlink) {
        targets.putIfAbsent(r.id, () => r.target);
      }
    }
    return targets;
  }

  /// [entry] as the public value: its address from [targets], its text the
  /// string of its first cell, else its display.
  XlsxHyperlink _linkOf(LinkEntry entry, Map<String, String>? targets) {
    final String? id = entry.relationshipId;
    String? address;
    if (id != null) {
      address = targets?[id];
      if (address == null && _featureReported.add('hyperlink')) {
        _warn(XlsxWarningCode.featureEntryInvalid, null, detail: 'hyperlink');
      }
    }
    final Object? shown = cellAt(
      entry.range.firstRow,
      entry.range.firstColumn,
    )?.value;
    return XlsxHyperlink(
      address: address,
      location: entry.location,
      text: shown is String ? shown : entry.display ?? '',
      tooltip: entry.tooltip,
    );
  }

  /// [id] when it is a hyperlink relationship of the sheet, one of its own,
  /// that no `<hyperlink>` of [group] but the one at [skip] uses; otherwise
  /// `null`. An entry that cannot be read counts, by its `r:id`.
  String? _unusedId(ItemGroup<LinkEntry> group, int? skip, String id) {
    int found = 0;
    for (final OpcRelationship r in _readRelationships()) {
      if (r.id == id && r.type == RelType.hyperlink) found++;
    }
    if (found != 1) return null;
    for (int i = 0; i < group.items.length; i++) {
      final GroupItem<LinkEntry> item = group.items[i];
      if (i == skip || !item.counted) continue;
      if (_linkId(item) == id) return null;
    }
    return id;
  }
}

/// The relationship id [item] names: its typed one, or, for an entry that
/// cannot be read, its `r:id` as written.
String? _linkId(GroupItem<LinkEntry> item) =>
    item.value?.relationshipId ??
    readerOf(item.source).getAttribute('id', namespaceUri: Ns.rel);

/// The `hyperlinks` holder of a sheet: on a row or column edit of the sheet
/// each link's `ref` shifts ([ReferenceShift.shiftRange]); a link the edit
/// deletes wholly goes, with the relationship of its address when no other
/// link of the sheet uses it, as `removeHyperlink` removes one. On every
/// edit an internal `location` goes through the rewriter, on the sheet.
/// Only the changed attributes are rewritten.
final class _LinkHolder implements ReferenceHolder {
  _LinkHolder(this._sheet, this._part);

  final XlsxSheet _sheet;
  final WorksheetPart _part;

  @override
  String get holderName => 'hyperlinks';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    final ItemGroup<LinkEntry>? group = _part.hyperlinkGroup;
    if (group == null) return;
    final String host = _sheet.name;
    final ReferenceShift? local = edit != null && _editsSheet(edit, host)
        ? edit
        : null;
    bool changed = false;
    final List<String> gone = <String>[];
    final List<GroupItem<LinkEntry>> items = <GroupItem<LinkEntry>>[];
    for (final GroupItem<LinkEntry> item in group.items) {
      if (!item.counted) {
        items.add(item);
        continue;
      }
      final XmlPullReader r = readerOf(item.source);
      final String? location = r.getAttribute('location', namespaceUri: '');
      final XlsxRange? range = item.value?.range;
      String? nextRef;
      if (local != null && range != null) {
        final XlsxRange? moved = local.shiftRange(range);
        if (moved == null) {
          changed = true;
          final String? id = _linkId(item);
          if (id != null) gone.add(id);
          continue;
        }
        if (moved != range) nextRef = moved.ref;
      }
      final String? nextLocation = location == null
          ? null
          : rewriteFormula(decodeXstring(location), mapper, host);
      if (nextRef == null && nextLocation == null) {
        items.add(item);
        continue;
      }
      changed = true;
      final OpaqueXml source = spliceElement(
        item.source,
        (XmlPullReader r, int level) => level == 0
            ? SpliceEdit(
                attributes: <String, String>{
                  'ref': ?nextRef,
                  if (nextLocation != null)
                    'location': escapeXstring(nextLocation),
                },
              )
            : null,
      );
      items.add(GroupItem<LinkEntry>(readLinkEntry(source).value, source));
    }
    if (!changed) return;
    final ChangeLog log = _sheet._host.log;
    final List<String> drop = <String>[
      for (final String id in gone.toSet())
        if (_unused(items, id)) id,
    ];
    editLayout(
      log,
      _part,
      'hyperlinks',
      () => _part.swapLayout(
        'hyperlinks',
        group,
        items.any((GroupItem<LinkEntry> i) => i.counted)
            ? group.withItems(items)
            : null,
      ),
    );
    for (final String id in drop) {
      removeStoredRelationship(
        log,
        _sheet._host.reader.package,
        _sheet._partName!,
        id,
      );
    }
  }

  /// Whether [id] is a hyperlink relationship of the sheet, listed once,
  /// that no entry of [items] names.
  bool _unused(List<GroupItem<LinkEntry>> items, String id) {
    int found = 0;
    for (final OpcRelationship r in _sheet._readRelationships()) {
      if (r.id == id && r.type == RelType.hyperlink) found++;
    }
    if (found != 1) return false;
    return !items.any(
      (GroupItem<LinkEntry> i) => i.counted && _linkId(i) == id,
    );
  }
}
