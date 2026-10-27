/// The list export helper: [XlsxListExport] writes rows under a header, with
/// an optional caption above and an optional totals row below, as a
/// filtered list whose header stays in view and repeats on every printed
/// page.
///
/// New in jet_office; quds_office_engine has no list export. The helper is
/// a composition of public `XlsxSheetWriter` calls and writes no XML of its
/// own.
library;

import '../xml/xml_number.dart';
import 'cell_ref.dart';
import 'column.dart';
import 'font.dart';
import 'properties.dart';
import 'range.dart';
import 'sheet_name.dart';
import 'sheet_writer.dart';
import 'style.dart';
import 'table.dart';
import 'values.dart';
import 'xlsx_writer.dart';

/// One column of an [XlsxListExport]: its header text, width and style,
/// and what the totals row shows under it.
///
/// The `const` constructor checks nothing; `XlsxListExport.writeTo` does
/// and throws [ArgumentError] naming the field.
final class XlsxListColumn {
  /// A column headed [header], [width] characters wide, whose cells carry
  /// [style] and whose totals row shows [totals], or [totalsLabel] with
  /// [XlsxTotalsFunction.none].
  const XlsxListColumn(
    this.header, {
    this.width,
    this.style,
    this.totals = XlsxTotalsFunction.none,
    this.totalsLabel,
  });

  /// The text of the column's header cell: not empty, and unique in its
  /// list ignoring case.
  final String header;

  /// The width in characters of the default font, from 0 to 255, as
  /// `XlsxColumn.width`; `null` keeps the sheet's default width. Nothing is
  /// measured: a pure-Dart writer has no font metrics.
  final double? width;

  /// The style of the column's cells, such as its number format, beneath
  /// the header, caption and totals styles; `null` for none.
  final XlsxStyle? style;

  /// What the totals row shows under the column: a `SUBTOTAL` over the
  /// column's data rows, which skips rows a filter hides, or nothing for
  /// [XlsxTotalsFunction.none]. [XlsxTotalsFunction.custom] is refused.
  final XlsxTotalsFunction totals;

  /// The text the totals row shows under the column, only with
  /// [XlsxTotalsFunction.none]; `null` for none (see [XlsxListExport] for
  /// the default `Total`).
  final String? totalsLabel;

  @override
  bool operator ==(Object other) =>
      other is XlsxListColumn &&
      other.header == header &&
      other.width == width &&
      other.style == style &&
      other.totals == totals &&
      other.totalsLabel == totalsLabel;

  @override
  int get hashCode => Object.hash(header, width, style, totals, totalsLabel);

  @override
  String toString() {
    final double? w = width;
    return 'XlsxListColumn($header, '
        'width: ${w == null ? null : describeDouble(w)}, style: $style, '
        'totals: ${totals.name}, totalsLabel: $totalsLabel)';
  }
}

/// A list of rows under a header, written to a sheet by [writeTo] or as a
/// workbook of its own by [toXlsx].
///
/// The sheet gets, from row 1 down:
///
/// - the [caption], when there is one, in column A, not merged (a merged
///   caption would break sorting and selecting whole columns);
/// - the header row, one [XlsxListColumn.header] per column, frozen and
///   repeated on every printed page (print titles);
/// - the data rows, under an auto filter that covers the header and them.
///   A list without rows gets one empty data row, so the filter and every
///   `SUBTOTAL` have a valid range;
/// - the totals row, when a column has a function other than
///   [XlsxTotalsFunction.none] or a [XlsxListColumn.totalsLabel]. A column
///   with a function shows `SUBTOTAL(1xx, …)` over its data rows, with the
///   codes of [XlsxTable]'s totals row, so rows a filter hides are left
///   out; a column with a label shows the label. When no column has a label
///   and the first column has no function, the first column shows `Total`.
///
/// Column widths and styles come from the [columns]. The helper has no
/// logic of its own beyond this layout.
final class XlsxListExport {
  /// A list of [columns], with an optional [caption] above it. The styles
  /// default as their fields describe. The constructor checks nothing;
  /// [writeTo] does.
  XlsxListExport(
    List<XlsxListColumn> columns, {
    this.caption,
    this.captionStyle,
    this.headerStyle,
    this.totalsStyle,
  }) : columns = List<XlsxListColumn>.unmodifiable(columns);

