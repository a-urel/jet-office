# XLSX writer

What phase 1 builds and the rules it holds to. The writer's shape comes from
[`0001`](decisions/0001-port-a-file-engine-from-quds.md) and
[`0002`](decisions/0002-two-xlsx-paths-stream-and-model.md). The phase-1 scope,
output shape and diagnostics are
[`0003`](decisions/0003-phase-1-scope-output-and-diagnostics.md). The draft API
lives in a git-ignored working document under `docs/superpowers/`. This page
keeps what has to outlive it.

Until phase 1 ships, this page describes the target. Once a rule below has a
test, its row names that test.

## Rules the writer enforces

Data problems become warnings and the file still opens. Programmer errors
throw. This follows `jet_print`'s "render, don't crash, report diagnostics"
habit.

| Case | Behaviour | Why |
|---|---|---|
| Sheet name with `[ ] : * ? / \`, longer than 31, or empty | sanitized, warning | Excel refuses the file otherwise |
| Duplicate sheet name (case-insensitive) | suffixed ` (2)`, warning | same |
| Control character U+0000–U+001F other than tab, LF, CR | removed, warning | XML 1.0 forbids it |
| Text longer than 32,767 characters | truncated, warning | Excel's cell limit |
| Row 1,048,577 | `XlsxLimitError` | the caller decides whether to split into sheets |
| `NaN` / infinity | `ArgumentError` | no valid XML number exists |
| `XlsxDecimal` text that is not plain digits | `ArgumentError` | see [Money](#money) |
| A cell value of an unsupported type | `ArgumentError` | a value is a programmer's choice, so guessing would hide the bug |
| Column/freeze/header setting after the first row | `StateError` | forward-only writer (0002) |
| `close()` twice, or a row after `close()` | `StateError` | |

## Money

Monépro holds amounts in `Decimal` from `package:decimal`. On 2026-10-24 its
client used `decimal ^3.2.6` in 360 files, and its amount fields were 419
`Decimal` against 42 `double`.

- **`XlsxDecimal` takes a `String`.** Monépro writes
  `XlsxDecimal(amount.toString())`. `Decimal.toString()` always prints plain
  digits, `-?\d+(\.\d+)?`, with no exponent and no grouping. The encoder
  writes those digits into `<v>` verbatim, so `0.1` stays `0.1` and no
  `double` round trip happens on the Dart side.
- **`jet_office` does not depend on `package:decimal`.** `archive` stays the
  only runtime dependency (0001), and `jet_print` would otherwise inherit
  `decimal`. Accepting `Decimal` directly would need a new decision record.
- **Anything but plain digits throws.** `XlsxDecimal('1.234,56')`,
  `XlsxDecimal('1e3')` and `XlsxDecimal('')` raise an `ArgumentError`, because
  the caller built the string.
- **A `double` column passes a `double`.** The encoder writes it as a number
  and rejects `NaN` and infinity.
- **Excel keeps 15 significant digits.** It reads every number as an IEEE
  double. Money fits easily. `XlsxDecimal` prevents a second rounding in Dart,
  not Excel's own.

## Port map

Each file below names its Quds source path and commit in its library doc
comment (AGENTS.md). Quds paths are relative to
`../quds_office_suite/packages/quds_office_engine/lib/src/`, at commit
`15c5d29`.

| jet_office file (`lib/src/`) | Ported from Quds | Changes |
|---|---|---|
| `xml/xml_escape.dart` | `xml/xml_reader.dart` → `encodeXmlText`, `encodeXmlAttribute` | strips forbidden control characters, reports them |
| `xml/xml_writer.dart` | `xml/` writer used by `sheet/serial/sheet_serial.dart` | writes UTF-8 bytes in chunks, not one string |
| `opc/` (content types, relationships, part names) | `opc/content_types.dart`, `opc/relationships.dart`, `opc/opc_archive.dart` (write side) | write-only in phase 1, no crypto |
| `zip/archive_adapter.dart` | — (new) | the only file that imports `package:archive` |
| `xlsx/cell_encoder.dart` | `builders/xlsx_io.dart` → `_sheetXml` cell branch | the one encoder from 0002: dates, decimals, formulas, NaN |
| `xlsx/style_registry.dart` | `builders/xlsx_io.dart` → `style`, `_Font`, `_Fill`, `_Border`, `_Xf`; `sheet/styles/` | value-typed `XlsxStyle`, built-in number format ids |
| `xlsx/xlsx_writer.dart` | `builders/xlsx_io.dart` → `XlsxWorkbookBuilder`, `XlsxSheetBuilder` | streams rows, shared strings written last |
| `xlsx/sheet_name.dart` | `builders/office_markup.dart` → `sheetName` | case-insensitive uniqueness |
| `xlsx/xlsx_table.dart` | — (new) | |
| `xlsx/shared_strings.dart` | `sheet/shared_strings.dart` | written last, `count`/`uniqueCount` checked |
| `xlsx/styles/` (fonts, fills, borders, alignment, protection) | `sheet/styles/sml_styles.dart` | model-neutral value types, gradient fills added (M2) |
| `xlsx/validation.dart`, `xlsx/conditional_format.dart`, `xlsx/defined_names.dart`, `xlsx/table_part.dart`, `xlsx/protection.dart` | `sheet/serial/sheet_serial.dart` (data validation, conditional formats, defined names, table part, protection) | element writers take the public value types (M3, M4) |
| `xlsx/drawing.dart` | `sheet/serial/sheet_drawing_io.dart` | PNG and JPEG, one-cell and two-cell anchors (M4) |

Out of phase 1: see [`0003`](decisions/0003-phase-1-scope-output-and-diagnostics.md).
