# Working in jet-office

`jet_office` is a pure-Dart library that generates, reads and modifies XLSX and
DOCX files. It has no editors, no rendering and no PDF. It is ported from
`quds_office_engine` (MIT); see `docs/decisions/0001` and `0002` before any
design change.

Consumers: Monépro (list and dashboard export, spreadsheet import, document
templates) and later `jet_print` (report export to XLSX/DOCX). `jet_office`
knows nothing about either of them.

## The quality gate

Run from the repository root. A clean checkout must pass all three:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Never report work as done without running these and reading the output.

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