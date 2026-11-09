# jet_charts_flutter

The Flutter backend of the jet_ chart family. It measures and draws what
`jet_charts_core` lays out, so a chart on screen shows the same data, axes and
colours as the same chart exported to XLSX or DOCX by `jet_office`.

It depends on `flutter`, `jet_charts_core` and `jet_core` only, and uses
Flutter's widgets layer, not Material or Cupertino, so an app's own design
system decides the rest.

## Status

Milestones J3 and J4 are done (J4 but its Excel check: the new kinds' Excel
values are estimates until the owner's E1 and E2). The package exports
`FlutterTextMeasurer` (the `TextMeasurer` that measures with the `TextPainter`
the renderer paints with), `paintChartPrimitives` and `ChartLayoutPainter`, and
the widget `JetChart`: loading, empty and error states in English, Turkish and
German, a screen reader description, hover and touch tooltips (`onHover`,
`onTap`), light animation of marks when the data changes, and reduced motion. It
paints column, bar, line, area, pie, donut, sparkline, scatter and combination
charts, smooth lines and translucent areas, and the keyboard walks a chart's
points (arrows, Home, End) while a screen reader reads a node per point.
`example/` is a gallery app for comparing the charts with Excel for Mac.

The package is a member of the repository's pub workspace (decisions 0013 and
0016 in the repository root's `docs/decisions/`).

## Usage

An app depends on `jet_charts_flutter`, `jet_charts_core` (the chart model
and themes) and `jet_core` (`FormatLocale`); they are not published, so
depend on them by path or git. A Turkish app sets both `locale` and
`strings`:

```dart
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_core/jet_core.dart';

final Widget chart = JetChart(
  chart: Chart(
    kind: ChartKind.column,
    title: const ChartTitle(text: 'Satışlar'),
    series: <ChartSeries>[
      ChartSeries(
        name: ChartData<String>(values: <String?>['Kuzey']),
        categories: ChartData<Object>(values: <Object?>['Ç1', 'Ç2']),
        values: ChartData<double>(values: <double?>[1250.5, 1800]),
      ),
    ],
  ),
  locale: FormatLocale.trTR,
  strings: JetChartStrings.tr,
);
```

While `loading` is true the default loading look animates without end, so a
widget test must pump a fixed duration rather than `pumpAndSettle`.

## Themes

`docs/app-themes.md` shows how an app builds its light and dark theme with
`ChartTheme.fromColors`, a donut with a total, a sparkline, smooth lines and
translucent areas, compact amounts and dates in Turkish, and how to test a
chart with animations disabled.
