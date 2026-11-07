/// The tables of an [XlsxSheet]: the members that read, add, restyle, resize
/// and remove them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetTablesApi] in, so these are members of the sheet.
///
/// A table is a part of its own, related from the sheet and listed in its
/// `<tableParts>`. Reading adds nothing to the package's content: a part is
/// saved from the original bytes until an edit gives it to the package, and
/// a typed part keeps what it does not type as written. The sheet's cached
/// list is edited by the changes, so `merge`, `autoFilter` and `setCell` see
/// a table at once and an undo takes it away again.
///
/// Renaming a table and turning a totals row on or off are W5's: they need
/// the formula lexer and cell moves. So are resizing a table with a totals
/// row or a sort state and removing a table that formulas use.
part of 'xlsx_sheet.dart';

/// The change of the sheet's list of tables: [entry] went in at [index], or
/// left it when [added] is false.
final class _TableListChange implements Change {
  _TableListChange(this.list, this.index, this.entry, {required this.added});

  /// The sheet's cached list.
  final List<({String partName, TablePart table})> list;

  /// Where the entry is in [list] while it is there.
  final int index;

  /// The table.
  final ({String partName, TablePart table}) entry;

  /// Whether the change adds [entry] rather than removes it.
  final bool added;

  @override
  void revert() => _apply(!added);

  @override
  void reapply() => _apply(added);

  void _apply(bool insert) {
    if (insert) {
      list.insert(index, entry);
    } else {
      list.removeAt(index);
    }
  }
}

/// The content type of a slicer cache part, which names its table by id.
const String _slicerCacheType = 'application/vnd.ms-excel.slicerCache+xml';

