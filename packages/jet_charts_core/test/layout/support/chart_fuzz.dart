/// Seeded random charts for the layout fuzz test (`test/layout/fuzz_test.dart`)
/// and the long-run tool (`tool/fuzz_layout.dart`), and the check both run.
///
/// [layoutFuzzCase] builds case `i` of seed `s` from a `Random` seeded with
/// `s` and `i` alone, so any case is reproduced without the ones before it,
/// and the same on the VM and in a browser: the generator draws only from
/// `Random`, never from hash order or the platform's number formatting.
///
/// [checkLayoutCase] lays a case out and lists what breaks the layout's
/// promise: no overlapping text, nothing outside the chart, no throw, every
/// number finite.
library;

import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';

/// One generated input of `layoutChart`.
final class LayoutFuzzCase {
  /// Creates a case of [chart] laid out with [theme] on [size], measured by
  /// [measurer], formatted for [locale].
  const LayoutFuzzCase({
    required this.chart,
    required this.theme,
    required this.themeName,
    required this.size,
    required this.measurer,
    required this.locale,
    required this.localeName,
  });

  /// The chart.
  final Chart chart;

  /// The theme.
  final ChartTheme theme;

  /// `office` or `custom`, for [describe].
  final String themeName;

  /// The size laid out on.
  final ChartSize size;

  /// The text measurer.
  final FixedWidthTextMeasurer measurer;

  /// The locale.
  final FormatLocale locale;

  /// The locale's name, for [describe].
  final String localeName;

  /// Lays the case out.
  ChartLayout layout() => layoutChart(
    chart,
    theme: theme,
    size: size,
    measurer: measurer,
    locale: locale,
  );

  /// The whole case as text, so a failure can be read and minimized.
  String describe() {
    final StringBuffer out = StringBuffer()
      ..writeln('size: ${size.width} x ${size.height}')
      ..writeln('theme: $themeName, locale: $localeName')
      ..writeln(
        'measurer: charWidthFactor ${measurer.charWidthFactor}, '
        'lineHeightFactor ${measurer.lineHeightFactor}',
      )
      ..writeln('kind: ${chart.kind.name}, grouping: ${chart.grouping.name}')
      ..writeln('title: ${_quote(chart.title?.text)}')
      ..writeln(
        'legend: ${chart.legend.position.name}, '
        'visible: ${chart.legend.visible}',
      )
      ..writeln('dataLabels: ${chart.dataLabels.visible}')
      ..writeln('categoryAxis: ${_axis(chart.categoryAxis)}')
      ..writeln('valueAxis: ${_axis(chart.valueAxis)}');
    for (int s = 0; s < chart.series.length; s++) {
      final ChartSeries series = chart.series[s];
      out
        ..writeln('series $s: name ${series.name.values.map(_quote).toList()}')
        ..writeln(
          '  categories: '
          '${series.categories.values.map(_category).toList()}',
        )
        ..writeln('  values: ${series.values.values}');
    }
    return out.toString();
  }
}

String _axis(ChartAxis axis) =>
    'title ${_quote(axis.title)}, min ${axis.min}, max ${axis.max}, '
    'visible ${axis.visible}, gridLines ${axis.gridLines}';

String _quote(String? text) => text == null ? 'null' : '"$text"';

String _category(Object? value) => switch (value) {
  null => 'null',
  final String text => _quote(text),
  final DateTime date =>
    'DateTime.utc(${date.year}, ${date.month}, '
        '${date.day})',
  _ => value.toString(),
};

/// The kinds the frame draws; nine cases in ten use one of them.
const List<ChartKind> _framed = <ChartKind>[
  ChartKind.column,
  ChartKind.bar,
  ChartKind.line,
  ChartKind.area,
];

/// The kinds drawn as a placeholder.
const List<ChartKind> _other = <ChartKind>[
  ChartKind.pie,
  ChartKind.donut,
  ChartKind.scatter,
  ChartKind.sparkline,
  ChartKind.combination,
  ChartKind.unsupported,
];

