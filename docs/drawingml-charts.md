# DrawingML charts

The DrawingML layer (`lib/src/drawingml/`) writes a `jet_charts_core` `Chart`
as a `c:chartSpace` part the way Excel for Mac writes it, reads such a part
back, and keeps an opened part byte for byte. Decision
[`0014`](decisions/0014-chart-phase-and-drawingml-layer.md) sets the phase;
[`0015`](decisions/0015-drawingml-layer-imports.md) says what the layer may
import. The layer knows neither XLSX nor DOCX. Its types carry the prefix
`Drawing`.

**Status of C1: done** (the owner's Excel check of the fixtures is in
`docs/excel-checks.md`). The owner's reference workbook is committed and
every chart in it but one reads typed ("Excel's reference workbook" below).

**Status of C2: built; the owner's Excel check is open**
(`docs/excel-checks.md`, "C2"). The XLSX host is `XlsxWorkbook`'s
(`docs/xlsx-model.md`, "What C2 adds"); the layer writes and reads the J4
kinds below. Nothing of this layer is exported: `lib/jet_office.dart` exports
the host's `XlsxChart` and `XlsxSheetChart` and re-exports the
`jet_charts_core` types they take, and the `Drawing*` types stay private. C3
is the DOCX host.

## What is in it

- `color.dart`: colours as `c:schemeClr` (with `lumMod` and `lumOff`) or
  `a:srgbClr`; `applyDrawingLuminance`.
- `text.dart`: the `c:txPr` blocks of the title, axes, legend and data labels,
  and rich text (`c:rich`).
- `chart/chart_space.dart`: `DrawingChartSpace`, the typed form (a `Chart`, the
  language, the axis and series ids, the automatic title) and
  `DrawingChartIssue`.
- `chart/chart_writer.dart`: `writeDrawingChartSpace`.
- `chart/chart_reader.dart`: `readDrawingChartSpace`, which always gives a
  view (`Chart`) and gives the typed form only when it can be written again.
- `chart/chart_part.dart`: `DrawingChart`, the part handle (a `PartContent`)
  the hosts hold.
- `chart/chart_values.dart`: number text, Excel date serials, `_xHHHH_`
  escaping.
- `lib/src/xml/xml_equivalence.dart`: `xmlDifference`.

