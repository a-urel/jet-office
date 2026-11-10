# 0022 — The document features phase 4 leaves opaque are covered in the end

**Status:** Accepted — 2026-11-10

Supersedes part of [`0010`](0010-phase-4-docx-document-model.md)'s "Out of
phase 4" list: the words that put tracked changes, comments, notes and content
controls among the things that "stay opaque". It is the document counterpart
of [`0018`](0018-workbook-features-covered-in-the-end.md). Phase 4 keeps its
scope (D1 to D6, done), and `0010` is not edited.

## Context

`0010` keeps these opaque, or leaves them out of phase 4:
- template fill and mail merge (the next phase);
- native charts (the chart phase, `0014`);
- editing tracked changes, comments, notes, content controls, text boxes,
  floating pictures and equations;
- right-to-left and complex-script typing;
- layout and pagination;
- encryption (`0004`);
- `.doc`, Strict OOXML, flat XML, RTF and ODT.

Later records already cover some of them:
- charts: `0014` and `0017`;
- encryption: `0004` and `0018`;
- equations: `0019`;
- text boxes and floating pictures: `0021`.

Opaque content is kept byte for byte but cannot be read typed or edited. A
table of contents is a field (`TOC`) whose cached result the model keeps as
written; nothing builds or updates one.

The owner decided on 2026-11-10: every document feature in this list is added
in the end, except macros.

## Decision

**`jet_office` will in the end read, edit and write these typed:**
- tracked changes (`w:ins`, `w:del`, the property-change elements), with
  accepting and rejecting them;
- comments (`comments.xml` and Word's extended comment parts), with replies;
- footnotes and endnotes;
- content controls (`w:sdt`);
- a table of contents: inserting the `TOC` field and filling its result from
  the document's headings.

**Still decided by their own records:** template fill and mail merge
(`0010`, the next phase, its own record), charts (`0014`, `0017`),
encryption (`0004`, `0018`), equations (`0019`), ink (`0020`), shapes, text
boxes, floating pictures and icons (`0021`).

**These stay out, as before:**
- macros. A macro-enabled document's `vbaProject.bin` passes through and is
  never read, run, created or edited (`0010`).
- layout and pagination. A table of contents filled by the library shows no
  page numbers until Word updates the field, as `PAGE` and `NUMPAGES` show
  their cached result today (`0010`).
- `.doc`, Strict OOXML, flat XML, RTF and ODT.

Order: template fill comes first, as `0010` planned. The features above follow
in an order the owner sets, led by what Monépro needs. Each becomes a milestone
of its own, with its own plan and the owner's Word check.

## Consequences

- **Nothing may close a door.** Until a feature is typed, no edit may drop or
  break it silently. Template fill in particular must keep tracked changes,
  comments, notes and content controls around the text it replaces. When it
  cannot, it reports a warning.
- **Opaque until typed.** Each feature stays byte-kept until its milestone
  types it.
- **Template fill and content controls meet.** Content controls are one way to
  mark a placeholder. The template fill record decides whether it uses them;
  the content control milestone must not contradict that choice.