/// The runes text is made of: Latin, digits, space, Turkish letters and
/// emoji (outside the Basic Multilingual Plane, so two UTF-16 units each).
const List<int> _runes = <int>[
  0x41, 0x42, 0x43, 0x4D, 0x57, 0x61, 0x65, 0x69, 0x6D, 0x77, //
  0x30, 0x31, 0x37, 0x39, 0x20, 0x20, 0x2D, 0x2E, //
  0x130, 0x131, 0x11E, 0x11F, 0x15E, 0x15F, //
  0x1F600, 0x1F4C8, 0x1F1F9, 0x2764, //
];

/// The values a data point or a bound is drawn from. Without [extreme] only
/// `null`, `0`, small, negative and ordinary values are drawn; with it also
/// `NaN`, the infinities and huge values.
double? _value(math.Random r, {bool extreme = true}) {
  switch (extreme
      ? r.nextInt(12)
      : <int>[0, 3, 4, 7, 9, 10, 11][r.nextInt(7)]) {
    case 0:
      return null;
    case 1:
      return double.nan;
    case 2:
      return r.nextBool() ? double.infinity : double.negativeInfinity;
    case 3:
      return 0;
    case 4:
      return r.nextDouble() * 1e-6;
    case 5:
      return r.nextBool() ? 1e300 : -1e300;
    case 6:
      return r.nextBool() ? double.maxFinite : -double.maxFinite;
    case 7:
      return -r.nextDouble() * 1000;
    case 8:
      return (r.nextDouble() - 0.5) * 1e12;
    default:
      return r.nextDouble() * 100;
  }
}

/// A finite value for an axis bound.
double _bound(math.Random r) {
  final double? v = _value(r);
  return v != null && v.isFinite ? v : r.nextDouble() * 50 - 10;
}

String _text(math.Random r, int maxRunes) {
  final int length = r.nextInt(maxRunes + 1);
  return String.fromCharCodes(<int>[
    for (int i = 0; i < length; i++) _runes[r.nextInt(_runes.length)],
  ]);
}

double _between(math.Random r, double low, double high) =>
    low + r.nextDouble() * (high - low);

/// Case [index] of [seed].
LayoutFuzzCase layoutFuzzCase(int seed, int index) {
  final math.Random r = math.Random(seed * 1000003 + index);
  final ChartKind kind = r.nextInt(10) == 0
      ? _other[r.nextInt(_other.length)]
      : _framed[r.nextInt(_framed.length)];
  final ChartGrouping grouping =
      ChartGrouping.values[r.nextInt(ChartGrouping.values.length)];
  final int seriesCount = r.nextInt(13);
  final int categoryCount = r.nextInt(61);
  final int categoryType = r.nextInt(3);
  final bool extreme = r.nextInt(3) == 0;
  Object? category(int i) {
    if (r.nextInt(20) == 0) {
      return null;
    }
    switch (categoryType) {
      case 0:
        return _text(r, 40);
      case 1:
        return r.nextBool() ? i + 1 : _value(r) ?? 0;
      default:
        return DateTime.utc(
          1900 + r.nextInt(200),
          1 + r.nextInt(12),
          1 + r.nextInt(28),
        );
    }
  }

  final List<Object?> categories = <Object?>[
    for (int i = 0; i < categoryCount; i++) category(i),
  ];
  final List<ChartSeries> series = <ChartSeries>[
    for (int s = 0; s < seriesCount; s++)
      ChartSeries(
        name: ChartData<String>(
          values: <String?>[if (r.nextInt(8) != 0) _text(r, 30)],
        ),
        categories: ChartData<Object>(values: categories),
        values: ChartData<double>(
          values: <double?>[
            for (
              int i = 0, n = r.nextInt(6) == 0 ? r.nextInt(61) : categoryCount;
              i < n;
              i++
            )
              _value(r, extreme: extreme),
          ],
        ),
      ),
  ];
  ChartAxis axis({required bool value}) {
    double? min;
    double? max;
    if (value && r.nextInt(4) == 0) {
      switch (r.nextInt(3)) {
        case 0:
          min = _bound(r);
        case 1:
          max = _bound(r);
        default:
          min = _bound(r);
          max = _bound(r);
      }
    }
    return ChartAxis(
      title: r.nextInt(4) == 0 ? _text(r, 200) : null,
      min: min,
      max: max,
      visible: r.nextInt(6) != 0,
      gridLines: r.nextBool(),
    );
  }

  final ChartAxis categoryAxis = axis(value: false);
  final ChartAxis valueAxis = axis(value: true);
  final Chart chart = Chart(
    kind: kind,
    grouping: grouping,
    series: series,
    title: r.nextInt(3) == 0 ? null : ChartTitle(text: _text(r, 200)),
    legend: ChartLegend(
      position: ChartLegendPosition
          .values[r.nextInt(ChartLegendPosition.values.length)],
      visible: r.nextInt(4) != 0,
    ),
    dataLabels: ChartDataLabels(visible: r.nextInt(3) == 0),
    categoryAxis: categoryAxis,
    valueAxis: valueAxis,
  );
  final bool custom = r.nextBool();
  final ChartTheme theme = custom
      ? ChartTheme.office.copyWith(
          palette: <ChartColor>[
            for (int i = 0; i < 3; i++) ChartColor.rgb(r.nextInt(0x1000000)),
          ],
        )
      : ChartTheme.office;
  final ChartSize size = ChartSize(
    _between(r, 20, 1600),
    _between(r, 20, 1000),
  );
  final FixedWidthTextMeasurer measurer = FixedWidthTextMeasurer(
    charWidthFactor: _between(r, 0.4, 0.9),
    lineHeightFactor: _between(r, 0.4, 0.9),
  );
  const List<(String, FormatLocale)> locales = <(String, FormatLocale)>[
    ('en-US', FormatLocale.enUS),
    ('de-DE', FormatLocale.deDE),
    ('tr-TR', FormatLocale.trTR),
  ];
  final (String localeName, FormatLocale locale) =
      locales[r.nextInt(locales.length)];
  return LayoutFuzzCase(
    chart: chart,
    theme: theme,
    themeName: custom ? 'custom' : 'office',
    size: size,
    measurer: measurer,
    locale: locale,
    localeName: localeName,
  );
}

