/// The formatting of tables, rows and cells: the table's style, width,
/// layout, alignment, indentation, borders, cell margins and look; a row's
/// height, split and header rules; a cell's width, span, merge, alignment,
/// shading, borders and text direction.
///
/// Not ported from Quds; written for jet_office.
///
/// [DocxTableProperties], [DocxTableRowProperties] and
/// [DocxTableCellProperties] are views over the `w:tblPr`, `w:trPr` and
/// `w:tcPr` of a table, a row and a cell as read, in the shape of
/// `DocxParagraphProperties`: each member is a nullable getter and setter,
/// `null` meaning "not set here", a value the model cannot type reads `null`
/// and stays in the file, setting what a member reads is a no-op, and a set
/// writes one element in the place the schema gives, among the children the
/// model does not type. A table, row or cell read without the element
/// writes one in its place when a value is first set (`w:tblPr` before the
/// grid and the rows, `w:trPr` after any `w:tblPrEx` and before the cells,
/// `w:tcPr` first in the cell); one read in another place stays there and
/// the new one is written in the schema's place (plan Ruling 8).
///
/// Lengths are points; a value is rounded to the file's unit and reads back
/// rounded.
library;

import '../properties.dart';
import '../property_codec.dart';
import '../table_property_codecs.dart';
import '../units.dart';
import 'edit_sink.dart';
import 'formatting.dart';
import 'property_set.dart';
import 'styles.dart' show DocxStyleType;
import 'table_formatting.dart';

/// The most columns a table has through the API: Word's limit of 63. A
/// `w:gridSpan` set is checked against it ([DocxTableCellProperties.gridSpan]),
/// and a merge too; a file may hold more, and reads.
const int maxTableColumns = 63;

/// A property of a table, to name it for [DocxTableProperties.clear].
enum DocxTableProperty {
  /// The table style, [DocxTableProperties.style] (`w:tblStyle`).
  style('tblStyle'),

  /// The width, [DocxTableProperties.width] (`w:tblW`).
  width('tblW'),

  /// The layout, [DocxTableProperties.layout] (`w:tblLayout`).
  layout('tblLayout'),

  /// The alignment, [DocxTableProperties.alignment] (`w:jc`).
  alignment('jc'),

  /// The indentation, [DocxTableProperties.indentationPt] (`w:tblInd`).
  indentation('tblInd'),

  /// The borders, [DocxTableProperties.borders] (`w:tblBorders`).
  borders('tblBorders'),

  /// The default cell margins, [DocxTableProperties.cellMargins]
  /// (`w:tblCellMar`).
  cellMargins('tblCellMar'),

  /// The table look, [DocxTableProperties.look] (`w:tblLook`).
  look('tblLook');

  const DocxTableProperty(this._element);

  final String _element;
}

/// A property of a row, to name it for [DocxTableRowProperties.clear].
enum DocxTableRowProperty {
  /// The height, [DocxTableRowProperties.height] (`w:trHeight`).
  height('trHeight'),

  /// Whether the row may not split across pages,
  /// [DocxTableRowProperties.cantSplit] (`w:cantSplit`).
  cantSplit('cantSplit'),

  /// Whether the row repeats as a header,
  /// [DocxTableRowProperties.repeatAsHeader] (`w:tblHeader`).
  repeatAsHeader('tblHeader');

  const DocxTableRowProperty(this._element);

  final String _element;
}

/// A property of a cell, to name it for [DocxTableCellProperties.clear].
enum DocxTableCellProperty {
  /// The width, [DocxTableCellProperties.width] (`w:tcW`).
  width('tcW'),

  /// The number of grid columns spanned, [DocxTableCellProperties.gridSpan]
  /// (`w:gridSpan`).
  gridSpan('gridSpan'),

  /// The vertical merge, [DocxTableCellProperties.verticalMerge]
  /// (`w:vMerge`).
  verticalMerge('vMerge'),

  /// The vertical alignment, [DocxTableCellProperties.verticalAlignment]
  /// (`w:vAlign`).
  verticalAlignment('vAlign'),

