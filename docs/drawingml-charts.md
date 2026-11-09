# DrawingML charts

The DrawingML layer (`lib/src/drawingml/`) writes a `jet_charts_core` `Chart`
as a `c:chartSpace` part the way Excel for Mac writes it, reads such a part
back, and keeps an opened part byte for byte. Decision
[`0014`](decisions/0014-chart-phase-and-drawingml-layer.md) sets the phase;
[`0015`](decisions/0015-drawingml-layer-imports.md) says what the layer may
import. The layer knows neither XLSX nor DOCX. Its types carry the prefix
`Drawing`.

**Status of C1: done except the owner's reference workbook and Excel check
(Task 10).** Nothing here is exported from `lib/jet_office.dart` yet: the
public API arrives with the hosts, C2 (XLSX) and C3 (DOCX).

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
  kept.** A `dk1` where Excel writes `tx1`, an extra `c:dispUnits`, a part
  without `c16` ids. `chart_reader_test.dart` ("parts that are not typed",
  "variants of other producers"), `chart_part_test.dart` ("opened").
- **An opened part is saved byte for byte until `replace` gives it a new typed
  form.** The bytes are held, not copied. `chart_part_test.dart`.
- **Reading is lazy and never throws.** `chart`, `typed` and `issues` read on
  first use, once. Unreadable bytes give no chart and the issue `unreadable`.
  `chart_part_test.dart`, `chart_reader_test.dart` (the "unreadable input" test).
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
  `test/theme/chart_color_test.dart`.

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
  of `chart_defaults.xlsx`. `chart_writer_test.dart` ("Excel's default
  charts").
- **Data problems are issues, programmer errors throw.** A chart the writer
  cannot express (a kind outside the J2 set, a secondary axis, a series of
  another kind) is an `ArgumentError`; so are axis ids that are not distinct
  unsigned 32-bit numbers and series ids that are not braced GUIDs.
  `chart_writer_test.dart` ("ArgumentError", "fix round 1").
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
  `chart_writer_test.dart` ("fix round 1"), `chart_reader_test.dart`.
- **Dates are Excel serials** (the 1900 system, with its phantom 29 February
  1900), written in `m/d/yyyy` unless the category axis has a format.
  `chart_values_test.dart`, `chart_writer_test.dart` ("data").
- **More than six series use derived fixed colours** from
  `ChartTheme.colorOf`; ten series write and read back equal, and 10,000
  points write and read in linear time. `chart_reader_test.dart`
  ("round trip").
- **The vertical axis title is turned** (`rot="-5400000"`), the chart title
  and the legend are flat. This follows Excel's known habit and is unconfirmed
  until the owner's reference workbook. `chart_writer_test.dart` ("fix round
  1").
- **The legend and data labels use shapes known from Excel** (a legend
  `bodyPr` with `rot="0"`; data labels inset with `spAutoFit`), also awaiting
  the reference workbook. `text_test.dart`.

### Validation

- **Every written chart part is accepted by the Open XML SDK.** The fixtures
  `c1_kinds` and `c1_options` (`test/fixtures/c1_fixtures.dart`) go through
  `tool/ooxml_validate` in CI; `chart_fixtures_test.dart` checks they write
  without an issue, read back typed and equal, and that the drawing holds one
  graphic frame per chart.
- **The tool ignores two SDK errors in every run:** on Excel's own
  `c16r3:dataDisplayOptions16` extension of `c:chart/c:extLst`, matched at its
  path and content. The SDK has a schema gap there; Excel writes it. With
  `--libreoffice-resave` it also ignores the two errors on LibreOffice's chart
  style parts. Both are in `AGENTS.md`, "Validation". A real defect in those
  spots is hidden by the narrow match; keep the match narrow.

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

## Open for C3

- `c:externalData` and the embedded workbook built by `XlsxWriter`.
- Inline and anchored chart drawings in the body.
- `DocxWarningCode`s for chart issues.
- A chart that is a picture today stays one when opened.

## Open for both

- The secondary axis, combination charts and the other kinds (J4).
- Excel's palette past six series.
- The owner's reference workbook (`test/fixtures/owner/charts/`, steps in
  `TALIMATLAR.md`): every chart in it must read typed, and the writer's
  habits above are corrected against it. Until it arrives
  `excel_reference_test` skips the chart group.