/// The table half of [XlsxSheet].
mixin _SheetTablesApi {
  // What the sheet gives its table half.
  SheetHost get _host;
  String get name;
  String? get _partName;
  Set<String> get _attachedTables;
  List<XlsxRange> get merges;
  XlsxRange? get autoFilter;
  WorksheetPart _editablePart(String what);
  List<({String partName, TablePart table})> _sheetTables();
  XlsxReadCell? cellAt(int row, int column);
  void setCell(int row, int column, Object? value);

  /// The tables of the sheet, each as [XlsxTable] types it: in the order of
  /// the sheet's table relationships when the file is opened, then a table
  /// added goes last. After a save and a reopen the order follows the
  /// relationships again, which may differ from this list's after a table
  /// was removed and another added.
  ///
  /// A table part the model cannot type (a root that is not a SpreadsheetML
  /// `table`, a `ref` that is not a range, or columns that do not match it)
  /// is left out, kept as written, and its name stays taken. A
  /// `totalsRowFunction` no schema value names reads
  /// [XlsxTotalsFunction.none] and is reported once as `featureEntryInvalid`
  /// with the detail `table`. The part's calculated columns, `dataDxfId`,
  /// `xr:uid`, filter criteria and sort state are not in [XlsxTable]; they
  /// stay in the file as read. A sheet without a part has none. Unmodifiable;
  /// a table part is read on first use.
  List<XlsxTable> get tables => _partName == null
      ? const <XlsxTable>[]
      : List<XlsxTable>.unmodifiable(<XlsxTable>[
          for (final ({String partName, TablePart table}) t in _sheetTables())
            t.table.value,
        ]);

  /// Adds [table] to the sheet as the writer's `table` does.
  ///
  /// The part is `xl/tables/table{id}.xml`, rendered by the writer, with the
  /// `id` one above the highest table `id` of the package; a part that has the
  /// name makes it take the next number. The sheet relates it and lists it in
  /// `<tableParts>`, made in schema position when the sheet has none, `count`
  /// recomputed. An empty header cell takes the column's name and an empty
  /// totals cell the column's label, `SUBTOTAL` or formula; a totals cell
  /// with a value keeps it. Those cells are set as [setCell] sets them, so
  /// the save drops `calcChain` and asks Excel to recalculate when one was
  /// written.
  ///
  /// Throws an [ArgumentError] as the writer does, named by its field, for a
  /// table `checkTable` refuses; named `name` for a name a table has on any
  /// sheet (loaded or not, listed or not) or a defined name has in any scope,
  /// ignoring case; named `range` for an overlap with a table, the auto filter
  /// or a merge of the sheet (the message names both); named `values[column]`
  /// for a header cell that holds anything but the column's name. Throws a
  /// [StateError] for a sheet that is not a worksheet or has no part, and as
  /// [setCell] does for a cell it cannot set, and an [XlsxReadException] when
  /// the sheet, its relationships or a table part it needs cannot be read.
  /// Whatever it throws, nothing has changed, except that reading warnings
  /// are reported on first read.
  void addTable(XlsxTable table) {
    checkTable(table);
    final WorksheetPart part = _editablePart('tables');
    _host.checkTableNameFree(table.name);
    final List<({String partName, TablePart table})> list = _sheetTables();
    final XlsxRange range = table.range;
    checkTablePlace(table.name, range, _tableRanges(list), autoFilter, merges);
    final List<({int row, int column, Object? value})> cells = _tableCells(
      table,
    );
    final ChangeLog log = _host.log;
    final OpcPackage package = _host.reader.package;
    final String sheetPart = _partName!;
    // Read here, so that a broken part throws XlsxReadException: inside the
    // transaction `addStoredRelationship` would throw the package's own error.
    _host.reader.relationshipsOf(sheetPart.substring(1));
    log.transaction(() {
      for (final ({int row, int column, Object? value}) c in cells) {
        setCell(c.row, c.column, c.value);
      }
      final int id = _host.takeTableId();
      final StringBuffer xml = StringBuffer();
      writeTable(XmlWriter(xml), id, table);
      final TablePart typed = TablePart.read(XmlPullReader(xml.toString()))!;
      final String added = addStoredPart(
        log,
        package,
        '/${tablePartName(id)}',
        ContentType.table,
        typed,
      );
      final String relationship = addStoredRelationship(
        log,
        package,
        sheetPart,
        type: RelType.table,
        target: relationshipTarget(sheetPart, added),
      );
      editLayout(
        log,
        part,
        'tableParts',
        () => part.addTablePart(relationship),
      );
      markStoredPart(log, _attachedTables, added.substring(1));
      applyChange(
        log,
        _TableListChange(list, list.length, (
          partName: added.substring(1),
          table: typed,
        ), added: true),
      );
    });
  }

  /// The cells [table] writes over what the sheet holds, with their values:
  /// each header cell and totals cell that changes. Throws an [ArgumentError]
  /// as `tableHeaderCell` does.
  List<({int row, int column, Object? value})> _tableCells(XlsxTable table) {
    final XlsxRange range = table.range;
    final List<({int row, int column, Object? value})> cells =
        <({int row, int column, Object? value})>[];
    for (int c = range.firstColumn; c <= range.lastColumn; c++) {
      if (table.headerRow) {
        final Object? current = _tableCellValue(range.firstRow, c);
        final Object? next = tableHeaderCell(table, c, current);
        if (current == null) {
          cells.add((row: range.firstRow, column: c, value: next));
        }
      }
      if (table.totalsRow) {
        final Object? current = _tableCellValue(range.lastRow, c);
        final Object? next = tableTotalsCell(table, c, current);
        if (current == null && next != null) {
          cells.add((row: range.lastRow, column: c, value: next));
        }
      }
    }
    return cells;
  }

  /// What the cell at [row] and [column] holds, as the writer's checks take
  /// it: its formula, else its value; `null` for no value.
  Object? _tableCellValue(int row, int column) {
    final XlsxReadCell? cell = cellAt(row, column);
    final String? formula = cell?.formula;
    return formula != null ? XlsxFormula(formula) : cell?.value;
  }

  /// Gives the table [name] the look [style], or none with `null`.
  ///
  /// The `name` and the flags of `<tableStyleInfo>` that differ are set in
  /// place and everything else of the part stays; a table without the element
  /// gains it after `<tableColumns>`, and `null` removes it. A style equal to
  /// the table's is no edit. Neither this nor [resizeTable] and [removeTable]
  /// touches `calcChain`.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no table
  /// [name], ignoring case, and named `style` for a name that is not a
  /// built-in table style (a custom style the table has already may keep its
  /// name and change its flags); a [StateError] for a sheet that is not a
  /// worksheet or has no part; and an [XlsxReadException] when the sheet
  /// cannot be read. Whatever it throws, nothing has changed.
  void setTableStyle(String name, XlsxTableStyle? style) {
    _editablePart('tables');
    final ({String partName, TablePart table}) entry = _tableNamed(name);
    final TablePart table = entry.table;
    final XlsxTableStyle? current = table.style;
    if (style == current) return;
    if (style != null && style.name != current?.name) checkTableStyle(style);
    _editTable(entry, () => table.setStyle(style));
  }

  /// Moves the last row of the table [name], so that it covers [range].
  ///
  /// The `ref` of the table and of its `<autoFilter>` change; cells stay. A
  /// [range] equal to the table's is no edit.
  ///
  /// A formula over the table (`SUM(T[A])`) has another result, so the save
  /// sets `fullCalcOnLoad` when the workbook has formulas, as a name edit
  /// does; `calcChain` stays. Undoing the resize takes that back.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no table
  /// [name], ignoring case; named `range` for a range outside the sheet or in
  /// reverse, one whose first row, first column or last column differ from
  /// the table's, one that leaves no data row, or an overlap with another
  /// table, the auto filter or a merge (the message names both); a
  /// [StateError] for a table with a totals row or a `<sortState>` (W5 moves
  /// them) and for a sheet that is not a worksheet or has no part; and an
  /// [XlsxReadException] when the sheet cannot be read. Whatever it throws,
  /// nothing has changed.
  void resizeTable(String name, XlsxRange range) {
    validateRange(range, 'range');
    _editablePart('tables');
    final ({String partName, TablePart table}) entry = _tableNamed(name);
    final TablePart table = entry.table;
    final XlsxRange old = table.range;
    if (range == old) return;
    final String tableName = table.displayName;
    if (table.totalsRow) {
      throw StateError(
        'The table "$tableName" has a totals row; resizing it arrives in W5.',
      );
    }
    if (table.hasSortState) {
      throw StateError(
        'The table "$tableName" has a sort state; resizing it arrives in W5.',
      );
    }
    if (range.firstRow != old.firstRow ||
        range.firstColumn != old.firstColumn ||
        range.lastColumn != old.lastColumn) {
      throw ArgumentError.value(
        range,
        'range',
        'Only the last row of the table "$tableName" over ${old.ref} may '
            'move.',
      );
    }
    if (range.rowCount < (table.hasHeader ? 2 : 1)) {
      throw ArgumentError.value(
        range,
        'range',
        'The table "$tableName" needs at least one data row.',
      );
    }
    checkTablePlace(
      tableName,
      range,
      _tableRanges(<({String partName, TablePart table})>[
        for (final ({String partName, TablePart table}) t in _sheetTables())
          if (!identical(t.table, table)) t,
      ]),
      autoFilter,
      merges,
    );
    _host.log.transaction(() {
      _editTable(entry, () => table.resize(range));
      _host.workbookPart.tableEdits++;
      _host.log.record(TableResizeChange(_host.workbookPart));
    });
  }

  /// Removes the table [name]: its `<tablePart>`, its relationship and its
  /// part go, and the `<tableParts>` with its last entry. The cells stay.
  ///
  /// Every sheet loads, to look for a use of the table.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no table
  /// [name], ignoring case; a [StateError] naming the first use when a cell
  /// formula, a defined name of any sheet or a `calculatedColumnFormula` or
  /// `totalsRowFormula` of another table holds `name[`, ignoring case, not
  /// after a character of a name (`MySales[` does not use `Sales`; Excel
  /// repairs a file whose formula names a table it lacks; a string in a
  /// formula that holds the text refuses too, until W5's lexer tells them
  /// apart), when the table part has relationships of its own (a query
  /// table) or a tab on the same sheet part removed it, and for a sheet that
  /// is not a worksheet or has no part; and an
  /// [XlsxReadException] when a sheet cannot be read. Whatever it throws,
  /// nothing has changed, except that reading warnings are reported on first
  /// read.
  ///
  /// A slicer cache part (content type
  /// `application/vnd.ms-excel.slicerCache+xml`) whose `tableId` is the
  /// table's `id` refuses too, with a [StateError]: Excel would find a
  /// slicer on a table the file lacks. Every such part is read. A pivot
  /// cache that names the table is not checked.
  void removeTable(String name) {
    final WorksheetPart part = _editablePart('tables');
    final ({String partName, TablePart table}) entry = _tableNamed(name);
    final String tableName = entry.table.displayName;
    final PackageReader reader = _host.reader;
    final OpcPackage package = reader.package;
    final String partName = entry.partName;
    if (!package.hasPart(partName)) {
      throw StateError(
        'The table "$tableName" cannot be removed: a sheet on the same part '
        'removed it.',
      );
    }
    if (reader
        .guardXml(partName, () => package.relationshipsOf(partName))
        .isNotEmpty) {
      throw StateError(
        'The table "$tableName" has relationships of its own (a query table, '
        'say); it cannot be removed.',
      );
    }
    final String? slicer = _slicerOf(reader, package, entry.table.id);
    if (slicer != null) {
      throw StateError(
        'The table "$tableName" cannot be removed: the slicer cache '
        '"$slicer" is on it.',
      );
    }
    final String? use = _host.firstTableUse(entry.table);
    if (use != null) {
      throw StateError(
        'The table "$tableName" cannot be removed: $use uses it, and rewriting '
        'formulas arrives in W5.',
      );
    }
    final String sheetPart = _partName!;
    final List<String> ids = <String>[
      for (final PartRelationship rel in reader.relationshipsOf(
        sheetPart.substring(1),
      ))
        if (rel.type == RelType.table && rel.target == partName) rel.id,
    ];
    final List<({String partName, TablePart table})> list = _sheetTables();
    final ChangeLog log = _host.log;
    log.transaction(() {
      for (final String id in ids) {
        editLayout(log, part, 'tableParts', () => part.removeTablePart(id));
        removeStoredRelationship(log, package, sheetPart, id);
      }
      final bool referenced = reader.guardXml(
        partName,
        () => package.isReferenced(partName),
      );
      if (!referenced) {
        _host.forgetTablePart(partName);
        removeStoredPart(log, package, partName);
      }
      applyChange(
        log,
        _TableListChange(list, list.indexOf(entry), entry, added: false),
      );
    });
  }

  /// The name of the first slicer cache part of [package] whose
  /// `tableSlicerCache` names the table [id], or `null`. Throws an
  /// [XlsxReadException] when a slicer cache part cannot be read.
  String? _slicerOf(PackageReader reader, OpcPackage package, int id) {
    if (id <= 0) return null;
    for (final String name in package.partNames) {
      if (package.contentTypeOf(name) != _slicerCacheType) continue;
      final bool found = reader.guardXml(name, () {
        final XmlPullReader r = reader.openXml(name);
        while (r.next()) {
          if (r.eventType == XmlEventType.startElement &&
              r.localName == 'tableSlicerCache' &&
              r.getAttribute('tableId', namespaceUri: '') == '$id') {
            return true;
          }
        }
        return false;
      });
      if (found) return name;
    }
    return null;
  }

  /// Runs [edit], a change of the table of [entry], in one transaction, with
  /// the table's part made what the package writes.
  void _editTable(
    ({String partName, TablePart table}) entry,
    void Function() edit,
  ) {
    final ChangeLog log = _host.log;
    log.transaction(() {
      attachStoredPart(
        log,
        _host.reader.package,
        _attachedTables,
        entry.partName,
        entry.table,
      );
      editTable(log, entry.table, edit);
    });
  }

  /// The table of the sheet named [name], ignoring case. Throws an
  /// [ArgumentError] named `name` when there is none.
  ({String partName, TablePart table}) _tableNamed(String name) {
    final String key = sheetNameKey(name);
    for (final ({String partName, TablePart table}) t in _sheetTables()) {
      if (sheetNameKey(t.table.displayName) == key) return t;
    }
    throw ArgumentError.value(
      name,
      'name',
      'The sheet "${this.name}" has no table "$name".',
    );
  }

  /// The names and ranges of [tables], for `checkTablePlace`.
  List<({String name, XlsxRange range})> _tableRanges(
    List<({String partName, TablePart table})> tables,
  ) => <({String name, XlsxRange range})>[
    for (final ({String partName, TablePart table}) t in tables)
      (name: t.table.displayName, range: t.table.range),
  ];
}
