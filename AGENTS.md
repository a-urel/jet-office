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
under `packages/`, and a DrawingML layer here) before any design change.

`packages/jet_charts_core` is the pure-Dart chart core (decision 0014); it has
its own `AGENTS.md`, and this package does not depend on it until C1.

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
```

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
dotnet run --project tool/ooxml_validate -- build/model-resaved
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
```

- `tool/write_fixtures.dart` writes each fixture of `allFixtures()`
  (`test/fixtures/fixtures.dart`, which joins the milestone lists) as
  `<name>.xlsx` and its expected values as `<name>.expected.json`, and each
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
  with 1.27 cm margins, twelve columns and 40 rows). A fixture with a `DocxFixture.headerFooterText` (`d4_headers`,
  `d4_fields`, `d5_pictures`, `d5_links`, `d6_list`, `d6_list_landscape`) also
  gets `<name>.stories.txt`, what
  its headers and footers show. No fixture ends in a table, because
  LibreOffice's text export of one never ends (see below), or in a section
  break, as the model adds no block after one.
  `--corrupt` adds a deliberately broken `m1_corrupt.xlsx` and
  `d1_corrupt.docx`, to prove every check still fails on a bad file. The
  `validate` job's negative-control step writes `m1_corrupt.xlsx` to
  `build/corrupt` and requires every check to reject it, except the model
  round trip (`tool/round_trip_model.dart`), which passes on it: the model
  keeps the file's stray content faithfully, so the Open XML SDK must reject
  the model's output instead, and the round trip must reject a truncated
  copy. A second step does the same for `d1_corrupt.docx` in
  `build/corrupt-docx` (a `w:r` directly under `w:body`, and "first" spelled
  "firzt"), with `tool/compare_text.dart`, `tool/compare_resaved_docx.dart`
  and `tool/round_trip_docx.dart` in place of their XLSX counterparts.
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
  two elements, matched on the element and its exact value; every other error,
  and every run without the flag, counts. The `d1_corrupt.docx` negative
  control must still fail with it.
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
  the two rows below it, adds a sheet, saves to the second directory, and checks
  the edits read back with `XlsxReader` and the model; it also writes the
  generated workbooks of `tool/write_model_sample.dart`, `w1_generated.xlsx`,
  `w2_generated.xlsx`, `w3_generated.xlsx` (a `Report` sheet with a filter, a
  validation, the four conditional rule kinds, two links, print settings, header
  and footer, and a formula using a workbook name; a protected `Locked` sheet;
  workbook properties, `OfficeProperties`) and `w4_generated.xlsx` (an `Objects`
  sheet with rich text, a visible and a hidden note, a PNG and a JPEG as
  one-cell and two-cell pictures, a picture moved to a larger size, a table with
  totals and one without a style; a `Removed` sheet where a table and a picture
  were added and removed again), there. It prints each
  problem as `<file>: <problem>` and exits 1 on any, 2 on unusable
  arguments. CI runs it on the fixtures and validates the output with the
  Open XML SDK, so the model's edited and generated files are validated,
  not only its unchanged round trips.
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
  (`build/fixtures/d1_*.docx`, `d2_*`, `d3_*`, `d4_*`, `d5_*`; D4 and D5 write
  theirs under `build/d4/` and `build/d5/`), the model's round trips of them
  and of the owner's Word files, and the model's edits of the owner's
  Word files in Word for Mac, and records the result in
  `docs/word-checks.md`, which says how to write them. A repair prompt there
  is a model or writer bug, as in Excel's case. A body that ends in a table
  cannot be a fixture (LibreOffice's text export never ends on one) and Word
  cannot save one, so `dart run tool/write_table_last.dart build/table-last`
  writes `d3_table_last.docx` for that check alone, and `d4_break_last.docx`, a
  body whose last block carries a section break, which no fixture may be either;
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
printing time, file size and memory per phase. `xlsx_format_benchmark_test.dart`
times `NumberFormatter.formatCell` on every cell of the read file (the
benchmark of synthetic values is in `jet_core`). The quality gate does not run
them; run them by hand on the VM and in Chrome (`dart test benchmark` runs all
six). They record figures and fail on none (`docs/benchmark.md`):

```bash
dart test benchmark
dart test -p chrome benchmark
```

## Fuzzing

`test/xlsx/read/fuzz_test.dart` mutates a corpus of fixtures and producer
files (`test/xlsx/read/support/fuzz.dart`) and requires the reader to throw
nothing but `XlsxReadException`. The gate runs seeds 1 to 4 with 100 cases
each, the same cases on the VM and in Chrome (except the two deflated
corpus entries, whose cases may differ by platform, decision 0006). For
longer runs, by hand:

```bash
dart run tool/fuzz_reader.dart --seeds 1-200 --cases 1000
```

It prints each failure as `seed <s> case <i> (<mutation>): <error>` and
exits 1 on any. A failure is a reader defect: pin it as a unit test in the
owning `*_test.dart` with the input minimized by hand, then fix it.

The number formatter's fuzz test and `tool/fuzz_formatter.dart` are in
`jet_core` (decision 0012).

`test/xlsx/model/feature_fuzz_test.dart` fuzzes the model's sheet and
workbook features (seeds 1 to 4, 100 cases each, over the `m3_*` and `m4_*`
fixtures, a sheet as Excel writes it and the `excel_objects` producer file:
whole mutated files, many of them well formed so they reach the features' own
parsers; open, then reading, setting, undoing and saving every W3 and W4 member
throw nothing but `XlsxReadException`, and undoing the edits of a file restores
it, all but what the mutated part itself may lose: `undoDifferences`), the same
cases on the VM and in Chrome;
longer runs by hand:

```bash
dart run tool/fuzz_reader.dart --features --seeds 1-200 --cases 1000
```

It prints failures as the reader's run does. Pin a failure as a unit test in
the owning `*_test.dart` first.

`test/docx/fuzz_test.dart` does the same for `DocxDocument` (seeds 1 to 4,
900 cases each, over the fixtures (the `d3_*`, `d4_*`, `d5_*` and `d6_*` ones
among them), a hand-made table with every element of the table values, a hand-made
`sections_by_hand` (every section child, six stories, broken references and
broken fields), a hand-made `drawings_by_hand` (inline, anchored, linked and
broken pictures, external, anchor and broken hyperlinks, bookmarks with bad
ids, a header with a picture and a link, and properties parts with values that
cannot be read), and the producer variants of
`test/docx/support/docx_fuzz.dart`: whole mutated files, with every part name
mutated somewhere, and about a third of the cases replacing the value of a
`w:` attribute (`w:val`, `w:w`, `w:left` and the like) of the main, styles or
numbering part, or an attribute or element text of a `docProps` part, by
`abc`, twenty digits, `-` or `1in`; open, load the body, styles, numbering and
properties, then read every typed property (a throw there is a failure, even a
`DocxReadException`), including every table's, row's and cell's properties
and grid, walking cells and nested tables, every picture, hyperlink and
bookmark, every property field, and every section's typed values,
`evenAndOddHeaders` and its six stories with their fields (a throw there is a
failure, except a `DocxReadException` from the blocks of a story part that
cannot be read, as from a load); call `styles.ensure` and
`numbering.addBulletList` on what loaded, and set the properties; add a row to
each loaded table and merge ranges of its cells (only `ArgumentError` may
come out of those two); set every field's `resultText`, add a footer
paragraph and call `addSection` (nothing but that `DocxReadException` may come
out of them); add a picture, a bookmark pair and two hyperlinks to a body
paragraph and to the last footer's paragraph; and save (never a `StateError`,
even for a table the file left without rows; a `DocxReadException` naming a
story's relationships part that cannot be read, when a picture or link went
in that story, plan D5's ledger Ruling H, after which the walk takes them out
and saves again), throw nothing but `DocxReadException` from a load), and
check the saved file holds what was added, the same cases on the VM and in
Chrome;
longer runs by hand:

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

