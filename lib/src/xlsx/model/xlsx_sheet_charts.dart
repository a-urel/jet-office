/// The charts of an [XlsxSheet]: the members that list, add, replace, move
/// and remove them.
///
/// Not ported from Quds; written for jet_office (milestone C2).
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetCharts] in, so these are members of the sheet.
///
/// A chart is an anchor of the sheet's drawing part ([DrawingPart]) that
/// directly holds a graphic frame showing a chart part
/// (`xl/charts/chartN.xml`). The drawing is the one the pictures read
/// ([_PicturesRead]), with the drawing's chart relationships beside its
/// media. Each chart part is opened once as a [DrawingChart] and read lazily
/// by the DrawingML layer, which never throws; reading adds nothing to the
/// package's content, so every part is saved as written.
///
/// An edit is one recorded change, as a picture's is: it changes the
/// drawing's entries in place and creates and drops the drawing, the chart
/// parts and the parts only they relate to. A chart part the package holds is
/// never changed in place: a new chart is a new [DrawingChart] content, and
/// an undo gives the part its previous content back, so the listing, which
/// opens a part again once its content is another object, follows.
part of 'xlsx_sheet.dart';

/// The type of the relationship from a chart part to its chart style part
/// (`xl/charts/styleN.xml`), as Excel writes it.
const String _chartStyleType =
    'http://schemas.microsoft.com/office/2011/relationships/chartStyle';

/// The type of the relationship from a chart part to its chart colour style
/// part (`xl/charts/colorsN.xml`), as Excel writes it.
const String _chartColorStyleType =
    'http://schemas.microsoft.com/office/2011/relationships/chartColorStyle';

/// The change of the chart part the relationship [id] of the drawing names:
/// [before] gave way to [after], either `null` for none.
final class _DrawingChartChange implements Change {
  _DrawingChartChange(this.read, this.id, this.before, this.after);

  final _PicturesRead read;
  final String id;
  final String? before;
  final String? after;

  @override
  void revert() => _set(before);

  @override
  void reapply() => _set(after);

  void _set(String? name) {
    if (name == null) {
      read.charts.remove(id);
    } else {
      read.charts[id] = name;
    }
  }
}

/// The change of what the package writes for the chart part [name]: the
/// content [before] (`null` for the file's bytes) gave way to [after].
final class _ChartContentChange implements Change {
  _ChartContentChange(this.package, this.name, this.before, this.after);

  final OpcPackage package;
  final String name;
  final PartContent? before;
  final PartContent after;

  @override
  void revert() =>
      package.setContent(name, before ?? originalPartContent(package, name));

  @override
  void reapply() => package.setContent(name, after);
}

/// A chart part as the sheet opened it: its `chart`, or `null` when the part
/// could not be opened or is larger than `XlsxReadLimits.maxChartPartBytes`,
/// and the `source` it was opened from: the content the package held for the
/// part then (`OpcPackage.contentOf`), `null` for its original bytes.
typedef _ChartPartRead = ({DrawingChart? chart, PartContent? source});

