# 0025 — DOCX template sections, scopes and limits, and the fill rules of 0024 a review found wrong

**Status:** Proposed — 2026-11-17

Supersedes these parts of [`0024`](0024-docx-template-fill.md), which is not
edited:

- "A list repeats, a false, empty or missing value removes" (Decision,
  "Sections: Mustache"), where it speaks of a missing value, and "a section
  whose name is missing keeps both tags visible and shows its content once"
  (Decision, "Missing values stay visible"): the two contradict each other;
  point 1 below is the one rule.
- "Template and data problems are warnings, never exceptions" (Decision,
  "Missing values stay visible"): point 2.
- "filled by the same name" (Decision, "Syntax"), for `MERGEFIELD`s: point 3.
- "A fill changes only what it fills; `comparePackages` proves it"
  (Decision, "0022's preservation"): point 5.
- "A filled document has no `MERGEFIELD` left" (Consequences, "Merge fields
  are consumed"): point 4.
- "Limits on tags, nesting and copies: the plan" (What this does not decide):
  point 6.

It also states, as the rules the code follows, what the design
(`docs/superpowers/specs/2026-11-12-docx-template-fill-design.md`,
git-ignored) left loose or got wrong, as a review of it found on 2026-11-17
(`docs/superpowers/reviews/2026-11-17-specs-2026-11-12-docx-template-fill-design/`,
git-ignored too): points 7 to 17.

## Context

Milestone T1 filled a template's values; milestone T2 fills its sections:
`{{#name}}`, `{{^name}}` and `{{/name}}`, around inlines of a paragraph, table
rows or blocks, repeated per item of a list, shown or removed by a condition,
with a map as the scope of the names inside, nested. The T2 plan (git-ignored,
`docs/superpowers/plans/2026-11-16-t2-docx-template-sections.md`) made rulings
the design left open, and the owner approved four of them on 2026-11-16: the
limits, a warning for them, ids given at save, and one id counter for
bookmarks, comments and revisions.

Building T1 and T2 showed that some sentences of 0024 are false as written or
contradict each other, and a review of the design found it loose in places
the code had to decide. A plan is git-ignored and does not outlive its
branch, so the rules that must last are recorded here. `docs/docx-model.md`,
"What T1 does" and "What T2 does", has each rule with its test.

## Decision

**A section's tags decide its form, its value decides what happens to its
content, and a name is looked up from the innermost section outward. What
cannot be filled stays as written and warns; a programmer error throws before
anything changes. Every fill is bounded by three limits.**

1. **A missing section name.** For `{{#name}}` and `{{^name}}` alike, a name
   the data lacks keeps both tags as written, shows the content once in the
   same scope and warns `templateValueMissing` once, with the opening tag as
   detail. With `removeMissing` the tags go, the content still shows once,
   and the warning stays. A missing name never removes content.
2. **What throws.** Problems in the *content* of the template or the data
   warn: a tag that is malformed or cannot be filled where it stands, a name
   the data lacks, a value that is not text, a section that does not pair or
   that a limit refuses. Programmer errors throw `ArgumentError`: data of an
   unsupported type, a map key that is not a `String`, a cycle in the data
   (`checkTemplateData`), and a limit below 1. A part the fill must read that
   cannot be read (a header or a footer) throws `DocxReadException`. Either
   way the document is left as it was.
3. **How names are looked up.** A `{{}}` tag resolves by a dotted path: each
   segment a key of a nested map (`lookupPath`). A `MERGEFIELD` resolves by
   its whole name as one key, dots included (`lookupKey`). Inside sections
   both look up through scopes, the innermost section's value first: a path's
   first segment, or a merge field's whole name, is looked up in each scope
   from the innermost outward, skipping a scope that is not a map; the first
   map that has the key decides, and the rest of the path is walked in it
   with no further fallback (`{{a.b}}` with an innermost `a: null` is missing,
   never the outer `a.b`). `{{.}}` is the innermost value; at the top it is the
   data map, which is not text.
4. **What a fill consumes.** Every typed `MERGEFIELD` whose name the data has
   is replaced by plain runs, and a missing one too under `removeMissing`. A
   missing one stays otherwise, and so does a `MERGEFIELD` the model does not
   type: inside another field (an `IF`), or kept as loose runs; it warns
   `templateFieldNotTyped`. A filled document may therefore still hold merge
   fields.
5. **What the tools prove.** `tool/fill_docx.dart` checks, on every document
   it fills: `comparePackages` finds differences only in the main part and in
   the header and footer parts that held a tag the fill fills, never in
   `[Content_Types].xml` or another part; `fill({})` gives the template back
   with no difference; no drawing, revision or content control id is written
   more often than the template wrote it; and the tags it can name are filled
   or, warned missing, left. It proves nothing about the paragraphs inside a
   changed part; the unit tests own that.
6. **Limits** (Rulings 1 and 2 of the T2 plan, approved by the owner on
   2026-11-16). `DocxTemplateOptions` has `maxCopies` (default 100000: copies
   one fill may make, all sections and levels together, a list of n items
   making n - 1), `maxSectionDepth` (32: how deep sections may nest) and
   `maxTags` (1000000: tags and merge fields one fill may fill, copies
   counted). A section a limit refuses keeps its tags as written, shows its
   content once in the outer scope, and the fill warns the new code
   `templateLimitExceeded` with the opening tag; a tag past `maxTags` stays as
   written with the same warning. A limit below 1 throws `ArgumentError`.
   The ids of copies are given **at save** (Ruling 3): `wp:docPr` and its
   `pic:cNvPr`, the `w:id` of revisions, a content control's `w:sdtPr/w:id`;
   and **one id counter** serves bookmarks, comments and revisions (Ruling 4),
   so a document whose revision ids pass its bookmark ids gives a built
   bookmark a higher id than D5 did, still valid.
7. **Where the two tags stand.** *Inline*: both tags in one paragraph and one
   inline list (the paragraph's runs, or one hyperlink's). *Rows*: the two
   paragraphs directly in cells of one table, in different rows or cells; the
   content is the whole rows from the opener's to the closer's. *Blocks*: each
   tag alone in its paragraph (spaces, no-break spaces, bookmarks, comment
   marks and `w:proofErr` beside it only), both paragraphs in one container.
   Crossing, unpaired and mixed-level tags, two containers, a tag paragraph
   that is not alone or carries a section break, rows across a vertical
   merge, and a rows pair inside a rows pair of the same table that selects
   the same rows, are malformed: the tags stay, warn
   `templateSectionMalformed`, and the content is filled in the outer scope.
   Content holding a section break is never copied or removed. Copies keep
   bookmarks, comment ranges and references and note references in the first
   copy only, with one `templateRepeatDroppedAnnotation` per section, whose
   detail is the opening tag (the kind of mark is not named, owner,
   2026-11-16); a removal takes the other half of a paired mark with it,
   with `templateRemovalDroppedAnnotation`; a tag in a field's result, typed
   or kept as runs, is not filled. The full table is in `docs/docx-model.md`,
   "What T2 does".
8. **An anchored picture's alt text is not scanned.** The scan of opaque
   content reads `w:t`, `w:instrText` and `w:fldSimple/@w:instr`, never
   `wp:docPr/@descr`, so T1 and T2 find no tag there and do not report one.
   An anchored picture is opaque by `docs/docx-model.md`, "Pictures", and
   decision [`0010`](0010-phase-4-docx-document-model.md); decision
   [`0021`](0021-shapes-and-icons-covered-in-the-end.md) covers typing
   it later.
9. **Imports.** The template code follows the rule
   `test/architecture/layering_test.dart` enforces for all of
   `lib/src/docx/`: it never imports `lib/src/xlsx/`. It imports `jet_core`,
   the DOCX model, `common/`, `opc/` and `xml/`; there is no narrower rule for
   `template/`.
10. **Where a `MERGEFIELD` is typed:** in a paragraph's own runs and inside a
    typed hyperlink, not only in the paragraph's own runs.
11. **`\* MERGEFORMAT` and `\* CHARFORMAT` are ignored without a warning**,
    as Word adds one to every field it inserts.
12. **A value is inserted as text and never scanned again** for tags or merge
    fields. Copies are made from the unfilled content, and a value outside a
    section is never scanned again when the section is filled.
13. **Tag grammar.** An empty format (`{{a:}}`) is malformed, and so is a
    format on `#`, `^` or `/`; `{{.:FORMAT}}` is allowed.
14. **One transaction.** Decision 0010 has no public change-set API in phase
    4, so the public rule is: a fill that throws leaves the document as it
    was. That a fill is one change set, undone whole, is internal
    (`fillTemplateWithChanges`), and tests take it from there.
15. **Locations.** A warning names the template's paragraph
    (`body/tbl[0]/tr[1]/tc[0]/p[0]`); a warning in a copy names the paragraph
    it was copied from. A tag found by the scan of a footnotes, endnotes or
    comments part has its part and no paragraph path
    (`DocxTemplateTag.location` is `null`).
16. **Defaults without a code.** A `DateTime` shows in the locale's built-in
    format 14, a `Duration` as `[h]:mm:ss`.
17. **A code on a `String`** is applied as Excel applies a code to text. A
    readable code gives no warning; one the formatter cannot read warns
    `templateFormatWarning`, as for any value.

## Consequences

- **A fourteenth template warning,** `templateLimitExceeded`, has messages in
  `en`, `de` and `tr`, and `templateSectionMalformed`'s message no longer says
  sections are not filled; the native-speaker check covers both.
- **Three new public members,** `DocxTemplateOptions.maxCopies`,
  `maxSectionDepth` and `maxTags`; nothing else of the public API changes.
- **A save renews the ids of what a section copied,** in the save code, not
  in the template code; a document without copies saves byte for byte as
  before.
- **The owner's rule:** a T milestone is not done until the owner's Word check
  rows for it are recorded in `docs/word-checks.md`.

## What this does not decide

- **Pictures** (T3): the alt-text attribute of a picture placeholder and the
  size rules of picture values.
- **Tags in opaque parts that cannot be read**, which are skipped without a
  warning, and **tags in equations** (`m:oMath`, opaque, decision
  [`0019`](0019-equations-covered-in-the-end.md)).
- **A `double`** is accepted as a number beside the exact `FormatDecimal`;
  whether to keep it is left to T3.
- **A comment left with neither range nor reference** when a removal takes
  both: whether Word for Mac accepts it is for the owner's T2 check.
