/// The fixtures of milestone C2 (charts the workbook model adds).
///
/// New in jet_office. Each fixture is a workbook of [XlsxWorkbook] whose
/// chart data `XlsxSheet.writeChartData` writes to cells and whose charts
/// `XlsxSheet.addChart` adds, bound to those cells, with the ids their part
/// numbers give (`xlsxChartPartIds`). The values follow the conventions
/// documented in `m1_fixtures.dart`. [c2Charts] gives each fixture's charts,
/// in part order, as the parts must hold them, with the references spelled
/// out, for `test/drawingml/chart/chart_fixtures_test.dart`.
library;

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/xlsx/chart.dart' show xlsxChartPartIds;

import 'c1_fixtures.dart' show C1Chart;
import 'fixture.dart';

/// The fixtures of milestone C2.
List<Fixture> c2Fixtures() => <Fixture>[_kinds(), _data()];

/// The charts of the C2 fixture [name], in the order of their parts
/// (`xl/charts/chart1.xml` first), bound to the cells their data went to.
List<C1Chart> c2Charts(String name) => switch (name) {
  'c2_kinds' => _expected(_kindsCharts()),
  'c2_data' => _expected(_dataCharts()),
  _ => throw ArgumentError.value(name, 'name', 'is not a C2 fixture'),
};

/// One chart of a fixture as it is made: `chart` unbound, its data written
/// at (`row`, `column`) of `dataSheet` (none when `row` is `null`), and the
/// chart added at `anchor` in `theme` and `language`.
typedef _Made = ({
  Chart chart,
  String dataSheet,
  int? row,
  int column,
  XlsxAnchor anchor,
  ChartTheme theme,
  String language,
});

/// The charts of [made], bound, with the ids of their part numbers.
List<C1Chart> _expected(List<_Made> made) => <C1Chart>[
  for (int i = 0; i < made.length; i++)
    (
      space: DrawingChartSpace(
        chart: made[i].row == null
            ? made[i].chart
            : _bound(
                made[i].chart,
                made[i].dataSheet,
                made[i].row!,
                made[i].column,
              ),
        language: made[i].language,
        ids: xlsxChartPartIds(i + 1, made[i].chart.series.length),
      ),
      theme: made[i].theme,
    ),
];

/// [sheet] as a reference's prefix spells it.
String _prefix(String sheet) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(sheet)
    ? '$sheet!'
    : "'${sheet.replaceAll("'", "''")}'!";

/// The absolute reference to rows [first] to [last] (0-based) of column
/// [column] of [sheet].
String _ref(String sheet, int column, int first, [int? last]) {
  final String letter = String.fromCharCode(0x41 + column);
  return '${_prefix(sheet)}\$$letter\$${first + 1}'
      '${last == null || last == first ? '' : ':\$$letter\$${last + 1}'}';
}

/// [chart] bound to its table at ([row], [column]) of [sheet], as
/// `writeChartData` lays it out: names across the header row, the
/// categories down the first column (a scatter series' x values in a column
/// of their own, left of its y values), then one column per series.
Chart _bound(Chart chart, String sheet, int row, int column) {
  final bool scatter = chart.kind == ChartKind.scatter;
  return chart.copyWith(
    series: <ChartSeries>[
      for (final (int i, ChartSeries s) in chart.series.indexed)
        _boundSeries(
          s,
          sheet,
          row,
          x: scatter ? column + 2 * i : column,
          y: scatter ? column + 2 * i + 1 : column + 1 + i,
        ),
    ],
  );
}

/// [s] bound to its name in row [row] and its values below it in column [y]
/// of [sheet], and to its categories below row [row] in column [x].
ChartSeries _boundSeries(
  ChartSeries s,
  String sheet,
  int row, {
  required int x,
  required int y,
}) => s.copyWith(
  name: s.name.copyWith(reference: _ref(sheet, y, row)),
  categories: s.categories.copyWith(
    reference: _ref(sheet, x, row + 1, row + s.categories.values.length),
  ),
  values: s.values.copyWith(
    reference: _ref(sheet, y, row + 1, row + s.values.values.length),
  ),
);

