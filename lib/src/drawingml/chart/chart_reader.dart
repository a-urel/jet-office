/// The chart reader: [readDrawingChartSpace] reads a `c:chartSpace` part into
/// the [Chart] it shows, and into its typed form when the writer reproduces
/// the part.
///
/// Not ported from Quds; written for jet_office.
///
/// A chart part is untrusted input (decision 0007): the reader never throws.
/// Bytes that are not XML, or whose root is not `c:chartSpace`, give no chart
/// and [DrawingChartIssue.unreadable]. Anything else gives a view of what the
/// part shows: the kind and grouping of its one group, the series with their
/// names, categories, values, references and colours, the title, the legend,
/// the two axes and the data labels. A part the model does not draw (another
/// group, several groups, a third axis) is [ChartKind.unsupported], with the
/// series of its first group.
///
/// The typed form ([DrawingChartSpace]) is offered only when writing it gives
/// the part again by `xmlDifference` (ruling R2 of C1), so whatever the reader
/// cannot carry (an element the writer does not write, a `dk1` for `tx1`, a
/// number spelled another way) leaves the part untyped instead of losing it.
/// Reading and that check are linear in the size of the part: every cache
/// draws its entries, the points it lacks included, from one budget of
/// 1,048,576 plus the part's size in bytes, and a number text longer than
/// 400 characters is not parsed.
///
/// This layer imports `opc`, `xml`, `common`, `jet_charts_core` and `jet_core`
/// only, never `xlsx` or `docx` (decisions 0014 and 0015).
library;

import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';

import '../../common/theme_colors.dart';
import '../../xml/xml_equivalence.dart';
import '../../xml/xml_pull_reader.dart';
import '../color.dart';
import 'chart_space.dart';
import 'chart_values.dart';
import 'chart_writer.dart';

part 'chart_reader_series.dart';

/// What [readDrawingChartSpace] read from a chart part.
final class DrawingChartRead {
  /// Creates a result of [chart], [typed] and [issues].
  const DrawingChartRead(this.chart, this.typed, this.issues);

  /// What the part shows, or `null` when it could not be read as a chart.
  final Chart? chart;

  /// The part in typed form, or `null` unless its kind is one the writer
  /// writes and writing this form gives the part again.
  final DrawingChartSpace? typed;

  /// Each kind of data problem met, once, in the order first met.
  final List<DrawingChartIssue> issues;
}

/// Reads [bytes], a `c:chartSpace` part.
///
/// [theme] (`ChartTheme.office` when `null`) is the theme the part would be
/// written in: a series colour equal to the one the writer derives for that
/// series' index ([ChartTheme.seriesColor]), as the writer writes it in the
/// theme's `exportColors`, reads as `null`, and the typed form is checked by
/// writing it in [theme]. [themeColors] are the file theme's colours, which
/// give a scheme colour its RGB value (the Office theme's when `null`).
/// [date1904] reads date categories as serials of the 1904 date system, and
/// checks the typed form by writing it in that system.
///
/// Never throws, whatever [theme] holds: when the writer refuses it (a line
/// width, marker size or text size the part cannot hold), the part is read
/// with no typed form.
///
/// Bytes that are not well-formed UTF-8 XML, or whose root is not
/// `c:chartSpace` with a `c:chart`, give no chart and
/// [DrawingChartIssue.unreadable]. A kind the model does not draw gives a
/// [ChartKind.unsupported] chart and [DrawingChartIssue.unsupportedKind]; its
/// `unsupportedName` is the names of the plot area's groups joined by `+`
/// (`barChart+lineChart`), or `null` when it has none. A number that cannot
/// be read is an empty point (or an unset value) and
/// [DrawingChartIssue.badNumber], as is a point index or count beyond
/// 1,048,576, the rows of a sheet: such a count is cut to that limit. All
/// the caches of the part (names, categories and values) share one budget
/// of 1,048,576 entries plus the part's size in bytes; a cache whose count
/// would exceed what is left is cut to its last point, with
/// [DrawingChartIssue.badNumber].
DrawingChartRead readDrawingChartSpace(
  Uint8List bytes, {
  ChartTheme? theme,
  ThemeColors? themeColors,
  bool date1904 = false,
}) {
  final _Node? root;
  try {
    root = _parse(bytes, themeColors);
  } on XmlParseException {
    return _unreadable;
  }
  if (root == null ||
      root.uri != drawingChartNamespace ||
      root.name != 'chartSpace') {
    return _unreadable;
  }
  final _Node? chart = root.child('chart');
  if (chart == null) {
    return _unreadable;
  }
  return _ChartReader(
    root,
    chart,
    theme ?? ChartTheme.office,
    _maxPoints + bytes.length,
    date1904,
  ).read(bytes);
}

