# Working in jet-core

`jet_core` is a pure-Dart package of building blocks shared by the jet_
packages. Today that is one thing: the number format engine, extracted from
`jet_office` (decision 0008 there), which shows a value as Excel for Mac does.
It has no dependencies, no editors, no rendering and knows no file format.

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
  the owner. The oracle, fuzz and benchmark sections arrive with the engine.
- No `Xlsx...` name in `lib/`, except where text explains history.
- Follow the surrounding code: explicit types, dartdoc on every public member,
  plain sentences.
