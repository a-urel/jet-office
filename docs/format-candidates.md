# Format candidates

**Date:** 2026-10-28. **Status:** Assessment only. Nothing here is decided or
scheduled; each format needs its own decision record before any code.

This page records what it would cost `jet_office` to support file formats
other than XLSX and DOCX, so a later phase can start from it instead of
redoing the analysis. Figures are rough estimates made against `main` at
`2bfeec7` (end of phase 1), when `lib/` held about 15,700 lines, nearly all
of them under `lib/src/xlsx/`.

## Summary

| Format | Cost | Risk | Likely need |
|---|---|---|---|
| CSV | Low: days | Low | Plausible (list export, import) |
| ODS, minimal | Medium: one milestone | Medium | Low: LibreOffice opens XLSX |
| Quattro Pro (`.qpw`) | Medium to high | Medium | Near zero |
| Apple iWork (`.numbers`, `.pages`) | Very high, ongoing | High | Very low: Numbers and Pages open XLSX and DOCX |

**Recommendation at the time of writing:** CSV is the only candidate worth
building without a concrete consumer request. The others wait for a consumer
(Monépro or `jet_print`) to ask for them by name.

## What carries over

The layers decisions 0001 and 0002 keep apart are what a second format can
reuse:

- `lib/src/xml/` (writer, escaping, number text): format-neutral, reusable
  as is by any XML format.
- `lib/src/zip/archive_adapter.dart`: reusable by ZIP-based formats, with
  changes noted per format below.
- The value wrappers, warning model and locale messages: reusable as concepts.

Everything OOXML-specific does not carry over: `lib/src/opc/`, the cell
encoder (decision 0002), the style registry's index model, and the XLSX parts
for conditional formats, validation, tables, drawings and notes.

## CSV

There is no CSV support in `lib/`. CSV appears only in the validation tooling
(`tool/compare_csv.dart`, `tool/src/csv_compare.dart`), where LibreOffice's
CSV export is the oracle for fixture values. Decision 0001 mentions "CSV
straight from Postgres" as one option for server-side export, undecided.

**Cost:** about 200 to 400 lines in `lib/` plus tests. `XlsxListExport`'s
column and value handling is largely reusable.

**Design questions a record must settle:**

- **Delimiter.** Excel in Turkish and German locales expects `;` because the
  decimal separator is a comma. The delimiter needs to follow the locale or
  be an option.
- **Encoding.** Excel reads UTF-8 correctly only with a BOM; without one,
  Turkish characters break.
- **Quoting and line endings.** RFC 4180: CRLF, and fields with the
  delimiter, a quote or a line break are quoted.
- **Types.** CSV carries none. Dates and numbers are written as text, and
  Excel guesses on open.
- **Formula injection.** User data starting with `=`, `+`, `-` or `@` can run
  as a formula in Excel. Such cells are escaped and reported with a warning
  code, which needs messages in `en`, `de` and `tr` like every other code.

## ODS (OpenDocument spreadsheet)

LibreOffice's native format. ODT is the word-processing counterpart and is
not assessed here; it belongs after DOCX exists.

| Area | Carries over? | Work |
|---|---|---|
| ZIP | Partly | ODF requires a `mimetype` entry first and stored uncompressed. The adapter needs entry order and stored entries. |
| XML layer | Yes | None. |
| Package parts | No | `META-INF/manifest.xml` replaces OPC content types and relationships. |
| Cells | No | `table:table-cell office:value-type="float"`, no shared strings, no style indexes. Needs its own encoder rule next to decision 0002. |
| Styles | Model only | Named `style:style family="table-cell"` plus a separate `number:number-style` tree for number formats. One of the largest parts. |
| Formulas | No | ODS expects OpenFormula (`of:=SUM([.A1:.B2])`). Excel formula text needs a tokenizer and translator. The largest risk. |
| Conditional formats, validation | No | Different structure, partly in `calcext:` extensions. |
| Tables, images, notes | No | `table:database-range`, `draw:frame`, `office:annotation`. |

**Scopes:**

- **A. Minimal export:** values (numbers, text, dates, booleans), basic
  styles, column widths, merges, freeze panes, several sheets, no formulas
  (cached values only). About 3,000 to 4,000 lines in `lib/` and as much
  again in tests; one milestone the size of M1 or M2.
- **B. A plus formulas:** add 2,000 to 3,000 lines for the OpenFormula
  translator, with many edge cases.
