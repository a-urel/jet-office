import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_gallery/gallery.dart';
import 'package:jet_charts_gallery/main.dart';
import 'package:jet_charts_gallery/monepro.dart';
import 'package:jet_core/jet_core.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('the gallery holds the 14 J3 core charts, one_series, '
      'turkish_amounts and the 14 J4 core charts, with unique names', () {
    final List<String> names = <String>[
      for (final GalleryEntry e in galleryEntries()) e.name,
    ];
    expect(names, <String>[
      'column_clustered',
      'column_stacked',
      'column_percent',
      'bar_clustered',
      'line_gap',
      'area_stacked',
      'column_negative',
      'column_eight_series',
      'column_long_labels',
      'column_data_labels',
      'legend_top',
      'legend_left',
      'legend_right',
      'tile',
      'one_series',
      'turkish_amounts',
      'line_smooth',
      'area_translucent',
      'pie_basic',
      'pie_small_slices',
      'pie_negative',
      'donut_center',
      'donut_two_series',
      'sparkline_line',
      'sparkline_area',
      'scatter_basic',
      'scatter_dates',
      'combo_column_line',
      'combo_area_column_line',
      'line_secondary',
    ]);
  });

  test('a sparkline is 120 by 40 points, every other entry 360 by 216', () {
    for (final GalleryEntry entry in galleryEntries()) {
      expect(
        entry.size,
        entry.chart.kind == ChartKind.sparkline
            ? const ChartSize(120, 40)
            : gallerySize,
        reason: entry.name,
      );
    }
  });

  test('only area_translucent and sparkline_area change the Office theme, '
      'and only its area opacity and line', () {
    for (final GalleryEntry entry in galleryEntries()) {
      final ChartTheme expected = switch (entry.name) {
        'area_translucent' => ChartTheme.office.copyWith(
          areaOpacity: 0.25,
          areaLine: true,
        ),
        'sparkline_area' => ChartTheme.office.copyWith(areaOpacity: 0.1),
        _ => ChartTheme.office,
      };
      expect(entry.theme, expected, reason: entry.name);
    }
  });

  test('the Monépro themes share one font family, light and dark, and the '
      'page holds its four charts', () {
    expect(moneproLightTheme.axisLabels.fontFamily, moneproFontFamily);
    expect(moneproDarkTheme.axisLabels.fontFamily, moneproFontFamily);
    expect(moneproLightTheme.background, isNot(moneproDarkTheme.background));
    expect(moneproCharts().map((GalleryEntry e) => e.name), <String>[
      'donut_center',
      'sparkline_area',
      'line_smooth',
      'combo_column_line',
    ]);
  });

  testWidgets('every entry lays out at its size without overlap', (
    WidgetTester tester,
  ) async {
    final FlutterTextMeasurer measurer = FlutterTextMeasurer();
    addTearDown(measurer.dispose);
    for (final FormatLocale locale in <FormatLocale>[
      FormatLocale.enUS,
      FormatLocale.trTR,
    ]) {
      for (final GalleryEntry entry in galleryEntries()) {
        final ChartLayout layout = layoutChart(
          entry.chart,
          theme: entry.theme,
          size: entry.size,
          measurer: measurer,
          locale: locale,
        );
        expect(
          findOverlaps(layout.primitives, layout.size),
          isEmpty,
          reason: entry.name,
        );
      }
    }
  });

  testWidgets('the first screen pumps without exceptions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GalleryApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('column_clustered'), findsOneWidget);
    expect(find.textContaining('Aptos Narrow'), findsOneWidget);
    final Size frame = tester.getSize(find.byType(JetChart).first);
    expect(frame, const Size(360, 216));
    expect(find.textContaining('overlaps: 0'), findsWidgets);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Monépro page shows its four charts light and dark and '
      'names the font it got', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GalleryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monépro look'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining(moneproFontFamily), findsOneWidget);
    expect(find.text('donut_center (light)'), findsOneWidget);
    expect(find.text('donut_center (dark)'), findsOneWidget);
    expect(find.textContaining('overlaps: 0'), findsWidgets);
    expect(find.textContaining('overlaps: 1'), findsNothing);
  });

  testWidgets('every Monépro chart lays out without overlap, light and dark', (
    WidgetTester tester,
  ) async {
    final FlutterTextMeasurer measurer = FlutterTextMeasurer();
    addTearDown(measurer.dispose);
    for (final ChartTheme theme in <ChartTheme>[
      moneproLightTheme,
      moneproDarkTheme,
    ]) {
      for (final GalleryEntry entry in moneproCharts()) {
        final ChartLayout layout = layoutChart(
          entry.chart,
          theme: moneproTheme(theme, entry),
          size: entry.size,
          measurer: measurer,
        );
        expect(
          findOverlaps(layout.primitives, layout.size),
          isEmpty,
          reason: entry.name,
        );
      }
    }
  });
}
