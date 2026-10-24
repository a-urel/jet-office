# Working in jet-office

`jet_office` is a pure-Dart library that generates, reads and modifies XLSX and
DOCX files. It has no editors, no rendering and no PDF. It is ported from
`quds_office_engine` (MIT); see `docs/decisions/0001`, `0002` and `0003`
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
optional, because it needs the .NET SDK (8 or later) and LibreOffice:

```bash
dart run tool/write_fixtures.dart build/fixtures
dotnet run --project tool/ooxml_validate -- build/fixtures
LC_ALL=C.UTF-8 soffice --headless \
  --convert-to 'csv:Text - txt - csv (StarCalc):44,34,UTF8,1,,0,false,true,false,false,false,-1' \
  --outdir build/fixtures build/fixtures/*.xlsx
dart run tool/compare_csv.dart build/fixtures
```

- `tool/write_fixtures.dart` writes each fixture of
  `test/fixtures/m1_fixtures.dart` as `<name>.xlsx` and its expected values as
  `<name>.expected.json`. `--corrupt` adds a deliberately broken
  `m1_corrupt.xlsx`, to prove both checks still fail on a bad file.
- `tool/ooxml_validate` validates every `.xlsx` with the Open XML SDK against
  the Microsoft 365 schemas and fails on any error. An error there is a writer
  bug.
- `tool/compare_csv.dart` compares LibreOffice's CSV export of every sheet
  with the expected values on raw values. Its doc comment explains the filter
  options; `tool/src/csv_compare.dart` holds the comparison and its contract.
- Neither is Excel. The owner opens each milestone's fixtures in Excel and
  records the result in `docs/excel-checks.md`.

## Hard rules

- **Pure Dart, web-safe.** Nothing under `lib/` imports `dart:io`, `dart:ui`,
  `dart:html` or any Flutter library. Bytes in, bytes out. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **The public API is exactly what `lib/jet_office.dart` exports.**
  Everything under `lib/src/` is private.
- **`package:archive` is reachable only from `lib/src/zip/archive_adapter.dart`.**
  Enforced by `test/architecture/archive_isolation_test.dart`.
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