const DrawingChartRead _unreadable = DrawingChartRead(
  null,
  null,
  <DrawingChartIssue>[DrawingChartIssue.unreadable],
);

const String _c16Namespace =
    'http://schemas.microsoft.com/office/drawing/2014/chart';

/// The largest `c:axId`, that of `xsd:unsignedInt`.
const int _maxAxisId = 4294967295;

final RegExp _axisIdText = RegExp(r'^[0-9]{1,10}$');

/// An element of the part: its name, attributes, children and text.
///
/// A colour element (`a:srgbClr`, `a:schemeClr`, `a:sysClr`) is read by
/// `readDrawingColor` as the tree is built and keeps only the colour.
final class _Node {
  _Node(this.uri, this.name, this.attributes);

  final String uri;
  final String name;

  /// The attributes by local name, the first of each name; namespace
  /// declarations are left out.
  final Map<String, String> attributes;
  final List<_Node> children = <_Node>[];
  StringBuffer? _text;

  /// Whether this is a colour element, whose colour is [color].
  bool isColor = false;

  /// The colour of a colour element, `null` when it could not be read.
  ChartColor? color;

  /// The character data directly inside the element, concatenated.
  String get text => _text?.toString() ?? '';

  /// The `val` attribute.
  String? get val => attributes['val'];

  void addText(String text) {
    (_text ??= StringBuffer()).write(text);
  }

  /// The first child named [name] in [uri].
  _Node? child(String name, [String uri = drawingChartNamespace]) {
    for (final _Node node in children) {
      if (node.name == name && node.uri == uri) {
        return node;
      }
    }
    return null;
  }

  /// The children named [name] in [uri].
  Iterable<_Node> all(String name, [String uri = drawingChartNamespace]) =>
      children.where((_Node node) => node.name == name && node.uri == uri);
}

/// The root element of [bytes] as a tree, or `null` when there is none.
///
/// Throws only an [XmlParseException].
_Node? _parse(Uint8List bytes, ThemeColors? themeColors) {
  final XmlPullReader r = XmlPullReader.fromBytes(bytes);
  final _Node document = _Node('', '', const <String, String>{});
  final List<_Node> open = <_Node>[document];
  while (r.next()) {
    switch (r.eventType) {
      case XmlEventType.startElement:
        final _Node node = _Node(r.namespaceUri, r.localName, _attributes(r));
        open.last.children.add(node);
        if (node.uri == drawingMainNamespace &&
            (node.name == 'srgbClr' ||
                node.name == 'schemeClr' ||
                node.name == 'sysClr')) {
          // Consumes the element through its end event.
          node.isColor = true;
          // Only a series' fill may carry an alpha (the area opacity); any
          // other colour with one is not read, as before.
          final bool seriesFill =
              open.length >= 4 &&
              open.last.name == 'solidFill' &&
              open[open.length - 2].name == 'spPr' &&
              open[open.length - 3].name == 'ser' &&
              open[open.length - 3].uri == drawingChartNamespace;
          node.color = readDrawingColor(
            r,
            theme: themeColors,
            allowAlpha: seriesFill,
          );
        } else {
          open.add(node);
        }
      case XmlEventType.endElement:
        if (open.length > 1) {
          open.removeLast();
        }
      case XmlEventType.characters || XmlEventType.cdata:
        final _Node node = open.last;
        // Whitespace between elements is no element's text.
        if (node.children.isEmpty || !r.isWhitespace) {
          node.addText(r.text);
        }
      default:
        break;
    }
  }
  return document.children.isEmpty ? null : document.children.first;
}

Map<String, String> _attributes(XmlPullReader r) {
  final int count = r.attributeCount;
  if (count == 0) {
    return const <String, String>{};
  }
  final Map<String, String> attributes = <String, String>{};
  for (int i = 0; i < count; i++) {
    final String qualified = r.attributeQualifiedName(i);
    if (qualified == 'xmlns' || qualified.startsWith('xmlns:')) {
      continue;
    }
    attributes.putIfAbsent(r.attributeLocalName(i), () => r.attributeValue(i));
  }
  return attributes;
}

/// Whether the `CT_Boolean` element [node] is on: [absent] when there is no
/// element, on when it has no `val` (the schema's default), off for `0` and
/// `false`.
bool _flag(_Node? node, {required bool absent}) {
  if (node == null) {
    return absent;
  }
  final String? value = node.val;
  return value != '0' && value != 'false';
}

final class _ChartReader {
  _ChartReader(
    this.root,
    this.chartNode,
    this.theme,
    this.pointBudget,
    this.date1904,
  );

  final _Node root;
  final _Node chartNode;
  final ChartTheme theme;
  final List<DrawingChartIssue> issues = <DrawingChartIssue>[];

