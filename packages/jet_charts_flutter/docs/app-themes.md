# Themes and charts for an app

How an app gives `jet_charts_flutter` its own look and builds the charts a
dashboard needs. The code on this page is compiled and run by
`test/app_themes_doc_test.dart`, so it stays true.

## One theme per brightness

`ChartTheme.fromColors` builds a whole theme from an app's colours and its
font. Call it once for light mode and once for dark mode, and hand the right one
to `JetChart.theme` from the app's own theme data.

- `palette` is the series colours, in order. A pie takes one per slice, in the
  same order.
- `semantic` names colours the app means something by. A series with
  `colorKey: 'income'` takes `semantic['income']`; `ChartSeries.color` wins
  over the key, and the key over the palette.
- `fontFamily` is the family name the app registered (in `pubspec.yaml`, under
  `flutter: fonts:`), written exactly the same. The chart measures and draws
  with that font. If the name is wrong Flutter falls back to its default font,
  and the chart still lays out without overlaps, but it does not look as meant.
- `text` and `background` are the app's. The grid line, the axis line and the
  tooltip border are `text` blended 15 % over `background`, unless `gridLine`
  is given.
- `fontSize` is 9 points by default; the title is `fontSize * 14 / 9`.

```dart
final ChartTheme lightTheme = ChartTheme.fromColors(
  palette: <ChartColor>[
    ChartColor.rgb(0x2563EB),
    ChartColor.rgb(0x10B981),
    ChartColor.rgb(0xF59E0B),
    ChartColor.rgb(0xEF4444),
    ChartColor.rgb(0x8B5CF6),
  ],
  semantic: <String, ChartColor>{
    'income': ChartColor.rgb(0x059669),
    'expense': ChartColor.rgb(0xDC2626),
  },
  fontFamily: 'Inter', // the family the app registered in its pubspec
  text: ChartColor.rgb(0x1F2937),
  background: ChartColor.rgb(0xFFFFFF),
);

final ChartTheme darkTheme = ChartTheme.fromColors(
  palette: <ChartColor>[
    ChartColor.rgb(0x60A5FA),
    ChartColor.rgb(0x34D399),
    ChartColor.rgb(0xFBBF24),
    ChartColor.rgb(0xF87171),
    ChartColor.rgb(0xA78BFA),
  ],
  semantic: <String, ChartColor>{
    'income': ChartColor.rgb(0x34D399),
    'expense': ChartColor.rgb(0xF87171),
  },
  fontFamily: 'Inter',
  text: ChartColor.rgb(0xE5E7EB),
  background: ChartColor.rgb(0x111827),
);
```

## A donut with a total

`holeSizePercent` (10 to 90, 75 by default; 75 is an estimate, not checked in
Excel) sets the hole, and `centerText` is drawn in it. The text is not shrunk: it is
drawn when it fits in the hole with a small gap to the ring, else it is
hidden, and a hidden text is listed in the layout's `hidden` and reachable
through the tooltip. Choose a text and a `holeSizePercent` that fit at the
tile's size. `ChartDataLabels(showPercent: true)` writes
each slice's share, `showValue: false` leaves the amount out, and
`minShare: 0.1` leaves slices under 10 % unlabelled (a screen-only option: a
file written by `jet_office` does not carry it). Slice gaps are the theme's
`sliceBorderWidth`, the outline of every slice in the background colour.

A sparkline has no axes, title, legend or labels. Draw it at the size of its
tile (for example 120 by 40). An `area` series in it is a filled line, and
`valueAxis: ChartAxis(min: 0)` keeps the baseline at zero. A light fill is the
theme's `areaOpacity`.

## Smooth lines, translucent areas, compact amounts and dates

`ChartSeries.smooth` draws a line as a smooth curve. The curve is a Catmull-Rom
spline through the points, this library's estimate of Excel's smoothing (not
checked in Excel); it can pass a little above or below a point. `ChartTheme.areaOpacity` (above 0,
at most 1) makes every area fill translucent, and `areaLine: true` draws the
series colour as a line along the top of the fill. This is the usual look for a
line over a light fill.

