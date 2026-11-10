# DrawingML charts

The DrawingML layer (`lib/src/drawingml/`) writes a `jet_charts_core` `Chart`
as a `c:chartSpace` part the way Excel for Mac writes it, reads such a part
back, and keeps an opened part byte for byte. Decision
[`0014`](decisions/0014-chart-phase-and-drawingml-layer.md) sets the phase;
[`0015`](decisions/0015-drawingml-layer-imports.md) says what the layer may
import. The layer knows neither XLSX nor DOCX. Its types carry the prefix
`Drawing`.

**Status of C1: done** (the owner's Excel check of the fixtures is in
`docs/excel-checks.md`). The owner's reference workbook is committed and every chart in
it but one reads typed ("Excel's reference workbook" below). Nothing here
is exported from `lib/jet_office.dart` yet: the public API arrives with the
hosts, C2 (XLSX) and C3 (DOCX).

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
stacked, on one category axis and one value axis.

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
- **A kind outside the model (a pie, a combination) or a third axis is
  `unsupportedKind`:** a view with the kind `unsupported`, no typed form.
  `chart_reader_test.dart`.
- **The typed form carries the language, the two axis ids, each series'
  `c16:uniqueId` and Excel's automatic title.** Anything else Excel writes is
  fixed by the writer; a part that differs is not typed.
  `chart_reader_test.dart` ("the column chart keeps its ids").
