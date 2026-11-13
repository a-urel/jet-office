/// Writes the workbooks the owner opens in the C2 Excel check (the XLSX
/// chart host), to a directory that is created.
///
/// ```bash
/// dart run tool/write_c2_check.dart build/c2
/// ```
///
/// - `c2_kinds.xlsx`, `c2_data.xlsx`, `c1_kinds.xlsx`, `c1_options.xlsx`:
///   the chart fixtures of `allFixtures()`, every chart added by the model.
/// - `c2_dashboard.xlsx`: a dashboard as Monépro would export it. The sheet
///   `Veri` holds the data of eight charts, written by
///   `XlsxSheet.writeChartData`; the sheet `Pano`, active, holds the charts,
///   two across, bound to those cells: a clustered column, a stacked bar, a
///   smooth and a straight line in an app theme with fixed colours, a
///   stacked area, a pie, a donut of two series, a scatter chart of numeric
///   x values and a column with a line on the secondary axis. Each chart's
///   frame is named after the chart of the gallery app
///   (`packages/jet_charts_flutter/example/lib/gallery.dart`) whose data and
///   title it shows (`_chartNames`); the line's theme is the light one of
///   the app's Monépro look page (`monepro.dart`), copied here, as this
///   package never depends on the app.
/// - `c2_edited/`: the owner's `chart_reference.xlsx` and
///   `chart_reference_j4.xlsx` (`test/fixtures/owner/charts/`) edited in one
///   transaction of the sheet `Veri`: chart 1 replaced by a pie of its first
///   series, chart 2 moved 10 rows down, chart 3 removed, two rows inserted
///   at row 2, the sheet renamed `Veri 2026`, and a column chart
///   `Eklenen grafik` of the series of the (now second) moved chart added
///   below every chart; and `<name>_undone.xlsx`, the same edits made on the
///   file opened again and undone, which must equal the owner's file
///   (`comparePackages` finds no difference but the bookkeeping the model
///   recomputes, `dimension` and `spans`, else the tool fails).
///
/// The steps are in `test/fixtures/owner/charts/TALIMATLAR_C2.md` (Turkish);
/// the results go in `docs/excel-checks.md`, "C2", from the owner only. Run
/// from the repository root. Exit code 2 on unusable arguments, 1 on any
/// error.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../test/fixtures/fixtures.dart';
import 'src/part_compare.dart';

void main(List<String> args) {
  exitCode = runC2Check(args, out: stdout, err: stderr);
}

/// Runs the tool with [args], printing each file written to [out] and
/// problems to [err]; returns the exit code.
int runC2Check(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 1) {
    err.writeln('usage: dart run tool/write_c2_check.dart <outDir>');
    return 2;
  }
  try {
    writeC2Check(args.single).forEach(out.writeln);
  } on Object catch (e) {
    err.writeln('write_c2_check failed: $e');
    return 1;
  }
  return 0;
}

/// The names of the fixtures written as they are, in order.
const List<String> _fixtureNames = <String>[
  'c2_kinds',
  'c2_data',
  'c1_kinds',
  'c1_options',
];

/// The owner's workbooks edited into `c2_edited/`, in order.
const List<String> _ownerNames = <String>[
  'chart_reference',
  'chart_reference_j4',
];

/// The names of `c2_dashboard.xlsx`'s charts, in order: each the name of
/// the gallery app's chart whose data and title it shows, but `bar_stacked`,
/// `bar_clustered` stacked (the gallery has no stacked bar).
const List<String> _chartNames = <String>[
  'column_clustered',
  'bar_stacked',
  'line_smooth',
  'area_stacked',
  'pie_basic',
  'donut_two_series',
  'scatter_basic',
  'combo_column_line',
];

/// Writes the C2 check's files to [dir] and returns their paths, in the
/// order of the library comment. Throws a [StateError] when an undone file
/// differs from the owner's.
List<String> writeC2Check(String dir) {
  final Map<String, Fixture> fixtures = <String, Fixture>{
    for (final Fixture f in allFixtures()) f.name: f,
  };
  final List<String> paths = <String>[
    for (final String name in _fixtureNames)
      _write('$dir/$name.xlsx', fixtures[name]!.build()),
    _write('$dir/c2_dashboard.xlsx', _dashboard()),
  ];
  for (final String name in _ownerNames) {
    final Uint8List original = File(
      'test/fixtures/owner/charts/$name.xlsx',
    ).readAsBytesSync();
    final XlsxWorkbook edited = XlsxWorkbook.open(original);
    _edit(edited);
    paths.add(_write('$dir/c2_edited/$name.xlsx', edited.save().bytes));
    final XlsxWorkbook undone = XlsxWorkbook.open(original);
    undone.undo(_edit(undone));
    final Uint8List back = undone.save().bytes;
    final List<String> differences = comparePackages(
      original,
      back,
      ignoreBookkeeping: true,
    );
    if (differences.isNotEmpty) {
      throw StateError(
        '$name: undoing the edits does not give the file back: '
        '${differences.join('; ')}',
      );
    }
    paths.add(_write('$dir/c2_edited/${name}_undone.xlsx', back));
  }
  return paths;
}

