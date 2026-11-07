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

`jet_charts_flutter` and `jet_print`'s painter do not exist yet, and
`jet_office` does not use this package yet.

## Status

Milestone J1 is done. The package exports the chart model, the theme (with the
Office theme built in), the drawing primitives with their geometry, and
the text measurer interface with a fixed-width one for tests.

Nothing draws yet: axis scales and layout are J2. The first Excel axis oracle
(`test/fixtures/owner/axis/`) is committed and waits on the owner's run in
Excel for Mac; `docs/axis-scaling.md` holds the question.

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
