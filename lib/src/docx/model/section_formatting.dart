/// The values of section properties: page size, margins, columns, how a
/// section starts, its vertical alignment, and page and line numbering.
///
/// Not ported from Quds; written for jet_office.
///
/// Lengths are points at the API and twips in the file, rounded, as in
/// `formatting.dart`: a value set reads back rounded, and two values are
/// equal when their stored numbers are. A bad argument throws
/// [ArgumentError] (not finite, an inconsistent list) or [RangeError] (out
/// of range once rounded).
library;

import '../units.dart';
import 'numbering_formats.dart';

/// A page's orientation (`w:orient` of `w:pgSz`).
///
/// It does not change the size: a landscape page has the width and height
/// the section says, as Word writes them (the long side as the width).
enum DocxPageOrientation {
  /// A tall page.
  portrait,

  /// A wide page.
  landscape,
}

/// The size of a page (`w:pgSz`): width and height, each from 0 to 1584
/// points, and the orientation.
final class DocxPageSize {
  /// A page of [widthPt] by [heightPt] points.
  ///
  /// Throws [ArgumentError] when a length is not finite and [RangeError]
  /// when one is out of range once rounded.
  DocxPageSize(
    double widthPt,
    double heightPt, {
    this.orientation = DocxPageOrientation.portrait,
  }) : _width = twipsOf(widthPt, 'widthPt', min: 0, max: maxTwips),
       _height = twipsOf(heightPt, 'heightPt', min: 0, max: maxTwips);

  /// An A4 page (11906 by 16838 twips); [landscape] turns it, with the long
  /// side as the width.
  DocxPageSize.a4({bool landscape = false})
    : this(
        ptOfTwips(landscape ? 16838 : 11906),
        ptOfTwips(landscape ? 11906 : 16838),
        orientation: landscape
            ? DocxPageOrientation.landscape
            : DocxPageOrientation.portrait,
      );

  /// A Letter page (12240 by 15840 twips); [landscape] turns it, with the
  /// long side as the width.
  DocxPageSize.letter({bool landscape = false})
    : this(
        ptOfTwips(landscape ? 15840 : 12240),
        ptOfTwips(landscape ? 12240 : 15840),
        orientation: landscape
            ? DocxPageOrientation.landscape
            : DocxPageOrientation.portrait,
      );

  final int _width;
  final int _height;

  /// The page's orientation.
  final DocxPageOrientation orientation;

  /// The page's width, in points.
  double get widthPt => ptOfTwips(_width);

  /// The page's height, in points.
  double get heightPt => ptOfTwips(_height);

  @override
  bool operator ==(Object other) =>
      other is DocxPageSize &&
      other._width == _width &&
      other._height == _height &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(_width, _height, orientation);

  @override
  String toString() =>
      'DocxPageSize($widthPt x $heightPt, ${orientation.name})';
}

/// The margins of a page (`w:pgMar`), in points: the four sides, the
/// distance of the header and the footer from the page edge, and the
/// gutter.
///
/// `w:pgMar` requires all seven, so all are required here. `top` and
/// `bottom` are signed, from -1584 to 1584 (a negative one tells Word to
/// keep the header or footer inside the body's space); the others run from 0
/// to 1584.
final class DocxPageMargins {
  /// Margins of the given sides.
  ///
  /// Throws [ArgumentError] for a length that is not finite and
  /// [RangeError] for one out of range once rounded.
  DocxPageMargins({
    required double top,
    required double right,
    required double bottom,
    required double left,
    required double header,
    required double footer,
    required double gutter,
  }) : _top = twipsOf(top, 'top', min: -maxTwips, max: maxTwips),
       _right = twipsOf(right, 'right', min: 0, max: maxTwips),
       _bottom = twipsOf(bottom, 'bottom', min: -maxTwips, max: maxTwips),
       _left = twipsOf(left, 'left', min: 0, max: maxTwips),
       _header = twipsOf(header, 'header', min: 0, max: maxTwips),
       _footer = twipsOf(footer, 'footer', min: 0, max: maxTwips),
       _gutter = twipsOf(gutter, 'gutter', min: 0, max: maxTwips);

  final int _top;
  final int _right;
  final int _bottom;
  final int _left;
  final int _header;
  final int _footer;
  final int _gutter;

  /// The margin above the body, in points.
  double get topPt => ptOfTwips(_top);

  /// The margin at the right, in points.
  double get rightPt => ptOfTwips(_right);

