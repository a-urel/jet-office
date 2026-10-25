/// [XlsxPageSetup], how a worksheet prints, its checks and its
/// `printOptions`, `pageMargins` and `pageSetup` XML.
///
/// New in jet_office; Quds writes no page setup at all. The value types
/// describe SpreadsheetML (paper, scale, margins, centering), not the
/// writer; the writer checks a setup when it is registered and the trailer
/// writes `pageSetup` attributes in `CT_PageSetup` order, those that differ
/// from the schema defaults only.
library;

import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'limits.dart';

/// Which way a page is printed (`ST_Orientation`).
enum XlsxOrientation {
  /// Taller than wide. XML `portrait`.
  portrait,

  /// Wider than tall. XML `landscape`.
  landscape,
}

/// In which order the pages of a sheet wider and longer than one page are
/// printed (`ST_PageOrder`).
enum XlsxPageOrder {
  /// Down the first column of pages, then over to the next. XML
  /// `downThenOver`, the default.
  downThenOver,

  /// Across the first row of pages, then down to the next. XML
  /// `overThenDown`.
  overThenDown,
}

/// A paper size, by its id in ECMA-376's `paperSize` list (1 to 118).
///
/// The constants name the common sizes; any other id from the list is
/// `XlsxPaperSize(id)`. The `const` constructor cannot check [id]; the
/// writer does when the page setup is registered. Compared by [id].
final class XlsxPaperSize {
  /// The paper size with [id] in ECMA-376's list.
  const XlsxPaperSize(this.id);

  /// Letter, 8.5 x 11 in. Id 1, the schema default.
  static const XlsxPaperSize letter = XlsxPaperSize(1);

  /// Tabloid, 11 x 17 in. Id 3.
  static const XlsxPaperSize tabloid = XlsxPaperSize(3);

  /// Legal, 8.5 x 14 in. Id 5.
  static const XlsxPaperSize legal = XlsxPaperSize(5);

  /// Executive, 7.25 x 10.5 in. Id 7.
  static const XlsxPaperSize executive = XlsxPaperSize(7);

  /// A3, 297 x 420 mm. Id 8.
  static const XlsxPaperSize a3 = XlsxPaperSize(8);

  /// A4, 210 x 297 mm. Id 9.
  static const XlsxPaperSize a4 = XlsxPaperSize(9);

  /// A5, 148 x 210 mm. Id 11.
  static const XlsxPaperSize a5 = XlsxPaperSize(11);

  /// B4 (JIS), 257 x 364 mm. Id 12.
  static const XlsxPaperSize b4 = XlsxPaperSize(12);

  /// B5 (JIS), 182 x 257 mm. Id 13.
  static const XlsxPaperSize b5 = XlsxPaperSize(13);

  /// The id in ECMA-376's `paperSize` list, from 1 to 118.
  final int id;

  @override
  bool operator ==(Object other) => other is XlsxPaperSize && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'XlsxPaperSize($id)';
}

/// The margins of a printed page in inches (`CT_PageMargins`).
///
/// The defaults are Excel's "Normal" margins. Each must be finite and at
/// least 0; the `const` constructor cannot check them, the writer does when
/// the page setup is registered. [header] and [footer] are measured from the
/// page edge.
final class XlsxPageMargins {
  /// Margins in inches; the defaults are Excel's "Normal".
  const XlsxPageMargins({
    this.left = 0.7,
    this.right = 0.7,
    this.top = 0.75,
    this.bottom = 0.75,
    this.header = 0.3,
    this.footer = 0.3,
  });

  /// The left margin in inches.
  final double left;

  /// The right margin in inches.
  final double right;

  /// The top margin in inches.
  final double top;

  /// The bottom margin in inches.
  final double bottom;

  /// The distance of the header from the top edge in inches.
  final double header;

  /// The distance of the footer from the bottom edge in inches.
  final double footer;

  @override
  bool operator ==(Object other) =>
      other is XlsxPageMargins &&
      other.left == left &&
      other.right == right &&
      other.top == top &&
      other.bottom == bottom &&
      other.header == header &&
      other.footer == footer;

  @override
  int get hashCode => Object.hash(left, right, top, bottom, header, footer);

  @override
  String toString() =>
      'XlsxPageMargins(left: ${describeDouble(left)}, '
      'right: ${describeDouble(right)}, top: ${describeDouble(top)}, '
      'bottom: ${describeDouble(bottom)}, '
      'header: ${describeDouble(header)}, footer: ${describeDouble(footer)})';
}

