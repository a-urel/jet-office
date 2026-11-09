/// The texts `JetChart` shows and says: its state texts and its description
/// for a screen reader.
library;

import 'package:jet_charts_core/jet_charts_core.dart';

/// The texts of `JetChart` in one language: what its loading, empty and error
/// looks show, and the words of [describe], the description a screen reader
/// reads.
///
/// The templates [seriesCount], [categoryRange], [valueRange], [moreValues],
/// [share] and [centerText] take the placeholders `{n}` (a count), `{first}`
/// and `{last}` (the first and last category), `{min}` and `{max}` (the least
/// and greatest value), `{value}` and `{percent}` (a value and its share) and
/// `{text}` (a donut's centre text). Each is replaced once, so a category
/// named `{last}` stays as it is. A template ends without a full stop;
/// [describe] adds it.
final class JetChartStrings {
  /// Creates the texts of one language.
  const JetChartStrings({
    required this.loading,
    required this.empty,
    required this.error,
    required this.kindNames,
    required this.seriesCount,
    required this.categoryRange,
    required this.valueRange,
    required this.moreValues,
    this.share = '{value} ({percent})',
    this.centerText = 'Center: {text}',
  });

  /// English.
  static const JetChartStrings en = JetChartStrings(
    loading: 'Loading chart…',
    empty: 'No data',
    error: 'The chart could not be shown',
    kindNames: <ChartKind, String>{
      ChartKind.column: 'Column chart',
      ChartKind.bar: 'Bar chart',
      ChartKind.line: 'Line chart',
      ChartKind.area: 'Area chart',
      ChartKind.pie: 'Pie chart',
      ChartKind.donut: 'Donut chart',
      ChartKind.scatter: 'Scatter chart',
      ChartKind.sparkline: 'Sparkline',
      ChartKind.combination: 'Combination chart',
      ChartKind.unsupported: 'Unsupported chart',
    },
    seriesCount: 'Series ({n})',
    categoryRange: 'Categories ({n}): {first} to {last}',
    valueRange: 'Values from {min} to {max}',
    moreValues: 'and {n} more',
    share: '{value} ({percent})',
    centerText: 'Center: {text}',
  );

  /// Turkish.
  static const JetChartStrings tr = JetChartStrings(
    loading: 'Grafik yükleniyor…',
    empty: 'Veri yok',
    error: 'Grafik gösterilemedi',
    kindNames: <ChartKind, String>{
      ChartKind.column: 'Sütun grafik',
      ChartKind.bar: 'Çubuk grafik',
      ChartKind.line: 'Çizgi grafik',
      ChartKind.area: 'Alan grafik',
      ChartKind.pie: 'Pasta grafik',
      ChartKind.donut: 'Halka grafik',
      ChartKind.scatter: 'Dağılım grafiği',
      ChartKind.sparkline: 'Mini grafik',
      ChartKind.combination: 'Birleşik grafik',
      ChartKind.unsupported: 'Desteklenmeyen grafik',
    },
    seriesCount: 'Seriler ({n})',
    categoryRange: 'Kategoriler ({n}): {first} ile {last} arası',
    valueRange: 'Değerler {min} ile {max} arasında',
    moreValues: 've {n} değer daha',
    share: '{value} ({percent})',
    centerText: 'Orta: {text}',
  );

  /// German.
  static const JetChartStrings de = JetChartStrings(
    loading: 'Diagramm wird geladen…',
    empty: 'Keine Daten',
    error: 'Das Diagramm kann nicht angezeigt werden',
    kindNames: <ChartKind, String>{
      ChartKind.column: 'Säulendiagramm',
      ChartKind.bar: 'Balkendiagramm',
      ChartKind.line: 'Liniendiagramm',
      ChartKind.area: 'Flächendiagramm',
      ChartKind.pie: 'Kreisdiagramm',
      ChartKind.donut: 'Ringdiagramm',
      ChartKind.scatter: 'Punktdiagramm',
      ChartKind.sparkline: 'Sparkline',
      ChartKind.combination: 'Kombinationsdiagramm',
      ChartKind.unsupported: 'Nicht unterstütztes Diagramm',
    },
    seriesCount: 'Datenreihen ({n})',
    categoryRange: 'Kategorien ({n}): {first} bis {last}',
    valueRange: 'Werte von {min} bis {max}',
    moreValues: 'und {n} weitere',
    share: '{value} ({percent})',
    centerText: 'Mitte: {text}',
  );

  /// The most `category value` pairs [describe] reads per series before
  /// [moreValues] counts the rest.
  static const int maxValuesPerSeries = 12;

  /// The most per-point screen reader nodes `JetChart` gives below its own
  /// node (one per category, slice or scatter point); a chart that would
  /// need more gets none, and [describe] alone speaks for it.
  static const int maxPointNodes = 200;

  /// What the loading look shows and says.
  final String loading;

  /// What the empty look shows and says, below the chart's title if any.
  final String empty;

  /// What the error look shows and says; the error itself is never shown.
  final String error;

  /// The name of each chart kind as it starts a sentence, such as
  /// `Column chart`; a kind missing here is named by its enum name.
  final Map<ChartKind, String> kindNames;

