/// The fixtures of milestone C1 (chart parts in a workbook).
///
/// New in jet_office. Each fixture is a workbook of [XlsxWorkbook] whose
/// charts `XlsxSheet.addChart` draws on one sheet, so the parts reach the
/// Open XML SDK, LibreOffice and Excel inside a real file. Until C2 a
/// test-only host drew them; each chart carries the ids C1 gave it
/// (`xlsxChartWithIds`), so every part is still the one C1's Excel check
/// opened (`docs/excel-checks.md`, "C1"). The values follow the conventions
/// documented in `m1_fixtures.dart`; the charts' series refer to the sheet's
/// cells and cache their values. [c1Charts] gives each fixture's charts, in
/// part order, for `test/drawingml/chart/chart_fixtures_test.dart`.
library;

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/xlsx/chart.dart' show xlsxChartWithIds;

import 'fixture.dart';

/// One chart of a fixture: its typed form and the theme it is written in.
typedef C1Chart = ({DrawingChartSpace space, ChartTheme theme});

/// The fixtures of milestone C1.
List<Fixture> c1Fixtures() => <Fixture>[_kinds(), _options()];

/// The charts of the C1 fixture [name], in the order of their parts
/// (`xl/charts/chart1.xml` first).
List<C1Chart> c1Charts(String name) => switch (name) {
  'c1_kinds' => _kindsCharts(),
  'c1_options' => _optionsCharts(),
  _ => throw ArgumentError.value(name, 'name', 'is not a C1 fixture'),
};

/// The series id of series [series] of chart [chart], a GUID in braces.
String _seriesId(int chart, int series) =>
    '{00000000-00C1-0000-${chart.toString().padLeft(4, '0')}-'
    '${series.toString().padLeft(12, '0')}}';

/// The ids of chart [chart] (0-based: the part `chart{chart + 1}.xml`) with
/// [series] series.
DrawingChartIds _ids(int chart, int series) => DrawingChartIds(
  categoryAxis: 100000 + 2 * chart,
  valueAxis: 100001 + 2 * chart,
  series: <String>[for (int s = 0; s < series; s++) _seriesId(chart, s)],
);

/// Adds [charts] to [sheet] in order, each with its ids, in a grid of three
/// across, 8 columns by 15 rows each, from row 2, moving with its cells but
/// keeping its size: where C1's host drew them.
void _addCharts(XlsxSheet sheet, List<C1Chart> charts) {
  for (int i = 0; i < charts.length; i++) {
    final DrawingChartSpace space = charts[i].space;
    final int column = (i % 3) * 8;
    final int row = 1 + (i ~/ 3) * 15;
    sheet.addChart(
      xlsxChartWithIds(
        XlsxChart(
          space.chart,
          XlsxTwoCellAnchor(
            XlsxAnchorPoint(row, column),
            XlsxAnchorPoint(row + 15, column + 8),
            resize: XlsxPictureResize.move,
          ),
          theme: charts[i].theme,
          language: space.language,
          autoTitle: space.autoTitle,
        ),
        space.ids,
      ),
    );
  }
}

/// Sets [rows] on [sheet] from A1.
void _setRows(XlsxSheet sheet, List<List<Object?>> rows) {
  for (int r = 0; r < rows.length; r++) {
    for (int c = 0; c < rows[r].length; c++) {
      sheet.setCell(r, c, rows[r][c]);
    }
  }
}

// ---------------------------------------------------------------- c1_kinds

const List<String> _quarters = <String>['Q1', 'Q2', 'Q3', 'Q4'];
const List<num> _north = <num>[120, 135.25, 150, 142.5];
const List<num> _south = <num>[95.5, 110, 87.75, 128];

/// The series of `c1_kinds` named by column [column] (`B` or `C`) of `Data`.
ChartSeries _kindsSeries(String column, String name, List<num> values) =>
    ChartSeries(
      name: ChartData<String>(
        values: <String?>[name],
        reference: 'Data!\$$column\$1',
      ),
      categories: ChartData<Object>(
        values: _quarters,
        reference: r'Data!$A$2:$A$5',
      ),
      values: ChartData<double>(
        values: <double?>[for (final num v in values) v.toDouble()],
        reference: 'Data!\$$column\$2:\$$column\$5',
      ),
    );

