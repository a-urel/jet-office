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
import '../range.dart';
import '../table.dart';

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
  );

  final String _source;
  final List<_Column> _columns;
  final XlsxRange _range;
  final XlsxRange? _filter;
  final XlsxTableStyle? _style;
}

/// A table part whose column names, style and last row can be changed.
final class TablePart implements PartContent {
  TablePart._(
    this._state,
    this.displayName,
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
      ),
      displayName!,
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
  final String displayName;

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
    );
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
  /// `ref` of the table and, when it has one, of its `<autoFilter>` change.
  void resize(XlsxRange range) {
    String source = _text();
    final _Places at = _Places(source);
    final int filter = at.filterStart;
    if (filter >= 0) {
      final String tag = source.substring(filter, at.filterTagEnd);
      if (_attribute.allMatches(tag).any((RegExpMatch m) => m[1] == 'ref')) {
        source = source.replaceRange(
          filter,
          at.filterTagEnd,
          _withAttribute(tag, 'ref', range.ref),
        );
      }
    }
    final String root = source.substring(at.rootStart, at.rootTagEnd);
    _reread(
      source.replaceRange(
        at.rootStart,
        at.rootTagEnd,
        _withAttribute(root, 'ref', range.ref),
      ),
    );
  }

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
