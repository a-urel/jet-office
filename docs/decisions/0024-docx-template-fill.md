# 0024 — DOCX template fill: `{{}}` tags and merge fields, filled in place on the model

**Status:** Accepted — 2026-11-12

Settles what [`0010`](0010-phase-4-docx-document-model.md) left to "its own
record" under "What this does not decide": the template fill design
(placeholder syntax, repeating rows and blocks, documents per record). Follows
[`0022`](0022-document-features-covered-in-the-end.md), which puts template
fill first among the document features and binds it to keep tracked changes,
comments, notes and content controls around what it replaces. Neither record
is edited.

## Context

A template is a Word file a person designs in Word, with placeholders a
program fills from data: a contract, an invoice, a letter. `DocxDocument`
(D1 to D6) already opens, edits and saves Word files without loss, so template
fill is a layer on it.

Monépro, the first consumer, has no Word output and no template mechanism yet.
Its documents are PDFs drawn in code; its sales invoice, dispatch note, quote
and contract have no print, and its Contracts app ("contract management and
templates") is a placeholder. Its money is `Decimal`, shown per locale with
the symbol after the number (`1.234,56 ₺`), in `tr`, `en` and `de`; it makes
one document per record.

Quds' mail merge, which 0010 excluded from the port, matches `«Name»` and
`MERGEFIELD` on a paragraph's joined text and replaces the whole paragraph
with one run: every other run's formatting, hyperlinks, note references and
comment anchors are lost. Its many-document merge edits the template in place
and drops headers and footers.

The design is in `docs/superpowers/specs/2026-11-12-docx-template-fill-design.md`.
That folder is git-ignored, so this record keeps what has to outlive it. The
owner decided the syntax, sections, documents per record, missing values,
formats and pictures on 2026-11-12.

## Decision

**Template fill finds placeholders in the model's typed paragraphs and
replaces them through the model's edit primitives, one document per fill.
It never rebuilds a paragraph, and it never changes the template.**

- **Syntax.** Text tags `{{name}}`, Mustache-shaped, are the main way:
  `{{name}}`, `{{name:FORMAT}}`, `{{#name}}`…`{{/name}}`, `{{^name}}`…
  `{{/name}}`, `{{.}}`; names are dotted paths of Unicode letters, digits and
  `_`. Word's own mail merge fields (`MERGEFIELD`, from Mailings > Insert
  Merge Field) are filled by the same name and replaced by plain runs, as
  Word's Finish & Merge does. Content controls are not placeholders in this
  phase.
- **Content controls agree later.** The content control milestone (0022) may
  fill a control whose tag is a tag body, by the same names, formats,
  sections and missing-value rules; it may not give any of them another
  meaning.
- **Split runs keep their formatting.** A tag is matched across the runs Word
  split it into (proofing marks, bookmark and comment marks, deletions between
  them do not break it). The value takes the properties of the run holding
  `{{`; the runs inside the tag go; zero-text marks inside it stay, after the
  value; nothing else in the paragraph changes. A tag that crosses anything
  else (a tab, a picture, a field, a tracked insertion, a content control, a
  link's edge) is not filled, and warns.
- **Sections: Mustache.** A list repeats, a false, empty or missing value
  removes, a true value shows, a map enters a scope; `{{^}}` inverts. Where
  the two tags stand decides what repeats: inlines of one paragraph, rows of
  one table, or the blocks between two paragraphs that hold only a tag.
  Copies keep bookmarks, comment anchors and note references in the first
  copy only, with a warning, and get fresh ids for drawings, revisions and
  content controls; a repeat across a vertical merge is refused with a
  warning.
- **Values and formats through `jet_core`.** `{{tutar:#,##0.00 ₺}}` formats
  with `NumberFormatter` in the caller's `FormatLocale`, as `DocxListExport`
  does; exact decimals go in as `FormatDecimal`, never `double`.
- **Pictures both ways.** An inline picture whose alt text is a tag gets its
  image replaced, keeping the template's size; a text tag whose value is a
  picture becomes an inline picture.
- **One document per record.** A fill returns a new document; a fill can also
  be applied to a `DocxDocument` the caller holds. One merged document of
  many records is a later milestone.
- **Missing values stay visible.** A name the data lacks leaves its tag as
  written and warns; a section whose name is missing keeps both tags visible
  and shows its content once. An option removes missing tags instead, still
  warning. Data that names nothing gives the template back. Template and data
  problems are warnings, never exceptions; a fill on a held document is one
  transaction.
- **0022's preservation.** Tracked changes, comments, notes and content
  controls around a tag stay. A tag inside one of them, or in a part the model
  keeps opaque (footnotes, endnotes, comments, text boxes, anchored pictures),
  is not filled and warns; the fill scans those parts' text to find them.
  A fill changes only what it fills; `comparePackages` proves it.
- **Milestones T1 to T3.** T1 values (tags, merge fields, split runs, formats,
  warnings, headers and footers, listing a template's tags); T2 sections;
  T3 pictures, proof and release readiness. Each has the owner's Word for Mac
  check, on templates he authors in Word himself, recorded in
  `docs/word-checks.md`.

## Consequences

- **Thirteen or so new warning codes** need messages in `en`, `de` and `tr`
  and the native-speaker check before release.
- **The owner authors two templates** (an invoice with tags, a letter with
  merge fields) for `test/fixtures/owner/docx/`; the tests rest on Word's own
  run splitting, not on files the library writes.
- **No expression language.** The caller computes totals and decisions; a
  template only shows and chooses. Adding one later would be its own record.
- **Merge fields are consumed.** A filled document has no `MERGEFIELD` left,
  so it cannot be merged again in Word; the template keeps them.
- **Tags the model cannot reach are reported, not filled,** until the
  milestones of 0019, 0021 and 0022 type those places.

## What this does not decide

- **Public names and signatures.** Settled in the plan and fixed at T3.
- **The merged document** of many records: its own milestone.
- **Whether anchored pictures' images can be swapped in T3**: decided after
  the owner's sample template.
- **Limits** on tags, nesting and copies: the plan.
