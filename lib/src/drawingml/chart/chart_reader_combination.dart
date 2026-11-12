/// The plot areas of several bar, line and area groups read back: a
/// combination chart, and a column, line or area chart with a secondary
/// value axis.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_reader.dart`, kept apart only to keep that file readable:
/// these are members of its reader, through a private extension.
///
/// Such a plot area reads when every group is a `c:barChart` of columns, a
/// `c:lineChart` or a `c:areaChart`, and every group's two `c:axId` name one
/// of at most two axis pairs (a `c:catAx` or `c:dateAx` and a `c:valAx`),
/// which are the plot area's two or four axes: the first group's pair is the
/// primary one, the other the secondary one. Groups of one kind give a chart
/// of that kind, groups of several a combination whose series carry their
/// group's kind; a series of a group on the secondary pair is bound to the
/// secondary axis. The series are read in their `c:order` (document order
/// when an order is missing, unreadable or repeated). Anything else (a
/// horizontal bar group beside another, a third pair, a pair no group uses)
/// is left to the caller, which reads it as `unsupported`.
part of 'chart_reader.dart';

/// The axes of a plot area of bar, line and area groups: the primary pair,
/// and the secondary pair when a group is on it.
typedef _AxisPairs = ({
  _Node categoryAxis,
  _Node valueAxis,
  (int, int) primary,
  _Node? secondaryValueAxis,
  (int, int)? secondary,
});

extension _CombinationReading on _ChartReader {
  /// The chart of [groups] on [axes], or `null` when they are not a plot
  /// area of bar, line and area groups on one or two axis pairs.
  DrawingChartRead? _readGroups(
    Uint8List bytes,
    List<_Node> groups,
    List<_Node> axes,
  ) {
    final _AxisPairs? pairs = _axisPairs(groups, axes);
    if (pairs == null) {
      return null;
    }
    final List<ChartKind> kinds = <ChartKind>[
      for (final _Node group in groups)
        switch (group.name) {
          'lineChart' => ChartKind.line,
          'areaChart' => ChartKind.area,
          _ =>
            group.child('barDir')?.val == 'bar'
                ? ChartKind.bar
                : ChartKind.column,
        },
    ];
    if (kinds.contains(ChartKind.bar)) {
      // A bar chart's secondary axis, and bars beside other groups, are not
      // in the model.
      return null;
    }
    final Set<ChartKind> distinct = kinds.toSet();
    final ChartKind kind = distinct.length == 1
        ? distinct.single
        : ChartKind.combination;
    final List<({_Node node, ChartKind kind, bool secondary})> members =
        <({_Node node, ChartKind kind, bool secondary})>[
          for (int g = 0; g < groups.length; g++)
            for (final _Node node in groups[g].all('ser'))
              (
                node: node,
                kind: kinds[g],
                secondary: _pairOf(groups[g]) != pairs.primary,
              ),
        ];
    _sortByOrder(members, (m) => m.node);
    final List<_Node> seriesNodes = <_Node>[for (final m in members) m.node];
    final List<ChartSeries> series = <ChartSeries>[
      for (int i = 0; i < members.length; i++)
        _readSeries(
          members[i].node,
          i,
          lines: members[i].kind == ChartKind.line,
        ).copyWith(
          kind: kind == ChartKind.combination ? members[i].kind : null,
          axis: members[i].secondary
              ? ChartAxisBinding.secondary
              : ChartAxisBinding.primary,
        ),
    ];
    final ChartAxis? secondaryAxis = pairs.secondaryValueAxis == null
        ? null
        : _axis(pairs.secondaryValueAxis);
    final _Node? titleNode = chartNode.child('title');
    final String? titleText = _titleText(titleNode);
    // A combination's lines are never stacked; its columns, else its areas,
    // give the grouping.
    final _Node grouping = kind == ChartKind.combination
        ? groups.firstWhere(
            (_Node g) => g.name == 'barChart',
            orElse: () => groups.firstWhere(
              (_Node g) => g.name == 'areaChart',
              orElse: () => groups.first,
            ),
          )
        : groups.first;
    final Chart chart = Chart(
      kind: kind,
      grouping: _ChartReader._grouping(grouping),
      series: series,
      categoryAxis: _axis(pairs.categoryAxis),
      valueAxis: _axis(pairs.valueAxis),
      // An axis of the default options is no axis of the chart's own: the
      // writer writes `const ChartAxis()` for a missing one.
      secondaryValueAxis: secondaryAxis == const ChartAxis()
          ? null
          : secondaryAxis,
      title: titleText == null ? null : ChartTitle(text: titleText),
      legend: _ChartReader._legend(chartNode.child('legend')),
      dataLabels: _ChartReader._dataLabels(groups.first, seriesNodes),
    );
    final DrawingChartSpace? typed = _typed(
      bytes,
      chart,
      seriesNodes,
      categoryAxisId: pairs.primary.$1,
      valueAxisId: pairs.primary.$2,
      secondaryCategoryAxisId: pairs.secondary?.$1,
      secondaryValueAxisId: pairs.secondary?.$2,
      autoTitle: titleNode != null && titleText == null,
    );
    return DrawingChartRead(
      chart,
      typed,
      List<DrawingChartIssue>.unmodifiable(issues),
    );
  }

