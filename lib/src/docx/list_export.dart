/// The list export helper: [DocxListExport] writes rows under a header, with
/// an optional caption above, as a table that repeats its header row on every
/// page, under a page header and footer.
///
/// New in jet_office; quds_office_engine has no list export. Not ported from
/// Quds. The helper is a composition of the public document model's calls and
/// writes no XML of its own. This file holds the columns, the export's value
/// and its argument checks; the writing is added in later steps of D6.
library;

import 'package:jet_core/jet_core.dart';

import '../common/image.dart';
import '../common/name_key.dart';
import '../common/properties.dart';
import 'docx_document.dart';
import 'model/blocks.dart';
import 'model/formatting.dart';
import 'model/section_formatting.dart';
import 'model/table_properties.dart';

/// [value] as text that reads the same on every platform: a whole number
/// keeps its `.0`, which JavaScript's number printing drops.
String _describe(double? value) =>
    value != null &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value.abs() < 1e15
    ? '${value.toInt()}.0'
    : '$value';

/// One column of a [DocxListExport]: its header text, width, number format
/// and alignment.
///
/// The `const` constructor checks nothing; `DocxListExport.writeTo` does and
/// throws [ArgumentError] naming the field.
final class DocxListColumn {
  /// A column headed [header], [widthPt] points wide, whose numbers and dates
  /// show with [numberFormat] and whose cells are aligned [alignment].
  const DocxListColumn(
    this.header, {
    this.widthPt,
    this.numberFormat,
    this.alignment,
  });

  /// The text of the column's header cell: not empty, and unique in its list
  /// ignoring case.
  final String header;

  /// The width in points, finite and greater than 0; `null` for a share of
  /// what the other columns leave of the text width. Nothing is measured: a
  /// pure-Dart library has no font metrics.
  final double? widthPt;

  /// An Excel number format code, such as `#,##0.00` or `dd.mm.yyyy`, for
  /// the numbers, dates, durations and booleans of the column; `null` for
  /// `General` (a date without a code shows as the locale's short date). A
  /// code the formatter cannot read is refused.
  final String? numberFormat;

  /// The alignment of the column's cells, header and totals included;
  /// `null` for right for a column with a [numberFormat] and the paragraph
  /// default otherwise.
  final DocxAlignment? alignment;

  @override
  bool operator ==(Object other) =>
      other is DocxListColumn &&
      other.header == header &&
      other.widthPt == widthPt &&
      other.numberFormat == numberFormat &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(header, widthPt, numberFormat, alignment);

  @override
  String toString() =>
      'DocxListColumn($header, widthPt: ${_describe(widthPt)}, '
      'numberFormat: $numberFormat, alignment: $alignment)';
}

/// A list of rows under a header, written into a document by [writeTo] or as
/// a document of its own by [toDocx].
///
/// The list is a table with one [DocxListColumn.header] per column, the data
/// rows below it, and a totals row when the caller gives one. The header
/// repeats on every page. The page has a header (the [logo], the [title] and
/// the [date]) and a footer with the page number; the [caption] stands above
/// the table.
///
/// The constructor checks nothing; [writeTo] and [toDocx] do, and throw
/// [ArgumentError] naming the field, before the document changes.
///
/// ```dart
/// final DocxResult out = DocxListExport(
///   const <DocxListColumn>[
///     DocxListColumn('Code', widthPt: 80),
///     DocxListColumn('Amount', numberFormat: '#,##0.00'),
///   ],
///   title: 'Accounts',
///   date: DateTime(2026, 11, 8),
/// ).toDocx(<List<Object?>>[
///   <Object?>['A-1', 1234.5],
///   <Object?>['A-2', 99.5],
/// ]);
/// ```
final class DocxListExport {
  /// A list of [columns]. The remaining fields default as they are
  /// described. The constructor checks nothing; [writeTo] does.
  DocxListExport(
    List<DocxListColumn> columns, {
    this.title,
    this.logo,
    this.logoHeightPt = 28,
    this.date,
    this.dateFormat,
    this.caption,
    this.pageSize,
    this.margins,
    this.footerBefore = 'Page ',
    this.footerMiddle = ' of ',
    this.footerAfter = '',
    this.locale = FormatLocale.enUS,
    this.headerShading = 'D9D9D9',
  }) : columns = List<DocxListColumn>.unmodifiable(columns);

