# 0021 — Shapes, text boxes and icons are covered in the end

**Status:** Accepted — 2026-11-10

Supersedes one part of [`0010`](0010-phase-4-docx-document-model.md)'s "Out of
phase 4" list: the words that put text boxes and floating pictures among the
things that "stay opaque". Adds to [`0009`](0009-phase-3-workbook-model.md),
which does not name shapes. Phase 3 and phase 4 keep their scope, and neither
record is edited.

## Context

Excel's and Word's Insert > Shapes and Insert > Icons write:

- **Shapes**: a preset or freeform geometry with fill, line and text. In a
  workbook it is an `xdr:sp` in the drawing part. In a document it is a
  `wps:wsp` in a `w:drawing`, which Word wraps in `mc:AlternateContent` with
  a VML fallback.
- **Connectors and groups**: `xdr:cxnSp` and `xdr:grpSp` in a workbook,
  `wpg:wgp` in a document.
- **Text boxes**: shapes with `txBox="1"`. In a document their text is
  WordprocessingML paragraphs, written twice: once in the shape, once in the
  fallback.
- **Icons**: SVG pictures. A `pic` whose blip names a PNG fallback and
  carries the SVG through the `asvg:svgBlip` extension.

An analysis on 2026-11-10 (`docs/shapes.md`) found this about the models
today:

- Both models keep all of these byte for byte on a round trip, and adding
  pictures, notes or tables leaves them alone.
- Nothing reads or writes them typed. `addPicture` takes PNG and JPEG only.
- A workbook's icon lists as a picture of its PNG. A document's inline icon
  reads as a `DocxPicture` of its PNG.
- A document's text box adds no text to its paragraph.
- One edit goes wrong: a structural edit (W5) does not move a shape's
  `textlink`, the cell its text shows (`docs/xlsx-model.md`, "Structural edits
  (W5)").

The analysis used hand-made files. No owner file holds a shape or an icon yet.

The owner decided the same day: shapes, text boxes and icons are a feature
for later. It is too early to plan them.

## Decision

**`jet_office` will in the end read, write and edit shapes, connectors,
groups, text boxes and SVG pictures (icons) in both formats.** Until then
they stay opaque, kept byte for byte, as `0009` and `0010` require.

## What this does not decide

These wait for the owner, and for reference files saved from Excel and Word
for Mac (`docs/shapes.md`, section 6):

- **The level of support and the order**: a typed read, adding shapes,
  SVG pictures, text boxes, editing existing shapes (`docs/shapes.md`,
  section 3).
- **The milestone names.** `docs/shapes.md` proposes S.
- **Where the order sits relative to C2 and C3**, which share the drawing
  part and the anchored drawing with shapes.
- **Who makes an SVG's PNG fallback.** `jet_office` has no rendering.
- **Whether a DOCX writer writes Word's VML fallback.**
- **Whether a text box's text counts in the body's text.**

## Consequences

- No edit may drop a shape, a text box or an icon silently, nor an icon's SVG
  part and its relationship.
- The `textlink` gap is a W5 matter. It does not wait for shapes. Its expected
  behaviour waits for the owner's Excel check.
- When shapes are planned, the owner first saves the reference files. Only
  the owner's runs count.
