# Changelog

## Unreleased

- J4: painting of pies, donuts, sparklines, scatter and combination charts,
  smooth lines and translucent areas; the loading and animation of arcs and
  opacity; the keyboard (arrows, Home, End) and a screen reader node per
  category, slice or scatter point (`JetChartStrings.maxPointNodes`).
- J4: `docs/app-themes.md`, the gallery app's J4 charts and the Excel
  gallery's, and benchmark cases for a 10,000-point scatter chart and a pie of
  60 slices.
- J4 (for Monépro): `JetChart.tooltipLines` (`JetChartTooltipLines`), the
  app's own lines under a tooltip's rows, in the box and the screen reader
  nodes.

## 0.1.0-dev.1

- J3: the package, in the repository's workspace (decision 0016).
- J3: `FlutterTextMeasurer`, a `TextMeasurer` that measures with a cached
  `TextPainter` and returns that painter for drawing.
- J3: `paintChartPrimitives`, `ChartLayoutPainter` and the widget `JetChart`
  with its state builders and `JetChartStrings` (en, tr, de), screen reader
  semantics, hover and touch tooltips (`JetChartHit`, `onHover`, `onTap`),
  animation of marks on a data change, and reduced motion.
- J3: golden images (macOS), the measurer fuzz, a layout and paint benchmark,
  and the gallery app with the Excel gallery workbook writer.
