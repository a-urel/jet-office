/// The fixed gallery of charts the goldens and the SVG gallery lay out, and
/// the text form of primitives the golden files hold.
///
/// Pure Dart, no `dart:io`. Every chart is laid out with
/// `FixedWidthTextMeasurer()` and `ChartTheme.office` in en-US, so a golden
/// changes only when the layout does.
library;

import 'package:jet_charts_core/jet_charts_core.dart';

/// One chart of the gallery.
final class GalleryChart {
  /// Creates a gallery chart named [name] (a file name stem) of [chart].
  const GalleryChart(this.name, this.chart);

  /// The name, also the golden's file stem.
  final String name;

  /// The chart.
  final Chart chart;

  /// Lays the chart out on [size] as the goldens do.
  ChartLayout layout(ChartSize size) => layoutChart(
    chart,
    theme: ChartTheme.office,
    size: size,
    measurer: const FixedWidthTextMeasurer(),
  );
}

/// The size the goldens are laid out on.
const ChartSize goldenSize = ChartSize(360, 240);

/// The sizes the SVG gallery shows every chart at.
const List<ChartSize> gallerySizes = <ChartSize>[
  ChartSize(360, 240),
  ChartSize(640, 400),
  ChartSize(160, 100),
];

const List<String> _quarters = <String>['Q1', 'Q2', 'Q3', 'Q4'];

ChartSeries _series(
  String name,
  List<Object> categories,
  List<double?> values,
) => ChartSeries(
  name: ChartData<String>(values: <String?>[name]),
  categories: ChartData<Object>(values: categories),
  values: ChartData<double>(values: values),
);

List<ChartSeries> _three() => <ChartSeries>[
  _series('North', _quarters, <double?>[12, 18, 9, 15]),
  _series('South', _quarters, <double?>[8, 11, 14, 10]),
  _series('West', _quarters, <double?>[5, 7, 6, 13]),
];

Chart _column({
  ChartKind kind = ChartKind.column,
  ChartGrouping grouping = ChartGrouping.clustered,
  List<ChartSeries>? series,
  String? title = 'Sales by quarter',
  ChartLegend legend = const ChartLegend(),
  ChartDataLabels dataLabels = const ChartDataLabels(),
}) => Chart(
  kind: kind,
  grouping: grouping,
  series: series ?? _three(),
  title: title == null ? null : ChartTitle(text: title),
  legend: legend,
  dataLabels: dataLabels,
);

/// The gallery's charts: clustered, stacked and percent columns; bars; a line
/// with a gap; a stacked area; negative values; eight series; long category
/// labels; data labels; a legend on the top, left and right (the bottom is the
/// default of the rest); and a tile.
List<GalleryChart> galleryCharts() => <GalleryChart>[
  GalleryChart('column_clustered', _column()),
  GalleryChart('column_stacked', _column(grouping: ChartGrouping.stacked)),
  GalleryChart(
    'column_percent',
    _column(grouping: ChartGrouping.percentStacked),
  ),
  GalleryChart('bar_clustered', _column(kind: ChartKind.bar)),
  GalleryChart(
    'line_gap',
    _column(
      kind: ChartKind.line,
      title: 'A gap in the line',
      series: <ChartSeries>[
        _series(
          'Visits',
          <Object>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
          <double?>[4, 7, null, 9, 6, 11],
        ),
        _series(
          'Orders',
          <Object>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
          <double?>[2, 3, 4, null, 5, 6],
        ),
      ],
    ),
  ),
  GalleryChart(
    'area_stacked',
    _column(kind: ChartKind.area, grouping: ChartGrouping.stacked),
  ),
  GalleryChart(
    'column_negative',
    _column(
      title: 'Profit and loss',
      series: <ChartSeries>[
        _series('Profit', _quarters, <double?>[14, -6, 9, -11]),
        _series('Cash', _quarters, <double?>[-3, 8, -12, 5]),
      ],
    ),
  ),
  GalleryChart(
    'column_eight_series',
    _column(
      title: 'Eight series',
      series: <ChartSeries>[
        for (int s = 0; s < 8; s++)
          _series('Series ${s + 1}', _quarters, <double?>[
            for (int c = 0; c < 4; c++) 3.0 + (s * 3 + c * 5) % 11,
          ]),
      ],
    ),
  ),
  GalleryChart(
    'column_long_labels',
    _column(
      title: 'Long category labels',
      series: <ChartSeries>[
        _series(
          'Revenue',
          <Object>[
            'Northern region, first half',
            'Southern region, first half',
            'Western region, second half',
            'Eastern region, second half',
            'Central region, whole year',
          ],
          <double?>[120, 95, 143, 80, 110],
        ),
      ],
    ),
  ),
  GalleryChart(
    'column_data_labels',
    _column(dataLabels: const ChartDataLabels(visible: true)),
  ),
  GalleryChart(
    'legend_top',
    _column(legend: const ChartLegend(position: ChartLegendPosition.top)),
  ),
  GalleryChart(
    'legend_left',
    _column(legend: const ChartLegend(position: ChartLegendPosition.left)),
  ),
  GalleryChart(
    'legend_right',
    _column(legend: const ChartLegend(position: ChartLegendPosition.right)),
  ),
  GalleryChart(
    'tile',
    _column(
      title: null,
      legend: const ChartLegend(visible: false),
      series: <ChartSeries>[
        _series('Sales', _quarters, <double?>[12, 18, 9, 15]),
      ],
    ),
  ),
];

