# 0009 — Phase 3 is a workbook model that opens, generates, edits and saves without loss

**Status:** Proposed — 2026-11-02

## Context

[`0002`](0002-two-xlsx-paths-stream-and-model.md) named `XlsxWorkbook`, a
model for read and modify, and said it would be ported from Quds'
`SmlWorkbook` and `sheet_serial.dart`, keeping parts it does not understand
as raw bytes. [`0003`](0003-phase-1-scope-output-and-diagnostics.md) and
[`0007`](0007-phase-2-reader-scope-and-untrusted-input.md) left open whether
the model also builds workbooks in memory to write later.
[`0008`](0008-number-format-engine.md) left exposing the `[ColorN]` palette
to the model phase. [`0004`](0004-file-encryption-is-future-work.md) left
open which phase reads encrypted files.

Phases 1 and 2 and the number format engine are done. Phase 1 left
model-neutral value types and element writers for every writer feature;
phase 2 left the safe ZIP and OPC reading, the parser and the one cell
decoder for the model to build on.

The owner set the aim: `jet_office` is a general-purpose office library, so
the model is designed for any consumer, not for Monépro. The model must open
a file, change it, and save it so that it looks and behaves the same in
Excel; generate files from nothing, small and large; and later serve the
owner's editor, which needs structural edits and undo.

A review of Quds at `15c5d29` found that its model keeps unknown parts but
loses content inside the parts it knows. It rewrites `workbook.xml` without
`workbookPr`, so a 1904-system file shifts every date by four years. It
drops hyperlinks, page setup, `legacyDrawing` and `extLst` from sheets. It
flattens styles, recalculates formulas over Excel's cached results, expands
shared formulas, and inserts rows without shifting formulas or any other
reference.

The full design is in
`docs/superpowers/specs/2026-11-02-phase-3-xlsx-model-design.md`. That folder
is git-ignored, so this record keeps what has to outlive it.

## Decision

**Phase 3 builds `XlsxWorkbook`, an in-memory model that is opened from
bytes or created empty, changed, and saved. The model is the single source
of every save, and saving keeps everything it does not change.**

- **Scope: milestones W1 to W6.**
  - **W1, foundation:** open and save with no loss, and generate values.
  - **W2:** styles and layout typed.
  - **W3:** sheet and workbook features typed.
  - **W4:** objects typed.
  - **W5:** structural editing, with the formula lexer and the public
    change sets and undo.
  - **W6:** proof and release readiness.

  The milestones are named W so they do not clash with M1–M5, R1–R4 and
  N1–N3.
- **The fidelity standard is behaviour in Excel, not bytes.**
  - Opened and saved with no change, every part is semantically equal to the
    input's. A test-side comparer defines "semantically equal" and pins each
    normalization.
  - After a change, only the change and named bookkeeping differ:
    `calcChain` dropped, `fullCalcOnLoad` set, `dimension` and `spans`
    recomputed.
  - Content Excel does not show (defined names, pivot caches, connections,
    custom XML, `extLst`) counts as content.
- **Three layers of preservation.**
  1. A part the model never loaded is written from its original bytes.
     Nothing can change it, so this is writing the model, and no dirty flag
     exists to get wrong.
  2. A loaded part is always serialized from the model.
  3. Inside a loaded part, what the model does not type is kept as an opaque
     node at its position, with its namespace declarations, and unknown
     attributes on typed elements are kept too.

  Milestones move content from opaque to typed.
- **Opened files keep their indexes and names.**
  - While any sheet is unloaded, the shared-string table and `cellXfs` are
    append-only.
  - Part names and relationship ids are never changed; new ones take unused
    names.
- **Lazy by part, whole sheets, no object per cell.**
  - `open` reads the skeleton; a part loads on first use.
  - A sheet loads whole. Row windows with patches were rejected: the model
    would no longer be the single source.
  - Cells live in a compact store; the objects the API returns are views.
  - Saving streams one part at a time through the one cell encoder.
