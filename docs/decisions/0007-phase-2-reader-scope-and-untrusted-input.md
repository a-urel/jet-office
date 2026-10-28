# 0007 — Phase 2 is a fast reader for import; files are untrusted input

**Status:** Accepted — 2026-10-28

## Context

[`0001`](0001-port-a-file-engine-from-quds.md) listed phase 2 as "XLSX read:
values and types, for import". [`0002`](0002-two-xlsx-paths-stream-and-model.md)
named the model for read and modify, `XlsxWorkbook`, and required one cell
encoder for both paths. Phase 1 ([`0003`](0003-phase-1-scope-output-and-diagnostics.md))
is complete: a writer, with model-neutral value types meant for the model to
reuse.

The owner's first need is Monépro's import of master data: product lists,
price lists and customers, up to about 100,000 rows by 12 columns. The files
come both from users' own spreadsheet programs and from suppliers' and
accounting systems' exports, and users upload them. The owner also plans a
separate viewer and editor application, which will need the full model and a
way to show each cell as Excel does. The owner's measure of success for the
reader: nothing read missing, nothing read wrong, and fast.

The full design is in
`docs/superpowers/specs/2026-10-28-phase-2-xlsx-reader-design.md`. That folder
is git-ignored, so this record keeps what has to outlive it.

## Decision

**Phase 2 is a fast, faithful XLSX reader for data import. It returns sheets
of raw rows with typed cells and builds no model. The model and modifying
files are the next phase, built on phase 2's parts.**

- **Scope: milestones R1 to R4.** R1, foundation: safe ZIP and OPC reading,
  the XML pull parser, shared strings, sheet rows, the cell decoder. R2,
  types: number formats, dates and durations, exact decimals, error values,
  formulas, producer variants. R3, files from other producers and hostile
  files. R4, benchmark, documentation and release readiness. Named R so they
  do not clash with phase 1's M1 to M5. 0001's phase-2 line is refined, not
  edited.
- **Lazy and synchronous.** The reader takes the file as bytes. Opening reads
  the workbook skeleton only; a sheet and the shared strings are decompressed
  on first use, and a sheet's rows come from a lazy synchronous `Iterable`.
  Rows are sparse and not retained by the reader. Same reasoning as phase 1:
  `async` would not move CPU work off the thread.
- **A cell carries** its typed value (`String`, `XlsxDecimal`, `bool`,
  `DateTime`, `Duration`, an error value or `null`), its formula text or the
  shared, array or data-table formula it belongs to, its number format id and
  code, and whether it shows a date. Numbers keep the file's digits as
  `XlsxDecimal`, so prices never pass through `double`. Dates are wall-clock
  fields in a `DateTime.utc`. A sheet also gives its merge ranges, because a
  merged value lives only in the top-left cell.
- **One cell decoder.** Exactly one function turns a `<c>` element into a
  cell value, and the next phase's model calls it. A guard test keeps other
  files from interpreting a cell's `t` attribute, as the cell encoder's guard
  does for writing (0002). Text stored as `ST_Xstring` or formula text is
  decoded by one `_xHHHH_` decoder, the exact reverse of the writer's
  escaping ([`0005`](0005-escape-xstring-in-formulas-and-defined-names.md)).
- **Files are untrusted input.** Limits (`XlsxReadLimits`, with defaults the
  caller can change) are checked from the ZIP's central directory before
  anything is inflated, and again on the inflated bytes. Every entry's CRC-32
  is verified and duplicate entry names are refused, which `package:archive`
  4.5.2 does not do itself. DTDs are refused. A file the reader cannot open
  raises a typed exception that names the reason; a cell it cannot read
  exactly is a warning, with the phase 1 machinery and messages in English,
  German and Turkish. Nothing is dropped silently. A programmer error still
  throws `ArgumentError` or `StateError`.
- **No owner Excel check per reader milestone.** AGENTS.md's rule that the
  owner opens each milestone's fixtures in Excel was written for the writer,
  whose output Excel must accept. For the reader, Excel and Google Sheets
  produce the input: the owner makes the R3 fixture files in those programs
  and confirms what each cell shows, and checks the new German and Turkish
  messages. Writer changes keep the rule.

**Out of phase 2:**

- The document model and modifying files: the next phase (0002).
- Styles beyond the number format, conditional formats, validations,
  images, notes, tables, defined names, page setup and column widths.
- Rich text runs: a rich text cell reads as its plain text.
- Formula evaluation: the cached result is read.
- Strict OOXML, `.xlsb`, legacy `.xls`, CSV and encrypted files: refused with
  the typed exception ([`0004`](0004-file-encryption-is-future-work.md)).

**Planned after phase 2: a number format engine.** A pure function that
renders a cell value with its number format code the way Excel shows it
(`00123`, `1.234,50 ₺`, `28.10.2026`). The viewer application needs it for
every cell, and import benefits from it (leading zeros of codes). Phase 2
gives the raw value, the format id and code, and phase 1's date classifier,
which the engine builds on. Its scope (sections, conditions, colors,
locale-dependent separators and built-in codes, date and time tokens) is
settled when it starts. Quds has no such engine. It is a separate piece of
work before the viewer, not part of the reader or the model.

## Consequences

**The model gets no second reader.** ZIP and OPC reading, the parser, the
shared-string and style readers and the cell decoder are written once, here.
The model adds what it keeps in memory and the raw bytes of parts it does not
understand.

**Memory is a small multiple of one sheet's XML, not the cell count.** The
ported pull parser works on a Dart `String`, so a sheet of N UTF-8 bytes
costs about 2N, briefly 3N while decoding. The R4 benchmark reads the file
phase 1's benchmark writes and records time and peak memory on the VM and in
Chrome. Like the writer's, it is a recorded figure, not a threshold.

**Verification differs from the writer's.** The reader is tested against
the writer (every phase 1 fixture read back equals what the writer stored),
against LibreOffice's re-save of those fixtures in CI, against the owner's
Excel and Google Sheets files, against hand-made producer variants, and
against hostile files and a fuzz test that may raise only the typed
exception.

**The German and Turkish reader messages need a native-speaker check before
release**, as phase 1's did.

## What this does not decide

- **The public API's exact names and signatures.** Settled milestone by
  milestone and fixed at R4.
- **The next phase's shape:** whether the model also gets a "build in memory,
  write later" mode, and how it represents what it does not understand
  beyond 0002's raw bytes.
- **A parser that works on UTF-8 bytes directly.** A later optimization if
  the benchmark calls for it; it would not change the API.
- **Publishing.** Still the owner's decision.
