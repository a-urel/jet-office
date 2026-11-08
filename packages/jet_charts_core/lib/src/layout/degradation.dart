/// The order in which a chart that does not fit loses its content, and the
/// flags of what is still shown.
///
/// Two ways take content away. A part that does not fit its own space (a
/// title wider than the chart, a legend over a third of it, an axis title
/// longer than its axis) is hidden alone ([FramePart]). When the plot would
/// be under 1 by 1, or tick or category labels would collide, the next
/// [DegradeStep] is taken, in order.
library;

import '../model/chart.dart';
import 'resolve.dart';

/// The steps that take content away when it does not fit, in order.
///
/// A step is taken when the plot would be under 1 by 1 or the tick labels or
/// category labels would collide. When every step is taken and the plot is
/// still under 1 by 1, only the background is drawn.
enum DegradeStep {
  /// The data labels go. Task 8 fills this hook; until then it hides nothing.
  dataLabels,

  /// The legend goes.
  legend,

  /// The axis titles go.
  axisTitles,

  /// The chart title goes.
  title,

  /// The category labels go.
  categoryLabels,

  /// The value axis' tick labels go.
  valueLabels,
}

/// A part that is hidden alone when it does not fit its own space.
enum FramePart {
  /// The chart title.
  title,

  /// The legend.
  legend,

  /// The value axis' title.
  valueTitle,

  /// The category axis' title.
  categoryTitle,
}

/// What the frame draws: each flag is true while its part is shown.
final class FrameShown {
  /// What [chart] asks for: every part it has.
  FrameShown.wanted(Chart chart, ResolvedChart resolved)
    : dataLabels = chart.dataLabels.visible,
      legend = chart.legend.visible && resolved.seriesNames.isNotEmpty,
      title = (chart.title?.text ?? '').isNotEmpty,
      valueTitle = (chart.valueAxis.title ?? '').isNotEmpty,
      categoryTitle = (chart.categoryAxis.title ?? '').isNotEmpty,
      categoryLabels = chart.categoryAxis.visible && resolved.categoryCount > 0,
      valueLabels = chart.valueAxis.visible;

  /// Whether the data labels are drawn.
  bool dataLabels;

  /// Whether the legend is drawn.
  bool legend;

  /// Whether the chart title is drawn.
  bool title;

  /// Whether the value axis' title is drawn.
  bool valueTitle;

  /// Whether the category axis' title is drawn.
  bool categoryTitle;

  /// Whether the category labels are drawn.
  bool categoryLabels;

  /// Whether the value axis' tick labels are drawn.
  bool valueLabels;

  /// Hides [part], which does not fit its own space.
  void hide(FramePart part) {
    switch (part) {
      case FramePart.title:
        title = false;
      case FramePart.legend:
        legend = false;
      case FramePart.valueTitle:
        valueTitle = false;
      case FramePart.categoryTitle:
        categoryTitle = false;
    }
  }

  /// Takes [step] of the degradation order.
  void take(DegradeStep step) {
    switch (step) {
      case DegradeStep.dataLabels:
        // Task 8: data labels are hidden here.
        dataLabels = false;
      case DegradeStep.legend:
        legend = false;
      case DegradeStep.axisTitles:
        valueTitle = false;
        categoryTitle = false;
      case DegradeStep.title:
        title = false;
      case DegradeStep.categoryLabels:
        categoryLabels = false;
      case DegradeStep.valueLabels:
        valueLabels = false;
    }
  }

  /// Takes every step: only the background is left.
  void hideAll() {
    for (final DegradeStep step in DegradeStep.values) {
      take(step);
    }
  }
}
