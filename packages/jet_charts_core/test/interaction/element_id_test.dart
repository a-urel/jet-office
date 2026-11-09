import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

import '../support/gallery.dart';

/// Every id in [primitives], the children of each clip included.
Iterable<String> _ids(List<ChartPrimitive> primitives) sync* {
  for (final ChartPrimitive p in primitives) {
    yield p.id;
    if (p is ClipPrimitive) {
      yield* _ids(p.children);
    }
  }
}

/// The expected fields of one id form.
typedef _Expected = ({
  ChartElementKind kind,
  ChartAxisRole? axis,
  int? series,
  int? category,
  int? index,
});

_Expected _e(
  ChartElementKind kind, {
  ChartAxisRole? axis,
  int? series,
  int? category,
  int? index,
}) =>
    (kind: kind, axis: axis, series: series, category: category, index: index);

void main() {
  group('ChartElementId.parse reads each id form of the scheme', () {
    final Map<String, _Expected> cases = <String, _Expected>{
      'background': _e(ChartElementKind.background),
      'title': _e(ChartElementKind.title),
      'legend': _e(ChartElementKind.legend),
      'plot': _e(ChartElementKind.plot),
      'plot/clip': _e(ChartElementKind.plotClip),
      'placeholder': _e(ChartElementKind.placeholder),
      'legend/2/symbol': _e(ChartElementKind.legendSymbol, series: 2),
      'legend/0/marker': _e(ChartElementKind.legendSymbol, series: 0),
      'legend/0/text': _e(ChartElementKind.legendText, series: 0),
      'axis/value/line': _e(
        ChartElementKind.axisLine,
        axis: ChartAxisRole.value,
      ),
      'axis/category/line': _e(
        ChartElementKind.axisLine,
        axis: ChartAxisRole.category,
      ),
      'axis/value/label/10': _e(
        ChartElementKind.axisLabel,
        axis: ChartAxisRole.value,
        index: 10,
      ),
      'axis/category/label/3': _e(
        ChartElementKind.axisLabel,
        axis: ChartAxisRole.category,
        category: 3,
        index: 3,
      ),
      'axis/value/title': _e(
        ChartElementKind.axisTitle,
        axis: ChartAxisRole.value,
      ),
      'axis/category/title': _e(
        ChartElementKind.axisTitle,
        axis: ChartAxisRole.category,
      ),
      'grid/value/0': _e(
        ChartElementKind.gridLine,
        axis: ChartAxisRole.value,
        index: 0,
      ),
      'grid/category/4': _e(
        ChartElementKind.gridLine,
        axis: ChartAxisRole.category,
        index: 4,
      ),
      'series/1/bar/4': _e(ChartElementKind.bar, series: 1, category: 4),
      'series/0/line/2': _e(ChartElementKind.line, series: 0, index: 2),
      'series/0/marker/7': _e(ChartElementKind.marker, series: 0, category: 7),
      'series/2/area': _e(ChartElementKind.area, series: 2),
      'label/1/3': _e(ChartElementKind.dataLabel, series: 1, category: 3),
      'series/12/bar/365': _e(ChartElementKind.bar, series: 12, category: 365),
    };
    for (final MapEntry<String, _Expected> c in cases.entries) {
      test(c.key, () {
        final ChartElementId? id = ChartElementId.parse(c.key);
        expect(id, isNotNull);
        expect(id!.id, c.key);
        expect(id.kind, c.value.kind);
        expect(id.axis, c.value.axis);
        expect(id.series, c.value.series);
        expect(id.category, c.value.category);
        expect(id.index, c.value.index);
      });
    }
  });

  test('ChartElementId.parse rejects strings outside the scheme', () {
    for (final String bad in <String>[
      '',
      'series/x/bar/1',
      'series/-1/bar/1',
      'series/1/bar',
      'series/1/bar/1/2',
      'series/1/area/0',
      'series/1/pie/0',
      'series//bar/1',
      'series/01/bar/1',
      'series/+1/bar/1',
      'series/1.0/bar/1',
      'series/ 1/bar/1',
      'series/99999999999999999999999/bar/1',
      'axis/depth/line',
      'axis/value',
      'axis/value/label',
      'axis/value/label/x',
      'axis/value/line/0',
      'axis/category/title/0',
      'grid/value',
      'grid/depth/0',
      'grid/value/0/1',
      'label/1/2/3',
      'label/1',
      'legend/1',
      'legend/1/name',
      'legend/1/symbol/0',
      'legend/1/marker/0',
      'legend/x/marker',
      'legend/01/marker',
      'plot/area',
      'plot/clip/0',
      'Background',
      'background/',
      '/background',
      'title/0',
      'unknown',
    ]) {
      expect(ChartElementId.parse(bad), isNull, reason: '"$bad"');
    }
  });

  test('ids are values', () {
    expect(
      ChartElementId.parse('series/1/bar/4'),
      ChartElementId.parse('series/1/bar/4'),
    );
    expect(
      ChartElementId.parse('series/1/bar/4').hashCode,
      ChartElementId.parse('series/1/bar/4').hashCode,
    );
    expect(
      ChartElementId.parse('series/1/bar/4'),
      isNot(ChartElementId.parse('series/1/bar/3')),
    );
    expect(
      ChartElementId.parse('series/1/marker/4'),
      isNot(ChartElementId.parse('series/1/bar/4')),
    );
    expect(ChartElementId.parse('label/1/3').toString(), contains('label/1/3'));
  });

  test('every id of every gallery layout parses', () {
    for (final (String name, ChartLayout layout) in goldenLayouts()) {
      for (final String id in _ids(layout.primitives)) {
        final ChartElementId? parsed = ChartElementId.parse(id);
        expect(parsed, isNotNull, reason: '$name: $id');
        expect(parsed!.id, id);
      }
      for (final ChartHiddenLabel hidden in layout.hidden) {
        expect(
          ChartElementId.parse(hidden.id),
          isNotNull,
          reason: '$name: hidden ${hidden.id}',
        );
      }
    }
  });

  test("a line chart's legend marker is in the gallery and parses", () {
    final ChartLayout layout = goldenLayouts()
        .firstWhere(((String, ChartLayout) e) => e.$1 == 'line_gap')
        .$2;
    expect(_ids(layout.primitives), contains('legend/0/marker'));
    expect(
      ChartElementId.parse('legend/0/marker'),
      isNot(ChartElementId.parse('legend/0/symbol')),
    );
  });

  test('a theme with a value axis line gives an id that parses', () {
    final ChartLayout layout = layoutChart(
      galleryCharts().first.chart,
      theme: ChartTheme.office.copyWith(valueAxisLine: true),
      size: goldenSize,
      measurer: const FixedWidthTextMeasurer(),
    );
    expect(_ids(layout.primitives), contains('axis/value/line'));
    for (final String id in _ids(layout.primitives)) {
      expect(ChartElementId.parse(id), isNotNull, reason: id);
    }
  });
}
