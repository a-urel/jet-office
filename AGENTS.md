# Working in jet-office

`jet_office` is a pure-Dart library that generates, reads and modifies XLSX and
DOCX files. It has no editors, no rendering and no PDF. It is ported from
`quds_office_engine` (MIT); see `docs/decisions/0001`, `0002`, `0003`,
`0004` (which supersedes part of `0003`), `0005` (which supersedes ruling
R10 in `docs/xlsx-writer.md`), `0006` (ZIP bytes may differ by platform),
`0007` (phase 2: a fast reader for import; files are untrusted input),
`0008` (a number format engine that shows values as Excel for Mac does) and
`0009` (phase 3: a workbook model that opens, generates, edits and saves
without loss; supersedes part of `0002`) and `0010` (phase 4: a DOCX document
model, on the same fidelity standard), `0011` (a new document's parts are
this library's own, with Word's values) and `0012` (the number format engine
lives in `jet_core`; supersedes `0001`'s one runtime dependency and `0008`'s
location and names) and `0013` (one repository: a pub workspace, with
`jet_core` under `packages/`) and `0014` (the chart phase: `jet_charts_core`
under `packages/`, and a DrawingML layer here) and `0015` (what the DrawingML
layer may import; supersedes that sentence of `0014`) and `0016`
(`jet_charts_flutter`, the Flutter backend, is a member of the workspace, so
resolving it needs Flutter's SDK) and `0017` (every Excel chart kind is
covered in the end, Monépro's first; supersedes the design's chart non-goals)
and `0018` (what phase 3 leaves opaque, formula evaluation and encryption are
covered in the end; macros and other formats stay out; supersedes part of
`0009`) and `0019` (equations are covered in the end; level, order and
editor undecided; supersedes 0010's "equations stay opaque") and `0020` (ink
from the Draw tab is covered in the end; level, order and drawing surface
undecided) and `0021` (shapes, text boxes and icons are covered in the end;
level and order undecided; supersedes 0010's "text boxes and floating
pictures stay opaque") and `0022` (what phase 4 leaves opaque, tracked
changes, comments, notes, content controls and a table of contents, is
covered in the end; template fill first; macros stay out; supersedes part of
`0010`) before any design change.

Phase 3, the workbook model, is complete at W6 (proof and release readiness):
its names are fixed, so a rename of a public name of `XlsxWorkbook` is breaking
(`docs/xlsx-model.md`, "What W6 does").