  /// The entries the caches of the part may still fill, points they lack
  /// included: 1,048,576 plus the size of the part in bytes at the start.
  int pointBudget;

  /// Whether date categories count in the 1904 date system.
  final bool date1904;

  void _report(DrawingChartIssue issue) {
    if (!issues.contains(issue)) {
      issues.add(issue);
    }
  }

  DrawingChartRead read(Uint8List bytes) {
    final _Node? plotArea = chartNode.child('plotArea');
    final List<_Node> groups = <_Node>[];
    final List<_Node> axes = <_Node>[];
    for (final _Node node in plotArea?.children ?? const <_Node>[]) {
      if (node.uri != drawingChartNamespace) {
        continue;
      }
      if (node.name.endsWith('Chart')) {
        groups.add(node);
      } else if (const <String>{
        'catAx',
        'dateAx',
        'valAx',
        'serAx',
      }.contains(node.name)) {
        axes.add(node);
      }
    }
    final _Node? categoryAxis = axes
        .where((_Node a) => a.name == 'catAx' || a.name == 'dateAx')
        .firstOrNull;
    final _Node? valueAxis = axes
        .where((_Node a) => a.name == 'valAx')
        .firstOrNull;
    final _Node? group = groups.firstOrNull;
    ChartKind kind = ChartKind.unsupported;
    if (group != null &&
        groups.length == 1 &&
        axes.length == 2 &&
        categoryAxis != null &&
        valueAxis != null) {
      kind = switch (group.name) {
        'barChart' =>
          group.child('barDir')?.val == 'bar'
              ? ChartKind.bar
              : ChartKind.column,
        'lineChart' => ChartKind.line,
        'areaChart' => ChartKind.area,
        _ => ChartKind.unsupported,
      };
    }
    if (kind == ChartKind.unsupported) {
      _report(DrawingChartIssue.unsupportedKind);
    }
    final bool lines = const <String>{
      'lineChart',
      'line3DChart',
      'radarChart',
      'scatterChart',
      'stockChart',
    }.contains(group?.name);
    final List<_Node> seriesNodes = group?.all('ser').toList() ?? <_Node>[];
    final List<ChartSeries> series = <ChartSeries>[
      for (int i = 0; i < seriesNodes.length; i++)
        _readSeries(seriesNodes[i], i, lines: lines),
    ];
    final _Node? titleNode = chartNode.child('title');
    final String? titleText = _titleText(titleNode);
    final Chart chart = Chart(
      kind: kind,
      grouping: switch (group?.child('grouping')?.val) {
        'stacked' => ChartGrouping.stacked,
        'percentStacked' => ChartGrouping.percentStacked,
        _ => ChartGrouping.clustered,
      },
      series: series,
      categoryAxis: _axis(categoryAxis),
      valueAxis: _axis(valueAxis),
      title: titleText == null ? null : ChartTitle(text: titleText),
      legend: _legend(chartNode.child('legend')),
      dataLabels: _dataLabels(group, seriesNodes),
      unsupportedName: kind == ChartKind.unsupported && groups.isNotEmpty
          ? groups.map((_Node g) => g.name).join('+')
          : null,
    );
    final DrawingChartSpace? typed = kind == ChartKind.unsupported
        ? null
        // A supported kind needs both axes, so neither is null here.
        : _typed(
            bytes,
            chart,
            categoryAxis!,
            valueAxis!,
            seriesNodes,
            autoTitle: titleNode != null && titleText == null,
          );
    return DrawingChartRead(
      chart,
      typed,
      List<DrawingChartIssue>.unmodifiable(issues),
    );
  }

  /// The typed form of the part, or `null` when its ids cannot be written,
  /// the writer refuses [theme] (an [ArgumentError]), or writing it does not
  /// give [bytes] again.
  DrawingChartSpace? _typed(
    Uint8List bytes,
    Chart chart,
    _Node categoryAxis,
    _Node valueAxis,
    List<_Node> seriesNodes, {
    required bool autoTitle,
  }) {
    final int? categoryId = _axisId(categoryAxis);
    final int? valueId = _axisId(valueAxis);
    if (categoryId == null || valueId == null || categoryId == valueId) {
      return null;
    }
    final List<String> seriesIds = <String>[];
    for (final _Node node in seriesNodes) {
      final String? id = _seriesId(node);
      if (id == null) {
        // The writer gives ids to the first series only; a later series with
        // one is not reproduced.
        break;
      }
      if (!isDrawingChartSeriesId(id)) {
        return null;
      }
      seriesIds.add(id);
    }
    final DrawingChartSpace space = DrawingChartSpace(
      chart: chart,
      language: root.child('lang')?.val ?? 'en-US',
      ids: DrawingChartIds(
        categoryAxis: categoryId,
        valueAxis: valueId,
        series: List<String>.unmodifiable(seriesIds),
      ),
      autoTitle: autoTitle,
    );
    final DrawingChartWritten written;
    try {
      written = writeDrawingChartSpace(space, theme, date1904: date1904);
    } on ArgumentError {
      // The writer refuses the reader's theme (a line width, marker size or
      // text size the part cannot hold): the part is read but not typed.
      return null;
    }
    return xmlDifference(written.bytes, bytes) == null ? space : null;
  }

