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

  String name;

  /// The totals row's function, [XlsxTotalsFunction.none] for none or an
  /// unknown one.
  final XlsxTotalsFunction function;

  /// The decoded `totalsRowLabel`, or `null`.
  final String? label;

  /// The decoded `<totalsRowFormula>`, or `null`; set while reading.
  String? formula;

  /// Whether [name] differs from the source, so it is spliced in.
  bool changed = false;

  /// The source offsets of the `name` attribute's quoted value, quotes
  /// included; `-1` when the element has no `name`.
  final int start;
  final int end;

  /// Where a missing `name` attribute is inserted: just after the element
  /// name.
  final int insertAt;
}

/// A table part whose column names can be changed.
final class TablePart implements PartContent {
  TablePart._(
    this._source,
    this.displayName,
    this.range,
    this.hasHeader,
    this._columns,
    this.id,
    this.totalsRow,
    this.autoFilterRange,
    this.hasSortState,
    this.style,
    this.problems,
  );

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
      r.sourceText(0, r.sourceLength),
      displayName!,
      range,
      hasHeader,
      columns,
      id,
      totalsRow,
      autoFilterRange,
      hasSortState,
      style,
      problems,
    );
  }

  final String _source;
  final List<_Column> _columns;

  /// The table's name in formulas.
  final String displayName;

  /// The cells the table covers, header and totals rows included.
  final XlsxRange range;

  /// Whether the first row of [range] is a header of column names.
  final bool hasHeader;

  /// The table's `id`, `0` when it has none or it is not a number.
  final int id;

  /// Whether the last row of [range] is a totals row (`totalsRowCount` over
  /// 0).
  final bool totalsRow;

  /// The `ref` of the table's `<autoFilter>`, or `null` for no filter or a
  /// `ref` that is not a range.
  final XlsxRange? autoFilterRange;

  /// Whether the table or its filter has a `<sortState>`, kept as written.
  final bool hasSortState;

  /// The look of the table, or `null` when it has no `<tableStyleInfo>` or
  /// the element names no style.
  final XlsxTableStyle? style;

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
    final _Column column = _columns[index];
    column.name = name;
    column.changed = true;
  }

  @override
  List<Uint8List> encode() {
    if (!_columns.any((_Column c) => c.changed)) {
      return <Uint8List>[utf8.encode(_source)];
    }
    final StringBuffer out = StringBuffer();
    int at = 0;
    for (final _Column c in _columns) {
      if (!c.changed) continue;
      final String value = '"${escapeXmlAttribute(escapeXstring(c.name))}"';
      if (c.start < 0) {
        out
          ..write(_source.substring(at, c.insertAt))
          ..write(' name=')
          ..write(value);
        at = c.insertAt;
      } else {
        out
          ..write(_source.substring(at, c.start))
          ..write(value);
        at = c.end;
      }
    }
    out.write(_source.substring(at));
    return <Uint8List>[utf8.encode(out.toString())];
  }
}

/// An attribute of a start tag: its name and its quoted value.
final RegExp _attribute = RegExp(r'''\s([^\s=/>]+)\s*=\s*("[^"]*"|'[^']*')''');

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
