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

`prims` is the number of top-level primitives of the layout: the marks are
children of the plot's clip and the markers of the marker clip, so they are not
counted. The 10,000 point line is one polyline and, as the Office theme has
`lineMarkers` on, a circle marker on every point: 10,000 arcs.

## Figures

Machine: Apple M3 Pro, macOS 27.2, Flutter 3.47.9 (stable, 2026-10-29), Dart
as bundled. Date: 2026-11-09, after the J3 gallery fixes (a marker on every
line point, line markers in a clip of their own); the machine was under load
(load average about 9), and the VM table is the second of two runs, the first
being up to 1.5 times slower throughout. Chrome timers resolve 0.1 ms, so
small figures there are coarse.

### VM (`flutter test benchmark`)

```
case                      size         prims  cold med  cold max  warm med  warm max paint med paint max
column clustered 3x12     360x240         32     1.30      2.19      0.47      0.95      0.13      0.17
column clustered 3x12     640x400         38     1.00      1.44      0.33      0.62      0.10      0.14
column clustered 3x12     1280x720        38     0.66      1.03      0.18      0.24      0.08      0.21
line 2x30                 360x240         42     1.14      1.58      0.28      0.44      0.20      0.34
line 2x30                 640x400         57     0.92      1.99      0.20      0.49      0.16      0.30
line 2x30                 1280x720        57     1.60      2.25      0.28      0.45      0.12      0.17
area stacked 4x12         360x240         38     0.81      1.13      0.21      0.34      0.04      0.08
area stacked 4x12         640x400         44     0.60      0.77      0.15      0.22      0.04      0.09
area stacked 4x12         1280x720        44     0.47      0.78      0.13      0.40      0.04      0.08
line 1x10000              1280x720       136   226.24    247.67    249.66    299.93     15.66     25.35
column clustered 2x3650   1280x720       135    93.28    119.41    101.38    139.21      2.13     10.12
```

### Chrome (`--platform chrome`)

```
case                      size         prims  cold med  cold max  warm med  warm max paint med paint max
column clustered 3x12     360x240         32     2.10      3.00      0.40      0.70      0.40      0.60
column clustered 3x12     640x400         38     1.60      2.50      0.40      0.50      0.30      0.50
column clustered 3x12     1280x720        38     1.10      1.80      0.20      0.30      0.30      0.50
line 2x30                 360x240         42     2.10      2.50      0.40      0.70      0.80      1.00
line 2x30                 640x400         57     1.90      2.80      0.35      0.40      0.90      1.30
line 2x30                 1280x720        57     4.90      5.70      1.20      1.50      0.80      0.90
area stacked 4x12         360x240         38     2.30      2.80      0.40      0.50      0.25      0.30
area stacked 4x12         640x400         44     1.60      1.80      0.40      0.50      0.30      0.70
area stacked 4x12         1280x720        44     1.20      1.30      0.30      0.30      0.30      0.30
line 1x10000              1280x720       136   511.75    521.20    515.85    535.90     77.25     95.30
column clustered 2x3650   1280x720       135   182.70    185.40    190.30    197.90     20.20     21.20
```

## Reading the figures

- Dashboard charts lay out in about 1 to 5 ms cold and mostly under 1 ms
  warm, and record in under 1 ms (a line of 2 by 30 with its 60 markers
  about 0.2 ms on the VM and 0.9 ms in Chrome): far inside a 16 ms frame.
- The two large series are slow in layout (about 230 to 250 ms for the line
  and 90 to 100 ms for the column on the VM; about twice that in Chrome). The
  column is cheap to paint (2 ms on the VM, 20 ms in Chrome, as before). The
  text cache does not help them (warm is not faster than cold), so the cost
  is in the core's layout of many points and categories, not in text
  measurement. The widget lays out on a size or data change, not every frame,
  but a chart this large should be decimated by the caller.
- The 10,000 markers made the line's paint much slower: 0.42 ms before them
  and 15.7 ms now on the VM, 3.7 ms and 77 ms in Chrome, while its layout
  did not change. 77 ms is several frames; a caller that draws a line this
  dense should decimate it or use a theme with `lineMarkers` off.
- Data labels are off: the core's label placement is linear per obstacle and
  takes about 1 s at 3,650 categories by 2 series.