- **C. Parity with XLSX:** 10,000 lines or more, in effect a second writer.

**Validation:** CI would add an ODF validator (`odfvalidator`, Java). The
existing LibreOffice CSV comparison works for ODS almost unchanged, which is
the main thing that makes ODS affordable.

**First design question:** a separate `OdsWriter`, or a format-neutral sheet
model both writers render. `XlsxWriter`'s API is XLSX-specific; this choice
drives the cost more than anything else.

## Quattro Pro

Corel's spreadsheet, part of WordPerfect Office.

| Format | Structure | Documentation |
|---|---|---|
| `.wq1`, `.wq2` (DOS) | Binary records, Lotus 1-2-3 style | Old, partly documented |
| `.wb1`, `.wb2`, `.wb3` (Windows) | Binary; `.wb3` inside an OLE compound file | Sparse |
| `.qpw` (Quattro Pro 9 and later) | Binary record stream inside an OLE2 compound file (CFB) | No official specification; LibreOffice reads it through `libwps`, read only |

**Cost:**

- **Container.** A pure-Dart, web-safe CFB writer. Quds has one
  (`opc/ole/cfbf_writer.dart` and `cfbf_reader.dart`, 1,125 lines at
  `15c5d29`, see decision 0004), which lowers this part.
- **Records.** Little-endian binary records for cells, styles and sheet
  structure. None of `lib/src/xml/` applies.
- **Formulas.** Translation from Excel formula text to Quattro's binary
  tokens. The largest risk again.
- **Validation.** No validator. LibreOffice reads `.qpw`, so the CSV
  comparison can partly be reused. A real check needs a licensed Quattro Pro
  on Windows.
- **Maintenance.** The format is frozen, so breakage risk is low.

Rough size: a few weeks to a month or two for a minimal `.qpw` writer
(values and basic styles, CFB writer included), formulas and parity on top.

**Why it is not worth it now:** the user base is small (mostly legacy
WordPerfect installations in legal and public-sector settings), and no
consumer has asked for it. Recent Quattro Pro versions are believed to open
XLSX; **this was not verified** and should be checked before any decision.

**Link to encryption:** the CFB container is also what encrypted XLSX and
DOCX need (decision 0004). If a CFB writer is ever ported, encryption is the
reason; Quattro Pro would be a side benefit.

## Apple iWork

Numbers (`.numbers`), Pages (`.pages`) and Keynote (`.key`) have used the
IWA format since 2013. It has no published specification.

| Area | State |
|---|---|
| Container | A ZIP or a macOS package directory, holding `Index.zip` with `.iwa` files. The ZIP adapter partly applies. |
| Compression | An Apple variant of Snappy framing without CRCs. Needs a pure-Dart Snappy to stay web-safe. |
| Data | Protocol Buffers messages. `package:protobuf` is pure Dart, but the `.proto` schemas are not official: the community extracts them from Apple's binaries. Their licence and provenance are unclear, which conflicts with the provenance rule in `AGENTS.md`. |
| Model | Object graphs linked by IDs for cells, styles and formulas, undocumented. Formulas use their own binary tree form. |
| Stability | Apple can change the schema with any Numbers or Pages release. A writer that works today may produce files a later version refuses. |
| Validation | No validator. LibreOffice's `libetonyek` reads iWork only. The only real check is opening the file in Numbers on a Mac, which is hard to automate in CI. |

**Scopes:**

- **Reading Numbers (values only):** several weeks plus ongoing upkeep.
  References: `numbers-parser` (Python) and SheetJS's partial support.
- **Writing Numbers files that open cleanly:** months, high risk; missing an
  undocumented required field corrupts the file silently.
- **Pages, Keynote:** each a separate and larger project.

**Cheaper alternative:** what Mac users usually need is for the file to open
in Numbers or Pages, which XLSX and DOCX already do. Opening a milestone's
fixtures in Numbers once and recording the result in `docs/excel-checks.md`
costs far less than an iWork writer.

## When to revisit

Reopen this page when one of these happens:

- A consumer asks for a format by name, with the use case.
- Server-side export is decided (decision 0001 lists it as open); CSV may
  come with it.
- A CFB writer is ported for encryption (decision 0004), which lowers the
  cost of Quattro Pro and other CFB-based formats.
- A format-neutral sheet model is proposed for another reason, which lowers
  the cost of ODS.
