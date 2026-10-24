# 0003 — Phase 1 scope, output shape and diagnostics

**Status:** Accepted — 2026-10-24

## Context

[`0001`](0001-port-a-file-engine-from-quds.md) listed phase 1 as a short set of
features: typed cells, styles, number formats, frozen panes, autofilter, column
widths, merges and multiple sheets. It framed the writer around Monépro's list
exports. [`0002`](0002-two-xlsx-paths-stream-and-model.md) fixed the writer's
shape: forward-only, with one cell encoder shared with the later model.

The owner has since set a wider aim. Phase 1 is a general-purpose XLSX writer,
not an export helper for one app. Monépro and `jet_print` are its first
consumers. They decide what is built first, and they do not shape the API.
Excel is the reference reader: a file that LibreOffice opens but Excel
"repairs" is a bug.

That aim leaves four things the earlier records do not settle. The phase-1
feature list is too small. The output API was left open (0002 did not say
whether `close()` returns bytes or writes to a sink). The earlier records do
not define warnings, and the users who read them speak English, German and
Turkish. "Opens in Excel" has no check behind it yet.

One fact constrains the output. `package:archive` 4.0.9 and 4.5.2 cannot
deflate a single ZIP entry incrementally. An entry is compressed from a whole
byte buffer. 0002 named per-sheet buffering as the fallback for this case:
the adapter buffers each sheet as UTF-8 bytes and compresses it once.

The full design is in
`docs/superpowers/specs/2026-10-24-phase-1-xlsx-writer-design.md`. That folder
is git-ignored, so this record keeps what has to outlive it.

## Decision

**Phase 1 is a general-purpose XLSX writer with Excel as its reference reader.
Its feature set is milestones M1 to M5 below. This record supersedes the phase-1
feature list in 0001.**

- **Scope: M1 to M5.** 0001 and 0002 stay unedited. Where 0001's phase-1 list
  and this record differ, this record wins.
  - **M1, foundation:** XML escaping and a UTF-8 chunked XML writer; OPC parts
    and document properties; the ZIP adapter; the cell encoder; the
    shared-string table; a minimal style registry; multiple sheets with name
    sanitizing and case-insensitive uniqueness; limits and lifecycle errors;
    warnings; a CI job that validates the fixtures with the Open XML SDK and
    LibreOffice.
  - **M2, styling and layout:** fonts, fills (solid, pattern, gradient),
    borders, alignment, cell protection, number formats, column and row
    settings, merges, freeze and split panes, autofilter, sheet view, tab
    colour and visibility.
  - **M3, sheet and workbook features:** hyperlinks, defined names, data
    validation, conditional formatting, page setup, headers and footers, sheet
    and workbook protection (legacy password hash only, no SHA-512), document
    properties.
  - **M4, objects:** rich text, notes, PNG and JPEG images, Excel tables.
  - **M5, helper, proof and release readiness:** `XlsxListExport`, the
    100,000 by 12 benchmark, README, example, changelog, a dartdoc review of
    the public API, the final Excel checklist.
- **Target readers.** Excel 2016 and later on Windows and macOS, and Excel for
  the web. Features that need Excel 2010+ markup emit it, with the 2007 form
  alongside where one exists.
- **Output is synchronous.** `XlsxWriter.close()` returns, it is not `async`.
  Encoding happens in the caller's `row()` calls. A caller who needs a
  responsive UI runs the writer in an isolate or web worker.
- **Two output modes.** In memory (the default): `close()` returns the file as
  bytes with the warnings. To a sink: the writer is given a `Sink<List<int>>`
  from `dart:core`, compressed bytes go to it as each part is finished, and
  `close()` closes it. The in-memory case never hands the caller a nullable
  `bytes`.
- **Buffering is per sheet.** Because `archive` cannot deflate one entry
  incrementally, the adapter holds one sheet's UTF-8 bytes and compresses them
  when the sheet is finished. `addSheet` finishes the previous sheet, so one
  sheet is open at a time. Tab order is independent of write order, because
  `workbook.xml` is written at `close()`.
