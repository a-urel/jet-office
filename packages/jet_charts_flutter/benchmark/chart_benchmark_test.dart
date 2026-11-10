// The benchmark prints its table; `print` is its output, as in the
// repository's other benchmarks.
// ignore_for_file: avoid_print

/// Times `layoutChart` and `paintChartPrimitives` on dashboard charts and on
/// large series: a 10,000-point line, 3,650 categories of two columns, a
/// 10,000-point scatter chart and a pie of 60 slices.
///
/// Records figures and fails on nothing (`docs/benchmark.md`). Run it with
/// `flutter test benchmark` from this package's folder; the gate does not run
/// it. Flutter's browser tests compile only files under `test/`, so for
/// Chrome copy this file to `test/zz_chart_benchmark_test.dart`, run
/// `flutter test --platform chrome test/zz_chart_benchmark_test.dart` and
/// delete the copy (`docs/benchmark.md`).
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

const int _warmUp = 5;
const int _runs = 20;

ChartSeries _series(String name, int count, double phase) {
  final List<Object> categories = <Object>[
    for (int i = 0; i < count; i++) 'Cat ${i + 1}',
  ];
  final List<double?> values = <double?>[
    for (int i = 0; i < count; i++)
      50 + 30 * ((i * 7 + phase * 13) % 17) / 17 + (i % 11) * 2 + phase,
  ];
  return ChartSeries(
    name: ChartData<String>(values: <String?>[name]),
    categories: ChartData<Object>(values: categories),
    values: ChartData<double>(values: values),
  );
}

Chart _chart(
  ChartKind kind,
  ChartGrouping grouping,
  int series,
  int categories,
) => Chart(
  kind: kind,
  grouping: grouping,
  series: <ChartSeries>[
    for (int s = 0; s < series; s++)
      _series('Series ${s + 1}', categories, s.toDouble()),
  ],
  title: const ChartTitle(text: 'Benchmark'),
  legend: const ChartLegend(),
  dataLabels: const ChartDataLabels(),
);

/// A scatter chart of one series of [count] points.
Chart _scatter(int count) => Chart(
  kind: ChartKind.scatter,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['Points']),
      categories: ChartData<Object>(
        values: <Object?>[for (int i = 0; i < count; i++) (i * 37 % 1000) / 10],
      ),
      values: ChartData<double>(
        values: <double?>[
          for (int i = 0; i < count; i++)
            50 + 30 * ((i * 7) % 17) / 17 + i % 11,
        ],
      ),
    ),
  ],
  title: const ChartTitle(text: 'Benchmark'),
  legend: const ChartLegend(),
);

/// A pie of one series of [count] slices, with percent labels.
Chart _pie(int count) => Chart(
  kind: ChartKind.pie,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['Share']),
      categories: ChartData<Object>(
        values: <Object?>[for (int i = 0; i < count; i++) 'Slice ${i + 1}'],
      ),
      values: ChartData<double>(
        values: <double?>[for (int i = 0; i < count; i++) 1 + (i * 7) % 13],
      ),
    ),
  ],
  title: const ChartTitle(text: 'Benchmark'),
  legend: const ChartLegend(),
  dataLabels: const ChartDataLabels(visible: true, showPercent: true),
);

/// The time of one call of [run], in microseconds.
int _time(void Function() run) {
  final Stopwatch watch = Stopwatch()..start();
  run();
  return watch.elapsedMicroseconds;
}

/// The median and the worst of [_runs] timed calls after [_warmUp] untimed
/// ones, in milliseconds. [before] runs untimed before each call.
(double, double) _measure(void Function() run, {void Function()? before}) {
  for (int i = 0; i < _warmUp; i++) {
    before?.call();
    run();
  }
  final List<int> times = <int>[];
  for (int i = 0; i < _runs; i++) {
    before?.call();
    times.add(_time(run));
  }
  times.sort();
  return (
    (times[_runs ~/ 2 - 1] + times[_runs ~/ 2]) / 2 / 1000,
    times.last / 1000,
  );
}

