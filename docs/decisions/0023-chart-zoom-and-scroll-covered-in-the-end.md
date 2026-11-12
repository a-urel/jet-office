# 0023 — Zooming and scrolling a chart are covered in the end

**Status:** Accepted — 2026-11-12

Adds to [`0014`](0014-chart-phase-and-drawingml-layer.md) and
[`0017`](0017-every-excel-chart-kind-eventually.md). Neither names
zooming or scrolling. Nothing in either record changes.

## Context

A chart of the jet_charts family is always laid out to fit the size it is
given. `layoutChart` makes the content fit:

- category labels wrap, turn, skip or are cut with an ellipsis;
- the legend shrinks or moves;
- what still does not fit goes in the order of `DegradeStep`.

Nothing scrolls, pans or zooms. Excel's charts do not either. The design's
second anti-goal is a clear difference in look or behaviour between the app
and Office. It also requires one layout for screen, PDF and files.

On 2026-11-12 the owner asked whether charts are scrollable and whether they
should be. The case where it would help is a long time series on a narrow
screen, such as a year of daily sales on a phone.

Two ways were named:

- **Without the library:** today an app can put a chart of a fixed width per
  category in a horizontal scroll view. The axes scroll with the plot.
- **In the library:** a visible range (a viewport) with pan and zoom, the
  axes staying in place. It is screen behaviour with no Office counterpart,
  like the tooltip and hover. Files and PDF still show all the data.

The owner decided: not needed for now; zooming and scrolling are covered in
the future.

## Decision

**The jet_charts family will in the end let a chart on screen zoom and
scroll.** Until then every chart fits its size, as today.

## What this does not decide

These wait for a concrete need in Monépro, and for the owner:

- **The level:**
  - horizontal scrolling of the category axis;
  - zoom by pinch, wheel or a range control;
  - pan on the value axis;
  - which kinds take part (pie and donut likely not).
- **The model:** a visible range in `jet_charts_core`, and how the value axis
  scales to the visible data or to all of it (Excel's rule, `autoValueScale`,
  is defined for the data shown).
- **The interaction** in `jet_charts_flutter`: touch, mouse, keyboard and
  accessibility, and how it meets the tooltip and hit testing.
- **The order and the milestone name.**

## Consequences

- A file or PDF export keeps showing the whole chart. Zooming and scrolling
  stay screen-only and never reach `c:chartSpace`.
- Until it is built, the layout's fitting rules and `DegradeStep` stay as
  they are, and an app that needs scrolling wraps the chart itself.
- When it is planned, it gets its own record that settles the open questions
  above.
