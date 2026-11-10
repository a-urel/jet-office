/// A table part (`xl/tables/tableN.xml`) with its column names typed and
/// everything else kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// Excel requires the text of a table's header cell to equal its column's
/// `name`, and repairs the table when they differ, so setting a header cell
/// renames the column (decision 0009 does not let the model leave content it
/// does not type wrong). The part is written as its source text with each
/// changed name spliced in at its position, so every other character stays as
/// written. W1 typed what that needs: the table's `displayName`, `ref` and
/// `headerRowCount`, and each `<tableColumn>`'s `name`. W4 types the rest of
/// what [XlsxTable] holds (`id`, `totalsRowCount`, the filter, the style and
/// each column's totals) for reading; calculated columns, `dataDxfId`,
/// `xr:uid`, filter criteria and the sort state stay in the source, untyped.
///
/// What an edit can change is a [TableState], which is immutable, so an edit
/// swaps the part's state and an undo swaps it back. [TablePart.setStyle] and
/// [TablePart.resize] splice the source too, each attribute at its place, and
/// read the result again; a renamed column stays a change of the state until
/// the part is written or the source is spliced. [TablePart.readHead] reads
/// what stays true of a part [TablePart.read] cannot type: its name and id.
///
/// Column names are `ST_Xstring`: `_xHHHH_` is decoded on read and escaped on
/// write, as for sheet names. Formulas that refer to a renamed column by its
/// old name (`Sales[Amount]`) are not rewritten; that needs the formula lexer
/// of W5.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/package.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../formula/reference_shift.dart';
import '../range.dart';
import '../table.dart';
import 'reference_holders.dart' show rewrittenFormulaMarkup;

/// One `<tableColumn>`: its decoded name, its totals and where its `name`
/// attribute sits.
final class _Column {
  _Column(
    this.name,
    this.start,
    this.end,
    this.insertAt,
    this.function,
    this.label,
  );

  final String name;

  /// The totals row's function, [XlsxTotalsFunction.none] for none or an
  /// unknown one.
  final XlsxTotalsFunction function;

  /// The decoded `totalsRowLabel`, or `null`.
  final String? label;

  /// The decoded `<totalsRowFormula>`, or `null`; set while reading.
  String? formula;

  /// Whether [name] differs from the source, so it is spliced in.
  bool changed = false;

  /// This column named [next], to be spliced in.
  _Column renamed(String next) =>
      _Column(next, start, end, insertAt, function, label)
        ..formula = formula
        ..changed = true;

  /// The source offsets of the `name` attribute's quoted value, quotes
  /// included; `-1` when the element has no `name`.
  final int start;
  final int end;

  /// Where a missing `name` attribute is inserted: just after the element
  /// name.
  final int insertAt;
}

/// What an edit of a [TablePart] can change, at one moment. Immutable, so an
/// edit and its undo swap one for the other ([TablePart.restore]).
final class TableState {
  const TableState._(
    this._source,
    this._columns,
    this._range,
    this._filter,
    this._style,
    this._name,
  );

  final String _source;
  final String _name;
  final List<_Column> _columns;
  final XlsxRange _range;
  final XlsxRange? _filter;
  final XlsxTableStyle? _style;
}

/// A table part whose column names, style and last row can be changed.
final class TablePart implements PartContent {
  TablePart._(
    this._state,
    this.hasHeader,
    this.id,
    this.totalsRow,
    this.hasSortState,
    this.problems,
  );