## Hard rules

- **Pure Dart, web-safe.** Nothing under `lib/` imports `dart:io`, `dart:ui`,
  `dart:html` or any Flutter library. Bytes in, bytes out. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **The public API is exactly what `lib/jet_office.dart` exports.**
  Everything under `lib/src/` is private.
- **`package:archive` is reachable only from
  `lib/src/zip/archive_adapter.dart`.** Enforced by
  `test/architecture/archive_isolation_test.dart`.
- **Runtime dependencies are `archive` and `jet_core`** (decision 0012), the
  second a package of this workspace (`packages/jet_core`, decision 0013; it has
  its own `AGENTS.md`). Enforced by `test/architecture/dependencies_test.dart`.
- **The OPC layer does not know XLSX.** Nothing under `lib/src/opc` imports
  anything under `lib/src/xlsx`, so DOCX can share it (decision 0009).
  Enforced by `test/architecture/opc_isolation_test.dart`.
- **The format layers depend one way.** Nothing under `lib/src/docx/` imports
  `lib/src/xlsx/` (the number formatter is `package:jet_core`, decision 0012);
  nothing under `lib/src/common/` imports `lib/src/xlsx/`, `lib/src/docx/` or
  the barrel; nothing under `lib/src/drawingml/` (the DrawingML both formats
  share, decision 0014) imports `lib/src/xlsx/`, `lib/src/docx/` or the barrel;
  nothing under `lib/src/` imports `lib/jet_office.dart`.
  Enforced by `test/architecture/layering_test.dart`.
- **One cell encoder.** Only `lib/src/xlsx/cell_encoder.dart` writes `<c ` or
  `<v>` (decision 0002). Enforced by `test/architecture/cell_encoder_test.dart`.
- **One cell decoder.** Only `lib/src/xlsx/read/cell_decoder.dart`
  interprets a cell's or a formula's `t` attribute (decision 0007). Enforced by
  `test/architecture/cell_decoder_test.dart`.
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
Word check is in `docs/word-checks.md`.

Quds is cloned read-only next to this repo at `../quds_office_suite`. The port
map for the writer is in `docs/xlsx-writer.md`, "Port map"; the reader's is in
`docs/xlsx-reader.md`, "Port map", with the rules the reader enforces. Read
the Quds file before porting it, and never import from it.

`docs/superpowers/` is git-ignored: working designs and plans live there and
are not repository history. Knowledge that must outlive a branch goes in a
tracked page under `docs/`, a decision record, or this file.