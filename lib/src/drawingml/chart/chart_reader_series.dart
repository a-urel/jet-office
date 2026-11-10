/// The series of a chart part read back: their names, colours, categories
/// and values, with the references verbatim.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_reader.dart`, kept apart only to keep that file readable:
/// these are members of its reader, through a private extension.
part of 'chart_reader.dart';

/// The most points a series' data is read with, and one past the largest
/// point index read: 1,048,576, the rows of a sheet.
const int _maxPoints = 1 << 20;

/// A number as a chart part may spell it: `xsd:double` without `INF` and
/// `NaN`. Each character can match one way only, so matching is linear.
final RegExp _numberText = RegExp(
  r'^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$',
);

/// The longest number text read; a longer one is a bad number. Excel's
/// numbers have at most 17 significant digits.
const int _maxNumberLength = 400;

final RegExp _countText = RegExp(r'^[0-9]+$');

/// The largest date serial [drawingDateOf] converts, either way.
const double _maxSerial = 9e7;

/// The data of a `c:cat`, `c:val` or the like: its reference, its format
/// code, whether it holds numbers, and the text of each point (`null` for a
/// point it lacks).
typedef _Source = ({
  String? reference,
  String? formatCode,
  bool numbers,
  List<String?> points,
});

extension _SeriesReading on _ChartReader {
  ChartSeries _readSeries(_Node node, int index, {required bool lines}) {
    final _Source? categories = _source(
      node.child('cat') ?? node.child('xVal'),
    );
    final _Source? values = _source(node.child('val') ?? node.child('yVal'));
    final String? formatCode = values?.formatCode;
    return ChartSeries(
      name: _seriesName(node.child('tx')),
      categories: categories == null
          ? ChartData<Object>(values: const <Object?>[])
          : ChartData<Object>(
              values: _categoryValues(categories),
              reference: categories.reference,
            ),
      values: values == null
          ? ChartData<double>(values: const <double?>[])
          : ChartData<double>(
              values: <double?>[
                for (final String? text in values.points)
                  text == null ? null : _number(text),
              ],
              reference: values.reference,
            ),
      formatCode: formatCode == 'General' ? null : formatCode,
      color: _seriesColor(node.child('spPr'), index, lines: lines),
      smooth: _flag(node.child('smooth'), absent: false),
      pointColors: _pointColors(node, lines: lines),
    );
  }

  /// The colours of the series' `c:dPt` points, by index: a line's from the
  /// marker's fill, a bar's from the shape's fill; `null` for a point
  /// without one. The list ends at the last point with a colour, and an
  /// index beyond [_maxPoints] is [DrawingChartIssue.badNumber].
  List<ChartColor?> _pointColors(_Node series, {required bool lines}) {
    final List<ChartColor?> colors = <ChartColor?>[];
    for (final _Node point in series.all('dPt')) {
      final int? index = _count(point.child('idx')?.val);
      if (index == null || index >= _maxPoints) {
        _report(DrawingChartIssue.badNumber);
        continue;
      }
      final _Node? shape = lines
          ? point.child('marker')?.child('spPr')
          : point.child('spPr');
      final ChartColor? color = shape
          ?.child('solidFill', drawingMainNamespace)
          ?.children
          .where((_Node n) => n.isColor)
          .firstOrNull
          ?.color;
      if (color == null) {
        continue;
      }
      if (index >= colors.length) {
        final int growth = index + 1 - colors.length;
        if (growth > pointBudget) {
          // The list draws from the budget of the part's data, as a cache.
          _report(DrawingChartIssue.badNumber);
          continue;
        }
        pointBudget -= growth;
        colors.addAll(List<ChartColor?>.filled(growth, null));
      }
      colors[index] = color;
    }
    return colors;
  }

  /// The series name of the `c:tx` [node]: the reference and the cached text
  /// of a `c:strRef` (no value when the cache has none), or the text of a
  /// `c:v`.
  ChartData<String> _seriesName(_Node? node) {
    if (node == null) {
      return ChartData<String>(values: const <String?>[]);
    }
    final _Node? reference = node.child('strRef');
    if (reference != null) {
      final String? value = _firstText(reference.child('strCache'));
      return ChartData<String>(
        values: value == null ? const <String?>[] : <String?>[value],
        reference: _referenceOf(reference),
      );
    }
    final _Node? v = node.child('v');
    return ChartData<String>(
      values: v == null
          ? const <String?>[]
          : <String?>[drawingUnescapeXstring(v.text)],
    );
  }

  /// The text of the first point of the cache [node], Xstring decoded.
  String? _firstText(_Node? node) {
    if (node == null) {
      return null;
    }
    for (final String? text in _points(node)) {
      if (text != null) {
        return drawingUnescapeXstring(text);
      }
    }
    return null;
  }

  /// The categories of [source]: numbers, dates when its format code is a
  /// date's, or text.
  List<Object?> _categoryValues(_Source source) {
    if (!source.numbers) {
      return <Object?>[
        for (final String? text in source.points)
          text == null ? null : drawingUnescapeXstring(text),
      ];
    }
    final String? code = source.formatCode;
    final bool dates =
        code != null && classifyFormatCode(code) == FormatKind.date;
    final List<Object?> values = <Object?>[];
    for (final String? text in source.points) {
      final double? number = text == null ? null : _number(text);
      if (number == null || !dates) {
        values.add(number);
      } else if (number.abs() > _maxSerial) {
        _report(DrawingChartIssue.badNumber);
        values.add(null);
      } else {
        values.add(drawingDateOf(number));
      }
    }
    return values;
  }

