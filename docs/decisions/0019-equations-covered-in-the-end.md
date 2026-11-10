# 0019 — Equations are covered in the end

**Status:** Accepted — 2026-11-10

Supersedes one part of [`0010`](0010-phase-4-docx-document-model.md)'s "Out of
phase 4" list: the words that put equations among the things that "stay
opaque". Phase 4 keeps its scope (D1 to D6), and `0010` is not edited.

## Context

Word and Excel store equations as Office Math (OMML,
`http://schemas.openxmlformats.org/officeDocument/2006/math`):

- **In a Word document**, an equation is an `m:oMath` or `m:oMathPara` in a
  paragraph. It can be in the body, a table cell, a header or a footer.
- **In a workbook**, Excel's Insert > Equation draws a text box in the drawing
  part. The box sits in `mc:AlternateContent`: its `a14` choice holds
  `a14:m`, and a fallback holds the plain text.
- **The run properties differ by host:** Word puts `w:rPr` inside a math run,
  and Excel puts `a:rPr` there.

An analysis on 2026-11-10 found this about the models today:

- The DOCX model keeps an equation as opaque content, byte for byte, but an
  equation adds no text to its paragraph.
- The workbook model keeps an equation's anchor byte for byte on a round trip.
- One edit goes wrong: a structural edit (W5) does not move an anchor wrapped
  in `mc:AlternateContent`, so the box stays where it was while its cells
  move (`docs/xlsx-model.md`, "Structural edits (W5)").

The analysis used hand-made files. No owner file holds an equation yet.

The owner decided the same day: equations are a feature for later. The level,
the order and whether there will be an editor are not decided, and need not be
yet.

## Decision

**`jet_office` will in the end read, and later write, equations in both
formats.** Until then they stay opaque, kept byte for byte, as `0009` and
`0010` require.

## What this does not decide

These wait for the owner, and for reference files saved from Word and Excel
for Mac:

- **The level of support:**
  - an equation's plain text only;
  - a typed read-only OMML tree;
  - writing from a builder API or a linear format such as LaTeX or UnicodeMath;
  - the workbook's text box host.
- **The order.**
- **The milestone names.**
- **Where the code sits.** A shared OMML layer under `lib/src/` would need its
  own allowed imports, named in a record, as `0015` did for DrawingML.
- **Whether there will be a Flutter equation editor, and where it would sit.**
  AGENTS.md says `jet_office` has no editors and no rendering, so an editor
  would need a package and a record of its own.

## Consequences

- Phase 3 and phase 4 code must not close the door. Equations stay
  preserved, and no edit may drop them silently.
- The fix of the structural edit gap above is a W5 matter. It does not wait
  for equations. Its expected behaviour waits for the owner's Excel check:
  does Excel move an equation box when rows or columns are inserted?
- When equations are planned, the owner first saves reference files from Word
  and Excel for Mac. Only the owner's runs count.