/// The cells `writeChartData` sets for [chart] at ([row], [column]):
/// (row, column) to the value, both 0-based.
Map<(int, int), Object> _cells(Chart chart, int row, int column) {
  final bool scatter = chart.kind == ChartKind.scatter;
  final Map<(int, int), Object> cells = <(int, int), Object>{};
  for (final (int i, ChartSeries s) in chart.series.indexed) {
    final int x = scatter ? column + 2 * i : column;
    final int y = scatter ? x + 1 : column + 1 + i;
    cells[(row, y)] = s.name.values.single!;
    for (final (int j, Object? c) in s.categories.values.indexed) {
      cells[(row + 1 + j, x)] = c!;
    }
    for (final (int j, double? v) in s.values.values.indexed) {
      cells[(row + 1 + j, y)] = v!;
    }
  }
  return cells;
}

/// The serial of [date] in the 1900 date system.
int _serial(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(1899, 12, 30)).inDays;

/// What the file stores for [value]: a whole number without a decimal
/// point, a date as its serial.
String _stored(Object value) => switch (value) {
  final DateTime d => '${_serial(d)}',
  final double v when v == v.truncateToDouble() => '${v.toInt()}',
  final num v => '$v',
  _ => '$value',
};

/// What a reader shows for [value]: a date as its serial.
Object _shown(Object value) => value is DateTime ? _serial(value) : value;

/// What a fixture's sheets store and show: its `storedValues` and
/// `expectedValues`.
typedef _Values = ({
  Map<String, List<List<String>>> stored,
  Map<String, List<List<Object?>>> expected,
});

/// The stored and expected rows of [sheets], with the data [made] writes.
_Values _values(List<_Made> made, List<String> sheets) {
  final Map<String, Map<(int, int), Object>> bySheet =
      <String, Map<(int, int), Object>>{
        for (final String s in sheets) s: <(int, int), Object>{},
      };
  for (final _Made m in made) {
    if (m.row == null) continue;
    bySheet[m.dataSheet]!.addAll(_cells(m.chart, m.row!, m.column));
  }
  final Map<String, List<List<String>>> stored = <String, List<List<String>>>{};
  final Map<String, List<List<Object?>>> expected =
      <String, List<List<Object?>>>{};
  bySheet.forEach((String sheet, Map<(int, int), Object> cells) {
    int rows = 0;
    int columns = 0;
    for (final (int r, int c) in cells.keys) {
      if (r + 1 > rows) rows = r + 1;
      if (c + 1 > columns) columns = c + 1;
    }
    stored[sheet] = <List<String>>[
      for (int r = 0; r < rows; r++)
        <String>[
          for (int c = 0; c < columns; c++)
            cells[(r, c)] == null ? '' : _stored(cells[(r, c)]!),
        ],
    ];
    expected[sheet] = <List<Object?>>[
      for (int r = 0; r < rows; r++)
        <Object?>[
          for (int c = 0; c < columns; c++)
            cells[(r, c)] == null ? null : _shown(cells[(r, c)]!),
        ],
    ];
  });
  return (stored: stored, expected: expected);
}

/// A series [name] over [categories] with [values], unbound.
ChartSeries _series(
  String name,
  List<Object> categories,
  List<double> values, {
  ChartKind? kind,
  ChartAxisBinding axis = ChartAxisBinding.primary,
  String? formatCode,
  bool smooth = false,
}) => ChartSeries(
  name: ChartData<String>(values: <String?>[name]),
  categories: ChartData<Object>(values: categories),
  values: ChartData<double>(values: values),
  kind: kind,
  axis: axis,
  formatCode: formatCode,
  smooth: smooth,
);

/// A two-cell anchor of 8 columns by 15 rows from ([row], [column]),
/// moving and sizing with its cells.
XlsxAnchor _anchor(int row, int column) => XlsxTwoCellAnchor(
  XlsxAnchorPoint(row, column),
  XlsxAnchorPoint(row + 15, column + 8),
);

// ---------------------------------------------------------------- c2_kinds

const List<Object> _costs = <Object>['Kira', 'Maaş', 'Vergi', 'Diğer'];
const List<Object> _quarters = <Object>['Q1', 'Q2', 'Q3', 'Q4'];

