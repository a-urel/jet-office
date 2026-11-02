# 0010 — Phase 4 is a DOCX document model that generates, opens and saves without loss

**Status:** Proposed — 2026-11-02

## Context

[`0001`](0001-port-a-file-engine-from-quds.md) listed phase 4 as "DOCX
write: paragraphs, tables with a repeating header row, page header and footer
with `PAGE`/`NUMPAGES` fields, inline images. Then template fill and mail
merge on top of the same model." [`0002`](0002-two-xlsx-paths-stream-and-model.md)
left DOCX's shape to phase 4 ("Template filling probably wants only a
model"). `0009` (phase 3) built a format-neutral package layer under
`lib/src/opc/` for DOCX to share, and left to phase 4 whether shared public
types such as `XlsxImage` get format-neutral names.

The first consumers generate documents: Monépro exports lists and dashboards
to Word, and `jet_print` exports reports to DOCX. A list export shows a logo,
the report name, a date, page numbers and the content. The owner set the
same aim as for XLSX: a general-purpose library, which the consumers order
but do not shape.

A survey of Quds' Word code at `15c5d29` (about 10,700 lines) found a good
reader and a lossy writer. Save regenerates the document, settings,
numbering (two hard-coded lists), styles, notes, headers and `app.xml`, and
drops XML it does not know. It writes `pPr`, `rPr` and `sectPr` children out
of schema order, passes XML-forbidden control characters, takes bookmark ids
from `String.hashCode`, loses header pictures, and its mail merge collapses
paragraphs into one run.

The full design is in
`docs/superpowers/specs/2026-11-02-phase-4-docx-design.md`. That folder is
git-ignored, so this record keeps what has to outlive it.

## Decision

**Phase 4 builds `DocxDocument`, one in-memory model that is created empty
or opened from bytes, changed and saved. It applies 0009's fidelity standard
and preservation layers to WordprocessingML. Generation comes first; opening
and saving without loss is there from the first milestone.**

- **Scope: milestones D1 to D6**, named D so they do not clash with M, R, N
  and W.
  - **D1, foundation:** shared machinery extracted from `lib/src/xlsx/`,
    format-neutral renames, `DocxDocument()`, `open` and `save`, paragraphs
    and runs typed, everything else opaque, text rules, a new document like
    Word's blank one, warnings, limits and failures, round trip and
    validation.
  - **D2:** run and paragraph formatting, styles, lists.
  - **D3:** tables, with the repeating header row.
  - **D4:** sections, headers and footers, fields (`PAGE`, `NUMPAGES` and
    others).
  - **D5:** inline pictures (in headers too), hyperlinks, bookmarks,
    document properties.
  - **D6:** `DocxListExport`, proof and release readiness.
- **One model, no stream writer.** A Word document large enough to need
  0002's forward-only path is not a realistic export. A stream writer can be
  added beside the model later, sharing its element writers, if a benchmark
  shows the need.
- **The fidelity standard is 0009's, with Word as the judge.** Open and save
  with no change gives semantically equal parts; a change touches only what
  it changes plus named bookkeeping. A part never loaded is written from its
  bytes; a loaded part is serialized from the model; inside it, what the
  model does not type is kept as an opaque node, and unknown attributes are
  kept. Files from Word, LibreOffice and Google Docs are held to the same
  bar; elements are matched by namespace URI, never by prefix.
- **Word for Mac (Microsoft 365) is the reference reader.** A file Word
  repairs is a bug. Each D milestone gets the owner's Word check, recorded
  in `docs/word-checks.md`.
- **A new document looks like Word's current blank document:** Aptos
  through the theme, Word's `Normal` spacing, A4 portrait. The reference is
  a blank document the owner saves from Word for Mac.
- **One property writer per container.** `rPr`, `pPr`, `tblPr`, `trPr`,
  `tcPr`, `sectPr` and their style counterparts are each written by one
  function in schema order, with kept children merged into that order, and
  a test checks the order against ECMA-376.
- **Text uses the one XML escaper.** Forbidden characters are removed with a
  warning; `\t` and `\n` become tabs and breaks.
- **Files are untrusted input, as in 0007 and 0009.** `DocxReadLimits`,
  CRC-32, duplicate entries and DTDs refused, `DocxReadException` with a
  `DocxReadFailure`, opaque XML bounded before it is kept, a fuzz test in
  the gate. Macro-enabled documents and templates pass through with their
  content types; macros are never run, created or edited.
- **Public names.** `XlsxImage`, `XlsxImageFormat` and `XlsxLocale` become
  `OfficeImage`, `OfficeImageFormat` and `OfficeLocale`; the library is
  unpublished, so the old names are removed. Warnings stay per format:
  `DocxWarning` and `DocxWarningCode` beside `XlsxWarning`, because a Word
  warning has a location path, not a sheet and cells. So do `DocxResult`,
  `DocxReadLimits`, `DocxReadException` and `DocxReadFailure`. Every
  `DocxWarningCode` has messages in `en`, `de` and `tr`.
- **Layering.** The format-neutral machinery (warning collection and
  messages, read limits, the mapping of ZIP and XML failures) moves out of
  `lib/src/xlsx/` before any DOCX code. A guard test fails if `lib/src/docx/`
  imports `lib/src/xlsx/`, except the number format engine, which
  `DocxListExport` uses. Pictures and document properties are built once
  under `lib/src/opc/` by whichever of phase 3 and phase 4 needs them first.
  Shared changes land in main as their own commits.
- **Change records.** DOCX primitives go through 0009's `ChangeLog`; no
  public change-set API in phase 4.
- **Not Quds' serializer.** Its property vocabulary, built-in style
  definitions and parts of its property parsing may be ported under the
  usual rules; its serializer, mail merge and other DOCX writers are not.

**Out of phase 4:** template fill and mail merge (the next phase, on this
model; this refines 0001's phase-4 line); native charts (a later DrawingML
chart phase shared with XLSX; a chart is a picture until then, and charts
in opened documents are kept); editing tracked changes, comments, notes,
content controls, text boxes, floating pictures and equations, which stay
opaque; right-to-left and complex-script typing; layout and pagination;
encryption [0004]; `.doc`, Strict OOXML, flat XML, RTF, ODT.

## Consequences

**D1 waits for W1.** It needs the package layer in main. The spec, this
record and the D1 plan come first.

**Phase 3 rebases once.** The extraction commits move files W2 will edit,
so they land before W2 starts.

**The fidelity claim rests on the owner's Word files.** Files the library
writes itself carry none of what preservation is for (rsids, `w14:paraId`,
`mc:AlternateContent`, `w:sdt`, compatibility settings). The owner supplies
Word for Mac files for D1.

**Fields show their cached result until Word lays the document out.** The
model writes `1` for `PAGE` and `NUMPAGES`; a reader that does not paginate,
this library included, sees that.

**Word versions without Aptos substitute a font** in new documents.

**New warning codes need the native-speaker check** in German and Turkish
before release, as earlier phases' did.

## What this does not decide

- **The public API's exact names and signatures.** Settled milestone by
  milestone and fixed at D6.
- **Where the extracted machinery lives** (`lib/src/opc/` or a sibling).
- **The template fill design**: placeholder syntax, repeating rows and
  blocks, documents per record. Its own record.
- **Publishing.** Still the owner's decision.
