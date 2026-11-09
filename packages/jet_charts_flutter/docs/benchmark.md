# Benchmark

`benchmark/chart_benchmark_test.dart` times `layoutChart` and
`paintChartPrimitives`. The figures are records, not thresholds: nothing fails
when a later run is slower, and they are not a promise. The gate does not run
it.

## Run it

```bash
flutter test benchmark
```

Flutter's browser tests compile only files under `test/`, so for Chrome copy
the file there, run it and delete the copy:

```bash
cp benchmark/chart_benchmark_test.dart test/zz_chart_benchmark_test.dart
flutter test --platform chrome test/zz_chart_benchmark_test.dart
rm test/zz_chart_benchmark_test.dart
```

## Method

Three dashboard charts, each at 360 by 240, 640 by 400 and 1280 by 720: a
clustered column of 3 series by 12 categories, a line of 2 by 30 and a stacked
area of 4 by 12. Two large series at 1280 by 720: a line of 1 series by 10,000
points and a clustered column of 2 series by 3,650 categories. Every chart has
a title and a legend; data labels are off. `ChartTheme.office`, default font.

Per case: 5 warm-up runs, then 20 timed runs; the table gives the median and
the worst, in milliseconds.

- **cold**: layout with a new `FlutterTextMeasurer` for each run (empty text
  cache).
- **warm**: layout with one measurer reused (cache filled).
- **paint**: `paintChartPrimitives` into a `ui.PictureRecorder`, then
  `endRecording()` and dispose of the picture. `flutter test` paints without
  a GPU, so this is the cost of recording, not of rasterising.

`prims` is the number of top-level primitives of the layout. The 10,000 point
line is laid out as the core does it (it has no marker switch): it is one
polyline, so it has few primitives.

## Figures

Machine: Apple M3 Pro, macOS 27.2, Flutter 3.47.9 (stable, 2026-10-29), Dart
as bundled. Date: 2026-11-09. Chrome timers resolve 0.1 ms, so small figures
there are coarse.

### VM (`flutter test benchmark`)

```
case                      size         prims  cold med  cold max  warm med  warm max paint med paint max
column clustered 3x12     360x240         32     1.24      2.56      0.53      1.36      0.14      0.30
column clustered 3x12     640x400         32     0.82      1.15      0.27      0.61      0.09      0.22
column clustered 3x12     1280x720        38     0.86      2.10      0.20      0.33      0.10      0.44
line 2x30                 360x240         39     1.27      2.16      0.25      0.97      0.07      0.31
line 2x30                 640x400         54     0.99      2.28      0.14      0.30      0.07      0.14
line 2x30                 1280x720        39     0.71      1.49      0.11      0.43      0.04      0.09
area stacked 4x12         360x240         38     0.62      2.03      0.16      0.36      0.04      0.05
area stacked 4x12         640x400         38     0.49      1.54      0.10      0.16      0.04      0.11
area stacked 4x12         1280x720        44     0.46      0.58      0.09      1.11      0.05      0.08
line 1x10000              1280x720       134   248.17    269.47    271.77    305.35      0.42      5.36
column clustered 2x3650   1280x720       135    90.00    106.73    102.83    126.80      2.08      8.54
```

### Chrome (`--platform chrome`)

```
case                      size         prims  cold med  cold max  warm med  warm max paint med paint max
column clustered 3x12     360x240         32     2.20      3.50      0.30      0.50      0.40      0.70
column clustered 3x12     640x400         32     1.30      3.30      0.20      0.40      0.30      0.40
column clustered 3x12     1280x720        38     1.15      1.70      0.20      0.30      0.30      0.60
line 2x30                 360x240         39     2.05      2.70      0.30      0.70      0.20      0.30
line 2x30                 640x400         54     2.10      2.90      0.30      0.40      0.30      0.60
line 2x30                 1280x720        39     1.90      1.90      0.20      0.40      0.20      0.30
area stacked 4x12         360x240         38     1.50      2.40      0.20      0.30      0.20      0.30
area stacked 4x12         640x400         38     1.25      2.20      0.20      0.30      0.20      0.30
area stacked 4x12         1280x720        44     1.30      1.90      0.20      0.30      0.30      0.30
line 1x10000              1280x720       134   521.30    531.20    529.70    559.40      3.70      5.90
column clustered 2x3650   1280x720       135   185.35    188.10    196.55    230.80     19.50     20.30
```

## Reading the figures

- Dashboard charts lay out in about 1 to 2 ms cold and well under 1 ms warm,
  and record in under 0.5 ms: far inside a 16 ms frame.
- The two large series are slow in layout (about 250 ms for the line and 90 to
  100 ms for the column on the VM; about twice that in Chrome) and cheap to
  paint. The text cache does not help them (warm is not faster than cold), so
  the cost is in the core's layout of many points and categories, not in text
  measurement. The widget lays out on a size or data change, not every frame,
  but a chart this large should be decimated by the caller.
- Data labels are off: the core's label placement is linear per obstacle and
  takes about 1 s at 3,650 categories by 2 series.
