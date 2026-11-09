import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_gallery/gallery.dart';
import 'package:jet_charts_gallery/main.dart';
import 'package:jet_core/jet_core.dart';

void main() {
  test('the gallery holds the 14 core charts, one_series and '
      'turkish_amounts, with unique names', () {
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
    ]);
  });

  testWidgets('every entry lays out at 360 by 216 without overlap', (
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
          theme: ChartTheme.office,
          size: gallerySize,
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
}