  /// Reads the root of the table part [r] is positioned before, typed or
  /// not: its `id` (`0` when it has none or it is not a number) and the
  /// decoded `name` and `displayName` it has, whatever the root is named.
  ///
  /// What follows the root's start tag is not read, so a part that breaks
  /// later still answers. Returns `null` for a part without a root. XML
  /// errors in the start tag are thrown by [r].
  static ({int id, List<String> names})? readHead(XmlPullReader r) {
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement) continue;
      return (
        id: int.tryParse(r.getAttribute('id')?.trim() ?? '') ?? 0,
        names: <String>[
          for (final String attribute in const <String>['name', 'displayName'])
            if (r.getAttribute(attribute) case final String name)
              decodeXstring(name),
        ],
      );
    }
    return null;
  }

  /// Reads the table part [r] is positioned before, or returns `null` when
  /// the model cannot type it: the root is not a SpreadsheetML `<table>`, its
  /// `ref` is not a range, or `<tableColumns>` does not list one column per
  /// column of the range. A part that is `null` here is left unchanged.
  ///
  /// A `totalsRowFunction` that is not one of `ST_TotalsRowFunction`'s values
  /// reads [XlsxTotalsFunction.none] and adds `table` to [problems].
  ///
  /// XML errors are thrown by [r] as it reads.
  static TablePart? read(XmlPullReader r) {
    String? displayName;
    XlsxRange? range;
    bool hasHeader = true;
    int id = 0;
    bool totalsRow = false;
    XlsxRange? autoFilterRange;
    bool autoFilterSeen = false;
    bool hasSortState = false;
    XlsxTableStyle? style;
    bool styleSeen = false;
    bool inAutoFilter = false;
    StringBuffer? formula;
    final List<String> problems = <String>[];
    final List<_Column> columns = <_Column>[];
    // Only the first <tableColumns> is typed; a repeated one stays as text.
    int columnsSeen = 0;
    bool inColumns = false;
    while (r.next()) {
      final XmlEventType type = r.eventType;
      if (formula != null) {
        if (type == XmlEventType.characters || type == XmlEventType.cdata) {
          formula.write(r.text);
          continue;
        }
        if (type == XmlEventType.endElement) {
          columns.last.formula ??= decodeXstring(formula.toString());
          formula = null;
          continue;
        }
        formula = null;
      }
      if (type != XmlEventType.startElement) continue;
      final bool main = r.namespaceUri == Ns.main;
      if (r.depth == 1) {
        if (r.localName != 'table' || !main) return null;
        displayName = decodeXstring(
          r.getAttribute('displayName') ?? r.getAttribute('name') ?? '',
        );
        range = _range(r.getAttribute('ref'));
        hasHeader = r.getAttribute('headerRowCount')?.trim() != '0';
        id = int.tryParse(r.getAttribute('id')?.trim() ?? '') ?? 0;
        totalsRow =
            (int.tryParse(r.getAttribute('totalsRowCount')?.trim() ?? '') ??
                0) >
            0;
      } else if (r.depth == 2) {
        inAutoFilter = false;
        inColumns = r.localName == 'tableColumns' && main && ++columnsSeen == 1;
        if (main && r.localName == 'autoFilter' && !autoFilterSeen) {
          autoFilterSeen = true;
          inAutoFilter = true;
          autoFilterRange = _range(r.getAttribute('ref'));
        } else if (main && r.localName == 'sortState') {
          hasSortState = true;
        } else if (main && r.localName == 'tableStyleInfo' && !styleSeen) {
          styleSeen = true;
          style = _style(r);
        }
      } else if (inColumns &&
          r.depth == 3 &&
          r.localName == 'tableColumn' &&
          main) {
        columns.add(_column(r, problems));
      } else if (inColumns &&
          r.depth == 4 &&
          r.localName == 'totalsRowFormula' &&
          main &&
          columns.isNotEmpty &&
          columns.last.formula == null) {
        formula = StringBuffer();
      } else if (inAutoFilter &&
          r.depth == 3 &&
          r.localName == 'sortState' &&
          main) {
        hasSortState = true;
      }
    }
    if (range == null || columns.length != range.columnCount) return null;
    return TablePart._(
      TableState._(
        r.sourceText(0, r.sourceLength),
        columns,
        range,
        autoFilterRange,
        style,
        displayName!,
      ),
      hasHeader,
      id,
      totalsRow,
      hasSortState,
      problems,
    );
  }

  TableState _state;

  List<_Column> get _columns => _state._columns;

  /// What an edit can change, for [restore].
  TableState get state => _state;

  /// Makes [state], from [TablePart.state] of this part, what the part holds.
  void restore(TableState state) => _state = state;

  /// The table's name in formulas.
  String get displayName => _state._name;

  /// The cells the table covers, header and totals rows included.
  XlsxRange get range => _state._range;

  /// Whether the first row of [range] is a header of column names.
  final bool hasHeader;

  /// The table's `id`, `0` when it has none or it is not a number.
  final int id;

  /// Whether the last row of [range] is a totals row (`totalsRowCount` over
  /// 0).
  final bool totalsRow;

  /// The `ref` of the table's `<autoFilter>`, or `null` for no filter or a
  /// `ref` that is not a range.
  XlsxRange? get autoFilterRange => _state._filter;

  /// Whether the table or its filter has a `<sortState>`, kept as written.
  final bool hasSortState;

  /// The look of the table, or `null` when it has no `<tableStyleInfo>` or
  /// the element names no style.
  XlsxTableStyle? get style => _state._style;

  /// What the part holds that the model cannot read, by detail, for the sheet
  /// to report: `table` for a `totalsRowFunction` no schema value names.
  final List<String> problems;

  /// The whole table as the model types it: [displayName] as the name, the
  /// range, the columns with their totals, a header row unless
  /// `headerRowCount` is `0`, a totals row, a filter when the part has an
  /// `<autoFilter>` and its [style]. Built afresh, so it shows a renamed
  /// column.
  XlsxTable get value => XlsxTable(
    displayName,
    range,
    <XlsxTableColumn>[
      for (final _Column c in _columns)
        XlsxTableColumn(
          c.name,
          totalsFunction: c.function,
          totalsLabel: c.label,
          totalsFormula: c.formula,
        ),
    ],
    headerRow: hasHeader,
    totalsRow: totalsRow,
    autoFilter: autoFilterRange != null,
    style: style,
  );

  /// The number of columns, one per column of [range].
  int get columnCount => _columns.length;

  /// The name of column [index] (0 is the range's first column).
  String columnName(int index) => _columns[index].name;

  /// Every `calculatedColumnFormula` and `totalsRowFormula` of the part, with
  /// the column's name, both decoded, read from the part's text.
  List<({String column, String formula})> get columnFormulas {
    final List<({String column, String formula})> found =
        <({String column, String formula})>[];
    final XmlPullReader r = XmlPullReader(_text(), maxDepth: 0x7FFFFFFF);
    String column = '';
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement ||
          r.namespaceUri != Ns.main) {
        continue;
      }
      if (r.depth == 3 && r.localName == 'tableColumn') {
        column = decodeXstring(r.getAttribute('name') ?? '');
      } else if (r.depth == 4 &&
          (r.localName == 'calculatedColumnFormula' ||
              r.localName == 'totalsRowFormula')) {
        final StringBuffer text = StringBuffer();
        while (r.next() && r.eventType != XmlEventType.endElement) {
          if (r.eventType == XmlEventType.characters ||
              r.eventType == XmlEventType.cdata) {
            text.write(r.text);
          }
        }
        found.add((column: column, formula: decodeXstring(text.toString())));
      }
    }
    return found;
  }

  /// Gives column [index] the name [name], which the caller has checked
  /// (scrubbed, unique in the table, 1 to 255 characters).
  void setColumnName(int index, String name) {
    final TableState s = _state;
    _state = TableState._(
      s._source,
      List<_Column>.of(s._columns)..[index] = s._columns[index].renamed(name),
      s._range,
      s._filter,
      s._style,
      s._name,
    );
  }

  /// Gives the table the name [name], which the caller has checked: the
  /// root's `displayName` is set and its `name`, when it has one.
  void rename(String name) {
    final String source = _text();
    final _Places at = _Places(source);
    String root = source.substring(at.rootStart, at.rootTagEnd);
    final String value = escapeXstring(name);
    if (_attribute.allMatches(root).any((RegExpMatch m) => m[1] == 'name')) {
      root = _withAttribute(root, 'name', value);
    }
    root = _withAttribute(root, 'displayName', value);
    _reread(source.replaceRange(at.rootStart, at.rootTagEnd, root));
  }

  /// Gives the table the look [style], which the caller has checked: the
  /// `name` and the flags of `<tableStyleInfo>` that differ are set in place
  /// and every other attribute stays. Without an element one is written after
  /// `<tableColumns>`; `null` removes the element.
  void setStyle(XlsxTableStyle? style) {
    final String source = _text();
    final _Places at = _Places(source);
    final int start = at.styleStart;
    if (style == null) {
      _reread(source.replaceRange(start, at.styleEnd, ''));
    } else if (start < 0) {
      final StringBuffer element = StringBuffer();
      writeTableStyle(XmlWriter(element), style, prefix: at.prefix);
      final int end = at.columnsEnd;
      _reread(source.replaceRange(end, end, element.toString()));
    } else {
      final XlsxTableStyle? old = this.style;
      String tag = source.substring(start, at.styleTagEnd);
      void flag(String attribute, bool Function(XlsxTableStyle s) of) {
        if (old != null && of(old) == of(style)) return;
        tag = _withAttribute(tag, attribute, of(style) ? '1' : '0');
      }

      if (old?.name != style.name) {
        tag = _withAttribute(tag, 'name', style.name);
      }
      flag('showFirstColumn', (XlsxTableStyle s) => s.showFirstColumn);
      flag('showLastColumn', (XlsxTableStyle s) => s.showLastColumn);
      flag('showRowStripes', (XlsxTableStyle s) => s.showRowStripes);
      flag('showColumnStripes', (XlsxTableStyle s) => s.showColumnStripes);
      _reread(source.replaceRange(start, at.styleTagEnd, tag));
    }
  }

  /// Makes [range] what the table covers, which the caller has checked: the
  /// `ref` of the table and, when it has one, of its `<autoFilter>` change
  /// (to the range less its totals row, when it was so before). A
  /// `<sortState>` and its conditions whose last row is the last body row
  /// follow it.
  void resize(XlsxRange range) {
    final String source = _text();
    final XlsxRange old = this.range;
    XlsxRange body(XlsxRange t) => XlsxRange(
      t.firstRow,
      t.firstColumn,
      t.lastRow - (totalsRow ? 1 : 0),
      t.lastColumn,
    );
    final int oldLast = body(old).lastRow;
    final int newLast = body(range).lastRow;
    final List<(int, int, String)> edits = <(int, int, String)>[];
    final XmlPullReader p = XmlPullReader(source, maxDepth: 0x7FFFFFFF);
    bool filterSeen = false;
    while (p.next()) {
      if (p.eventType != XmlEventType.startElement) continue;
      final String tag = p.sourceText(p.eventStart, p.eventEnd);
      if (p.depth == 1) {
        edits.add((
          p.eventStart,
          p.eventEnd,
          _withAttribute(tag, 'ref', range.ref),
        ));
        continue;
      }
      if (p.namespaceUri != Ns.main) continue;
      final XlsxRange? ref = _range(p.getAttribute('ref'));
      if (ref == null) continue;
      final String local = p.localName;
      if (p.depth == 2 && local == 'autoFilter' && !filterSeen) {
        filterSeen = true;
        final XlsxRange to = ref == body(old) ? body(range) : range;
        edits.add((
          p.eventStart,
          p.eventEnd,
          _withAttribute(tag, 'ref', to.ref),
        ));
      } else if ((local == 'sortState' || local == 'sortCondition') &&
          ref.lastRow == oldLast &&
          p.depth <= 4) {
        final XlsxRange to = XlsxRange(
          ref.firstRow,
          ref.firstColumn,
          newLast,
          ref.lastColumn,
        );
        edits.add((
          p.eventStart,
          p.eventEnd,
          _withAttribute(tag, 'ref', to.ref),
        ));
      }
    }
    final StringBuffer out = StringBuffer();
    int at = 0;
    for (final (int start, int end, String text) in edits) {
      out
        ..write(source.substring(at, start))
        ..write(text);
      at = end;
    }
    out.write(source.substring(at));
    _reread(out.toString());
  }

  /// The cells the table covers after [edit], a row or column edit of its
  /// sheet, or `null` when the edit deletes every row or column of it (the
  /// table goes). Excel's rules (W5 Ruling 5): rows inserted inside grow it,
  /// rows inserted right below it do not; deleting every body row keeps one
  /// empty body row. Throws a [StateError], as Excel refuses, for deleting
  /// the header row while body rows stay, and (not ruled yet) for deleting
  /// the totals row, or every body row of a table with one, while the rest
  /// stays.
  XlsxRange? shiftedRange(ReferenceShift edit) {
    final XlsxRange old = range;
    final XlsxRange? moved = edit.shiftRange(old);
    if (moved == null || edit.axis != ShiftAxis.rows || edit.count > 0) {
      return moved;
    }
    final int first = edit.index - 1;
    final int last = first - edit.count - 1;
    bool deleted(int row) => row >= first && row <= last;
    if (hasHeader && deleted(old.firstRow)) {
      throw StateError(
        'The header row of the table "$displayName" cannot be deleted while '
        'its other rows stay.',
      );
    }
    final int bodyFirst = old.firstRow + (hasHeader ? 1 : 0);
    final int bodyLast = old.lastRow - (totalsRow ? 1 : 0);
    final bool everyBodyRow = first <= bodyFirst && last >= bodyLast;
    if (totalsRow && (deleted(old.lastRow) || everyBodyRow)) {
      throw StateError(
        'The totals row or every body row of the table "$displayName" cannot '
        'be deleted while the rest of it stays.',
      );
    }
    final int least = (hasHeader ? 1 : 0) + 1;
    if (moved.rowCount >= least) return moved;
    return XlsxRange(
      moved.firstRow,
      moved.firstColumn,
      moved.firstRow + least - 1,
      moved.lastColumn,
    );
  }

  /// The part's text with [to] (from [shiftedRange]) as the table's range
  /// after [edit], or with only its formulas rewritten when [edit] is
  /// `null` (an edit of another sheet, a rename or a move); `null` when
  /// nothing changes. The `ref` of the table and of its `<autoFilter>`
  /// change; a column edit drops the `<tableColumn>` of each deleted column
  /// and adds one, named `Column1` and on as Excel names them, for each
  /// inserted inside, renumbering `count` and each `<filterColumn>`'s
  /// `colId` (dropping a deleted column's); a `<sortState>` and its
  /// conditions shift, one wholly deleted going. Every
  /// `calculatedColumnFormula` and `totalsRowFormula` goes through
  /// [rewrite], which gets the formula decoded, the index of its column
  /// (0 is the first) and whether it is the totals row's, and returns `null`
  /// for no change. Every other character stays as written.
  String? shiftedText(
    ReferenceShift? edit,
    XlsxRange? to,
    String? Function(String formula, int column, {required bool totals})
    rewrite,
  ) {
    final String source = _text();
    final XlsxRange old = range;
    final XlsxRange next = to ?? old;
    final bool columnEdit = edit != null && edit.axis == ShiftAxis.columns;
    final List<(int, int, String)> edits = <(int, int, String)>[];
    // The columns inserted before old column `insertAt`, for a column edit.
    int insertAt = -1;
    int inserted = 0;
    if (columnEdit && edit.count > 0) {
      inserted = next.columnCount - old.columnCount;
      insertAt = edit.index - 1 - old.firstColumn;
    }
    bool columnDeleted(int i) {
      if (!columnEdit || edit.count > 0) return false;
      final int column = old.firstColumn + i;
      return column >= edit.index - 1 && column < edit.index - 1 - edit.count;
    }

    final Set<String> names = <String>{
      for (final _Column c in _columns) c.name.toLowerCase(),
    };
    int maxId = 0;
    int nameNumber = 0;
    String newColumns(String prefix) {
      final StringBuffer out = StringBuffer();
      for (int k = 0; k < inserted; k++) {
        String name;
        do {
          name = 'Column${++nameNumber}';
        } while (names.contains(name.toLowerCase()));
        names.add(name.toLowerCase());
        out.write(
          '<${prefix}tableColumn id="${++maxId}" '
          'name="${escapeXmlAttribute(escapeXstring(name))}"/>',
        );
      }
      return out.toString();
    }

    final XmlPullReader r = XmlPullReader(source, maxDepth: 0x7FFFFFFF);
    // First pass: the highest column id.
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement &&
          r.depth == 3 &&
          r.localName == 'tableColumn' &&
          r.namespaceUri == Ns.main) {
        final int? id = int.tryParse(r.getAttribute('id')?.trim() ?? '');
        if (id != null && id > maxId) maxId = id;
      }
    }
    final XmlPullReader p = XmlPullReader(source, maxDepth: 0x7FFFFFFF);
    bool inFilter = false;
    bool inColumns = false;
    bool filterSeen = false;
    int columnsSeen = 0;
    int column = -1;
    XlsxRange? filter;
    XlsxRange? filterTo;
    String tag() => p.sourceText(p.eventStart, p.eventEnd);
    void setRef(XlsxRange value) => edits.add((
      p.eventStart,
      p.eventEnd,
      _withAttribute(tag(), 'ref', value.ref),
    ));
    void dropElement() {
      final int start = p.eventStart;
      final int tagEnd = p.eventEnd;
      final bool empty = p.isEmptyElement;
      p.skip();
      edits.add((start, empty ? tagEnd : p.eventEnd, ''));
    }

    while (p.next()) {
      final XmlEventType type = p.eventType;
      if (type == XmlEventType.endElement &&
          p.depth == 1 &&
          p.localName == 'tableColumns' &&
          inColumns &&
          inserted > 0 &&
          insertAt >= column + 1) {
        final String name = p.qualifiedName;
        final String prefix = name.substring(
          0,
          name.length - p.localName.length,
        );
        edits.add((p.eventStart, p.eventStart, newColumns(prefix)));
        inserted = 0;
      }
      if (type != XmlEventType.startElement) continue;
      final bool main = p.namespaceUri == Ns.main;
      final int depth = p.depth;
      if (depth == 1) {
        if (next != old) setRef(next);
        continue;
      }
      if (depth == 2) {
        inFilter = false;
        inColumns = false;
        if (!main) continue;
        switch (p.localName) {
          case 'autoFilter' when !filterSeen:
            filterSeen = true;
            inFilter = true;
            filter = _range(p.getAttribute('ref'));
            if (filter != null && edit != null) {
              filterTo = _filterAfter(filter, old, next, edit);
              if (filterTo != null && filterTo != filter) setRef(filterTo);
            }
          case 'sortState' when edit != null:
            _shiftSort(p, edit, edits, dropElement);
          case 'tableColumns':
            inColumns = ++columnsSeen == 1;
            if (inColumns && next.columnCount != old.columnCount) {
              edits.add((
                p.eventStart,
                p.eventEnd,
                _withAttribute(tag(), 'count', '${next.columnCount}'),
              ));
            }
        }
        continue;
      }
      if (!main) continue;
      if (inFilter && depth == 3 && edit != null) {
        if (p.localName == 'sortState') {
          _shiftSort(p, edit, edits, dropElement);
        } else if (p.localName == 'filterColumn' &&
            columnEdit &&
            filter != null &&
            filterTo != null) {
          final int? id = int.tryParse(p.getAttribute('colId')?.trim() ?? '');
          if (id == null) continue;
          final ({int row, int column})? cell = edit.shiftCell(
            filter.firstRow,
            filter.firstColumn + id,
          );
          if (cell == null) {
            dropElement();
          } else if (cell.column - filterTo.firstColumn != id) {
            edits.add((
              p.eventStart,
              p.eventEnd,
              _withAttribute(
                tag(),
                'colId',
                '${cell.column - filterTo.firstColumn}',
              ),
            ));
          }
        }
        continue;
      }
      if (inColumns && depth == 3 && p.localName == 'tableColumn') {
        column++;
        if (inserted > 0 && insertAt == column) {
          final String name = p.qualifiedName;
          final String prefix = name.substring(
            0,
            name.length - p.localName.length,
          );
          edits.add((p.eventStart, p.eventStart, newColumns(prefix)));
          inserted = 0;
        }
        if (columnDeleted(column)) dropElement();
        continue;
      }
      if (inColumns &&
          depth == 4 &&
          (p.localName == 'calculatedColumnFormula' ||
              p.localName == 'totalsRowFormula') &&
          !p.isEmptyElement) {
        final bool totals = p.localName == 'totalsRowFormula';
        final int index = column;
        final int start = p.eventEnd;
        final StringBuffer text = StringBuffer();
        bool nested = false;
        while (p.next()) {
          if (p.eventType == XmlEventType.endElement && p.depth < depth) {
            break;
          }
          if (p.eventType == XmlEventType.characters ||
              p.eventType == XmlEventType.cdata) {
            text.write(p.text);
          } else if (p.eventType == XmlEventType.startElement) {
            nested = true;
          }
        }
        if (nested) continue;
        final String? markup = rewrittenFormulaMarkup(
          text.toString(),
          (String f) => rewrite(f, index, totals: totals),
        );
        if (markup != null) edits.add((start, p.eventStart, markup));
      }
    }
    if (edits.isEmpty) return null;
    edits.sort(
      ((int, int, String) a, (int, int, String) b) => a.$1.compareTo(b.$1),
    );
    final StringBuffer out = StringBuffer();
    int at = 0;
    for (final (int start, int end, String text) in edits) {
      out
        ..write(source.substring(at, start))
        ..write(text);
      at = end;
    }
    out.write(source.substring(at));
    return out.toString();
  }

  /// The `<autoFilter>` range [filter] of a table over [old], now over
  /// [next], after [edit]: the table's range less its totals row when it
  /// was so before, else [filter] shifted.
  XlsxRange? _filterAfter(
    XlsxRange filter,
    XlsxRange old,
    XlsxRange next,
    ReferenceShift edit,
  ) {
    XlsxRange body(XlsxRange table) => XlsxRange(
      table.firstRow,
      table.firstColumn,
      table.lastRow - (totalsRow ? 1 : 0),
      table.lastColumn,
    );
    if (filter == body(old)) return body(next);
    return edit.shiftRange(filter);
  }

  /// Records in [edits] the shift of the `<sortState>` [p] is on: its `ref`
  /// and each `<sortCondition>`'s; a condition wholly deleted goes, and the
  /// state goes ([drop]) with its range or its last condition.
  static void _shiftSort(
    XmlPullReader p,
    ReferenceShift edit,
    List<(int, int, String)> edits,
    void Function() drop,
  ) {
    final XlsxRange? range = _range(p.getAttribute('ref'));
    if (range == null) return;
    final XlsxRange? moved = edit.shiftRange(range);
    if (moved == null) {
      drop();
      return;
    }
    final int mark = edits.length;
    final int start = p.eventStart;
    final String stateTag = p.sourceText(p.eventStart, p.eventEnd);
    if (moved != range) {
      edits.add((
        start,
        p.eventEnd,
        _withAttribute(stateTag, 'ref', moved.ref),
      ));
    }
    if (p.isEmptyElement) return;
    final int depth = p.depth;
    int conditions = 0;
    int kept = 0;
    while (p.next()) {
      if (p.eventType == XmlEventType.endElement && p.depth < depth) break;
      if (p.eventType != XmlEventType.startElement) continue;
      final bool condition =
          p.depth == depth + 1 &&
          p.localName == 'sortCondition' &&
          p.namespaceUri == Ns.main;
      if (!condition) {
        p.skip();
        continue;
      }
      conditions++;
      final XlsxRange? at = _range(p.getAttribute('ref'));
      final XlsxRange? to = at == null ? null : edit.shiftRange(at);
      final int cStart = p.eventStart;
      final int cTagEnd = p.eventEnd;
      final String cTag = p.sourceText(cStart, cTagEnd);
      final bool empty = p.isEmptyElement;
      p.skip();
      final int cEnd = empty ? cTagEnd : p.eventEnd;
      if (at != null && to == null) {
        edits.add((cStart, cEnd, ''));
        continue;
      }
      kept++;
      if (at != null && to != at) {
        edits.add((cStart, cTagEnd, _withAttribute(cTag, 'ref', to!.ref)));
      }
    }
    if (conditions > 0 && kept == 0) {
      edits
        ..removeRange(mark, edits.length)
        ..add((start, p.eventEnd, ''));
    }
  }

  /// Makes [source], text from [shiftedText], what the part holds.
  void replaceText(String source) => _reread(source);

  /// Makes [source], an edit of this part's text, what the part holds. The
  /// text was read under the file's depth limit, so none applies here.
  void _reread(String source) {
    final TablePart next = TablePart.read(
      XmlPullReader(source, maxDepth: 0x7FFFFFFF),
    )!;
    _state = next._state;
  }

  @override
  List<Uint8List> encode() => <Uint8List>[utf8.encode(_text())];

  /// The part's text, with the changed column names spliced in.
  String _text() {
    final String source = _state._source;
    if (!_columns.any((_Column c) => c.changed)) return source;
    final StringBuffer out = StringBuffer();
    int at = 0;
    for (final _Column c in _columns) {
      if (!c.changed) continue;
      final String value = '"${escapeXmlAttribute(escapeXstring(c.name))}"';
      if (c.start < 0) {
        out
          ..write(source.substring(at, c.insertAt))
          ..write(' name=')
          ..write(value);
        at = c.insertAt;
      } else {
        out
          ..write(source.substring(at, c.start))
          ..write(value);
        at = c.end;
      }
    }
    out.write(source.substring(at));
    return out.toString();
  }
}