`packages/jet_charts_core` is the pure-Dart chart core (decision 0014); it has
its own `AGENTS.md`; milestone J3 is done (the Flutter renderer, ids, hit
testing, tooltip and summary), and J4 is done (the kinds pie, donut,
sparkline, scatter, combination, the secondary axis, smooth lines), its Excel
checks E1 and E2 recorded and their values followed
(`packages/jet_charts_core/docs/excel-checks.md`, "J4 values"; the secondary
axis and a numeric scatter wait for the owner's later E3), and this package
depends on it from C1.
Milestone C1 (the DrawingML chart layer, `docs/drawingml-charts.md`) is done
(the owner's Excel check is in `docs/excel-checks.md`); every chart of the
owner's `chart_reference.xlsx` but one reads typed.
`packages/jet_charts_flutter` is its Flutter backend (decision 0016), with its
own `AGENTS.md`; milestones J3 and J4 are done. This
package never depends on it. `packages/jet_charts_flutter/docs/app-themes.md`
is the guide for an app's themes and charts.

Consumers: Monépro (list and dashboard export, spreadsheet import, document
templates) and later `jet_print` (report export to XLSX/DOCX). `jet_office`
knows nothing about either of them.

## The quality gate

Run from the repository root. A clean checkout must pass all of it:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart test -p chrome
(cd packages/jet_core && dart test && dart test -p chrome)
(cd packages/jet_charts_core && dart test && dart test -p chrome)
(cd packages/jet_charts_flutter && flutter test && flutter test --platform chrome --exclude-tags golden)
(cd packages/jet_charts_flutter/example && flutter test)
```

The workspace has a Flutter package, so resolving it (`flutter pub get` or
Flutter's `dart pub get` at the root) needs Flutter's SDK, 3.47.9 in CI, and
`dart` must be Flutter's (decision 0016). `jet_charts_flutter`'s tests need
Flutter's engine and run with `flutter test`. Its golden image tests (tag
`golden`) run on macOS only: the local `flutter test` runs them, and CI and the
Chrome leg skip them.

The Chrome leg runs every test that is not marked `@TestOn('vm')` in a
browser, which proves the library is web-safe at run time and not only by its
imports. It needs a local Chrome.

Never report work as done without running these and reading the output.

## Validation

CI's `validate` job runs after the quality gate and is required. Locally it is
optional. The Open XML SDK step runs whenever `dotnet` (8 or later) is
installed; the LibreOffice steps need LibreOffice as well. The fixtures come
from `allFixtures()` (`test/fixtures/fixtures.dart`), so a fixture added to a
milestone list is validated without further wiring:

```bash
dart run tool/write_fixtures.dart build/fixtures
dotnet run --project tool/ooxml_validate -- build/fixtures
LC_ALL=C.UTF-8 soffice --headless \
  --convert-to 'csv:Text - txt - csv (StarCalc):44,34,UTF8,1,,0,false,true,false,false,false,-1' \
  --outdir build/fixtures build/fixtures/*.xlsx
dart run tool/compare_csv.dart build/fixtures
mkdir -p build/resaved
LC_ALL=C.UTF-8 soffice --headless --convert-to 'xlsx:Calc MS Excel 2007 XML' \
  --outdir build/resaved build/fixtures/*.xlsx
dart run tool/compare_resaved.dart build/fixtures build/resaved
dart run tool/round_trip_model.dart build/fixtures build/model
dart run tool/round_trip_model.dart build/resaved build/model-resaved
dotnet run --project tool/ooxml_validate -- build/model
dotnet run --project tool/ooxml_validate -- --libreoffice-resave build/model-resaved
dart run tool/edit_model.dart build/fixtures build/model-edited
dotnet run --project tool/ooxml_validate -- build/model-edited
(ulimit -f 500000; LC_ALL=C.UTF-8 soffice --headless \
  --convert-to 'txt:Text (encoded):UTF8' \
  --outdir build/fixtures build/fixtures/*.docx)
dart run tool/compare_text.dart build/fixtures
mkdir -p build/resaved-docx
LC_ALL=C.UTF-8 soffice --headless --convert-to 'docx:MS Word 2007 XML' \
  --outdir build/resaved-docx build/fixtures/*.docx
dart run tool/compare_resaved_docx.dart build/fixtures build/resaved-docx
dart run tool/round_trip_docx.dart build/fixtures build/model-docx-fixtures
dart run tool/round_trip_docx.dart build/resaved-docx build/model-docx
dart run tool/round_trip_docx.dart test/fixtures/owner/docx build/model-docx-owner
dotnet run --project tool/ooxml_validate -- build/model-docx-fixtures
dotnet run --project tool/ooxml_validate -- --libreoffice-resave build/model-docx
dotnet run --project tool/ooxml_validate -- build/model-docx-owner
dart run tool/edit_docx.dart build/fixtures build/edited-docx-fixtures
dart run tool/edit_docx.dart build/resaved-docx build/edited-docx
dart run tool/edit_docx.dart test/fixtures/owner/docx build/edited-docx-owner
dotnet run --project tool/ooxml_validate -- build/edited-docx-fixtures
dotnet run --project tool/ooxml_validate -- --libreoffice-resave build/edited-docx
dotnet run --project tool/ooxml_validate -- build/edited-docx-owner
dart run packages/jet_charts_flutter/example/tool/write_excel_gallery.dart build/excel_gallery
dotnet run --project tool/ooxml_validate -- build/excel_gallery
```

- `tool/write_fixtures.dart` writes each fixture of `allFixtures()`
  (`test/fixtures/fixtures.dart`, which joins the milestone lists) as
  `<name>.xlsx` and its expected values as `<name>.expected.json`, the C1
  chart fixtures among them (`c1_kinds`, the sheet `Data` with the 12 column,
  bar, line and area charts in the three groupings, Office theme; `c1_options`,
  the sheet `O'Brien` with six charts of the options: title, the four legend
  positions and a hidden legend, axis titles, a fixed range, format codes, data
  labels, hidden axes, literal data, date categories, an automatic title and
  eight series in an app theme with fixed colours), whose chart parts of
  `writeDrawingChartSpace` the test-only host `withCharts`
  (`test/drawingml/chart/support/chart_host.dart`, replaced by C2's host) draws
  on the sheet, and each
  DOCX fixture of `docxFixtures()` (`test/fixtures/docx_fixtures.dart`) as
  `<name>.docx` and its expected text as `<name>.expected.txt`: the D1
  documents (`d1_*`), the D2 ones (`d2_*`), the D3 tables (`d3_basic`,
  `d3_header_row`, `d3_merges`, `d3_formatting`, `d3_nested`), the D4
  sections, headers and fields (`d4_sections`, four sections with a Letter one
  last; `d4_headers`; `d4_fields`) and the D5 pictures, links and properties
  (`d5_pictures`, a PNG in the body, a JPEG in a cell and the PNG as a header
  logo; `d5_links`, a bookmark, an external and an internal link and a footer
  link; `d5_properties`, every core property, the company and the
  application) and the D6 lists written by `DocxListExport` (`d6_list`, Turkish
  with a logo, a caption, a date, an amount and a share column, 120 rows over
  three A4 pages and a totals row; `d6_list_landscape`, English on landscape A4
  with 1.27 cm margins, twelve columns and 40 rows). A fixture with a
  `DocxFixture.headerFooterText` (`d4_headers`, `d4_fields`, `d5_pictures`,
  `d5_links`, `d6_list`, `d6_list_landscape`) also gets `<name>.stories.txt`,
  what its headers and footers show. No fixture ends in a table, because
  LibreOffice's text export of one never ends (see below), or in a section
  break, as the model adds no block after one.
  `--corrupt` adds a deliberately broken `m1_corrupt.xlsx`, `c1_corrupt.xlsx`,
  `c1_corrupt_labels.xlsx` and `d1_corrupt.docx`, to prove every check still
  fails on a bad file. The
  `validate` job's negative-control step writes `m1_corrupt.xlsx` to
  `build/corrupt` and requires every check to reject it, except the model round
  trip (`tool/round_trip_model.dart`), which passes on it: the model keeps the
  file's stray content faithfully, so the Open XML SDK must reject the model's
  output instead, and the round trip must reject a truncated copy. The same step
  moves `c1_corrupt.xlsx` (`c1_kinds` whose first chart's
  `c16r3:dataDisplayOptions16` holds two `dispNaAsBlank`) to
  `build/corrupt-chart` and requires `tool/ooxml_validate` to reject it, so the
  validator's ignore of that extension (below) stays narrow, and
  `c1_corrupt_labels.xlsx` (`c1_options` whose line chart's first leader line
  extension holds two `c15:showLeaderLines`) beside it, for the leader line
  ignore. A second step does
  the same for `d1_corrupt.docx` in `build/corrupt-docx` (a `w:r` directly under
  `w:body`, and "first" spelled "firzt"), with `tool/compare_text.dart`,
  `tool/compare_resaved_docx.dart` and `tool/round_trip_docx.dart` in place of
  their XLSX counterparts.
- `tool/write_fixtures.dart` imports test helpers that use `package:archive`.
  That is allowed: the archive rule covers `lib/` only.
- `tool/ooxml_validate` validates every `.xlsx` and `.docx` with the Open XML
  SDK against the Microsoft 365 schemas and fails on any error. An error there
  is a writer or model bug.
  `--libreoffice-resave` is for a directory that came from LibreOffice's
  re-save, or from the model's round trip or edit of one (`build/resaved-docx`,
  `build/model-docx`, `build/edited-docx`): LibreOffice writes a repeating
  header row as `<w:tblHeader w:val="true"/>`, which the SDK refuses (it takes
  only `on` and `off` there) and the model keeps as read. `w:cantSplit` has the
  same type, so the flag covers `w:val="true"` there too, though the
  LibreOffice checked writes it bare. The flag ignores that one error on those
  two elements, matched on the element and its exact value. For
  `build/model-resaved` it covers LibreOffice's chart style parts
  (`xl/charts/styleN.xml`), which LibreOffice writes beside every chart it
  re-saves and the model keeps as read: a `cs:dataPointMarkerLayout` with
  children and a `cs:fontRef` holding `cs:schemeClr` for `a:schemeClr`, the
  two errors matched on their ids, the part's content type and the element.
  The `d1_corrupt.docx` negative control must still fail with it.
  One error pair is ignored in every run, with or without the flag: the SDK
  3.5.1 refuses the `c:chart/c:extLst` extension
  `{56B9EC1D-385E-4148-901F-78D8002777C0}` (`c16r3:dataDisplayOptions16`) that
  Excel itself writes in every chart part (the owner's `chart_defaults.xlsx`
  fails the same way), so the tool ignores its `Sch_UndeclaredAttribute` and
  `Sch_InvalidElementContentExpectingComplex` only on the `c:ext` at
  `/c:chartSpace[1]/c:chart[1]/c:extLst[1]/c:ext[1]` of a chart part whose
  only attribute is `uri` with exactly that value, whose only child is one
  `c16r3:dataDisplayOptions16`, whose only child is one `c16r3:dispNaAsBlank`,
  whose only attribute is an unqualified `val` of `1`, `0`, `true` or `false`
  (Excel writes `1`). Anything else there (another attribute, a second or no
  `dispNaAsBlank`, another value) still counts; `c1_corrupt.xlsx` (below) is
  its negative control. One more error is ignored in every run: the SDK
  refuses the data label leader lines Excel writes in each series' shown
  labels (the owner's `chart_reference.xlsx`, charts 20 and 21, fails the same
  way), so the tool ignores `Sch_UnexpectedElementContentExpectingComplex`
  only on a `c:ext` at `.../c:ser[n]/c:dLbls[1]/c:extLst[1]/c:ext[1]` of a
  bar, line or area group whose only attribute is `uri`
  `{CE6537A1-D6FC-4f65-9D91-7224C49458BB}` and whose children are exactly one
  `c15:showLeaderLines` (only `val` of `1`, `0`, `true` or `false`) and one
  `c15:leaderLines` holding one `c:spPr`; `c1_corrupt_labels.xlsx` (two
  `showLeaderLines`) is its negative control. Every other error counts, in
  every run.
- LibreOffice's text export of a document whose body ends in a table never
  ends: it writes the file without bound. No fixture may end in a table (the
  fixture list says so), and the CI step and the command above cap the file
  size with `ulimit -f` so a runaway fails instead of filling the disk.
- `DocxFixture.libreOfficeTextSkip` (a reason; `d3_nested`, whose text
  LibreOffice writes differently by version) makes `tool/write_fixtures.dart`
  write `<name>.libreoffice-skip.txt`, and `tool/compare_text.dart` skip that
  document and print `<name>: skipped: <reason>`. Its re-save is still
  compared.
- `tool/compare_csv.dart` compares LibreOffice's CSV export of every sheet
  with the expected values on raw values. Its doc comment explains the filter
  options; `tool/src/csv_compare.dart` holds the comparison and its contract.
  On a Mac LibreOffice takes the system's locale, not `LC_ALL`, so on a Turkish
  system this check fails on `3,14159` and `DOĞRU`: use a profile of its own
  (`-env:UserInstallation=file:///<dir>`) whose `registrymodifications.xcu` sets
  `ooSetupSystemLocale` to `en-US`.
- `tool/compare_resaved.dart` reads LibreOffice's XLSX re-save of every
  fixture with `XlsxReader` and compares it with the expected values; any
  reader warning is a mismatch unless `resaveAllowedWarnings` in
  `tool/src/read_compare.dart` names it with a reason. If a LibreOffice
  instance is already running, add `-env:UserInstallation=file:///<dir>` to
  the `soffice` call.
- `tool/round_trip_model.dart` opens every `.xlsx` of a directory with
  `XlsxWorkbook`, loads all sheets, saves to the second directory and
  prints each `comparePackages` difference (with `ignoreBookkeeping`:
  the model recomputes `dimension` and `spans`) as `<file>: <line>`; it
  exits 1 on any difference or error, 2 on unusable arguments. CI runs it
  on the fixtures and on LibreOffice's re-save, then validates both
  outputs with the Open XML SDK. The model keeps what it does not
  understand, so the `--corrupt` workbook round-trips (exit 0) and the
  SDK rejects the output; a truncated copy is the round trip's own
  negative control.
- `tool/edit_model.dart` opens every `.xlsx` of a directory with
  `XlsxWorkbook`, sets a `DateTime`, an `XlsxDate`, a formula and a string
  in the row after the first sheet's last row, gives those cells a bold
  style with a red fill, sets column B's width, the new row's height, a
  merge of the two cells right of them, a frozen first row and a tab
  colour, defines the workbook name `Model_edit` (a number added when
  taken), links the new string cell, adds a list validation, a cell-value
  rule and a data bar on free cells of the new row, sets a landscape A4 page
  setup that fits one page wide, a footer, an auto filter over the new row
  (when no filter or table is in the way) and the workbook's title
  (`OfficeProperties`; no protection: it would lock the owner's review), sets a
  rich text cell, a note and a 4 by 2 pixel PNG picture on the next free columns
  of the new row, adds a table `Model_table` (a number added when taken) over
  the two rows below it, adds a sheet, then (W5) sets a probe text and a
  formula using it on a free row, inserts two rows above the sheet's last row
  and a column at B and renames the sheet `Model edit` (a number added when
  taken), saves to the second directory, and checks the edits read back with
  `XlsxReader` and the model; it also writes the
  generated workbooks of `tool/write_model_sample.dart`, `w1_generated.xlsx`,
  `w2_generated.xlsx`, `w3_generated.xlsx` (a `Report` sheet with a filter, a
  validation, the four conditional rule kinds, two links, print settings, header
  and footer, and a formula using a workbook name; a protected `Locked` sheet;
  workbook properties, `OfficeProperties`) and `w4_generated.xlsx` (an `Objects`
  sheet with rich text, a visible and a hidden note, a PNG and a JPEG as
  one-cell and two-cell pictures, a picture moved to a larger size, a table with
  totals and one without a style; a `Removed` sheet where a table and a picture
  were added and removed again) and `w5_generated.xlsx` (a `Data` sheet with
  two tables, a shared formula group, a chart, a validation, a rule, a note and
  a picture, and a `Summary` sheet of formulas, names, a 3D sum and a table
  sum, then two rows inserted, a column deleted, `Data` renamed `Veri 2026` and
  moved last and a table removed), there. It prints each
  problem as `<file>: <problem>` and exits 1 on any, 2 on unusable
  arguments. CI runs it on the fixtures and validates the output with the
  Open XML SDK, so the model's edited and generated files are validated,
  not only its unchanged round trips.
- `tool/write_w5_check.dart <out-dir>` writes the workbooks of the owner's W5
  Excel check (`build/w5`): `w5_generated.xlsx`, `w5_rows.xlsx` (each row and
  column edge as a formula beside the value and formula Excel should give),
  `w5_charts.xlsx` (`c1_kinds` with a row inserted in the data),
  `w5_rename.xlsx` (sheet names that need quotes, a moved tab, an undone
  edit), and the owner's `chart_reference.xlsx` and the `excel_objects`
  producer file with a row inserted and the sheet renamed. It is not part of
  the CI chain; `dotnet run --project tool/ooxml_validate -- build/w5`
  validates its output, and the owner's steps are in `docs/excel-checks.md`,
  "W5". Exit 2 on unusable arguments.
- `tool/write_w6_check.dart <out-dir>` writes the files of the owner's W6
  Excel check (`build/w6`): `w6_generated_100k.xlsx` and `w6_generated_1m.xlsx`
  (the benchmark's workload, generated with the model), `w6_shapes.xlsx` (two
  rectangles with `textlink`, shifted by edits and a sheet rename),
  `w6_wrapped.xlsx` (a text box in `mc:AlternateContent` moved by edits) and
  `final/` (`tool/edit_model.dart` run on the fixtures and on the owner's
  workbooks). It is not part of the CI chain; `dotnet run --project
  tool/ooxml_validate -- build/w6` and `... -- build/w6/final` validate its
  output, and the owner's steps are in `docs/excel-checks.md`, "W6". Exit 2 on
  unusable arguments, 1 on any error.
- `tool/compare_text.dart` compares LibreOffice's text export of every DOCX
  fixture (`txt:Text (encoded):UTF8`) with its `<name>.expected.txt`, or its
  `<name>.libreoffice.txt` (`DocxFixture.libreOfficeText`: list labels such as
  `    • Bullet one` that the model's text lacks), by
  `textDifferences` in `tool/src/text_compare.dart`: a leading BOM and one
  trailing newline are ignored, everything else must be equal. It prints
  each difference as `<name>: <line>`, exits 1 on any, 2 on unusable input.
- `tool/compare_resaved_docx.dart` opens LibreOffice's DOCX re-save of every
  fixture with `DocxDocument` and compares the body's text with the expected
  text, by `docxResavedText` (`tool/src/text_compare.dart`): LibreOffice ends a
  section with columns or another page in an empty paragraph of its own and
  turns `w:pageBreakBefore` into a `w:br` of the page before, so neither is a
  line. A fixture with a `<name>.stories.txt` has what its headers and footers
  show compared too, by `docxStoriesText`: per section the stories it shows, a
  first one with a title page and an even one with odd and even headers, as
  LibreOffice writes every section its own copies, each field as `{NAME}`, as it
  computes `DATE` and `TIME` and rewrites switches. Any warning is a mismatch
  unless `docxResaveAllowedWarnings` in `tool/src/read_compare.dart` names it
  with a reason. Exit codes as above.
- `tool/round_trip_docx.dart` opens every `.docx` of a directory with
  `DocxDocument`, reads the body, every typed property, every picture,
  hyperlink and bookmark, every section value and story and the document
  properties (which loads `styles`, `numbering`, `settings`, the headers and
  footers and the `docProps` parts), saves to the second directory and prints
  each `comparePackages` difference (`tool/src/part_compare.dart`) as
  `<file>: <line>`; it exits 1 on any difference or error, 2 on unusable
  arguments. A loaded part nothing changed is saved as read, so it also
  encodes the main, styles, numbering, header, footer and properties parts
  from the model and compares them with the input (`encodedPartDifferences`,
  `encodedMainDifferences`, `encodedStoryDifferences`,
  `encodedPropertiesDifferences`, `tool/src/docx_serialize.dart`; a part whose
  root is not a properties part is never written from the model and is not
  compared; `encodedMainDifferences` and `encodedStoryDifferences` take the
  children of `w:pPr`,
  `w:rPr`, `w:tblPr`, `w:trPr`, `w:tcPr` and `w:sectPr` in any order, as the
  model writes them in schema order). CI
  runs it on the fixtures, on LibreOffice's re-save and on the owner's Word
  files, then validates all three outputs with the Open XML SDK. As for
  workbooks, the `d1_corrupt.docx` document round-trips (exit 0)
  and the SDK must reject the output; a truncated copy is the round trip's
  own negative control.
- `tool/edit_docx.dart` opens every `.docx` of a directory with
  `DocxDocument` and edits the body: it sets the text of the first run with
  text to `Edited by the model` and makes it bold in the theme colour accent
  1; it replaces the last paragraph of plain runs (or `w:proofErr` marks;
  no other inline, field, drawing or `w:sectPr`), other than the edited one,
  with `Replaced by the model`. In a document with a table (the
  first top-level `DocxTable` with a cell) it sets the text of the first
  cell's first paragraph to `Edited cell`, through that paragraph's first
  run or a new one, and appends a row `New row` when the table has a grid
  (`addRow`; left out otherwise). In every document it adds to `section.footer`
  of the last section (the story it has, its own or inherited, or a new one) a
  paragraph `Page ` + `PAGE` + ` of ` + `NUMPAGES`, then `addSection()` (next
  page) and makes the new last section landscape A4. In that section it appends
  a table `addTable(columns: 2)`, whose width follows the landscape page, of a
  header row `Head one`, `Head two`, a body row and a third row merged across
  both columns; a paragraph `A picture, links to jet_office and the added
  heading.` holding a 4 by 2 pixel PNG (`addPicture`, 3 by 1.5 points), an
  external link `jet_office` to `https://example.com/jet-office` and an
  internal link `the added heading` to the bookmark `Model_edit`
  (`addHyperlink`); a paragraph `Added by the model` of the style
  `styles.ensure(DocxBuiltInStyle.heading1)` (`Balk1` in a Turkish Word file;
  Word's definition when the file has none), its text inside the bookmark
  `Model_edit` (`addBookmarkStart`, `addBookmarkEnd`); and a bullet list
  (`numbering.addBulletList`) of two items, `First item` and `Second item` at
  level 1 (`addListItem`). It sets the document properties' title to `Edited
  by the model`, keeping every other property (`OfficeProperties`). It saves
  to the second directory, reads the saved file back and checks the text, bold
  and accent of the run, the replacing paragraph, the heading's style and its
  bookmark (start and end sharing an id), the picture (the PNG at its size),
  the two links' targets, each item's text, list number and level, the cell
  text, the new row, the added table's rows (header flag, texts, merge) and
  width, the section count, the new section's page and start, the break before
  the table, the footer paragraph in the section that was last and, inherited,
  in the new one, the title, and that the body has five blocks more (the
  table, the paragraph of the picture and links, the heading, the two items),
  or six when its last block could not take the break (a table, or a paragraph
  with a break) and `addSection` added a paragraph. `comparePackages` must
  find differences only in the main part (named by the root relationship), the
  numbering part, the styles part when `ensure` added a style (`Heading1`,
  `TableGrid` and `Normal Table`, or `Hyperlink`), one footer part, the core
  properties part (and, when the file lacks it, `_rels/.rels` and the extended
  properties part when the file lacks that too), at most one media part the
  file lacked (none when it has the PNG: the picture shares it),
  `[Content_Types].xml` when a part was created, and the main part's
  relationships, which may only gain relationships of the hyperlink and image
  types, and of the footer, styles and numbering types when such a part was
  created: one that goes or changes, or one of another type, is a problem. It
  prints each problem as `<file>: <problem>` and exits 1 on any, 2 on unusable
  arguments. CI runs it on the fixtures, on LibreOffice's re-save and on the
  owner's Word files, and validates the three outputs with the Open XML SDK;
  the owner opens the edited owner files in Word (`docs/word-checks.md`).
- `tool/draft_expected_docx.dart` drafts the `<name>.expected.txt` of an owner
  file from the model's own reading and prints a review list; it never
  overwrites an existing text.
- `tool/write_large_docx.dart <out-dir>` writes `large.docx` for the owner's
  Word check of D6: the owner's `long.docx` scaled to about 40,000 paragraphs
  by `scaledLongDocx` (`test/docx/support/large_document.dart`, the
  benchmark's own scaling), with one paragraph edited by the model. It is not
  part of the CI chain; `dotnet run --project tool/ooxml_validate --
  build/d6/benchmark` validates its output. Exit 2 on unusable arguments, 1 on
  any error.
- `tool/write_list_into.dart <in-dir> <out-dir>` writes a fixed Turkish list
  (`turkishList()`: a logo, a title, a date, a caption, three rows and a totals
  row) with `DocxListExport.writeTo` into every `.docx` of the first directory
  and saves it to the second, for the owner's Word check of D6 on real files
  (`build/d6/list-into-owner` from `test/fixtures/owner/docx`;
  `dotnet run --project tool/ooxml_validate -- build/d6/list-into-owner`
  validates it). It is not part of the CI chain;
  `test/docx/list_into_owner_test.dart` (VM) holds the same check as tests.
  Exit 2 on unusable arguments, 1 on any error.
- `packages/jet_charts_flutter/example/tool/write_excel_gallery.dart <dir>`
  writes `gallery.xlsx`, the charts of the chart gallery app
  (`packages/jet_charts_flutter/example`, its README) as Excel's own default
  charts, for the owner's side-by-side check against Excel for Mac (steps in
  its `TALIMATLAR.md`; the result goes in
  `packages/jet_charts_core/docs/excel-checks.md`, from the owner only). The
  Open XML SDK must report no error on it. Exit 2 on unusable arguments.
- The number formatter's tools and its Excel oracle (the owner's Excel for
  Mac CSVs, the LibreOffice comparison, the oracle workbook writer) are in
  `jet_core` (decision 0012); see its `AGENTS.md` and `docs/number-format.md`.
  `jet_office` keeps `test/xlsx/cell_formatting_test.dart`, which tests the
  `formatCell` extension and the warning and colour mappings.
- `docs/warning-messages.md` lists every warning message in `en`, `de` and
  `tr`, for the native-speaker check recorded in `docs/excel-checks.md`. It is
  generated: after a message changes, run
  `dart run tool/warning_messages.dart > docs/warning-messages.md`.
  `test/tool/warning_messages_test.dart` fails when the file is stale.
- Neither is Excel. The owner opens each writer milestone's fixtures in Excel
  and records the result in `docs/excel-checks.md`; so does each model milestone
  (W1 to W6, decision 0009): its round-tripped and generated workbooks, and the
  owner's own files opened, edited and saved. Reader milestones (phase 2, R1 to
  R4) have no such check: Excel produces their input, and the owner supplies
  Excel and Google Sheets files instead (`0007`). Those files go in
  `test/fixtures/owner/`, listed in its `manifest.json`; the README there says
  which workbooks to save and how the expected values are written and confirmed
  (`tool/draft_expected.dart` drafts them). Never edit a committed owner file or
  its expected JSON without the owner.
- Neither is Word. The owner opens each D milestone's fixtures
  (`build/fixtures/d1_*.docx`, `d2_*`, `d3_*`, `d4_*`, `d5_*`, `d6_*`; D4, D5
  and D6 write theirs under `build/d4/`, `build/d5/` and `build/d6/`), the
  model's round trips of them and of the owner's Word files, and the model's
  edits of the owner's Word files in Word for Mac, and records the result in
  `docs/word-checks.md`, which says how to write them. A repair prompt there is
  a model or writer bug, as in Excel's case. A body that ends in a table cannot
  be a fixture (LibreOffice's text export never ends on one) and Word cannot
  save one, so `dart run tool/write_table_last.dart build/table-last` writes
  `d3_table_last.docx` for that check alone, and `d4_break_last.docx`, a body
  whose last block carries a section break, which no fixture may be either;
  never run `soffice` on that folder.
- Word files go in `test/fixtures/owner/docx/`, listed in its
  `manifest.json`, each with `<name>.expected.txt`, the text of the body's
  paragraphs (`test/fixtures/owner/README.md`, section "Word files", says
  how). They are `blank.docx`, `features.docx`, `long.docx` and, for D2's
  built-in styles and lists, `builtins.docx` (the README says how it was
  made). `tool/draft_expected_docx.dart` drafts each text from the model's
  reading;
  the owner confirms every line against Word and sets `confirmedBy`. Never
  edit a committed Word file, its expected text or its manifest entry
  without the owner.

## Benchmark

`benchmark/` writes 100,000 rows of 12 mixed columns with `XlsxWriter` and
`XlsxStreamWriter` (`xlsx_benchmark_test.dart`), and reads that file back with
`XlsxReader` (`xlsx_read_benchmark_test.dart`, with the time of each phase and
memory per byte of sheet XML). `xlsx_model_benchmark_test.dart` opens that file
with `XlsxWorkbook`, loads the sheet, reads every row, sets a cell and saves,
timing each phase and recording what the loaded store retains, for that sheet
and for a formula-dense one. `xlsx_read_worst_case_test.dart`
reads the largest single sheet the default limits accept (about 250 MiB of XML;
about 20 s, and about 2.3 GB of heap in Chrome). Each prints time, file size and
peak memory per run. `docx_benchmark_test.dart` builds a 10,000 x 12 table
with `addTable` and `addRow`, saves it, opens the bytes and reads every cell,
printing time, file size and memory per phase. `docx_model_benchmark_test.dart`
scales the owner's `long.docx` to about 40,000 paragraphs, opens it, loads the
body, changes one paragraph, saves and reopens the saved bytes, timing each
phase. `xlsx_format_benchmark_test.dart` times `NumberFormatter.formatCell`
on every cell of the read file (the benchmark of synthetic values is in
`jet_core`). `xlsx_model_generate_benchmark_test.dart` generates 100,000 and
1,000,000 rows of 12 columns with `XlsxWorkbook()` and saves them, beside the
two writers, with links, rules and structural edits timed on the generated
sheet. The quality gate does not run them; run them by hand on the VM and
in Chrome (`dart test benchmark` runs all eight). They record figures and fail
on none (`docs/benchmark.md`):

```bash
dart test benchmark
dart test -p chrome benchmark
```

## Fuzzing

`test/xlsx/read/fuzz_test.dart` mutates a corpus of fixtures and producer
files (`test/xlsx/read/support/fuzz.dart`; `c1_kinds` among them, with its
twelve chart parts) and requires the reader to throw nothing but
`XlsxReadException`. The gate runs seeds 1 to 4 with 500 cases each, the same
cases on the VM and in Chrome (except the two deflated corpus entries, whose
cases may differ by platform, decision 0006). It ran 100 until `c1_kinds`
joined the corpus: the fixed seeds must mutate every part name of the corpus
(`every part name is mutated in some corpus entry`), and 400 left
`xl/charts/chart12.xml` unmutated; raise the count again when a new entry
makes that test fail. For longer runs, by hand:

```bash
dart run tool/fuzz_reader.dart --seeds 1-200 --cases 1000
```

It prints each failure as `seed <s> case <i> (<mutation>): <error>` and
exits 1 on any. A failure is a reader defect: pin it as a unit test in the
owning `*_test.dart` with the input minimized by hand, then fix it.

The number formatter's fuzz test and `tool/fuzz_formatter.dart` are in
`jet_core` (decision 0012).

The chart layout's fuzz test and `tool/fuzz_layout.dart` are in
`packages/jet_charts_core` (its `AGENTS.md`, "Fuzzing").

`test/drawingml/chart/chart_fuzz_test.dart` fuzzes the chart reader and the
chart part handle (C1, `test/drawingml/chart/support/chart_fuzz.dart`; seeds 1
to 4, 100 cases each). Its corpus is text, never a ZIP: the two Excel parts of
`excel_charts.dart` and every chart of `c1_kinds` and `c1_options` as the
writer writes it, each read in its own theme. The mutations are the reader
fuzz's on the part's bytes, and an attribute's value or an element's text
replaced by `abc`, twenty digits, `-`, `NaN` or `1e999`.
`readDrawingChartSpace` must throw nothing; a typed form must write a part
that reads as the same typed form again; `DrawingChart.opened` must read as
the reader does and encode the bytes unchanged. A fingerprint of the cases
proves the VM and Chrome get the same ones; a change to the writer or to the
C1 fixtures' charts changes it. Longer runs, by hand:

```bash
dart run tool/fuzz_chart.dart --seeds 1-200 --cases 1000
```

It prints each failure as `seed <s> case <i> (<mutation>): <error>` and exits
1 on any, 2 on bad arguments. Pin a failure as a unit test in the owning
`*_test.dart` first.

`test/xlsx/model/feature_fuzz_test.dart` fuzzes the model's sheet and
workbook features (seeds 1 to 4, 100 cases each, over the `m3_*` and `m4_*`
fixtures, `c1_kinds`, a sheet as Excel writes it and the `excel_objects`
producer file:
whole mutated files, many of them well formed so they reach the features' own
parsers; open, then reading, setting, undoing and saving every W3 and W4 member
throw nothing but `XlsxReadException`, and undoing the edits of a file restores
it, all but what the mutated part itself may lose: `undoDifferences`; since W5
it also inserts rows, deletes a column, renames and moves the first sheet and
removes a table, where only the `StateError`s a structural edit documents for
what it refuses may come out besides), the same cases on the VM and in Chrome;
longer runs by hand:

```bash
dart run tool/fuzz_reader.dart --features --seeds 1-200 --cases 1000
```

It prints failures as the reader's run does. Pin a failure as a unit test in
the owning `*_test.dart` first.

`test/xlsx/formula/formula_lexer_fuzz_test.dart` fuzzes the formula lexer
(W5; seeds 1 to 4, 1000 strings each, mutated from formulas as the fixtures,
producer files and Excel's documentation write them, over an alphabet of
reference, string, error, array and structured reference characters, a
non-ASCII letter and a lone surrogate): the lexer must never throw, and its
tokens must join back to the input with no gap or empty token. A digest of the
cases proves the VM and Chrome get the same strings and tokens, and a formula
past the length limit must lex in bounded time. Pin a failure as a unit test
in `test/xlsx/formula/formula_lexer_test.dart` first.

`test/docx/fuzz_test.dart` does the same for `DocxDocument` (seeds 1 to 4, 900
cases each, over the fixtures (the `d3_*`, `d4_*`, `d5_*` and `d6_*` ones among
them), a hand-made table with every element of the table values, a hand-made
`sections_by_hand` (every section child, six stories, broken references and
broken fields), a hand-made `drawings_by_hand` (inline, anchored, linked and
broken pictures, external, anchor and broken hyperlinks, bookmarks with bad ids,
a header with a picture and a link, and properties parts with values that cannot
be read), and the producer variants of `test/docx/support/docx_fuzz.dart`: whole
mutated files, with every part name mutated somewhere, and about a third of the
cases replacing the value of a `w:` attribute (`w:val`, `w:w`, `w:left` and the
like) of the main, styles or numbering part, or an attribute or element text of
a `docProps` part, by `abc`, twenty digits, `-` or `1in`; open, load the body,
styles, numbering and properties, then read every typed property (a throw there
is a failure, even a `DocxReadException`), including every table's, row's and
cell's properties and grid, walking cells and nested tables, every picture,
hyperlink and bookmark, every property field, and every section's typed values,
`evenAndOddHeaders` and its six stories with their fields (a throw there is a
failure, except a `DocxReadException` from the blocks of a story part that
cannot be read, as from a load); call `styles.ensure` and
`numbering.addBulletList` on what loaded, and set the properties; add a row to
each loaded table and merge ranges of its cells (only `ArgumentError` may come
out of those two); set every field's `resultText`, add a footer paragraph and
call `addSection` (nothing but that `DocxReadException` may come out of them);
add a picture, a bookmark pair and two hyperlinks to a body paragraph and to the
last footer's paragraph; and save (never a `StateError`, even for a table the
file left without rows; a `DocxReadException` naming a story's relationships
part that cannot be read, when a picture or link went in that story, plan D5's
ledger Ruling H, after which the walk takes them out and saves again), throw
nothing but `DocxReadException` from a load), and check the saved file holds
what was added, the same cases on the VM and in Chrome; longer runs by hand:

```bash
dart run tool/fuzz_docx.dart --seeds 1-200 --cases 1000
```

It prints each failure as `seed <s> case <i> (<mutation>): <error>` and exits
1 on any. Pin a failure as a unit test in the owning `*_test.dart` first.

The gate runs 900 cases per seed, not 150, for one reason: the seeds are fixed,
so the cases must between them mutate every part name of the corpus
(`every part name is mutated in some corpus entry`), and the D3 fixtures,
`tables_by_hand`, the D4 fixtures, with their header and footer parts,
`sections_by_hand` and the D5 fixtures joined the corpus and made fewer too few
(with the D5 fixtures, 600 left `word/footer4.xml` of `d4_headers` unmutated;
with the D6 ones, 750 left `word/_rels/footer1.xml.rels` unmutated).
When a new part name or corpus entry joins the corpus, run that test and raise
the count again if it fails.

In Chrome the runner loads every suite in a same-origin iframe of one page,
so all suites share one thread. A test that holds it for over 30 seconds makes
whatever suite is loading meanwhile fail with "Timed out waiting for browser
to load test suite", though nothing is wrong with that suite. The DOCX fuzz
loop's 3,600 cases held it for about a minute, and on 2026-11-10
`test/docx/model/list_helpers_test.dart` and `test/docx/round_trip_test.dart`
failed to load that way (exit code 1). So every long fuzz loop awaits
`EventLoopBreather.breathe()` (`test/support/event_loop.dart`) after each
case, which gives the other suites a turn about once a second. A new long
synchronous loop must do the same.

## Hard rules

- **Pure Dart, web-safe.** Nothing under `lib/` imports `dart:io`, `dart:ui`,
  `dart:html` or any Flutter library. Bytes in, bytes out. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **The public API is exactly what `lib/jet_office.dart` exports.**
  Everything under `lib/src/` is private.
- **`package:archive` is reachable only from
  `lib/src/zip/archive_adapter.dart`.** Enforced by
  `test/architecture/archive_isolation_test.dart`.
- **Runtime dependencies are `archive`, `jet_core` and `jet_charts_core`**
  (decisions 0012 and 0014), the last two packages of this workspace
  (`packages/jet_core`, decision 0013, and `packages/jet_charts_core`; each has
  its own `AGENTS.md`). Enforced by `test/architecture/dependencies_test.dart`.
- **The OPC layer does not know XLSX.** Nothing under `lib/src/opc` imports
  anything under `lib/src/xlsx`, so DOCX can share it (decision 0009).
  Enforced by `test/architecture/opc_isolation_test.dart`.
- **The format layers depend one way.** Nothing under `lib/src/docx/` imports
  `lib/src/xlsx/` (the number formatter is `package:jet_core`, decision 0012);
  nothing under `lib/src/common/` imports `lib/src/xlsx/`, `lib/src/docx/` or
  the barrel; `lib/src/drawingml/` (the DrawingML both formats
  share, decision 0014) imports only `dart:`, its own files, `../opc/`,
  `../xml/`, `../common/`, `package:jet_charts_core/jet_charts_core.dart` and
  `package:jet_core/jet_core.dart` (decision 0015);
  nothing under `lib/src/` imports `lib/jet_office.dart`.
  Enforced by `test/architecture/layering_test.dart`.
- **One cell encoder.** Only `lib/src/xlsx/cell_encoder.dart` writes `<c ` or
  `<v>` (decision 0002). Enforced by `test/architecture/cell_encoder_test.dart`.
- **One cell decoder.** Only `lib/src/xlsx/read/cell_decoder.dart`
  interprets a cell's or a formula's `t` attribute (decision 0007). Enforced by
  `test/architecture/cell_decoder_test.dart`.
- **Every reference is held.** Every model file that stores a range, a
  `sqref` or a formula is covered by a reference holder, so a structural edit
  (W5) moves it. Enforced by `test/architecture/reference_holders_test.dart`.
- **No undo stack in the library** (decision 0009): the change log keeps ids
  of change sets, never the sets. Enforced by
  `test/architecture/change_log_history_test.dart`.
- **Every warning code has a message in `en`, `de` and `tr`.** Enforced by
  `test/architecture/warning_messages_test.dart`.
- **Tests come first.** Write the failing test, watch it fail, then implement.
  A ported Quds defect is fixed with a regression test first.
- **Ported files carry provenance.** The library doc comment names the Quds
  source path and commit (`15c5d29` unless a later one is recorded). `NOTICE`
  keeps Quds' MIT licence text.
- **Port, don't copy.** A Quds file is not added until it has real dartdoc
  (not "`foo` API."), tests, and passes the lints. Do not port modules outside
  the current phase (phase 1 scope: `docs/decisions/0003`).
- **Data problems warn, programmer errors throw.** See the table in
  `docs/xlsx-writer.md`, "Rules the writer enforces".
- **Decisions live in `docs/decisions/`.** An accepted record is never edited;
  write a new one that supersedes it.

## Reference

The DOCX model's rules, each with its test, are in `docs/docx-model.md`; the
Word check is in `docs/word-checks.md`. The chart layer's rules and what C2 and
C3 must do are in `docs/drawingml-charts.md`.
Equations (OMML), parked for later (decision 0019), are analysed in
`docs/equations.md`.
Shapes, text boxes and icons (Insert > Shapes and Icons), parked for later
(decision 0021), are analysed in `docs/shapes.md`.

Quds is cloned read-only next to this repo at `../quds_office_suite`. The port
map for the writer is in `docs/xlsx-writer.md`, "Port map"; the reader's is in
`docs/xlsx-reader.md`, "Port map", with the rules the reader enforces. Read
the Quds file before porting it, and never import from it.

`docs/superpowers/` is git-ignored: working designs and plans live there and
are not repository history. Knowledge that must outlive a branch goes in a
tracked page under `docs/`, a decision record, or this file.