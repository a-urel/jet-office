/// The charts of an [XlsxSheet]: the members that list them.
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
part of 'xlsx_sheet.dart';

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