/// Where the elements of a table part's text are, as [TablePart.read] takes
/// them: the first of each. A start of -1 is an element the text lacks.
final class _Places {
  _Places(String source) {
    final XmlPullReader r = XmlPullReader(source, maxDepth: 0x7FFFFFFF);
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.depth == 1) {
        rootStart = r.eventStart;
        rootTagEnd = r.eventEnd;
        final String name = r.qualifiedName;
        prefix = name.substring(0, name.length - r.localName.length);
      } else if (r.depth == 2 && r.namespaceUri == Ns.main) {
        final int start = r.eventStart;
        final int tagEnd = r.eventEnd;
        final bool empty = r.isEmptyElement;
        final String localName = r.localName;
        r.skip();
        final int end = empty ? tagEnd : r.eventEnd;
        if (localName == 'autoFilter' && filterStart < 0) {
          filterStart = start;
          filterTagEnd = tagEnd;
        } else if (localName == 'tableStyleInfo' && styleStart < 0) {
          styleStart = start;
          styleTagEnd = tagEnd;
          styleEnd = end;
        } else if (localName == 'tableColumns' && columnsEnd < 0) {
          columnsEnd = end;
        }
      }
    }
  }

  int rootStart = -1;
  int rootTagEnd = -1;

  /// The prefix of the root's name, with its colon, or empty.
  String prefix = '';

  int filterStart = -1;
  int filterTagEnd = -1;
  int styleStart = -1;
  int styleTagEnd = -1;
  int styleEnd = -1;

  /// The end of the first `<tableColumns>`, end tag included.
  int columnsEnd = -1;
}

