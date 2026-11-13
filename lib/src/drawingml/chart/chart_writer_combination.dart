/// The groups of a chart part with axes: one per drawn kind and axis, for a
/// combination chart and a chart with a secondary value axis, as Excel for
/// Mac writes them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_writer.dart`, kept apart only to keep that file readable:
/// these are members of its writer, through a private extension.
///
/// The template is the owner's `chart_reference_j4.xlsx` (Excel for Mac
/// 16.114.4, `packages/jet_charts_core/docs/excel-checks.md`, "J4 values"),
/// chart 5: Excel's "Clustered Column - Line" on one axis, a `c:barChart` of
/// gap 150 without overlap, then a `c:lineChart` whose line is 2.25 pt
/// without markers, and no `c:crosses` on either axis. The secondary axes
/// (a deleted `c:catAx` without tick marks or `c:crosses`, and a `c:valAx`
/// on the right that crosses it at the maximum, without grid lines unless
/// the axis asks) are Excel's own combination of the owner's
/// `chart_reference_e3.xlsx` (E3), chart 1. A combination with an area group
/// (written first, as the layout draws areas under columns) is an estimate
/// from the gallery workbook
/// (`packages/jet_charts_flutter/example/lib/src/excel_gallery.dart`), not
/// checked in Excel.
part of 'chart_writer.dart';

/// Whether a chart of [kind] may have a secondary value axis: column, line,
/// area and combination charts (`ChartSeries.axis`); a bar chart's is not
/// written.
bool _hasSecondaryAxis(ChartKind kind) => switch (kind) {
  ChartKind.column ||
  ChartKind.line ||
  ChartKind.area ||
  ChartKind.combination => true,
  _ => false,
};

/// Whether a group of [kind] is a `c:barChart`.
bool _isBars(ChartKind kind) =>
    kind == ChartKind.column || kind == ChartKind.bar;

/// The order the groups of each axis are written in: the layout's
/// (`markGroups` of `jet_charts_core`), areas under columns and bars, lines
/// on top.
const List<ChartKind> _groupOrder = <ChartKind>[
  ChartKind.area,
  ChartKind.column,
  ChartKind.bar,
  ChartKind.line,
];

extension _CombinationWriting on _ChartWriter {
  /// Whether each series goes on the secondary axes: bound to it, in a chart
  /// that may have one, while some series is bound to the primary axis (as
  /// the layout measures it; with none, every series is on the primary
  /// axes and no secondary axis is written).
  List<bool> _secondaryOf() {
    final bool anyPrimary = chart.series.any(
      (ChartSeries s) => s.axis == ChartAxisBinding.primary,
    );
    return <bool>[
      for (final ChartSeries s in chart.series)
        _hasSecondaryAxis(chart.kind) &&
            anyPrimary &&
            s.axis == ChartAxisBinding.secondary,
    ];
  }

  /// The kind [series] is drawn as: its own in a combination chart (a series
  /// of no kind is a column; the writer refuses the others), else the
  /// chart's.
  ChartKind _drawnKind(ChartSeries series) {
    if (chart.kind != ChartKind.combination) {
      return chart.kind;
    }
    return switch (series.kind) {
      ChartKind.line => ChartKind.line,
      ChartKind.area => ChartKind.area,
      _ => ChartKind.column,
    };
  }

  /// The grouping of a group of [kind]: the chart's, but `clustered` for a
  /// combination's lines, which the layout draws unstacked.
  ChartGrouping _groupingOf(ChartKind kind) =>
      chart.kind == ChartKind.combination && kind == ChartKind.line
      ? ChartGrouping.clustered
      : chart.grouping;

  /// The plot area's groups: per axis, primary first, a group per drawn kind
  /// in [_groupOrder], each with its series in series order (their `c:idx`
  /// and `c:order` are their indexes in the chart). A chart of one kind on
  /// one axis pair is one group, even with no series; a combination with no
  /// series is an empty column group.
  void _writeGroups() {
    if (!_secondary.contains(true) && chart.kind != ChartKind.combination) {
      _writeGroup(chart.kind, <int>[
        for (int i = 0; i < chart.series.length; i++) i,
      ]);
      return;
    }
    if (chart.series.isEmpty) {
      _writeGroup(ChartKind.column, const <int>[]);
      return;
    }
    final List<ChartKind> kinds = <ChartKind>[
      for (final ChartSeries s in chart.series) _drawnKind(s),
    ];
    for (final bool secondary in <bool>[false, true]) {
      for (final ChartKind kind in _groupOrder) {
        final List<int> members = <int>[
          for (int i = 0; i < kinds.length; i++)
            if (kinds[i] == kind && _secondary[i] == secondary) i,
        ];
        if (members.isNotEmpty) {
          _writeGroup(kind, members, secondary: secondary);
        }
      }
    }
  }

  /// An axis' `c:crosses` of [value], or of `autoZero` when [value] is
  /// `null`, but none on a combination chart's primary axes, as Excel's
  /// chart 5 writes them.
  void _writeCrosses(String? value) {
    if (value == null && chart.kind == ChartKind.combination) {
      return;
    }
    _value('c:crosses', value ?? 'autoZero');
  }

  /// Whether the value axis, or the [secondary] one, shows `0%`: the chart
  /// is percent stacked and a stacked group is on that axis (for a chart of
  /// one kind on one axis pair, whether or not it has series). A scatter
  /// chart has no grouping.
  bool _percentAxis({required bool secondary}) {
    if (chart.kind == ChartKind.scatter ||
        chart.grouping != ChartGrouping.percentStacked) {
      return false;
    }
    if (!secondary && chart.kind != ChartKind.combination) {
      return true;
    }
    for (int i = 0; i < chart.series.length; i++) {
      if (_secondary[i] == secondary &&
          _groupingOf(_drawnKind(chart.series[i])) ==
              ChartGrouping.percentStacked) {
        return true;
      }
    }
    return false;
  }
}
