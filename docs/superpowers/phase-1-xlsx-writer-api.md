# Phase 1 — XLSX writer: API draft

Working document (git-ignored under `docs/superpowers/`, per the `jet_print`
convention). It describes the API phase 1 should ship and the port map behind
it. The snippets have **not been compiled**. They are the target shape, and the
first TDD round makes them real.

Decisions it builds on: [`0001`](../decisions/0001-port-a-file-engine-from-quds.md),
[`0002`](../decisions/0002-two-xlsx-paths-stream-and-model.md).

## 1. What a Monépro screen needs

| Screen kind | Needs |
|---|---|
| A list (current accounts, stock, invoices) | header row, typed columns, ₺ and date formats, frozen header, autofilter, column widths, optional totals row |
| A filtered list | the filters written above the table ("Tarih: 01.10–24.10, Şube: Merkez"), then the table |
| A dashboard | one summary sheet (KPI label/value pairs) plus one sheet per underlying list |
| Any export | a file name and sheet names that never make Excel refuse the file, with Turkish characters intact |

Everything below exists to serve that table. Anything that does not is out of
phase 1.

## 2. The surface

### Values

A cell accepts `null`, `String`, `int`, `double`, `bool`, `DateTime`, or one of
three wrappers:

```dart
XlsxDecimal('1234.56')        // digits written verbatim; for money from
                              // numeric columns, so no double round trip
XlsxDate(2026, 10, 24)        // date only, no time part
XlsxFormula('SUM(C2:C101)')   // written as a formula; Excel computes it on open
```

Anything else throws `ArgumentError`. A value is a programmer's choice, so
guessing would hide the bug.

A `DateTime` is written from its wall-clock fields (year…second) as a
1900-system serial. `isUtc` is ignored on purpose: Excel has no time zones, and
a user expects to see the time the screen showed.

### Styles and number formats

```dart
const XlsxStyle header = XlsxStyle(
  bold: true,
  fill: XlsxColor(0xFFF2F2F2),
  border: XlsxBorder.thin,
  horizontal: XlsxAlign.center,
);

const XlsxStyle money = XlsxStyle(numFmt: XlsxNumFmt.money('₺'));
// → format code  #,##0.00 "₺"   (Excel localizes the separators itself,
//   so Turkish Excel shows 1.234,56 ₺)

const XlsxStyle date = XlsxStyle(numFmt: XlsxNumFmt.localeShortDate);
// → built-in format 14: shows in the reader's own date order
```

A style is an immutable value. The writer deduplicates by `==` into its
registry, so callers never handle the integer ids Quds' `style()` returns.
`XlsxStyle.merge(other)` overlays a column style with a row style, for example
a bold totals row on a money column.

### Writer

```dart
final XlsxWriter book = XlsxWriter(
  properties: const XlsxProperties(title: 'Cari Hesaplar', creator: 'Monépro'),
);

final XlsxSheetWriter sheet = book.addSheet('Cari Hesaplar');

// Header-section settings: must be set before the first row (0002).
sheet
  ..columns(const <XlsxColumn>[
    XlsxColumn('Kod', width: 12),
    XlsxColumn('Ünvan', width: 40),
    XlsxColumn('Bakiye', width: 16, style: money),
    XlsxColumn('Son Hareket', width: 14, style: date),
  ])
  ..freeze(rows: 1)
  ..pageHeader('Cari Hesaplar')
  ..pageFooter('Sayfa &P / &N');           // Excel page fields

sheet.headerRow(style: header);            // writes the column titles
for (final Cari c in rows) {
  sheet.row(<Object?>[c.kod, c.unvan, XlsxDecimal(c.bakiye), c.sonHareket]);
}
sheet.totalsRow(<int, XlsxTotal>{2: XlsxTotal.sum}, label: 'Toplam');
// → SUBTOTAL(109, C2:C{last}), so the total follows the autofilter

final XlsxResult out = book.close();
// out.bytes    → Uint8List
// out.warnings → e.g. "3 cells had control characters removed (B17, B204, …)"
```

