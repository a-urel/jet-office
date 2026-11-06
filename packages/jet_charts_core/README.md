# jet_charts_core

The chart core of the jet_ packages, in pure Dart: a chart model, a theme, axis
scales, layout and drawing primitives. It has no Flutter and no `dart:io`, and
runs on the web, desktop, mobile and server alike. It depends on `jet_core`
only.

It is the first part of a chart family (`docs/superpowers/specs/` holds the
design; decision 0014 records the phase). A Flutter renderer, a PDF painter and
the chart parts of `jet_office` come later and each draws or writes what this
package describes. Today the package is set up and exports nothing.

Not published to pub.dev. Use it as a git dependency:

```yaml
dependencies:
  jet_charts_core:
    git:
      url: https://github.com/a-urel/jet-office.git
      path: packages/jet_charts_core
```

See `AGENTS.md` for the rules of the package and
`docs/decisions/0014-chart-phase-and-drawingml-layer.md` in the repository
root for why it exists.