  /// The shading, [DocxTableCellProperties.shading] (`w:shd`).
  shading('shd'),

  /// The borders, [DocxTableCellProperties.borders] (`w:tcBorders`).
  borders('tcBorders'),

  /// The text direction, [DocxTableCellProperties.textDirection]
  /// (`w:textDirection`).
  textDirection('textDirection');

  const DocxTableCellProperty(this._element);

  final String _element;
}

/// The properties of a table (`w:tblPr`).
///
/// Get one from `DocxTable.properties`; it is the same object every time.
/// Each set is one change of the document's change log.
final class DocxTableProperties {
  DocxTableProperties._(PropertyContainer source, DocxEditSink Function() sink)
    : _set = _TableSet(source, sink);

  final PropertySet _set;

  /// The id of the table's style (`w:tblStyle`), or `null`.
  ///
  /// The rules are those of `DocxParagraphProperties.style`, with the
  /// styles of a table: on a table in a document, the id set is resolved
  /// against the document's table styles (`TableGrid` becomes the id the
  /// document has for it, whatever its language, and the built-in is added
  /// when the document lacks it); any other id is kept and reported at save.
  /// Setting the empty string, or an id holding a character XML forbids,
  /// throws [ArgumentError]; `null` removes the style.
  String? get style => _set.valueOf('tblStyle') as String?;

  set style(String? value) {
    checkStyleId(value);
    _set.setStyleId('tblStyle', value, DocxStyleType.table);
  }

  /// The width (`w:tblW`), or `null`.
  DocxTableWidth? get width => _set.valueOf('tblW') as DocxTableWidth?;

  set width(DocxTableWidth? value) => _set.setValue('tblW', value);

  /// How the columns are laid out (`w:tblLayout`), or `null`.
  DocxTableLayout? get layout => _set.valueOf('tblLayout') as DocxTableLayout?;

  set layout(DocxTableLayout? value) => _set.setValue('tblLayout', value);

  /// How the table lines up between the margins (`w:jc`), or `null`.
  DocxTableAlignment? get alignment =>
      _set.valueOf('jc') as DocxTableAlignment?;

  set alignment(DocxTableAlignment? value) => _set.setValue('jc', value);

  /// The indentation from the margin, in points (`w:tblInd`), or `null`.
  ///
  /// It may be negative, to -1584; one in another unit than `dxa` reads
  /// `null` and is written back as read. A value is stored in twips.
  /// Throws [ArgumentError] for a value that is not finite and [RangeError]
  /// for one out of range once rounded.
  double? get indentationPt => _set.valueOf('tblInd') as double?;

  set indentationPt(double? value) {
    _set.setValue(
      'tblInd',
      value == null
          ? null
          : ptOfTwips(
              twipsOf(value, 'indentationPt', min: -maxTwips, max: maxTwips),
            ),
    );
  }

  /// The borders (`w:tblBorders`), or `null`.
  DocxTableBorders? get borders =>
      _set.valueOf('tblBorders') as DocxTableBorders?;

  set borders(DocxTableBorders? value) => _set.setValue('tblBorders', value);

  /// The default margins inside the cells (`w:tblCellMar`), or `null`.
  DocxTableMargins? get cellMargins =>
      _set.valueOf('tblCellMar') as DocxTableMargins?;

  set cellMargins(DocxTableMargins? value) =>
      _set.setValue('tblCellMar', value);

  /// Which parts of the table style apply (`w:tblLook`), or `null`.
  DocxTableLook? get look => _set.valueOf('tblLook') as DocxTableLook?;

  set look(DocxTableLook? value) => _set.setValue('tblLook', value);

  /// Removes [property] from the table, whatever the getter reads of it,
  /// so a child the model cannot type goes too. Nothing is recorded when
  /// the table has no such child.
  void clear(DocxTableProperty property) => _set.clearChild(property._element);
}