  /// The columns, left to right; at least one and at most
  /// [maxTableColumns]. Unmodifiable.
  final List<DocxListColumn> columns;

  /// The report's name, centred and bold in the page header; `null` for
  /// none.
  final String? title;

  /// The picture at the left of the page header; `null` for none.
  final OfficeImage? logo;

  /// The height of the [logo] in points, finite and greater than 0; the
  /// width follows the picture's proportions.
  final double logoHeightPt;

  /// The report's date, shown at the right of the page header as fixed text
  /// (not a `DATE` field, which would show the day the file is opened);
  /// `null` for none.
  final DateTime? date;

  /// The Excel date code of the [date]; `null` for the [locale]'s short
  /// date.
  final String? dateFormat;

  /// The text above the table; `null` for none.
  final String? caption;

  /// The page size of the section the list is written to; `null` for A4
  /// portrait.
  final DocxPageSize? pageSize;

  /// The margins of that section; `null` for Word's blank-document margins
  /// (2.5 cm, header and footer 1.25 cm).
  final DocxPageMargins? margins;

  /// The text before the page number in the footer.
  final String footerBefore;

  /// The text between the page number and the number of pages.
  final String footerMiddle;

  /// The text after the number of pages.
  final String footerAfter;

  /// The locale that formats the numbers and dates.
  final FormatLocale locale;

  /// The fill of the header row as RGB hex of six digits, in either case;
  /// `null` for none.
  final String? headerShading;

  /// Writes the list into [document], one data row per entry of [rows] and
  /// [totals] as a last row when given.
  ///
  /// Until the page, header, footer and look are added in later steps of D6,
  /// the list is a plain table appended to the end of the body: a header row
  /// that repeats, the data rows and the totals row, each cell holding the
  /// value as Excel shows it. A `String` is written as given, `null` as an
  /// empty cell, and a `num`, [FormatDecimal], `DateTime`, `Duration` or
  /// `bool` through [NumberFormatter] with the column's
  /// [DocxListColumn.numberFormat] and [locale] (`General` without a code, and
  /// the locale's short date for a `DateTime` without one).
  ///
  /// Throws [ArgumentError], before [document] changes, for no columns or
  /// more than [maxTableColumns] (named `columns`), an empty header or one
  /// that repeats an earlier header ignoring case (`columns[i].header`), a
  /// width that is not finite or not greater than 0 (`columns[i].widthPt`),
  /// a number format that cannot be read (`columns[i].numberFormat`), a
  /// [logoHeightPt] that is not finite or not greater than 0
  /// (`logoHeightPt`), a [headerShading] that is not six hex digits
  /// (`headerShading`), [totals] longer than [columns] (`totals`) and a
  /// [totals] value of an unsupported type (`totals[j]`). A row longer than
  /// [columns] throws [ArgumentError] named `rows[i]`, `i` counting from 0,
  /// and a value of an unsupported type named `rows[i][j]`, each before that
  /// row is written. [rows] is read once, so the rows before it stay written.
  void writeTo(
    DocxDocument document,
    Iterable<List<Object?>> rows, {
    List<Object?>? totals,
  }) {
    _check();
    final NumberFormatter formatter = NumberFormatter(locale: locale);
    List<String>? totalsTexts;
    if (totals != null) {
      if (totals.length > columns.length) {
        throw ArgumentError.value(
          totals.length,
          'totals',
          'The totals have more values than the ${columns.length} columns.',
        );
      }
      totalsTexts = <String>[
        for (int j = 0; j < totals.length; j++)
          _cellText(formatter, totals[j], columns[j], 'totals[$j]'),
      ];
    }
    final DocxTable table = document.body.addTable(columns: columns.length);
    table.addRow(<String>[
      for (final DocxListColumn c in columns) c.header,
    ], header: true);
    int index = 0;
    for (final List<Object?> row in rows) {
      if (row.length > columns.length) {
        throw ArgumentError.value(
          row.length,
          'rows[$index]',
          'The row has more values than the ${columns.length} columns.',
        );
      }
      table.addRow(<String>[
        for (int j = 0; j < row.length; j++)
          _cellText(formatter, row[j], columns[j], 'rows[$index][$j]'),
      ]);
      index++;
    }
    if (totalsTexts != null) table.addRow(totalsTexts);
  }