  static int? _axisId(_Node axis) {
    final String? text = axis.child('axId')?.val;
    if (text == null || !_axisIdText.hasMatch(text)) {
      return null;
    }
    final int id = int.parse(text);
    return id > _maxAxisId ? null : id;
  }

  static String? _seriesId(_Node series) {
    for (final _Node ext
        in series.child('extLst')?.all('ext') ?? const <_Node>[]) {
      final String? id = ext.child('uniqueId', _c16Namespace)?.val;
      if (id != null) {
        return id;
      }
    }
    return null;
  }

  /// The text of the title [node]: its rich text, one line per paragraph and
  /// its runs joined, or the cached text of its reference; `null` when there
  /// is no title or it has no text (Excel's automatic title).
  String? _titleText(_Node? node) {
    final _Node? tx = node?.child('tx');
    if (tx == null) {
      return null;
    }
    final _Node? rich = tx.child('rich');
    if (rich != null) {
      return <String>[
        for (final _Node p in rich.all('p', drawingMainNamespace))
          _paragraphText(p),
      ].join('\n');
    }
    final _Node? reference = tx.child('strRef');
    if (reference != null) {
      return _firstText(reference.child('strCache')) ?? '';
    }
    return drawingUnescapeXstring(tx.child('v')?.text ?? '');
  }

  static String _paragraphText(_Node paragraph) {
    final StringBuffer out = StringBuffer();
    for (final _Node node in paragraph.children) {
      if (node.uri != drawingMainNamespace) {
        continue;
      }
      if (node.name == 'r' || node.name == 'fld') {
        out.write(node.child('t', drawingMainNamespace)?.text ?? '');
      } else if (node.name == 'br') {
        out.write('\n');
      }
    }
    return out.toString();
  }

  ChartAxis _axis(_Node? node) {
    if (node == null) {
      return const ChartAxis();
    }
    final _Node? scaling = node.child('scaling');
    return ChartAxis(
      title: _titleText(node.child('title')),
      min: _numberOf(scaling?.child('min')),
      max: _numberOf(scaling?.child('max')),
      majorUnit: _numberOf(node.child('majorUnit')),
      formatCode: _formatCode(node.child('numFmt')),
      visible: !_flag(node.child('delete'), absent: false),
      gridLines: node.child('majorGridlines') != null,
    );
  }

  /// The `formatCode` of the `c:numFmt` [node], `null` when it is linked to
  /// the source or there is none.
  static String? _formatCode(_Node? node) {
    if (node == null) {
      return null;
    }
    final String? linked = node.attributes['sourceLinked'];
    if (linked == '1' || linked == 'true') {
      return null;
    }
    return node.attributes['formatCode'];
  }

  /// The number of the `val` of [node], `null` when there is no [node]; a
  /// value that cannot be read is `null` and [DrawingChartIssue.badNumber].
  double? _numberOf(_Node? node) {
    if (node == null) {
      return null;
    }
    return _number(node.val ?? '');
  }

  static ChartLegend _legend(_Node? node) {
    if (node == null) {
      return const ChartLegend(visible: false);
    }
    return ChartLegend(
      position: switch (node.child('legendPos')?.val) {
        'b' => ChartLegendPosition.bottom,
        't' => ChartLegendPosition.top,
        'l' => ChartLegendPosition.left,
        // `r`, `tr` and no position (the schema's default is `r`).
        _ => ChartLegendPosition.right,
      },
      visible: !_flag(node.child('delete'), absent: false),
    );
  }

  /// The first series' data labels that has its own, else the group's.
  ///
  /// Excel writes shown labels in each series and keeps the group's flags
  /// off (`chart_reference.xlsx`, charts 20 and 21), so a series' labels
  /// come first.
  static ChartDataLabels _dataLabels(_Node? group, List<_Node> seriesNodes) {
    _Node? labels;
    for (final _Node node in seriesNodes) {
      labels = node.child('dLbls');
      if (labels != null) {
        break;
      }
    }
    labels ??= group?.child('dLbls');
    if (labels == null) {
      return const ChartDataLabels();
    }
    return ChartDataLabels(
      visible:
          !_flag(labels.child('delete'), absent: false) &&
          _flag(labels.child('showVal'), absent: false),
      formatCode: _formatCode(labels.child('numFmt')),
    );
  }
}
