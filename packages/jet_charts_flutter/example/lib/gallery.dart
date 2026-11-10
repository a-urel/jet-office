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

/// The size of a sparkline in both outputs, in points: the cell the
/// workbook gives its Excel sparkline is about this size.
const ChartSize sparklineSize = ChartSize(120, 40);

/// One chart of the gallery.
final class GalleryEntry {
  /// Creates an entry named [name] of [chart], whose Excel chart carries the
  /// title [excelTitle], drawn in [theme] (`ChartTheme.office` when null) at
  /// [size].
  GalleryEntry({
    required this.name,
    required this.excelTitle,
    required this.chart,
    ChartTheme? theme,
    this.size = gallerySize,
  }) : theme = theme ?? ChartTheme.office;

  /// The name: the app's caption and the workbook's sheet name (cut to 31
  /// characters there).
  final String name;

  /// The title text of the Excel chart: the chart's title, or empty when it
  /// has none, in which case the Excel chart's automatic title is deleted.
  final String excelTitle;

  /// The chart.
  final Chart chart;

  /// The theme the app draws the chart in: the Office theme, or a copy of it
  /// that changes a value Excel's default chart does not have (an area's
  /// opacity). The workbook always writes Excel's default chart.
  final ChartTheme theme;

  /// The size the app draws the chart at: [gallerySize], or [sparklineSize]
  /// for a sparkline.
  final ChartSize size;

  @override
  bool operator ==(Object other) =>
      other is GalleryEntry &&
      name == other.name &&
      excelTitle == other.excelTitle &&
      chart == other.chart &&
      theme == other.theme &&
      size == other.size;

  @override
  int get hashCode => Object.hash(name, excelTitle, chart, theme, size);

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

GalleryEntry _entry(
  String name,
  Chart chart, {
  ChartTheme? theme,
  ChartSize size = gallerySize,
}) => GalleryEntry(
  name: name,
  excelTitle: chart.title?.text ?? '',
  chart: chart,
  theme: theme,
  size: size,
);

/// The categories of the owner's E1 table (`TALIMATLAR_J4.md` of
/// `test/fixtures/owner/charts`).
const List<String> _regions = <String>['Kuzey', 'Güney', 'Doğu', 'Batı'];

/// The format code of `turkish_amounts`.
const String turkishAmountFormat = '#,##0 "₺"';

/// The gallery: the 14 J3 charts of `packages/jet_charts_core/test/support/
/// gallery.dart` with the same names and data, then `one_series` (one series
/// with a title and a legend: Excel's default chart of one series hides its
/// legend) and `turkish_amounts` (Turkish month names, values in the format
/// [turkishAmountFormat]), then the 14 J4 charts of that file, with the same
/// names, data and themes: a smooth line, translucent areas, pies, donuts,
/// sparklines (at [sparklineSize]), scatter charts, combination charts and a
/// secondary value axis.
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
  ...j4Entries(),
];

