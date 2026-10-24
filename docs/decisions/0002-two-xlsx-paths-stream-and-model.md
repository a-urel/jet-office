# 0002 — Two XLSX paths, a forward-only writer and a workbook model, sharing one cell encoder

**Status:** Proposed — 2026-10-24

## Context

[`0001`](0001-port-a-file-engine-from-quds.md) puts two different jobs in one
package. Phase 1 exports: rows arrive in order, are written once and never
revisited, and there can be many of them. Phases 2 and 3 import and modify:
open a file someone else wrote, look anywhere in it, change cells, and save
it with everything not touched kept intact.

Quds already has both, as two unrelated implementations.
`builders/xlsx_io.dart` → `XlsxWorkbookBuilder` holds every row as
`List<List<XlsxCell?>>` and concatenates XML into a `StringBuffer` at `build`.
`sheet/model/sml_workbook.dart` → `SmlWorkbook`, read and written by
`sheet/serial/sheet_serial.dart` through an `XmlWriter`, is the round-trip
model. They do not share how a cell value becomes XML. The builder writes a
`DateTime` as a string. Neither strips the control characters XML 1.0 forbids,
because both use the same escaper. Two encoders means two places for each bug.

The export case sets the memory budget. A Monépro list of 100,000 rows by 12
columns is 1.2 million cells. Built as a model in Flutter web, that is 1.2
million Dart objects before any XML exists. Then comes the XML itself as a
Dart string, which is UTF-16 and so twice its UTF-8 size. Then the ZIP. The
builder approach holds all three at once. Most of the cells in such a list are
numbers, dates and a few repeated strings (a currency, a status, a branch).

Excel puts no order on the parts of a ZIP. The shared-string table can be
written after the sheets that index into it, so a writer can stream sheet rows
out and keep only the unique strings in memory.

## Decision

**`jet_office` has two XLSX paths, and both go through one cell encoder.**

1. **`XlsxWriter`: forward-only, for export (phase 1).** Sheets are written one
   after another and rows top to bottom. A row is encoded to UTF-8 XML as it is
   appended and handed to the ZIP adapter. Nothing written can be read back or
   changed. What stays in memory: the unique strings (shared-string table,
   written last), the style registry, merges, and the column and pane settings
   (written in the sheet header, so they must be set before the first row).
   Calling these setters after the first row throws a `StateError`; it does
   not silently do nothing.
2. **`XlsxWorkbook`: a model, for read and modify (phases 2 and 3).** It is
   ported from `SmlWorkbook` and `sheet_serial.dart`. Parts it does not
   understand are kept as raw bytes and written back unchanged. This is the
   same idea as `jet_print`'s `UnknownElement`: opening and saving a customer's
   template must not lose what the library cannot read.
3. **One cell encoder, one style registry, one XML escaper.** A cell value
   becomes XML in exactly one function, which both paths call. That function
   handles strings (strip forbidden control characters, mark leading or
   trailing spaces `xml:space="preserve"`), numbers (reject `NaN` and
   infinity), decimals written from their digits so `0.1` stays `0.1`, dates
   (wall-clock fields to a 1900-system serial, never via UTC), booleans and
   formulas. A guard test fails if any other file under `lib/` writes `<c ` or
   `<v>`. It plays the same role `jet_print`'s one-paint-path rule plays for
   pictures.

## Consequences

**Export memory scales with unique strings, not rows.** That is the property
the 100,000-row benchmark in 0001 measures. Until the benchmark exists it is a
design claim, not a result.

**The writer cannot do anything that needs hindsight.** Column widths fitted to
content, a totals row whose position is known only at the end, or a header
that changes after the data: a caller does these with what it knows up front.
Fixed widths come from column definitions. Totals are formulas such as
`SUBTOTAL(109, C2:C100001)`, written when the row count is known, which is
after the last data row. Fitting widths by sampling the first N rows is a
possible later option. It is not in phase 1.

**Two paths are more code than one.** A model-only design (Quds' `SmlWorkbook`
for everything) was rejected over the memory figure above. A writer-only design
was rejected because phases 2 and 3 need random access. The shared encoder is
what keeps the two from drifting the way Quds' two did. Every value rule is
tested once, at the encoder, and both paths are tested to call it.

**Streaming depends on the ZIP adapter.** Whether `package:archive` can deflate
one entry incrementally is the first thing phase 1 checks. If it cannot, the
adapter buffers each sheet as UTF-8 bytes and compresses once per sheet. That
still halves the string memory and still avoids the cell objects. The public
API does not change either way, because only the adapter knows.

## What this does not decide

- **Inline strings versus a shared-string table.** The table is the default
  because it is what Excel writes and it compresses repeated values. Using
  `inlineStr` for long unique text is an encoder detail that can change without
  changing the API.
- **DOCX.** Phase 4 decides its own shape. Template filling probably wants only
  a model.
- **Formula evaluation.** The writer writes formula text and Excel computes it
  when the file opens. Porting `sheet/formula` is not part of either path.
- **Threading.** Running the writer in an isolate (or a web worker) is a
  caller's choice. The writer keeps no global state, so either works.
