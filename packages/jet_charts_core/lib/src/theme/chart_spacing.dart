/// The distances and line widths of a chart's layout: [ChartSpacing].
library;

import '../model/equality.dart';

/// The gaps, symbol sizes and line widths the layout uses, in the unit of the
/// backend (points in the Office theme).
///
/// Every default is the Office theme's value. Excel's default charts
/// (`chart_defaults.xlsx`) verify the line widths, the overlap and the tick
/// length, and the owner's `chart_reference.xlsx` the bar overlap; the gaps and the legend's sizes are unconfirmed, as Excel lays a
/// chart out itself and writes none of them (`docs/excel-checks.md`).
final class ChartSpacing {
  /// Creates a spacing; every field has the Office theme's default.
  ///
  /// Throws an [ArgumentError] when a field other than [overlapPercent] and
  /// [barOverlapPercent] is negative or not finite (a negative padding would
  /// put the title and the legend outside the size), or when one of those two
  /// is not finite; they may be negative, and the bars clamp them.
  ChartSpacing({
    this.padding = 8,
    this.titleGap = 6,
    this.legendGap = 6,
    this.legendSymbol = 7,
    this.legendItemGap = 12,
    this.labelGap = 4,
    this.minTextGap = 2,
    this.tickLength = 0,
    this.gridLineWidth = 0.75,
    this.axisLineWidth = 0.75,
    this.overlapPercent = -27,
    this.barOverlapPercent = 0,
  }) {
    for (final (String name, double value) in <(String, double)>[
      ('padding', padding),
      ('titleGap', titleGap),
      ('legendGap', legendGap),
      ('legendSymbol', legendSymbol),
      ('legendItemGap', legendItemGap),
      ('labelGap', labelGap),
      ('minTextGap', minTextGap),
      ('tickLength', tickLength),
      ('gridLineWidth', gridLineWidth),
      ('axisLineWidth', axisLineWidth),
    ]) {
      if (!value.isFinite || value < 0) {
        throw ArgumentError.value(
          value,
          name,
          'must be finite and not negative',
        );
      }
    }
    for (final (String name, double value) in <(String, double)>[
      ('overlapPercent', overlapPercent),
      ('barOverlapPercent', barOverlapPercent),
    ]) {
      if (!value.isFinite) {
        throw ArgumentError.value(value, name, 'must be finite');
      }
    }
  }

  /// The margin between the chart's edge and its content. Unconfirmed.
  final double padding;

  /// The gap between the title and what lies under it. Unconfirmed.
  final double titleGap;

  /// The gap between the legend and the plot area. Unconfirmed.
  final double legendGap;

  /// The side of a legend's colour symbol. Unconfirmed.
  final double legendSymbol;

  /// The gap between two legend entries. Unconfirmed.
  final double legendItemGap;

  /// The gap between an axis and its tick labels. Unconfirmed.
  final double labelGap;

  /// The smallest gap left between two texts that share a line. Unconfirmed.
  final double minTextGap;

  /// The length of an axis tick mark. Reserved: milestone J2 draws no tick
  /// marks whatever its value, so it changes nothing yet. Verified: Excel's
  /// default axes have no tick marks.
  final double tickLength;

  /// The width of a grid line. Verified: 0.75 pt in Excel.
  final double gridLineWidth;

  /// The width of an axis line. Verified: 0.75 pt in Excel.
  final double axisLineWidth;

  /// The overlap of the bars of one category in a clustered column chart, as
  /// a percentage of a bar's width; negative leaves a gap. Verified: -27 in
  /// Excel.
  final double overlapPercent;

  /// The overlap of the bars of one category in a clustered bar chart (bars
  /// along the horizontal axis), as [overlapPercent] is for columns.
  /// Verified: 0 in Excel, which writes no `c:overlap` for its clustered bar
  /// chart (`chart_reference.xlsx`). Stacked kinds always overlap fully
  /// (`ChartTheme.overlapPercentOf`).
  final double barOverlapPercent;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartSpacing copyWith({
    double? padding,
    double? titleGap,
    double? legendGap,
    double? legendSymbol,
    double? legendItemGap,
    double? labelGap,
    double? minTextGap,
    double? tickLength,
    double? gridLineWidth,
    double? axisLineWidth,
    double? overlapPercent,
    double? barOverlapPercent,
  }) {
    return ChartSpacing(
      padding: padding ?? this.padding,
      titleGap: titleGap ?? this.titleGap,
      legendGap: legendGap ?? this.legendGap,
      legendSymbol: legendSymbol ?? this.legendSymbol,
      legendItemGap: legendItemGap ?? this.legendItemGap,
      labelGap: labelGap ?? this.labelGap,
      minTextGap: minTextGap ?? this.minTextGap,
      tickLength: tickLength ?? this.tickLength,
      gridLineWidth: gridLineWidth ?? this.gridLineWidth,
      axisLineWidth: axisLineWidth ?? this.axisLineWidth,
      overlapPercent: overlapPercent ?? this.overlapPercent,
      barOverlapPercent: barOverlapPercent ?? this.barOverlapPercent,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartSpacing &&
        valueEquals(padding, other.padding) &&
        valueEquals(titleGap, other.titleGap) &&
        valueEquals(legendGap, other.legendGap) &&
        valueEquals(legendSymbol, other.legendSymbol) &&
        valueEquals(legendItemGap, other.legendItemGap) &&
        valueEquals(labelGap, other.labelGap) &&
        valueEquals(minTextGap, other.minTextGap) &&
        valueEquals(tickLength, other.tickLength) &&
        valueEquals(gridLineWidth, other.gridLineWidth) &&
        valueEquals(axisLineWidth, other.axisLineWidth) &&
        valueEquals(overlapPercent, other.overlapPercent) &&
        valueEquals(barOverlapPercent, other.barOverlapPercent);
  }

  @override
  int get hashCode => Object.hash(
    valueHash(padding),
    valueHash(titleGap),
    valueHash(legendGap),
    valueHash(legendSymbol),
    valueHash(legendItemGap),
    valueHash(labelGap),
    valueHash(minTextGap),
    valueHash(tickLength),
    valueHash(gridLineWidth),
    valueHash(axisLineWidth),
    valueHash(overlapPercent),
    valueHash(barOverlapPercent),
  );

  @override
  String toString() => 'ChartSpacing(padding: $padding)';
}