/// An attribute of a start tag: its name and its quoted value.
final RegExp _attribute = RegExp(r'''\s([^\s=/>]+)\s*=\s*("[^"]*"|'[^']*')''');

/// The start tag [tag] with the attribute [name] set to [value]: in place, or
/// added last.
String _withAttribute(String tag, String name, String value) {
  final String quoted = '"${escapeXmlAttribute(value)}"';
  for (final RegExpMatch m in _attribute.allMatches(tag)) {
    if (m[1] == name) {
      return tag.replaceRange(m.end - m[2]!.length, m.end, quoted);
    }
  }
  final int close = tag.length - (tag.endsWith('/>') ? 2 : 1);
  return tag.replaceRange(close, close, ' $name=$quoted');
}

_Column _column(XmlPullReader r, List<String> problems) {
  final String name = decodeXstring(r.getAttribute('name') ?? '');
  final XlsxTotalsFunction function = _function(
    r.getAttribute('totalsRowFunction'),
    problems,
  );
  final String? rawLabel = r.getAttribute('totalsRowLabel');
  final String? label = rawLabel == null ? null : decodeXstring(rawLabel);
  final int tagStart = r.eventStart;
  final String tag = r.sourceText(tagStart, r.eventEnd);
  final int insertAt = tagStart + 1 + r.qualifiedName.length;
  for (final RegExpMatch m in _attribute.allMatches(tag)) {
    if (m[1] == 'name') {
      // The quoted value ends the match.
      final int end = tagStart + m.end;
      return _Column(name, end - m[2]!.length, end, insertAt, function, label);
    }
  }
  return _Column(name, -1, -1, insertAt, function, label);
}