String _ms((double, double) f) =>
    '${f.$1.toStringAsFixed(2).padLeft(9)} ${f.$2.toStringAsFixed(2).padLeft(9)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('layout and paint figures', () {
    final List<(String, Chart, List<ChartSize>)> cases =
        <(String, Chart, List<ChartSize>)>[
          (
            'column clustered 3x12',
            _chart(ChartKind.column, ChartGrouping.clustered, 3, 12),
            const <ChartSize>[
              ChartSize(360, 240),
              ChartSize(640, 400),
              ChartSize(1280, 720),
            ],
          ),
          (
            'line 2x30',
            _chart(ChartKind.line, ChartGrouping.clustered, 2, 30),
            const <ChartSize>[
              ChartSize(360, 240),
              ChartSize(640, 400),
              ChartSize(1280, 720),
            ],
          ),
          (
            'area stacked 4x12',
            _chart(ChartKind.area, ChartGrouping.stacked, 4, 12),
            const <ChartSize>[
              ChartSize(360, 240),
              ChartSize(640, 400),
              ChartSize(1280, 720),
            ],
          ),
          (
            'line 1x10000',
            _chart(ChartKind.line, ChartGrouping.clustered, 1, 10000),
            const <ChartSize>[ChartSize(1280, 720)],
          ),
          (
            'column clustered 2x3650',
            _chart(ChartKind.column, ChartGrouping.clustered, 2, 3650),
            const <ChartSize>[ChartSize(1280, 720)],
          ),
          (
            'scatter 1x10000',
            _scatter(10000),
            const <ChartSize>[ChartSize(1280, 720)],
          ),
          (
            'pie 60 slices',
            _pie(60),
            const <ChartSize>[ChartSize(360, 240), ChartSize(1280, 720)],
          ),
        ];

    final StringBuffer out = StringBuffer()
      ..writeln()
      ..writeln(
        'All times in ms: median and worst of $_runs runs after '
        '$_warmUp warm-up runs.',
      )
      ..writeln(
        '${'case'.padRight(26)}${'size'.padRight(11)}${'prims'.padLeft(7)}'
        '${'cold med'.padLeft(10)}${'cold max'.padLeft(10)}'
        '${'warm med'.padLeft(10)}${'warm max'.padLeft(10)}'
        '${'paint med'.padLeft(10)}${'paint max'.padLeft(10)}',
      );

    for (final (String name, Chart chart, List<ChartSize> sizes) in cases) {
      for (final ChartSize size in sizes) {
        FlutterTextMeasurer? cold;
        final (double, double) coldFigures = _measure(
          () => layoutChart(
            chart,
            theme: ChartTheme.office,
            size: size,
            measurer: cold!,
          ),
          before: () {
            cold?.dispose();
            cold = FlutterTextMeasurer();
          },
        );
        cold?.dispose();

        final FlutterTextMeasurer warm = FlutterTextMeasurer();
        final (double, double) warmFigures = _measure(
          () => layoutChart(
            chart,
            theme: ChartTheme.office,
            size: size,
            measurer: warm,
          ),
        );

        final ChartLayout laid = layoutChart(
          chart,
          theme: ChartTheme.office,
          size: size,
          measurer: warm,
        );
        final (double, double) paintFigures = _measure(() {
          final ui.PictureRecorder recorder = ui.PictureRecorder();
          paintChartPrimitives(ui.Canvas(recorder), laid.primitives, warm);
          recorder.endRecording().dispose();
        });
        warm.dispose();

        out.writeln(
          '${name.padRight(26)}'
          '${'${size.width.toInt()}x${size.height.toInt()}'.padRight(11)}'
          '${laid.primitives.length.toString().padLeft(7)}'
          '${_ms(coldFigures)} ${_ms(warmFigures)} ${_ms(paintFigures)}',
        );
      }
    }
    print(out);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
