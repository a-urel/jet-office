# 0017 — Every Excel chart kind is covered in the end

**Status:** Accepted — 2026-11-10

Supersedes the "Non-goals (for now)" list of chart kinds in the jet_charts
design (`docs/superpowers/specs/2026-11-04-jet-charts-design.md`, §2) and adds
to [`0014`](0014-chart-phase-and-drawingml-layer.md), which set up the chart
phase. Milestones J4 and J5 keep their scope and order.

## Context

The design lists 3D charts, the Office 2016 `cx:` kinds (waterfall, treemap,
histogram, funnel), trendlines, error bars, stock and radar charts as non-goals
or "later, on demand". Bubble, surface, box and whisker, Pareto, sunburst and
map charts are not named at all. A file with one of them is kept byte for byte
by `jet_office` and drawn as a placeholder by `jet_charts`.

The owner decided on 2026-11-10: no chart kind may stay unnamed. In the end
every kind is covered. The kinds Monépro uses now come first.

## Decision

**jet_charts and jet_office aim to cover every chart kind Excel offers, on
screen and in files. Monépro's kinds come first: J4 (pie, donut, sparkline,
scatter, combination, secondary axis, accessibility) and J5 (Monépro moves to
`JetChart`) keep their scope and run before any kind below.**

The remaining kinds, with a rough size estimate (one unit ≈ one J milestone):

| Group | Kinds | Size |
|---|---|---|
| On existing layouts | bubble, stock (high-low-close, open-high-low-close), waterfall, funnel | small |
| New layout or Excel maths | radar, trendlines, error bars, histogram, Pareto, box and whisker, surface as 2D contour | medium |
| New file format | the `cx:` chart part (chartex) in `jet_office`'s DrawingML layer, as C1 did for `c:chartSpace` | large |
| Undocumented Excel layout | treemap, sunburst | large |
| 3D | 3D column, bar, line, area, pie, surface | large, about two milestones |
| Geographic data | map chart | largest; its data source and licence are the owner's decision |

Proposed order after J5: the small group with radar, trendlines and error bars;
then the `cx:` layer with histogram, Pareto, box and whisker, treemap and
sunburst; then 3D; then the map chart. Each group becomes a milestone of its
own with its own plan. Where Excel's behaviour decides the look, the owner's
Excel for Mac check is the oracle, as for every chart.

## Consequences

- **The anti-goals still hold.** 3D and the dense kinds must not overlap
  labels on screen. Where Excel's own 3D drawing overlaps them, the difference
  is recorded as deliberate, as the design already requires.
- **The model must leave room.** J4 and later milestones must not take design
  choices that block a later kind. That means keeping room for a third axis or
  depth, a polar layout, and `cx:` data.
- **Placeholders stay until a kind is done.** An unsupported kind read from a
  file is still kept byte for byte and drawn as a placeholder.
- **A future record adds the milestone names.** Each group's milestone names
  and plans are added later, when that group starts.
