# jet_charts_core

The chart core of the jet_ packages, in pure Dart. It has no Flutter and no
`dart:io`, and runs on the web, desktop, mobile and server alike. It depends on
`jet_core` only.

## The family

`jet_charts_core` is the first part of a chart family. It describes a chart and
what to draw for it; a backend draws that, and `jet_office` writes and reads it
as a chart in XLSX and DOCX. Decision 0014
(`docs/decisions/0014-chart-phase-and-drawingml-layer.md` in the repository
root) records why. The packages share one repository, a pub workspace (decision
0013):

| Package | Holds | Depends on |
|---|---|---|
| `jet_core` | number format engine, locale, what else two families share | pure Dart only |
| `jet_charts_core` | model, theme, scales, layout, primitives | `jet_core` |
| `jet_charts_flutter` | `CustomPainter` renderer, widget, text measurer, interaction | core, Flutter |
| `jet_office` (repository root) | `c:chartSpace` read and write, host adapters for XLSX, DOCX | `jet_core`, `jet_charts_core` (from C1, decision 0014) |
| `jet_print` (later) | PDF painter, its own measurer | core |

`jet_charts_flutter` is the Flutter backend and `jet_office` reads and writes
the model as a chart part (milestone C1); `jet_print`'s painter does not exist
yet.

## Status

Milestone J4 is done, its values checked against Excel for Mac (E1 and E2,
`docs/excel-checks.md`; the secondary axis and a numeric scatter not yet): pie, donut, sparkline,
scatter and combination charts, a series' own kind, the secondary value axis,
smooth lines, point colours, translucent areas with an edge line, percent data
labels with `minShare`, a donut's `holeSizePercent` and `centerText`, and
`ChartTheme.fromColors` for an app's own light and dark themes
(`packages/jet_charts_flutter/docs/app-themes.md`). The J2 notes below stay
true.

Milestone J2 is done. The package exports the chart model, the theme (with the
Office theme built in), the drawing primitives with their geometry, and the
text measurer interface with a fixed-width one for tests (J1), and now:

- `autoValueScale`, the value axis' minimum, maximum and major unit as Excel
  for Mac chooses them, fitted on the owner's Excel runs
  (`docs/axis-scaling.md`);
- `layoutChart`, which turns a chart, a theme, a size and a text measurer into
  drawing primitives for column, bar, line and area charts of every grouping,
  with axes, grid, titles, legend, data labels and category labels that turn,
  skip or cut to fit;
- `findOverlaps`, which checks a layout for texts that collide.

`docs/parity.md` compares the layout with Excel and lists every difference.
Nothing draws yet: the Flutter renderer is J3, in `jet_charts_flutter`.

Not published to pub.dev. Use it as a git dependency:

```yaml
dependencies:
  jet_charts_core:
    git:
      url: https://github.com/a-urel/jet-office.git
      path: packages/jet_charts_core
```

See `AGENTS.md` for the rules of the package.

Apache License 2.0, see [`LICENSE`](LICENSE), as the rest of this repository.