/// An integer fingerprint of [c] that does not depend on the platform's
/// number formatting: equal on the VM and in a browser when the generator
/// drew the same case.
int layoutFuzzFingerprint(LayoutFuzzCase c) {
  int h = 17;
  void add(int v) => h = (h * 31 + v) & 0x3FFFFFFF;
  void addDouble(double? v) {
    if (v == null) {
      add(1);
    } else if (v.isNaN) {
      add(2);
    } else if (v.isInfinite) {
      add(v > 0 ? 3 : 4);
    } else {
      // Six significant digits as an integer mantissa and an exponent.
      final int e = v == 0 ? 0 : (math.log(v.abs()) / math.ln10).floor();
      add(e + 400);
      add((v / math.pow(10.0, e) * 1e5).round() & 0x3FFFFFFF);
    }
  }

  void addText(String? t) {
    if (t == null) {
      add(5);
      return;
    }
    add(t.length);
    for (final int unit in t.codeUnits) {
      add(unit);
    }
  }

  final Chart chart = c.chart;
  add(chart.kind.index);
  add(chart.grouping.index);
  add(chart.legend.position.index);
  add(chart.legend.visible ? 1 : 0);
  add(chart.dataLabels.visible ? 1 : 0);
  addText(chart.title?.text);
  for (final ChartAxis axis in <ChartAxis>[
    chart.categoryAxis,
    chart.valueAxis,
  ]) {
    addText(axis.title);
    addDouble(axis.min);
    addDouble(axis.max);
    add(axis.visible ? 1 : 0);
    add(axis.gridLines ? 1 : 0);
  }
  for (final ChartSeries s in chart.series) {
    for (final String? name in s.name.values) {
      addText(name);
    }
    for (final Object? category in s.categories.values) {
      switch (category) {
        case final String text:
          addText(text);
        case final DateTime date:
          add(date.year);
          add(date.month);
          add(date.day);
        case final num number:
          addDouble(number.toDouble());
        default:
          add(6);
      }
    }
    for (final double? v in s.values.values) {
      addDouble(v);
    }
  }
  for (final ChartColor color in c.theme.palette) {
    add(color.rgb);
  }
  addDouble(c.size.width);
  addDouble(c.size.height);
  addDouble(c.measurer.charWidthFactor);
  addDouble(c.measurer.lineHeightFactor);
  addText(c.localeName);
  return h;
}

/// The tolerance of the inside-the-chart check, as `findOverlaps` uses.
const double _tolerance = 1e-6;

