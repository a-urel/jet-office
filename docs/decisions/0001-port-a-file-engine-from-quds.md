# 0001 — jet_office is a pure-Dart file engine ported from Quds, not a dependency on it

**Status:** Proposed — 2026-10-24

## Context

Monépro needs to export every list and dashboard it shows, and later to import
customer spreadsheets (current accounts, stock, bank statements) and fill
document templates (contracts, letters, quotes). The Flutter client is the only
place that work can run today. The backend is Supabase. Python is used only by
the AI agent service, so it is not a general backend for exports.
Supabase Edge Functions run TypeScript on Deno, not Dart.

`jet_print` cannot carry this. Its fill pass turns every text value into a
string before layout (`rendering/fill/element_resolver.dart` → `jetStringify`
in `_resolveText`), so the number and date types a spreadsheet needs are gone
before any exporter could see them. Its exports also consume paginated frames,
and a list export has no pages. A list is already rows and typed columns. It
needs a spreadsheet writer, not a report.

`quds_office_suite` (MIT, by Mohammed Asaad Asaad), measured at commit
`15c5d29` (2026-10-20), ships `quds_office_engine` 1.5.0: about 146,000 lines of
pure Dart. It reads and writes OOXML through its own OPC, ZIP, Deflate and XML
layers. The part Monépro would use is small:

| Quds module | Lines | Needed for |
|---|---:|---|
| `xml/` | ~1,650 | everything |
| `opc/` core (content types, relationships, package parts) | ~1,000 | everything |
| `opc/` rest (ZIP/Deflate/CRC ~1,400; OLE, encryption, repair, isolates) | ~5,400 | nothing: ZIP comes from `archive`, the rest is out of scope |
| `builders/xlsx_io.dart` | ~1,180 | XLSX write and simple read |
| `sheet/` model + serial + styles | ~4,500 | XLSX read and modify |
| `sheet/formula` | ~3,800 | evaluating formulas (not needed to write them) |
| `word/` model + serial + properties | ~10,500 | DOCX template fill |

The rest is `pdf/` (~65,000), `reports/` (~29,000), slides, BiDi, fonts and
crypto, none of which Monépro needs. `jet_print` already exports PDF.

Reading the XLSX write path turned up defects a production export would hit.
The XML text escaper (`xml/xml_reader.dart` → `_escape`) passes the control
characters U+0000–U+001F through, and XML 1.0 forbids them, so one stray
character from imported ERP data makes Excel refuse the file.
`XlsxSheetBuilder.setCell` accepts a `DateTime` and writes its `toString()` as
a shared string, not as a date serial. A `NaN` or infinite double is written
verbatim into `<v>`. Duplicate sheet names are not made unique. Quds' tests
touch XLSX in 18 files, and its dartdoc is mostly placeholder text
("`setCell` API.").

## Decision

**`jet_office` is a new pure-Dart package, in its own repository, that ports
the parts of `quds_office_engine` it needs. It does not depend on Quds.**

- **Scope: files only.** Generate, read and modify XLSX and DOCX. No editors, no
  rendering, no PDF, no PPTX, no legacy `.xls`/`.doc`, no macros, no
  encryption.
- **Pure Dart, safe on the web.** No Flutter, no `dart:io`, no `dart:ui` under
  `lib/`. Bytes in, bytes out, so it runs in Flutter web, desktop and mobile
  and in any later Dart server. A guard test enforces the import ban.
- **ZIP through `package:archive`, behind one adapter.** Quds' own ZIP, Deflate
  and CRC code (~1,400 lines) is not ported. `archive` is already in
  `jet_print`'s lockfile through `image`, so a consumer of both gets no new
  package. Only one file may import it, enforced the same way as
  `jet_print`'s `barcode_dependency_isolation_test.dart`.
- **Ported, not copied.** A file is ported when it gets dartdoc, tests and the
  repository's lints. A ported file names its Quds source path and commit in its
  library doc comment. `NOTICE` carries Quds' MIT licence text and copyright
  holder. `jet_office` itself is Apache-2.0, matching `jet_print`.
- **The defects above are fixed during the port, not inherited.** Each fix
  starts with a failing test.
- **Phases, each shippable on its own:**
  1. XLSX write: typed cells, styles, number formats, frozen panes,
     autofilter, column widths, merges, multiple sheets. This covers every
     list and dashboard export.
  2. XLSX read: values and types, for import.
  3. XLSX modify: open a customer's template, fill it, save it.
  4. DOCX write: paragraphs, tables with a repeating header row, page header
     and footer with `PAGE`/`NUMPAGES` fields, inline images. Then template
     fill and mail merge on top of the same model.

  Pictures in XLSX (a logo above a list) come with phase 1 or right after it,
  because report export needs them. Native charts and formula evaluation come
  later, if a real screen asks for them.
- **`jet_print` is the second consumer, and it is planned for.** `jet_print`
  exports XLSX and DOCX through `jet_office`, the way Quds'
  `QudsReportEngine.exportToExcel` / `exportToWord` sit on its own builders.
  The dependency points one way: `jet_office` knows nothing about reports,
  bands or `jet_print` types. A feature `jet_print` needs is added to
  `jet_office` as a general file feature (merges, row heights, pictures,
  header/footer fields), never as a report concept.

## Consequences

**Monépro gets a spreadsheet export it controls.** A defect gets fixed in a day
in a package whose author is the consumer. There is no licence ceiling to grow
past and no upstream to wait for.

**The port costs about 20,000 lines of Quds input through phase 4**, before
tests. That is a large share of `jet_print`'s ~48,000 library lines, and it
competes for the same single developer's time as Monépro itself. Phase 1 alone
is about 4,700 lines of input (XML, OPC core, the builder, styles) and pays for
itself on the first export screen. The later phases are each justified by a screen, not by
completeness.

**Upstream fixes stop arriving for free.** After the port, a Quds bug fix has to
be noticed and ported by hand. The commit recorded in each file header is what
makes a diff against upstream possible. In the other direction, offering the
defect fixes back to Quds as pull requests costs little and is courteous.

**Exports run in the user's browser or app.** For a list already on screen this
is ideal: no round trip, and the data is already loaded. For a very large
export it means the client holds the rows and the compressed file in memory at
once. Phase 1 needs a large-dataset benchmark (100,000 rows on Flutter web)
before it claims to handle large lists. 0002 decides the writer shape that
benchmark tests.

**One more repository to keep green.** It inherits `jet_print`'s conventions
(`AGENTS.md`, the three-command quality gate, ADRs), so the cost is CI minutes
and attention, not new process.

## What this does not decide

- **Server-side export.** Scheduled or e-mailed exports, and exports too large
  for a client, have no runtime yet. Options include a Dart service on Cloud
  Run, the Python agent service with `openpyxl`, or CSV straight from Postgres.
  Each needs its own record.
- **The writer's internal shape.** Streaming versus an in-memory model is
  [`0002`](0002-two-xlsx-paths-stream-and-model.md).
- **The public API.** That is a design document, not a record, until phase 1
  ships.
- **The pub.dev name.** `jet_office` is the working name, and it has not been
  checked against pub.dev.
- **How `jet_print` maps a report to a sheet or a document.** Carrying typed
  values through its fill pass, deriving columns from band elements, and what
  a page break becomes are `jet_print` decisions, recorded there.
