/// The series of a chart part: their names, colours, markers, categories
/// and values, as Excel for Mac writes them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_writer.dart`, kept apart only to keep that file readable:
/// these are members of its writer, through a private extension.
part of 'chart_writer.dart';

/// What the category values of a series are written as.
enum _CategoryType { number, date, text }

extension _SeriesWriting on _ChartWriter {
  void _writeSeries(ChartSeries series, int index) {
    w.start('c:ser');
    _value('c:idx', index.toString());
    _value('c:order', index.toString());
    _writeSeriesName(series.name);
    final ChartColor color = theme.colorOf(series, index);
    w.start('c:spPr');
    if (chart.kind == ChartKind.line) {
      w.start('a:ln');
      w.attribute('w', (theme.lineWidth * _emuPerPoint).round().toString());
      w.attribute('cap', 'rnd');
      _solidFill(color);
      w.empty('a:round');
      w.end();
      w.empty('a:effectLst');
      w.end();
      w.start('c:marker');
      _value('c:symbol', 'circle');
      _value('c:size', theme.markerSize.round().clamp(2, 72).toString());
      w.start('c:spPr');
      _solidFill(color);
      w.start('a:ln');
      w.attribute('w', _markerLineWidth);
      _solidFill(color);
      w.end();
      w.empty('a:effectLst');
      w.end();
      w.end();
    } else {
      _solidFill(color);
      w.start('a:ln');
      w.empty('a:noFill');
      w.end();
      w.empty('a:effectLst');
      w.end();
      if (_bars) {
        _value('c:invertIfNegative', '0');
      }
    }
    _writeCategories(series.categories);
    w.start('c:val');
    _writeNumbers(
      series.values.values,
      series.values.reference,
      _scrub(series.formatCode ?? 'General'),
      (double v) => v,
    );
    w.end();
    if (chart.kind == ChartKind.line) {
      _value('c:smooth', '0');
    }
    if (index < space.ids.series.length) {
      w.start('c:extLst');
      w.start('c:ext');
      w.attribute('uri', _uniqueIdExtension);
      w.attribute('xmlns:c16', _c16Namespace);
      _value('c16:uniqueId', _scrub(space.ids.series[index]));
      w.end();
      w.end();
    }
    w.end();
  }

  /// The series' `c:tx`: a `c:strRef` with a one-point cache when the name
  /// has a reference, else a `c:v` of its value; nothing when it has neither.
  void _writeSeriesName(ChartData<String> name) {
    final String? value = name.values.isEmpty ? null : name.values.first;
    final String? reference = name.reference;
    if (reference == null && value == null) {
      return;
    }
    w.start('c:tx');
    if (reference == null) {
      _element('c:v', _xstring(value!));
    } else {
      w.start('c:strRef');
      _element('c:f', _xstring(reference));
      w.start('c:strCache');
      _value('c:ptCount', '1');
      if (value != null) {
        _writeTextPoint(0, value);
      }
      w.end();
      w.end();
    }
    w.end();
  }

  /// The series' `c:cat`, left out when the categories have neither values
  /// nor a reference.
  void _writeCategories(ChartData<Object> categories) {
    final List<Object?> values = categories.values;
    final String? reference = categories.reference;
    if (values.isEmpty && reference == null) {
      return;
    }
    w.start('c:cat');
    switch (_categoryType(values)) {
      case _CategoryType.number:
        _writeNumbers(
          values,
          reference,
          'General',
          (Object v) => (v as num).toDouble(),
        );
      case _CategoryType.date:
        _writeNumbers(
          values,
          reference,
          _scrub(chart.categoryAxis.formatCode ?? 'm/d/yyyy'),
          (Object v) => drawingSerialOf(v as DateTime),
        );
      case _CategoryType.text:
        _writeTexts(values, reference);
    }
    w.end();
  }

  /// What [values] are written as: numbers when every entry that is not
  /// `null` is a `num`, dates when every one is a `DateTime`, else text (and
  /// text when every entry is `null`).
  static _CategoryType _categoryType(List<Object?> values) {
    bool numbers = true;
    bool dates = true;
    bool any = false;
    for (final Object? v in values) {
      if (v == null) {
        continue;
      }
      any = true;
      numbers = numbers && v is num;
      dates = dates && v is DateTime;
      if (!numbers && !dates) {
        return _CategoryType.text;
      }
    }
    if (!any) {
      return _CategoryType.text;
    }
    return numbers ? _CategoryType.number : _CategoryType.date;
  }

  /// A `c:strRef` with a `c:strCache` when [reference] is set, else a
  /// `c:strLit`, of the `toString()` of each entry; a `null` entry has no
  /// point.
  void _writeTexts(List<Object?> values, String? reference) {
    if (reference != null) {
      w.start('c:strRef');
      _element('c:f', _xstring(reference));
      w.start('c:strCache');
    } else {
      w.start('c:strLit');
    }
    _value('c:ptCount', values.length.toString());
    for (int i = 0; i < values.length; i++) {
      final Object? v = values[i];
      if (v != null) {
        _writeTextPoint(i, v.toString());
      }
    }
    w.end();
    if (reference != null) {
      w.end();
    }
  }

  void _writeTextPoint(int index, String text) {
    w.start('c:pt');
    w.attribute('idx', index.toString());
    _element('c:v', _xstring(text));
    w.end();
  }

  /// A `c:numRef` with a `c:numCache` when [reference] is set, else a
  /// `c:numLit`, of [formatCode] and each entry as [toDouble] gives it; a
  /// `null`, `NaN` or infinite entry has no point, and the last two report
  /// [DrawingChartIssue.nonFiniteValue].
  void _writeNumbers<T extends Object>(
    List<T?> values,
    String? reference,
    String formatCode,
    double Function(T) toDouble,
  ) {
    if (reference != null) {
      w.start('c:numRef');
      _element('c:f', _xstring(reference));
      w.start('c:numCache');
    } else {
      w.start('c:numLit');
    }
    _element('c:formatCode', drawingEscapeXstring(formatCode));
    _value('c:ptCount', values.length.toString());
    for (int i = 0; i < values.length; i++) {
      final T? v = values[i];
      if (v == null) {
        continue;
      }
      final double number = toDouble(v);
      if (!number.isFinite) {
        _report(DrawingChartIssue.nonFiniteValue);
        continue;
      }
      w.start('c:pt');
      w.attribute('idx', i.toString());
      _element('c:v', drawingNumberText(number));
      w.end();
    }
    w.end();
    if (reference != null) {
      w.end();
    }
  }
}