  /// The series count, before a colon and the series' names, with `{n}`.
  final String seriesCount;

  /// The category count and range, with `{n}`, `{first}` and `{last}`.
  final String categoryRange;

  /// The value range, with `{min}` and `{max}`.
  final String valueRange;

  /// What follows a series' first [maxValuesPerSeries] values when it has
  /// more, with `{n}`, the count of the rest.
  final String moreValues;

  /// A value of a pie or donut with its share of its series' whole, with
  /// `{value}` and `{percent}`; `{value} ({percent})` unless given.
  final String share;

  /// A donut's centre text, with `{text}`; the English `Center: {text}`
  /// unless given.
  final String centerText;

  /// The description of [summary] for a screen reader, in sentences: the
  /// kind and title; a donut's [centerText]; the series count and names; the
  /// category count, first and last; the value range; then one sentence per
  /// series of up to [maxValuesPerSeries] `category value` pairs,
  /// [moreValues] counting the rest.
  ///
  /// In a pie or donut each value that has a share is read by [share], as
  /// `category value (percent)`. A scatter chart has no categories: its
  /// category sentence is left out, and each series reads `(x, y)` pairs of
  /// its points.
  ///
  /// The values are the summary's texts, formatted for its locale. A missing
  /// value is left out of the pairs and the count. A sentence with nothing to
  /// say (no series, no category, no value) is left out.
  String describe(ChartSummary summary) => sentences(summary).join(' ');

  /// The sentences [describe] joins, each ending in a full stop.
  List<String> sentences(ChartSummary summary) {
    final String kind = kindNames[summary.kind] ?? summary.kind.name;
    final List<String> out = <String>[
      summary.title == null ? '$kind.' : '$kind: ${summary.title}.',
    ];
    final String? center = summary.centerText;
    if (center != null) {
      out.add('${_fill(centerText, <String, String>{'text': center})}.');
    }
    final bool scatter = summary.kind == ChartKind.scatter;
    final List<String> names = summary.seriesNames;
    if (names.isNotEmpty) {
      out.add(
        '${_fill(seriesCount, <String, String>{'n': '${names.length}'})}: '
        '${names.join(', ')}.',
      );
    }
    final List<String> categories = summary.categories;
    if (categories.isNotEmpty && !scatter) {
      out.add(
        '${_fill(categoryRange, <String, String>{'n': '${categories.length}', 'first': categories.first, 'last': categories.last})}.',
      );
    }
    final String? min = summary.minimum;
    final String? max = summary.maximum;
    if (min != null && max != null) {
      out.add(
        '${_fill(valueRange, <String, String>{'min': min, 'max': max})}.',
      );
    }
    for (int s = 0; s < summary.values.length && s < names.length; s++) {
      final List<String> pairs = <String>[];
      final List<String> values = summary.values[s];
      final List<String> shares = s < summary.shares.length
          ? summary.shares[s]
          : const <String>[];
      final List<String> xs = s < summary.xValues.length
          ? summary.xValues[s]
          : const <String>[];
      for (int c = 0; c < values.length; c++) {
        if (values[c].isEmpty) {
          continue;
        }
        if (scatter) {
          if (c < xs.length) {
            pairs.add('(${xs[c]}, ${values[c]})');
          }
          continue;
        }
        if (c >= categories.length) {
          break;
        }
        final String value = c < shares.length && shares[c].isNotEmpty
            ? _fill(share, <String, String>{
                'value': values[c],
                'percent': shares[c],
              })
            : values[c];
        pairs.add('${categories[c]} $value');
      }
      if (pairs.isEmpty) {
        continue;
      }
      final String shown = pairs.take(maxValuesPerSeries).join(', ');
      final int rest = pairs.length - maxValuesPerSeries;
      out.add(
        rest > 0
            ? '${names[s]}: $shown '
                  '${_fill(moreValues, <String, String>{'n': '$rest'})}.'
            : '${names[s]}: $shown.',
      );
    }
    return out;
  }

  /// [template] with each `{name}` of [values] replaced, in one pass.
  static String _fill(String template, Map<String, String> values) {
    return template.replaceAllMapped(
      RegExp(r'\{(n|first|last|min|max|value|percent|text)\}'),
      (Match m) => values[m[1]] ?? m[0]!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! JetChartStrings ||
        loading != other.loading ||
        empty != other.empty ||
        error != other.error ||
        seriesCount != other.seriesCount ||
        categoryRange != other.categoryRange ||
        valueRange != other.valueRange ||
        moreValues != other.moreValues ||
        share != other.share ||
        centerText != other.centerText ||
        kindNames.length != other.kindNames.length) {
      return false;
    }
    for (final MapEntry<ChartKind, String> e in kindNames.entries) {
      if (other.kindNames[e.key] != e.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    loading,
    empty,
    error,
    seriesCount,
    categoryRange,
    valueRange,
    moreValues,
    share,
    centerText,
    Object.hashAllUnordered(
      kindNames.entries.map(
        (MapEntry<ChartKind, String> e) => Object.hash(e.key, e.value),
      ),
    ),
  );
}
