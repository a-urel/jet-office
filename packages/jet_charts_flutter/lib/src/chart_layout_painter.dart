/// A [CustomPainter] that paints a chart layout's primitives.
library;

import 'package:flutter/rendering.dart';
import 'package:jet_charts_core/jet_charts_core.dart';

import 'primitive_painter.dart';
import 'text_measurer.dart';

/// Paints [primitives] with [paintChartPrimitives], drawing text with
/// [measurer], the measurer the layout was measured with.
final class ChartLayoutPainter extends CustomPainter {
  /// Creates a painter of [primitives] whose text [measurer] draws; it also
  /// repaints whenever [repaint] notifies.
  ChartLayoutPainter({
    required this.primitives,
    required this.measurer,
    super.repaint,
  });

  /// What to paint, in order, usually a `ChartLayout`'s primitives.
  final List<ChartPrimitive> primitives;

  /// The measurer whose painters draw the text.
  final FlutterTextMeasurer measurer;

  /// Paints [primitives] on [canvas]; [size] is not used, as the primitives
  /// carry their own positions.
  @override
  void paint(Canvas canvas, Size size) {
    paintChartPrimitives(canvas, primitives, measurer);
  }

  /// Whether [oldDelegate] painted another primitive list or with another
  /// measurer, compared by identity.
  @override
  bool shouldRepaint(ChartLayoutPainter oldDelegate) {
    return !identical(primitives, oldDelegate.primitives) ||
        !identical(measurer, oldDelegate.measurer);
  }
}
