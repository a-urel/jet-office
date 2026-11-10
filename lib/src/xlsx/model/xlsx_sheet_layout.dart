/// The row, column and default size layout of an [XlsxSheet]: the members
/// that read and set `rowFormat`, `column` and `defaultSizes`.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetLayout] in, so these are members of the sheet.
part of 'xlsx_sheet.dart';

/// Moves [sheet]'s cells, row formats and column runs for [edit], a row or
/// column edit of this sheet, in one transaction.
///
/// It runs after the reference holders, which work on the positions before
/// the edit: the cells move by block, as one change ([moveStoredCells]),
/// and the cells the edit deletes go, a shared master a holder promoted
/// away from among them. Inserted rows take the format of the row above
/// (Excel's "Format same as above": its style and height, not `hidden` or
/// `collapsed`); the `<cols>` runs split, shift and shrink
/// ([shiftColumnRuns]), inserted columns taking the column to the left's.
/// The `<dimension>` and each row's `spans` are recomputed on save. Throws
/// a [StateError] when an insert would push a cell off the sheet, or the
/// sheet is not a worksheet; nothing changes then.
void moveSheetGeometry(XlsxSheet sheet, ReferenceShift edit) {
  final bool rows = edit.axis == ShiftAxis.rows;
  final WorksheetPart part = sheet._editablePart(rows ? 'rows' : 'columns');
  final CellStore store = part.cells;
  final ChangeLog log = sheet._host.log;
  final int from = edit.index - 1;
  log.transaction(() {
    moveStoredCells(log, store, rows: rows, from: from, delta: edit.count);
    if (rows) {
      if (edit.count > 0 && from > 0) _copyRowFormat(log, store, from, edit);
      return;
    }
    if (!part.columnsEditable || part.columnRuns.isEmpty) return;
    final List<ColRun> next = shiftColumnRuns(
      part.columnRuns,
      edit.index,
      edit.count,
    );
    if (sameRuns(part.columnRuns, next)) return;
    editLayout(log, part, 'cols', () => part.setColumnRuns(next));
  });
}

/// Gives the rows [edit] inserted at [from] the format of the row above.
void _copyRowFormat(
  ChangeLog log,
  CellStore store,
  int from,
  ReferenceShift edit,
) {
  final List<KeptAttribute> format = insertedFormat(
    store.rowAttributes(from - 1),
  );
  const Set<String> formatting = <String>{
    's',
    'customFormat',
    'ht',
    'customHeight',
    'outlineLevel',
  };
  if (!format.any(
    (KeptAttribute a) =>
        a.namespaceUri.isEmpty && formatting.contains(a.qualifiedName),
  )) {
    return;
  }
  final int end = from + edit.count > XlsxLimits.maxRows
      ? XlsxLimits.maxRows
      : from + edit.count;
  for (int row = from; row < end; row++) {
    setStoredRowAttributes(log, store, row, format);
  }
}

