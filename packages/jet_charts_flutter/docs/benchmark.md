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
points and a clustered column of 2 series by 3,650 categories. J4 added a
scatter chart of 1 series by 10,000 points at 1280 by 720 (a marker on each
point) and a pie of 60 slices at 360 by 240 and 1280 by 720, with percent data
labels. Every chart has a title and a legend; data labels are off, but for
the pie's. `ChartTheme.office`, default font.

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
counted. The 10,000 point line is one polyline and no markers: the Office
theme has `lineMarkers` on, but its category step (about 0.12 pt) is under
`markerSize` plus 2, so the core draws a marker only on a point with no
neighbour, and it has none. The line of 2 by 30 keeps a marker on every point
at every size.

## Figures

Machine: Apple M3 Pro, macOS 27.2, Flutter 3.47.9 (stable, 2026-10-29), Dart
as bundled. Date: 2026-11-09, after the J3 gallery fixes (a marker on every
line point whose step fits it, line markers in a clip of their own); the
machine was under heavy load (load average 10 to 13), and the VM table is the
second of two runs, the first being up to 1.5 times slower throughout. Chrome timers resolve 0.1 ms, so
small figures there are coarse. The two J4 cases were added after that run:
they were timed on 2026-11-10 on the same machine (Flutter 3.47.9), the machine
not under load; their figures are in the same tables, and the rows above them
are the earlier run's, so the two groups are not strictly comparable.

### VM (`flutter test benchmark`)

```
case                      size         prims  cold med  cold max  warm med  warm max paint med paint max
column clustered 3x12     360x240         32     1.45      2.49      0.49      1.05      0.13      0.19
column clustered 3x12     640x400         38     1.70      4.03      0.36      0.87      0.10      0.15
column clustered 3x12     1280x720        38     0.65      1.34      0.19      0.24      0.09      0.35
line 2x30                 360x240         42     1.33      2.11      0.30      1.41      0.19      0.35
line 2x30                 640x400         57     1.25      3.25      0.15      0.36      0.17      0.32
line 2x30                 1280x720        57     1.83      3.08      0.31      0.42      0.12      1.15
area stacked 4x12         360x240         38     0.92      1.26      0.23      0.31      0.05      0.20
area stacked 4x12         640x400         44     0.74      2.86      0.17      0.21      0.05      0.17
area stacked 4x12         1280x720        44     0.50      0.94      0.13      0.50      0.05      0.07
line 1x10000              1280x720       135   293.84    419.78    274.87    342.41      0.41      5.07
column clustered 2x3650   1280x720       135   107.57    167.25    114.18    172.85      2.70      9.96
scatter 1x10000           1280x720        38    16.25     25.42     15.25     26.94     11.81     30.34
pie 60 slices             360x240         87     3.82     10.69      1.80      7.52      0.10      0.18
pie 60 slices             1280x720       247     3.64     13.36      2.43      9.65      0.27      6.83
```

### Chrome (`--platform chrome`)

```
case                      size         prims  cold med  cold max  warm med  warm max paint med paint max
column clustered 3x12     360x240         32     2.45     13.00      0.40      0.50      0.40      0.90
column clustered 3x12     640x400         38     1.60      2.10      0.40      1.10      0.30      0.50
column clustered 3x12     1280x720        38     1.10      1.20      0.20      0.70      0.30      0.60
line 2x30                 360x240         42     2.20      3.40      0.40      0.50      0.80      1.10
line 2x30                 640x400         57     2.00      3.10      0.35      0.50      0.90      1.10
line 2x30                 1280x720        57     5.30      6.70      1.30      1.60      0.80      0.90
area stacked 4x12         360x240         38     2.65      4.50      0.40      0.60      0.20      0.30
area stacked 4x12         640x400         44     1.80      3.00      0.40      0.50      0.30      0.40
area stacked 4x12         1280x720        44     1.20      1.40      0.30      0.30      0.30      0.30
line 1x10000              1280x720       135   532.55    538.90    548.60    565.70      4.00      5.90
column clustered 2x3650   1280x720       135   192.60    204.70    212.90    220.00     21.25     22.10
scatter 1x10000           1280x720        38    25.55     26.80     24.70     26.00     73.20     75.80
pie 60 slices             360x240         87     9.30     10.50      6.20      6.70      0.60      0.80
pie 60 slices             1280x720       247    12.50     12.90      9.80     10.20      1.10      1.20
```

## Reading the figures

- Dashboard charts lay out in about 1 to 5 ms cold and mostly under 1 ms
  warm, and record in under 1 ms (a line of 2 by 30 with its 60 markers
  about 0.2 ms on the VM and 0.9 ms in Chrome): far inside a 16 ms frame.
- The two large series are slow in layout (about 230 to 300 ms for the line
  and 90 to 110 ms for the column on the VM, the higher figures under load;
  about twice that in Chrome). The
  column is cheap to paint (2 ms on the VM, 20 ms in Chrome, as before). The
  text cache does not help them (warm is not faster than cold), so the cost
  is in the core's layout of many points and categories, not in text
  measurement. The widget lays out on a size or data change, not every frame,
  but a chart this large should be decimated by the caller.
- A marker on each of the 10,000 points made the line's paint much slower
  (15.7 ms on the VM, 77 ms in Chrome, against 0.42 and 3.7 ms without
  them), and the markers touched and hid the line. A line now gets markers
  only where its category step is at least `markerSize` plus 2 pt, so this
  line has none and records in 0.41 ms on the VM and 4 ms in Chrome again;
  its `prims` is one fewer, as the marker clip is left out. Excel's
  behaviour on dense lines was not checked (`jet_charts_core/docs/parity.md`).
- Data labels are off: the core's label placement is linear per obstacle and
  takes about 1 s at 3,650 categories by 2 series.
- J4 cases. The 10,000-point scatter chart lays out in about 16 ms on the VM and
  25 ms in Chrome, far cheaper than the line (its markers are children of the
  plot's clip, so `prims` is 38). Its cost is in painting: 10,000 markers record
  in about 12 ms on the VM and 73 ms in Chrome (30 and 76 ms worst), which is
  over a 16 ms frame in Chrome; a chart this large should be decimated by the
  caller. The pie of 60 slices, labels and leader lines included, lays out in
  about 2 to 4 ms on the VM and 6 to 12 ms in Chrome and records in under 1.2
  ms. The scatter and pie rows were run once and the VM's worst figures are
  one-off spikes, not a trend.
