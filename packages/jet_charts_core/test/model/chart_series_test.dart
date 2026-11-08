import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

ChartSeries series(List<double?> values, {List<Object?>? categories}) {
  return ChartSeries(
    name: ChartData<String>(values: <String?>['Sales']),
    categories: ChartData<Object>(values: categories ?? <Object?>['a', 'b']),
    values: ChartData<double>(values: values),
  );
}

void main() {
  test('a series carries nulls, NaN and infinities', () {
    final List<double?> v = <double?>[null, double.nan, double.infinity, -1];
    final ChartSeries a = series(v);
    final ChartSeries b = series(<double?>[
      null,
      double.nan,
      double.infinity,
      -1,
    ]);
    expect(a.values.values.length, 4);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(series(<double?>[null, 1, double.infinity, -1])));
  });

  test('categories and values may differ in length', () {
    final ChartSeries s = series(<double?>[1, 2, 3]);
    expect(s.categories.values.length, 2);
    expect(s.values.values.length, 3);
    expect(s, series(<double?>[1, 2, 3]));
  });

  test('categories hold strings, numbers and dates by value', () {
    final DateTime d = DateTime.utc(2026, 1, 2);
    final ChartSeries a = series(
      <double?>[1],
      categories: <Object?>['x', 2, d],
    );
    final ChartSeries b = series(
      <double?>[1],
      categories: <Object?>['x', 2, DateTime.utc(2026, 1, 2)],
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('lists are copied and unmodifiable', () {
    final List<double?> source = <double?>[1, 2];
    final ChartData<double> data = ChartData<double>(values: source);
    source[0] = 99;
    source.add(3);
    expect(data.values, <double?>[1, 2]);
    expect(() => data.values.add(1), throwsUnsupportedError);
    expect(() => data.values[0] = 5, throwsUnsupportedError);
  });

  test('a reference is optional and kept', () {
    expect(ChartData<double>(values: <double?>[1]).reference, isNull);
    expect(
      ChartData<double>(
        values: <double?>[1],
        reference: r'Sheet1!$B$2',
      ).reference,
      r'Sheet1!$B$2',
    );
    expect(
      ChartData<double>(values: <double?>[1], reference: 'a'),
      isNot(ChartData<double>(values: <double?>[1], reference: 'b')),
    );
  });

  test('copyWith changes one field', () {
    final ChartSeries s = series(<double?>[1]);
    final ChartSeries t = s.copyWith(axis: ChartAxisBinding.secondary);
    expect(t.axis, ChartAxisBinding.secondary);
    expect(t.values, s.values);
    expect(t, isNot(s));
    expect(s.axis, ChartAxisBinding.primary);
    expect(s.copyWith(), s);
  });

  test('data of a narrower type equals the same data of a wider type', () {
    final ChartData<String> narrow = ChartData<String>(
      values: <String?>['a', null],
    );
    final ChartData<Object> wide = ChartData<Object>(
      values: <Object?>['a', null],
    );
    expect(narrow == wide, isTrue);
    expect(wide == narrow, isTrue);
    expect(narrow.hashCode, wide.hashCode);
  });

  test('data equality is symmetric across type arguments', () {
    final ChartData<String> a = ChartData<String>(values: <String?>['a']);
    final ChartData<Object> b = ChartData<Object>(values: <Object?>['a']);
    expect(a == b, isTrue);
    expect(b == a, isTrue);
    expect(a.hashCode, b.hashCode);
  });

  test('categories of String copy with Object values', () {
    final ChartSeries s = ChartSeries(
      name: ChartData<String>(values: <String?>['n']),
      categories: ChartData<String>(values: <String?>['a', 'b']),
      values: ChartData<double>(values: <double?>[1, 2]),
    );
    final ChartData<Object> copy = s.categories.copyWith(values: <Object?>[1]);
    expect(copy.values, <Object?>[1]);
    expect(s.categories.values, <Object?>['a', 'b']);
  });

  test('a series colour wins over its key and the palette', () {
    final ChartTheme theme = ChartTheme.office.copyWith(
      semantic: <String, ChartColor>{'income': ChartColor.rgb(0x00FF00)},
    );
    final ChartSeries base = series(<double?>[1]);
    final ChartColor own = ChartColor.rgb(0x123456);
    expect(
      theme.colorOf(
        ChartSeries(
          name: base.name,
          categories: base.categories,
          values: base.values,
          color: own,
          colorKey: 'income',
        ),
        0,
      ),
      own,
    );
    expect(
      theme.colorOf(
        ChartSeries(
          name: base.name,
          categories: base.categories,
          values: base.values,
          colorKey: 'income',
        ),
        3,
      ),
      ChartColor.rgb(0x00FF00),
    );
    expect(theme.colorOf(base, 2), theme.seriesColor(2));
  });

  test('an unknown colour key falls to the palette', () {
    final ChartSeries base = series(<double?>[1]);
    final ChartSeries keyed = ChartSeries(
      name: base.name,
      categories: base.categories,
      values: base.values,
      colorKey: 'nope',
    );
    expect(ChartTheme.office.colorOf(keyed, 1), ChartTheme.office.palette[1]);
  });

  test('colour and key take part in equality and copyWith', () {
    final ChartSeries base = series(<double?>[1]);
    final ChartSeries a = base.copyWith(
      color: ChartColor.rgb(1),
      colorKey: 'k',
    );
    expect(a.color, ChartColor.rgb(1));
    expect(a.colorKey, 'k');
    expect(a, isNot(base));
    expect(a, base.copyWith(color: ChartColor.rgb(1), colorKey: 'k'));
    expect(
      a.hashCode,
      base.copyWith(color: ChartColor.rgb(1), colorKey: 'k').hashCode,
    );
    expect(a.copyWith(name: base.name).colorKey, 'k');
  });
}