/// The layout half of [XlsxSheet].
mixin _SheetLayout {
  // What the sheet gives its layout half.
  SheetHost get _host;
  String get name;
  Set<String> get _layoutReported;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);
  CellStore _editableCells(String what);
  StylesPart _stylesFor();
  StateError _untypedStyles();
  XlsxStyle? _styleOfIndex(int? index);
  void _warn(XlsxWarningCode code, String? cell, {String? detail});

  /// How [row] looks: its height, visibility, outline level, collapsed mark
  /// and style, read from the row's `ht` (with `customHeight`), `hidden`,
  /// `outlineLevel`, `collapsed` and `s` (with `customFormat`).
  ///
  /// A row the file lacks has the default format. An `ht` without
  /// `customHeight="1"` is Excel's automatic height, so `height` is `null`;
  /// the style is read as [XlsxSheet.styleAt] reads a row's. An attribute
  /// that cannot be read (an `ht` of `abc`, an outline level of 9) reads as
  /// its default and is reported once (`layoutInvalid`); it is saved as
  /// written until [setRowFormat] sets that field. Loads the sheet. Throws a
  /// [RangeError] outside Excel's rows and an [XlsxReadException] when the
  /// sheet cannot be read.
  XlsxRowFormat rowFormat(int row) {
    RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
    final CellStore? store = _load()?.cells;
    if (store == null) return const XlsxRowFormat();
    return _readRowFormat(store, row);
  }

  /// Sets how [row] looks to exactly [format].
  ///
  /// The row keeps its cells and every attribute the format does not cover
  /// (`x14ac:dyDescent`, `thickBot`, ...); a field equal to the row's
  /// current one is left as written, even when it cannot be read. A new
  /// attribute is written as the writer writes a row (`ht` with
  /// `customHeight="1"`, `hidden="1"`, `outlineLevel`, `collapsed="1"`, and
  /// the style as `s` with `customFormat="1"`); a changed one is replaced
  /// where it stood. A style is appended to the styles when no cell format
  /// matches it, so no existing index moves, and a style that is the default
  /// writes no `s`. A row left with no cells, no attributes and no other
  /// content is removed. On save, `sheetFormatPr/@outlineLevelRow` is the
  /// larger of the kept value and the deepest row outline level.
  ///
  /// Throws an [ArgumentError] named `height` for a height outside 0 to
  /// 409.5 (or not finite) or `outlineLevel` for a level outside 0 to 7, an
  /// [ArgumentError] naming the field of an invalid style and an
  /// `XlsxLimitError` past the writer's limits, a [StateError] for a sheet
  /// that is not a worksheet or has no part and, when [XlsxRowFormat.style]
  /// changes, when the styles part is not a SpreadsheetML `styleSheet`, a
  /// [RangeError] outside Excel's rows, and an [XlsxReadException] when the
  /// sheet cannot be read. Whatever it throws, nothing has changed, except
  /// that reading warnings are reported on first read.
  void setRowFormat(int row, XlsxRowFormat format) => _recordSheetEdit(
    this,
    XlsxChangeKind.featureChanged,
    index: row,
    count: 1,
    () {
      RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
      final double? height = format.height;
      if (height != null) checkRowHeight(height, 'height');
      checkOutlineLevel(format.outlineLevel, 'outlineLevel');
      final CellStore store = _editableCells('row formats');
      final StylesPart? loaded = _host.styles;
      if (loaded != null && !loaded.isTyped && format.style != null) {
        throw _untypedStyles();
      }
      final XlsxRowFormat current = _readRowFormat(store, row);
      if (current == format) return;
      final bool styleChanged = format.style != current.style;
      final StylesPart? styles = styleChanged && format.style != null
          ? _stylesFor()
          : null;
      final List<KeptAttribute> old = store.rowAttributes(row);
      final ChangeLog log = _host.log;
      log.transaction(() {
        final int id = styles == null
            ? 0
            : appendStyle(log, styles, format.style);
        final List<KeptAttribute> next = _rowAttributesFor(
          old,
          current,
          format,
          styleId: styleChanged ? id : null,
        );
        if (sameAttributes(old, next)) return;
        setStoredRowAttributes(log, store, row, next);
      });
    },
  );

  /// How column [index] (0 for A) looks: its width, style, visibility,
  /// outline level and collapsed mark, read from the `<col>` holding it
  /// (`width`, `style`, `hidden`, `outlineLevel`, `collapsed`), or `null`
  /// for a default column.
  ///
  /// A column no `<col>` holds, and one whose `<col>` sets nothing the
  /// model reads, is a default column. The `width` is read whenever it is a
  /// width, with or without `customWidth="1"` (which only says whether the
  /// width was set by hand), so the columns the writer wrote without a width
  /// read the default width, 9.140625. The style is read as
  /// [XlsxSheet.styleAt] reads a row's. An attribute that cannot be read (a
  /// `width` of `abc`, an outline level of 9) reads as its default and is
  /// reported once (`layoutInvalid`); it is saved as written until
  /// [setColumn] sets that field. A `<cols>` that is not plain (see
  /// [setColumn]) reads as no columns. Loads the sheet. Throws a
  /// [RangeError] outside Excel's columns and an [XlsxReadException] when
  /// the sheet cannot be read.
  XlsxColumn? column(int index) {
    RangeError.checkValueInInterval(
      index,
      0,
      XlsxLimits.maxColumns - 1,
      'index',
    );
    final ColRun? run = _load()?.columnRunAt(index + 1);
    if (run == null) return null;
    final XlsxColumn column = _readColumn(run);
    return column == const XlsxColumn() ? null : column;
  }

  /// Sets how column [index] (0 for A) looks to exactly [column]; `null`,
  /// like an [XlsxColumn] that sets nothing, resets it to the default.
  ///
  /// The `<col>` holding the column is split into up to three, the columns
  /// before it, the column itself and the columns after it, and the outer
  /// runs keep every attribute (`bestFit`, ...); a column of the same
  /// `<col>` as a neighbour joins it again. The column keeps every attribute
  /// the column does not cover; a field equal to the current one is left as
  /// written, even when it cannot be read, and setting a column to what
  /// [column] reads changes nothing. A new attribute is written as the
  /// writer writes a `<col>` (`width` always, then `style`, `hidden`,
  /// `customWidth="1"`, `outlineLevel`, `collapsed="1"`); a changed one is
  /// replaced where it stood. A width equal to the current one is left as
  /// written, `customWidth` included; a width reset to `null` writes the
  /// sheet's default column width without `customWidth`. A style is
  /// appended to the styles when no cell format matches it, so no existing
  /// index moves. A `<cols>` left with no `<col>` is removed, and a sheet
  /// without one gets it in schema position. On save,
  /// `sheetFormatPr/@outlineLevelCol` is the larger of the kept value and
  /// the deepest column outline level, made when needed.
  ///
  /// Only the first `<cols>` is edited, and only when it is plain: its
  /// `<col>` elements have no children or declarations of their own, whole
  /// `min` and `max` inside the grid, and are sorted and do not overlap.
  /// Any other `<cols>` is kept as written, and [setColumn] throws a
  /// [StateError].
  ///
  /// Throws an [ArgumentError] named `column.width` for a width outside 0
  /// to 255 (or not finite) or `column.outlineLevel` for a level outside 0
  /// to 7, an [ArgumentError] naming the field of an invalid style
  /// (`column.style.font.name`, ...) and an `XlsxLimitError` past the
  /// writer's limits, a [StateError] for a sheet that is not a worksheet or
  /// has no part, for a `<cols>` that is not plain and, when
  /// [XlsxColumn.style] changes, when the styles part is not a
  /// SpreadsheetML `styleSheet`, a [RangeError] outside Excel's columns, and
  /// an [XlsxReadException] when the sheet cannot be read. Whatever it
  /// throws, nothing has changed, except that reading warnings are reported
  /// on first read.
  void setColumn(int index, XlsxColumn? column) => _recordSheetEdit(
    this,
    XlsxChangeKind.featureChanged,
    index: index,
    count: 1,
    () {
      RangeError.checkValueInInterval(
        index,
        0,
        XlsxLimits.maxColumns - 1,
        'index',
      );
      if (column != null) {
        final double? width = column.width;
        if (width != null) checkColumnWidth(width, 'column.width');
        checkOutlineLevel(column.outlineLevel, 'column.outlineLevel');
      }
      final WorksheetPart part = _editablePart('columns');
      if (!part.columnsEditable) {
        throw StateError(
          'The sheet "$name" has a <cols> that is not plain (a <col> with '
          'children, an invalid or overlapping range, ...); its columns '
          'cannot be set.',
        );
      }
      final StylesPart? loaded = _host.styles;
      if (loaded != null && !loaded.isTyped && column?.style != null) {
        throw _untypedStyles();
      }
      final ColRun? run = part.columnRunAt(index + 1);
      final XlsxColumn current = run == null
          ? const XlsxColumn()
          : _readColumn(run);
      final XlsxColumn next = column ?? const XlsxColumn();
      if (current == next) return;
      final bool styleChanged = next.style != current.style;
      final StylesPart? styles = styleChanged && next.style != null
          ? _stylesFor()
          : null;
      final String defaultWidth = formatXmlDouble(_defaultColumnWidth(part));
      final ChangeLog log = _host.log;
      log.transaction(() {
        int id = 0;
        if (styles != null) {
          try {
            id = appendStyle(log, styles, next.style);
          } on ArgumentError catch (error, stack) {
            final String? field = error.name;
            Error.throwWithStackTrace(
              ArgumentError.value(
                error.invalidValue,
                field == null ? 'column.style' : 'column.style.$field',
                error.message,
              ),
              stack,
            );
          }
        }
        editLayout(log, part, 'cols', () {
          final List<ColRun> runs = setColumnInRuns(
            part.columnRuns,
            index + 1,
            '${part.elementPrefix}col',
            (List<KeptAttribute>? old) => next == const XlsxColumn()
                ? null
                : _columnAttributesFor(
                    old,
                    current,
                    next,
                    styleId: styleChanged ? id : null,
                    defaultWidth: defaultWidth,
                  ),
          );
          // A column that reads differently can still write the same <col>.
          if (!sameRuns(part.columnRuns, runs)) part.setColumnRuns(runs);
        });
      });
    },
  );

  /// The column a `<col>` describes, reporting what cannot be read.
  XlsxColumn _readColumn(ColRun run) {
    final String element = run.min == run.max
        ? 'column ${columnName(run.min - 1)}'
        : 'columns ${columnName(run.min - 1)}:${columnName(run.max - 1)}';
    String? width;
    bool hidden = false;
    bool collapsed = false;
    int outlineLevel = 0;
    int? styleIndex;
    for (final KeptAttribute a in run.attributes) {
      if (a.namespaceUri.isNotEmpty) continue;
      final String v = a.value;
      switch (a.qualifiedName) {
        case 'width':
          width = v;
        case 'customWidth':
          // Only whether the width is written; reported when unreadable.
          _layoutBool(element, 'customWidth', v);
        case 'hidden':
          hidden = _layoutBool(element, 'hidden', v) ?? false;
        case 'collapsed':
          collapsed = _layoutBool(element, 'collapsed', v) ?? false;
        case 'outlineLevel':
          final int? level = parseOutlineLevel(v);
          outlineLevel = level ?? 0;
          if (level == null) {
            _layoutProblem(
              element,
              'outlineLevel "$v" is not an outline level from 0 to '
              '${XlsxLimits.maxOutlineLevel}.',
            );
          }
        case 'style':
          styleIndex = parseStyleIndex(v);
          if (styleIndex == null) {
            _layoutProblem(element, 'style "$v" is not a cell format index.');
          }
      }
    }
    double? custom;
    if (width != null) {
      final double? w = _plainNumber.hasMatch(width)
          ? double.tryParse(width)
          : null;
      if (w == null || !w.isFinite || w < 0 || w > XlsxLimits.maxColumnWidth) {
        _layoutProblem(element, 'width "$width" is not a column width.');
      } else {
        custom = w;
      }
    }
    return XlsxColumn(
      width: custom,
      style: _styleOfIndex(styleIndex),
      hidden: hidden,
      outlineLevel: outlineLevel,
      collapsed: collapsed,
    );
  }

  /// The attributes [next] gives a `<col>` whose attributes were [old]
  /// (`null` for a new one) and whose column was [current]: each changed
  /// field replaced where it stood, or added in the writer's order after
  /// the others, and `width` (which the schema requires) always.
  ///
  /// [styleId] is the cell format index of a changed style (0 for none);
  /// `null` leaves the style attribute as it is.
  static List<KeptAttribute> _columnAttributesFor(
    List<KeptAttribute>? old,
    XlsxColumn current,
    XlsxColumn next, {
    required int? styleId,
    required String defaultWidth,
  }) {
    final bool created = old == null;
    final bool widthChanged = created || next.width != current.width;
    final Map<String, String?> changed = <String, String?>{};
    if (widthChanged) {
      final double? w = next.width;
      changed['width'] = w == null ? defaultWidth : formatXmlDouble(w);
    }
    if (styleId != null) {
      changed['style'] = styleId == 0 ? null : '$styleId';
    }
    if (next.hidden != current.hidden) {
      changed['hidden'] = next.hidden ? '1' : null;
    }
    if (widthChanged) {
      changed['customWidth'] = next.width == null ? null : '1';
    }
    if (next.outlineLevel != current.outlineLevel) {
      changed['outlineLevel'] = next.outlineLevel == 0
          ? null
          : '${next.outlineLevel}';
    }
    if (next.collapsed != current.collapsed) {
      changed['collapsed'] = next.collapsed ? '1' : null;
    }
    final List<KeptAttribute> attributes = replaceAttributes(
      old ?? const <KeptAttribute>[],
      changed,
    );
    if (attributes.any(
      (KeptAttribute a) => a.namespaceUri.isEmpty && a.qualifiedName == 'width',
    )) {
      return attributes;
    }
    return <KeptAttribute>[
      (qualifiedName: 'width', namespaceUri: '', value: defaultWidth),
      ...attributes,
    ];
  }

  /// The sheet's default column width: its `defaultColWidth` when that is a
  /// column width, else Excel's standard one, as the writer writes it.
  static double _defaultColumnWidth(WorksheetPart part) {
    final String? text = part.sheetFormatAttribute('defaultColWidth');
    final double? width = text != null && _plainNumber.hasMatch(text)
        ? double.tryParse(text)
        : null;
    return width != null && width.isFinite && _isColumnWidth(width)
        ? width
        : standardColumnWidth;
  }

  static bool _isColumnWidth(double width) =>
      width >= 0 && width <= XlsxLimits.maxColumnWidth;

  /// The sheet's default row height in points and default column width in
  /// characters, or `null` for each that the sheet leaves to Excel.
  ///
  /// They are read from `sheetFormatPr`: the row height is `defaultRowHeight`
  /// when `customHeight="1"` (Excel's own default is not a setting), the
  /// column width is `defaultColWidth`; `baseColWidth` is not read. An
  /// attribute that cannot be read reads as `null` and is reported once
  /// (`layoutInvalid`). Loads the sheet. Throws an [XlsxReadException] when
  /// the sheet cannot be read.
  ({double? rowHeight, double? columnWidth}) get defaultSizes {
    final WorksheetPart? part = _load();
    if (part == null) return (rowHeight: null, columnWidth: null);
    return _readDefaultSizes(part);
  }

  ({double? rowHeight, double? columnWidth}) _readDefaultSizes(
    WorksheetPart part,
  ) {
    const String element = 'sheetFormatPr';
    double? number(String name, num max) {
      final String? text = part.sheetFormatAttribute(name);
      if (text == null) return null;
      final double? v = _plainNumber.hasMatch(text)
          ? double.tryParse(text)
          : null;
      if (v == null || !v.isFinite || v < 0 || v > max) {
        _layoutProblem(element, '$name "$text" is not a size.');
        return null;
      }
      return v;
    }

    final double? height = number('defaultRowHeight', XlsxLimits.maxRowHeight);
    final String? custom = part.sheetFormatAttribute('customHeight');
    final bool customHeight = custom == null
        ? false
        : _layoutBool(element, 'customHeight', custom) ?? false;
    return (
      rowHeight: customHeight ? height : null,
      columnWidth: number('defaultColWidth', XlsxLimits.maxColumnWidth),
    );
  }

  /// Sets the sheet's default row height and default column width to
  /// exactly [rowHeight] and [columnWidth]; `null` is Excel's own.
  ///
  /// They are written as the writer's `defaultSizes` writes them:
  /// `defaultRowHeight` with `customHeight="1"` and `defaultColWidth`. A
  /// size equal to the current one is left as written; the rest of
  /// `sheetFormatPr` (`baseColWidth`, ...) is kept, and a sheet without the
  /// element gets it in schema position. A `sheetFormatPr` with element
  /// children is kept as written and cannot be edited.
  ///
  /// Throws an [ArgumentError] named `rowHeight` for a height outside 0 to
  /// 409.5 or `columnWidth` for a width outside 0 to 255 (or not finite), a
  /// [StateError] for a sheet that is not a worksheet or has no part and for
  /// a `sheetFormatPr` with element children, and an [XlsxReadException]
  /// when the sheet cannot be read. Whatever it throws, nothing has
  /// changed, except that reading warnings are reported on first read.
  void setDefaultSizes({double? rowHeight, double? columnWidth}) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        if (rowHeight != null) checkRowHeight(rowHeight, 'rowHeight');
        if (columnWidth != null) checkColumnWidth(columnWidth, 'columnWidth');
        final WorksheetPart part = _editablePart('default sizes');
        final ({double? rowHeight, double? columnWidth}) current =
            _readDefaultSizes(part);
        if (current.rowHeight == rowHeight &&
            current.columnWidth == columnWidth) {
          return;
        }
        if (!part.sheetFormatEditable) {
          throw StateError(
            'The sheet "$name" has a sheetFormatPr with element children; its '
            'default sizes cannot be set.',
          );
        }
        final Map<String, String?> changes = <String, String?>{};
        if (columnWidth != current.columnWidth) {
          changes['defaultColWidth'] = columnWidth == null
              ? null
              : formatXmlDouble(columnWidth);
        }
        if (rowHeight != current.rowHeight || !part.hasSheetFormat) {
          if (rowHeight != null) {
            changes['defaultRowHeight'] = formatXmlDouble(rowHeight);
            changes['customHeight'] = '1';
          } else {
            // As the writer writes no custom height: the standard one.
            changes['defaultRowHeight'] = formatXmlDouble(standardRowHeight);
            changes['customHeight'] = null;
          }
        }
        final ChangeLog log = _host.log;
        log.transaction(() {
          editLayout(
            log,
            part,
            'sheetFormatPr',
            () => part.changeSheetFormat(changes),
          );
        });
      });

  /// The format of [row] from its attributes, reporting what cannot be
  /// read.
  XlsxRowFormat _readRowFormat(CellStore store, int row) {
    final List<KeptAttribute> attributes = store.rowAttributes(row);
    if (attributes.isEmpty) return const XlsxRowFormat();
    final String element = 'row ${row + 1}';
    String? ht;
    bool customHeight = false;
    bool hidden = false;
    bool collapsed = false;
    int outlineLevel = 0;
    for (final KeptAttribute a in attributes) {
      if (a.namespaceUri.isNotEmpty) continue;
      final String v = a.value;
      switch (a.qualifiedName) {
        case 'ht':
          ht = v;
        case 'customHeight':
          customHeight = _layoutBool(element, 'customHeight', v) ?? false;
        case 'hidden':
          hidden = _layoutBool(element, 'hidden', v) ?? false;
        case 'collapsed':
          collapsed = _layoutBool(element, 'collapsed', v) ?? false;
        case 'outlineLevel':
          final int? level = _plainInt.hasMatch(v) ? int.tryParse(v) : null;
          if (level != null &&
              level >= 0 &&
              level <= XlsxLimits.maxOutlineLevel) {
            outlineLevel = level;
          } else {
            outlineLevel = 0;
            _layoutProblem(
              element,
              'outlineLevel "$v" is not an outline level from 0 to '
              '${XlsxLimits.maxOutlineLevel}.',
            );
          }
      }
    }
    double? height;
    if (ht != null) {
      final double? h = _plainNumber.hasMatch(ht) ? double.tryParse(ht) : null;
      if (h == null || !h.isFinite || h < 0 || h > XlsxLimits.maxRowHeight) {
        _layoutProblem(element, 'ht "$ht" is not a row height.');
      } else if (customHeight) {
        height = h;
      }
    }
    return XlsxRowFormat(
      height: height,
      hidden: hidden,
      outlineLevel: outlineLevel,
      collapsed: collapsed,
      style: _styleOfIndex(XlsxSheet._rowStyleIndex(store, row)),
    );
  }

  /// The attributes [format] gives a row whose attributes were [old] and
  /// whose format was [current]: each changed field replaced where it
  /// stood, or added in the writer's order after the others.
  ///
  /// [styleId] is the cell format index of a changed style (0 for none);
  /// `null` leaves the style attributes as they are.
  static List<KeptAttribute> _rowAttributesFor(
    List<KeptAttribute> old,
    XlsxRowFormat current,
    XlsxRowFormat format, {
    required int? styleId,
  }) {
    // The attributes that change, in the order the writer writes them
    // (`CT_Row`): an absent name is removed.
    final Map<String, String?> changed = <String, String?>{};
    if (styleId != null) {
      changed['s'] = styleId == 0 ? null : '$styleId';
      changed['customFormat'] = styleId == 0 ? null : '1';
    }
    if (format.height != current.height) {
      final double? h = format.height;
      changed['ht'] = h == null ? null : formatXmlDouble(h);
    }
    if (format.hidden != current.hidden) {
      changed['hidden'] = format.hidden ? '1' : null;
    }
    if (format.height != current.height) {
      changed['customHeight'] = format.height == null ? null : '1';
    }
    if (format.outlineLevel != current.outlineLevel) {
      changed['outlineLevel'] = format.outlineLevel == 0
          ? null
          : '${format.outlineLevel}';
    }
    if (format.collapsed != current.collapsed) {
      changed['collapsed'] = format.collapsed ? '1' : null;
    }
    return replaceAttributes(old, changed);
  }

  /// Reads a boolean attribute of [element]: `1` or `true`, `0` or
  /// `false`; anything else is reported and reads as `null`.
  bool? _layoutBool(String element, String name, String value) {
    switch (value) {
      case '1' || 'true':
        return true;
      case '0' || 'false':
        return false;
    }
    _layoutProblem(element, '$name "$value" is not a boolean.');
    return null;
  }

  /// Reports that an attribute of [element] (`row 3`, ...) cannot be read,
  /// once however often it is read.
  void _layoutProblem(String element, String problem) {
    final String detail = '$element: $problem';
    if (_layoutReported.add(detail)) {
      _warn(XlsxWarningCode.layoutInvalid, null, detail: detail);
    }
  }

  static final RegExp _plainInt = RegExp(r'^[+-]?\d+$');
  static final RegExp _plainNumber = RegExp(
    r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$',
  );
}
