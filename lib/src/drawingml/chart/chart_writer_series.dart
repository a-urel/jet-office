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
  /// A series of a bar, line or area group, drawn as [kind] (the chart's,
  /// or in a combination the series' own).
  void _writeSeries(ChartSeries series, int index, ChartKind kind) {
    w.start('c:ser');
    _value('c:idx', index.toString());
    _value('c:order', index.toString());
    _writeSeriesName(series.name);
    final ChartColor color = theme.colorOf(series, index);
    w.start('c:spPr');
    if (kind == ChartKind.line) {
      _seriesLine(color);
      w.empty('a:effectLst');
      w.end();
      w.start('c:marker');
      if (theme.lineMarkersOf(chart.kind)) {
        _value('c:symbol', 'circle');
        _value('c:size', theme.markerSize.clamp(2, 72).round().toString());
        _markerShape(color);
      } else {
        // Excel's "Line" without markers, and a combination's line
        // (`chart_reference_j4.xlsx`, chart 5). A lone point, which the
        // layout marks, has no marker here: a series' marker is all or
        // nothing.
        _value('c:symbol', 'none');
      }
      w.end();
    } else {
      final bool area = kind == ChartKind.area;
      _solidFill(
        color,
        alpha: area && theme.areaOpacity < 1 ? theme.areaOpacity : null,
      );
      if (area && theme.areaLine) {
        _seriesLine(color);
      } else {
        w.start('a:ln');
        w.empty('a:noFill');
        w.end();
      }
      w.empty('a:effectLst');
      w.end();
      if (_isBars(kind)) {
        _value('c:invertIfNegative', '0');
      }
    }
    if (kind != ChartKind.area) {
      _writePointColors(series, color, kind);
    }
    if (chart.dataLabels.visible) {
      _writeSeriesDataLabels();
    }
    _writeCategories(series.categories);
    _writeValues(series);
    if (kind == ChartKind.line) {
      _value('c:smooth', series.smooth ? '1' : '0');
    }
    _writeSeriesId(index);
    w.end();
  }

  /// The series' `c:val`, or the element [name], in its format code
  /// (`General` when it has none).
  void _writeValues(ChartSeries series, {String name = 'c:val'}) {
    w.start(name);
    _writeNumbers(
      series.values.values,
      series.values.reference,
      _scrub(series.formatCode ?? 'General'),
      (double v) => v,
    );
    w.end();
  }

  /// The `c:extLst` of the `c16:uniqueId` of series [index], left out when
  /// `space.ids` has no id for it.
  void _writeSeriesId(int index) {
    if (index < space.ids.series.length) {
      w.start('c:extLst');
      w.start('c:ext');
      w.attribute('uri', _uniqueIdExtension);
      w.attribute('xmlns:c16', _c16Namespace);
      _value('c16:uniqueId', _scrub(space.ids.series[index]));
      w.end();
      w.end();
    }
  }

  /// A series' `a:ln` of [color]: the theme's line width, a round cap and a
  /// round join.
  void _seriesLine(ChartColor color) {
    w.start('a:ln');
    w.attribute('w', (theme.lineWidth * _emuPerPoint).round().toString());
    w.attribute('cap', 'rnd');
    _solidFill(color);
    w.empty('a:round');
    w.end();
  }

  /// A marker's `c:spPr`: [color] as its fill and its line, and an empty
  /// effect list.
  void _markerShape(ChartColor color) {
    w.start('c:spPr');
    _solidFill(color);
    w.start('a:ln');
    w.attribute('w', _markerLineWidth);
    _solidFill(color);
    w.end();
    w.empty('a:effectLst');
    w.end();
  }

  /// One `c:dPt` per point of [series], drawn as [kind], with its own colour
  /// (`ChartTheme.pointColorOf`: a point colour key is written as the
  /// theme's colour of it), after the
  /// series' shape and marker (`c:dPt` follows `c:marker` and
  /// `c:invertIfNegative`, and precedes `c:dLbls`, in the schema).
  ///
  /// Each holds the index, `c:invertIfNegative 0` of a bar, for a line the
  /// marker with the colour as its fill and line, `c:bubble3D 0` and the
  /// shape, a fill for a bar and the series' own line (the segment is not
  /// recoloured) for a line, or a scatter chart's line without fill. The
  /// layout is an estimate, not checked in Excel (pending E1; a scatter
  /// chart's, as a line's, is not in the E1 file).
  void _writePointColors(
    ChartSeries series,
    ChartColor seriesColor,
    ChartKind kind,
  ) {
    final bool scatter = kind == ChartKind.scatter;
    final bool marked = scatter || kind == ChartKind.line;
    for (int i = 0; i < theme.pointColorCount(series); i++) {
      final ChartColor? color = theme.pointColorOf(series, i);
      if (color == null) {
        continue;
      }
      w.start('c:dPt');
      _value('c:idx', i.toString());
      if (_isBars(kind)) {
        _value('c:invertIfNegative', '0');
      }
      if (marked) {
        w.start('c:marker');
        _value('c:symbol', 'circle');
        _value('c:size', theme.markerSize.clamp(2, 72).round().toString());
        _markerShape(color);
        w.end();
      }
      _value('c:bubble3D', '0');
      w.start('c:spPr');
      if (scatter) {
        _scatterSeriesLine();
      } else if (marked) {
        _seriesLine(seriesColor);
      } else {
        _solidFill(color);
        w.start('a:ln');
        w.empty('a:noFill');
        w.end();
      }
      w.empty('a:effectLst');
      w.end();
      w.end();
    }
  }

  /// The series' `c:dLbls` of shown labels, as Excel writes them
  /// (`chart_reference.xlsx`, charts 20 and 21): the format when the labels
  /// have one, a bare shape, the data label text, `c:showVal 1` among the
  /// flags, `c:showLeaderLines 0`, and Excel's leader lines in a `c15`
  /// extension (left out when not [leaderLines]). No position: Excel writes
  /// none, and draws each kind's default.
  void _writeSeriesDataLabels({bool leaderLines = true}) {
    w.start('c:dLbls');
    final String? formatCode = chart.dataLabels.formatCode;
    if (formatCode != null) {
      w.empty('c:numFmt', <String, String>{
        'formatCode': _scrub(formatCode),
        'sourceLinked': '0',
      });
    }
    _noFillShape();
    writeDrawingTextBody(
      w,
      theme.dataLabels,
      mode: mode,
      language: language,
      use: DrawingTextUse.dataLabel,
    );
    _writeLabelFlags(showValue: chart.dataLabels.showValue);
    _value('c:showLeaderLines', '0');
    if (!leaderLines) {
      w.end();
      return;
    }
    w.start('c:extLst');
    w.start('c:ext');
    w.attribute('uri', _leaderLinesExtension);
    w.attribute('xmlns:c15', _c15Namespace);
    _value('c15:showLeaderLines', '1');
    w.start('c15:leaderLines');
    w.start('c:spPr');
    _line(_leaderLineColor, _leaderLineWidth);
    w.empty('a:effectLst');
    w.end();
    w.end();
    w.end();
    w.end();
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

  /// The series' `c:cat`, or the element [name], left out when the
  /// categories have neither values nor a reference.
  void _writeCategories(ChartData<Object> categories, {String name = 'c:cat'}) {
    final List<Object?> values = categories.values;
    final String? reference = categories.reference;
    if (values.isEmpty && reference == null) {
      return;
    }
    w.start(name);
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
          (Object v) => drawingSerialOf(v as DateTime, date1904: date1904),
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
