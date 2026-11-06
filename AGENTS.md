# Working in jet-core

`jet_core` is a pure-Dart package of building blocks shared by the jet_
packages. Today that is one thing: the number format engine, extracted from
`jet_office` (its decision 0008; jet_core's `docs/decisions/0001`), which shows
a value as Excel for Mac does. It has no dependencies, no editors, no rendering
and knows no file format.

**The rule for adding to it:** two families really use it, and it knows no file
format. Code that only one family needs stays in that family's package; code
that names XLSX, DOCX or any other format does not belong here.

Consumers: `jet_office` (XLSX and DOCX), `jet_charts` (axis and label
formatting) and Monépro. `jet_core` knows none of them.

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

## The Excel oracle

The number formatter's oracle is Excel for Mac, not LibreOffice. The owner
saves the CSVs of the oracle workbooks in each region and commits them under
`test/fixtures/owner/number_format/`; the README there says how.

- `test/format/oracle_test.dart` (in the gate, VM only) compares the formatter
  with the owner's Excel CSVs, per region; a region without a manifest entry
  prints `unverified` and passes. Excel wins: a mismatch is fixed with a test,
  or recorded in the test's `knownDifferences` with a reason. Never edit a
  committed CSV, `manifest.json` or `cases.json` there without the owner
  (`docs/number-format.md`, "Excel as the oracle").
- `tool/write_format_oracle.dart <dir>` writes the oracle workbooks from
  `cases.json`. The workbooks come from a small XLSX writer in
  `tool/src/format_oracle.dart`, using `archive` (a dev dependency): jet_core
  has no writer of its own and depends on none.
- `tool/compare_format_libreoffice.dart <dir>` compares the formatter with
  LibreOffice's text "as shown" of the same workbooks. It reports and never
  fails: LibreOffice is a second opinion, not Excel, so it exits 0 with
  differences (2 only on unusable input). CI runs it in the `second-opinion`
  job (`continue-on-error`); its doc comment explains the filter options:

```bash
dart run tool/write_format_oracle.dart build/format_oracle
LC_ALL=C.UTF-8 soffice --headless \
  --convert-to 'csv:Text - txt - csv (StarCalc):44,34,UTF8,1,,0,false,true,true,false,false,1' \
  --outdir build/format_oracle build/format_oracle/*.xlsx
dart run tool/compare_format_libreoffice.dart build/format_oracle
```

## Benchmark

`benchmark/format_benchmark_test.dart` times `NumberFormatter` on 100,000
numbers, serial dates (`FormatDecimal`) and `DateTime`s, and prints the time of
each. The quality gate does not run it; run it by hand on the VM and in Chrome.
It records figures and fails on none (`docs/benchmark.md`):

```bash
dart test benchmark
dart test -p chrome benchmark
```

## Fuzzing

`test/format/fuzz_test.dart` mutates a corpus of format codes
(`test/format/support/fuzz.dart`) and requires `NumberFormatter` to throw
nothing, to return a `text` of at most 1,000 characters more than a text value
it shows unchanged, and `parts` that join to `text`. It runs seeds 1 to 4 with
200 cases each, in three locales and both date systems; the same cases on the
VM and in Chrome. The corpus is pinned by its length and a hash in the test,
and a seed gives the cases it gave in jet_office: change the corpus only on
purpose, with both numbers in the same commit. For longer runs, by hand:

```bash
dart run tool/fuzz_formatter.dart --seeds 1-200 --cases 1000
```

It prints each failure as
`seed <s> case <i>: <code> <value> width <w> <locale> <system>: <problem>` and
exits 1 on any. A failure is a formatter defect: pin it as a unit test in the
owning `test/format/*_test.dart` with the input minimized by hand, then fix it.
The rules are in `docs/number-format.md`.

## Hard rules

- **Pure Dart, web-safe.** Nothing under `lib/` imports `dart:io`, `dart:ui`,
  `dart:html` or any Flutter library. Enforced by
  `test/architecture/platform_imports_test.dart`.
- **No dependencies.** `pubspec.yaml` keeps `dependencies:` empty and nothing
  under `lib/` imports a `package:` other than `package:jet_core/`. Enforced by
  `test/architecture/dependencies_test.dart`. `archive`, `xml` and `test` are
  dev dependencies for tests only.
- **The public API is exactly what `lib/jet_core.dart` exports.** Everything
  under `lib/src/` is private.
- **One tokenizer.** A number format code is scanned in exactly one place,
  `lib/src/format/format_code.dart`; no other file holds the `AM/PM` and `A/P`
  markers. Enforced by `test/architecture/format_code_test.dart`.
- **Tests come first.** Write the failing test, watch it fail, then implement.
- **Decisions live in `docs/decisions/`.** An accepted record is never edited;
  write a new one that supersedes it.
- **Excel is the oracle.** The owner's Excel for Mac output wins over any other
  producer. Never edit a committed owner file (CSV, manifest, cases) without
  the owner.
- No `Xlsx...` name in `lib/`, except where text explains history.
- Follow the surrounding code: explicit types, dartdoc on every public member,
  plain sentences.

## Reference

The engine's rules, each with its test, are in `docs/number-format.md`; the
benchmark's figures are in `docs/benchmark.md`; why the package exists and what
may be added to it is `docs/decisions/0001-jet-core-holds-what-the-families-share.md`.

jet_office is cloned next to this repo (`../jet-office`), where the engine was
written (its decision 0008) and which is to depend on `jet_core`. Read it for the
history; never import from it.