/// The 12 kind and grouping charts of `c1_kinds`, in the Office theme.
List<C1Chart> _kindsCharts() {
  final List<C1Chart> charts = <C1Chart>[];
  for (final ChartKind kind in <ChartKind>[
    ChartKind.column,
    ChartKind.bar,
    ChartKind.line,
    ChartKind.area,
  ]) {
    for (final ChartGrouping grouping in ChartGrouping.values) {
      charts.add((
        space: DrawingChartSpace(
          chart: Chart(
            kind: kind,
            grouping: grouping,
            title: ChartTitle(text: '${kind.name}, ${grouping.name}'),
            series: <ChartSeries>[
              _kindsSeries('B', 'Kuzey', _north),
              _kindsSeries('C', 'Güney', _south),
            ],
          ),
          ids: _ids(charts.length, 2),
        ),
        theme: ChartTheme.office,
      ));
    }
  }
  return charts;
}

/// `c1_kinds`: the sheet `Data` (a header row and four quarters of `Kuzey`
/// and `Güney`) and on it a column, bar, line and area chart in each of the
/// three groupings, 12 in all, drawn in the Office theme.
Fixture _kinds() => Fixture(
  'c1_kinds',
  <String, List<List<String>>>{
    'Data': <List<String>>[
      <String>['Çeyrek', 'Kuzey', 'Güney'],
      for (int r = 0; r < 4; r++)
        <String>[_quarters[r], '${_north[r]}', '${_south[r]}'],
    ],
  },
  <String, List<List<Object?>>>{
    'Data': <List<Object?>>[
      <Object?>['Çeyrek', 'Kuzey', 'Güney'],
      for (int r = 0; r < 4; r++) <Object?>[_quarters[r], _north[r], _south[r]],
    ],
  },
  () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('Data');
    _setRows(sheet, <List<Object?>>[
      <Object?>['Çeyrek', 'Kuzey', 'Güney'],
      for (int r = 0; r < 4; r++) <Object?>[_quarters[r], _north[r], _south[r]],
    ]);
    _addCharts(sheet, _kindsCharts());
    return book.save();
  },
);

// -------------------------------------------------------------- c1_options

/// The sheet of `c1_options`, whose name needs quotes in a reference.
const String _sheet = "O'Brien";

/// Its name as a reference spells it.
const String _quoted = "'O''Brien'";

/// The four dates of column A.
final List<DateTime> _dates = <DateTime>[
  DateTime(2026, 1, 1),
  DateTime(2026, 2, 1),
  DateTime(2026, 3, 1),
  DateTime(2026, 4, 1),
];

/// The serials of [_dates].
const List<int> _serials = <int>[46023, 46054, 46082, 46113];

/// The value of series [s] (0 to 7) in row [r] (0 to 3): a whole number for
/// an even series, a half for an odd one.
num _value(int s, int r) => s.isEven ? 10 * s + 3 * r + 10 : 10 * s + r + 0.5;

/// The column letter of series [s]: `B` to `I`.
String _column(int s) => String.fromCharCode(0x42 + s);

/// Series [s] of `c1_options`, by reference to `O'Brien`.
ChartSeries _optionsSeries(int s, {String? formatCode, ChartColor? color}) {
  final String column = _column(s);
  return ChartSeries(
    name: ChartData<String>(
      values: <String?>['S${s + 1}'],
      reference: '$_quoted!\$$column\$1',
    ),
    categories: ChartData<Object>(
      values: _dates,
      reference: '$_quoted!\$A\$2:\$A\$5',
    ),
    values: ChartData<double>(
      values: <double?>[for (int r = 0; r < 4; r++) _value(s, r).toDouble()],
      reference: '$_quoted!\$$column\$2:\$$column\$5',
    ),
    formatCode: formatCode,
    color: color,
  );
}

