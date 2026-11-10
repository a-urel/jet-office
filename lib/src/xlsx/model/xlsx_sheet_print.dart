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
  /// `ranges[i]` for a range the writer refuses, a [StateError] for a sheet
  /// that is not a worksheet or has no part and an [XlsxReadException] when
  /// the sheet cannot be read; nothing has changed then. A print area asks
  /// Excel for no recalculation.
  set printArea(List<XlsxRange> ranges) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        checkPrintAreaRanges(ranges);
        _editablePart('print area');
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
      });

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
  /// or `columns` for a span outside the sheet or reversed, a [StateError]
  /// for a sheet that is not a worksheet or has no part and an
  /// [XlsxReadException] when the sheet cannot be read; nothing has changed
  /// then.
  void setPrintTitles({(int, int)? rows, (int, int)? columns}) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        checkPrintTitles(rows: rows, columns: columns);
        _editablePart('print titles');
        final ({(int, int)? rows, (int, int)? columns}) current = printTitles;
        if (current.rows == rows && current.columns == columns) return;
        _setBuiltIn(
          _titlesName,
          rows == null && columns == null
              ? null
              : printTitlesFormula(name, rows: rows, columns: columns),
        );
      });

  // -- Page setup, headers and footers -----------------------------------

  /// How the sheet prints, read from its `printOptions`, `pageMargins`,
  /// `pageSetup` and `sheetPr/pageSetUpPr`, or `null` when it has none of
  /// the first three.
  ///
  /// `fitToWidth` and `fitToHeight` are read only when the sheet is fitted
  /// to pages (`fitToPage`; an axis that is absent counts as 1 and `0`
  /// reads `null`, automatic), a `firstPageNumber` only with
  /// `useFirstPageNumber`, and `scale` only when the sheet is not fitted.
  /// A field with a bad value reads as its default, is reported once per
  /// element as `featureEntryInvalid` and stays in the file. Only the
  /// first element of each kind is read. Loads the sheet. Throws an
  /// [XlsxReadException] when the sheet cannot be read.
  XlsxPageSetup? get pageSetup {
    final WorksheetPart? part = _load();
    return part == null
        ? null
        : readPageSetup(_pageNodes(part), _reportInvalid);
  }

  /// Sets how the sheet prints, or removes `printOptions`, `pageMargins`,
  /// `pageSetup` and `fitToPage` with `null`.
  ///
  /// A new element is the text the writer writes for the same setup, in
  /// schema position. An existing element keeps its other attributes
  /// (`r:id` of the printer settings, `horizontalDpi`, `copies`, ...) and
  /// changes an attribute only when its meaning changes; an element the
  /// setup does not need goes when nothing is left in it. `fitToPage` joins
  /// `sheetPr` as `pageSetUpPr` and leaves it with `sheetPr`, which goes
  /// when it is empty. A setup equal to [pageSetup] changes nothing.
  ///
  /// Throws an [ArgumentError] named after the field for a value the
  /// writer refuses (a `scale` outside 10 to 400 or beside a fit axis, a
  /// negative margin, ...), a [StateError] for a sheet that is not a
  /// worksheet or has no part and an [XlsxReadException] when the sheet
  /// cannot be read. Whatever it throws, nothing has changed.
  set pageSetup(XlsxPageSetup? value) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        if (value != null) checkPageSetup(value);
        final WorksheetPart part = _editablePart('page setup');
        final PageSetupNodes old = _pageNodes(part);
        if (value == readPageSetup(old, _reportInvalid)) return;
        final String prefix = part.elementPrefix;
        final PageSetupNodes applied = value == null
            ? removePageSetup(old)
            : applyPageSetup(old, value, prefix);
        final XmlNode? sheetPr = sheetPrFit(
          old.sheetPr,
          value != null && pageSetupFitsToPage(value),
          prefix,
          _sheetPrOrder,
        );
        final ChangeLog log = _host.log;
        log.transaction(() {
          _swapNode(part, 'sheetPr', old.sheetPr, sheetPr);
          _swapNode(part, 'printOptions', old.options, applied.options);
          _swapNode(part, 'pageMargins', old.margins, applied.margins);
          _swapNode(part, 'pageSetup', old.setup, applied.setup);
        });
      });

  /// The headers and footers of the sheet, from its `headerFooter`, or
  /// `null` when it has none.
  ///
  /// `_xHHHH_` in a text is decoded. `differentOddEven` and `differentFirst`
  /// read `null` when the writer derives the same value from the texts. A
  /// text the writer would refuse, or a flag that is not a boolean, reads
  /// as its default, is reported once as `featureEntryInvalid` and stays in
  /// the file. Only the first `headerFooter` is read. Loads the sheet.
  /// Throws an [XlsxReadException] when the sheet cannot be read.
  XlsxHeaderFooter? get headerFooter {
    final Object? node = _load()?.layoutElement('headerFooter');
    return node is XmlNode ? readHeaderFooter(node, _reportInvalid) : null;
  }

  /// Sets the headers and footers, or removes the `headerFooter` with
  /// `null`.
  ///
  /// A new element is the text the writer writes, and none for a value
  /// that has no text and only defaults. An existing one has its text
  /// children replaced and its flags changed where their meaning does; its
  /// other attributes and children stay, and the element goes when nothing
  /// is left in it. `legacyDrawingHF` is not touched. A value equal to
  /// [headerFooter] changes nothing.
  ///
  /// Throws an [ArgumentError] named after the text for a value the writer
  /// refuses, a [StateError] for a sheet that is not a worksheet or has no
  /// part and an [XlsxReadException] when the sheet cannot be read.
  /// Whatever it throws, nothing has changed.
  set headerFooter(XlsxHeaderFooter? value) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        if (value != null) checkHeaderFooter(value);
        final WorksheetPart part = _editablePart('header and footer');
        final XmlNode? old = part.layoutElement('headerFooter') as XmlNode?;
        final XlsxHeaderFooter? current = old == null
            ? null
            : readHeaderFooter(old, _reportInvalid);
        if (value == current) return;
        final XmlNode? next = value == null
            ? null
            : applyHeaderFooter(old, value, part.elementPrefix);
        final ChangeLog log = _host.log;
        log.transaction(() => _swapNode(part, 'headerFooter', old, next));
      });

  /// The typed first element of each slot of the page setup.
  PageSetupNodes _pageNodes(WorksheetPart part) {
    XmlNode? node(String slot) {
      final Object? e = part.layoutElement(slot);
      return e is XmlNode ? e : null;
    }

    return (
      options: node('printOptions'),
      margins: node('pageMargins'),
      setup: node('pageSetup'),
      sheetPr: node('sheetPr'),
    );
  }

  /// Makes [next] the element of [slot] unless it is [old] already. Must
  /// run inside a transaction.
  void _swapNode(WorksheetPart part, String slot, XmlNode? old, XmlNode? next) {
    if (identical(old, next)) return;
    editLayout(_host.log, part, slot, () => part.setNode(slot, next));
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
  set autoFilter(XlsxRange? range) => _recordSheetEdit(
    this,
    XlsxChangeKind.featureChanged,
    range: range,
    () => _setAutoFilter(range),
  );

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

  /// Reports `featureEntryInvalid` once for [what], a built-in name or the
  /// name of an element.
  void _reportInvalid(String what) {
    if (_featureReported.add(what)) {
      _warn(
        XlsxWarningCode.featureEntryInvalid,
        null,
        detail: what.startsWith('_xlnm.') ? 'definedName' : what,
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

/// The `autoFilter` holder of a sheet, which also moves its sort state and
/// page breaks.
///
/// On a row or column edit of the sheet the filter's `ref` shifts
/// ([ReferenceShift.shiftRange]); when the edit deletes it wholly the filter
/// goes, with its `_xlnm._FilterDatabase` name. On a column edit each
/// `filterColumn`'s `colId` is renumbered from the filter's new first column,
/// and one whose column is deleted goes. A `sortState` (the sheet's, or the
/// filter's) shifts its `ref` and each `sortCondition`'s; a condition wholly
/// deleted goes, and the state goes with its range or its last condition. A
/// `brk` of `rowBreaks` (on a row edit) or `colBreaks` (on a column edit) names
/// the first row or column of a page (0-based); it shifts with it and goes when
/// it is deleted, `count` and `manualBreakCount` following; on the other axis
/// its `min` and `max` shift as a range does, and it goes when that span is
/// wholly deleted. Only the changed attributes are rewritten.
final class _FilterHolder implements ReferenceHolder {
  _FilterHolder(this._sheet, this._part);

  final XlsxSheet _sheet;
  final WorksheetPart _part;

  ChangeLog get _log => _sheet._host.log;

  @override
  String get holderName => 'autoFilter';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    if (edit == null || !_editsSheet(edit, _sheet.name)) return;
    _shiftFilter(edit);
    _shiftSheetSort(edit);
    final bool rows = edit.axis == ShiftAxis.rows;
    _shiftBreaks(rows ? 'rowBreaks' : 'colBreaks', edit);
    _shiftExtents(rows ? 'colBreaks' : 'rowBreaks', edit);
  }

  /// Shifts the filter, or removes it when the edit deletes it wholly.
  void _shiftFilter(ReferenceShift edit) {
    final XmlNode? node = _part.layoutElement('autoFilter') as XmlNode?;
    final String? ref = node?.attribute('ref');
    final List<XlsxRange>? read = ref == null ? null : parseSqref(ref);
    if (node == null || read == null || read.length != 1) return;
    final XlsxRange range = read.single;
    final XlsxRange? moved = edit.shiftRange(range);
    if (moved == null) {
      _sheet._editBuiltIn(_SheetPrint._filterName, null);
      editLayout(_log, _part, 'autoFilter', () {
        _part.setNode('autoFilter', null);
      });
      return;
    }
    XmlNode next = node.withChanges(<String, String?>{
      if (moved != range) 'ref': moved.ref,
    });
    bool changed = false;
    final List<Object> children = <Object>[];
    for (final Object c in node.children) {
      final Object? kept = _shiftChild(c, range, moved, edit);
      changed |= !identical(kept, c);
      if (kept != null) children.add(kept);
    }
    if (changed) next = next.withChildren(children);
    if (identical(next, node)) return;
    editLayout(_log, _part, 'autoFilter', () {
      _part.setNode('autoFilter', next);
    });
    return;
  }

  /// [child] of a filter over [range], now over [moved]: a `filterColumn`
  /// renumbered on a column edit, or `null` when its column is deleted; a
  /// `sortState` shifted, or `null` when it goes; anything else as it is.
  static Object? _shiftChild(
    Object child,
    XlsxRange range,
    XlsxRange moved,
    ReferenceShift edit,
  ) {
    if (child is XmlNode && child.localName == 'sortState') {
      return _shiftSort(child, edit);
    }
    if (child is! OpaqueXml || child.namespaceUri != Ns.main) return child;
    if (child.localName == 'sortState') {
      final XmlNode node = XmlNode.read(
        readerOf(child),
        const <String, Set<String>>{},
      );
      final XmlNode? next = _shiftSort(node, edit);
      return identical(next, node) ? child : next;
    }
    if (child.localName != 'filterColumn' || edit.axis != ShiftAxis.columns) {
      return child;
    }
    final int? id = parseSheetId(readerOf(child).getAttribute('colId'));
    if (id == null) return child;
    final ({int row, int column})? cell = edit.shiftCell(
      range.firstRow,
      range.firstColumn + id,
    );
    if (cell == null) return null;
    final int next = cell.column - moved.firstColumn;
    if (next == id) return child;
    return _withAttribute(child, 'colId', '$next');
  }

  static OpaqueXml _withAttribute(OpaqueXml element, String name, String to) =>
      spliceElement(
        element,
        (XmlPullReader r, int level) => level == 0
            ? SpliceEdit(attributes: <String, String>{name: to})
            : null,
      );

  /// [sort] shifted, `null` when its range or its last condition goes;
  /// [sort] itself when nothing changes or its `ref` cannot be read.
  static XmlNode? _shiftSort(XmlNode sort, ReferenceShift edit) {
    final XlsxRange? range = _single(sort.attribute('ref'));
    if (range == null) return sort;
    final XlsxRange? moved = edit.shiftRange(range);
    if (moved == null) return null;
    bool changed = false;
    bool hadCondition = false;
    final List<Object> children = <Object>[];
    for (final Object c in sort.children) {
      if (c is! OpaqueXml ||
          c.namespaceUri != Ns.main ||
          c.localName != 'sortCondition') {
        children.add(c);
        continue;
      }
      hadCondition = true;
      final XlsxRange? at = _single(
        readerOf(c).getAttribute('ref', namespaceUri: ''),
      );
      final XlsxRange? to = at == null ? at : edit.shiftRange(at);
      if (at != null && to == null) {
        changed = true;
      } else if (at != null && to != at) {
        changed = true;
        children.add(_withAttribute(c, 'ref', to!.ref));
      } else {
        children.add(c);
      }
    }
    if (hadCondition &&
        !children.any(
          (Object c) => c is OpaqueXml && c.localName == 'sortCondition',
        )) {
      return null;
    }
    final XmlNode next = sort.withChanges(<String, String?>{
      if (moved != range) 'ref': moved.ref,
    });
    return changed ? next.withChildren(children) : next;
  }

  static XlsxRange? _single(String? ref) {
    final List<XlsxRange>? read = ref == null ? null : parseSqref(ref);
    return read == null || read.length != 1 ? null : read.single;
  }

  /// Shifts the sheet's own `sortState`, which goes only when the edit
  /// deletes its range or its last condition, not with the filter.
  void _shiftSheetSort(ReferenceShift edit) {
    final XmlNode? node = _part.layoutElement('sortState') as XmlNode?;
    if (node == null) return;
    final XmlNode? next = _shiftSort(node, edit);
    if (identical(next, node)) return;
    editLayout(_log, _part, 'sortState', () {
      _part.setNode('sortState', next);
    });
  }

  void _shiftBreaks(String slot, ReferenceShift edit) {
    final XmlNode? node = _part.layoutElement(slot) as XmlNode?;
    if (node == null) return;
    final bool rows = edit.axis == ShiftAxis.rows;
    bool changed = false;
    final List<Object> children = <Object>[];
    for (final Object c in node.children) {
      final String? text = c is XmlNode && c.localName == 'brk'
          ? c.attribute('id')
          : null;
      final int? id = text == null ? null : parseSheetId(text);
      if (c is! XmlNode || id == null) {
        children.add(c);
        continue;
      }
      final ({int row, int column})? at = edit.shiftCell(
        rows ? id : 0,
        rows ? 0 : id,
      );
      if (at == null) {
        changed = true;
        continue;
      }
      final int moved = rows ? at.row : at.column;
      final XmlNode next = c.withChanges(<String, String?>{
        if (moved != id) 'id': '$moved',
      });
      changed |= !identical(next, c);
      children.add(next);
    }
    if (!changed) return;
    _setBreaks(slot, node, children);
  }

  /// Sets [slot] to [node] holding [children], its `count` and
  /// `manualBreakCount` following; removes it when no `brk` is left.
  void _setBreaks(String slot, XmlNode node, List<Object> children) {
    final List<XmlNode> breaks = <XmlNode>[
      for (final Object c in children)
        if (c is XmlNode && c.localName == 'brk') c,
    ];
    final int manual = breaks
        .where(
          (XmlNode b) =>
              b.attribute('man') == '1' || b.attribute('man') == 'true',
        )
        .length;
    final XmlNode? next = breaks.isEmpty
        ? null
        : node.withChildren(children).withChanges(<String, String?>{
            if (node.attribute('count') != null) 'count': '${breaks.length}',
            if (node.attribute('manualBreakCount') != null)
              'manualBreakCount': '$manual',
          });
    editLayout(_log, _part, slot, () => _part.setNode(slot, next));
  }

  /// Shifts the `min` and `max` (0-based, on the edit's axis) of each `brk`
  /// of [slot] as a range; a break whose span the edit deletes wholly goes
  /// (as [_shiftBreaks] counts), and a span that reaches the sheet's end
  /// keeps reaching it.
  void _shiftExtents(String slot, ReferenceShift edit) {
    final XmlNode? node = _part.layoutElement(slot) as XmlNode?;
    if (node == null) return;
    final bool rows = edit.axis == ShiftAxis.rows;
    bool changed = false;
    final List<Object> children = <Object>[];
    for (final Object c in node.children) {
      children.add(c);
      if (c is! XmlNode || c.localName != 'brk') continue;
      final String? minText = c.attribute('min');
      final String? maxText = c.attribute('max');
      final int? min = minText == null ? 0 : parseSheetId(minText);
      final int? max = maxText == null ? min : parseSheetId(maxText);
      final int limit = rows ? XlsxLimits.maxRows : XlsxLimits.maxColumns;
      if (min == null || max == null || min > max || max >= limit) continue;
      final XlsxRange? moved = edit.shiftRange(
        rows ? XlsxRange(min, 0, max, 0) : XlsxRange(0, min, 0, max),
      );
      if (moved == null) {
        children.removeLast();
        changed = true;
        continue;
      }
      final int first = rows ? moved.firstRow : moved.firstColumn;
      // A span to the sheet's end stays there, as a whole row or column.
      final int last = max == limit - 1
          ? max
          : rows
          ? moved.lastRow
          : moved.lastColumn;
      final XmlNode shifted = c.withChanges(<String, String?>{
        if (minText != null && first != min) 'min': '$first',
        if (maxText != null && last != max) 'max': '$last',
      });
      if (!identical(shifted, c)) {
        children.last = shifted;
        changed = true;
      }
    }
    if (!changed) return;
    _setBreaks(slot, node, children);
  }
}
