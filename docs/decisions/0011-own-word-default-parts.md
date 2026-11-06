# 0011 — A new document's parts are written by this library, with Word's values

**Status:** Accepted — 2026-11-06

## Context

[`0010`](0010-phase-4-docx-document-model.md) says a new document looks like
Word's current blank document. D1 and D2 met that by copying XML from the
owner's `blank.docx` and `builtins.docx` into `lib/`: the theme, the styles
with Word's list of 376 latent styles, the font table, the settings and the
list definitions. The package is Apache-2.0, and whether Microsoft-authored
XML may ship under it was left open in `NOTICE` for the owner. The phase 4
spec named a fallback: the ECMA-376 default theme with hand-written styles of
the same values.

## Decision

The owner chose to rewrite these parts with the same values, before anything
is published.

- **Styles, list definitions, the font table and the compatibility settings
  are built from tables of values** in `lib/src/docx/default_styles.dart`,
  `blank_document.dart` and `builtin_numbering.dart`. The values are fonts,
  sizes, spacing, colours and priorities. The oracle tests compare them with
  the owner's files, which stay test input only.
- **The theme is this library's own**, named `jet_office`. It keeps Word's
  current colours and Aptos, so `DocxColor.theme` and the look of a document
  do not change. This departs from the spec's fallback: the ECMA-376 theme
  would change the colours and the fonts, against `0010`. It has no
  per-script font list and a plain format scheme.
- **The latent styles name only the styles Word's gallery offers**, 25 of
  them; the others are hidden until used.
- **`word/document.xml` stays as it was:** its root is a list of namespace
  names and its section holds the page's values; a file read later may rely
  on those prefixes.
- Settings no part of the look depends on are left out: `m:mathPr` (Word's
  defaults) and `w15:chartTrackingRefBased`.

## Consequences

- East Asian, Arabic and other scripts take the font Word picks, not the
  theme's list. Latin text, Turkish and German included, does not change.
- A drawing that uses the theme's fill, line or effect styles looks plainer.
  The library writes none yet.
- Word's Styles pane recommends fewer built-in styles until they are used.
- This lowers the risk that the package ships Microsoft's text. It is an
  engineering decision, not legal advice: the values, and the shape the
  schema gives them, are still those of Word's defaults.
- The Word check is repeated for what a new document writes
  (`docs/word-checks.md`).
