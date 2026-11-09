/// The gallery of the owner's side-by-side check against Excel for Mac: the
/// charts the app draws and `tool/write_excel_gallery.dart` writes as Excel's
/// own charts.
///
/// Pure Dart, no Flutter: the workbook writer and its tests use it too.
library;

import 'package:jet_charts_core/jet_charts_core.dart';

/// The size of every chart in both outputs, in points (logical pixels in the
/// app): Excel's default chart of 5 by 3 inches.
const ChartSize gallerySize = ChartSize(360, 216);

/// One chart of the gallery.
final class GalleryEntry {
  /// Creates an entry named [name] of [chart], whose Excel chart carries the
  /// title [excelTitle].
  const GalleryEntry({
    required this.name,
    required this.excelTitle,
    required this.chart,
  });

  /// The name: the app's caption and the workbook's sheet name (cut to 31
  /// characters there).
  final String name;

  /// The title text of the Excel chart: the chart's title, or empty when it
  /// has none, in which case the Excel chart's automatic title is deleted.
  final String excelTitle;

  /// The chart.
  final Chart chart;

  @override
  bool operator ==(Object other) =>
      other is GalleryEntry &&
      name == other.name &&
      excelTitle == other.excelTitle &&
      chart == other.chart;

  @override
  int get hashCode => Object.hash(name, excelTitle, chart);

  @override
  String toString() => 'GalleryEntry($name)';
}

const List<String> _quarters = <String>['Q1', 'Q2', 'Q3', 'Q4'];

ChartSeries _series(
  String name,
  List<Object> categories,
  List<double?> values, {
  String? formatCode,
}) => ChartSeries(
  name: ChartData<String>(values: <String?>[name]),
  categories: ChartData<Object>(values: categories),
  values: ChartData<double>(values: values),
  formatCode: formatCode,
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

GalleryEntry _entry(String name, Chart chart) =>
    GalleryEntry(name: name, excelTitle: chart.title?.text ?? '', chart: chart);

/// The format code of `turkish_amounts`.
const String turkishAmountFormat = '#,##0 "₺"';

/// The gallery: the 13 charts of `packages/jet_charts_core/test/support/
/// gallery.dart` with the same names and data, then `one_series` (one series
/// with a title and a legend: Excel's default chart of one series hides its
/// legend) and `turkish_amounts` (Turkish month names, values in the format
/// [turkishAmountFormat]).
List<GalleryEntry> galleryEntries() => <GalleryEntry>[
  _entry('column_clustered', _column()),
  _entry('column_stacked', _column(grouping: ChartGrouping.stacked)),
  _entry('column_percent', _column(grouping: ChartGrouping.percentStacked)),
  _entry('bar_clustered', _column(kind: ChartKind.bar)),
  _entry(
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
  _entry(
    'area_stacked',
    _column(kind: ChartKind.area, grouping: ChartGrouping.stacked),
  ),
  _entry(
    'column_negative',
    _column(
      title: 'Profit and loss',
      series: <ChartSeries>[
        _series('Profit', _quarters, <double?>[14, -6, 9, -11]),
        _series('Cash', _quarters, <double?>[-3, 8, -12, 5]),
      ],
    ),
  ),
  _entry(
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
  _entry(
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
  _entry(
    'column_data_labels',
    _column(dataLabels: const ChartDataLabels(visible: true)),
  ),
  _entry(
    'legend_top',
    _column(legend: const ChartLegend(position: ChartLegendPosition.top)),
  ),
  _entry(
    'legend_left',
    _column(legend: const ChartLegend(position: ChartLegendPosition.left)),
  ),
  _entry(
    'legend_right',
    _column(legend: const ChartLegend(position: ChartLegendPosition.right)),
  ),
  _entry(
    'tile',
    _column(
      title: null,
      legend: const ChartLegend(visible: false),
      series: <ChartSeries>[
        _series('Sales', _quarters, <double?>[12, 18, 9, 15]),
      ],
    ),
  ),
  _entry(
    'one_series',
    _column(
      title: 'One series',
      series: <ChartSeries>[
        _series('Sales', _quarters, <double?>[12, 18, 9, 15]),
      ],
    ),
  ),
  _entry(
    'turkish_amounts',
    _column(
      title: 'Aylık tutarlar',
      series: <ChartSeries>[
        _series('Gelir', _months, <double?>[
          12500,
          18250,
          9800,
          15400,
          21000,
          17600,
        ], formatCode: turkishAmountFormat),
        _series('Gider', _months, <double?>[
          8400,
          11900,
          14250,
          10100,
          12800,
          13500,
        ], formatCode: turkishAmountFormat),
      ],
    ),
  ),
];

const List<String> _months = <String>[
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
];