/// The charts of `c2_kinds`: each one's data in a block of seven rows of
/// columns A to D of `Data`, the charts two across from column G.
List<_Made> _kindsCharts() {
  final List<Chart> charts = <Chart>[
    Chart(
      kind: ChartKind.pie,
      title: const ChartTitle(text: 'Giderler'),
      dataLabels: const ChartDataLabels(visible: true, showPercent: true),
      series: <ChartSeries>[
        _series('Gider', _costs, <double>[40, 35.5, 15, 9.5]),
      ],
    ),
    Chart(
      kind: ChartKind.donut,
      title: const ChartTitle(text: 'İki yıl'),
      holeSizePercent: 50,
      series: <ChartSeries>[
        _series('2025', _costs, <double>[30, 25, 25, 20]),
        _series('2026', _costs, <double>[40, 35.5, 15, 9.5]),
      ],
    ),
    Chart(
      kind: ChartKind.scatter,
      title: const ChartTitle(text: 'Ölçümler'),
      categoryAxis: const ChartAxis(title: 'x'),
      valueAxis: const ChartAxis(title: 'y', gridLines: true),
      series: <ChartSeries>[
        _series(
          'A',
          <Object>[1.5, 2, 3.25, 4, 5.5],
          <double>[2, 3.5, 3, 5, 6.25],
        ),
        _series('B', <Object>[1, 2.5, 3, 4.75, 6], <double>[1, 1.5, 4, 4.5, 5]),
      ],
    ),
    Chart(
      kind: ChartKind.combination,
      title: const ChartTitle(text: 'Gelir ve hedef'),
      series: <ChartSeries>[
        // A combination's series of no kind is a column, and reads as one.
        _series('Gelir', _quarters, <double>[
          120,
          135.25,
          150,
          142.5,
        ], kind: ChartKind.column),
        _series('Hedef', _quarters, <double>[
          125,
          130,
          140,
          150,
        ], kind: ChartKind.line),
      ],
    ),
    Chart(
      kind: ChartKind.combination,
      title: const ChartTitle(text: 'Gelir ve marj'),
      secondaryValueAxis: const ChartAxis(formatCode: '0%'),
      series: <ChartSeries>[
        _series('Gelir', _quarters, <double>[
          120,
          135.25,
          150,
          142.5,
        ], kind: ChartKind.column),
        _series(
          'Marj',
          _quarters,
          <double>[0.12, 0.15, 0.11, 0.18],
          kind: ChartKind.line,
          axis: ChartAxisBinding.secondary,
          formatCode: '0%',
        ),
      ],
    ),
    Chart(
      kind: ChartKind.combination,
      title: const ChartTitle(text: 'Üç tür'),
      series: <ChartSeries>[
        _series('Stok', _quarters, <double>[
          60,
          72,
          65,
          80,
        ], kind: ChartKind.area),
        _series('Gelir', _quarters, <double>[
          120,
          135.25,
          150,
          142.5,
        ], kind: ChartKind.column),
        _series('Hedef', _quarters, <double>[
          125,
          130,
          140,
          150,
        ], kind: ChartKind.line),
      ],
    ),
    Chart(
      kind: ChartKind.line,
      title: const ChartTitle(text: 'Eğri'),
      series: <ChartSeries>[
        _series('Kuzey', _quarters, <double>[
          120,
          135.25,
          150,
          142.5,
        ], smooth: true),
        _series('Güney', _quarters, <double>[
          95.5,
          110,
          87.75,
          128,
        ], smooth: true),
      ],
    ),
  ];
  return <_Made>[
    for (final (int i, Chart chart) in charts.indexed)
      (
        chart: chart,
        dataSheet: 'Data',
        row: 7 * i,
        column: 0,
        anchor: _anchor((i ~/ 2) * 15, 6 + (i % 2) * 8),
        theme: ChartTheme.office,
        language: 'en-US',
      ),
  ];
}

/// `c2_kinds`: the sheet `Data` with a pie, a donut of two series, a scatter
/// chart of numeric x values, a column and line combination, the same with
/// the line on the secondary axis, a column, area and line combination and
/// a smooth line chart, each beside its data, in the Office theme.
Fixture _kinds() {
  final List<_Made> made = _kindsCharts();
  final _Values values = _values(made, <String>['Data']);
  return Fixture(
    'c2_kinds',
    values.stored,
    values.expected,
    () => _buildOn(<String>['Data'], 'Data', made),
  );
}