/// The function named [value], [XlsxTotalsFunction.none] when it is absent;
/// one no schema value names reads `none` and adds `table` to [problems].
XlsxTotalsFunction _function(String? value, List<String> problems) {
  if (value == null) return XlsxTotalsFunction.none;
  for (final XlsxTotalsFunction f in XlsxTotalsFunction.values) {
    if (totalsFunctionXml(f) == value.trim()) return f;
  }
  if (!problems.contains('table')) problems.add('table');
  return XlsxTotalsFunction.none;
}

/// The style of the `<tableStyleInfo>` [r] is positioned at, or `null` when
/// it names none.
XlsxTableStyle? _style(XmlPullReader r) {
  final String? name = r.getAttribute('name');
  if (name == null) return null;
  bool flag(String attribute) {
    final String? v = r.getAttribute(attribute)?.trim();
    return v == '1' || v == 'true';
  }

  return XlsxTableStyle(
    name,
    showFirstColumn: flag('showFirstColumn'),
    showLastColumn: flag('showLastColumn'),
    showRowStripes: flag('showRowStripes'),
    showColumnStripes: flag('showColumnStripes'),
  );
}

XlsxRange? _range(String? ref) {
  if (ref == null) return null;
  try {
    return XlsxRange.parse(ref.trim());
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}