/// The six charts of `c1_options`.
List<C1Chart> _optionsCharts() {
  final ChartTheme app = ChartTheme.office.copyWith(
    exportColors: ChartExportColors.fixed,
  );
  return <C1Chart>[
    // A title, a legend on top, axis titles, a fixed range and format codes.
    (
      space: DrawingChartSpace(
        chart: Chart(
          kind: ChartKind.column,
          title: const ChartTitle(text: 'Gelir & gider\n"2026"'),
          legend: const ChartLegend(position: ChartLegendPosition.top),
          categoryAxis: const ChartAxis(title: 'Ay', formatCode: 'mmm yy'),
          valueAxis: const ChartAxis(
            title: 'Tutar\nTL',
            min: 0,
            max: 100,
            majorUnit: 20,
            formatCode: '#,##0.00 "TL"',
            gridLines: true,
          ),
          series: <ChartSeries>[
            _optionsSeries(0, formatCode: '#,##0'),
            _optionsSeries(1, formatCode: '#,##0.0'),
          ],
        ),
        language: 'tr-TR',
        ids: _ids(0, 2),
      ),
      theme: ChartTheme.office,
    ),
    // A legend on the left, data labels with a format code and Excel's
    // automatic title.
    (
      space: DrawingChartSpace(
        chart: Chart(
          kind: ChartKind.line,
          legend: const ChartLegend(position: ChartLegendPosition.left),
          dataLabels: const ChartDataLabels(visible: true, formatCode: '0.0'),
          series: <ChartSeries>[_optionsSeries(2)],
        ),
        language: 'tr-TR',
        ids: _ids(1, 1),
        autoTitle: true,
      ),
      theme: ChartTheme.office,
    ),
    // A legend on the right and hidden axes without grid lines.
    (
      space: DrawingChartSpace(
        chart: Chart(
          kind: ChartKind.area,
          grouping: ChartGrouping.stacked,
          legend: const ChartLegend(position: ChartLegendPosition.right),
          categoryAxis: const ChartAxis(visible: false),
          valueAxis: const ChartAxis(visible: false),
          series: <ChartSeries>[_optionsSeries(3), _optionsSeries(4)],
        ),
        language: 'tr-TR',
        ids: _ids(2, 2),
      ),
      theme: ChartTheme.office,
    ),
    // A hidden legend and literal data: no references at all.
    (
      space: DrawingChartSpace(
        chart: Chart(
          kind: ChartKind.bar,
          title: const ChartTitle(text: 'Literal'),
          legend: const ChartLegend(visible: false),
          series: <ChartSeries>[
            for (final (String name, List<double?> values)
                in <(String, List<double?>)>[
                  ('Elma', <double?>[3, 1.5, 4]),
                  ('Armut', <double?>[2, null, 5.25]),
                ])
              ChartSeries(
                name: ChartData<String>(values: <String?>[name]),
                categories: ChartData<Object>(values: <Object?>['a', 'b', 'c']),
                values: ChartData<double>(values: values),
              ),
          ],
        ),
        language: 'tr-TR',
        ids: _ids(3, 2),
      ),
      theme: ChartTheme.office,
    ),
    // Date categories shown in a date format.
    (
      space: DrawingChartSpace(
        chart: Chart(
          kind: ChartKind.column,
          title: const ChartTitle(text: 'Tarihler'),
          categoryAxis: const ChartAxis(formatCode: 'dd.mm.yyyy'),
          series: <ChartSeries>[_optionsSeries(5)],
        ),
        language: 'tr-TR',
        ids: _ids(4, 1),
      ),
      theme: ChartTheme.office,
    ),
    // An app theme with fixed colours and eight series, past the six
    // accents, the last with a colour of its own.
    (
      space: DrawingChartSpace(
        chart: Chart(
          kind: ChartKind.line,
          title: const ChartTitle(text: 'Sekiz seri'),
          series: <ChartSeries>[
            for (int s = 0; s < 7; s++) _optionsSeries(s),
            _optionsSeries(7, color: ChartColor.rgb(0x123456)),
          ],
        ),
        language: 'tr-TR',
        ids: _ids(5, 8),
      ),
      theme: app,
    ),
  ];
}

/// `c1_options`: the sheet `O'Brien` (a header row, four dates and eight
/// series) and on it six charts of the options: a title, legends on top,
/// left and right and a hidden one, axis titles, a fixed range, format
/// codes, data labels, hidden axes without grid lines, literal data, date
/// categories, an automatic title, and eight series in an app theme with
/// fixed colours.
Fixture _options() => Fixture(
  'c1_options',
  <String, List<List<String>>>{
    _sheet: <List<String>>[
      <String>['Tarih', for (int s = 0; s < 8; s++) 'S${s + 1}'],
      for (int r = 0; r < 4; r++)
        <String>[
          '${_serials[r]}',
          for (int s = 0; s < 8; s++) '${_value(s, r)}',
        ],
    ],
  },
  <String, List<List<Object?>>>{
    _sheet: <List<Object?>>[
      <Object?>['Tarih', for (int s = 0; s < 8; s++) 'S${s + 1}'],
      for (int r = 0; r < 4; r++)
        <Object?>[_serials[r], for (int s = 0; s < 8; s++) _value(s, r)],
    ],
  },
  () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet(_sheet);
    _setRows(sheet, <List<Object?>>[
      <Object?>['Tarih', for (int s = 0; s < 8; s++) 'S${s + 1}'],
      for (int r = 0; r < 4; r++)
        <Object?>[
          XlsxDate(_dates[r].year, _dates[r].month, _dates[r].day),
          for (int s = 0; s < 8; s++) _value(s, r),
        ],
    ]);
    _addCharts(sheet, _optionsCharts());
    return book.save();
  },
);
