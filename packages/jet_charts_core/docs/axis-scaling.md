# Axis scaling

Excel's automatic minimum, maximum and major unit are not documented and are not
in the file. Excel recomputes them, and they can be read from it by script. This
page says what is known of them; the chart phase's record is
[decision 0014](../../../docs/decisions/0014-chart-phase-and-drawingml-layer.md).

## The question

Does Excel's automatic value axis depend on the chart's size and font, or only on
the data? If it does, size and font are inputs to scaling, and scale and layout
are one step. J2's scale design starts from the answer.

## The oracle

Excel for Mac is the oracle, and only the owner's run counts as a result, as for
the number format engine. `test/fixtures/owner/axis/` holds the case list and the results; its
`README.md` describes the files, and `TALIMATLAR.md` is the owner's steps.

From the repository root:

```bash
dart run packages/jet_charts_core/tool/write_axis_oracle.dart build/axis_oracle
osascript packages/jet_charts_core/tool/axis_oracle/run_excel.applescript \
  build/axis_oracle/axis_oracle.xlsx build/axis_oracle/axis_oracle.tr-TR.csv
dart run packages/jet_charts_core/tool/analyze_axis_oracle.dart
```

Twelve data sets, each charted at heights 150, 300 and 600 pt at font 10, and at
height 300 with fonts 8 and 18: 60 clustered column charts of one series, 360 pt
wide. The script records the height and font Excel reports, not those the case
asked for, so a result counts only if Excel took them. One region's run answers
the question. `test/axis_oracle_test.dart` checks the committed results.

## Findings

The owner's run of 2026-11-08 (`tr-TR`, Excel for Mac 16.114.4; the manifest
entry has the details) answers the question. The owner compared the three
charts of `TALIMATLAR.md`, step 4, on screen with their rows, and they matched.
`tool/analyze_axis_oracle.dart` prints:

```
answer: across height: yes (tr-TR d05, d06); across font: no
```

- **The minimum and maximum depend on the data only.** No data set changed
  them across height or font.
- **The major unit can depend on the height.** At 150 pt, two sets took a
  coarser unit than at 300 and 600 pt: `d05` (`0, 0, 0`; 0.2 against 0.1, on
  0 to 1) and `d06` (`-5, 3`; 2 against 1, on -6 to 4). The other ten sets kept
  one unit at every height.
- **The font did not matter.** Fonts 8, 10 and 18 at 300 pt gave the same axis
  for every set.

So the major unit is an input of layout, not of the data alone: J2 chooses it
with the plot area's height known, and scale and layout are one step for it.
Neither the width nor a font change was tested, so this run says nothing of
them; the other two regions stay `unverified`.

### The full run

The owner's full run of 2026-11-08 (`tr-TR`, Excel for Mac 16.114.4, 239
charts, `test/fixtures/owner/axis_full/`; the manifest entry has the details)
measured the plot area's inside box beside each axis. The owner compared the
three charts of its `TALIMATLAR.md`, step 4, with their rows, and they matched.
`tool/analyze_axis_oracle.dart --full` prints the runs below; every row but
one is met by the rule (`test/scale/axis_parity_test.dart`).

- **The major unit depends on the plot length and the tick labels' font
  size.** Through `autoValueScale`, the most intervals Excel takes are
  `excelMaxIntervals` (`lib/src/scale/value_scale.dart`), rounded down and
  kept between 1 and 10:
  - vertical value axis (column, line, area): `(plot height - font) /
    (font + 2)`: labels one font size tall, 2 pt apart, fit the axis. On
    `L10` at font 10 the unit goes 50, 20, 10, 5 as the plot grows from 24 to
    144 pt; at a chart 100 pt high (plots of 68 and 44 pt) font 8 holds 5
    intervals and font 18 one.
  - horizontal value axis (bar): `(plot width + 2 font) / (3.9 font)`. A bar
    chart needs a plot about three times as long as a column chart for the
    same unit (`B10` at font 10 reaches 5 only at 563 pt). The labels' width
    does not enter: the percent bars `G08` and `G11`, with labels twice as
    wide, fit the same rule.
  - never more than 10: a 264 pt column plot that could hold 20 took 10.

  The constants are the simplest that meet every L, B, W, M, G and F row; the
  data allow the gap from 1.96 to 2.32 pt, and the bar factors from 3.83 to
  3.93 and 1.85 to 2.38.
- **Width does not matter.** `W05` and `W06` at 150 and 300 pt high kept one
  scale at every width from 120 to 720 pt.
- **The minimum and maximum follow Task 3's rule** for every M row (the
  one-sixth rule, single, equal, blank, wide and mixed-sign values, two
  series, line and area) and for every grouping (G: stacked and percent
  stacked, with negatives, as column, bar and area).
- **Fixed bounds and unit** (F) follow the rule, with one exception: `F05`
  fixes the minimum and the maximum both to 5, and Excel keeps an axis of no
  length (5 to 5 by 0.5). The rule ignores the fixed maximum there and draws
  5 to 11 by 1; `docs/parity.md` lists it.
- **Category labels.** Excel's tick label spacing was 2 at 180 pt wide and 1
  at 360 and 720 pt for labels of 3, 12 and 30 characters (`C`), never more
  than 2; layout now skips at most every second level label before it turns
  them.

Still unverified: the other two regions (`en-US`, `de-DE`), whose number
format could change label widths though not, by this rule, the unit; fonts
other than Aptos Narrow; bar charts above 10 intervals (the run bounds them by
12 only); and the plot box's own margins, which this rule takes as given.
