import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:test/test.dart';

const FixedWidthTextMeasurer measurer = FixedWidthTextMeasurer();

ChartSeries series(String name, List<double?> values) {
  return ChartSeries(
    name: ChartData<String>(values: <String?>[name]),
    categories: ChartData<Object>(values: <Object>['A', 'B', 'C']),
    values: ChartData<double>(values: values),
  );
}

ChartLayout lay(
  ChartKind kind, {
  ChartTheme? theme,
  ChartLegendPosition position = ChartLegendPosition.bottom,
}) {
  return layoutChart(
    Chart(
      kind: kind,
      legend: ChartLegend(position: position),
      series: <ChartSeries>[
        series('Visits', <double?>[4, 7, 5]),
        series('Orders', <double?>[2, 3, 4]),
      ],
    ),
    theme: theme ?? ChartTheme.office,
    size: const ChartSize(400, 300),
    measurer: measurer,
  );
}

T? find<T extends ChartPrimitive>(ChartLayout l, String id) {
  for (final ChartPrimitive p in l.primitives) {
    if (p.id == id) {
      return p as T;
    }
  }
  return null;
}

Matcher near(double v) => closeTo(v, 1e-9);

void main() {
  final ChartTheme office = ChartTheme.office;
  final ChartSpacing spacing = office.spacing;

  for (final ChartLegendPosition position in ChartLegendPosition.values) {
    test('a line series has a line and a marker as its symbol, '
        '${position.name}', () {
      final ChartLayout l = lay(ChartKind.line, position: position);
      for (int s = 0; s < 2; s++) {
        final ChartColor color = office.seriesColor(s);
        final PathPrimitive line = find<PathPrimitive>(
          l,
          ids.legendSymbolId(s),
        )!;
        final TextPrimitive text = find<TextPrimitive>(l, ids.legendTextId(s))!;
        expect(line.points, hasLength(2));
        expect(line.closed, isFalse);
        expect(line.fill, isNull);
        expect(line.stroke, color);
        expect(line.strokeWidth, office.lineWidth);
        final ChartPoint a = line.points[0];
        final ChartPoint b = line.points[1];
        expect(a.y, b.y);
        expect(b.x - a.x, near(spacing.legendLineSymbol));
        expect(spacing.legendLineSymbol, 16);
        // At the entry's vertical middle, before its text.
        expect(a.y, near(text.rect.top + text.rect.height / 2));
        expect(text.rect.left, near(b.x + spacing.labelGap));
        final ArcPrimitive marker = find<ArcPrimitive>(
          l,
          ids.legendMarkerId(s),
        )!;
        expect(marker.center.x, near((a.x + b.x) / 2));
        expect(marker.center.y, near(a.y));
        expect(marker.radius, office.markerSize / 2);
        expect(marker.innerRadius, 0);
        expect(marker.sweepAngle, 360);
        expect(marker.fill, color);
        expect(marker.stroke, color);
        expect(marker.strokeWidth, 0.75);
        // The marker is drawn over the line.
        expect(
          l.primitives.indexOf(marker),
          greaterThan(l.primitives.indexOf(line)),
        );
      }
      expect(findOverlaps(l.primitives, l.size), isEmpty);
    });
  }

  test('without line markers the legend line has no marker', () {
    final ChartLayout l = lay(
      ChartKind.line,
      theme: office.copyWith(lineMarkers: false),
    );
    expect(find<PathPrimitive>(l, ids.legendSymbolId(0)), isNotNull);
    expect(find<ArcPrimitive>(l, ids.legendMarkerId(0)), isNull);
  });

  for (final ChartKind kind in <ChartKind>[
    ChartKind.column,
    ChartKind.bar,
    ChartKind.area,
  ]) {
    test('a ${kind.name} series keeps the square symbol', () {
      final ChartLayout l = lay(kind);
      final RectPrimitive square = find<RectPrimitive>(
        l,
        ids.legendSymbolId(0),
      )!;
      expect(square.rect.width, spacing.legendSymbol);
      expect(square.rect.height, spacing.legendSymbol);
      expect(square.fill, office.seriesColor(0));
      expect(find<ArcPrimitive>(l, ids.legendMarkerId(0)), isNull);
    });
  }
}