/// The properties of a table row (`w:trPr`).
///
/// Get one from `DocxTableRow.properties`; it is the same object every
/// time. Each set is one change of the document's change log.
final class DocxTableRowProperties {
  DocxTableRowProperties._(
    PropertyContainer source,
    DocxEditSink Function() sink,
  ) : _set = _RowSet(source, sink);

  final PropertySet _set;

  /// The height (`w:trHeight`), or `null`.
  DocxRowHeight? get height => _set.valueOf('trHeight') as DocxRowHeight?;

  set height(DocxRowHeight? value) => _set.setValue('trHeight', value);

  /// Whether the row stays on one page (`w:cantSplit`), or `null`. `false`
  /// is written as `w:val="0"`.
  bool? get cantSplit => _set.valueOf('cantSplit') as bool?;

  set cantSplit(bool? value) => _set.setValue('cantSplit', value);

  /// Whether the row is repeated at the top of each page the table spans
  /// (`w:tblHeader`), or `null`. `false` is written as `w:val="0"`.
  ///
  /// Word repeats only an unbroken run of header rows from the first row of
  /// the table; the model does not check that.
  bool? get repeatAsHeader => _set.valueOf('tblHeader') as bool?;

  set repeatAsHeader(bool? value) => _set.setValue('tblHeader', value);

  /// Removes [property] from the row, whatever the getter reads of it.
  /// Nothing is recorded when the row has no such child.
  void clear(DocxTableRowProperty property) =>
      _set.clearChild(property._element);
}

/// The properties of a table cell (`w:tcPr`).
///
/// Get one from `DocxTableCell.properties`; it is the same object every
/// time. Each set is one change of the document's change log.
final class DocxTableCellProperties {
  DocxTableCellProperties._(
    PropertyContainer source,
    DocxEditSink Function() sink,
    this._checkGridSpan,
    this._checkContinuation,
  ) : _set = _CellSet(source, sink);

  final PropertySet _set;

  /// Throws when a span the cell would change to does not fit where it is.
  final void Function(int span) _checkGridSpan;

  /// Throws when the cell has nothing above to continue.
  final void Function() _checkContinuation;

  /// The width (`w:tcW`), or `null`.
  DocxTableWidth? get width => _set.valueOf('tcW') as DocxTableWidth?;

  set width(DocxTableWidth? value) => _set.setValue('tcW', value);

  /// How many grid columns the cell spans (`w:gridSpan`), or `null`.
  ///
  /// A file may hold a span past [maxTableColumns], or one that does not fit
  /// its grid, and it reads. Setting a span outside 1 to [maxTableColumns]
  /// throws [RangeError].
  ///
  /// In a row of a table with a grid, a wider span must fit: the spans of the
  /// row with its `w:gridBefore` and `w:gridAfter` may not be more than the
  /// columns of the grid, or [ArgumentError] is thrown. Remove the cells it
  /// takes the place of first, or use `DocxTable.mergeCells`, which does both.
  ///
  /// A span that changes, wider or narrower, `null` and
  /// [DocxTableCellProperty.gridSpan] of [clear] included, must also leave
  /// vertical merges in line, or [ArgumentError] is thrown: a cell that
  /// continues one keeps the columns of the cell above it, and a cell that
  /// the row below continues keeps its own, for the cell itself and those it
  /// moves along the row. So to build a merge by hand, set the spans first
  /// and then [verticalMerge], from the top row down.
  ///
  /// A cell in no table is not checked; a row is when it goes in one
  /// (`DocxTable.insertRowAt`), and a cell (`DocxTableRow.insertCellAt`).
  int? get gridSpan => _set.valueOf('gridSpan') as int?;

  set gridSpan(int? value) {
    if (value != null) {
      RangeError.checkValueInInterval(value, 1, maxTableColumns, 'gridSpan');
    }
    _checkGridSpan(value ?? 1);
    _set.setValue('gridSpan', value);
  }

