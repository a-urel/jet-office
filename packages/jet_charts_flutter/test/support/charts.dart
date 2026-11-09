/// The charts of the golden images: copies of the charts of the same names in
/// `packages/jet_charts_core/test/support/gallery.dart`, with the same data.
///
/// They are laid out with `ChartTheme.office` whose text styles name the
/// family `Roboto` (`test/fonts/`), so the images show real text.
library;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

/// `ChartTheme.office` with every text style's family set to `Roboto`.
final ChartTheme robotoOfficeTheme = robotoTheme(ChartTheme.office);

/// [theme] with every text style's family set to `Roboto`.
ChartTheme robotoTheme(ChartTheme theme) => theme.copyWith(
  axisLabels: theme.axisLabels.copyWith(fontFamily: 'Roboto'),
  titleText: theme.titleText.copyWith(fontFamily: 'Roboto'),
  legendText: theme.legendText.copyWith(fontFamily: 'Roboto'),
  dataLabels: theme.dataLabels.copyWith(fontFamily: 'Roboto'),
  tooltip: theme.tooltip.copyWith(
    text: theme.tooltip.text.copyWith(fontFamily: 'Roboto'),
  ),
);

/// The size of every golden but the tile's.
const ChartSize goldenSize = ChartSize(360, 240);

/// The tile's size.
const ChartSize tileSize = ChartSize(160, 100);

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

/// The golden charts, each with its name (the image's file stem) and size.
List<(String, Chart, ChartSize)> goldenCharts() => <(String, Chart, ChartSize)>[
  ('column_clustered', _column(), goldenSize),
  ('bar_clustered', _column(kind: ChartKind.bar), goldenSize),
  (
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
    goldenSize,
  ),
  (
    'area_stacked',
    _column(kind: ChartKind.area, grouping: ChartGrouping.stacked),
    goldenSize,
  ),
  (
    'column_negative',
    _column(
      title: 'Profit and loss',
      series: <ChartSeries>[
        _series('Profit', _quarters, <double?>[14, -6, 9, -11]),
        _series('Cash', _quarters, <double?>[-3, 8, -12, 5]),
      ],
    ),
    goldenSize,
  ),
  (
    'column_data_labels',
    _column(dataLabels: const ChartDataLabels(visible: true)),
    goldenSize,
  ),
  (
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
    goldenSize,
  ),
  (
    'legend_right',
    _column(legend: const ChartLegend(position: ChartLegendPosition.right)),
    goldenSize,
  ),
  (
    'tile',
    _column(
      title: null,
      legend: const ChartLegend(visible: false),
      series: <ChartSeries>[
        _series('Sales', _quarters, <double?>[12, 18, 9, 15]),
      ],
    ),
    tileSize,
  ),
];

/// Every golden chart laid out with [robotoOfficeTheme] and [measurer] on its
/// size: the name, the size and the layout.
List<(String, ChartSize, ChartLayout)> galleryForGoldens(
  FlutterTextMeasurer measurer,
) => <(String, ChartSize, ChartLayout)>[
  for (final (String name, Chart chart, ChartSize size) in goldenCharts())
    (
      name,
      size,
      layoutChart(
        chart,
        theme: robotoOfficeTheme,
        size: size,
        measurer: measurer,
      ),
    ),
];
