# 0018 — The workbook features phase 3 leaves opaque are covered in the end

**Status:** Accepted — 2026-11-10

Supersedes part of [`0009`](0009-phase-3-workbook-model.md)'s "Out of phase 3"
list. Phase 3 keeps its scope (W1 to W6). This record names what comes after
it. It answers [`0004`](0004-file-encryption-is-future-work.md)'s question:
encryption is covered.

## Context

`0009` keeps these opaque, or leaves them out of phase 3:
- formula evaluation;
- encryption;
- pivot tables;
- slicers;
- sparklines;
- form controls;
- external links;
- threaded comments;
- connections;
- macros;
- Strict OOXML, `.xlsb` and `.xls`.

Opaque content is kept byte for byte but cannot be read typed or edited.

The owner decided on 2026-11-10: macros and the other formats stay out; every
other item is added in the end.

## Decision

**`jet_office` will in the end read, edit and write these typed:**
- formula evaluation;
- encryption (a `password` on `open` and `save`);
- pivot tables, with their caches;
- slicers;
- Excel's cell-level sparklines (`x14`);
- form controls;
- external links;
- threaded comments;
- connections.

**These stay out, as before:**
- macros. `vbaProject.bin` passes through and is never read, run, created
  or edited (`0003`, `0009`).
- Strict OOXML, `.xlsb` and `.xls`.

Order:
1. Phase 3 finishes first: W5 (structural editing), then W6.
2. The features above follow in an order the owner sets, led by what Monépro
   needs.

Each feature becomes a milestone of its own with its own plan and the owner's
Excel check. Formula evaluation builds on W5's lexer, as `0009` planned.

## Consequences

- **W5 and W6 must not block these features.** Nothing in them may close a
  door. In particular:
  - reference shifting must reach pivot caches, slicers, sparklines and
    external links;
  - when they are opaque, it must fix them or report a warning, as `0009`
    already requires.
- **Opaque until typed.** Each feature stays byte-kept until its milestone
  types it.
- **The sparkline link.** Exporting a `jet_charts` sparkline to a real Excel
  sparkline (design §4.3) is part of the sparkline milestone.