- **Warnings are structured.** A warning carries a code, the sheet, a count and
  the first ten cell references. They are aggregated per sheet and code, so a
  dirty column of 100,000 rows gives one warning. `message(XlsxLocale)` returns
  text in `en`, `de` or `tr` from hand-written tables, with no `intl`
  dependency. `toString()` is English. A test fails if any code lacks a message
  in any locale. A consumer who needs another language formats the code itself.
- **Errors are English only.** `ArgumentError`, `StateError`, `RangeError` and
  `XlsxLimitError` are read by developers, not end users.
- **Excel compatibility is verified, not assumed.**
  - CI validates every fixture with the Open XML SDK and requires zero errors.
  - CI converts every fixture with LibreOffice headless and compares the result
    with the input values.
  - A test-side consistency checker enforces Excel's cross-part rules that
    pass the schema (unique defined names, table header cells equal to column
    names, non-overlapping merges, correct shared-string counts, present
    relationship targets). Each rule is added with the feature that can break
    it.
  - The owner opens each milestone's fixtures in Excel. A milestone is done
    only when none shows a repair prompt or a wrong value.
- **Public value types are model-neutral.** `XlsxStyle` and its parts, data
  validation, conditional format, defined name, page setup, image and table
  definitions describe SpreadsheetML, not the writer. The phase-3 reader
  parses into the same types, and the same element writers serialize them.
  Types cover the full vocabulary of what they describe, including gradient
  fills. They are `final class`es with named constructors, so fields can be
  added.
- **Output is deterministic** within one platform and one `archive` version.
  ZIP entries carry a fixed timestamp and a fixed order, and
  `docProps/core.xml` holds no "now" unless the caller gives a time. The same
  input then gives the same bytes. Byte-identity across `archive` versions or
  across the VM and JavaScript is not promised.

**Out of phase 1:**

- Reading or modifying files. The random-access model (`XlsxWorkbook`) is
  phase 3. Whether it also gets a "build in memory, write later" mode is
  decided there.
- Charts, sparklines, pivot tables, slicers, threaded comments, form controls
  and external links. They follow phase 1 as separate pieces of work if a
  consumer asks.
- Formula evaluation. Formula text is written and Excel computes it.
- The 1904 date system, `.xlsb`, legacy `.xls` and Strict OOXML.
- Macros and encryption, ever.

## Consequences

**The public API may break between milestones.** No consumer uses a milestone
before M5. Each milestone grows the types it needs, and M5's dartdoc review
settles the shape that ships. There is no release deadline: phase 1 ships when
its features are complete and verified.

**Peak memory is one sheet's UTF-8 bytes (briefly twice while they are handed
to the ZIP adapter), the unique strings and, in memory mode, the compressed
file so far.** It does not scale with cell objects. The 100,000 by 12
benchmark in M5 records time and peak memory on Chrome and on the VM. It is a
recorded figure, not a pass or fail threshold yet.

**CI gains one `validate` job, which runs both the Open XML SDK validation
and the LibreOffice comparison, and a dependency on `dotnet` and
LibreOffice.** Locally they are optional. The three-command gate is unchanged
and still runs first.

**Three languages of messages are three tables to keep complete.** The German
and Turkish texts are written by the builder and checked by a native speaker
before release.

**The consistency checker is test code, so it does not ship.** It reads
fixtures with `package:xml`, a dev dependency. The library's only runtime
dependency stays `archive`.

## What this does not decide

- **The public API's exact names and signatures.** Those are settled
  milestone by milestone and fixed at M5.
- **Phases 2 to 4.** XLSX read, XLSX modify and DOCX keep the shape and order
  in 0001 and 0002.
- **Inline versus shared strings per value.** That stays an encoder detail
  (0002).
- **SHA-512 protection and PPTX.** SHA-512 would need a crypto dependency.
  0001 already excludes PPTX.
- **Publishing.** Removing `publish_to: none` is the owner's decision after M5.
- **How the validation jobs are wired.** A fixture generator, a small `dotnet`
  tool and the LibreOffice command line are the builder's choice.