/// A workbook of [sheets] whose charts [made] adds to [chartSheet], each
/// after writing its data.
XlsxResult _buildOn(List<String> sheets, String chartSheet, List<_Made> made) {
  final XlsxWorkbook book = XlsxWorkbook();
  for (final String s in sheets) {
    book.addSheet(s);
  }
  for (final _Made m in made) {
    final Chart chart = m.row == null
        ? m.chart
        : book.sheet(m.dataSheet).writeChartData(m.chart, m.row!, m.column);
    book
        .sheet(chartSheet)
        .addChart(
          XlsxChart(chart, m.anchor, theme: m.theme, language: m.language),
        );
  }
  return book.save();
}

// ----------------------------------------------------------------- c2_data

/// The sheet of `c2_data`'s data, whose name needs quotes in a reference.
const String _dataSheet = "O'Brien";

/// The sheet of `c2_data`'s charts.
const String _board = 'Pano';

/// The charts of `c2_data`: dates and format codes, an app theme with fixed
/// colours, and literal data, on `Pano`, their data on `O'Brien`.
List<_Made> _dataCharts() {
  final List<DateTime> months = <DateTime>[
    DateTime(2026, 1, 1),
    DateTime(2026, 2, 1),
    DateTime(2026, 3, 1),
    DateTime(2026, 4, 1),
  ];
  const List<Object> days = <Object>['Pzt', 'Sal', 'Çar', 'Per', 'Cum'];
  final ChartTheme app = ChartTheme.office.copyWith(
    exportColors: ChartExportColors.fixed,
  );
  return <_Made>[
    // Date categories in a date format, values in a currency format.
    (
      chart: Chart(
        kind: ChartKind.column,
        title: const ChartTitle(text: 'Gelir ve gider'),
        categoryAxis: const ChartAxis(formatCode: 'dd.mm.yyyy'),
        valueAxis: const ChartAxis(formatCode: '#,##0 "TL"', gridLines: true),
        series: <ChartSeries>[
          _series('Gelir', months, <double>[
            1250.5,
            980,
            1430.25,
            1105,
          ], formatCode: '#,##0.00 "TL"'),
          _series('Gider', months, <double>[
            800,
            760.75,
            910,
            870,
          ], formatCode: '#,##0.00 "TL"'),
        ],
      ),
      dataSheet: _dataSheet,
      row: 0,
      column: 0,
      anchor: _anchor(0, 0),
      theme: ChartTheme.office,
      language: 'tr-TR',
    ),
    // An app theme with fixed colours.
    (
      chart: Chart(
        kind: ChartKind.line,
        title: const ChartTitle(text: 'Haftalık'),
        series: <ChartSeries>[
          _series('Ziyaret', days, <double>[120, 135, 128, 150, 160]),
          _series('Satış', days, <double>[12, 15, 11, 18, 20]),
        ],
      ),
      dataSheet: _dataSheet,
      row: 6,
      column: 0,
      anchor: _anchor(0, 8),
      theme: app,
      language: 'tr-TR',
    ),
    // Literal data: no references, no cells.
    (
      chart: Chart(
        kind: ChartKind.bar,
        title: const ChartTitle(text: 'Literal'),
        series: <ChartSeries>[
          _series('Elma', <Object>['a', 'b', 'c'], <double>[3, 1.5, 4]),
        ],
      ),
      dataSheet: _dataSheet,
      row: null,
      column: 0,
      anchor: _anchor(15, 0),
      theme: ChartTheme.office,
      language: 'tr-TR',
    ),
  ];
}

/// `c2_data`: the data of two charts on `O'Brien`, written with dates and
/// format codes, and on `Pano` three charts: a column chart of date
/// categories in currency formats, a line chart in an app theme with fixed
/// colours, and a bar chart of literal data.
Fixture _data() {
  final List<_Made> made = _dataCharts();
  final _Values values = _values(made, <String>[_dataSheet, _board]);
  return Fixture(
    'c2_data',
    values.stored,
    values.expected,
    () => _buildOn(<String>[_dataSheet, _board], _board, made),
  );
}
