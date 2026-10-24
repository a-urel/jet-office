/// Alignment and protection for cell formats.
///
/// New in jet_office. Quds keeps alignment as loose fields of its private
/// `_Xf` class inside `builders/xlsx_io.dart`, with no protection and no
/// validation; here alignment and protection are public, model-neutral value
/// types with every `CT_CellAlignment` and `CT_CellProtection` property, and
/// the writer checks them when they are registered.
library;

import '../xml/xml_writer.dart';
import 'limits.dart';

/// Horizontal text placement (`ST_HorizontalAlignment`).
enum XlsxHorizontalAlignment {
  /// Text left, numbers right (Excel's default).
  general,

  /// Against the left edge.
  left,

  /// Centered.
  center,

  /// Against the right edge.
  right,

  /// Repeats the content to fill the cell.
  fill,

  /// Spread to both edges.
  justify,

  /// Centered across the adjacent empty cells.
  centerContinuous,

  /// Spread evenly across the cell.
  distributed,
}

/// Vertical text placement (`ST_VerticalAlignment`).
enum XlsxVerticalAlignment {
  /// Against the top edge.
  top,

  /// Centered.
  center,

  /// Against the bottom edge (Excel's default).
  bottom,

  /// Spread to top and bottom.
  justify,

  /// Spread evenly from top to bottom.
  distributed,
}

/// The reading direction of cell text, written as `readingOrder`.
enum XlsxReadingOrder {
  /// Taken from the first character (written as `0`, the default).
  context,

  /// Left to right (written as `1`).
  leftToRight,

  /// Right to left (written as `2`).
  rightToLeft,
}

/// How the text of a cell is aligned (`CT_CellAlignment`).
///
/// Every field is nullable, and `null` means "inherit": [merge] lets the
/// non-null fields of one alignment win over another. The `const`
/// constructor cannot check its arguments; the writer does, when the
/// alignment is registered, and throws [ArgumentError] naming the field.
final class XlsxAlignment {
  /// Creates an alignment. See each field for its limits.
  const XlsxAlignment({
    this.horizontal,
    this.vertical,
    this.wrapText,
    this.indent,
    this.textRotation,
    this.shrinkToFit,
    this.readingOrder,
    this.justifyLastLine,
  });

  /// The [textRotation] that stacks the text vertically, one letter above
  /// the next.
  static const int verticalText = XlsxLimits.verticalTextRotation;

  /// The horizontal placement.
  final XlsxHorizontalAlignment? horizontal;

  /// The vertical placement.
  final XlsxVerticalAlignment? vertical;

  /// Whether long text wraps onto more lines.
  final bool? wrapText;

  /// The indent in character widths, within 0 to [XlsxLimits.maxIndent].
  final int? indent;

  /// The rotation in degrees: `0..90` counterclockwise, `91..180` clockwise
  /// (`90` less the value; [XlsxLimits.maxTextRotation] is the largest), or
  /// [verticalText].
  final int? textRotation;

  /// Whether the text shrinks to fit the cell.
  final bool? shrinkToFit;

  /// The reading direction.
  final XlsxReadingOrder? readingOrder;

  /// Whether the last line of distributed or justified text is spread too.
  final bool? justifyLastLine;

