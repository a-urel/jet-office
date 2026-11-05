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
model, on the same fidelity standard) before any design change.

Consumers: Monépro (list and dashboard export, spreadsheet import, document
templates) and later `jet_print` (report export to XLSX/DOCX). `jet_office`
knows nothing about either of them.

## The quality gate

Run from the repository root. A clean checkout must pass all four:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart test -p chrome
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
dart run tool/write_format_oracle.dart build/format_oracle
LC_ALL=C.UTF-8 soffice --headless \
  --convert-to 'csv:Text - txt - csv (StarCalc):44,34,UTF8,1,,0,false,true,true,false,false,1' \
  --outdir build/format_oracle build/format_oracle/*.xlsx
dart run tool/compare_format_libreoffice.dart build/format_oracle
LC_ALL=C.UTF-8 soffice --headless --convert-to 'txt:Text (encoded):UTF8' \
  --outdir build/fixtures build/fixtures/*.docx
dart run tool/compare_text.dart build/fixtures
mkdir -p build/resaved-docx
LC_ALL=C.UTF-8 soffice --headless --convert-to 'docx:MS Word 2007 XML' \
  --outdir build/resaved-docx build/fixtures/*.docx
dart run tool/compare_resaved_docx.dart build/fixtures build/resaved-docx
dart run tool/round_trip_docx.dart build/fixtures build/model-docx-fixtures
dart run tool/round_trip_docx.dart build/resaved-docx build/model-docx
dart run tool/round_trip_docx.dart test/fixtures/owner/docx build/model-docx-owner
dotnet run --project tool/ooxml_validate -- build/model-docx-fixtures
dotnet run --project tool/ooxml_validate -- build/model-docx
dotnet run --project tool/ooxml_validate -- build/model-docx-owner
dart run tool/edit_docx.dart build/fixtures build/edited-docx-fixtures
dart run tool/edit_docx.dart build/resaved-docx build/edited-docx
dart run tool/edit_docx.dart test/fixtures/owner/docx build/edited-docx-owner
dotnet run --project tool/ooxml_validate -- build/edited-docx-fixtures
dotnet run --project tool/ooxml_validate -- build/edited-docx
dotnet run --project tool/ooxml_validate -- build/edited-docx-owner
```

- `tool/write_fixtures.dart` writes each fixture of `allFixtures()`
  (`test/fixtures/fixtures.dart`, which joins the milestone lists) as
  `<name>.xlsx` and its expected values as `<name>.expected.json`, and each
  DOCX fixture of `docxFixtures()` (`test/fixtures/docx_fixtures.dart`) as
  `<name>.docx` and its expected text as `<name>.expected.txt`.
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
- `tool/compare_csv.dart` compares LibreOffice's CSV export of every sheet
  with the expected values on raw values. Its doc comment explains the filter
  options; `tool/src/csv_compare.dart` holds the comparison and its contract.
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
  (when no filter or table is in the way) and the workbook's title (no
  protection: it would lock the owner's review), adds a sheet, saves to the
  second directory, and checks the edits read back with `XlsxReader` and the
  model; it also writes the generated workbooks of
  `tool/write_model_sample.dart`, `w1_generated.xlsx`, `w2_generated.xlsx`
  and `w3_generated.xlsx` (a `Report` sheet with a filter, a validation, the
  four conditional rule kinds, two links, print settings, header and footer,
  and a formula using a workbook name; a protected `Locked` sheet; workbook
  properties), there. It prints each
  problem as `<file>: <problem>` and exits 1 on any, 2 on unusable
  arguments. CI runs it on the fixtures and validates the output with the
  Open XML SDK, so the model's edited and generated files are validated,
  not only its unchanged round trips.
- `tool/compare_text.dart` compares LibreOffice's text export of every DOCX
  fixture (`txt:Text (encoded):UTF8`) with its `<name>.expected.txt`, by
  `textDifferences` in `tool/src/text_compare.dart`: a leading BOM and one
  trailing newline are ignored, everything else must be equal. It prints
  each difference as `<name>: <line>`, exits 1 on any, 2 on unusable input.
- `tool/compare_resaved_docx.dart` opens LibreOffice's DOCX re-save of every
  fixture with `DocxDocument` and compares the body's text with the expected
  text; any warning is a mismatch unless `docxResaveAllowedWarnings` in
  `tool/src/read_compare.dart` names it with a reason. Exit codes as above.
- `tool/round_trip_docx.dart` opens every `.docx` of a directory with
  `DocxDocument`, reads the body, saves to the second directory and prints
  each `comparePackages` difference (`tool/src/part_compare.dart`) as
  `<file>: <line>`; it exits 1 on any difference or error, 2 on unusable
  arguments. CI runs it on the fixtures, on LibreOffice's re-save and on the
  owner's Word files, then validates all three outputs with the Open XML
  SDK. As for workbooks, the `d1_corrupt.docx` document round-trips (exit 0)
  and the SDK must reject the output; a truncated copy is the round trip's
  own negative control.
- `tool/edit_docx.dart` opens every `.docx` of a directory with
  `DocxDocument`, sets the text of the first run with text, replaces the
  last paragraph of runs only with a new one, adds a paragraph of style
  `Heading1` (`Normal` when `word/styles.xml` defines no `Heading1`), saves
  to the second directory, and checks the edits read back and that
  `comparePackages` finds differences in `word/document.xml` only. It
  prints each problem as `<file>: <problem>` and exits 1 on any, 2 on
  unusable arguments. CI runs it on the fixtures, on LibreOffice's re-save
  and on the owner's Word files, and validates the three outputs with the
  Open XML SDK; the owner opens the edited owner files in Word
  (`docs/word-checks.md`).
- `tool/draft_expected_docx.dart` drafts the `<name>.expected.txt` of an owner
  file from the model's own reading and prints a review list; it never
  overwrites an existing text.
- `tool/compare_format_libreoffice.dart` compares the number formatter with
  LibreOffice's text "as shown" of the oracle cases
  (`test/fixtures/owner/number_format/`), exported from the workbooks
  `tool/write_format_oracle.dart` writes, and lists every difference. It
  reports and never fails: LibreOffice is a second opinion, not Excel, so
  it exits 0 with differences (2 only on unusable input) and its CI steps
  have `continue-on-error`. Its doc comment explains the filter options.
- The number formatter's oracle is Excel for Mac, not LibreOffice.
  `test/xlsx/format/oracle_test.dart` (in the gate, VM only) compares it
  with the owner's Excel CSVs of the oracle workbooks, per region; a region
  without a manifest entry prints `unverified` and passes. The README under
  `test/fixtures/owner/number_format/` says how the owner runs them.
  Excel wins: a mismatch is fixed with a test, or recorded in the test's
  `knownDifferences` with a reason. Never edit a committed CSV or manifest
  entry there without the owner (`docs/number-format.md`, "Excel as the
  oracle").
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
  (`build/fixtures/d1_*.docx`), the model's round trips of them and of the
  owner's Word files, and the model's edits of the owner's Word files in
  Word for Mac, and records the result in
  `docs/word-checks.md`, which says how to write them. A repair prompt there
  is a model or writer bug, as in Excel's case.
- Word files go in `test/fixtures/owner/docx/`, listed in its
  `manifest.json`, each with `<name>.expected.txt`, the text of the body's
  paragraphs (`test/fixtures/owner/README.md`, section "Word files", says
  how). `tool/draft_expected_docx.dart` drafts it from the model's reading;
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
peak memory per run. `xlsx_format_benchmark_test.dart` times
`XlsxNumberFormatter` on every cell of the read file and on 100,000 numbers,
serial dates and `DateTime`s. The quality gate does not run them; run them by
hand on the VM and in Chrome (`dart test benchmark` runs all five). They record
figures and fail on none (`docs/benchmark.md`):

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

`test/xlsx/format/fuzz_test.dart` does the same for `XlsxNumberFormatter`
(seeds 1 to 4, 200 cases each: mutated format codes and random values, in
three locales and both date systems; no throw, `text` of at most 1,000
characters, `parts` joined equal `text`);
longer runs with `dart run tool/fuzz_formatter.dart --seeds 1-200 --cases 1000`.
The rules are in `docs/number-format.md`.

`test/xlsx/model/feature_fuzz_test.dart` fuzzes the model's sheet and
workbook features (seeds 1 to 4, 100 cases each, over the `m3_*` fixtures and
a sheet as Excel writes it: whole mutated files, many of them well formed so
they reach the features' own parsers; open, then reading, setting, undoing and
saving every W3 member throw nothing but `XlsxReadException`, and undoing the
edits of a corpus file restores it), the same cases on the VM and in Chrome;
longer runs by hand:

```bash
dart run tool/fuzz_reader.dart --features --seeds 1-200 --cases 1000
```

It prints failures as the reader's run does. Pin a failure as a unit test in
the owning `*_test.dart` first.

`test/docx/fuzz_test.dart` does the same for `DocxDocument` (seeds 1 to 4,
100 cases each, over the fixtures and producer variants of
`test/docx/support/docx_fuzz.dart`: whole mutated files, with every part name
mutated somewhere; open, read the body and save throw nothing but
`DocxReadException`), the same cases on the VM and in Chrome; longer runs
by hand:

```bash
dart run tool/fuzz_docx.dart --seeds 1-200 --cases 1000
```

It prints each failure as `seed <s> case <i> (<mutation>): <error>` and exits
1 on any. Pin a failure as a unit test in the owning `*_test.dart` first.

## Hard rules

- **Pure Dart, web-safe.** Nothing under `lib/` imports `dart:io`, `dart:ui`,
  `dart:html` or any Flutter library. Bytes in, bytes out. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **The public API is exactly what `lib/jet_office.dart` exports.**
  Everything under `lib/src/` is private.
- **`package:archive` is reachable only from
  `lib/src/zip/archive_adapter.dart`.** Enforced by
  `test/architecture/archive_isolation_test.dart`.
- **The OPC layer does not know XLSX.** Nothing under `lib/src/opc` imports
  anything under `lib/src/xlsx`, so DOCX can share it (decision 0009).
  Enforced by `test/architecture/opc_isolation_test.dart`.
- **The format layers depend one way.** Nothing under `lib/src/docx/` imports
  `lib/src/xlsx/` except `lib/src/xlsx/format/` (the number formatter);
  nothing under `lib/src/common/` imports `lib/src/xlsx/`, `lib/src/docx/` or
  the barrel; nothing under `lib/src/` imports `lib/jet_office.dart`.
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