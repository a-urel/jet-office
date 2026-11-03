/// The view, tab colour and outline summary of an [XlsxSheet]: the members
/// that read and set `view`, `tabColor` and `outlineSummary`.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetViews] in, so these are members of the sheet.
///
/// The first `<sheetView>` of the first `<sheetViews>` and the first
/// `<sheetPr>` are typed ([XmlNode]); an edit changes the attributes the
/// value covers and keeps everything else (`tabSelected`, `topLeftCell`,
/// `workbookViewId`, `codeName`, other children). What is created is what
/// the writer writes: the attributes come from the writer's own functions
/// (`sheetViewAttributes`, `paneAttributes`, `writeColorAttributes`).
part of 'xlsx_sheet.dart';

/// The children of `<sheetPr>` in schema order.
const List<String> _sheetPrOrder = <String>[
  'tabColor',
  'outlinePr',
  'pageSetUpPr',
];

/// The children of `<sheetView>` in schema order.
const List<String> _sheetViewOrder = <String>[
  'pane',
  'selection',
  'pivotSelection',
  'extLst',
];

final RegExp _wholeNumber = RegExp(r'^\+?\d+$');
final RegExp _decimalNumber = RegExp(r'^\+?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

/// Whether the first sheet view of [sheet] says its tab is selected.
///
/// The hook the workbook uses when the active sheet changes. Loads the
/// sheet; `false` for a sheet without a worksheet part.
bool sheetTabSelected(XlsxSheet sheet) => sheet._tabSelected;

/// Sets `tabSelected` of the first sheet view of [sheet]: `1` when
/// [selected], else the attribute removed. A sheet without a sheet view
/// gets one (as the writer writes it, with `workbookViewId="0"`) when
/// [selected] is true. Equal to the current value changes nothing.
///
/// Records a layout change in the workbook's log, so it must run inside a
/// transaction of it, as the workbook's own edits do. Throws a
/// [StateError] for a sheet that is not a worksheet or has no part.
void setSheetTabSelected(XlsxSheet sheet, bool selected) =>
    sheet._setTabSelected(selected);

/// The view half of [XlsxSheet].
mixin _SheetViews {
  // What the sheet gives its view half.
  SheetHost get _host;
  String get name;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);
  bool? _layoutBool(String element, String name, String value);
  void _layoutProblem(String element, String problem);

  /// How the sheet is shown: zoom, gridlines, headings, right-to-left,
  /// zeros, formulas and its frozen or split pane, read from the first
  /// `<sheetView>` of the first `<sheetViews>`.
  ///
  /// A sheet without one has the default view. An attribute that cannot be
  /// read (a `zoomScale` of 500 or `abc`, a boolean that is not one, a pane
  /// split that is not a split) reads as its default (no pane for a bad
  /// split) and is reported once (`layoutInvalid`); it is saved as written
  /// until the view is set to something else. A `pane` with
  /// `state="frozen"` or `"frozenSplit"` is a frozen pane of `ySplit` rows
  /// and `xSplit` columns; otherwise its splits are twips, read as a split
  /// at their points. A pane that splits nothing is no pane. Loads the
  /// sheet. Throws an [XlsxReadException] when the sheet cannot be read.
  XlsxSheetView get view {
    final WorksheetPart? part = _load();
    return part == null ? const XlsxSheetView() : _readView(part);
  }

  /// Sets the view to exactly [value].
  ///
  /// Only the attributes of the fields that change are written, as the
  /// writer writes them (an attribute at Excel's default is removed); the
  /// rest of the `<sheetView>` (`tabSelected`, `topLeftCell`,
  /// `workbookViewId`, ...) and its other children are kept. A changed pane
  /// is written as the writer writes it (`pane` with `xSplit`, `ySplit`,
  /// `topLeftCell` of a freeze, `activePane` and `state`, and a `selection`
  /// of the active part when none names it), and every `<selection>` that
  /// names a part the new pane lacks is dropped. A view equal to the
  /// current one leaves the element as written. A sheet without
  /// `<sheetViews>` gets it in schema position.
  ///
  /// Throws an [ArgumentError] named `zoom` for a zoom outside 10 to 400,
  /// `rows`, `columns`, `x` or `y` for a pane outside the writer's limits,
  /// a [StateError] for a sheet that is not a worksheet or has no part and
  /// an [XlsxReadException] when the sheet cannot be read. Whatever it
  /// throws, nothing has changed, except that reading warnings are
  /// reported on first read.
  set view(XlsxSheetView value) {
    checkSheetView(value);
    final WorksheetPart part = _editablePart('view');
    final XlsxSheetView current = _readView(part);
    if (current == value) return;
    final XmlNode next = _viewNode(part, current, value);
    _editViews(part, next);
  }

  /// The colour of the sheet's tab, from `sheetPr/tabColor`, or `null` for
  /// none.
  ///
  /// A `tabColor` the writer would refuse (a theme index above 11, a bad
  /// `rgb`) reads as `null` and is reported once (`layoutInvalid`). Loads
  /// the sheet. Throws an [XlsxReadException] when the sheet cannot be
  /// read.
  XlsxColor? get tabColor {
    final WorksheetPart? part = _load();
    return part == null ? null : _readTabColor(part);
  }

  /// Sets the tab colour; `null` removes `sheetPr/tabColor`, and the
  /// `<sheetPr>` with it when nothing else is left in it.
  ///
  /// A colour equal to the current one leaves the element as written. A
  /// sheet without `<sheetPr>` gets it in schema position; one that has it
  /// keeps its attributes (`codeName`, ...) and other children
  /// (`pageSetUpPr`, ...).
  ///
  /// Throws an [ArgumentError] named `tabColor` for a colour outside
  /// SpreadsheetML's limits, a [StateError] for a sheet that is not a
  /// worksheet or has no part and an [XlsxReadException] when the sheet
  /// cannot be read. Whatever it throws, nothing has changed.
  set tabColor(XlsxColor? value) {
    if (value != null) validateColor(value, 'tabColor');
    final WorksheetPart part = _editablePart('tab colour');
    if (_readTabColor(part) == value) return;
    final XmlNode? tab = value == null
        ? null
        : XmlNode.made(
            part.elementPrefix,
            'tabColor',
            attributes: _colorAttributes(value),
          );
    _editSheetPr(part, 'tabColor', tab);
  }

  /// Where the summary rows and columns of the outline sit, from
  /// `sheetPr/outlinePr`: `below` is true when the summary row is below its
  /// detail rows and `right` when the summary column is right of its
  /// detail columns, both Excel's default.
  ///
  /// An attribute that is not a boolean reads as the default and is
  /// reported once (`layoutInvalid`). Loads the sheet. Throws an
  /// [XlsxReadException] when the sheet cannot be read.
  ({bool below, bool right}) get outlineSummary {
    final WorksheetPart? part = _load();
    return part == null ? (below: true, right: true) : _readOutline(part);
  }

  /// Sets where the outline summary sits, to exactly [below] and [right].
  ///
  /// `summaryBelow` and `summaryRight` are written as the writer writes
  /// them (`0` for false, removed for the default true); the `outlinePr`
  /// goes when nothing else is left in it, and the `<sheetPr>` when it is
  /// empty. Values equal to the current ones leave the element as written.
  ///
  /// Throws a [StateError] for a sheet that is not a worksheet or has no
  /// part and an [XlsxReadException] when the sheet cannot be read.
  /// Whatever it throws, nothing has changed.
  void setOutlineSummary({bool below = true, bool right = true}) {
    final WorksheetPart part = _editablePart('outline summary');
    final ({bool below, bool right}) current = _readOutline(part);
    if (current.below == below && current.right == right) return;
    final XmlNode? old = part.sheetPr?.child('outlinePr');
    final XmlNode next = (old ?? XmlNode.made(part.elementPrefix, 'outlinePr'))
        .withChanges(<String, String?>{
          if (current.below != below) 'summaryBelow': below ? null : '0',
          if (current.right != right) 'summaryRight': right ? null : '0',
        });
    _editSheetPr(part, 'outlinePr', next.isBare ? null : next);
  }

  // -- Reading ---------------------------------------------------------------

  XlsxSheetView _readView(WorksheetPart part) {
    final XmlNode? node = part.sheetViews?.child('sheetView');
    if (node == null) return const XlsxSheetView();
    const String element = 'sheetView';
    bool flag(String attribute, bool fallback) {
      final String? text = node.attribute(attribute);
      return text == null
          ? fallback
          : _layoutBool(element, attribute, text) ?? fallback;
    }

    int zoom = 100;
    final String? zoomText = node.attribute('zoomScale');
    if (zoomText != null) {
      final int? v = _wholeNumber.hasMatch(zoomText)
          ? int.tryParse(zoomText)
          : null;
      if (v == null || v < XlsxLimits.minZoom || v > XlsxLimits.maxZoom) {
        _layoutProblem(element, 'zoomScale "$zoomText" is not a zoom.');
      } else {
        zoom = v;
      }
    }
    return XlsxSheetView(
      zoom: zoom,
      showGridLines: flag('showGridLines', true),
      showHeadings: flag('showRowColHeaders', true),
      rightToLeft: flag('rightToLeft', false),
      showZeros: flag('showZeros', true),
      showFormulas: flag('showFormulas', false),
      pane: _readPane(node),
    );
  }

  XlsxPane? _readPane(XmlNode view) {
    final XmlNode? pane = view.child('pane');
    if (pane == null) return null;
    const String element = 'pane';
    final String? state = pane.attribute('state');
    final bool frozen = state == 'frozen' || state == 'frozenSplit';
    double? axis(String attribute) {
      final String? text = pane.attribute(attribute);
      if (text == null) return 0;
      final double? v = _decimalNumber.hasMatch(text)
          ? double.tryParse(text)
          : null;
      if (v == null || !v.isFinite || (frozen && v != v.truncateToDouble())) {
        _layoutProblem(element, '$attribute "$text" is not a split.');
        return null;
      }
      return v;
    }

    final double? x = axis('xSplit');
    final double? y = axis('ySplit');
    if (x == null || y == null || (x == 0 && y == 0)) return null;
    final XlsxPane read = frozen
        ? XlsxPane.frozen(rows: y.toInt(), columns: x.toInt())
        : XlsxPane.split(x: x / 20, y: y / 20);
    try {
      checkPane(read);
    } on ArgumentError catch (e) {
      _layoutProblem(element, '${e.message}');
      return null;
    }
    return read;
  }

  XlsxColor? _readTabColor(WorksheetPart part) {
    final XmlNode? node = part.sheetPr?.child('tabColor');
    if (node == null) return null;
    final XmlPullReader r = XmlPullReader(node.leafXml())..next();
    final ReadStyleValue<XlsxColor?> color = readColor(r);
    final String? problem = color.problem;
    if (problem != null) _layoutProblem('sheetPr', 'tabColor: $problem');
    return color.value;
  }

  ({bool below, bool right}) _readOutline(WorksheetPart part) {
    final XmlNode? node = part.sheetPr?.child('outlinePr');
    bool flag(String attribute) {
      final String? text = node?.attribute(attribute);
      return text == null
          ? true
          : _layoutBool('outlinePr', attribute, text) ?? true;
    }

    return (below: flag('summaryBelow'), right: flag('summaryRight'));
  }

  bool get _tabSelected {
    final WorksheetPart? part = _load();
    final String? text = part?.sheetViews
        ?.child('sheetView')
        ?.attribute('tabSelected');
    return text == null
        ? false
        : _layoutBool('sheetView', 'tabSelected', text) ?? false;
  }

  // -- Editing ---------------------------------------------------------------

  /// `<sheetViews>` of [part] with its first view changed from [current] to
  /// [value]: made when the part has none.
  XmlNode _viewNode(
    WorksheetPart part,
    XlsxSheetView current,
    XlsxSheetView value,
  ) {
    final String prefix = part.elementPrefix;
    final XmlNode? views = part.sheetViews;
    final XmlNode? first = views?.child('sheetView');
    if (views == null || first == null) {
      final XmlNode made = _withPane(
        XmlNode.made(
          prefix,
          'sheetView',
          attributes: sheetViewAttributes(value),
        ),
        prefix,
        value.pane,
      );
      return views == null
          ? XmlNode.made(prefix, 'sheetViews', children: <Object>[made])
          : views.withChildren(<Object>[made, ...views.children]);
    }
    final Map<String, String> written = sheetViewAttributes(value);
    final Map<String, String?> changes = <String, String?>{};
    void field(String attribute, bool changed) {
      if (changed) changes[attribute] = written[attribute];
    }

    field('showFormulas', value.showFormulas != current.showFormulas);
    field('showGridLines', value.showGridLines != current.showGridLines);
    field('showRowColHeaders', value.showHeadings != current.showHeadings);
    field('showZeros', value.showZeros != current.showZeros);
    field('rightToLeft', value.rightToLeft != current.rightToLeft);
    field('zoomScale', value.zoom != current.zoom);
    XmlNode next = first.withChanges(changes, addBefore: 'workbookViewId');
    if (value.pane != current.pane) {
      next = _withPane(next, part.elementPrefix, value.pane);
    }
    return views.replacingChild(first, next);
  }

  /// [view] with [pane] as its pane: the `<pane>` as the writer writes it,
  /// no `<selection>` naming a part the pane lacks, and one naming the
  /// active part.
  XmlNode _withPane(XmlNode view, String prefix, XlsxPane? pane) {
    final ({Map<String, String> attributes, String active})? written =
        pane == null ? null : paneAttributes(pane);
    final Map<String, String> splits = written?.attributes ?? const {};
    final Set<String> parts = <String>{
      'topLeft',
      if (splits.containsKey('xSplit')) 'topRight',
      if (splits.containsKey('ySplit')) 'bottomLeft',
      if (splits.containsKey('xSplit') && splits.containsKey('ySplit'))
        'bottomRight',
    };
    bool hasActive = false;
    final List<Object> kept = <Object>[];
    for (final Object c in view.children) {
      if (c is XmlNode && c.localName == 'pane') continue;
      if (c is XmlNode && c.localName == 'selection') {
        final String named = c.attribute('pane') ?? 'topLeft';
        if (!parts.contains(named)) continue;
        if (named == written?.active) hasActive = true;
      }
      kept.add(c);
    }
    XmlNode next = view.withChildren(kept);
    if (written != null) {
      next = next.withChildInOrder(
        XmlNode.made(prefix, 'pane', attributes: written.attributes),
        _sheetViewOrder,
      );
      if (!hasActive) {
        next = next.withChildInOrder(
          XmlNode.made(
            prefix,
            'selection',
            attributes: <String, String>{'pane': written.active},
          ),
          _sheetViewOrder,
        );
      }
    }
    return next;
  }

  void _setTabSelected(bool selected) {
    final WorksheetPart part = _editablePart('selected tab');
    if (_tabSelected == selected) return;
    final XmlNode? views = part.sheetViews;
    final XmlNode? first = views?.child('sheetView');
    final XmlNode next;
    if (views == null || first == null) {
      final XmlNode made = XmlNode.made(
        part.elementPrefix,
        'sheetView',
        attributes: <String, String>{'tabSelected': '1', 'workbookViewId': '0'},
      );
      next = views == null
          ? XmlNode.made(
              part.elementPrefix,
              'sheetViews',
              children: <Object>[made],
            )
          : views.withChildren(<Object>[made, ...views.children]);
    } else {
      next = views.replacingChild(
        first,
        first.withChanges(<String, String?>{
          'tabSelected': selected ? '1' : null,
        }),
      );
    }
    _editViews(part, next);
  }

  void _editViews(WorksheetPart part, XmlNode next) {
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(
        log,
        part,
        'sheetViews',
        () => part.setNode('sheetViews', next),
      );
    });
  }

  /// Makes [child] the `sheetPr` child named [name] (`null` removes it),
  /// creating the `<sheetPr>` in schema position and removing it when
  /// nothing is left in it.
  void _editSheetPr(WorksheetPart part, String name, XmlNode? child) {
    final XmlNode? pr = part.sheetPr;
    final XmlNode? old = pr?.child(name);
    XmlNode? next;
    if (pr == null) {
      if (child == null) return;
      next = XmlNode.made(
        part.elementPrefix,
        'sheetPr',
        children: <Object>[child],
      );
    } else if (old != null) {
      next = pr.replacingChild(old, child);
    } else if (child != null) {
      next = pr.withChildInOrder(child, _sheetPrOrder);
    } else {
      return;
    }
    final XmlNode? result = next.isBare ? null : next;
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(log, part, 'sheetPr', () => part.setNode('sheetPr', result));
    });
  }

  /// The attributes the writer writes for [color], by name.
  static Map<String, String> _colorAttributes(XlsxColor color) {
    final StringBuffer out = StringBuffer();
    final XmlWriter w = XmlWriter(out)..start('c');
    writeColorAttributes(w, color);
    w.end();
    final XmlPullReader r = XmlPullReader(out.toString())..next();
    return <String, String>{
      for (final KeptAttribute a in keepAttributes(r)) a.qualifiedName: a.value,
    };
  }
}