/// Lays [c] out and lists every broken promise as a line: a throw, or what
/// [layoutProblems] finds.
List<String> checkLayoutCase(LayoutFuzzCase c) {
  final ChartLayout layout;
  try {
    layout = c.layout();
  } catch (e, stack) {
    final String top = stack.toString().split('\n').take(6).join('\n');
    return <String>['layoutChart threw ${e.runtimeType}: $e\n$top'];
  }
  return layoutProblems(layout);
}

/// Every broken promise of [layout] as a line: a number that is not finite,
/// an overlap `findOverlaps` reports, or a primitive outside the size. Marks
/// inside a `ClipPrimitive` may reach past the plot by design, so they are
/// checked for finiteness only; the clip's own rectangle, and every text,
/// must lie inside the size.
List<String> layoutProblems(ChartLayout layout) {
  final List<String> problems = <String>[];
  final ChartSize size = layout.size;

  void finite(String id, String what, Iterable<double> values) {
    for (final double v in values) {
      if (!v.isFinite) {
        problems.add('$id: $what is not finite ($v)');
        return;
      }
    }
  }

  void inside(String id, String what, ChartRect r) {
    final double left = math.min(r.left, r.right);
    final double right = math.max(r.left, r.right);
    final double top = math.min(r.top, r.bottom);
    final double bottom = math.max(r.top, r.bottom);
    if (left < -_tolerance ||
        top < -_tolerance ||
        right > size.width + _tolerance ||
        bottom > size.height + _tolerance) {
      problems.add('$id: $what $r lies outside $size');
    }
  }

  Iterable<double> rect(ChartRect r) => <double>[
    r.left,
    r.top,
    r.width,
    r.height,
  ];

  void walk(List<ChartPrimitive> list, {required bool clipped}) {
    for (final ChartPrimitive p in list) {
      switch (p) {
        case RectPrimitive():
          finite(p.id, 'rect', <double>[...rect(p.rect), p.strokeWidth]);
          if (!clipped) {
            inside(p.id, 'rect', p.rect);
          }
        case PathPrimitive():
          finite(p.id, 'path', <double>[
            for (final ChartPoint q in p.points) ...<double>[q.x, q.y],
            p.strokeWidth,
            ...?p.dash,
          ]);
          if (!clipped && p.points.isNotEmpty) {
            double minX = p.points.first.x;
            double maxX = minX;
            double minY = p.points.first.y;
            double maxY = minY;
            for (final ChartPoint q in p.points) {
              minX = math.min(minX, q.x);
              maxX = math.max(maxX, q.x);
              minY = math.min(minY, q.y);
              maxY = math.max(maxY, q.y);
            }
            inside(
              p.id,
              'path',
              ChartRect(minX, minY, maxX - minX, maxY - minY),
            );
          }
        case ArcPrimitive():
          finite(p.id, 'arc', <double>[
            p.center.x,
            p.center.y,
            p.radius,
            p.innerRadius,
            p.startAngle,
            p.sweepAngle,
          ]);
          if (!clipped) {
            inside(
              p.id,
              'arc',
              ChartRect(
                p.center.x - p.radius,
                p.center.y - p.radius,
                2 * p.radius,
                2 * p.radius,
              ),
            );
          }
        case TextPrimitive():
          finite(p.id, 'text', <double>[
            ...rect(p.rect),
            p.rotationDegrees,
            p.style.size,
          ]);
          // findOverlaps reports a text outside the size; a clipped text is
          // still checked, as nothing clips a label on purpose.
          if (p.rect.left.isFinite &&
              p.rect.top.isFinite &&
              p.rect.width.isFinite &&
              p.rect.height.isFinite &&
              p.rotationDegrees.isFinite) {
            inside(p.id, 'text bounds', p.bounds);
          }
        case ClipPrimitive():
          finite(p.id, 'clip', rect(p.rect));
          if (!clipped) {
            inside(p.id, 'clip', p.rect);
          }
          walk(p.children, clipped: true);
      }
    }
  }

  walk(layout.primitives, clipped: false);
  if (problems.isEmpty) {
    for (final ChartOverlap overlap in findOverlaps(layout.primitives, size)) {
      if (overlap.kind != ChartOverlapKind.textOutside) {
        problems.add('overlap: $overlap');
      }
    }
  }
  return problems;
}