  /// The margin below the body, in points.
  double get bottomPt => ptOfTwips(_bottom);

  /// The margin at the left, in points.
  double get leftPt => ptOfTwips(_left);

  /// The distance of the header from the top edge, in points.
  double get headerPt => ptOfTwips(_header);

  /// The distance of the footer from the bottom edge, in points.
  double get footerPt => ptOfTwips(_footer);

  /// The extra margin for binding, in points.
  double get gutterPt => ptOfTwips(_gutter);

  @override
  bool operator ==(Object other) =>
      other is DocxPageMargins &&
      other._top == _top &&
      other._right == _right &&
      other._bottom == _bottom &&
      other._left == _left &&
      other._header == _header &&
      other._footer == _footer &&
      other._gutter == _gutter;

  @override
  int get hashCode =>
      Object.hash(_top, _right, _bottom, _left, _header, _footer, _gutter);

  @override
  String toString() =>
      'DocxPageMargins(top: $topPt, right: $rightPt, bottom: $bottomPt, '
      'left: $leftPt, header: $headerPt, footer: $footerPt, '
      'gutter: $gutterPt)';
}

/// One column of unequal width (`w:col`): its width and the space after it.
final class DocxColumn {
  /// A column of [widthPt] points followed by [spacingPt] points of space,
  /// each from 0 to 1584.
  ///
  /// Throws [ArgumentError] for a length that is not finite and
  /// [RangeError] for one out of range once rounded.
  DocxColumn(double widthPt, {double spacingPt = 0})
    : _width = twipsOf(widthPt, 'widthPt', min: 0, max: maxTwips),
      _spacing = twipsOf(spacingPt, 'spacingPt', min: 0, max: maxTwips);

  final int _width;
  final int _spacing;

  /// The column's width, in points.
  double get widthPt => ptOfTwips(_width);

  /// The space after the column, in points (Word ignores the last one's).
  double get spacingPt => ptOfTwips(_spacing);

  @override
  bool operator ==(Object other) =>
      other is DocxColumn &&
      other._width == _width &&
      other._spacing == _spacing;

  @override
  int get hashCode => Object.hash(_width, _spacing);

  @override
  String toString() => 'DocxColumn($widthPt, spacingPt: $spacingPt)';
}

/// The most columns a section has: Word's limit.
const int maxColumns = 45;

/// The text columns of a section (`w:cols`): [count] columns of equal
/// width, or the unequal [widths] given.
final class DocxColumns {
  /// Columns of equal width: [count] of them (1 to 45), [spacingPt] points
  /// apart (0 to 1584), with a line between them when [separator] is true.
  ///
  /// With [widths] the columns are unequal: [widths] must not be empty or
  /// longer than 45, [count], if given, must be its length, and
  /// [spacingPt] is the default the file gives (it is not used for
  /// columns with a space of their own).
  ///
  /// Throws [ArgumentError] for a length that is not finite, a [widths]
  /// that is empty or a [count] that is not its length, and [RangeError]
  /// for a number out of range once rounded.
  factory DocxColumns({
    int? count,
    double spacingPt = 36,
    bool separator = false,
    List<DocxColumn>? widths,
  }) {
    final int space = twipsOf(spacingPt, 'spacingPt', min: 0, max: maxTwips);
    if (widths != null) {
      if (widths.isEmpty) {
        throw ArgumentError.value(widths, 'widths', 'must not be empty');
      }
      if (widths.length > maxColumns) {
        throw RangeError.range(
          widths.length,
          1,
          maxColumns,
          'widths',
          'must hold from 1 to $maxColumns columns',
        );
      }
      if (count != null && count != widths.length) {
        throw ArgumentError.value(
          count,
          'count',
          'must be the number of widths (${widths.length})',
        );
      }
      return DocxColumns._(
        widths.length,
        space,
        separator,
        List<DocxColumn>.unmodifiable(widths),
      );
    }
    final int n = count ?? 1;
    RangeError.checkValueInInterval(n, 1, maxColumns, 'count');
    return DocxColumns._(n, space, separator, null);
  }

  const DocxColumns._(this.count, this._spacing, this.separator, this.widths);

  /// The number of columns.
  final int count;

  final int _spacing;

  /// Whether a line is drawn between the columns.
  final bool separator;

  /// The columns of unequal width, or `null` when they are equal. It cannot
  /// be changed.
  final List<DocxColumn>? widths;