  /// This alignment with every non-null field of [other] applied on top.
  ///
  /// A null [other] changes nothing.
  XlsxAlignment merge(XlsxAlignment? other) {
    if (other == null) {
      return this;
    }
    return XlsxAlignment(
      horizontal: other.horizontal ?? horizontal,
      vertical: other.vertical ?? vertical,
      wrapText: other.wrapText ?? wrapText,
      indent: other.indent ?? indent,
      textRotation: other.textRotation ?? textRotation,
      shrinkToFit: other.shrinkToFit ?? shrinkToFit,
      readingOrder: other.readingOrder ?? readingOrder,
      justifyLastLine: other.justifyLastLine ?? justifyLastLine,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is XlsxAlignment &&
      other.horizontal == horizontal &&
      other.vertical == vertical &&
      other.wrapText == wrapText &&
      other.indent == indent &&
      other.textRotation == textRotation &&
      other.shrinkToFit == shrinkToFit &&
      other.readingOrder == readingOrder &&
      other.justifyLastLine == justifyLastLine;

  @override
  int get hashCode => Object.hash(
    horizontal,
    vertical,
    wrapText,
    indent,
    textRotation,
    shrinkToFit,
    readingOrder,
    justifyLastLine,
  );

  @override
  String toString() {
    final List<String> parts = <String>[
      if (horizontal != null) 'horizontal: $horizontal',
      if (vertical != null) 'vertical: $vertical',
      if (wrapText != null) 'wrapText: $wrapText',
      if (indent != null) 'indent: $indent',
      if (textRotation != null) 'textRotation: $textRotation',
      if (shrinkToFit != null) 'shrinkToFit: $shrinkToFit',
      if (readingOrder != null) 'readingOrder: $readingOrder',
      if (justifyLastLine != null) 'justifyLastLine: $justifyLastLine',
    ];
    return 'XlsxAlignment(${parts.join(', ')})';
  }
}

/// Whether a cell is locked or hidden when its sheet is protected
/// (`CT_CellProtection`).
///
/// Both fields are nullable, and `null` means "inherit". Excel's defaults are
/// locked `true` and hidden `false`.
final class XlsxProtection {
  /// Creates a protection.
  const XlsxProtection({this.locked, this.hidden});

  /// Whether the cell cannot be edited while its sheet is protected.
  final bool? locked;

  /// Whether the cell's formula is hidden while its sheet is protected.
  final bool? hidden;

  /// This protection with every non-null field of [other] applied on top.
  ///
  /// A null [other] changes nothing.
  XlsxProtection merge(XlsxProtection? other) {
    if (other == null) {
      return this;
    }
    return XlsxProtection(
      locked: other.locked ?? locked,
      hidden: other.hidden ?? hidden,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is XlsxProtection &&
      other.locked == locked &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(locked, hidden);

  @override
  String toString() {
    final List<String> parts = <String>[
      if (locked != null) 'locked: $locked',
      if (hidden != null) 'hidden: $hidden',
    ];
    return 'XlsxProtection(${parts.join(', ')})';
  }
}

/// Checks [a]: an indent within `0..250` and a rotation within `0..180` or
/// [XlsxAlignment.verticalText].
///
/// Throws [ArgumentError] naming the field.
void validateAlignment(XlsxAlignment a) {
  final int? indent = a.indent;
  if (indent != null && (indent < 0 || indent > XlsxLimits.maxIndent)) {
    throw ArgumentError.value(
      indent,
      'indent',
      'An indent must be within 0..${XlsxLimits.maxIndent}.',
    );
  }
  final int? rotation = a.textRotation;
  if (rotation != null &&
      (rotation < 0 || rotation > XlsxLimits.maxTextRotation) &&
      rotation != XlsxAlignment.verticalText) {
    throw ArgumentError.value(
      rotation,
      'textRotation',
      'A text rotation must be within 0..${XlsxLimits.maxTextRotation}, '
          'or ${XlsxAlignment.verticalText} for vertical text.',
    );
  }
}

/// [a] as an `<alignment>` element, or null when every value is Excel's
/// default (general, bottom, no wrap, no shrink, no justified last line,
/// indent 0, rotation 0, context reading order), set explicitly or not.
///
/// Attributes follow Excel's order. The alignment must have passed
/// [validateAlignment]. The registry dedupes cell formats on this text.
String? alignmentXml(XlsxAlignment? a) {
  if (a == null) {
    return null;
  }
  final List<(String, String)> attributes = <(String, String)>[
    if (a.horizontal != null && a.horizontal != XlsxHorizontalAlignment.general)
      ('horizontal', a.horizontal!.name),
    if (a.vertical != null && a.vertical != XlsxVerticalAlignment.bottom)
      ('vertical', a.vertical!.name),
    if ((a.textRotation ?? 0) != 0) ('textRotation', '${a.textRotation}'),
    if (a.wrapText ?? false) ('wrapText', '1'),
    if ((a.indent ?? 0) != 0) ('indent', '${a.indent}'),
    if (a.justifyLastLine ?? false) ('justifyLastLine', '1'),
    if (a.shrinkToFit ?? false) ('shrinkToFit', '1'),
    if (a.readingOrder != null && a.readingOrder != XlsxReadingOrder.context)
      ('readingOrder', '${a.readingOrder!.index}'),
  ];
  return _emptyElement('alignment', attributes);
}

/// [p] as a `<protection>` element, or null when it is Excel's default
/// (locked, not hidden), set explicitly or not.
///
/// The registry dedupes cell formats on this text.
String? protectionXml(XlsxProtection? p) {
  if (p == null) {
    return null;
  }
  final List<(String, String)> attributes = <(String, String)>[
    if (p.locked == false) ('locked', '0'),
    if (p.hidden ?? false) ('hidden', '1'),
  ];
  return _emptyElement('protection', attributes);
}

String? _emptyElement(String name, List<(String, String)> attributes) {
  if (attributes.isEmpty) {
    return null;
  }
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out);
  w.start(name);
  for (final (String, String) attribute in attributes) {
    w.attribute(attribute.$1, attribute.$2);
  }
  w.end();
  return out.toString();
}
