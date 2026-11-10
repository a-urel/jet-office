// The code of docs/app-themes.md, mirrored: the charts of that page
// are built here exactly as the page shows them, laid out in both themes
// without an overlap, and one is shown with animations disabled.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_core/jet_core.dart';

// --- docs/app-themes.md: the themes -----------------------------------

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

// --- docs/app-themes.md: the charts -----------------------------------

/// Invoice statuses, coloured by the theme's semantic keys.
final Chart statuses = Chart(
  kind: ChartKind.donut,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['Faturalar']),
      categories: ChartData<Object>(
        values: <Object?>['Ödendi', 'Gecikmiş', 'Taslak'],
      ),
      values: ChartData<double>(values: <double?>[42, 7, 5]),
      pointColorKeys: <String?>['success', 'destructive', 'muted'],
    ),
  ],
);

/// Sales by hour, and the number of sales in each hour for the tooltip.
final Chart hours = Chart(
  kind: ChartKind.column,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['Satış']),
      categories: ChartData<Object>(values: <Object?>['09', '10', '11']),
      values: ChartData<double>(values: <double?>[840, 1210, 990]),
    ),
  ],
);
const List<int> counts = <int>[9, 12, 10];

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

/// The widget, as the page shows it.
Widget trendWidget() => JetChart(
  chart: trend,
  theme: lightTheme,
  locale: FormatLocale.trTR,
  strings: JetChartStrings.tr,
);

// --- the tests --------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<(String, Chart, ChartTheme, ChartSize)> cases =
      <(String, Chart, ChartTheme, ChartSize)>[
        for (final (String n, ChartTheme t) in <(String, ChartTheme)>[
          ('light', lightTheme),
          ('dark', darkTheme),
        ]) ...<(String, Chart, ChartTheme, ChartSize)>[
          (
            'donut $n',
            donut,
            t.copyWith(sliceBorderWidth: 2),
            const ChartSize(320, 240),
          ),
          (
            'sparkline $n',
            sparkline,
            t.copyWith(areaOpacity: 0.1),
            const ChartSize(120, 40),
          ),
          ('trend $n', trend, t, const ChartSize(360, 216)),
          (
            'trend area $n',
            trendArea,
            t.copyWith(areaOpacity: 0.25, areaLine: true),
            const ChartSize(360, 216),
          ),
        ],
      ];

  for (final (String name, Chart chart, ChartTheme theme, ChartSize size)
      in cases) {
    test('$name lays out without overlaps, inside its size', () {
      final FlutterTextMeasurer measurer = FlutterTextMeasurer();
      addTearDown(measurer.dispose);
      final ChartLayout layout = layoutChart(
        chart,
        theme: theme,
        size: size,
        measurer: measurer,
      );
      expect(layout.primitives, isNotEmpty);
      expect(findOverlaps(layout.primitives, size), isEmpty);
    });
  }

  test('the donut draws its centre text and the share labels', () {
    final FlutterTextMeasurer measurer = FlutterTextMeasurer();
    addTearDown(measurer.dispose);
    final ChartLayout layout = layoutChart(
      donut,
      theme: donutTheme,
      size: const ChartSize(320, 240),
      measurer: measurer,
    );
    final List<String> texts = <String>[
      for (final ChartPrimitive p in layout.primitives)
        if (p is TextPrimitive) p.text,
    ];
    expect(texts, contains('10,0 Mn'));
    // 52 % and 31 % reach minShare 0.1; 15 % does too; 2 % does not.
    expect(texts.where((String t) => t.endsWith('%')).length, 3);
  });

  test('the format codes show compact amounts and dates in Turkish', () {
    final FlutterTextMeasurer measurer = FlutterTextMeasurer();
    addTearDown(measurer.dispose);
    final ChartLayout layout = layoutChart(
      trend,
      theme: lightTheme,
      size: const ChartSize(360, 216),
      measurer: measurer,
      locale: FormatLocale.trTR,
    );
    final List<String> texts = <String>[
      for (final ChartPrimitive p in layout.primitives)
        if (p is TextPrimitive) p.text,
    ];
    expect(texts, contains('2,0 Mn'));
    expect(texts, contains('2 Mar'));
  });

  test('status slices follow the theme by key', () {
    final ChartTheme light = lightTheme.copyWith(
      semantic: <String, ChartColor>{
        'success': ChartColor.rgb(0x059669),
        'destructive': ChartColor.rgb(0xDC2626),
      },
    );
    final ChartTheme dark = darkTheme.copyWith(
      semantic: <String, ChartColor>{
        'success': ChartColor.rgb(0x34D399),
        'destructive': ChartColor.rgb(0xF87171),
      },
    );
    final ChartSeries series = statuses.series.single;
    expect(light.pointColorOf(series, 0), ChartColor.rgb(0x059669));
    expect(dark.pointColorOf(series, 1), ChartColor.rgb(0xF87171));
    // 'muted' is in neither theme: the slice is automatic.
    expect(light.pointColorOf(series, 2), isNull);
  });

  testWidgets('tooltipLines adds the count under the hour', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: JetChart(
              chart: hours,
              theme: lightTheme,
              tooltipLines: (ChartTooltip tooltip) => <String>[
                if (tooltip.category case final int hour)
                  '${counts[hour]} işlem',
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('12 işlem')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('with animations disabled a chart settles at once', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 360, height: 216, child: trendWidget()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(JetChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