String _write(String path, Uint8List bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  return path;
}

// ------------------------------------------------------------ c2_dashboard

const List<String> _quarters = <String>['Q1', 'Q2', 'Q3', 'Q4'];
const List<String> _regions = <String>['Kuzey', 'Güney', 'Doğu', 'Batı'];

ChartSeries _series(String name, List<Object> categories, List<double?> v) =>
    ChartSeries(
      name: ChartData<String>(values: <String?>[name]),
      categories: ChartData<Object>(values: categories),
      values: ChartData<double>(values: v),
    );

/// The gallery's three series North, South and West over the quarters.
List<ChartSeries> _three() => <ChartSeries>[
  _series('North', _quarters, <double?>[12, 18, 9, 15]),
  _series('South', _quarters, <double?>[8, 11, 14, 10]),
  _series('West', _quarters, <double?>[5, 7, 6, 13]),
];

/// The light theme of the gallery app's Monépro look page
/// (`packages/jet_charts_flutter/example/lib/monepro.dart`): its palette,
/// font family and colours, with fixed colours in the file.
final ChartTheme _moneproLight = ChartTheme.fromColors(
  palette: <ChartColor>[
    ChartColor.rgb(0x2563EB),
    ChartColor.rgb(0x10B981),
    ChartColor.rgb(0xF59E0B),
    ChartColor.rgb(0xEF4444),
    ChartColor.rgb(0x8B5CF6),
  ],
  fontFamily: 'DM Sans',
  text: ChartColor.rgb(0x1F2937),
  background: ChartColor.rgb(0xFFFFFF),
);

