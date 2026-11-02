/// A table part (`xl/tables/tableN.xml`) with its column names typed and
/// everything else kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// Excel requires the text of a table's header cell to equal its column's
/// `name`, and repairs the table when they differ, so setting a header cell
/// renames the column (decision 0009 does not let the model leave content it
/// does not type wrong). W1 types only what that needs: the table's
/// `displayName`, `ref` and `headerRowCount`, and each `<tableColumn>`'s
/// `name`. The part is written as its source text with each changed name
/// spliced in at its position, so every other character stays as written;
/// tables are typed fully in W3.
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

/// One `<tableColumn>`: its decoded name and where its `name` attribute sits.
final class _Column {
  _Column(this.name, this.start, this.end, this.insertAt);

  String name;

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
  );

  /// Reads the table part [r] is positioned before, or returns `null` when
  /// the model cannot type it: the root is not a SpreadsheetML `<table>`, its
  /// `ref` is not a range, or `<tableColumns>` does not list one column per
  /// column of the range. A part that is `null` here is left unchanged.
  ///
  /// XML errors are thrown by [r] as it reads.
  static TablePart? read(XmlPullReader r) {
    String? displayName;
    XlsxRange? range;
    bool hasHeader = true;
    final List<_Column> columns = <_Column>[];
    // Only the first <tableColumns> is typed; a repeated one stays as text.
    int columnsSeen = 0;
    bool inColumns = false;
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.depth == 1) {
        if (r.localName != 'table' || r.namespaceUri != Ns.main) return null;
        displayName =
            r.getAttribute('displayName') ?? r.getAttribute('name') ?? '';
        range = _range(r.getAttribute('ref'));
        hasHeader = r.getAttribute('headerRowCount')?.trim() != '0';
      } else if (r.depth == 2) {
        inColumns =
            r.localName == 'tableColumns' &&
            r.namespaceUri == Ns.main &&
            ++columnsSeen == 1;
      } else if (inColumns &&
          r.depth == 3 &&
          r.localName == 'tableColumn' &&
          r.namespaceUri == Ns.main) {
        columns.add(_column(r));
      }
    }
    if (range == null || columns.length != range.columnCount) return null;
    return TablePart._(
      r.sourceText(0, r.sourceLength),
      displayName!,
      range,
      hasHeader,
      columns,
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

_Column _column(XmlPullReader r) {
  final String name = decodeXstring(r.getAttribute('name') ?? '');
  final int tagStart = r.eventStart;
  final String tag = r.sourceText(tagStart, r.eventEnd);
  final int insertAt = tagStart + 1 + r.qualifiedName.length;
  for (final RegExpMatch m in _attribute.allMatches(tag)) {
    if (m[1] == 'name') {
      // The quoted value ends the match.
      final int end = tagStart + m.end;
      return _Column(name, end - m[2]!.length, end, insertAt);
    }
  }
  return _Column(name, -1, -1, insertAt);
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
