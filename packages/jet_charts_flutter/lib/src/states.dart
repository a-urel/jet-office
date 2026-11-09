/// The default looks of `JetChart`'s loading, empty and error states.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:jet_charts_core/jet_charts_core.dart';

import 'text_measurer.dart';

Color _color(ChartColor c) => Color(0xFF000000 | c.rgb);

/// The loading look: the theme's background and five columns of its grid
/// line colour, of fixed heights, whose opacity pulses between 0.4 and 1
/// over 1.2 s, or stays at 1 when the platform asks for no animation
/// (`MediaQuery.disableAnimations`). A screen reader reads [label].
final class LoadingLook extends StatefulWidget {
  /// Creates the loading look in [theme], read as [label].
  const LoadingLook({super.key, required this.theme, required this.label});

  /// The theme whose background and grid line colour it draws.
  final ChartTheme theme;

  /// What a screen reader reads.
  final String label;

  /// One pulse: from 0.4 to 1 and back.
  static const Duration period = Duration(milliseconds: 1200);

  /// Each column's height as a share of the padded area, left to right.
  static const List<double> heights = <double>[0.55, 0.8, 0.45, 0.95, 0.65];

  @override
  State<LoadingLook> createState() => _LoadingLookState();
}

final class _LoadingLookState extends State<LoadingLook>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LoadingLook.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      container: true,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      label: widget.label,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LoadingPainter(
          theme: widget.theme,
          pulse: still ? null : _controller,
        ),
      ),
    );
  }
}

final class _LoadingPainter extends CustomPainter {
  _LoadingPainter({required this.theme, required this.pulse})
    : super(repaint: pulse);

  final ChartTheme theme;

  /// The pulse's progress through one period; `null` paints at opacity 1.
  final Animation<double>? pulse;

  double get _opacity {
    final Animation<double>? p = pulse;
    if (p == null) {
      return 1;
    }
    // 0.4 at the start of the period, 1 at its middle.
    return 0.7 - 0.3 * math.cos(2 * math.pi * p.value);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _color(theme.background),
    );
    final double pad = theme.spacing.padding;
    final double width = size.width - 2 * pad;
    final double height = size.height - 2 * pad;
    if (width <= 0 || height <= 0) {
      return;
    }
    final Paint fill = Paint()
      ..color = _color(theme.gridLine).withValues(alpha: _opacity);
    final int n = LoadingLook.heights.length;
    final double slot = width / n;
    final double bar = slot * 0.6;
    for (int i = 0; i < n; i++) {
      final double h = height * LoadingLook.heights[i];
      canvas.drawRect(
        Rect.fromLTWH(
          pad + i * slot + (slot - bar) / 2,
          pad + height - h,
          bar,
          h,
        ),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_LoadingPainter oldDelegate) =>
      theme != oldDelegate.theme || pulse != oldDelegate.pulse;
}

/// The empty and error looks: the theme's background, an optional [title]
/// at the top in the title style, and [message] centred in what is left in
/// the axis label style, drawn with [measurer]. A screen reader reads the
/// title and the message.
final class MessageLook extends StatelessWidget {
  /// Creates a look of [message] under [title] in [theme], drawn with
  /// [measurer].
  const MessageLook({
    super.key,
    required this.theme,
    required this.measurer,
    required this.message,
    this.title,
  });

  /// The theme whose background and text styles it draws.
  final ChartTheme theme;

  /// The measurer whose painters draw the text.
  final FlutterTextMeasurer measurer;

  /// The centred text.
  final String message;

  /// The text above it, or `null` for none.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final String? t = title;
    return Semantics(
      container: true,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      label: t == null ? message : '$t\n$message',
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _MessagePainter(
            theme: theme,
            measurer: measurer,
            message: message,
            title: t,
          ),
        ),
      ),
    );
  }
}

final class _MessagePainter extends CustomPainter {
  _MessagePainter({
    required this.theme,
    required this.measurer,
    required this.message,
    required this.title,
  });

  final ChartTheme theme;
  final FlutterTextMeasurer measurer;
  final String message;
  final String? title;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _color(theme.background),
    );
    final double pad = theme.spacing.padding;
    double top = pad;
    final String? t = title;
    if (t != null) {
      final TextPainter p = measurer.textPainter(t, theme.titleText);
      p.paint(canvas, Offset((size.width - p.width) / 2, top));
      top += p.height + theme.spacing.titleGap;
    }
    final TextPainter p = measurer.textPainter(message, theme.axisLabels);
    final double rest = size.height - pad - top;
    p.paint(
      canvas,
      Offset((size.width - p.width) / 2, top + (rest - p.height) / 2),
    );
  }

  @override
  bool shouldRepaint(_MessagePainter oldDelegate) =>
      theme != oldDelegate.theme ||
      !identical(measurer, oldDelegate.measurer) ||
      message != oldDelegate.message ||
      title != oldDelegate.title;
}