  /// The columns, left to right from column A; at least one. Unmodifiable.
  final List<XlsxListColumn> columns;

  /// The text of the caption row above the header, or `null` for no
  /// caption: the header is then row 1.
  final String? caption;

  /// The style of the caption row, or `null` for bold 14 points.
  final XlsxStyle? captionStyle;

  /// The style of the header row, merged over each column's style, or
  /// `null` for bold.
  final XlsxStyle? headerStyle;

  /// The style of the totals row, merged over each column's style, or
  /// `null` for bold.
  final XlsxStyle? totalsStyle;

  static const XlsxStyle _bold = XlsxStyle(font: XlsxFont(bold: true));
  static const XlsxStyle _captionDefault = XlsxStyle(
    font: XlsxFont(bold: true, size: 14),
  );

  /// Whether the list has a totals row: a column has a function other than
  /// [XlsxTotalsFunction.none], or a label.
  bool get _hasTotals => columns.any(
    (XlsxListColumn c) =>
        c.totals != XlsxTotalsFunction.none || c.totalsLabel != null,
  );

  /// Writes the list to the empty [sheet], one data row per entry of
  /// [rows], and returns the range from the header row to the totals row,
  /// or to the last data row when the list has no totals row.
  ///
  /// An entry of [rows] holds the cell values of one row from column A on,
  /// as `XlsxSheetWriter.row` takes them; a row shorter than [columns]
  /// leaves the cells after it empty.
  ///
  /// Throws [ArgumentError], before any call reaches [sheet], for no
  /// columns (named `columns`), an empty header or one that repeats an
  /// earlier header ignoring case (`columns[i].header`),
  /// [XlsxTotalsFunction.custom] (`columns[i].totals`) and a label with a
  /// function (`columns[i].totalsLabel`); [StateError], before any call
  /// reaches [sheet], when [sheet] already has rows; and what the sheet's
  /// own calls throw, such as [ArgumentError] for a width out of range
  /// (`columns[i].width`) from `XlsxSheetWriter.columns`. A row longer
  /// than [columns] throws [ArgumentError] named `rows[i]`, `i` counting
  /// from 0, before that row is written. [rows] is read once, so the rows
  /// before it stay written, with the header settings.
  XlsxRange writeTo(XlsxSheetWriter sheet, Iterable<List<Object?>> rows) {
    _check();
    if (sheet.rowCount > 0) {
      throw StateError(
        'Sheet "${sheet.name}" already has rows; a list is written to a '
        'sheet without rows.',
      );
    }
    final int width = columns.length;
    final int headerRow = caption == null ? 0 : 1;
    sheet
      ..columns(<XlsxColumn?>[
        for (final XlsxListColumn c in columns)
          XlsxColumn(width: c.width, style: c.style),
      ])
      // Before the caption row: a header setting cannot follow a row.
      ..freeze(rows: headerRow + 1)
      ..printTitles(rows: (headerRow, headerRow));
    if (caption case final String text) {
      sheet.row(<Object?>[text], style: captionStyle ?? _captionDefault);
    }
    sheet.row(<Object?>[
      for (final XlsxListColumn c in columns) c.header,
    ], style: headerStyle ?? _bold);
    int index = 0;
    for (final List<Object?> values in rows) {
      if (values.length > width) {
        throw ArgumentError.value(
          values,
          'rows[$index]',
          'The row has ${values.length} values for $width columns.',
        );
      }
      sheet.row(values);
      index++;
    }
    if (index == 0) sheet.blankRow();
    final int lastData = sheet.rowCount - 1;
    int last = lastData;
    if (_hasTotals) {
      sheet.row(
        _totalsCells(headerRow + 1, lastData),
        style: totalsStyle ?? _bold,
      );
      last++;
    }
    sheet.autoFilter(XlsxRange(headerRow, 0, lastData, width - 1));
    return XlsxRange(headerRow, 0, last, width - 1);
  }

