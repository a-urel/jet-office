# Changelog

## Unreleased

- C1: `ChartTheme.stackedGapWidthPercent` (150), `barGapWidthPercent` (182),
  `ChartSpacing.barOverlapPercent` (0), `ChartTheme.gapWidthPercentOf` and
  `overlapPercentOf`: Excel's gap width and overlap per bar kind and grouping,
  confirmed by the owner's `chart_reference.xlsx`; the layout uses them, so
  clustered bars and stacked columns and bars are wider than before.
- C1: the Office theme's data labels are `404040` (`tx1` with `lumMod` 0.75
  and `lumOff` 0.25), as Excel writes them.
- J3: the Office theme has the chart border and no value axis line
  (`ChartTheme.border`, `borderWidth`, `valueAxisLine`).
- J3: `ChartElementId`, `ChartElementKind`, `ChartAxisRole` and
  `hitTestLayout`: hit testing of a layout by element id.
- J3: `ChartLayout.categoryBands`.
- J3: `chartTooltipAt`, `chartTooltipFor`, `ChartTooltip`, `ChartTooltipRow`,
  `ChartTooltipStyle` and `ChartTheme.tooltip`.
- J3: `summarizeChart` and `ChartSummary`, the text a screen reader reads.

## 0.1.0-dev.3

- J2: `autoValueScale`, `ValueScale` and `dataExtent`, the value axis as Excel
  for Mac chooses it, fitted on the owner's full axis oracle.
- J2: `layoutChart`, `ChartLayout` and `ChartHiddenLabel`: column, bar, line
  and area charts of every grouping laid out as drawing primitives, with
  titles, legend, data labels, and category labels that turn, skip or cut.
- J2: `findOverlaps`, `ChartOverlap` and `ChartOverlapKind`.
- A layout fuzz test and `tool/fuzz_layout.dart`, golden layouts, an SVG
  gallery (`tool/write_gallery.dart`) and `docs/parity.md`.
- Fixed the dartdoc of `excelMaxIntervals` for a font size of 0 on a vertical
  axis.

## 0.1.0-dev.2

- Set up the package: `jet_core` as the only dependency, architecture
  guards, quality gate.
- J1: the chart model, the theme (with the Office theme), the drawing
  primitives and geometry, and the text measurer, all exported by
  `package:jet_charts_core/jet_charts_core.dart` with explicit `show` lists.
  The first Excel axis oracle is committed; its results await the owner's run.
  Scales and layout follow in J2.
- `ChartData.==` compares `ChartData` of any type argument symmetrically.