/// The 14 J4 charts of `packages/jet_charts_core/test/support/gallery.dart`,
/// with the same names, data and themes, in its order.
List<GalleryEntry> j4Entries() => <GalleryEntry>[
  _entry(
    'line_smooth',
    _column(
      kind: ChartKind.line,
      title: 'A smooth and a straight line',
      series: <ChartSeries>[
        _series(
          'Smooth',
          <Object>['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          <double?>[4, 9, 3, 8, 6],
        ).copyWith(smooth: true),
        _series(
          'Straight',
          <Object>['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          <double?>[2, 5, null, 7, 9],
        ),
      ],
    ),
  ),
  _entry(
    'area_translucent',
    _column(
      kind: ChartKind.area,
      grouping: ChartGrouping.stacked,
      title: 'Translucent areas',
    ),
    theme: ChartTheme.office.copyWith(areaOpacity: 0.25, areaLine: true),
  ),
  _entry(
    'pie_basic',
    Chart(
      kind: ChartKind.pie,
      title: const ChartTitle(text: 'Sales by region'),
      series: <ChartSeries>[
        _series('Sales', _regions, <double?>[12, 18, 9, 15]),
      ],
      dataLabels: const ChartDataLabels(visible: true),
    ),
  ),
  _entry(
    'pie_small_slices',
    Chart(
      kind: ChartKind.pie,
      title: const ChartTitle(text: 'Small slices'),
      series: <ChartSeries>[
        _series(
          'Share',
          <Object>['Main', 'Second', 'Third', 'Fourth', 'Fifth'],
          <double?>[90, 4, 3, 2, 1],
        ),
      ],
      dataLabels: const ChartDataLabels(visible: true, showPercent: true),
    ),
  ),
  _entry(
    'pie_negative',
    Chart(
      kind: ChartKind.pie,
      series: <ChartSeries>[
        _series('B', _regions, <double?>[12, 18, -4, 9]),
      ],
      dataLabels: const ChartDataLabels(visible: true),
    ),
  ),
  _entry(
    'donut_center',
    Chart(
      kind: ChartKind.donut,
      series: <ChartSeries>[
        _series(
          'Satış',
          <Object>[..._regions, 'Merkez'],
          <double?>[12, 18, 3, 9, 3],
        ).copyWith(
          pointColors: <ChartColor?>[null, null, ChartColor.rgb(0xC0392B)],
        ),
      ],
      holeSizePercent: 55,
      centerText: 'Toplam 45',
      dataLabels: const ChartDataLabels(
        visible: true,
        showValue: false,
        showPercent: true,
        minShare: 0.1,
      ),
    ),
  ),
  _entry(
    'donut_two_series',
    Chart(
      kind: ChartKind.donut,
      title: const ChartTitle(text: 'Two years'),
      series: <ChartSeries>[
        _series('2025', _regions, <double?>[12, 18, 9, 15]),
        _series('2026', _regions, <double?>[14, 16, 11, 13]),
      ],
      dataLabels: const ChartDataLabels(visible: true),
    ),
  ),
  _entry(
    'sparkline_line',
    Chart(
      kind: ChartKind.sparkline,
      series: <ChartSeries>[
        _series('Refunds', const <Object>[], <double?>[4, 7, 5, 9, 6, 11, 8]),
      ],
      valueAxis: const ChartAxis(min: 0),
    ),
    size: sparklineSize,
  ),
  _entry(
    'sparkline_area',
    Chart(
      kind: ChartKind.sparkline,
      series: <ChartSeries>[
        _series('Refunds', const <Object>[], <double?>[
          4,
          7,
          5,
          9,
          6,
          11,
          8,
        ]).copyWith(kind: ChartKind.area),
      ],
      valueAxis: const ChartAxis(min: 0),
    ),
    theme: ChartTheme.office.copyWith(areaOpacity: 0.1),
    size: sparklineSize,
  ),
  _entry(
    'scatter_basic',
    Chart(
      kind: ChartKind.scatter,
      title: const ChartTitle(text: 'Price and volume'),
      series: <ChartSeries>[
        _series(
          'North',
          <Object>[1, 2, 3.5, 5, 7],
          <double?>[12, 18, 9, 15, 21],
        ),
        _series(
          'South',
          <Object>[1.5, 3, 4, 6, 8],
          <double?>[8, 11, 14, 10, 6],
        ),
      ],
      // Excel's default scatter has grid lines on both axes (E1, chart 4).
      categoryAxis: const ChartAxis(gridLines: true),
    ),
  ),
  _entry(
    'scatter_dates',
    Chart(
      kind: ChartKind.scatter,
      title: const ChartTitle(text: 'Orders by day'),
      series: <ChartSeries>[
        _series(
          'Orders',
          <Object>[
            DateTime(2026, 1, 1),
            DateTime(2026, 1, 4),
            DateTime(2026, 1, 9),
            DateTime(2026, 1, 15),
            DateTime(2026, 1, 22),
          ],
          <double?>[4, 7, 5, 9, 6],
        ),
      ],
      categoryAxis: const ChartAxis(formatCode: 'd mmm', gridLines: true),
    ),
  ),
  _entry(
    'combo_column_line',
    Chart(
      kind: ChartKind.combination,
      series: <ChartSeries>[
        _series('Satış', _regions, <double?>[12, 18, -4, 9]),
        _series('Adet', _regions, <double?>[
          120,
          95,
          140,
          80,
        ]).copyWith(kind: ChartKind.line, axis: ChartAxisBinding.secondary),
      ],
    ),
  ),
  _entry(
    'combo_area_column_line',
    Chart(
      kind: ChartKind.combination,
      title: const ChartTitle(text: 'Plan, sales and trend'),
      series: <ChartSeries>[
        _series('Plan', _quarters, <double?>[
          14,
          16,
          11,
          13,
        ]).copyWith(kind: ChartKind.area),
        _series('Sales', _quarters, <double?>[12, 18, 9, 15]),
        _series('Trend', _quarters, <double?>[
          10,
          13,
          12,
          14,
        ]).copyWith(kind: ChartKind.line),
      ],
    ),
  ),
  _entry(
    'line_secondary',
    Chart(
      kind: ChartKind.line,
      title: const ChartTitle(text: 'Sales and units'),
      series: <ChartSeries>[
        _series('Sales', _quarters, <double?>[12, 18, 9, 15]),
        _series('Units', _quarters, <double?>[
          120,
          95,
          140,
          80,
        ]).copyWith(axis: ChartAxisBinding.secondary),
      ],
      secondaryValueAxis: const ChartAxis(title: 'Units'),
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