  /// The data of [node], a `c:cat`, `c:val`, `c:xVal` or `c:yVal`, from its
  /// first `c:numRef`, `c:numLit`, `c:strRef`, `c:strLit` or
  /// `c:multiLvlStrRef` (whose levels are not read); `null` when it has none.
  _Source? _source(_Node? node) {
    if (node == null) {
      return null;
    }
    for (final _Node data in node.children) {
      if (data.uri != drawingChartNamespace) {
        continue;
      }
      final (_Node? cache, bool numbers) = switch (data.name) {
        'numRef' => (data.child('numCache'), true),
        'numLit' => (data, true),
        'strRef' => (data.child('strCache'), false),
        'strLit' => (data, false),
        _ => (null, false),
      };
      if (cache == null && !data.name.endsWith('Ref')) {
        continue;
      }
      final _Node? formatCode = cache?.child('formatCode');
      return (
        reference: _referenceOf(data),
        formatCode: formatCode == null
            ? null
            : drawingUnescapeXstring(formatCode.text),
        numbers: numbers,
        points: cache == null ? const <String?>[] : _points(cache),
      );
    }
    return null;
  }

  /// The `c:f` of [node], Xstring decoded, or `null`.
  static String? _referenceOf(_Node node) {
    final _Node? f = node.child('f');
    return f == null ? null : drawingUnescapeXstring(f.text);
  }

  /// The text of each point of the cache or literal [node], as many as its
  /// `c:ptCount` says (or as its last point needs), `null` for a point it
  /// lacks.
  ///
  /// A count or index that cannot be read, or one beyond [_maxPoints], is
  /// [DrawingChartIssue.badNumber]: the count is cut to the limit and the
  /// point left out. Every cache of the part draws its entries from one
  /// budget ([_ChartReader.pointBudget]); a cache whose count would exceed
  /// what is left is cut to its last point (within what is left), with
  /// [DrawingChartIssue.badNumber], so a part cannot ask for more entries
  /// than its size allows.
  List<String?> _points(_Node node) {
    int declared = 0;
    final _Node? count = node.child('ptCount');
    if (count != null) {
      final int? n = _count(count.val);
      if (n == null) {
        _report(DrawingChartIssue.badNumber);
      }
      declared = n ?? 0;
    }
    if (declared > _maxPoints) {
      _report(DrawingChartIssue.badNumber);
      declared = _maxPoints;
    }
    final List<(int, String?)> points = <(int, String?)>[];
    int needed = 0;
    for (final _Node point in node.all('pt')) {
      final int? index = _count(point.attributes['idx']);
      if (index == null || index >= _maxPoints) {
        _report(DrawingChartIssue.badNumber);
        continue;
      }
      points.add((index, point.child('v')?.text));
      if (index >= needed) {
        needed = index + 1;
      }
    }
    int length = declared > needed ? declared : needed;
    if (length > pointBudget) {
      _report(DrawingChartIssue.badNumber);
      length = needed < pointBudget ? needed : pointBudget;
    }
    pointBudget -= length;
    final List<String?> texts = List<String?>.filled(length, null);
    for (final (int index, String? text) in points) {
      if (index < length) {
        texts[index] = text;
      }
    }
    return texts;
  }

  /// [text] as a count or index, `null` unless it is digits only; a number
  /// beyond [_maxPoints] is given as one past it.
  static int? _count(String? text) {
    if (text == null || !_countText.hasMatch(text)) {
      return null;
    }
    if (text.length > 8) {
      // More digits than any count within the limit, leading zeros aside.
      final String digits = text.replaceFirst(RegExp('^0+'), '');
      if (digits.length > 8) {
        return _maxPoints + 1;
      }
      return digits.isEmpty ? 0 : int.parse(digits);
    }
    return int.parse(text);
  }

  /// [text] as a finite number, or `null` and [DrawingChartIssue.badNumber].
  double? _number(String text) {
    final double? n =
        text.length <= _maxNumberLength && _numberText.hasMatch(text)
        ? double.tryParse(text)
        : null;
    if (n == null || !n.isFinite) {
      _report(DrawingChartIssue.badNumber);
      return null;
    }
    return n;
  }

  /// The colour of the series shape [node]: its line's for a group of
  /// [lines], else its fill's (each the other when it lacks one); `null`
  /// when it has none, when it cannot be read, or when the writer would
  /// write the colour it derives for the series' [index] alike.
  ChartColor? _seriesColor(_Node? node, int index, {required bool lines}) {
    if (node == null) {
      return null;
    }
    final _Node? fill = node.child('solidFill', drawingMainNamespace);
    final _Node? line = node
        .child('ln', drawingMainNamespace)
        ?.child('solidFill', drawingMainNamespace);
    final _Node? holder = lines ? (line ?? fill) : (fill ?? line);
    final ChartColor? color = holder?.children
        .where((_Node n) => n.isColor)
        .firstOrNull
        ?.color;
    if (color == null) {
      return null;
    }
    return _writtenAlike(color, theme.seriesColor(index)) ? null : color;
  }

  /// Whether the writer writes [a] and [b] alike in the theme's export
  /// colours: as the same slot and luminance when they follow the file
  /// theme and both are bound to a slot, else as the same RGB value.
  bool _writtenAlike(ChartColor a, ChartColor b) {
    final bool scheme = theme.exportColors == ChartExportColors.fileTheme;
    final bool aSlot = scheme && a.slot != null;
    final bool bSlot = scheme && b.slot != null;
    if (aSlot != bSlot) {
      return false;
    }
    if (!aSlot) {
      return a.rgb == b.rgb;
    }
    return a.slot == b.slot &&
        (a.lumMod * 100000).round() == (b.lumMod * 100000).round() &&
        (a.lumOff * 100000).round() == (b.lumOff * 100000).round();
  }
}
