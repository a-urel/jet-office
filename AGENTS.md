# Working in jet-office

`jet_office` is a pure-Dart library that generates, reads and modifies XLSX and
DOCX files. It has no editors, no rendering and no PDF. It is ported from
`quds_office_engine` (MIT); see `docs/decisions/0001`, `0002`, `0003`,
`0004` (which supersedes part of `0003`), `0005` (which supersedes ruling
R10 in `docs/xlsx-writer.md`) and `0006` (ZIP bytes may differ by platform)
before any design change.

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
```

- `tool/write_fixtures.dart` writes each fixture of `allFixtures()`
  (`test/fixtures/fixtures.dart`, which joins the milestone lists) as
  `<name>.xlsx` and its expected values as `<name>.expected.json`.
  `--corrupt` adds a deliberately broken `m1_corrupt.xlsx`, to prove both
  checks still fail on a bad file. The `validate` job's last step writes it
  to `build/corrupt` and requires both checks to reject it.
- `tool/write_fixtures.dart` imports test helpers that use `package:archive`.
  That is allowed: the archive rule covers `lib/` only.
- `tool/ooxml_validate` validates every `.xlsx` with the Open XML SDK against
  the Microsoft 365 schemas and fails on any error. An error there is a writer
  bug.
- `tool/compare_csv.dart` compares LibreOffice's CSV export of every sheet
  with the expected values on raw values. Its doc comment explains the filter
  options; `tool/src/csv_compare.dart` holds the comparison and its contract.
- `docs/warning-messages.md` lists every warning message in `en`, `de` and
  `tr`, for the native-speaker check recorded in `docs/excel-checks.md`. It is
  generated: after a message changes, run
  `dart run tool/warning_messages.dart > docs/warning-messages.md`.
  `test/tool/warning_messages_test.dart` fails when the file is stale.
- Neither is Excel. The owner opens each milestone's fixtures in Excel and
  records the result in `docs/excel-checks.md`.

## Benchmark

`benchmark/` writes 100,000 rows of 12 mixed columns with `XlsxWriter` and
`XlsxStreamWriter` and prints time, file size and peak memory per run. The
quality gate does not run it; run it by hand on the VM and in Chrome. It
records figures and fails on none (`docs/benchmark.md`):

```bash
dart test benchmark
dart test -p chrome benchmark
```

## Hard rules

- **Pure Dart, web-safe.** Nothing under `lib/` imports `dart:io`, `dart:ui`,
  `dart:html` or any Flutter library. Bytes in, bytes out. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **The public API is exactly what `lib/jet_office.dart` exports.**
  Everything under `lib/src/` is private.
- **`package:archive` is reachable only from
  `lib/src/zip/archive_adapter.dart`.** Enforced by
  `test/architecture/archive_isolation_test.dart`.
- **One cell encoder.** Only `lib/src/xlsx/cell_encoder.dart` writes `<c ` or
  `<v>` (decision 0002). Enforced by `test/architecture/cell_encoder_test.dart`.
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

Quds is cloned read-only next to this repo at `../quds_office_suite`. The port
map is in `docs/xlsx-writer.md`, "Port map". Read the Quds file before porting
it, and never import from it.

`docs/superpowers/` is git-ignored: working designs and plans live there and
are not repository history. Knowledge that must outlive a branch goes in a
tracked page under `docs/`, a decision record, or this file.