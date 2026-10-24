/// The column value type.
///
/// New in jet_office; Quds' `colWidth` takes a width and a span and nothing
/// else. Here a column is a value carrying its width, style, visibility and
/// outline level.
library;

import '../xml/xml_number.dart';
import 'style.dart';

/// How one worksheet column looks: its width, its style, whether it is
/// hidden, and its outline (grouping) level.
///
/// Passed to `XlsxSheetWriter.columns`. Values are compared by their
/// contents. The `const` constructor cannot check its fields; the writer
/// checks them when the columns are set and throws [ArgumentError] naming
/// the field.
final class XlsxColumn {
  /// Creates a column description.
  ///
  /// [width] is in characters of the default font, from 0 to 255; `null`
  /// keeps the sheet's default width. [style] is the bottom layer of the
  /// style of every cell in the column, beneath the row's and the cell's
  /// own (see `XlsxStyle.merge`), and formats the column's empty cells.
  /// [outlineLevel] groups the column, from 0 (not grouped) to 7.
  /// [collapsed] marks the column that carries the expand button of a
  /// collapsed group next to it.
  const XlsxColumn({
    this.width,
    this.style,
    this.hidden = false,
    this.outlineLevel = 0,
    this.collapsed = false,
  });

  /// The width in characters of the default font, or `null` for the sheet's
  /// default column width.
  final double? width;

  /// The style of the column's cells, or `null` for none.
  final XlsxStyle? style;

  /// Whether the column is hidden.
  final bool hidden;

  /// The outline (grouping) level: 0 is not grouped, 7 the deepest level.
  final int outlineLevel;

  /// Whether the column carries the button of a collapsed group.
  final bool collapsed;

  @override
  bool operator ==(Object other) =>
      other is XlsxColumn &&
      other.width == width &&
      other.style == style &&
      other.hidden == hidden &&
      other.outlineLevel == outlineLevel &&
      other.collapsed == collapsed;

  @override
  int get hashCode =>
      Object.hash(width, style, hidden, outlineLevel, collapsed);

  @override
  String toString() {
    final List<String> fields = <String>[
      if (width case final double w) 'width: ${describeDouble(w)}',
      if (style != null) 'style: $style',
      if (hidden) 'hidden: true',
      if (outlineLevel != 0) 'outlineLevel: $outlineLevel',
      if (collapsed) 'collapsed: true',
    ];
    return 'XlsxColumn(${fields.join(', ')})';
  }
}