  /// The space between equal columns, in points.
  double get spacingPt => ptOfTwips(_spacing);

  @override
  bool operator ==(Object other) {
    if (other is! DocxColumns ||
        other.count != count ||
        other._spacing != _spacing ||
        other.separator != separator) {
      return false;
    }
    final List<DocxColumn>? a = widths;
    final List<DocxColumn>? b = other.widths;
    if (a == null || b == null) {
      return a == b;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(count, _spacing, separator, Object.hashAll(widths ?? []));

  @override
  String toString() =>
      'DocxColumns(count: $count, spacingPt: $spacingPt, '
      'separator: $separator, widths: $widths)';
}

/// Where a section starts (`w:type`): how it breaks from the one before.
enum DocxSectionStart {
  /// On the same page, with no break.
  continuous,

  /// In the next column.
  nextColumn,

  /// On the next page.
  nextPage,

  /// On the next even-numbered page.
  evenPage,

  /// On the next odd-numbered page.
  oddPage,
}

/// How a section's text sits between the top and bottom margins
/// (`w:vAlign`).
enum DocxSectionVerticalAlignment {
  /// At the top.
  top,

  /// Centered.
  center,

  /// Spread, justified from top to bottom.
  both,

  /// At the bottom.
  bottom,
}

/// The largest page number or line number start: five digits.
const int maxSectionNumber = 32767;

/// How a section numbers its pages (`w:pgNumType`): the format and the
/// number it starts at; a `null` field is not in the file, so the document's
/// own applies.
final class DocxPageNumbering {
  /// Page numbering with a [format] and a [start] (0 to 32767).
  ///
  /// Throws [RangeError] when [start] is out of range.
  DocxPageNumbering({this.format, this.start}) {
    if (start != null) {
      RangeError.checkValueInInterval(start!, 0, maxSectionNumber, 'start');
    }
  }

  /// The number format, or `null`.
  final DocxNumberFormat? format;

  /// The number the section's first page gets, or `null`.
  final int? start;

  @override
  bool operator ==(Object other) =>
      other is DocxPageNumbering &&
      other.format == format &&
      other.start == start;

  @override
  int get hashCode => Object.hash(format, start);

  @override
  String toString() => 'DocxPageNumbering(format: $format, start: $start)';
}

/// When line numbering starts over (`w:restart` of `w:lnNumType`).
enum DocxLineNumberRestart {
  /// On each page.
  newPage,

  /// In each section.
  newSection,

  /// Never: the numbers run through the document.
  continuous,
}

/// How a section numbers its lines (`w:lnNumType`); a `null` field is not in
/// the file, so Word's default applies.
final class DocxLineNumbering {
  /// Line numbering: a number is shown on every [countBy] lines (1 to
  /// 32767), counting from [start] (0 to 32767, as the file stores it),
  /// [distancePt] points from the text (0 to 1584), starting over as
  /// [restart] says.
  ///
  /// Throws [ArgumentError] for a length that is not finite and
  /// [RangeError] for a number out of range once rounded.
  DocxLineNumbering({
    this.countBy,
    this.start,
    double? distancePt,
    this.restart,
  }) : _distance = distancePt == null
           ? null
           : twipsOf(distancePt, 'distancePt', min: 0, max: maxTwips) {
    if (countBy != null) {
      RangeError.checkValueInInterval(countBy!, 1, maxSectionNumber, 'countBy');
    }
    if (start != null) {
      RangeError.checkValueInInterval(start!, 0, maxSectionNumber, 'start');
    }
  }

  /// A number on every this many lines, or `null`.
  final int? countBy;

  /// The first number, as stored (0 is the line numbered 1), or `null`.
  final int? start;

  final int? _distance;

  /// When the numbers start over, or `null`.
  final DocxLineNumberRestart? restart;

  /// The distance from the text, in points, or `null` (Word chooses).
  double? get distancePt => _distance == null ? null : ptOfTwips(_distance);

  @override
  bool operator ==(Object other) =>
      other is DocxLineNumbering &&
      other.countBy == countBy &&
      other.start == start &&
      other._distance == _distance &&
      other.restart == restart;

  @override
  int get hashCode => Object.hash(countBy, start, _distance, restart);

  @override
  String toString() =>
      'DocxLineNumbering(countBy: $countBy, start: $start, '
      'distancePt: $distancePt, restart: $restart)';
}