  /// A document of its own holding the list, with the document properties
  /// [properties]; see [writeTo] for the layout and the errors.
  DocxResult toDocx(
    Iterable<List<Object?>> rows, {
    List<Object?>? totals,
    OfficeProperties properties = const OfficeProperties(),
  }) {
    final DocxDocument document = DocxDocument();
    writeTo(document, rows, totals: totals);
    document.properties = properties;
    return document.save();
  }

  @override
  bool operator ==(Object other) {
    if (other is! DocxListExport ||
        other.title != title ||
        other.logo != logo ||
        other.logoHeightPt != logoHeightPt ||
        other.date != date ||
        other.dateFormat != dateFormat ||
        other.caption != caption ||
        other.pageSize != pageSize ||
        other.margins != margins ||
        other.footerBefore != footerBefore ||
        other.footerMiddle != footerMiddle ||
        other.footerAfter != footerAfter ||
        other.locale != locale ||
        other.headerShading != headerShading ||
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
    title,
    logo,
    logoHeightPt,
    date,
    dateFormat,
    caption,
    pageSize,
    margins,
    footerBefore,
    footerMiddle,
    footerAfter,
    locale,
    headerShading,
  );

  @override
  String toString() =>
      'DocxListExport($columns, title: $title, logo: $logo, '
      'logoHeightPt: ${_describe(logoHeightPt)}, date: $date, '
      'dateFormat: $dateFormat, caption: $caption, pageSize: $pageSize, margins: $margins, '
      'footerBefore: $footerBefore, footerMiddle: $footerMiddle, '
      'footerAfter: $footerAfter, locale: $locale, '
      'headerShading: $headerShading)';

  /// [value] as the text of a cell of [column], as Excel shows it; [name] is
  /// `rows[i][j]` or `totals[j]` for the error of an unsupported type.
  static String _cellText(
    NumberFormatter formatter,
    Object? value,
    DocxListColumn column,
    String name,
  ) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is DateTime && column.numberFormat == null) {
      return formatter.format(value, numberFormatId: 14).text;
    }
    if (value is num ||
        value is FormatDecimal ||
        value is DateTime ||
        value is Duration ||
        value is bool) {
      return formatter.format(value, numberFormat: column.numberFormat).text;
    }
    throw ArgumentError.value(
      value,
      name,
      'A cell takes a String, num, FormatDecimal, DateTime, Duration, bool '
      'or null.',
    );
  }

  static final RegExp _hex6 = RegExp(r'^[0-9A-Fa-f]{6}$');

  /// Throws [ArgumentError] naming the field unless the arguments can make a
  /// list.
  void _check() {
    if (columns.isEmpty) {
      throw ArgumentError.value(
        columns,
        'columns',
        'A list needs at least one column.',
      );
    }
    if (columns.length > maxTableColumns) {
      throw ArgumentError.value(
        columns.length,
        'columns',
        'A table has at most $maxTableColumns columns.',
      );
    }
    final Map<String, String> seen = <String, String>{};
    final NumberFormatter formatter = NumberFormatter(locale: locale);
    for (int i = 0; i < columns.length; i++) {
      final DocxListColumn c = columns[i];
      if (c.header.isEmpty) {
        throw ArgumentError.value(
          c.header,
          'columns[$i].header',
          'A header must not be empty.',
        );
      }
      final String key = officeNameKey(c.header);
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
      final double? width = c.widthPt;
      if (width != null && (!width.isFinite || width <= 0)) {
        throw ArgumentError.value(
          width,
          'columns[$i].widthPt',
          'A width must be finite and greater than 0.',
        );
      }
      final String? code = c.numberFormat;
      if (code != null &&
          formatter.format(0, numberFormat: code).warning ==
              FormatWarning.invalidCode) {
        throw ArgumentError.value(
          code,
          'columns[$i].numberFormat',
          'The number format cannot be read.',
        );
      }
    }
    if (!logoHeightPt.isFinite || logoHeightPt <= 0) {
      throw ArgumentError.value(
        logoHeightPt,
        'logoHeightPt',
        'The logo height must be finite and greater than 0.',
      );
    }
    final String? shading = headerShading;
    if (shading != null && !_hex6.hasMatch(shading)) {
      throw ArgumentError.value(
        shading,
        'headerShading',
        'The shading must be six hex digits, such as D9D9D9, or null.',
      );
    }
  }
}
