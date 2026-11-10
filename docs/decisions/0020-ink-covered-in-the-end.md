# 0020 — Ink is covered in the end

**Status:** Accepted — 2026-11-10

Adds to [`0009`](0009-phase-3-workbook-model.md) and
[`0010`](0010-phase-4-docx-document-model.md). Neither names ink. Both keep
what the model does not type as opaque content, so ink is kept today.
Nothing in either record changes.

## Context

Word and Excel store freehand drawing from the Draw tab ("ink") as follows:

- **The strokes** are in a part of their own, in W3C InkML
  (`http://www.w3.org/2003/InkML`): `xl/ink/inkN.xml` or `word/ink/inkN.xml`.
- **A content part reference** points to that part. It sits in
  `mc:AlternateContent`, with a picture of the strokes as the fallback:
  - in a drawing anchor, in a workbook;
  - in a run, in a document.

An analysis on 2026-11-10 ran hand-made files through the tools:

- the round trip, the edit tools and the Open XML SDK keep ink, its part and
  its relationships, in both formats;
- the strokes are not read.

No owner file holds ink yet.

One case is not settled. If Excel wraps the anchor itself in
`mc:AlternateContent`, the W5 gap that decision 0019 notes applies to ink too:
such an anchor does not move on a row or column edit
(`docs/xlsx-model.md`, "Structural edits (W5)").

The owner decided the same day: ink is a feature for later. The level, the
order and whether there will be a drawing surface are not decided.

## Decision

**`jet_office` will in the end read, and later write, ink in both formats.**
Until then it stays opaque, kept byte for byte, as `0009` and `0010` require.

## What this does not decide

These wait for the owner, and for reference files saved from Word and Excel
for Mac:

- **The level of support:**
  - listing ink objects;
  - reading strokes typed;
  - writing ink.
- **Who makes the picture fallback.** `jet_office` has no rendering.
- **The order and the milestone names.**
- **Where the code sits.** A shared InkML layer under `lib/src/` would need its
  own allowed imports, named in a record.
- **Whether there will be a Flutter drawing surface, and where.** It would be a
  package and a record of its own, as for an equation editor (0019).

## Consequences

- No edit may drop ink silently. Its part and relationships stay with it.
- The owner's reference files come first when ink is planned. Only the
  owner's runs count.
