/// The row format value type.
///
/// New in jet_office; the writer's `row` and `blankRow` take these as
/// separate parameters, and an opened workbook reads and sets them as one
/// value.
library;

import '../xml/xml_number.dart';
import 'style.dart';

/// How one worksheet row looks: its height, its visibility, its outline
/// (grouping) level and its style.
///
/// Read with `XlsxSheet.rowFormat` and set with `XlsxSheet.setRowFormat`.
/// The fields mean what the writer's `row(...)` parameters mean. Values are
/// compared by their contents. The `const` constructor cannot check its
/// fields; `setRowFormat` checks them and throws [ArgumentError] naming the
/// field.
final class XlsxRowFormat {
  /// Creates a row format.
  ///
  /// [height] is in points, from 0 to 409.5; `null` keeps the sheet's
  /// default (automatic) height. [hidden] hides the row. [outlineLevel]
  /// groups the row, from 0 (not grouped) to 7. [collapsed] marks the row
  /// that carries the expand button of a collapsed group next to it.
  /// [style] is the style of the row's cells that have no cell of their
  /// own, and the layer under the style of the cells that do (see
  /// `XlsxStyle.merge`); `null` is none.
  const XlsxRowFormat({
    this.height,
    this.hidden = false,
    this.outlineLevel = 0,
    this.collapsed = false,
    this.style,
  });

  /// The height in points, or `null` for the sheet's default height.
  final double? height;

  /// Whether the row is hidden.
  final bool hidden;

  /// The outline (grouping) level: 0 is not grouped, 7 the deepest level.
  final int outlineLevel;

  /// Whether the row carries the button of a collapsed group.
  final bool collapsed;

  /// The row's style, or `null` for none.
  ///
  /// Excel stores it as the row's `s` with `customFormat="1"`.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxRowFormat &&
      other.height == height &&
      other.hidden == hidden &&
      other.outlineLevel == outlineLevel &&
      other.collapsed == collapsed &&
      other.style == style;

  @override
  int get hashCode =>
      Object.hash(height, hidden, outlineLevel, collapsed, style);

  @override
  String toString() {
    final List<String> fields = <String>[
      if (height case final double h) 'height: ${describeDouble(h)}',
      if (hidden) 'hidden: true',
      if (outlineLevel != 0) 'outlineLevel: $outlineLevel',
      if (collapsed) 'collapsed: true',
      if (style != null) 'style: $style',
    ];
    return 'XlsxRowFormat(${fields.join(', ')})';
  }
}
