/// A `TextMeasurer` that measures with Flutter's `TextPainter`, the one the
/// renderer paints with.
library;

import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:jet_charts_core/jet_charts_core.dart';

/// Measures chart text with a [TextPainter] and keeps the painter for drawing.
///
/// Layout and painting use the same laid-out painter ([textPainter]), so the
/// widths layout reserves are the widths drawn, even when the theme's font is
/// not installed and Flutter falls back to another.
///
/// Painters are cached by text and style. The cache holds at most the
/// constructor's `cacheSize` painters; when it is full the least recently used
/// one leaves it and is disposed. Call [dispose] when the measurer is no longer used.
final class FlutterTextMeasurer implements TextMeasurer {
  /// Creates a measurer that scales text by [textScaler], falls back to the
  /// fonts of [fontFamilyFallback] in order, and caches up to [cacheSize]
  /// painters.
  ///
  /// Throws an [ArgumentError] when [cacheSize] is below one.
  FlutterTextMeasurer({
    this.textScaler = TextScaler.noScaling,
    List<String>? fontFamilyFallback,
    int cacheSize = 2048,
  }) : _fontFamilyFallback = fontFamilyFallback == null
           ? null
           : List<String>.unmodifiable(fontFamilyFallback),
       _cacheSize = cacheSize {
    if (cacheSize < 1) {
      throw ArgumentError.value(cacheSize, 'cacheSize', 'must be at least 1');
    }
  }

  /// How text is scaled for the user's text size setting, such as
  /// `MediaQuery.textScalerOf(context)`.
  final TextScaler textScaler;

  final List<String>? _fontFamilyFallback;
  final int _cacheSize;

  /// The cached painters, least recently used first.
  final LinkedHashMap<_Key, TextPainter> _cache =
      LinkedHashMap<_Key, TextPainter>();

  /// The size [text] takes in [style]: the width and height of
  /// [textPainter]'s painter.
  @override
  ChartSize measure(String text, ChartTextStyle style) {
    final TextPainter painter = textPainter(text, style);
    return ChartSize(painter.width, painter.height);
  }

  /// The laid-out painter that [measure] measures [text] in [style] with.
  ///
  /// It lays out left to right, with each line centred (`TextAlign.center`),
  /// in a [TextStyle] of the style's font family, this measurer's fallback
  /// fonts, the style's size, weight 700 when bold and 400 otherwise, and the
  /// style's colour, scaled by [textScaler]. The same input returns the same
  /// painter while it is cached. The measurer owns it: callers paint with it
  /// and must not change or dispose it.
  TextPainter textPainter(String text, ChartTextStyle style) {
    final _Key key = _Key(text, style);
    final TextPainter? cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontSize: style.size,
          fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
          color: Color(0xFF000000 | style.color.rgb),
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    if (_cache.length >= _cacheSize) {
      final _Key oldest = _cache.keys.first;
      _cache.remove(oldest)!.dispose();
    }
    _cache[key] = painter;
    return painter;
  }

  /// Disposes every cached painter and empties the cache.
  ///
  /// Painters [textPainter] returned before are no longer usable. The
  /// measurer itself still is: it lays out new painters.
  void dispose() {
    for (final TextPainter painter in _cache.values) {
      painter.dispose();
    }
    _cache.clear();
  }
}

/// A cache key: a text and its style.
final class _Key {
  const _Key(this.text, this.style);

  final String text;
  final ChartTextStyle style;

  @override
  bool operator ==(Object other) {
    return other is _Key && text == other.text && style == other.style;
  }

  @override
  int get hashCode => Object.hash(text, style);
}
