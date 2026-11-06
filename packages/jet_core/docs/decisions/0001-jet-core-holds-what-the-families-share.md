# 0001 — jet_core holds what the families share

**Status:** Accepted — 2026-11-06

## Context

`jet_office` wrote a number format engine (its decision 0008): it shows a
value as Excel for Mac does, from a number format code, a locale and a date
system. It lived under `lib/src/xlsx/format/` and named its inputs and results
with XLSX types (`XlsxDecimal`, `XlsxErrorValue`, `XlsxColor`, warning codes,
`XlsxReadCell`).

The charts need the same engine for axis and label formatting
(`jet_charts`), and Monépro needs Excel format codes for its charts and its
lists. None of them should depend on a package that reads and writes XLSX and
DOCX to format a number. At the same time the engine is not a part of a file
format: a format code is a string and a value is a value. The owner chose to
extract it, and to extract it as a package that can take other things two
families share, under a rule that keeps it small.

## Decision

**`jet_core` is a pure-Dart package of building blocks shared by the jet_
packages. It starts with the number format engine, extracted from
`jet_office`.**

- **The rule for adding to it.** Two families really use it, and it knows no
  file format. Code that only one family needs stays in that family's package;
  code that names XLSX, DOCX or any other format does not belong in `jet_core`.
  Warnings, read limits, the OPC layer, `OfficeLocale` and colour maths with
  `XlsxColor` stay in `jet_office`. A candidate is decided when a second
  family needs it, not before.
- **Neutral value types.** The engine takes and returns plain types:
  `FormatDecimal` (an exact decimal, digit for digit), `FormatErrorValue`
  (`#N/A` and its kin), `FormatColor`, `FormatWarning` and `FormattedValue`
  with its parts. No `Xlsx…` name appears in `lib/`, except where text
  explains history. `jet_office`'s `XlsxDecimal` and `XlsxErrorValue` will
  extend the neutral types, so a value read from a file reaches the engine with
  no conversion; `formatCell`, which takes a read cell, stays in `jet_office` as
  a thin wrapper. `jet_office` is unpublished, so its old names go and no alias
  is left behind.
- **No runtime dependencies.** `dependencies:` stays empty and nothing under
  `lib/` imports a `package:` other than `package:jet_core/`, nor `dart:io`,
  `dart:ui`, `dart:html` or Flutter. Values in, text out: it runs on the web,
  desktop, mobile and server alike, which the Chrome leg of the quality gate
  proves at run time. `archive`, `xml` and `test` are dev dependencies for
  tests and tools.
- **The Excel oracle moves with the engine, byte for byte.** The owner's Excel
  for Mac CSVs, `manifest.json` and `cases.json` under
  `test/fixtures/owner/number_format/` were copied, not edited, and the oracle
  test passes with the same `knownDifferences`. Excel wins over any other
  producer; a committed owner file is never edited without the owner.
- **Oracle workbooks come from a tool-local writer.** `jet_core` has no XLSX
  writer and depends on none, so `tool/src/format_oracle.dart` writes the
  oracle workbooks itself with a few hundred lines over `archive` (a dev
  dependency). It writes what Excel needs and throws rather than write a file
  Excel would repair: a text over 32,767 characters or a code over 255. It is
  a tool of the oracle, not a library: it is not exported and is not the
  start of a writer.
- **Repository and dependency form.** `jet_core` is its own repository
  (`~/Projects/oss/jet-core`), not published to pub.dev. A GitHub repository
  (`a-urel/jet-core`) is planned and does not exist yet. Until it does,
  `jet_office` will depend on it by path (`jet_core: {path: ../jet-core}`);
  once it exists, through a git dependency. Publishing is decided later and
  needs a new decision.

## Consequences

- A change to how Excel shows a value is made once, in `jet_core`, with the
  unit test that records Excel's text first, and every consumer gets it.
- `jet_office`'s public API will lose the `XlsxNumberFormatter` family of
  names and re-export the neutral ones. Its warning codes for number formats
  will map one for one onto `FormatWarning`, and keep their messages in `en`,
  `de` and `tr` there.
- The fuzz corpus no longer reads workbook fixtures. Its eight fixture codes
  are constants (`test/format/support/fixture_codes.dart`), and the length and
  hash of the whole corpus are pinned, so a seed gives the cases it gave in
  `jet_office`.
- Two repositories mean two quality gates and a manual step when the engine
  changes: run `jet_office`'s gate against the new `jet_core` before it merges.
- Anything added to `jet_core` later must pass the rule above, and a decision
  record says why.