/// How a sheet prints: paper, orientation, scaling, margins, page numbering
/// and what is printed besides the cells.
///
/// A `null` field leaves the choice to Excel's default (or the printer's).
/// [scale] and the fit-to fields exclude each other: a scale is a percentage
/// of normal size, fitting makes the sheet [fitToWidth] pages wide and
/// [fitToHeight] pages tall, where 0 leaves that axis as many pages as it
/// needs. When either fit field is set, an axis left `null` counts as 0. The
/// `const` constructor cannot check its fields; the writer does when the
/// setup is registered and throws [ArgumentError] naming the field.
final class XlsxPageSetup {
  /// A page setup; every field defaults to Excel's.
  const XlsxPageSetup({
    this.orientation,
    this.paperSize,
    this.scale,
    this.fitToWidth,
    this.fitToHeight,
    this.firstPageNumber,
    this.pageOrder,
    this.blackAndWhite = false,
    this.draft = false,
    this.margins = const XlsxPageMargins(),
    this.centerHorizontally = false,
    this.centerVertically = false,
    this.printGridLines = false,
    this.printHeadings = false,
  });

  /// Portrait or landscape; `null` leaves it to the printer.
  final XlsxOrientation? orientation;

  /// The paper; `null` leaves it to the printer (Excel's default is
  /// letter).
  final XlsxPaperSize? paperSize;

  /// The print scale in percent, from 10 to 400; `null` is 100. Cannot be
  /// combined with [fitToWidth] or [fitToHeight].
  final int? scale;

  /// The number of pages wide to fit the sheet to, from 0 (as many as
  /// needed) to 32,767; `null` leaves the width unfitted unless
  /// [fitToHeight] is set.
  final int? fitToWidth;

  /// The number of pages tall to fit the sheet to, from 0 (as many as
  /// needed) to 32,767; `null` leaves the height unfitted unless
  /// [fitToWidth] is set.
  final int? fitToHeight;

  /// The number the first printed page gets, from 1 to 32,767; `null`
  /// numbers automatically.
  final int? firstPageNumber;

  /// The order of the pages; `null` is [XlsxPageOrder.downThenOver].
  final XlsxPageOrder? pageOrder;

  /// Whether to print in black and white.
  final bool blackAndWhite;

  /// Whether to print in draft quality.
  final bool draft;

  /// The page margins in inches.
  final XlsxPageMargins margins;

  /// Whether to center the cells between the left and right margins.
  final bool centerHorizontally;

  /// Whether to center the cells between the top and bottom margins.
  final bool centerVertically;

  /// Whether to print the cell gridlines.
  final bool printGridLines;

  /// Whether to print the row and column headings.
  final bool printHeadings;

  @override
  bool operator ==(Object other) =>
      other is XlsxPageSetup &&
      other.orientation == orientation &&
      other.paperSize == paperSize &&
      other.scale == scale &&
      other.fitToWidth == fitToWidth &&
      other.fitToHeight == fitToHeight &&
      other.firstPageNumber == firstPageNumber &&
      other.pageOrder == pageOrder &&
      other.blackAndWhite == blackAndWhite &&
      other.draft == draft &&
      other.margins == margins &&
      other.centerHorizontally == centerHorizontally &&
      other.centerVertically == centerVertically &&
      other.printGridLines == printGridLines &&
      other.printHeadings == printHeadings;

  @override
  int get hashCode => Object.hash(
    orientation,
    paperSize,
    scale,
    fitToWidth,
    fitToHeight,
    firstPageNumber,
    pageOrder,
    blackAndWhite,
    draft,
    margins,
    centerHorizontally,
    centerVertically,
    printGridLines,
    printHeadings,
  );

  @override
  String toString() =>
      'XlsxPageSetup(orientation: $orientation, paperSize: $paperSize, '
      'scale: $scale, fitToWidth: $fitToWidth, fitToHeight: $fitToHeight, '
      'firstPageNumber: $firstPageNumber, pageOrder: $pageOrder, '
      'blackAndWhite: $blackAndWhite, draft: $draft, margins: $margins, '
      'centerHorizontally: $centerHorizontally, '
      'centerVertically: $centerVertically, '
      'printGridLines: $printGridLines, printHeadings: $printHeadings)';
}

/// Whether [setup] fits the sheet to pages, which the sheet's `sheetPr`
/// announces with `pageSetUpPr fitToPage`.
bool pageSetupFitsToPage(XlsxPageSetup setup) =>
    setup.fitToWidth != null || setup.fitToHeight != null;

