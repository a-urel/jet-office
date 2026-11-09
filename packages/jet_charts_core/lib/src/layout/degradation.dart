/// The order in which a chart that does not fit loses its content, and the
/// flags of what is still shown.
///
/// Two ways take content away. A part that does not fit its own space (a
/// title wider than the chart, a legend over a third of it, an axis title
/// longer than its axis) is hidden alone ([FramePart]). When the frame does
/// not fit ([FrameMisfit]), the first [DegradeStep] in order that can relieve
/// the misfit is taken ([FrameShown.relieves]); a step that cannot is passed
/// over, so a chart whose category labels alone do not fit keeps its title and
/// legend.
library;

import '../model/chart.dart';
import '../model/chart_kind.dart';
import 'resolve.dart';

/// The steps that take content away when it does not fit, in order.
///
/// A step is taken when the frame does not fit and the step can relieve what
/// does not fit. When no step can and the frame still does not fit, only the
/// background is drawn.
enum DegradeStep {
  /// The data labels go. They take no room from the frame, so this step
  /// relieves no misfit: they go, first, only when nothing else helps and
  /// only the background is drawn.
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

/// Why a frame does not fit.
enum FrameMisfit {
  /// The plot would be under 1 by 1, or the bands around it do not settle.
  space,

  /// The value axis' tick labels collide, at the coarsest scale it allows
  /// (an automatic unit; a fixed one is thinned instead).
  valueLabels,

  /// No plan of the category labels fits: their band limit (40% of the space
  /// left for the plot and the band) is too small even for a cut label.
  categoryLabels,

  /// The category labels would fit apart and within their band limit but
  /// for the room past the axis' ends; only hiding them relieves that.
  categoryRoom,
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
      categoryLabels =
          chart.categoryAxis.visible &&
          (chart.kind == ChartKind.scatter || resolved.categoryCount > 0),
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

  /// Whether taking [step] can relieve any of [misfits].
  ///
  /// A step that hides nothing shown relieves nothing. The data labels take
  /// no room from the frame and are never part of its misfit (a label that
  /// collides is hidden alone), so their step relieves nothing: they go only
  /// when no step can relieve the frame and only the background is left,
  /// and they stay first in the order and in the hidden list. Any other step
  /// frees space, so it relieves [FrameMisfit.space].
  ///
  /// The category labels get a deeper band from more space across the
  /// category axis, which is the plot's height for a column, line or area
  /// chart ([bar] false) and its width for a bar chart. So the legend
  /// relieves [FrameMisfit.categoryLabels] when it stands at the top or
  /// bottom of a column chart, or at the left or right of a bar chart; the
  /// axis titles when the category axis has a title (it stands across that
  /// direction); the title only on a column chart; and the category labels
  /// always. Only the category labels relieve [FrameMisfit.categoryRoom].
  ///
  /// [FrameMisfit.valueLabels] is relieved only by the value labels' own
  /// step: a fixed unit is thinned by the frame instead, and an automatic
  /// one has taken its coarsest step, so the legend, the titles and the
  /// category labels are never given up for the tick labels.
  bool relieves(
    DegradeStep step,
    Set<FrameMisfit> misfits, {
    required bool bar,
    required ChartLegendPosition legendPosition,
  }) {
    final bool space = misfits.contains(FrameMisfit.space);
    final bool along = misfits.contains(FrameMisfit.categoryLabels);
    switch (step) {
      case DegradeStep.dataLabels:
        return false;
      case DegradeStep.legend:
        final bool vertical =
            legendPosition == ChartLegendPosition.top ||
            legendPosition == ChartLegendPosition.bottom;
        return legend && (space || along && vertical != bar);
      case DegradeStep.axisTitles:
        return (valueTitle || categoryTitle) &&
            (space || along && categoryTitle);
      case DegradeStep.title:
        return title && (space || along && !bar);
      case DegradeStep.categoryLabels:
        return categoryLabels &&
            (space || along || misfits.contains(FrameMisfit.categoryRoom));
      case DegradeStep.valueLabels:
        return valueLabels &&
            (space || misfits.contains(FrameMisfit.valueLabels));
    }
  }

  /// Takes every step: only the background is left.
  void hideAll() {
    for (final DegradeStep step in DegradeStep.values) {
      take(step);
    }
  }
}