- **Scheme names.** `dark1`, `light1`, `dark2`, `light2` are written `tx1`,
  `bg1`, `tx2`, `bg2`; `dk1`, `lt1`, `dk2`, `lt2` are read as the same slots
  (and the part is then not typed). `test/drawingml/color_test.dart`.
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
- **The fuzz.** `chart_fuzz_test.dart` mutates the corpus (the Excel charts and
  every C1 chart; seeds 1 to 4, 100 cases each, the same cases on the VM and in
  Chrome, proved by a digest) and requires: the reader throws nothing, a typed
  form writes a part that reads typed again, an opened part encodes its bytes.
  Longer runs: `dart run tool/fuzz_chart.dart --seeds 1-200 --cases 1000`.
  The XLSX fuzz corpora also hold `c1_kinds`, so every chart part name is
  mutated there: the gate runs 500 cases per seed
  (`test/xlsx/read/fuzz_test.dart`, "every part name is mutated in some corpus
  entry").

### Writing

- **Excel's own output is the template.** `writeDrawingChartSpace` writes
  Excel's default column and line charts equal to `chart1.xml` and `chart2.xml`
  of `chart_defaults.xlsx`, and 22 of the 23 charts of the owner's
  `chart_reference.xlsx` read typed. `chart_writer_test.dart` ("Excel's
  default charts"), `excel_reference_test.dart`.
- **Data problems are issues, programmer errors throw.** A chart the writer
  cannot express (a kind outside the J2 set, a secondary axis, a series of
  another kind, centre text, which only a donut shows) is an `ArgumentError`;
  so are axis ids that are not distinct unsigned 32-bit numbers and series
  ids that are not braced GUIDs.
  `chart_writer_test.dart` ("ArgumentError", "ids").
- **A theme value the part cannot hold is an `ArgumentError` naming the
  field:** a line width (`lineWidth`, the spacing's grid and axis line
  widths) that is not finite or outside 0 to 1584 points (`ST_LineWidth`), a
  `markerSize` that is not finite or negative (it is then kept within 2 and
  72), a text size that is not finite or outside 1 to 4000 points
  (`ST_TextFontSize`, `sz` 100 to 400000). `chart_writer_test.dart`
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
  1900), written in `m/d/yyyy` unless the category axis has a format.
  `chart_values_test.dart`, `chart_writer_test.dart` ("data").
- **More than six series use `ChartTheme.colorOf`'s later passes:** Excel's
  colour cycle (`colors1.xml` of the owner's `chart_defaults.xlsx`): series 7
  to 12 of the Office theme are its accents at `lumMod` 60000, series 13 to 18
  at `lumMod` 80000 and `lumOff` 20000, and so on through the file's nine
  variations, each bound to the scheme (only the list of variations is from Excel's
  file; Excel's own rendering of series 13 and later is unchecked); a fixed
  palette gives fixed colours of the same variations. Ten series write and
  read back equal, and 10,000 points write and read in linear time.
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
  back as not smooth. `pointColors` of a column, bar or line series are one
  `c:dPt` per colour, after `c:marker` or `c:invertIfNegative` and before
  `c:dLbls` (the schema's order): `c:idx`, `c:invertIfNegative 0` of a bar,
  for a line the marker filled and lined in the colour, `c:bubble3D 0`, and
  `c:spPr` (a bar's fill; a line keeps the series' own line, so only the
  marker changes, as on screen). An area chart is never given `c:dPt`. In an
  area chart, `ChartTheme.areaOpacity` below 1 adds `a:alpha` of
  `(opacity * 100000).round()` after the fill colour's luminance children,
  and `areaLine` writes the series' `a:ln` (series colour, `lineWidth`,
  round cap) in place of no line; other kinds ignore both. `showValue: false`
  is `c:showVal 0`; `showPercent` is always `c:showPercent 0` (Excel allows
  it in pies only), and a `holeSizePercent` is ignored outside a donut.
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
  carry the part's language; a chart made by hand would tell.
- **Names.** Chart 23 used the name `Tutarlar` (`Veri!$B$2:$B$5`) as its
  first series' values, but Office.js resolved it: the part's `c:f` is
  `Veri!$B$2:$B$5`. Whether Excel writes `[0]!Tutarlar` for a name stays open
  for C2: it needs a chart made by hand in Excel.

### Validation

- **Every written chart part is accepted by the Open XML SDK.** The fixtures
  `c1_kinds` and `c1_options` (`test/fixtures/c1_fixtures.dart`) go through
  `tool/ooxml_validate` in CI; `chart_fixtures_test.dart` checks they write
  without an issue, read back typed and equal, and that the drawing holds one
  graphic frame per chart.
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

## Open for C2

- The drawing anchor (`xdr:graphicFrame`) and the sheet's `drawing` wiring in
  the workbook model and the writer.
- The public API: `addChart`, the charts of a sheet.
- `DrawingChartIssue` mapped to `XlsxWarningCode`s, with messages in `en`,
  `de` and `tr`.
- References generated for a list export.
- The `style` and `colors` parts of an opened chart kept with it.
- `date1904` from the workbook (`drawingSerialOf` knows the 1900 system only).
- The file theme's `ThemeColors` passed to the reader.
- The `chart_defaults` theme items still unconfirmed (`docs/excel-checks.md` of
  `jet_charts_core`).
- Whether Excel writes `[0]!Name` in a series reference to a workbook name:
  `chart_reference.xlsx`'s chart 23 was made through Office.js, which
  resolved the name to its range. A chart made by hand in Excel answers it.
- Whether a title typed in Excel carries the part's language (chart 13 of
  `chart_reference.xlsx`, set through Office.js, has `en-US` in a `tr-TR`
  part and is not typed).
- A cap on a chart part's size before it is read. `readDrawingChartSpace`
  builds a node per element, so it holds several times the part's size in
  memory, and `ReadLimits` allows ZIP entries of 256 MiB: C2 must refuse a
  chart part above a size of its own choosing before reading it (or read it
  streaming).
- `DrawingChart.typed` after `created` or `replace` is the space as given,
  which can differ from what reopening the bytes gives (a UTC date reads back
  local, a category axis minimum the writer drops, scrubbed characters, `NaN`
  scaling). A host that needs what the part holds reopens it.

## Open for C3

- `c:externalData` and the embedded workbook built by `XlsxWriter`.
- Inline and anchored chart drawings in the body.
- `DocxWarningCode`s for chart issues.
- A chart that is a picture today stays one when opened.

## Open for both

- The secondary axis, combination charts and the other kinds (J4; C2 and C3
  write them, and the writer refuses them until then).
- Excel's palette past 54 series: the colour cycle starts again after its
  nine variations, which `colors1.xml` does not state (unconfirmed). Series 7
  and 8 match a new chart made in Excel (the owner's check, 2026-11-09).
- Right-placed line data labels touch the line in Excel (`c1_options`).