  /// The part the cell takes in a vertical merge (`w:vMerge`), or `null`.
  ///
  /// Setting [DocxVerticalMerge.continuation] on a cell of a row of a table
  /// throws [ArgumentError] unless the row above has a cell of the same
  /// columns; a file may hold one with nothing to continue, and it reads. Set
  /// it after the spans of the merge: [gridSpan] has the rule.
  DocxVerticalMerge? get verticalMerge =>
      _set.valueOf('vMerge') as DocxVerticalMerge?;

  set verticalMerge(DocxVerticalMerge? value) {
    if (value == DocxVerticalMerge.continuation && value != verticalMerge) {
      _checkContinuation();
    }
    _set.setValue('vMerge', value);
  }

  /// How the content lines up between the top and the bottom (`w:vAlign`),
  /// or `null`.
  DocxCellAlignment? get verticalAlignment =>
      _set.valueOf('vAlign') as DocxCellAlignment?;

  set verticalAlignment(DocxCellAlignment? value) =>
      _set.setValue('vAlign', value);

  /// The shading behind the cell (`w:shd`), or `null`.
  DocxShading? get shading => _set.valueOf('shd') as DocxShading?;

  set shading(DocxShading? value) => _set.setValue('shd', value);

  /// The borders (`w:tcBorders`), or `null`.
  DocxCellBorders? get borders => _set.valueOf('tcBorders') as DocxCellBorders?;

  set borders(DocxCellBorders? value) => _set.setValue('tcBorders', value);

  /// The direction of the text (`w:textDirection`), or `null`.
  DocxTextDirection? get textDirection =>
      _set.valueOf('textDirection') as DocxTextDirection?;

  set textDirection(DocxTextDirection? value) =>
      _set.setValue('textDirection', value);

  /// Removes [property] from the cell, whatever the getter reads of it.
  /// Nothing is recorded when the cell has no such child. Clearing
  /// [DocxTableCellProperty.gridSpan] is checked as [gridSpan] is.
  void clear(DocxTableCellProperty property) {
    if (property == DocxTableCellProperty.gridSpan) _checkGridSpan(1);
    _set.clearChild(property._element);
  }
}

/// The table properties over [source] (a table's `w:tblPr` as read, or an
/// empty container); edits go to the sink [sink] gives.
DocxTableProperties newTableProperties(
  PropertyContainer source,
  DocxEditSink Function() sink,
) => DocxTableProperties._(source, sink);

/// The row properties over [source]; edits go to the sink [sink] gives.
DocxTableRowProperties newTableRowProperties(
  PropertyContainer source,
  DocxEditSink Function() sink,
) => DocxTableRowProperties._(source, sink);

/// The cell properties over [source]; edits go to the sink [sink] gives.
/// [checkGridSpan] throws for a new span that does not fit where the cell is,
/// and [checkContinuation] for a cell with nothing above to continue.
DocxTableCellProperties newTableCellProperties(
  PropertyContainer source,
  DocxEditSink Function() sink, {
  required void Function(int span) checkGridSpan,
  required void Function() checkContinuation,
}) => DocxTableCellProperties._(source, sink, checkGridSpan, checkContinuation);

/// The property set behind [properties], for the writer. Not exported.
PropertySet propertySetOfTableProperties(DocxTableProperties properties) =>
    properties._set;

/// The property set behind [properties], for the writer. Not exported.
PropertySet propertySetOfTableRowProperties(
  DocxTableRowProperties properties,
) => properties._set;

/// The property set behind [properties], for the writer. Not exported.
PropertySet propertySetOfTableCellProperties(
  DocxTableCellProperties properties,
) => properties._set;

final class _TableSet extends PropertySet {
  _TableSet(PropertyContainer source, DocxEditSink Function() sink)
    : super(source, tablePropertiesSchema, sink);
}

final class _RowSet extends PropertySet {
  _RowSet(PropertyContainer source, DocxEditSink Function() sink)
    : super(source, tableRowPropertiesSchema, sink);
}

final class _CellSet extends PropertySet {
  _CellSet(PropertyContainer source, DocxEditSink Function() sink)
    : super(source, tableCellPropertiesSchema, sink);
}
