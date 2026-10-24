/// The cell style value type.
///
/// New in jet_office; Quds' `style(...)` returns an id directly from loose
/// parameters. Here a style is a value made of six optional parts, and
/// layered styles (column, row, cell) combine with [XlsxStyle.merge].
library;

import 'alignment.dart';
import 'border.dart';
import 'fill.dart';
import 'font.dart';
import 'number_format.dart';

/// How a cell is formatted: a number format, a font, a fill, a border, an
/// alignment and a protection, each optional.
///
/// A `null` part means "inherit": from a lower layer when styles are
/// combined with [merge], and from Excel's default (General, Calibri 11, no
/// fill, no border) when the style reaches the writer. Values are compared
/// by their contents. The writer gives styles that would look the same one
/// cell format, even when they are spelled differently, such as
/// `XlsxFont()` and `XlsxFont(name: 'Calibri', size: 11)`.
///
/// The `const` constructor cannot check its parts. The writer checks them
/// when the style is first used and throws [ArgumentError] naming the field.
final class XlsxStyle {
  /// Creates a style from the given parts.
  const XlsxStyle({
    this.numFmt,
    this.font,
    this.fill,
    this.border,
    this.alignment,
    this.protection,
  });

  /// The number format, or `null` to inherit (General by default).
  final XlsxNumFmt? numFmt;

  /// The font, or `null` to inherit (Calibri 11 by default).
  final XlsxFont? font;

  /// The fill, or `null` to inherit (none by default).
  final XlsxFill? fill;

  /// The border, or `null` to inherit (none by default).
  final XlsxBorder? border;

  /// The text alignment, or `null` to inherit (Excel's defaults).
  final XlsxAlignment? alignment;

  /// The protection, or `null` to inherit (locked and not hidden).
  final XlsxProtection? protection;

  /// This style with [other] laid on top.
  ///
  /// The font, border, alignment and protection merge field by field, so a
  /// bold row over a money column gives bold money. The number format and
  /// the fill of [other] replace this style's whole. A null part of [other]
  /// never erases a part of this style, and a null [other] changes nothing.
  XlsxStyle merge(XlsxStyle? other) {
    if (other == null) {
      return this;
    }
    return XlsxStyle(
      numFmt: other.numFmt ?? numFmt,
      font: font?.merge(other.font) ?? other.font,
      fill: other.fill ?? fill,
      border: border?.merge(other.border) ?? other.border,
      alignment: alignment?.merge(other.alignment) ?? other.alignment,
      protection: protection?.merge(other.protection) ?? other.protection,
    );
  }

  /// A copy with each given part replaced whole.
  ///
  /// A `null` argument keeps the part, so a part cannot be reset to `null`
  /// with this method. To show General over an inherited number format,
  /// pass [XlsxNumFmt.general].
  XlsxStyle copyWith({
    XlsxNumFmt? numFmt,
    XlsxFont? font,
    XlsxFill? fill,
    XlsxBorder? border,
    XlsxAlignment? alignment,
    XlsxProtection? protection,
  }) => XlsxStyle(
    numFmt: numFmt ?? this.numFmt,
    font: font ?? this.font,
    fill: fill ?? this.fill,
    border: border ?? this.border,
    alignment: alignment ?? this.alignment,
    protection: protection ?? this.protection,
  );

  @override
  bool operator ==(Object other) =>
      other is XlsxStyle &&
      other.numFmt == numFmt &&
      other.font == font &&
      other.fill == fill &&
      other.border == border &&
      other.alignment == alignment &&
      other.protection == protection;

  @override
  int get hashCode =>
      Object.hash(numFmt, font, fill, border, alignment, protection);

  @override
  String toString() {
    final List<String> parts = <String>[
      if (numFmt != null) 'numFmt: $numFmt',
      if (font != null) 'font: $font',
      if (fill != null) 'fill: $fill',
      if (border != null) 'border: $border',
      if (alignment != null) 'alignment: $alignment',
      if (protection != null) 'protection: $protection',
    ];
    return 'XlsxStyle(${parts.join(', ')})';
  }
}
