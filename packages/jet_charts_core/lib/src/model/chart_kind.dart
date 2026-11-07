/// The kinds of chart the model describes.
library;

/// What a chart draws.
enum ChartKind {
  /// Vertical bars, one group per category.
  column,

  /// Horizontal bars, one group per category.
  bar,

  /// Points joined by lines over the categories.
  line,

  /// Lines with the area below them filled.
  area,

  /// One circle cut into slices, one per category.
  pie,

  /// A pie with a hole in the middle.
  donut,

  /// Points placed by two numbers.
  scatter,

  /// A small line chart without axes or text.
  sparkline,

  /// Series of different kinds in one chart; each series names its own kind.
  combination,

  /// A kind read from a file that the model does not draw. The chart's
  /// `unsupportedName` holds the kind's name in the file.
  unsupported,
}

/// How the series of a chart share the space of a category.
enum ChartGrouping {
  /// Side by side.
  clustered,

  /// On top of each other, adding up.
  stacked,

  /// On top of each other, each category scaled to one hundred percent.
  percentStacked,
}

/// Which value axis a series is measured on.
enum ChartAxisBinding {
  /// The chart's value axis.
  primary,

  /// The chart's secondary value axis.
  secondary,
}

/// Where the legend sits.
enum ChartLegendPosition {
  /// Above the plot.
  top,

  /// Below the plot.
  bottom,

  /// Left of the plot.
  left,

  /// Right of the plot.
  right,
}
