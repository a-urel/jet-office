# Axis oracle

What Excel for Mac chooses for an automatic value axis: its minimum, maximum and
major unit, for twelve data sets at different chart heights and font sizes. It
answers the question of `docs/axis-scaling.md`: does Excel's automatic scale
depend on the chart's size and font? Only the owner runs Excel. The steps, in
Turkish, are in `TALIMATLAR.md`.

Files here:

- `cases.json`: the case list (format below). If it changes after a run, the
  regions are run again.
- `manifest.json`: one entry per region the owner ran (format below); `[]` until
  the first run.
- `axis_oracle.<region>.csv`: what Excel reported in a region, committed exactly
  as the script wrote it.
- `chart_defaults.xlsx`, optional: Excel's default column and line charts, saved
  unedited, which settle the theme values listed in `docs/excel-checks.md`.

Never edit a committed CSV, manifest entry or `chart_defaults.xlsx` without the
owner, and never write a row by hand: no oracle value is ever invented.

## The workbook

```bash
dart run packages/jet_charts_core/tool/write_axis_oracle.dart build/axis_oracle
```

writes `axis_oracle.xlsx`, with the writer in `tool/src/axis_oracle.dart`: a
sheet per data set (`d01` to `d12`), labels in column A and values in column B,
and five clustered column charts of one series, 360 pt wide, stacked to the right
of the data. A chart is named by its case id. Nothing in a chart fixes the scale:
no `c:min`, `c:max` or `c:majorUnit`. Its font is `Aptos Narrow` at the case's
size, set on the chart space. The file has no theme part, so its look says
nothing about Excel's defaults; LibreOffice draws its bars invisible.

## `cases.json`

```json
{
  "version": 1,
  "chartWidth": 360,
  "sets": [{"id": "d01", "values": ["1", "2", "3"]}],
  "sizes": [{"height": 150, "font": 10}]
}
```

- `chartWidth`: every chart's width in points.
- `sets`: `id` is `d` and two digits, the sheet's name; `values` are numbers as
  text, written unchanged to the sheet and the chart's cache.
- `sizes`: heights and font sizes in points. Every set is charted at every size.

A case id is `d<nn>-h<height>-f<font>`, such as `d01-h150-f10`: twelve sets at
five sizes are 60 cases. Heights 150, 300 and 600 at font 10 compare height;
fonts 8, 10 and 18 at height 300 compare font.

## The CSV

`tool/axis_oracle/run_excel.applescript <workbook> <csv>` opens the workbook
read-only, reads every chart and closes without saving. The file is
`axis_oracle.<region>.csv`, UTF-8, one row per chart:

```
case,height,font,min,max,major
```

- `case`: the chart object's name.
- `height`: the height Excel reports for the chart object, not what the case
  asked; likewise `font`, the size Excel reports for the value axis' tick labels.
  A row is valid only if Excel took them: `height` within 1 pt of the case's,
  `font` exactly the case's.
- `min`, `max`, `major`: the value axis' `minimum scale`, `maximum scale` and
  `major unit`.

Numbers use `.` whatever the region and may be in exponent form (`1.0E-7`,
`6.0E+9`), as AppleScript writes them; it keeps about 13 significant digits. A
BOM and CR line ends are accepted. Rows are matched to cases by `case`, never by
position. A chart Excel could not answer for has no row: the script names it at
the end and exits 1, and the check reports the case as missing.

Regions are jet_core's: `en-US`, `de-DE`, `tr-TR`. One region's run answers the
question; the others stay `unverified`.

## `manifest.json`

A list, one object per region run:

```json
[
  {
    "region": "tr-TR",
    "appleLocale": "<what defaults read -g AppleLocale printed>",
    "excelLanguage": "<Excel's language in the run>",
    "excel": "<Excel → About Excel: name, version and build>",
    "macos": "<Apple menu → About This Mac>",
    "confirmedBy": "owner",
    "csv": "axis_oracle.tr-TR.csv",
    "notes": ""
  }
]
```

Every field is required, and no other; all but `notes` must be filled in, and a
`<placeholder>` left in is refused. `confirmedBy` is exactly `owner`. `notes`
holds anything Excel said or did, or `""`.

## How results are confirmed

`test/axis_oracle_test.dart`, in the gate, checks each region with an entry:
its CSV exists and has no problems (a wrong header, a case missing, unknown or
repeated, a field that is no number, `max` not above `min`, `major` not above
zero, a height or font Excel did not take). A region without an entry prints
`axis oracle: <region> unverified` and passes.

`tool/analyze_axis_oracle.dart [folder]` then prints, for each data set, whether
the minimum, maximum or major unit differ across height and across font, and the
answer last; with no results, `no results`. The answer goes in `Findings` of
`docs/axis-scaling.md`.
