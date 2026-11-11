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
/// Renaming a table rewrites every structured reference to it, a table with
/// a totals row or a sort state can be resized, and removing a table turns
/// its users into plain ranges, as Excel's "Convert to Range".
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

/// The content type of a pivot cache definition part.
const String _pivotCacheType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.'
    'pivotCacheDefinition+xml';

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
  /// A table part the model cannot read or type (XML that is not well
  /// formed, a root that is not a SpreadsheetML `table`, a `ref` that is not
  /// a range, or columns that do not match it) is left out, kept as written,
  /// and its name stays taken. A
  /// `totalsRowFunction` no schema value names reads
  /// [XlsxTotalsFunction.none] and is reported once as `featureEntryInvalid`
  /// with the detail `table`. The part's calculated columns, `dataDxfId`,
  /// `xr:uid`, filter criteria and sort state are not in [XlsxTable]; they
  /// stay in the file as read. A sheet without a part has none, and so has a
  /// sheet whose relationships cannot be read. Unmodifiable; a table part is
  /// read on first use. Does not load the sheet, and throws nothing.
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
  /// table that is not valid in itself, as the writer's `table` refuses it;
  /// named `name` for a name a table has on any
  /// sheet (loaded or not, listed or not) or a defined name has in any scope,
  /// ignoring case; named `range` for an overlap with a table, the auto filter
  /// or a merge of the sheet (the message names both); named `values[column]`
  /// for a header cell that holds anything but the column's name. Throws a
  /// [StateError] for a sheet that is not a worksheet or has no part, and as
  /// [setCell] does for a cell it cannot set, and an [XlsxReadException] when
  /// the sheet, its relationships or a table part it needs cannot be read.
  /// Whatever it throws, nothing has changed, except that reading warnings
  /// are reported on first read.
  void addTable(XlsxTable table) => _recordSheetEdit(
    this,
    XlsxChangeKind.tableChanged,
    range: table.range,
    () {
      checkTable(table);
      final WorksheetPart part = _editablePart('tables');
      _host.checkTableNameFree(table.name);
      final List<({String partName, TablePart table})> list = _sheetTables();
      final XlsxRange range = table.range;
      checkTablePlace(
        table.name,
        range,
        _tableRanges(list),
        autoFilter,
        merges,
      );
      final List<({int row, int column, Object? value})> cells = _tableCells(
        table,
      );
      final ChangeLog log = _host.log;
      final OpcPackage package = _host.reader.package;
      final String sheetPart = _partName!;
      // Read here, so that a broken part throws XlsxReadException: inside the
      // transaction `addStoredRelationship` would throw the package's own
      // error.
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
    },
  );

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
  /// the table's is no edit. It does not touch `calcChain` or ask Excel to
  /// recalculate; [resizeTable], [renameTable] and [removeTable] say when
  /// they do.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no table
  /// [name], ignoring case, and named `style` for a name that is not a
  /// built-in table style (a custom style the table has already may keep its
  /// name and change its flags); a [StateError] for a sheet that is not a
  /// worksheet or has no part; and an [XlsxReadException] when the sheet
  /// cannot be read. Whatever it throws, nothing has changed.
  void setTableStyle(String name, XlsxTableStyle? style) => _recordSheetEdit(
    this,
    XlsxChangeKind.tableChanged,
    () {
      _editablePart('tables');
      final ({String partName, TablePart table}) entry = _tableNamed(name);
      final TablePart table = entry.table;
      final XlsxTableStyle? current = table.style;
      if (style == current) return;
      if (style != null && style.name != current?.name) checkTableStyle(style);
      _editTable(entry, () => table.setStyle(style));
    },
  );

  /// Moves the last row of the table [name], so that it covers [range].
  ///
  /// The `ref` of the table and of its `<autoFilter>` change (the filter
  /// leaves out a totals row); a `<sortState>` and its conditions whose last
  /// row is the last body row follow it. Cells stay, except a totals row's:
  /// its cells within the table's columns move to the new last row, as
  /// they are (style and formula). A [range] equal to the table's is no edit.
  ///
  /// A formula over the table (`SUM(T[A])`) has another result, so the save
  /// sets `fullCalcOnLoad` when the workbook has formulas, as a name edit
  /// does; `calcChain` stays, unless a totals row moved (its cells are
  /// elsewhere: the save drops it). Undoing the resize takes that back.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no table
  /// [name], ignoring case; named `range` for a range outside the sheet or in
  /// reverse, one whose first row, first column or last column differ from
  /// the table's, one that leaves no data row, or an overlap with another
  /// table, the auto filter or a merge (the message names both); a
  /// [StateError] naming the cell when a totals row would move onto a cell
  /// that is not empty, or a totals cell is part of a shared, array or data
  /// table formula, and for a sheet that is not a worksheet or has no part;
  /// and an [XlsxReadException] when the sheet cannot be read. Whatever it
  /// throws, nothing has changed.
  void resizeTable(String name, XlsxRange range) => _recordSheetEdit(
    this,
    XlsxChangeKind.tableChanged,
    range: range,
    () {
      validateRange(range, 'range');
      _editablePart('tables');
      final ({String partName, TablePart table}) entry = _tableNamed(name);
      final TablePart table = entry.table;
      final XlsxRange old = table.range;
      if (range == old) return;
      final String tableName = table.displayName;
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
      final int least = (table.hasHeader ? 1 : 0) + (table.totalsRow ? 1 : 0);
      if (range.rowCount < least + 1) {
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
      final CellStore store = cellStoreOf(this as XlsxSheet)!;
      final int from = old.lastRow;
      final int to = range.lastRow;
      if (table.totalsRow) {
        for (int c = old.firstColumn; c <= old.lastColumn; c++) {
          final RawCell? target = store.cellAt(to, c);
          if (target != null &&
              (target.value != null ||
                  target.formula != null ||
                  target.inline != null)) {
            throw StateError(
              'The totals row of the table "$tableName" cannot move onto cell '
              '${cellRef(to, c)} on sheet "${this.name}": it is not empty.',
            );
          }
          final RawFormula? f = store.cellAt(from, c)?.formula;
          if (f != null && f.type != FormulaType.normal) {
            throw StateError(
              'The totals cell ${cellRef(from, c)} of the table "$tableName" '
              'is part of a shared, array or data table formula; it cannot '
              'move.',
            );
          }
        }
      }
      final ChangeLog log = _host.log;
      log.transaction(() {
        if (table.totalsRow) {
          for (int c = old.firstColumn; c <= old.lastColumn; c++) {
            final RawCell? cell = store.cellAt(from, c);
            if (cell == null) continue;
            setStoredCell(log, store, to, c, cell);
            setStoredCell(log, store, from, c, null);
          }
          _host.workbookPart.structureEdits++;
          log.record(StructureEditChange(_host.workbookPart));
        }
        _editTable(entry, () => table.resize(range));
        _host.workbookPart.tableEdits++;
        log.record(TableResizeChange(_host.workbookPart));
      });
    },
  );

  /// Gives the table [name] the name [newName], and every structured
  /// reference to it (`Sales[Amount]` becomes `Revenue[Amount]`) in a cell
  /// formula of any sheet, a defined name, a column formula of any table,
  /// a rule, a validation or a chart follows. Every sheet loads. A [newName]
  /// equal to the name is no edit; one differing only in case renames. A cell
  /// formula rewritten is a changed cell: the save drops `calcChain` and asks
  /// Excel to recalculate.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no table
  /// [name], ignoring case; named `newName` for a name the writer refuses for
  /// a table, or one a table or a defined name has, ignoring case; a
  /// [StateError] when a pivot cache names the table (its `worksheetSource
  /// name`), and for a sheet that is not a worksheet or has no part; and an
  /// [XlsxReadException] when a sheet cannot be read. Whatever it throws,
  /// nothing has changed and no warning is kept.
  void renameTable(String name, String newName) =>
      _recordSheetEdit(this, XlsxChangeKind.tableChanged, () {
        _editablePart('tables');
        final ({String partName, TablePart table}) entry = _tableNamed(name);
        final TablePart table = entry.table;
        final String old = table.displayName;
        if (newName == old) return;
        final XlsxTable value = table.value;
        try {
          checkTable(
            XlsxTable(
              newName,
              value.range,
              value.columns,
              headerRow: value.headerRow,
              totalsRow: value.totalsRow,
              autoFilter: value.autoFilter,
              style: value.style,
            ),
          );
          if (sheetNameKey(newName) != sheetNameKey(old)) {
            _host.checkTableNameFree(newName);
          }
        } on ArgumentError catch (e) {
          throw ArgumentError.value(newName, 'newName', e.message);
        }
        _refusePivot(old);
        final StructuredTable structured = _structured(table);
        final ChangeLog log = _host.log;
        _host.warnings.keepOnSuccess(
          () => log.transaction(() {
            _host.references.apply(
              StructuredRename(structured, newName: newName),
              null,
            );
            _host.forgetTablePart(entry.partName);
            _editTable(entry, () => table.rename(newName));
          }),
        );
      });

  /// The table [table] of this sheet as its structured references see it.
  StructuredTable _structured(TablePart table) => StructuredTable(
    sheet: name,
    name: table.displayName,
    range: table.range,
    columns: <String>[
      for (int i = 0; i < table.columnCount; i++) table.columnName(i),
    ],
    headerRow: table.hasHeader,
    totalsRow: table.totalsRow,
  );

  /// Throws a [StateError] when a pivot cache definition names the table
  /// [tableName] in its `worksheetSource name`, ignoring case. Throws an
  /// [XlsxReadException] when such a part cannot be read.
  void _refusePivot(String tableName) {
    final PackageReader reader = _host.reader;
    final OpcPackage package = reader.package;
    final String key = sheetNameKey(tableName);
    for (final String part in package.partNames.toList()) {
      if (package.contentTypeOf(part) != _pivotCacheType) continue;
      final bool found = reader.guardXml(part, () {
        final XmlPullReader r = reader.openXml(part);
        while (r.next()) {
          if (r.eventType == XmlEventType.startElement &&
              r.localName == 'worksheetSource') {
            final String? source = r.getAttribute('name', namespaceUri: '');
            if (source != null && sheetNameKey(source) == key) return true;
          }
        }
        return false;
      });
      if (found) {
        throw StateError(
          'The pivot cache "$part" names the table "$tableName" as its '
          'source; the table cannot be renamed or removed.',
        );
      }
    }
  }

  /// Removes the table [name]: its `<tablePart>`, its relationship and its
  /// part go, and the `<tableParts>` with its last entry. The cells stay.
  ///
  /// As Excel's "Convert to Range", every structured reference to the table
  /// becomes the plain range it covers: `Sales[Amount]` is `Data!$B$2:$B$4`
  /// from another sheet or a defined name, `$B$2:$B$4` from its own sheet,
  /// `[@Amount]` in a cell of a data row is that row's cell, column absolute
  /// (`$B3`), and the table's whole body (`$A2:$C4`) from a row outside the
  /// data, as Excel writes it, and an item the table lacks (`Sales[#Totals]`
  /// without a totals row) is `#REF!`. A reference
  /// behind a workbook prefix (`[1]!Sales[A]`) names another workbook's table
  /// and stays. Every sheet loads. A cell formula rewritten is a changed
  /// cell: the save drops `calcChain` and asks Excel to recalculate.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no table
  /// [name], ignoring case; a [StateError] when a reference cannot become a
  /// range (a column the table lacks, a span that cannot be read, or the
  /// formula's own row where the formula has no cell: a defined name or a
  /// rule), when the table part has relationships of its own (a query
  /// table) or a tab on the same sheet part removed it, when a slicer cache
  /// part (content type `application/vnd.ms-excel.slicerCache+xml`, whose
  /// `tableId` is the table's `id`) or a pivot cache (`worksheetSource
  /// name`) uses it, and for a sheet that is not a worksheet or has no part;
  /// and an [XlsxReadException] when a sheet cannot be read. Whatever it
  /// throws, nothing has changed and no warning is kept, except that
  /// reading warnings are reported on first read.
  void removeTable(String name) => _recordSheetEdit(
    this,
    XlsxChangeKind.tableChanged,
    () {
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
      _refusePivot(tableName);
      final StructuredTable structured = _structured(entry.table);
      final ChangeLog log = _host.log;
      _host.warnings.keepOnSuccess(
        () => log.transaction(() {
          _host.references.apply(TableToRange(structured), null);
          _dropTable(part, entry);
        }),
      );
    },
  );

  /// Takes the table of [entry] out of the sheet, its `<tablePart>`, its
  /// relationship and, when nothing else names it, its part.
  void _dropTable(
    WorksheetPart part,
    ({String partName, TablePart table}) entry,
  ) {
    final PackageReader reader = _host.reader;
    final OpcPackage package = reader.package;
    final String partName = entry.partName;
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

/// The `tables` holder of a sheet: on a row or column edit of the sheet each
/// table's range shifts by Excel's rules ([TablePart.shiftedRange]), with
/// its filter, sort state and columns ([TablePart.shiftedText]); a table
/// whose every row or column is deleted goes, as `removeTable` takes it
/// (its users become `#REF!` through the formula holders). On every edit
/// each `calculatedColumnFormula` and `totalsRowFormula` goes through the
/// rewriter, on the sheet.
final class _TableHolder implements ReferenceHolder {
  _TableHolder(this._sheet);

  final XlsxSheet _sheet;

  @override
  String get holderName => 'tables';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    final String host = _sheet.name;
    final ReferenceShift? local = edit != null && _editsSheet(edit, host)
        ? edit
        : null;
    final List<({String partName, TablePart table})> tables =
        List<({String partName, TablePart table})>.of(_sheet._sheetTables());
    if (tables.isEmpty) return;
    final PackageReader reader = _sheet._host.reader;
    // Every refusal before any change.
    final List<XlsxRange?> ranges = <XlsxRange?>[
      for (final ({String partName, TablePart table}) t in tables)
        local == null ? t.table.range : t.table.shiftedRange(local),
    ];
    _sheet._host.log.transaction(() {
      for (int i = 0; i < tables.length; i++) {
        final ({String partName, TablePart table}) entry = tables[i];
        final XlsxRange? to = ranges[i];
        if (to == null) {
          if (reader.package.hasPart(entry.partName)) {
            _sheet._dropTable(_sheet._editablePart('tables'), entry);
          }
          continue;
        }
        // The part's text is parsed again here: XML it cannot read is a
        // file problem, an XlsxReadException naming the part.
        final String? text = reader.guardXml(
          entry.partName,
          () => entry.table.shiftedText(
            local,
            to,
            (String formula, int column, {required bool totals}) =>
                rewriteFormula(
                  formula,
                  mapper,
                  host,
                  row: totals
                      ? entry.table.range.lastRow
                      : entry.table.range.firstRow +
                            (entry.table.hasHeader ? 1 : 0),
                  column: entry.table.range.firstColumn + column,
                ),
          ),
        );
        if (text == null) continue;
        _sheet._editTable(entry, () => entry.table.replaceText(text));
      }
    });
  }
}
