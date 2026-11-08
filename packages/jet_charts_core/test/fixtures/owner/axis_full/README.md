# Full axis oracle

The second Excel oracle of axis scaling (milestone J2). The first, in `../axis/`,
found Excel's automatic minimum and maximum to depend on the data only and the
major unit also on the axis length. This one measures that length: what Excel
for Mac chooses for the value axis, with the plot area's box and the category
labels' spacing, for column, bar, line and area charts of every grouping at
chosen widths, heights and fonts. Only the owner's run counts as a result. The
steps, in Turkish, are in `TALIMATLAR.md`.

Files here:

- `cases.json`: the case list, version 2 (format below). If it changes after a
  run, the regions are run again.
- `manifest.json`: one entry per region the owner ran, in the format of
  `../axis/README.md`; `[]` until the first run. Its `csv` is
  `axis_oracle_full.<region>.csv`.
- `axis_oracle_full.<region>.csv`: what Excel reported in a region, committed
  exactly as the script wrote it.
- `chart_defaults.xlsx`: Excel's default column and line charts, saved unedited,
  which settle the theme values listed in `docs/excel-checks.md` (required in
  this run; `TALIMATLAR.md`, step 9).

Never edit a committed CSV, manifest entry or `chart_defaults.xlsx` without the
owner, and never write a row by hand: no oracle value is ever invented.

## The workbook

```bash
dart run packages/jet_charts_core/tool/write_axis_oracle.dart --full build/axis_oracle_full
```

writes `axis_oracle_full.xlsx`, with the writer in `tool/src/axis_oracle_full.dart`
(a part of `tool/src/axis_oracle.dart`): a sheet per group, named `length`,
`width`, `bar`, `minmax`, `grouping`, `fixed` and `labels`, each case's data in a
block of rows (its labels in column A when it has them, a series per column from
B, a blank as an empty cell), and a chart per case, named by its case id, stacked
to the right of the data. A chart is the case's kind (`c:barChart` with
`c:barDir` `col` or `bar`, `c:lineChart`, `c:areaChart`) and grouping (a line or
area chart's `clustered` is written `standard`; a stacked bar chart has
`c:overlap` 100), one `c:ser` per series with a numeric cache (a blank is a
missing point), the category labels as a string cache when the case has them,
and the case's width and height. Only a case's fixed values fix the scale
(`c:min`, `c:max`, `c:majorUnit`). Its font is `Aptos Narrow` at the case's
size. It has no title and no legend, and the file no theme part, as in the first
oracle. The Open XML SDK reports no error on it.

## `cases.json`

```json
{
  "version": 2,
  "cases": [
    {"id": "L05-w360-h60-f10", "kind": "column", "grouping": "clustered",
     "series": [["12", "23"]], "width": 360, "height": 60, "font": 10}
  ]
}
```

- `id`: `<group><nn>-w<width>-h<height>-f<font>`; its sizes must be the case's.
- `kind`: `column`, `bar`, `line` or `area`.
- `grouping`: `clustered`, `stacked` or `percentStacked`.
- `series`: one or two lists of numbers as text, of one length; `""` is a blank.
- `categories`, optional: a text label per value.
- `width`, `height`, `font`: points.
- `fixedMin`, `fixedMax`, `fixedMajor`, optional: JSON numbers, the value axis'
  own settings.

The groups, 239 cases in all:

| Group | Cases | What it asks |
|---|---|---|
| L | 94 | The unit against length: column charts of the sets `L05` to `L10` (by `autoValueScale` at 10 intervals, 5 to 10 intervals; `test/tool/axis_oracle_test.dart` pins it), 360 pt wide at heights 60 to 275, `L10` at 400 and 800, and `L06` to `L10` at heights 100 and 150 with fonts 8 and 18. |
| W | 20 | Width: the first oracle's `d05` and `d06` at heights 150 and 300 and widths 120 to 720. |
| B | 80 | A horizontal value axis: the L sets as bar charts, 300 pt high at widths 80 to 600, and `L06` to `L10` at widths 150 and 300 with fonts 8 and 18. |
| M | 19 | The automatic minimum and maximum: data near the one-sixth rule, single, equal, blank, wide and mixed-sign values, two series, and line and area charts. |
| G | 12 | Stacked and percent stacked, with and without negatives, as column, bar and area. |
| F | 5 | Fixed bounds and unit, one below the data and one with the minimum equal to the maximum. |
| C | 9 | Category labels of 3, 12 and 30 characters at widths 180, 360 and 720. |

M, G and F are 360 by 300 pt at font 10; C is 300 pt high at font 10.

## The CSV

`tool/axis_oracle/run_excel.applescript <workbook> <csv> full` opens the workbook
read-only, reads every chart and closes without saving. Where Excel opens nothing
through its dictionary, the script opens the file with `open -a`, which cannot
ask for read-only, and waits for it by name; closing without saving keeps the
file unchanged. The file is
`axis_oracle_full.<region>.csv`, UTF-8, one row per chart:

```
case,width,height,font,min,max,major,plotLeft,plotTop,plotWidth,plotHeight,labelSpacing
```

- `case`: the chart object's name.
- `width`, `height`: the chart object's size as Excel reports it; `font`, the
  size Excel reports for the value axis' tick labels. A row is valid only if
  Excel took them: `width` and `height` within 1 pt of the case's, `font` exactly
  the case's.
- `min`, `max`, `major`: the value axis' `minimum scale`, `maximum scale` and
  `major unit` (for a bar chart too: it is still Excel's `value axis`). `max`
  must be above `min`, except that it may equal it where the case fixes both to
  one value (`F05`).
- `plotLeft`, `plotTop`, `plotWidth`, `plotHeight`: the plot area's `inside
  left`, `inside top`, `inside width` and `inside height`, in points from the
  chart's edge. They must be numbers, of no negative size, and the box may reach
  at most 1 pt outside the chart.
- `labelSpacing`: the category axis' `tick label spacing`, a positive whole
  number (an integral real such as `2.0` is written `2`); empty when the chart
  has no category labels (its series formula names none). A chart with labels
  must have it: where Excel does not give a whole number, the script counts the
  chart among its failures and writes no row.

Numbers are written as in the first oracle (`.` whatever the region, exponent
forms accepted). Rows are matched to cases by `case`. A chart Excel could not
answer for has no row: the script names it at the end and exits 1.

## How results are confirmed

The owner compares three charts on screen with their rows (`TALIMATLAR.md`, step
4): `L07-w360-h80-f10`, `B07-w100-h300-f10` (a bar chart, whose value axis runs
across) and `C03-w180-h300-f10`. A mismatch means the run is not a result.

`test/axis_oracle_test.dart`, in the gate, checks each region with an entry: its
CSV exists and has no problems (`readAxisFullCsv`). A region without an entry
prints `axis oracle (full): <region> unverified` and passes.

`tool/analyze_axis_oracle.dart --full [folder]` prints, per region and group:
for L and B, per set and font, the scale at each run of plot lengths (plot
height for columns, plot width for bars), so the length at which the unit
coarsens shows; for W whether width changed anything; for M, G and F Excel's
`min`, `max` and `major` beside `autoValueScale`'s at Excel's own plot length
through `provisionalMaxIntervals`, labelled provisional; for C the label spacing
per width.