  /// A workbook of one sheet named [sheetName] holding the list, with the
  /// document properties [properties]; see [writeTo] for the layout.
  ///
  /// Throws like [writeTo], and like `XlsxWriter` for invalid
  /// [properties].
  XlsxResult toXlsx(
    Iterable<List<Object?>> rows, {
    String sheetName = 'List',
    XlsxProperties properties = const XlsxProperties(),
  }) {
    final XlsxWriter book = XlsxWriter(properties: properties);
    writeTo(book.addSheet(sheetName), rows);
    return book.close();
  }

  /// The cells of the totals row over the data rows [first] to [last],
  /// 0-based and inclusive.
  List<Object?> _totalsCells(int first, int last) {
    final bool anyLabel = columns.any(
      (XlsxListColumn c) => c.totalsLabel != null,
    );
    return <Object?>[
      for (int i = 0; i < columns.length; i++)
        if (subtotalCode(columns[i].totals) case final int code)
          // A range even over one row (`B2:B2`): it reads as a column total.
          XlsxFormula(
            'SUBTOTAL($code,${cellRef(first, i)}:${cellRef(last, i)})',
          )
        else if (columns[i].totalsLabel case final String label)
          label
        else if (i == 0 && !anyLabel)
          'Total'
        else
          null,
    ];
  }

  @override
  bool operator ==(Object other) {
    if (other is! XlsxListExport ||
        other.caption != caption ||
        other.captionStyle != captionStyle ||
        other.headerStyle != headerStyle ||
        other.totalsStyle != totalsStyle ||
        other.columns.length != columns.length) {
      return false;
    }
    for (int i = 0; i < columns.length; i++) {
      if (other.columns[i] != columns[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(columns),
    caption,
    captionStyle,
    headerStyle,
    totalsStyle,
  );

  @override
  String toString() =>
      'XlsxListExport($columns, caption: $caption, '
      'captionStyle: $captionStyle, headerStyle: $headerStyle, '
      'totalsStyle: $totalsStyle)';

  /// Throws [ArgumentError] naming the field unless the columns can make a
  /// list.
  void _check() {
    if (columns.isEmpty) {
      throw ArgumentError.value(
        columns,
        'columns',
        'A list needs at least one column.',
      );
    }
    final Map<String, String> seen = <String, String>{};
    for (int i = 0; i < columns.length; i++) {
      final XlsxListColumn c = columns[i];
      if (c.header.isEmpty) {
        throw ArgumentError.value(
          c.header,
          'columns[$i].header',
          'A header must not be empty.',
        );
      }
      final String key = sheetNameKey(c.header);
      final String? earlier = seen[key];
      if (earlier != null) {
        throw ArgumentError.value(
          c.header,
          'columns[$i].header',
          'The header "${c.header}" repeats "$earlier"; headers are '
              'compared ignoring case.',
        );
      }
      seen[key] = c.header;
      if (c.totals == XlsxTotalsFunction.custom) {
        throw ArgumentError.value(
          c.totals,
          'columns[$i].totals',
          'A list writes no formula of its own; custom totals are not '
              'supported.',
        );
      }
      if (c.totalsLabel != null && c.totals != XlsxTotalsFunction.none) {
        throw ArgumentError.value(
          c.totalsLabel,
          'columns[$i].totalsLabel',
          'A totals label goes only with XlsxTotalsFunction.none.',
        );
      }
    }
  }
}