  /// The axis pairs of [groups] on [axes], or `null` unless every group is a
  /// bar, line or area group whose two axis ids name one of at most two
  /// pairs, and those pairs are exactly [axes].
  static _AxisPairs? _axisPairs(List<_Node> groups, List<_Node> axes) {
    if (groups.isEmpty || (axes.length != 2 && axes.length != 4)) {
      return null;
    }
    (int, int)? secondary;
    final (int, int)? primary = _pairOf(groups.first);
    if (primary == null) {
      return null;
    }
    for (final _Node group in groups) {
      if (group.name != 'barChart' &&
          group.name != 'lineChart' &&
          group.name != 'areaChart') {
        return null;
      }
      final (int, int)? pair = _pairOf(group);
      if (pair == null) {
        return null;
      }
      if (pair != primary) {
        secondary ??= pair;
        if (pair != secondary) {
          return null;
        }
      }
    }
    _Node? find(int id, {required bool category}) {
      _Node? found;
      for (final _Node axis in axes) {
        final bool fits = category
            ? axis.name == 'catAx' || axis.name == 'dateAx'
            : axis.name == 'valAx';
        if (fits && _ChartReader._axisId(axis) == id) {
          if (found != null) {
            return null;
          }
          found = axis;
        }
      }
      return found;
    }

    final _Node? categoryAxis = find(primary.$1, category: true);
    final _Node? valueAxis = find(primary.$2, category: false);
    if (categoryAxis == null || valueAxis == null) {
      return null;
    }
    if (secondary == null) {
      return axes.length == 2
          ? (
              categoryAxis: categoryAxis,
              valueAxis: valueAxis,
              primary: primary,
              secondaryValueAxis: null,
              secondary: null,
            )
          : null;
    }
    final _Node? secondaryCategory = find(secondary.$1, category: true);
    final _Node? secondaryValue = find(secondary.$2, category: false);
    if (axes.length != 4 ||
        secondaryCategory == null ||
        secondaryValue == null ||
        <_Node>{
              categoryAxis,
              valueAxis,
              secondaryCategory,
              secondaryValue,
            }.length !=
            4) {
      return null;
    }
    return (
      categoryAxis: categoryAxis,
      valueAxis: valueAxis,
      primary: primary,
      secondaryValueAxis: secondaryValue,
      secondary: secondary,
    );
  }

  /// The two `c:axId` of [group], or `null` unless it has exactly two that
  /// are axis ids.
  static (int, int)? _pairOf(_Node group) {
    final List<_Node> ids = group.all('axId').toList();
    if (ids.length != 2) {
      return null;
    }
    final int? first = _ChartReader._id(ids[0].val);
    final int? second = _ChartReader._id(ids[1].val);
    return first == null || second == null ? null : (first, second);
  }

  /// Sorts [items] by the `c:order` of the series [nodeOf] gives, keeping
  /// them as they are when an order is missing, unreadable or repeated.
  static void _sortByOrder<T>(List<T> items, _Node Function(T) nodeOf) {
    final List<int> orders = <int>[];
    for (final T item in items) {
      final int? order = _SeriesReading._count(
        nodeOf(item).child('order')?.val,
      );
      if (order == null) {
        return;
      }
      orders.add(order);
    }
    if (orders.toSet().length != orders.length) {
      return;
    }
    final List<int> positions = <int>[for (int i = 0; i < items.length; i++) i]
      ..sort((int a, int b) => orders[a].compareTo(orders[b]));
    final List<T> sorted = <T>[for (final int i in positions) items[i]];
    items
      ..clear()
      ..addAll(sorted);
  }
}