/// Throws [ArgumentError] naming the field unless [setup] is valid: a scale
/// of 10 to 400 and no fit axis beside it, fit axes of 0 to 32,767, a first
/// page number of 1 to 32,767, a paper size of 1 to 118, and margins that
/// are finite and at least 0.
void checkPageSetup(XlsxPageSetup setup) {
  final int? scale = setup.scale;
  if (scale != null) {
    if (scale < XlsxLimits.minPageScale || scale > XlsxLimits.maxPageScale) {
      throw ArgumentError.value(
        scale,
        'scale',
        'A page scale must be between ${XlsxLimits.minPageScale} and '
            '${XlsxLimits.maxPageScale} percent.',
      );
    }
    if (pageSetupFitsToPage(setup)) {
      throw ArgumentError.value(
        scale,
        'scale',
        'A scale cannot be combined with fitToWidth or fitToHeight.',
      );
    }
  }
  _checkFit(setup.fitToWidth, 'fitToWidth');
  _checkFit(setup.fitToHeight, 'fitToHeight');
  final int? first = setup.firstPageNumber;
  if (first != null && (first < 1 || first > XlsxLimits.maxFirstPageNumber)) {
    throw ArgumentError.value(
      first,
      'firstPageNumber',
      'A first page number must be between 1 and '
          '${XlsxLimits.maxFirstPageNumber}.',
    );
  }
  final XlsxPaperSize? paper = setup.paperSize;
  if (paper != null && (paper.id < 1 || paper.id > XlsxLimits.maxPaperSize)) {
    throw ArgumentError.value(
      paper.id,
      'paperSize',
      'A paper size id must be between 1 and ${XlsxLimits.maxPaperSize}.',
    );
  }
  final XlsxPageMargins m = setup.margins;
  _checkMargin(m.left, 'margins.left');
  _checkMargin(m.right, 'margins.right');
  _checkMargin(m.top, 'margins.top');
  _checkMargin(m.bottom, 'margins.bottom');
  _checkMargin(m.header, 'margins.header');
  _checkMargin(m.footer, 'margins.footer');
}

void _checkFit(int? pages, String name) {
  if (pages != null && (pages < 0 || pages > XlsxLimits.maxFitToPages)) {
    throw ArgumentError.value(
      pages,
      name,
      'A fit-to page count must be between 0 and '
      '${XlsxLimits.maxFitToPages}.',
    );
  }
}

void _checkMargin(double inches, String name) {
  // Written so that NaN fails too.
  if (!(inches >= 0 && inches.isFinite)) {
    throw ArgumentError.value(
      inches,
      name,
      'A margin must be finite and at least 0 inches.',
    );
  }
}

/// Writes `printOptions` (only when a flag is set), `pageMargins` and
/// `pageSetup` (only when an attribute differs from the default) for the
/// checked [setup].
void writePageSetup(XmlWriter w, XlsxPageSetup setup) {
  if (setup.centerHorizontally ||
      setup.centerVertically ||
      setup.printHeadings ||
      setup.printGridLines) {
    // CT_PrintOptions order: horizontalCentered, verticalCentered, headings,
    // gridLines.
    w.start('printOptions');
    if (setup.centerHorizontally) w.attribute('horizontalCentered', '1');
    if (setup.centerVertically) w.attribute('verticalCentered', '1');
    if (setup.printHeadings) w.attribute('headings', '1');
    if (setup.printGridLines) w.attribute('gridLines', '1');
    w.end();
  }
  // Required by the schema, all six attributes.
  final XlsxPageMargins m = setup.margins;
  w.empty('pageMargins', <String, String>{
    'left': formatXmlDouble(m.left),
    'right': formatXmlDouble(m.right),
    'top': formatXmlDouble(m.top),
    'bottom': formatXmlDouble(m.bottom),
    'header': formatXmlDouble(m.header),
    'footer': formatXmlDouble(m.footer),
  });
  // CT_PageSetup order: paperSize, scale, firstPageNumber, fitToWidth,
  // fitToHeight, pageOrder, orientation, blackAndWhite, draft,
  // useFirstPageNumber.
  final int? paper = setup.paperSize?.id;
  final int? scale = setup.scale;
  final int? first = setup.firstPageNumber;
  final XlsxOrientation? orientation = setup.orientation;
  final Map<String, String> attributes = <String, String>{
    if (paper != null && paper != 1) 'paperSize': '$paper',
    if (scale != null && scale != 100) 'scale': '$scale',
    'firstPageNumber': ?(first == null ? null : '$first'),
    // A missing axis is 0 (automatic); the schema default is 1.
    if (pageSetupFitsToPage(setup)) ...<String, String>{
      'fitToWidth': '${setup.fitToWidth ?? 0}',
      'fitToHeight': '${setup.fitToHeight ?? 0}',
    },
    if (setup.pageOrder == XlsxPageOrder.overThenDown)
      'pageOrder': 'overThenDown',
    'orientation': ?orientation?.name,
    if (setup.blackAndWhite) 'blackAndWhite': '1',
    if (setup.draft) 'draft': '1',
    if (first != null) 'useFirstPageNumber': '1',
  };
  if (attributes.isNotEmpty) w.empty('pageSetup', attributes);
}
