/// The pie and doughnut groups of a chart part read back: the slice colours,
/// the hole size and the labels.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_reader.dart`, kept apart only to keep that file readable:
/// these are members of its reader, through a private extension.
///
/// A pie has no axes, so its typed form carries `DrawingChartIds`' default
/// axis ids, which the writer checks but does not write: a pie written with
/// other axis ids reads back with the defaults.
part of 'chart_reader.dart';

/// The hole size a doughnut reads with when its `c:holeSize` is missing, not
/// a number or outside the 10 to 90 `Chart` holds: `Chart`'s default.
const double _defaultHoleSize = 75;

extension _PieReading on _ChartReader {
  /// The [Chart] and typed form of a pie or doughnut [group] of [kind].
  DrawingChartRead _readPie(
    Uint8List bytes,
    ChartKind kind,
    _Node group,
    List<ChartSeries> series,
    List<_Node> seriesNodes,
    _Node? titleNode,
    String? titleText,
  ) {
    final Chart chart = Chart(
      kind: kind,
      series: series,
      title: titleText == null ? null : ChartTitle(text: titleText),
      legend: _ChartReader._legend(chartNode.child('legend')),
      dataLabels: _pieDataLabels(group, seriesNodes),
      holeSizePercent: kind == ChartKind.donut
          ? _holeSize(group.child('holeSize'))
          : _defaultHoleSize,
    );
    final DrawingChartSpace? typed = _slicesWritten(series, seriesNodes)
        ? _typed(
            bytes,
            chart,
            seriesNodes,
            autoTitle: titleNode != null && titleText == null,
          )
        : null;
    return DrawingChartRead(
      chart,
      typed,
      List<DrawingChartIssue>.unmodifiable(issues),
    );
  }

  /// Whether each of [seriesNodes] holds a `c:dPt` for every value of its
  /// series in [series], as the writer writes one per slice. A part that
  /// does not cannot be its typed form's, so the typed check, which would
  /// write a slice for each of up to a million points a `c:ptCount` gives,
  /// is skipped.
  static bool _slicesWritten(
    List<ChartSeries> series,
    List<_Node> seriesNodes,
  ) {
    for (int i = 0; i < series.length && i < seriesNodes.length; i++) {
      if (seriesNodes[i].all('dPt').length < series[i].values.values.length) {
        return false;
      }
    }
    return true;
  }

  /// A series of a pie or doughnut: as any series, but its point colours are
  /// the slices', and a slice in the theme's colour of its index (the one the
  /// writer derives) reads as automatic. The list ends at the last slice with
  /// a colour of its own.
  ChartSeries _readPieSeries(_Node node, int index) {
    final ChartSeries series = _readSeries(node, index, lines: false);
    final List<ChartColor?> colors = <ChartColor?>[
      for (int i = 0; i < series.pointColors.length; i++)
        switch (series.pointColors[i]) {
          final ChartColor color
              when !_writtenAlike(color, theme.seriesColor(i)) =>
            color,
          _ => null,
        },
    ];
    int length = colors.length;
    while (length > 0 && colors[length - 1] == null) {
      length--;
    }
    return series.copyWith(pointColors: colors.sublist(0, length));
  }

  /// The hole size of the `c:holeSize` [node]: its `val` when it is a number
  /// within 10 and 90, else [_defaultHoleSize] (and
  /// [DrawingChartIssue.badNumber] when it is not a number).
  double _holeSize(_Node? node) {
    final double? size = _numberOf(node);
    if (size == null || size < 10 || size > 90) {
      return _defaultHoleSize;
    }
    return size;
  }

  /// The first series' data labels that has its own, else the group's: shown
  /// when they are not deleted and show the value or the percent.
  static ChartDataLabels _pieDataLabels(_Node group, List<_Node> seriesNodes) {
    _Node? labels;
    for (final _Node node in seriesNodes) {
      labels = node.child('dLbls');
      if (labels != null) {
        break;
      }
    }
    labels ??= group.child('dLbls');
    if (labels == null) {
      return const ChartDataLabels();
    }
    final bool value = _flag(labels.child('showVal'), absent: false);
    final bool percent = _flag(labels.child('showPercent'), absent: false);
    if (_flag(labels.child('delete'), absent: false) || !(value || percent)) {
      return const ChartDataLabels();
    }
    return ChartDataLabels(
      visible: true,
      formatCode: _ChartReader._formatCode(labels.child('numFmt')),
      showValue: value,
      showPercent: percent,
    );
  }
}
