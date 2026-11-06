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

Pending: no run has been recorded.