- **The model generates files.** `XlsxWorkbook()` starts empty, so 0003's
  and 0007's question is answered yes. Small and large files are both
  targets. The model can build everything `XlsxWriter` writes, and a parity
  test holds the two paths together.
- **The writers and the reader stay.**
  - `XlsxWriter` and `XlsxStreamWriter` remain the unbounded path for
    exports beyond memory.
  - `XlsxReader` remains the leanest import path.
  - The model shares their parts and extends them; it does not fork them.
    The one-encoder and one-decoder rules hold.
  - The decoder gains a raw step, so the model stores what the file stores
    (a date's serial digits) and shows typed values on access.
- **Not Quds' serializer.** This record supersedes 0002's statement that the
  model is ported from `SmlWorkbook` and `sheet_serial.dart`. Quds pieces may
  still be ported where they meet this record, such as its reference shifting
  in W5.
- **Structural edits are designed in from W1, built in W5.** That design is:
  - a lexer for Excel's full formula grammar;
  - one interface for everything that holds a reference;
  - renaming a sheet treated as a structural edit.

  Content the model does not type that an edit may affect is fixed if typed
  by then, and otherwise reported with a warning. It is never changed or
  left wrong silently.
- **Change records and transactions, no history.**
  - Every change goes through primitive changes that record what they
    replaced.
  - A transaction is atomic and returns a change set.
  - The library offers `undo` and `redo` of a change set. The undo stack and
    its policy belong to the editor.
- **Formula evaluation is future work that phase 3 must not block.**
  - Formulas, cached results and formula groups are stored separately and
    never expanded.
  - The lexer is the front of the future parser.
  - Change records carry what an engine needs for invalidation.
  - Until then, the model never writes its own results.
- **Files are untrusted input, as in 0007.**
  - `open` applies `XlsxReadLimits` and every reader rule. Opaque XML is
    parsed and bounded before it is kept.
  - A sheet that is broken on first load throws `XlsxReadException`, as the
    reader does.
  - The fuzz test covers the model.
- **The package layer is shared with DOCX.** The part graph, lazy loading,
  opaque nodes and the change-record machinery live under `lib/src/opc/`,
  which must not import `lib/src/xlsx/`. A guard test enforces it.
- **Macro-enabled workbooks pass through.** The model keeps
  `vbaProject.bin` like any part it does not understand. It never reads,
  runs, creates or edits it, and it saves with the original content types.
  0003's exclusion of macro support stands.
- **Each W milestone gets the owner's Excel check.** The model writes files,
  so AGENTS.md's rule for writer milestones applies. 0007's exemption was for
  reader milestones only.

**Out of phase 3:** formula evaluation; encryption, which a later record
adds as a `password` parameter on `open` and `save` (0004's question is
answered: not phase 3); DOCX (phase 4); undo stacks; typing charts, pivot
tables, slicers, sparklines, form controls, external links, threaded
comments and connections, which stay opaque; Strict OOXML, `.xlsb`, `.xls`.

## Consequences

**Opening and saving is honest by construction.** What the model does not
understand is kept, so a new kind of content in a customer's file costs
nothing until someone wants to edit it.

**An opened workbook may carry dead entries.** Append-only tables keep
unused strings and formats while sheets are unloaded. They are harmless to
Excel and compacted once every sheet is loaded.

**Formula results go stale until Excel opens the file.** The model sets
`fullCalcOnLoad` but computes nothing, so a non-calculating reader, this
library's included, sees old cached results after a change.

**Structural edits cost memory.** They load every part they must rewrite.

**The `[ColorN]` palette arrives with W2's styles**, settling 0008's
consequence.

**New warning codes need the native-speaker check** in German and Turkish
before release, as earlier phases' did.

## What this does not decide

- **The public API's exact names and signatures.** Settled milestone by
  milestone and fixed at W6.
- **The cell store's layout and how opaque nodes are stored.** The builder's
  choice, within the memory rule above.
- **When shared strings and formats are compacted**, automatically or on
  request.
- **Format-neutral public names** for types DOCX will share (`XlsxImage`,
  `XlsxWarning`). Phase 4 decides.
- **Publishing.** Still the owner's decision.