/// The dashboard's charts, in the order of [_chartNames], each with
/// its theme.
List<(Chart, ChartTheme)> _dashboardCharts() => <(Chart, ChartTheme)>[
  (
    Chart(
      kind: ChartKind.column,
      title: const ChartTitle(text: 'Sales by quarter'),
      series: _three(),
    ),
    ChartTheme.office,
  ),
  (
    Chart(
      kind: ChartKind.bar,
      grouping: ChartGrouping.stacked,
      title: const ChartTitle(text: 'Sales by quarter'),
      series: _three(),
    ),
    ChartTheme.office,
  ),
  (
    Chart(
      kind: ChartKind.line,
      title: const ChartTitle(text: 'A smooth and a straight line'),
      series: <ChartSeries>[
        _series(
          'Smooth',
          const <Object>['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          <double?>[4, 9, 3, 8, 6],
        ).copyWith(smooth: true),
        _series(
          'Straight',
          const <Object>['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          <double?>[2, 5, null, 7, 9],
        ),
      ],
    ),
    _moneproLight,
  ),
  (
    Chart(
      kind: ChartKind.area,
      grouping: ChartGrouping.stacked,
      title: const ChartTitle(text: 'Sales by quarter'),
      series: _three(),
    ),
    ChartTheme.office,
  ),
  (
    Chart(
      kind: ChartKind.pie,
      title: const ChartTitle(text: 'Sales by region'),
      series: <ChartSeries>[
        _series('Sales', _regions, <double?>[12, 18, 9, 15]),
      ],
      dataLabels: const ChartDataLabels(visible: true),
    ),
    ChartTheme.office,
  ),
  (
    Chart(
      kind: ChartKind.donut,
      title: const ChartTitle(text: 'Two years'),
      series: <ChartSeries>[
        _series('2025', _regions, <double?>[12, 18, 9, 15]),
        _series('2026', _regions, <double?>[14, 16, 11, 13]),
      ],
      dataLabels: const ChartDataLabels(visible: true),
    ),
    ChartTheme.office,
  ),
  (
    Chart(
      kind: ChartKind.scatter,
      title: const ChartTitle(text: 'Price and volume'),
      series: <ChartSeries>[
        _series(
          'North',
          const <Object>[1, 2, 3.5, 5, 7],
          <double?>[12, 18, 9, 15, 21],
        ),
        _series(
          'South',
          const <Object>[1.5, 3, 4, 6, 8],
          <double?>[8, 11, 14, 10, 6],
        ),
      ],
      categoryAxis: const ChartAxis(gridLines: true),
    ),
    ChartTheme.office,
  ),
  (
    Chart(
      kind: ChartKind.combination,
      series: <ChartSeries>[
        _series('Satış', _regions, <double?>[
          12,
          18,
          -4,
          9,
        ]).copyWith(kind: ChartKind.column),
        _series('Adet', _regions, <double?>[
          120,
          95,
          140,
          80,
        ]).copyWith(kind: ChartKind.line, axis: ChartAxisBinding.secondary),
      ],
    ),
    ChartTheme.office,
  ),
];

/// `c2_dashboard.xlsx`: each chart's data in a block of eight rows of
/// `Veri`, the charts on `Pano`, two across, each 8 columns by 15 rows with
/// a free column and row between them. No chart asks for Excel's automatic
/// title: a chart without a title shows none, as the app draws it (Excel
/// would show `Grafik Başlığı` on the combination of two series).
Uint8List _dashboard() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet data = book.addSheet('Veri');
  final XlsxSheet board = book.addSheet('Pano');
  for (final (int i, (Chart chart, ChartTheme theme))
      in _dashboardCharts().indexed) {
    final int row = (i ~/ 2) * 16;
    final int column = (i % 2) * 9;
    board.addChart(
      XlsxChart(
        data.writeChartData(chart, 8 * i, 0),
        XlsxTwoCellAnchor(
          XlsxAnchorPoint(row, column),
          XlsxAnchorPoint(row + 15, column + 8),
        ),
        name: _chartNames[i],
        theme: theme,
        language: 'tr-TR',
      ),
    );
  }
  book.activeSheet = board;
  return book.save().bytes;
}

// --------------------------------------------------------------- c2_edited

/// [s] with only its name, categories and values, references and caches as
/// read: what any chart kind the writer writes can take.
ChartSeries _plain(ChartSeries s) =>
    ChartSeries(name: s.name, categories: s.categories, values: s.values);

/// [anchor] moved [rows] rows down, its size and offsets kept.
XlsxAnchor _down(XlsxAnchor anchor, int rows) {
  XlsxAnchorPoint shift(XlsxAnchorPoint p) => XlsxAnchorPoint(
    p.row + rows,
    p.column,
    offsetX: p.offsetX,
    offsetY: p.offsetY,
  );
  return switch (anchor) {
    final XlsxTwoCellAnchor a => XlsxTwoCellAnchor(
      shift(a.from),
      shift(a.to),
      resize: a.resize,
    ),
    final XlsxOneCellAnchor a => XlsxOneCellAnchor(
      shift(a.from),
      width: a.width,
      height: a.height,
    ),
  };
}

/// Makes the C2 edits on the sheet `Veri` of [book] in one transaction and
/// returns it.
XlsxChangeSet _edit(XlsxWorkbook book) {
  final XlsxSheet sheet = book.sheet('Veri');
  return book.transaction(() {
    final List<XlsxSheetChart> charts = sheet.charts;
    final Chart first = charts[0].view!;
    sheet
      ..replaceChartAt(
        0,
        Chart(
          kind: ChartKind.pie,
          title: const ChartTitle(text: 'Pasta'),
          dataLabels: const ChartDataLabels(visible: true, showPercent: true),
          series: <ChartSeries>[_plain(first.series.first)],
        ),
      )
      ..moveChartAt(1, _down(charts[1].anchor, 10))
      ..removeChartAt(2)
      ..insertRows(1, 2);
    book.renameSheet(sheet, 'Veri 2026');
    // The moved chart's series, their references shifted and renamed.
    final List<XlsxSheetChart> now = sheet.charts;
    int below = 0;
    for (final XlsxSheetChart c in now) {
      final XlsxAnchor a = c.anchor;
      final int bottom = a is XlsxTwoCellAnchor ? a.to.row : a.from.row + 15;
      if (bottom > below) below = bottom;
    }
    sheet.addChart(
      XlsxChart(
        Chart(
          kind: ChartKind.column,
          title: const ChartTitle(text: 'Eklenen grafik'),
          series: <ChartSeries>[
            for (final ChartSeries s in now[1].view!.series) _plain(s),
          ],
        ),
        XlsxTwoCellAnchor(
          XlsxAnchorPoint(below + 2, 0),
          XlsxAnchorPoint(below + 17, 8),
        ),
        name: 'Eklenen grafik',
        language: 'tr-TR',
      ),
    );
  });
}
