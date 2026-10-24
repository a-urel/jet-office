/// The cell style value type.
///
/// New in jet_office; Quds' `style(...)` returns an id directly from loose
/// parameters. Later milestones grow this type (fonts, fills, borders,
/// alignment).
library;

import 'number_format.dart';

/// How a cell is formatted.
///
/// Values are compared by their contents, so equal styles share one entry in
/// the workbook. Today a style only carries a number format; the API may
/// break before it stabilises.
final class XlsxStyle {
  /// Creates a style with the optional [numFmt].
  const XlsxStyle({this.numFmt});

  /// The number format, or `null` to leave the cell's format at General.
  final XlsxNumFmt? numFmt;

  /// A copy of this style with the given fields replaced.
  XlsxStyle copyWith({XlsxNumFmt? numFmt}) =>
      XlsxStyle(numFmt: numFmt ?? this.numFmt);

  @override
  bool operator ==(Object other) =>
      other is XlsxStyle && other.numFmt == numFmt;

  @override
  int get hashCode => numFmt.hashCode;

  @override
  String toString() => 'XlsxStyle(numFmt: $numFmt)';
}
