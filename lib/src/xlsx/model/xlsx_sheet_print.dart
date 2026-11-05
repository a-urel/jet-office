/// The print area, print titles and auto filter of an [XlsxSheet]: the
/// members that read and set them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetPrint] in, so these are members of the sheet.
///
/// The print area and the print titles are the sheet's built-in defined
/// names (`_xlnm.Print_Area`, `_xlnm.Print_Titles`) in the workbook part;
/// the auto filter is the sheet's `<autoFilter>` and its hidden name
/// `_xlnm._FilterDatabase`, which one transaction keeps in step. A new name
/// is the text the writer writes for the same call, and a changed one
/// replaces the old in its place. A name whose formula is not plain
/// references of this sheet (`OFFSET(...)`, `#REF!`) reads as empty, is
/// reported once and kept; setting replaces it.
part of 'xlsx_sheet.dart';

/// Sets the auto filter of [sheet] to [range] (`null` removes it) as the
/// setter does; [afterName] runs between the change of the name and the
/// change of the element, inside the transaction, so a test can prove that
/// a failure in the second part undoes the first.
void setSheetAutoFilter(
  XlsxSheet sheet,
  XlsxRange? range, {
  void Function()? afterName,
}) => sheet._setAutoFilter(range, afterName: afterName);

/// The print and filter half of [XlsxSheet].
mixin _SheetPrint {
  // What the sheet gives its print half.
  SheetHost get _host;
  String get name;
  Set<String> get _featureReported;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);
  List<({String partName, TablePart table})> _sheetTables();
  void _warn(XlsxWarningCode code, String? cell, {String? detail});

  static const String _areaName = '_xlnm.Print_Area';
  static const String _titlesName = '_xlnm.Print_Titles';
  static const String _filterName = '_xlnm._FilterDatabase';

  /// The cells printed: the areas of the sheet's `_xlnm.Print_Area`, in
  /// file order, or an empty list when it has none.
  ///
  /// A formula that is not a list of plain references of this sheet
  /// (`OFFSET(...)`, `#REF!`, another sheet's cells, a whole column) reads
  /// as empty, is reported once as `featureEntryInvalid` and stays in the
  /// file. Does not load the sheet. Unmodifiable.
  List<XlsxRange> get printArea {
    final NameEntry? entry = _builtIn(_areaName);
    if (entry == null) return const <XlsxRange>[];
    final List<XlsxRange>? ranges = _parseAreas(entry.formula);
    if (ranges == null) {
      _reportInvalid(_areaName);
      return const <XlsxRange>[];
    }
    return List<XlsxRange>.unmodifiable(ranges);
  }

  /// Sets the cells printed, each of [ranges] one area on its own page; an
  /// empty list removes the name.
  ///
  /// The name is written as the writer's `printArea` writes it, after the
  /// names already there, or in the place of this sheet's own. A list equal
  /// to [printArea] changes nothing. Throws an [ArgumentError] named
  /// `ranges[i]` for a range the writer refuses; nothing has changed then.
  /// A print area asks Excel for no recalculation.
  set printArea(List<XlsxRange> ranges) {
    checkPrintAreaRanges(ranges);
    final List<XlsxRange> current = printArea;
    if (current.length == ranges.length) {
      bool same = true;
      for (int i = 0; i < ranges.length; i++) {
        if (current[i] != ranges[i]) same = false;
      }
      if (same) return;
    }
    _setBuiltIn(
      _areaName,
      ranges.isEmpty ? null : printAreaFormula(name, ranges),
    );
  }

  /// The rows and columns repeated on every printed page, as inclusive
  /// 0-based spans, or `null` for each the sheet does not repeat.
  ///
  /// Read like [printArea]: a formula that is not plain row and column
  /// spans of this sheet reads as no titles and is reported once. Does not
  /// load the sheet.
  ({(int, int)? rows, (int, int)? columns}) get printTitles {
    const ({(int, int)? rows, (int, int)? columns}) none = (
      rows: null,
      columns: null,
    );
    final NameEntry? entry = _builtIn(_titlesName);
    if (entry == null) return none;
    final ({(int, int)? rows, (int, int)? columns})? titles = _parseTitles(
      entry.formula,
    );
    if (titles == null) {
      _reportInvalid(_titlesName);
      return none;
    }
    return titles;
  }

  /// Repeats [rows] and [columns] (inclusive 0-based spans) on every
  /// printed page; both `null` removes the name.
  ///
  /// Written as the writer's `printTitles` writes it. Values equal to
  /// [printTitles] change nothing. Throws an [ArgumentError] named `rows`
  /// or `columns` for a span outside the sheet or reversed; nothing has
  /// changed then.
  void setPrintTitles({(int, int)? rows, (int, int)? columns}) {
    checkPrintTitles(rows: rows, columns: columns);
    final ({(int, int)? rows, (int, int)? columns}) current = printTitles;
    if (current.rows == rows && current.columns == columns) return;
    _setBuiltIn(
      _titlesName,
      rows == null && columns == null
          ? null
          : printTitlesFormula(name, rows: rows, columns: columns),
    );
  }

  /// The range of the sheet's `<autoFilter>`, or `null` when it has none.
  ///
  /// An element without a readable `ref` reads as `null`, is reported once
  /// as `featureEntryInvalid` and stays in the file. Loads the sheet.
  /// Throws an [XlsxReadException] when the sheet cannot be read.
  XlsxRange? get autoFilter {
    final Object? node = _load()?.layoutElement('autoFilter');
    if (node is! XmlNode) return null;
    final XlsxRange? range = _filterRange(node);
    if (range == null) _reportInvalid('autoFilter');
    return range;
  }

  /// Sets the filter range, or removes the filter with `null`; the filter
  /// buttons' choices are not applied or removed.
  ///
  /// Writes `<autoFilter ref="...">` in schema position and
  /// `_xlnm._FilterDatabase` in one transaction. Over the same first column
  /// the `filterColumn`s whose `colId` lies inside the new width stay; every
  /// other child goes, and all of them when the first column moves. Rows
  /// that a filter hid stay hidden. A range equal to [autoFilter] changes
  /// nothing.
  ///
  /// Throws an [ArgumentError] named `range` as the writer's `autoFilter`
  /// does, for a range outside the sheet, reversed, or overlapping a table
  /// (a table has its own filter), a [StateError] for a sheet that is not a
  /// worksheet or has no part and an [XlsxReadException] when the sheet
  /// cannot be read. Whatever it throws, nothing has changed.
  set autoFilter(XlsxRange? range) => _setAutoFilter(range);

  void _setAutoFilter(XlsxRange? range, {void Function()? afterName}) {
    if (range != null) validateRange(range, 'range');
    final WorksheetPart part = _editablePart('auto filter');
    if (range != null) {
      checkNoTableOverlap(range, <({String name, XlsxRange range})>[
        for (final ({String partName, TablePart table}) t in _sheetTables())
          (name: t.table.displayName, range: t.table.range),
      ]);
    }
    if (range == autoFilter) return;
    final XmlNode? old = part.layoutElement('autoFilter') as XmlNode?;
    final XmlNode? next = range == null ? null : _filterNode(part, old, range);
    final ChangeLog log = _host.log;
    log.transaction(() {
      _editBuiltIn(
        _filterName,
        range == null ? null : quotedSheetRef(name, range.absoluteRef),
        hidden: true,
      );
      afterName?.call();
      editLayout(
        log,
        part,
        'autoFilter',
        () => part.setNode('autoFilter', next),
      );
    });
  }

  /// The element for [range]: [old] with the new `ref` and the children
  /// that survive, or a new one.
  XmlNode _filterNode(WorksheetPart part, XmlNode? old, XlsxRange range) {
    if (old == null) {
      return XmlNode.made(
        part.elementPrefix,
        'autoFilter',
        attributes: <String, String>{'ref': range.ref},
      );
    }
    final XlsxRange? was = _filterRange(old);
    final bool sameStart = was != null && was.firstColumn == range.firstColumn;
    return old
        .withChanges(<String, String?>{'ref': range.ref})
        .withChildren(<Object>[
          if (sameStart)
            for (final Object c in old.children)
              if (_keepsColumn(c, range.columnCount)) c,
        ]);
  }

  /// Whether [child] is a `filterColumn` whose `colId` is below [width].
  bool _keepsColumn(Object child, int width) {
    if (child is! OpaqueXml ||
        child.namespaceUri != Ns.main ||
        child.localName != 'filterColumn') {
      return false;
    }
    final int? id = parseSheetId(readerOf(child).getAttribute('colId'));
    return id != null && id < width;
  }

  /// The range of the `ref` of [node], or `null` when it has none that
  /// `XlsxRange.parse` accepts.
  XlsxRange? _filterRange(XmlNode node) {
    final String? ref = node.attribute('ref');
    if (ref == null) return null;
    try {
      return XlsxRange.parse(ref);
    } on ArgumentError {
      return null;
    }
  }

  // -- The names ---------------------------------------------------------

  /// This sheet's name [builtIn] (compared ignoring case), or `null`.
  NameEntry? _builtIn(String builtIn) {
    final int index = _host.sheetIndexOf(this as XlsxSheet);
    final String key = builtIn.toLowerCase();
    for (final NameEntry e in _host.workbookPart.names) {
      if (e.localSheetId == index && e.name.toLowerCase() == key) return e;
    }
    return null;
  }

  /// Sets or removes this sheet's built-in name in one transaction.
  void _setBuiltIn(String builtIn, String? formula) {
    _host.log.transaction(() => _editBuiltIn(builtIn, formula));
  }

  /// Writes [formula] as this sheet's name [builtIn], in the place of the
  /// one there or after the others; `null` removes it. [hidden] is as the
  /// name had it, or `false`, unless given. Must run inside a transaction.
  /// Recorded as a workbook element edit, not as a name edit: print and
  /// filter names do not ask for recalculation.
  void _editBuiltIn(String builtIn, String? formula, {bool? hidden}) {
    final WorkbookPart part = _host.workbookPart;
    final NameEntry? existing = _builtIn(builtIn);
    editWorkbook(_host.log, part, 'definedNames', () {
      if (formula == null) {
        if (existing != null) part.removeName(existing);
        return;
      }
      final NameEntry entry = NameEntry(
        name: existing?.name ?? builtIn,
        formula: formula,
        localSheetId: _host.sheetIndexOf(this as XlsxSheet),
        hidden: hidden ?? existing?.hidden ?? false,
        comment: existing?.comment,
      );
      if (existing == null) {
        part.addName(entry);
      } else {
        part.replaceName(existing, entry);
      }
    });
  }

  void _reportInvalid(String what) {
    if (_featureReported.add(what)) {
      _warn(
        XlsxWarningCode.featureEntryInvalid,
        null,
        detail: what == 'autoFilter' ? what : 'definedName',
      );
    }
  }

  // -- Reading a name's formula -----------------------------------------

  /// The ranges of [formula], a comma list of references of this sheet, or
  /// `null` when it is anything else.
  List<XlsxRange>? _parseAreas(String formula) {
    final List<XlsxRange> ranges = <XlsxRange>[];
    for (final String part in _splitReferences(formula)) {
      final String? ref = _afterSheet(part);
      if (ref == null) return null;
      try {
        ranges.add(XlsxRange.parse(ref));
      } on ArgumentError {
        return null;
      }
    }
    return ranges.isEmpty ? null : ranges;
  }

  static final RegExp _columns = RegExp(
    r'^\$?([A-Za-z]{1,3})(?::\$?([A-Za-z]{1,3}))?$',
  );
  static final RegExp _rows = RegExp(
    r'^\$?([1-9][0-9]{0,6})(?::\$?([1-9][0-9]{0,6}))?$',
  );

  /// The spans of [formula], a comma list of whole columns and whole rows
  /// of this sheet (at most one of each), or `null` for anything else.
  ({(int, int)? rows, (int, int)? columns})? _parseTitles(String formula) {
    (int, int)? rows;
    (int, int)? columns;
    for (final String part in _splitReferences(formula)) {
      final String? ref = _afterSheet(part);
      if (ref == null) return null;
      final RegExpMatch? column = _columns.firstMatch(ref);
      final RegExpMatch? row = _rows.firstMatch(ref);
      if (column != null && columns == null) {
        final int first = _columnIndex(column.group(1)!);
        final int last = _columnIndex(column.group(2) ?? column.group(1)!);
        if (last >= XlsxLimits.maxColumns || first > last) return null;
        columns = (first, last);
      } else if (row != null && rows == null) {
        final int first = int.parse(row.group(1)!) - 1;
        final int last = int.parse(row.group(2) ?? row.group(1)!) - 1;
        if (last >= XlsxLimits.maxRows || first > last) return null;
        rows = (first, last);
      } else {
        return null;
      }
    }
    return rows == null && columns == null
        ? null
        : (rows: rows, columns: columns);
  }

  static int _columnIndex(String letters) {
    int column = 0;
    for (final int unit in letters.toUpperCase().codeUnits) {
      column = column * 26 + (unit - 64);
    }
    return column - 1;
  }

  /// [formula] split at the commas outside single quotes.
  static List<String> _splitReferences(String formula) {
    final List<String> parts = <String>[];
    final StringBuffer part = StringBuffer();
    bool quoted = false;
    for (int i = 0; i < formula.length; i++) {
      final String c = formula[i];
      if (c == "'") quoted = !quoted;
      if (c == ',' && !quoted) {
        parts.add(part.toString());
        part.clear();
      } else {
        part.write(c);
      }
    }
    parts.add(part.toString());
    return parts;
  }

  /// What follows `Sheet!` or `'Sheet'!` in [reference] when the sheet is
  /// this one (compared ignoring case), or `null`.
  String? _afterSheet(String reference) {
    final StringBuffer sheet = StringBuffer();
    int at;
    if (reference.startsWith("'")) {
      int i = 1;
      while (i < reference.length) {
        if (reference[i] == "'") {
          if (i + 1 < reference.length && reference[i + 1] == "'") {
            sheet.write("'");
            i += 2;
            continue;
          }
          break;
        }
        sheet.write(reference[i]);
        i++;
      }
      if (i + 1 >= reference.length || reference[i + 1] != '!') return null;
      at = i + 2;
    } else {
      final int bang = reference.indexOf('!');
      if (bang <= 0) return null;
      sheet.write(reference.substring(0, bang));
      at = bang + 1;
    }
    return sheetNameKey(sheet.toString()) == sheetNameKey(name)
        ? reference.substring(at)
        : null;
  }
}