`autoFilter` is on by default for a sheet that has a header row. A
`XlsxSheetWriter` also has `row(values, style:)`, `blankRow()`, `merge(...)` for
the filter caption above a table, and `rowCount`.

### One-call helper for lists

Most screens are exactly "columns + rows", so they get one call:

```dart
final Uint8List bytes = XlsxTable.export(
  sheetName: 'Stok Listesi',
  caption: 'Depo: Merkez · 24.10.2026',   // optional merged line above
  columns: columns,
  rows: rows,                               // Iterable<List<Object?>>
  totals: const <int, XlsxTotal>{4: XlsxTotal.sum},
).bytes;
```

`XlsxTable` is built on `XlsxWriter` and has no logic of its own. Monépro's
list widget passes its column model straight in.

## 3. Rules the writer enforces

| Case | Behaviour | Why |
|---|---|---|
| Sheet name with `[ ] : * ? / \`, longer than 31, or empty | sanitized, warning | Excel refuses the file otherwise |
| Duplicate sheet name (case-insensitive) | suffixed ` (2)`, warning | same |
| Control character U+0000–U+001F other than tab, LF, CR | removed, warning | XML 1.0 forbids it |
| Text longer than 32,767 characters | truncated, warning | Excel's cell limit |
| Row 1,048,577 | `XlsxLimitError` | the caller decides whether to split into sheets |
| `NaN` / infinity | `ArgumentError` | no valid XML number exists |
| Column/freeze/header setting after the first row | `StateError` | forward-only writer (0002) |
| `close()` twice, or a row after `close()` | `StateError` | |

Data problems become warnings and the file still opens. Programmer errors
throw. This follows `jet_print`'s "render, don't crash, report diagnostics"
habit.

## 4. Port map

| jet_office file (`lib/src/`) | Ported from Quds (`quds_office_engine/lib/src/`) | Changes |
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

Not ported in phase 1: charts and pictures (`addChart`, `addPicture`), the
reader (`XlsxGridReader`, phase 2), `SmlWorkbook` (phase 3), formulas,
encryption.

## 5. Tests and checks

- **Encoder unit tests first.** One test per row of §3, plus date serial
  edges: 1900-03-01 (after Excel's phantom 29 Feb 1900), midnight, 23:59:59.999
  rounding.
- **Part goldens.** The XML of each part (`sheet1.xml`, `styles.xml`,
  `sharedStrings.xml`, `workbook.xml`, `[Content_Types].xml`) is compared as
  text for a fixed fixture, so a change in output is a visible diff.
- **Opens in a real reader.** In CI, LibreOffice headless converts each
  fixture to CSV, and the CSV is compared with the input rows. This catches
  "Excel found a problem" bugs that goldens cannot see. Excel itself is a
  manual check before release.
- **Guards.** No `dart:io`, `dart:ui` or Flutter imports under `lib/`. Only
  `archive_adapter.dart` imports `archive`. Only `cell_encoder.dart` writes `<c `
  or `<v>`.
- **Benchmark.** 100,000 × 12 mixed cells on Flutter web (Chrome): time and
  peak memory, recorded the same way `jet_print`'s roadmap records its
  10k/50k figures.

## 6. Open questions

1. **Package name.** Is `jet_office` free on pub.dev? Not checked.
2. **Repository.** A separate `a-urel/jet-office` (0001 assumes so) or a
   member of the `jet-print` workspace?
3. **Money type.** What does Monépro's client hold an amount in: `double`,
   `String`, or a decimal package? `XlsxDecimal` assumes the digits are
   available as a string.
4. **`close()` sync or async.** Sync is simpler. Async leaves room for an
   adapter that compresses in chunks and yields to the event loop on web.
   Decide once the `archive` check in 0002 is done.