Format codes are Excel's. `#,##0.0,," Mn"` shows 2300000 as `2,3 Mn` in
`FormatLocale.trTR` (each trailing comma divides by a thousand). `d mmm` shows
a `DateTime` category as a day and the abbreviated month name of the locale,
for example `9 Mar`. Give the locale to `JetChart`; the same locale
formats the tooltip and the screen reader text.

```dart
ChartSeries _series(String name, List<Object?> categories, List<double?> v) =>
    ChartSeries(
      name: ChartData<String>(values: <String?>[name]),
      categories: ChartData<Object>(values: categories),
      values: ChartData<double>(values: v),
    );

/// A donut with a total in its hole, labels as shares, small slices left
/// unlabelled and a gap between slices.
final Chart donut = Chart(
  kind: ChartKind.donut,
  title: const ChartTitle(text: 'Gelir dağılımı'),
  series: <ChartSeries>[
    _series(
      'Gelir',
      <Object?>['Mağaza', 'Online', 'Toptan', 'Diğer'],
      <double?>[5200000, 3100000, 1500000, 200000],
    ),
  ],
  holeSizePercent: 60,
  centerText: '10,0 Mn',
  dataLabels: const ChartDataLabels(
    visible: true,
    showValue: false,
    showPercent: true,
    minShare: 0.1,
  ),
);

/// The gap between slices is the theme's: the slice outline in the
/// background colour, 2 points wide.
final ChartTheme donutTheme = lightTheme.copyWith(sliceBorderWidth: 2);

/// A sparkline of an area series, from zero.
final Chart sparkline = Chart(
  kind: ChartKind.sparkline,
  series: <ChartSeries>[
    _series('Satışlar', const <Object?>[], <double?>[
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
);

/// A smooth line with compact amounts and dates.
final Chart trend = Chart(
  kind: ChartKind.line,
  title: const ChartTitle(text: 'Günlük ciro'),
  series: <ChartSeries>[
    _series(
      'Ciro',
      <Object?>[
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 16),
        DateTime(2026, 3, 23),
        DateTime(2026, 3, 30),
      ],
      <double?>[1200000, 1850000, 1500000, 2300000, 2100000],
    ).copyWith(smooth: true, formatCode: '#,##0.0,," Mn"'),
  ],
  categoryAxis: const ChartAxis(formatCode: 'd mmm'),
  valueAxis: const ChartAxis(formatCode: '#,##0.0,," Mn"'),
);

/// The same line as a translucent area with an edge line.
final ChartTheme areaTheme = lightTheme.copyWith(
  areaOpacity: 0.25,
  areaLine: true,
);

final Chart trendArea = Chart(
  kind: ChartKind.area,
  title: trend.title,
  series: trend.series,
  categoryAxis: trend.categoryAxis,
  valueAxis: trend.valueAxis,
);
```

```dart
JetChart(
  chart: trend,
  theme: lightTheme,
  locale: FormatLocale.trTR,
  strings: JetChartStrings.tr,
)
```

For the translucent area, build the chart with `ChartKind.area` and the theme
`lightTheme.copyWith(areaOpacity: 0.25, areaLine: true)` (the test does).
The theme of the donut is `lightTheme.copyWith(sliceBorderWidth: 2)`.

## Testing

A chart that loads animates without end, and a chart whose data changes moves
its marks for `animationDuration`. Under `MediaQuery(disableAnimations: true)`
the widget does not animate at all, so a test can `pumpAndSettle` and then look
at the finished chart:

```dart
await tester.pumpWidget(
  MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: JetChart(chart: trend, theme: lightTheme),
    ),
  ),
);
await tester.pumpAndSettle();
```

Do not `pumpAndSettle` while `loading` is true: the loading look repeats.

To prove a chart fits its tile, lay it out with a `FlutterTextMeasurer` at the
tile's size and check that `findOverlaps(layout.primitives, size)` is empty.
The core guarantees it for every chart; the test guards the app's own theme
and font.

## Defaults that are estimates

The pie's first slice at 12 o'clock going clockwise, the donut's 75 % hole,
the 0.75 pt slice outline in the background colour, one colour per slice, the
sparkline's 0.75 pt line and the scatter and secondary axis defaults are this
library's estimates until the owner's check against Excel for Mac
(`packages/jet_charts_core/docs/excel-checks.md`).
