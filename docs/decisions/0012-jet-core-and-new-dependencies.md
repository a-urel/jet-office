# 0012 — The number format engine moves to jet_core, and the runtime dependencies are named

**Status:** Accepted — 2026-11-06

Supersedes the rule in [`0001`](0001-port-a-file-engine-from-quds.md) that
`archive` is the only runtime dependency, and the location and the names of
the engine in [`0008`](0008-number-format-engine.md). The rest of `0008` (what
the engine shows, and Excel for Mac as its oracle) still holds, and is now
kept in `jet_core`.

## Context

`0008` put the number format engine in `lib/src/xlsx/format/` and named its
inputs and results with XLSX types: `XlsxDecimal`, `XlsxErrorValue`,
`XlsxColor`, `XlsxWarningCode`, `XlsxReadCell`. The charts (`jet_charts`) need
the same engine for axis and label formatting, and Monépro needs Excel format
codes for its charts and its lists. None of them should depend on a package
that reads and writes XLSX and DOCX to format a number, and a format code is a
string and a value is a value: the engine is not a part of a file format.

The owner chose to extract it, and to extract it as a package that can take
other things two families share
(`docs/superpowers/specs/2026-11-04-jet-charts-design.md`, section 4.5).
`jet_core`'s own record
(`docs/decisions/0001-jet-core-holds-what-the-families-share.md` in
`../jet-core`) states the rule for what it holds. This record is
`jet_office`'s side of the same move.

## Decision

**`jet_office` depends on `jet_core` for number formats. The runtime
dependencies are `archive` and `jet_core`, and later `jet_charts_core`, by its
own record.**

- **What moved.** Everything under `lib/src/xlsx/format/`: the formatter, the
  format code parser, the number, date and text renderers, the locales, the
  built-in codes, `classifyFormatCode` and `FormatKind`. With it went its
  tests, its fuzz test and tool, its benchmark of synthetic values, the page
  `docs/number-format.md`, and the Excel oracle: the owner's CSVs,
  `manifest.json` and `cases.json` (copied byte for byte, checksums compared)
  and the tools that write the oracle workbooks and compare them with
  LibreOffice. `jet_office` no longer writes oracle workbooks. `jet_core` has
  no XLSX writer, so its oracle tool carries a small writer of its own.
- **What stayed.** Warnings, read limits, the OPC layer, `OfficeLocale`, and
  colour maths with `XlsxColor`. XLSX knowledge about formats stays in one
  small file, `lib/src/xlsx/cell_formatting.dart`, as extensions: `formatCell`
  on `NumberFormatter` (it takes an `XlsxReadCell`), `FormatWarning.xlsxCode`
  (each `FormatWarning` maps to its old `XlsxWarningCode`, one for one, and
  the message stays in `en`, `de` and `tr` here), and `FormatColor.xlsxColor`.
  The benchmark of `formatCell` on a read workbook stays too, since it needs
  the reader.
- **Neutral value types.** The engine takes and returns `FormatDecimal`,
  `FormatErrorValue`, `FormatColor`, `FormatWarning` and `FormattedValue`.
  `XlsxDecimal` and `XlsxErrorValue` extend `FormatDecimal` and
  `FormatErrorValue`, so a value from the reader reaches the engine with no
  conversion, and the two are equal both ways. `jet_office` re-exports the
  public types of `jet_core` from `lib/jet_office.dart`. `jet_office` is
  unpublished, so the old names (`XlsxNumberFormatter`, `XlsxFormatLocale`,
  `XlsxFormattedValue` and their kin) are gone and no alias is left behind.
- **Output unchanged.** The engine's output for the same code, value, locale
  and date system is the same as before the move. The oracle test passes in
  `jet_core` with the same `knownDifferences`, and `jet_office`'s tests
  check the extensions and the equality of the value types.
- **Dependency form.** `pubspec.yaml` has `jet_core: {path: ../jet-core}`.
  The `jet-core` GitHub repository (`a-urel/jet-core`) does not exist yet.
  When it does, the dependency becomes a git dependency (`git: url: ...`, with
  a `ref`), in the same commit that removes the sibling-checkout assumption
  below. Publishing to pub.dev is decided later and needs its own record.
- **Layering.** The format layers' rule in `AGENTS.md` loses its exception:
  nothing under `lib/src/docx/` imports `lib/src/xlsx/`, because the number
  formatter, the one shared piece, is a package now. DOCX may import
  `package:jet_core` when it needs it. A test (`dependencies_test.dart`)
  holds the dependency list: `archive` and `jet_core`, and `archive` only
  through its adapter.

## Consequences

- **CI cannot pass until the `jet-core` repository exists.** `dart pub get`
  needs `../jet-core` beside the checkout, and a clean CI checkout has none.
  No workaround is added to the workflow. When the repository exists, the
  dependency changes to a git dependency and the workflow needs nothing else.
- **A worktree needs two things.** A git-ignored `pubspec_overrides.yaml` with
  an absolute path to `jet-core` makes `dart pub get` work from any directory,
  but `dart analyze` still checks the relative path of `pubspec.yaml`, so
  `../jet-core` must exist beside the worktree too (a symlink to the
  checkout).
- A change to how Excel shows a value is made once, in `jet_core`, with the
  unit test that records Excel's text first, and every consumer gets it. It is
  then a manual step to run `jet_office`'s gate against the new `jet_core`
  before the change is released.
- The format engine's documents (`docs/number-format.md`, the oracle README)
  and tools are in `jet_core`. Pointers here name the file there; they do not
  copy it.
- The warning messages for the format codes still live here and are still
  checked in `en`, `de` and `tr` (`docs/warning-messages.md`).
- `0001`'s rule is now: runtime dependencies are only what a decision names,
  and `archive` is reachable only from `lib/src/zip/archive_adapter.dart`.
  Adding a dependency needs a record.