/// The chart half of [XlsxSheet].
mixin _SheetCharts {
  // What the sheet gives its chart half.
  SheetHost get _host;
  Set<String> get _featureReported;
  void _warn(XlsxWarningCode code, String? cell, {String? detail});
  _PicturesRead _readPictures();

  // What the sheet's picture half gives it.
  String get name;
  void setCell(int row, int column, Object? value);
  WorksheetPart _editablePart(String what);
  _PicturesRead _editablePictures(WorksheetPart part, {String what});
  DrawingPart _addDrawing(WorksheetPart part, _PicturesRead read);
  void _attach(_PicturesRead read, DrawingPart drawing);
  String _freeRelationshipId(_PicturesRead read);
  Map<String, String> _relationshipTargets(String source);
  void _dropTarget(String target);
  void _dropDrawing(WorksheetPart part, _PicturesRead read);

  /// The chart parts opened, by part name (no leading `/`). An entry holds
  /// while the package holds the same content for the part: an edit that
  /// rewrites it (a structural edit's references, on any sheet), its undo and
  /// its redo give the part other content, and the part is opened again.
  final Map<String, _ChartPartRead> _chartParts = <String, _ChartPartRead>{};

  /// The charts of the sheet in file order.
  ///
  /// A chart is a `oneCellAnchor` or `twoCellAnchor` of the sheet's drawing
  /// that directly holds an `xdr:graphicFrame` whose `a:graphicData` shows a
  /// chart (`c:chart`) and whose `r:id` names a chart relationship of the
  /// drawing to a part of the file. Its anchor is in pixels, as a picture's.
  /// A chart inside a group or `mc:AlternateContent`, or under an absolute
  /// anchor, is kept as written and not listed, without a warning.
  ///
  /// Each part is read once, in the Office theme, with the colours of the
  /// workbook's theme and in the workbook's date system: [XlsxSheetChart.view]
  /// is what it shows, and [XlsxSheetChart.typed] its typed form when writing
  /// that form gives the part again (a kind the library does not write lists
  /// as a view only, without a warning). A chart written in another theme may
  /// list as a view only; the file does not record the theme.
  ///
  /// Never throws for a chart part itself. A frame whose `r:id` dangles or
  /// names a relationship that is not a chart's, or that has no `cNvPr` id,
  /// is kept and not listed; a part that is not a chart, or larger than
  /// `XlsxReadLimits.maxChartPartBytes`, lists with no view and no typed
  /// form and is kept byte for byte; a part with a number that cannot be
  /// read lists. Each is reported once per sheet as `featureEntryInvalid`
  /// with the detail `chart`.
  ///
  /// Unmodifiable. Loads the sheet. Throws an [XlsxReadException] when the
  /// sheet, its relationships or the drawing part cannot be read, and, when
  /// the drawing holds more objects than `XlsxReadLimits.maxMerges` allows,
  /// `limitExceeded`.
  List<XlsxSheetChart> get charts {
    final _PicturesRead read = _readPictures();
    final DrawingPart? drawing = read.part;
    if (drawing == null) return const <XlsxSheetChart>[];
    bool problem = false;
    final List<XlsxSheetChart> found = <XlsxSheetChart>[];
    for (final DrawingEntry e in drawing.entries) {
      final DrawingChartFrame? frame = e.chartFrame;
      final XlsxAnchor? anchor = e.anchor;
      if (frame == null || anchor == null) continue;
      final String? partName = read.charts[frame.chartId];
      if (partName == null) {
        problem = true;
        continue;
      }
      final DrawingChart? part = _chartPart(partName).chart;
      if (part == null) {
        problem = true;
        found.add(
          XlsxSheetChart(anchor, frame.name, description: frame.description),
        );
        continue;
      }
      final List<DrawingChartIssue> issues = part.issues;
      if (issues.contains(DrawingChartIssue.unreadable) ||
          issues.contains(DrawingChartIssue.badNumber)) {
        problem = true;
      }
      final DrawingChartSpace? space = part.typed;
      found.add(
        XlsxSheetChart(
          anchor,
          frame.name,
          description: frame.description,
          view: part.chart,
          typed: space == null
              ? null
              : readXlsxChart(
                  space,
                  anchor,
                  name: frame.name,
                  description: frame.description,
                ),
        ),
      );
    }
    if (problem && _featureReported.add('chart')) {
      _warn(XlsxWarningCode.featureEntryInvalid, null, detail: 'chart');
    }
    return List<XlsxSheetChart>.unmodifiable(found);
  }

  /// Adds [chart] after everything the sheet's drawing holds, creating the
  /// drawing when the sheet has none (as `addPicture` does).
  ///
  /// The chart gets the part `xl/charts/chart{n}.xml`, n the lowest number
  /// no part has, with a content type override, and the drawing a
  /// relationship to it, with the lowest `rId{m}` the drawing neither has nor
  /// names. The frame is an anchor as Excel writes it: a `twoCellAnchor`
  /// (with no `editAs` when the chart moves and sizes with its cells, else
  /// as a picture's) or a `oneCellAnchor`, holding a `graphicFrame` with a
  /// `cNvPr` id one above the highest of the drawing, at least 2, the name
  /// `Chart {k}` when [XlsxChart.name] is `null`, k being the chart's
  /// position in [charts] from 1, and an `xfrm` of zeros. The part is
  /// written in [XlsxChart.theme] and the workbook's date system, with the
  /// ids a chart read from a part carries (a listed [XlsxSheetChart.typed]
  /// added again is a copy, whose axis ids are its own part's), else the
  /// ids `xlsxChartPartIds` gives n, so the same calls give the same bytes.
  ///
  /// A value that is not a finite number is left out and warned about once
  /// as `chartValueOmitted`, characters XML forbids are removed from the
  /// text and warned about once as `invalidCharactersRemoved`, each with the
  /// chart's name as the detail.
  ///
  /// Throws an [ArgumentError] for a chart the writer cannot express (its
  /// kind, a secondary axis it cannot have, a theme value out of range), for
  /// an anchor as `addPicture` does, named `anchor` for a one-cell anchor
  /// without both a width and a height (a chart has no size of its own),
  /// and for a name or description holding a character XML forbids; a
  /// [StateError] for a sheet that is not a worksheet or has no part, and
  /// for a `<drawing>` whose part is missing or is not a spreadsheet drawing;
  /// and an [XlsxReadException] when the sheet, its relationships or the
  /// drawing cannot be read. Whatever it throws, nothing has changed.
  void addChart(XlsxChart chart) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        final WorksheetPart part = _editablePart('charts');
        final _PicturesRead read = _editablePictures(part, what: 'charts');
        final int k = _listedCharts(read).length + 1;
        final String frameName = chart.name ?? 'Chart $k';
        final ({int cx, int cy})? extent = checkChartFrame(
          chart.anchor,
          which: 'Chart $k on sheet "$name"',
          name: chart.name,
          description: chart.description,
        );
        final int n = _freeChartNumber();
        final DrawingChart content = DrawingChart.created(
          DrawingChartSpace(
            chart: chart.chart,
            language: chart.language,
            ids:
                xlsxChartIds(chart) ??
                xlsxChartPartIds(n, chart.chart.series.length),
            autoTitle: chart.autoTitle,
          ),
          chart.theme,
          date1904: _host.date1904,
        );
        final ChangeLog log = _host.log;
        final OpcPackage package = _host.reader.package;
        log.transaction(() {
          final DrawingPart drawing = read.part ?? _addDrawing(part, read);
          final String added = addStoredPart(
            log,
            package,
            '/xl/charts/chart$n.xml',
            drawingChartContentType,
            content,
          );
          final String source = '/${read.partName!}';
          final String id = addStoredRelationship(
            log,
            package,
            source,
            type: drawingChartRelationshipType,
            target: relationshipTarget(source, added),
            id: _freeRelationshipId(read),
          );
          applyChange(
            log,
            _DrawingChartChange(read, id, null, added.substring(1)),
          );
          _attach(read, drawing);
          applyChange(
            log,
            _DrawingEntryChange(
              drawing,
              drawing.entries.length,
              null,
              DrawingEntry.renderedChart(
                chart.anchor,
                extent: extent,
                id: drawing.nextId,
                name: frameName,
                description: chart.description,
                chartId: id,
              ),
            ),
          );
        });
        _warnWritten(content, frameName);
      });

  /// Writes [chart] into the part of the chart at [index] of [charts], in
  /// [theme] (the Office theme when `null`) and the workbook's date system.
  ///
  /// The anchor, the frame (its name and description) and the part's
  /// relationships stay, and so do the part's language, automatic title and
  /// ids when it reads typed; otherwise the part takes `en-US`, no automatic
  /// title and the ids `xlsxChartPartIds` gives the number of its name. A
  /// series past the old ids takes the id of its position there, a part
  /// that showed a pie or a donut, which has no axes, takes those axis ids,
  /// and one that showed no secondary axis those secondary axis ids.
  /// It works on a chart listed as a view only, or with no view: that is the
  /// caller's choice to rebuild it. When [chart]'s kind is not the kind the
  /// part showed (or it showed none), the part's chart style and colour
  /// style relationships go, as their content is per kind, and so do their
  /// parts when nothing else targets them. A [chart] equal to the part's
  /// typed chart, in the Office theme, is no edit. Warns as [addChart] does.
  ///
  /// Throws a [RangeError] for an [index] outside [charts]; an
  /// [ArgumentError] for a chart the writer cannot express or a bad [theme];
  /// a [StateError] for a sheet that is not a worksheet or has no part, and
  /// for a `<drawing>` whose part is missing or is not a spreadsheet drawing;
  /// and an [XlsxReadException] when the sheet, the drawing or a
  /// relationships part cannot be read. Whatever it throws, nothing has
  /// changed.
  void replaceChartAt(
    int index,
    Chart chart, {
    ChartTheme? theme,
  }) => _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
    final WorksheetPart part = _editablePart('charts');
    final _PicturesRead read = _editablePictures(part, what: 'charts');
    final List<int> listed = _listedCharts(read);
    RangeError.checkValidIndex(index, listed, 'index');
    final DrawingChartFrame frame =
        read.part!.entries[listed[index]].chartFrame!;
    final String chartName = read.charts[frame.chartId]!;
    final ChartTheme written = theme ?? ChartTheme.office;
    final DrawingChart? old = _chartPart(chartName).chart;
    final DrawingChartSpace? typed = old?.typed;
    if (typed != null && typed.chart == chart && written == ChartTheme.office) {
      return;
    }
    final ChartKind? oldKind = old?.chart?.kind;
    final DrawingChartIds fresh = xlsxChartPartIds(
      _chartNumber(chartName) ?? index + 1,
      chart.series.length,
    );
    final DrawingChart content = DrawingChart.created(
      DrawingChartSpace(
        chart: chart,
        language: typed?.language ?? 'en-US',
        ids: typed == null
            ? fresh
            : _keptIds(
                typed.ids,
                fresh,
                axes: oldKind != ChartKind.pie && oldKind != ChartKind.donut,
                secondary: old?.chart?.secondaryValueAxis != null,
              ),
        autoTitle: typed?.autoTitle ?? false,
      ),
      written,
      date1904: _host.date1904,
    );
    final PackageReader reader = _host.reader;
    final OpcPackage package = reader.package;
    final List<OpcRelationship> styles = oldKind == chart.kind
        ? const <OpcRelationship>[]
        : reader.guardXml(
            chartName,
            () => <OpcRelationship>[
              for (final OpcRelationship r in package.peekRelationships(
                chartName,
              ))
                if (!r.external &&
                    (r.type == _chartStyleType ||
                        r.type == _chartColorStyleType))
                  r,
            ],
          );
    final ChangeLog log = _host.log;
    log.transaction(() {
      applyChange(
        log,
        _ChartContentChange(
          package,
          chartName,
          package.contentOf(chartName),
          content,
        ),
      );
      for (final OpcRelationship r in styles) {
        final String target = package.resolve(chartName, r.target);
        reader.guardXml(
          chartName,
          () => removeStoredRelationship(log, package, chartName, r.id),
        );
        _dropChartPart(target);
      }
    });
    _warnWritten(content, frame.name);
  });

  /// Moves the chart at [index] of [charts] to [anchor], which may be of the
  /// other kind, as `movePictureAt` moves a picture: the anchor element takes
  /// the new markers, `ext` and `editAs`, and its frame stays as written. An
  /// [anchor] equal to the chart's is no edit.
  ///
  /// Throws a [RangeError] for an [index] outside [charts]; an
  /// [ArgumentError] for a bad anchor, as [addChart] does; a [StateError]
  /// for a sheet that is not a worksheet or has no part, and for a
  /// `<drawing>` whose part is missing or is not a spreadsheet drawing; and
  /// an [XlsxReadException] when the sheet, its relationships or the drawing
  /// cannot be read. Whatever it throws, nothing has changed.
  void moveChartAt(int index, XlsxAnchor anchor) => _recordSheetEdit(
    this,
    XlsxChangeKind.featureChanged,
    () {
      final WorksheetPart part = _editablePart('charts');
      final _PicturesRead read = _editablePictures(part, what: 'charts');
      final List<int> listed = _listedCharts(read);
      RangeError.checkValidIndex(index, listed, 'index');
      final DrawingPart drawing = read.part!;
      final int at = listed[index];
      final DrawingEntry entry = drawing.entries[at];
      if (entry.anchor == anchor) return;
      final ({int cx, int cy})? extent = checkChartFrame(
        anchor,
        which: 'Chart ${index + 1} on sheet "$name"',
      );
      final XlsxAnchor placed = anchor is XlsxOneCellAnchor
          ? XlsxOneCellAnchor(
              anchor.from,
              width: extent!.cx / emuPerPixel,
              height: extent.cy / emuPerPixel,
            )
          : anchor;
      if (entry.anchor == placed) return;
      final DrawingEntry moved = _host.reader.guardXml(
        read.partName!,
        () => entry.movedTo(anchor, extent),
      );
      _host.log.transaction(() {
        _attach(read, drawing);
        applyChange(_host.log, _DrawingEntryChange(drawing, at, entry, moved));
      });
    },
  );

  /// Removes the chart at [index] of [charts].
  ///
  /// The frame goes, and so does the drawing's relationship to the chart
  /// part when no other entry names it. The chart part goes when no
  /// relationship of the package targets it any more, and with it every
  /// part only it targets (its chart style and colour style, its user
  /// shapes, an embedded workbook), and the parts only those target. A
  /// drawing left with no entry goes with the sheet's relationship to it and
  /// `<drawing>`, unless something else still targets it, as when the last
  /// picture goes.
  ///
  /// Throws a [RangeError] for an [index] outside [charts]; a [StateError]
  /// for a sheet that is not a worksheet or has no part, and for a
  /// `<drawing>` whose part is missing or is not a spreadsheet drawing; and
  /// an [XlsxReadException] when the sheet, the drawing or any relationships
  /// of the package cannot be read. Whatever it throws, nothing has changed.
  void removeChartAt(int index) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        final WorksheetPart part = _editablePart('charts');
        final _PicturesRead read = _editablePictures(part, what: 'charts');
        final List<int> listed = _listedCharts(read);
        RangeError.checkValidIndex(index, listed, 'index');
        final DrawingPart drawing = read.part!;
        final int at = listed[index];
        final DrawingEntry entry = drawing.entries[at];
        final PackageReader reader = _host.reader;
        final String drawingName = read.partName!;
        final Set<String> unused = reader.guardXml(drawingName, () {
          final Set<String> ids = <String>{...entry.relationshipIds};
          for (final DrawingEntry other in drawing.entries) {
            if (!identical(other, entry)) ids.removeAll(other.relationshipIds);
          }
          return ids;
        });
        final Map<String, String> targets = _relationshipTargets(drawingName);
        final ChangeLog log = _host.log;
        log.transaction(() {
          _attach(read, drawing);
          applyChange(log, _DrawingEntryChange(drawing, at, entry, null));
          for (final String id in unused) {
            removeStoredRelationship(log, reader.package, drawingName, id);
            final String? chart = read.charts[id];
            if (chart != null) {
              applyChange(log, _DrawingChartChange(read, id, chart, null));
            }
            final String? media = read.media[id];
            if (media != null) {
              applyChange(log, _DrawingMediaChange(read, id, media, null));
            }
            final String? target = targets[id];
            if (target == null) continue;
            if (chart != null) {
              _dropChartPart(target);
            } else {
              _dropTarget(target);
            }
          }
          if (drawing.entries.isEmpty) _dropDrawing(part, read);
        });
      });

  /// Writes the data table of [chart] to cells and returns [chart] with
  /// every series bound to them, so the chart in Excel follows edits of the
  /// cells.
  ///
  /// The table starts at ([row], [column]), 0-based, whose own cell stays
  /// empty: the series' names go across the header row from the next
  /// column, the categories down the first column from the next row, and
  /// series i's values in column [column] + 1 + i. A scatter chart has per
  /// series an x column, the categories, then a y column, the values, with
  /// the series name over the y column. A `DateTime` category is a date cell
  /// in the category axis' format code, or `m/d/yyyy`; a series' format code
  /// is the number format of its value cells; a `null` or non-finite entry
  /// leaves its cell empty. A series without categories, values or a name
  /// binds none of them. A series longer than the categories extends the
  /// block.
  ///
  /// The result holds, for each series, the `name`, `categories` and
  /// `values` references of the cells (`'Sheet'!$B$1`,
  /// `'Sheet'!$A$2:$A$5`, absolute, the sheet name always quoted), with the
  /// values as given. The cells are set as [setCell] does, overwriting what
  /// they held, and all of it is one change.
  ///
  /// Throws a [RangeError] for a [row] or [column] outside the sheet and a
  /// [StateError] when the table does not fit on it, or as [setCell] does;
  /// whatever it throws, nothing has changed.
  Chart writeChartData(Chart chart, int row, int column) =>
      _recordSheetEdit(this, XlsxChangeKind.cellsSet, () {
        RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
        RangeError.checkValueInInterval(
          column,
          0,
          XlsxLimits.maxColumns - 1,
          'column',
        );
        final List<ChartSeries> series = chart.series;
        if (series.isEmpty) return chart;
        final bool scatter = chart.kind == ChartKind.scatter;
        int length = 0;
        for (final ChartSeries s in series) {
          final int own = s.categories.values.length > s.values.values.length
              ? s.categories.values.length
              : s.values.values.length;
          if (own > length) length = own;
        }
        final int width = scatter ? 2 * series.length : 1 + series.length;
        if (row + 1 + length > XlsxLimits.maxRows ||
            column + width > XlsxLimits.maxColumns) {
          throw StateError(
            'The data of the chart needs ${1 + length} rows and $width '
            'columns from ${cellRef(row, column)}, which do not fit on sheet '
            '"$name".',
          );
        }
        String ref(int r, int c, [int? lastRow]) {
          final String first = '\$${columnName(c)}\$${r + 1}';
          final String last = lastRow == null || lastRow == r
              ? ''
              : ':\$${columnName(c)}\$${lastRow + 1}';
          return '${renderSheetPrefix(name)}$first$last';
        }

        final String dateFormat = chart.categoryAxis.formatCode ?? 'm/d/yyyy';
        void writeCategories(ChartSeries s, int c) {
          final List<Object?> values = s.categories.values;
          for (int i = 0; i < values.length; i++) {
            final Object? v = values[i];
            if (v == null || (v is double && !v.isFinite)) continue;
            setCell(
              row + 1 + i,
              c,
              v is DateTime
                  ? XlsxCell(
                      v,
                      style: XlsxStyle(numFmt: XlsxNumFmt.custom(dateFormat)),
                    )
                  : v,
            );
          }
        }

        final List<ChartSeries> bound = <ChartSeries>[];
        // The categories column of a non-scatter chart: the series with the
        // most categories gives them, every series binds to it.
        if (!scatter) {
          ChartSeries? shared;
          for (final ChartSeries s in series) {
            if (s.categories.values.length >
                (shared?.categories.values.length ?? 0)) {
              shared = s;
            }
          }
          if (shared != null) writeCategories(shared, column);
        }
        for (int i = 0; i < series.length; i++) {
          final ChartSeries s = series[i];
          final int xColumn = column + 2 * i;
          final int yColumn = scatter ? xColumn + 1 : column + 1 + i;
          if (scatter) writeCategories(s, xColumn);
          final String? nameText = s.name.values.isEmpty
              ? null
              : s.name.values.first;
          final bool named = nameText != null && nameText.isNotEmpty;
          if (named) setCell(row, yColumn, nameText);
          final XlsxStyle? valueStyle = s.formatCode == null
              ? null
              : XlsxStyle(numFmt: XlsxNumFmt.custom(s.formatCode!));
          final List<double?> values = s.values.values;
          for (int j = 0; j < values.length; j++) {
            final double? v = values[j];
            if (v == null || !v.isFinite) continue;
            setCell(
              row + 1 + j,
              yColumn,
              valueStyle == null ? v : XlsxCell(v, style: valueStyle),
            );
          }
          final int categoryCount = s.categories.values.length;
          bound.add(
            s.copyWith(
              name: named
                  ? s.name.copyWith(reference: ref(row, yColumn))
                  : s.name,
              categories: categoryCount == 0
                  ? s.categories
                  : s.categories.copyWith(
                      reference: ref(
                        row + 1,
                        scatter ? xColumn : column,
                        row + categoryCount,
                      ),
                    ),
              values: values.isEmpty
                  ? s.values
                  : s.values.copyWith(
                      reference: ref(row + 1, yColumn, row + values.length),
                    ),
            ),
          );
        }
        return chart.copyWith(series: bound);
      });

  /// Where the charts listed in [charts] are among the drawing's entries.
  List<int> _listedCharts(_PicturesRead read) {
    final List<DrawingEntry> entries =
        read.part?.entries ?? const <DrawingEntry>[];
    return <int>[
      for (int at = 0; at < entries.length; at++)
        if (entries[at].anchor != null &&
            entries[at].chartFrame != null &&
            read.charts.containsKey(entries[at].chartFrame!.chartId))
          at,
    ];
  }

  /// The lowest n from 1 for which the package has no part
  /// `xl/charts/chart{n}.xml`.
  int _freeChartNumber() {
    final PackageReader reader = _host.reader;
    int n = 1;
    while (reader.hasPart('xl/charts/chart$n.xml')) {
      n++;
    }
    return n;
  }

  /// The number n of a part named `.../chart{n}.xml`, or `null` for a part
  /// named otherwise.
  static int? _chartNumber(String name) {
    final RegExpMatch? match = RegExp(
      r'chart(\d{1,9})\.xml$',
      caseSensitive: false,
    ).firstMatch(name);
    return match == null ? null : int.parse(match[1]!);
  }

  /// The ids [old] of a part, kept for a chart whose part number gives
  /// [fresh]: the series ids [old] has, then [fresh]'s for the series past
  /// them; [old]'s primary axis ids when [axes] (the part had axes) and its
  /// secondary ones when [secondary] (it had a secondary axis), else
  /// [fresh]'s.
  static DrawingChartIds _keptIds(
    DrawingChartIds old,
    DrawingChartIds fresh, {
    required bool axes,
    required bool secondary,
  }) {
    final DrawingChartIds primaryFrom = axes ? old : fresh;
    final DrawingChartIds secondaryFrom = axes && secondary ? old : fresh;
    return DrawingChartIds(
      categoryAxis: primaryFrom.categoryAxis,
      valueAxis: primaryFrom.valueAxis,
      secondaryCategoryAxis: secondaryFrom.secondaryCategoryAxis,
      secondaryValueAxis: secondaryFrom.secondaryValueAxis,
      series: <String>[
        ...old.series.take(fresh.series.length),
        ...fresh.series.skip(old.series.length),
      ],
    );
  }

  /// Takes the part [target], the target of a relationship just removed, out
  /// of the package unless a relationship still points at it or it left
  /// already, and with it the parts only it targeted: an image through the
  /// media index ([_dropTarget]), any other part by this rule again.
  void _dropChartPart(String target) {
    final PackageReader reader = _host.reader;
    final OpcPackage package = reader.package;
    if (!reader.hasPart(target)) return;
    final List<({String type, String name})>? children = reader.guardXml(
      target,
      () => package.isReferenced(target)
          ? null
          : <({String type, String name})>[
              for (final OpcRelationship r in package.peekRelationships(target))
                if (!r.external)
                  (type: r.type, name: package.resolve(target, r.target)),
            ],
    );
    if (children == null) return;
    removeStoredPart(_host.log, package, target);
    for (final ({String type, String name}) child in children) {
      if (child.type == RelType.image) {
        _dropTarget(child.name);
      } else {
        _dropChartPart(child.name);
      }
    }
  }

  /// Warns about what the writer did to [content], the part of the chart
  /// called [frame]: each issue once.
  void _warnWritten(DrawingChart content, String frame) {
    final Set<DrawingChartIssue> issues = content.issues.toSet();
    if (issues.contains(DrawingChartIssue.invalidCharacter)) {
      _warn(XlsxWarningCode.invalidCharactersRemoved, null, detail: frame);
    }
    if (issues.contains(DrawingChartIssue.nonFiniteValue)) {
      _warn(XlsxWarningCode.chartValueOmitted, null, detail: frame);
    }
  }

  /// The chart part [name], opened from what the package holds for it now,
  /// and again only once that changes. A part over the size cap, or whose
  /// bytes cannot be read, opens as none.
  _ChartPartRead _chartPart(String name) {
    final PartContent? source = _host.reader.package.contentOf(name);
    final _ChartPartRead? cached = _chartParts[name];
    if (cached != null && identical(cached.source, source)) return cached;
    return _chartParts[name] = _openChartPart(name, source);
  }

  _ChartPartRead _openChartPart(String name, PartContent? source) {
    final PackageReader reader = _host.reader;
    final OpcPackage package = reader.package;
    final int cap = reader.limits.maxChartPartBytes;
    // The original bytes are not inflated when the file declares more.
    if (source == null && (package.declaredSize(name) ?? 0) > cap) {
      return (chart: null, source: source);
    }
    final Uint8List bytes;
    try {
      bytes = reader.guardXml(name, () => package.bytesOf(name));
    } on XlsxReadException {
      return (chart: null, source: source);
    }
    if (bytes.length > cap) return (chart: null, source: source);
    return (
      chart: DrawingChart.opened(
        bytes,
        themeColors: _host.themeColors,
        date1904: _host.date1904,
      ),
      source: source,
    );
  }
}