/// The golden of every chart at [goldenSize], and the tile again at 160 by
/// 100, the size it is for. Each entry is the golden's file stem and its
/// layout.
List<(String, ChartLayout)> goldenLayouts() => <(String, ChartLayout)>[
  for (final GalleryChart g in galleryCharts()) (g.name, g.layout(goldenSize)),
  ('tile_160x100', galleryCharts().last.layout(const ChartSize(160, 100))),
];

/// [primitives] as text, one line per primitive, numbers to two decimals; the
/// children of a clip are indented below it. This is the golden files' format.
String primitivesToText(List<ChartPrimitive> primitives) {
  final StringBuffer out = StringBuffer();
  _write(primitives, out, '');
  return out.toString();
}

void _write(List<ChartPrimitive> primitives, StringBuffer out, String indent) {
  for (final ChartPrimitive p in primitives) {
    switch (p) {
      case RectPrimitive():
        out.writeln(
          '${indent}rect ${p.id} ${_rect(p.rect)} fill=${_color(p.fill)} '
          'stroke=${_color(p.stroke)} width=${_n(p.strokeWidth)}',
        );
      case PathPrimitive():
        out.writeln(
          '${indent}path ${p.id} '
          '${p.points.map((ChartPoint q) => '${_n(q.x)},${_n(q.y)}').join(' ')} '
          'closed=${p.closed} fill=${_color(p.fill)} '
          'stroke=${_color(p.stroke)} width=${_n(p.strokeWidth)} '
          'dash=${p.dash == null ? '-' : p.dash!.map(_n).join(',')}',
        );
      case ArcPrimitive():
        out.writeln(
          '${indent}arc ${p.id} centre=${_n(p.center.x)},${_n(p.center.y)} '
          'radius=${_n(p.radius)} inner=${_n(p.innerRadius)} '
          'start=${_n(p.startAngle)} sweep=${_n(p.sweepAngle)} '
          'fill=${_color(p.fill)} stroke=${_color(p.stroke)} '
          'width=${_n(p.strokeWidth)}',
        );
      case TextPrimitive():
        out.writeln(
          '${indent}text ${p.id} ${_rect(p.rect)} rotation='
          '${_n(p.rotationDegrees)} size=${_n(p.style.size)} '
          'color=${_color(p.style.color)} bold=${p.style.bold} '
          '"${p.text.replaceAll('\n', r'\n')}"',
        );
      case ClipPrimitive():
        out.writeln('${indent}clip ${p.id} ${_rect(p.rect)}');
        _write(p.children, out, '$indent  ');
    }
  }
}

String _rect(ChartRect r) =>
    '${_n(r.left)},${_n(r.top)} ${_n(r.width)}x${_n(r.height)}';

String _color(ChartColor? c) =>
    c == null ? '-' : c.rgb.toRadixString(16).padLeft(6, '0').toUpperCase();

String _n(double v) {
  final String s = v.toStringAsFixed(2);
  return s == '-0.00' ? '0.00' : s;
}