Kinds written: column, bar, line and area, each clustered, stacked or percent
stacked (C1), with smooth lines (J4's field), on one category axis and one
value axis; and since C2 pie, donut, scatter of markers only, combination of
column, line and area groups, and a secondary value axis for a column, line,
area or combination chart. Estimates, not yet checked in Excel (the owner's C2 check,
which holds the E3 steps, decides): the secondary axis, numeric scatter x
values, an area group in a combination, a scatter chart's data labels
without the `c15` leader line extension, a scatter or date x axis without
`c:numFmt`, and a doughnut's data label position (none written).

## Rules

Each rule has the test that holds it.

### Reading and typing

- **A part is offered typed only when writing the typed form gives the part
  again.** "Gives again" is `xmlDifference` equal, not byte equal. The two
  charts of the owner's `chart_defaults.xlsx` read typed.
  `test/drawingml/chart/chart_reader_test.dart` ("Excel's default charts"),
  `test/drawingml/chart/excel_charts_test.dart`.
- **Another producer's part gives a view and no typed form, and its bytes are
  kept.** A `dk1` where Excel writes `tx1`, an extra `c:dispUnits`.
  `chart_reader_test.dart` ("parts that are not typed", "variants of other
  producers"), `chart_part_test.dart` ("opened"). A part without `c16` ids is
  typed, with no series ids, since the writer writes such a series without
  one (`chart_reader_test.dart`, "a part without c16 ids is read and typed,
  with no series ids").
- **An opened part is saved byte for byte until `replace` gives it a new typed
  form.** The bytes are held, not copied. `chart_part_test.dart`.
- **Reading is lazy and never throws.** `chart`, `typed` and `issues` read on
  first use, once. Unreadable bytes give no chart and the issue `unreadable`.
  `chart_part_test.dart`, `chart_reader_test.dart` (the "unreadable input"
  test).
- **The reader never throws, whatever theme it is given.** A theme the
  writer refuses (below) gives a view and no typed form.
  `chart_reader_test.dart` ("a theme the writer refuses gives a view only,
  never a throw").
- **A kind outside the model (a horizontal bar group beside another group,
  a pie beside axes, a scatter group beside a category axis) or a third axis
  (pair) is `unsupportedKind`:** a view with the kind `unsupported`, no typed
  form. `chart_reader_test.dart`.
- **Pies and doughnuts are written and read as Excel writes them (C2).** A
  plot area of one `c:pieChart` or `c:doughnutChart` and no axis reads as
  `pie` or `donut`. The writer writes no axes (the ids' axis fields are
  checked but unused, and a pie reads back with `DrawingChartIds`' defaults),
  `c:varyColors 1`, per slice a `c:dPt` in its point colour or the theme's
  colour of its index, outlined `sliceBorderWidth` wide in the background
  (`lt1` when that is the first light slot, as Excel's style 251 names it;
  `a:noFill` at 0), `c:firstSliceAng 0` and a donut's `holeSizePercent`
  rounded as `c:holeSize`; no series `c:spPr`, so a series' own colour, its
  smoothing, the grouping and the axes are not written. Shown labels are
  each series' with Excel's chart 7 values (a pie's `bestFit`, none for a
  doughnut, an estimate), leader lines in the theme's `leaderLine` at 0.75 pt
  and an empty `c15` extension; the group's repeat their position and flags,
  with `c:showLeaderLines 1` always. The reader gives a slice in the theme's
  colour of its index back as automatic, reads `showVal` and `showPercent`,
  and a hole size that is missing, outside 10 to 90 or not a number (that last
  a `badNumber`) as 75, so such a part is untyped. Charts 1, 2, 3 and 7 of
  `chart_reference_j4.xlsx` read typed and write their parts again.
  `excel_reference_j4_test.dart`, `chart_writer_test.dart` and
  `chart_reader_test.dart` ("pies and doughnuts").
- **Scatter charts of markers only are written and read as Excel writes them
  (C2).** A plot area of one `c:scatterChart` on two `c:valAx` reads as
  `scatter`, the axis of the group's first `c:axId` (else the first axis) as
  the category (x) axis. The writer writes Excel's chart 4 of
  `chart_reference_j4.xlsx`: `c:scatterStyle lineMarker`,
  `c:varyColors 0`, each series' line `a:noFill` 3 pt (`38100`, round cap),
  a circle marker of `markerSize` in its colour whatever `lineMarkers` says,
  its categories as `c:xVal` and its values as `c:yVal`, and `c:smooth 0`
  (a series' `smooth` draws nothing in a scatter chart and is not written);
  the x axis at the bottom with the ids' `categoryAxis` and the category
  axis' options (grid lines when `categoryAxis.gridLines`; no `c:numFmt`
  unless it has a format code), the y axis at the left with `valueAxis`,
  both with no tick marks, labels `nextTo` (though a value is negative),
  the theme's `scatterAxisLine`, crossing at `autoZero` and `midCat`. The
  reader takes a series' colour from its marker's fill. Excel's chart took
  text x values (`c:strRef`); numeric x values (`c:xVal/c:numRef`, as
  `_writeCategories` writes numbers and dates) are an estimate, not checked
  in Excel: E3 decides (`packages/jet_charts_core/docs/excel-checks.md`,
  "E3"; its steps are part of the owner's C2 check).
  So are a scatter chart's data labels (a line's, without the `c15` leader
  line extension the Open XML SDK refuses there), point colours (a line's
  markers, the line without fill), an x axis' number format and axis lines
  in a theme without `scatterAxisLine` (any chart's). Chart 4 reads typed
  and writes its part again. `excel_reference_j4_test.dart`,
  `chart_writer_test.dart` and `chart_reader_test.dart` ("scatter charts").
- **Combination charts and the secondary value axis are written and read
  (C2).** The writer writes a combination as a group per drawn kind (the
  series' own: column, line or area; no kind is a column; a pie, donut,
  scatter, bar or other kind there is an `ArgumentError` naming
  `chart.series[i].kind`), in the layout's order of areas, columns, then
  lines, each group's series in series order. Excel's chart 5 of
  `chart_reference_j4.xlsx` ("Clustered Column - Line", one axis) is the
  template: columns `c:gapWidth 150` and no overlap
  (`combinationGapWidthPercent`), a line group `standard` whatever the
  grouping, its lines 2.25 pt without markers (`combinationLineMarkers`
  off), and no `c:crosses` on the primary axes. In a column, line, area or
  combination chart a series bound to the secondary axis, while some series
  is bound to the primary one, goes in a group of its own after every
  primary group, on a second pair of the ids' `secondaryCategoryAxis` and
  `secondaryValueAxis`, written after the primary pair: a `c:valAx` on the
  right (`axPos r`, `crosses max`, the options of `secondaryValueAxis`, no
  grid lines unless it asks, `0%` only when a percent stacked group is on
  it), then a deleted `c:catAx` (`delete 1`, ticks `out`). A
  `secondaryValueAxis` with no series on it, and a binding when every series
  is secondary, write no second pair (the layout shows none); a bar, pie,
  donut or scatter chart's secondary axis is an `ArgumentError`. **E3
  decides:** the secondary axes and a combination with an area group are
  estimates from the gallery workbook (`excel_gallery.dart`, which the owner
  opened in Excel in E2), not checked in Excel. The reader reads several
  bar, line and area groups whose axis ids name one or two pairs, the first
  group's the primary one: groups of one kind as that kind, of several as a
  combination whose series carry their group's kind (so a series of no kind
  reads back as a column), a secondary group's series bound to the
  secondary axis, the series in their `c:order`, and a secondary axis of
  default options as `null`. Chart 5 reads typed but for its category
  labels: Excel writes `nextTo` beside the value -4, the writer `low` (the
  owner's choice, below), so Excel's own part is untyped and the part with
  `low` reads typed and writes again. `excel_reference_j4_test.dart`,
  `chart_writer_test.dart` and `chart_reader_test.dart` ("combination charts
  and the secondary axis").
- **The typed form carries the language, the axis ids (four with a
  secondary axis), each series' `c16:uniqueId` and Excel's automatic
  title.** Anything else Excel writes is
  fixed by the writer; a part that differs is not typed.
  `chart_reader_test.dart` ("the column chart keeps its ids").
- **Scheme names.** `dark1`, `light1`, `dark2`, `light2` are written `tx1`,
  `bg1`, `tx2`, `bg2`; `dk1`, `lt1`, `dk2`, `lt2` are read as the same slots
  (and the part is then not typed). One exception: a pie's or doughnut's
  slice border in `light1` is written `lt1`, as Excel's style 251 names it,
  and such a part reads typed. `test/drawingml/color_test.dart`,
  `chart_writer_test.dart` ("a pie: varied colours, a slice point per value
  outlined in lt1, ...").
- **Leader lines.** A pie's or doughnut's shown labels have leader lines in
  the theme's `ChartTheme.leaderLine`, as Excel draws them; a column, bar,
  line or area series' labels write Excel's fixed `A6A6A6` (`tx1` at
  `lumMod` 35000 and `lumOff` 65000) whatever the theme. Intended: those
  charts write `c:showLeaderLines 0`, so the line is never drawn and the
  part keeps Excel's own value (charts 20 and 21 of `chart_reference.xlsx`).
  `chart_writer_test.dart`.
- **The text font follows the colours.** With `ChartExportColors.fileTheme` it
  is the theme's minor font (`+mn-lt`, `+mn-ea`, `+mn-cs`); with `fixed` it is
  `latin typeface`. `test/drawingml/text_test.dart`, `chart_writer_test.dart`
  ("colours").
- **`lumMod` and `lumOff` are fractions on a `ChartColor`.** Other colour
  modifiers read as no colour. `color_test.dart`, `jet_charts_core`'s
  `test/theme/chart_color_test.dart`. A series colour the reader cannot
  express (a modifier other than `alpha`, a `lumMod` above 100000) therefore
  reads as `null`, and the view draws the theme's palette colour for that
  series in its place; the part's bytes keep the real colour.

### Equality

- **`xmlDifference` ignores the declaration, namespace declarations and
  prefixes, comments and whitespace between elements.** Text and attribute
  values are compared exactly. `test/xml/xml_equivalence_test.dart`.
- **Whitespace that is a leaf element's whole content is significant.** An
  `a:t` holding one space is a real title. A leaf of indentation in a
  hand-written part therefore blocks typing; its bytes are still kept.
  `xml_equivalence_test.dart` ("whitespace that is the whole content of a
  leaf is significant").
- **Malformed input and nesting beyond the reader's limit are a difference,
  never a throw.** `xml_equivalence_test.dart`.

### Untrusted input (decision 0007)

- **One point budget per part.** The caches of a part (names, categories,
  values) share `1,048,576` entries plus the part's byte length, counting the
  points a cache declares and lacks. A cache over the budget is cut after its
  last present point and reports `badNumber`; a legitimate sparse chart with
  more than a million declared empty points loses its trailing empty points in
  the view (its bytes are kept). `chart_reader_test.dart` ("declared point
  counts share one budget per part", "a point count beyond the limit is
  capped").
- **A number that does not parse, `NaN` and infinity are empty points** and
  report `badNumber`. A long run of digits is read in linear time.
  `chart_reader_test.dart`.
- **The fuzz.** `chart_fuzz_test.dart` mutates the corpus (the Excel charts,
  the seven of `chart_reference_j4.xlsx` and every C1 and `c2_kinds` chart;
  seeds 1 to 4, 100 cases each, the same cases on the VM and in Chrome, proved
  by a digest) and requires: the reader throws nothing, a typed form writes a
  part that reads typed again, an opened part encodes its bytes. Longer runs:
  `dart run tool/fuzz_chart.dart --seeds 1-200 --cases 1000`. The XLSX fuzz
  corpora also hold `c1_kinds` and `c2_kinds`, so every chart part name is
  mutated there: the gate runs 500 cases per seed
  (`test/xlsx/read/fuzz_test.dart`, "every part name is mutated in some corpus
  entry"), and the feature fuzz edits their charts through the host
  (`test/xlsx/model/feature_fuzz_test.dart`).
- **A pie's typed check stays linear.** A series with fewer `c:dPt` than
  values cannot be the typed form (the writer writes one per value), so it is
  not written to compare: a `c:ptCount` of twenty digits reads in
  milliseconds, untyped. `chart_reader_test.dart` ("a point count beyond the
  limit is read promptly, untyped").

### Writing

- **Excel's own output is the template.** `writeDrawingChartSpace` writes
  Excel's default column and line charts equal to `chart1.xml` and `chart2.xml`
  of `chart_defaults.xlsx`, and 22 of the 23 charts of the owner's
  `chart_reference.xlsx` read typed. `chart_writer_test.dart` ("Excel's
  default charts"), `excel_reference_test.dart`.
- **Data problems are issues, programmer errors throw.** A chart the writer
  cannot express (a kind other than column, bar, line, area, pie, donut,
  scatter or combination, a secondary axis of a bar, pie, donut or scatter
  chart, a series of another kind, centre text, which no part carries) is an
  `ArgumentError`;
  so are axis ids that are not distinct unsigned 32-bit numbers and series
  ids that are not braced GUIDs.
  `chart_writer_test.dart` ("ArgumentError", "ids").
- **A theme value the part cannot hold is an `ArgumentError` naming the
  field:** a line width (`lineWidth`, `sliceBorderWidth`, the spacing's grid
  and axis line widths) that is not finite or outside 0 to 1584 points
  (`ST_LineWidth`), a `markerSize` that is not finite or negative (it is then
  kept within 2 and 72), a text size that is not finite or outside 1 to 4000
  points (`ST_TextFontSize`, `sz` 100 to 400000). `chart_writer_test.dart`
  ("ArgumentError").
- **The gap width and overlap are clamped** to 0 to 500 and -100 to 100,
  rounded; a `NaN` gap width is 0. `chart_writer_test.dart` ("clamping").
- **Degenerate data writes a part and reports.** No series, a series without
  values, only `null`, `NaN` and infinite values: a well-formed part, issues
  `nonFiniteValue`, never a throw. `chart_writer_test.dart` ("Review Focus").
- **Characters XML 1.0 forbids are dropped and reported once**
  (`invalidCharacter`); markup, line breaks and emoji are kept as text.
  `chart_writer_test.dart` ("Review Focus").
- **References are text.** `'O''Brien'!$A$1:$A$3`, `[0]!Tutarlar` and
  `Sheet1!$B$2:$B$5,Sheet1!$D$2` pass through write and read unchanged.
  `chart_writer_test.dart`, `chart_reader_test.dart`.
- **`ST_Xstring` text escapes `_xHHHH_` look-alikes.** In `c:v`, `c:f` and
  `c:formatCode` the writer writes `_x005F_` for the underscore of a
  look-alike, and the reader decodes it, as Excel does. `a:t` is not escaped
  (Excel's behaviour there is unknown). `chart_values_test.dart`,
  `chart_writer_test.dart` ("xstring escaping"), `chart_reader_test.dart`.
- **Dates are Excel serials** (the 1900 system, with its phantom 29 February
  1900, or with `date1904` the 1904 system, counted from 1 January 1904; a
  part written so declares `c:date1904 1`), written in `m/d/yyyy` unless the
  category axis has a format. The XLSX host passes the workbook's system.
  `chart_values_test.dart` ("the 1904 system counts from 1904-01-01 with no
  phantom day"), `chart_writer_test.dart` ("data", "date categories write
  1904 serials with date1904"), `chart_reader_test.dart` ("date categories
  round trip in the 1904 system"), `chart_part_test.dart` ("created,
  replaced and opened use the 1904 system").
- **More than six series use `ChartTheme.colorOf`'s later passes:** Excel's
  colour cycle (`colors1.xml` of the owner's `chart_defaults.xlsx`): series 7
  to 12 of the Office theme are its accents at `lumMod` 60000, series 13 to 18
  at `lumMod` 80000 and `lumOff` 20000, and so on through the file's nine
  variations, each bound to the scheme (only the list of variations is from
  Excel's file; Excel's own rendering of series 13 and later is unchecked); a
  fixed palette gives fixed colours of the same variations. Ten series write
  and read back equal, and 10,000 points write and read in linear time.
  `chart_reader_test.dart` ("round trip"), `chart_writer_test.dart`
  ("colours").
- **Line markers follow `ChartTheme.lineMarkers`:** on, each line series has
  a circle of `markerSize`; off, `<c:marker><c:symbol val="none"/></c:marker>`,
  Excel's line without markers. The layout still marks a lone point (a value
  with no neighbour) when markers are off, so it shows; the part cannot say
  that, as a series' marker is all or nothing, so Excel draws no marker
  there. `chart_writer_test.dart` ("markers"), `chart_reader_test.dart` ("a
  theme without line markers").
- **The vertical axis title is turned** (`rot="-5400000"`), the chart title
  and the legend are flat, and an axis title's text has no `spc` (a chart
  title's has `spc="0"`), as Excel writes them (`chart_reference.xlsx`, chart
  17). `chart_writer_test.dart` ("vertical axis titles"), `text_test.dart`.
- **The legend and data label blocks are Excel's**: a legend `bodyPr` with
  `rot="0"` and no `spc` (every reference chart with a legend); data labels
  inset with `spAutoFit`, 9 pt `tx1` 75000/25000 (charts 20 and 21).
  `text_test.dart`.

### Excel's reference workbook

`test/fixtures/owner/charts/chart_reference.xlsx` holds 23 charts of
`Veri!A1:C5` (two series), made through Office.js in Excel for Mac 16.0300 in
the order of `TALIMATLAR.md`. `excel_reference_test.dart` reads each and
checks what it shows. What it showed, each now what the writer writes:

- **Gap width and overlap by kind and grouping.** Clustered column 219 and
  -27 (chart 1); clustered bar 182 and no `c:overlap` (chart 4); stacked and
  percent stacked columns and bars 150 and 100 (charts 2, 3, 5, 6). The values
  are the Office theme's in `jet_charts_core`
  (`ChartTheme.gapWidthPercentOf`, `overlapPercentOf`), so the layout draws
  them too. The writer leaves out an overlap of 0, the schema's default.
- **Blanks as zero** (`c:dispBlanksAs val="zero"`) in every area chart and in
  the stacked and percent stacked line charts (charts 8 to 12); `gap`
  elsewhere.
- **A percent stacked value axis** is `c:numFmt formatCode="0%"
  sourceLinked="1"` (charts 3, 6, 9, 12); the reader reads it as no format,
  as for any linked format.
- **An area chart's category axis** has `c:majorTickMark val="out"` (charts
  10 to 12); the value axis keeps `none`. Area charts cross `midCat`, as the
  writer already wrote.
- **A category axis that crosses inside the plot** (a series has a negative
  value, or the value axis' minimum is below zero) has `c:tickLblPos
  val="low"`, so Excel draws its labels under the plot (beside it for bars),
  as `jet_charts_core` does, not at the zero line under the negative bars;
  `nextTo`, Excel's default, otherwise and on every value axis. Not Excel's
  default: the owner's choice after the J4 gallery check (2026-11-10;
  `packages/jet_charts_core/docs/parity.md`, "Category labels"). The reader
  does not read the position.
- **Markers on stacked lines**: Excel keeps them (charts 8, 9), as the writer
  already wrote.
- **Axis titles** have no `spc` in their run properties (chart 17); the
  vertical one is turned `-5400000`, as already written.
- **Shown data labels are each series' own `c:dLbls`** (charts 20, 21): the
  format code when set, a bare shape, the data label block, `c:showVal 1`,
  `c:showLeaderLines 0` and a `c15:leaderLines` extension of a 0.75 pt
  `A6A6A6` line (`tx1` 35000/65000), and no `c:dLblPos`; the group's
  `c:dLbls` keeps every flag off. The reader takes the first series' labels
  before the group's. Line and area charts use the same per-series form by
  analogy; no Excel chart shows it. The data label colour is `404040`, now
  the Office theme's.
- **J4 fields of the four kinds (estimates, not checked in Excel; the owner's
  J4 reference charts decide).** A line series' `smooth` is `c:smooth 1` (the
  group's stays 0); an area series' `smooth` writes nothing, as Excel's area
  has no `c:smooth` (the curved top is screen only, `parity.md`), and reads
  back as not smooth. `pointColors` of a column, bar or line series, and the
  theme's colours of its `pointColorKeys` (`ChartTheme.pointColorOf`; the
  file holds no key, so the colour reads back as a point colour), are one
  `c:dPt` per colour, after `c:marker` or `c:invertIfNegative` and before
  `c:dLbls` (the schema's order): `c:idx`, `c:invertIfNegative 0` of a bar,
  for a line the marker filled and lined in the colour, `c:bubble3D 0`, and
  `c:spPr` (a bar's fill; a line keeps the series' own line, so only the
  marker changes, as on screen). An area chart is never given `c:dPt`. In an
  area chart, `ChartTheme.areaOpacity` below 1 adds `a:alpha` of
  `(opacity * 100000).round()` after the fill colour's luminance children,
  and `areaLine` writes the series' `a:ln` (series colour, `lineWidth`,
  round cap) in place of no line; other kinds ignore both. `showValue: false`
  is `c:showVal 0`; `showPercent` is `c:showPercent 0` but in a pie or
  doughnut (Excel allows it there only), and a `holeSizePercent` is ignored
  outside a donut.
  The reader reads `smooth` and the point colours back, and reads (and drops)
  an `a:alpha` of a series fill only (any other translucent colour reads as
  no colour, as before), so the typed form still depends on writing the
  part again. Labels that are shown with `showValue: false` draw nothing, as
  hidden ones do: the reader gives them back as hidden, so such a chart reads
  untyped. `chart_writer_test.dart` and `chart_reader_test.dart` ("J4
  fields").
- **A hidden axis has no `c:spPr` and no `c:txPr`** (chart 22, the value
  axis). The writer leaves both out of a hidden category axis too, by
  analogy; no Excel chart shows that yet.
- **The minimum, maximum and major unit** sit on the value axis only, as
  written (chart 18); **format codes** are stored invariant (`#,##0.00`,
  `0.0`; charts 19, 21).
- **Every chart of two series made without a title has Excel's automatic
  title** (a `c:title` without text, `c:autoTitleDeleted 0`), which the typed
  form carries; the legend is at the bottom.
- **Not typed: chart 13 (`Satışlar`).** Its title's run is `lang="en-US"`
  while `c:lang` and every other text are `tr-TR`: Office.js set the text.
  The typed form carries one language (ruling R3 of C1), so the chart gives a
  view only and its bytes are kept. A title typed in Excel's own window may
  carry the part's language; a chart made by hand would tell (a step of the
  owner's C2 check).
- **Names.** Chart 23 used the name `Tutarlar` (`Veri!$B$2:$B$5`) as its
  first series' values, but Office.js resolved it: the part's `c:f` is
  `Veri!$B$2:$B$5`. Whether Excel writes `[0]!Tutarlar` for a name stays
  open: it needs a chart made by hand in Excel (an optional step of the
  owner's C2 check).

### Validation

- **Every written chart part is accepted by the Open XML SDK.** The fixtures
  `c1_kinds` and `c1_options` (`test/fixtures/c1_fixtures.dart`) and
  `c2_kinds` and `c2_data` (`test/fixtures/c2_fixtures.dart`), all built by
  `XlsxWorkbook` since C2, go through `tool/ooxml_validate` in CI;
  `chart_fixtures_test.dart` checks they write without an issue, read back
  typed and equal, and that the drawing holds one graphic frame per chart.
  The SDK accepts pies, doughnuts, scatter and combination charts and the
  secondary axis as written; no ignore was added for them.
- **The tool ignores three SDK errors in every run:** `Sch_UndeclaredAttribute`
  and `Sch_InvalidElementContentExpectingComplex` on Excel's own
  `c16r3:dataDisplayOptions16` extension, and only on the `c:ext` at
  `/c:chartSpace[1]/c:chart[1]/c:extLst[1]/c:ext[1]` of a chart part whose
  only attribute is `uri="{56B9EC1D-385E-4148-901F-78D8002777C0}"`, whose only
  child is one `c16r3:dataDisplayOptions16`, whose only child is one
  `c16r3:dispNaAsBlank`, whose only attribute is an unqualified `val` of `1`,
  `0`, `true` or `false` (Excel writes `1`). The SDK 3.5.1 has a schema gap
  there; Excel writes it. Another attribute, a second or no `dispNaAsBlank`,
  or another value still fails: `c1_corrupt.xlsx` (`write_fixtures.dart
  --corrupt`, two `dispNaAsBlank`) is the negative control CI requires the
  tool to reject. It also ignores `Sch_UnexpectedElementContentExpectingComplex`
  on Excel's data label leader lines (`c:dLbls/c:extLst/c:ext` of
  `{CE6537A1-D6FC-4f65-9D91-7224C49458BB}` holding exactly one
  `c15:showLeaderLines` and one `c15:leaderLines` of one `c:spPr`), which the
  SDK refuses in Excel's own `chart_reference.xlsx`; `c1_corrupt_labels.xlsx`
  (two `showLeaderLines`) is its negative control. With `--libreoffice-resave`
  it also ignores the two errors
  on LibreOffice's chart style parts. Both are in `AGENTS.md`, "Validation". A
  real defect in those spots is hidden by the narrow match; keep the match
  narrow.

## What C1 types, and why

`Chart` stays the model; `DrawingChartSpace` adds only what must survive a
round trip to reproduce Excel's part (language, ids, automatic title). The
reader's view is always available, so a host can draw a chart from any
producer; the typed form is the promise that editing it loses nothing. A
chart that is only a view keeps its bytes until replaced.

## What C2 closed

Each item C1 left open for C2, and where it went:

- The drawing anchor (`xdr:graphicFrame`), the sheet's `drawing` wiring and
  the public API: done in the model (`XlsxSheet.charts`, `addChart`,
  `replaceChartAt`, `moveChartAt`, `removeChartAt`, `writeChartData`;
  `docs/xlsx-model.md`, "What C2 adds"). The writer (`XlsxWriter`,
  `XlsxStreamWriter`) gets no chart API (the owner's decision 2): its output
  can be opened with the model and charted.
- `DrawingChartIssue` as warnings: `unreadable` and `badNumber` are
  `featureEntryInvalid` with the detail `chart`, `invalidCharacter` is
  `invalidCharactersRemoved` and `nonFiniteValue` the new
  `chartValueOmitted`, with `en`, `de` and `tr` messages;
  `unsupportedKind` is no warning.
- References generated for a list export: `writeChartData` writes a chart's
  data to cells and binds it. `XlsxListExport` gets no chart: re-filed as
  later work, when Monépro asks for a chart beside a list.
- The `style` and `colors` parts of an opened chart: kept with it; a
  `replaceChartAt` of another kind drops them (their content is per kind), of
  the same kind keeps them, and `removeChartAt` drops them with the part.
- `date1904` from the workbook and the file theme's `ThemeColors` passed to
  the reader: done (the host passes both).
- The `chart_defaults` theme items still unconfirmed: the spacing values
  (padding, title and legend gaps, legend symbol and item gap) can be seen
  only on a drawn chart, as Excel lays out a chart with an empty `c:layout`
  itself; the owner's C2 check compares them on `c2_dashboard.xlsx` beside
  the gallery. The label gaps (4 and 2 pt) stay with `jet_charts_core`
  (`docs/excel-checks.md` there): no file holds them and the eye cannot
  measure them.
- Whether Excel writes `[0]!Name` for a series bound to a workbook name:
  pending the owner's chart made by hand (an optional step of the C2 check).
  A hand-written part holding `[0]!Tutarlar` reads, lists and saves
  unchanged, and structural edits and renames leave it alone
  (`test/xlsx/model/chart_names_test.dart`); `writeChartData` never writes
  one.
- Whether a title typed in Excel carries the part's language (chart 13):
  pending a step of the owner's C2 check.
- A cap on a chart part's size: `XlsxReadLimits.maxChartPartBytes`, 32 MiB by
  default, checked on the entry's declared size before it is read; a part
  over it lists with no view, warns and is kept byte for byte.
- `DrawingChart.typed` after `created` or `replace` is the space as given:
  the host lists a chart from the part it holds and reopens a part whose
  content changed (a structural edit's rewrite, an undo), so `charts` gives
  what the part holds. Caches stay as written after `setCell` or a
  structural edit (the owner's decision 5).
- A part name a content type override declares but no part has is skipped
  by `addChart`, and, since the follow-up to C2, by every part the model adds
  (`OpcPackage.freePartName`; `docs/xlsx-model.md`, "Untrusted input").

## Open for C3

- `c:externalData` and the embedded workbook built by `XlsxWriter`.
- Inline and anchored chart drawings in the body.
- `DocxWarningCode`s for chart issues.
- A chart that is a picture today stays one when opened.

## Open for both

- The other kinds (decision 0017 orders them later; the writer refuses them
  until then). The secondary axis, a numeric scatter and a combination's area
  group wait for the owner's C2 check (its E3 steps).
- Excel's palette past 54 series: the colour cycle starts again after its
  nine variations, which `colors1.xml` does not state (unconfirmed). Series 7
  and 8 match a new chart made in Excel (the owner's check, 2026-11-09).
- Right-placed line data labels touch the line in Excel (`c1_options`).
