# jet_office

A pure-Dart library that writes and reads XLSX files. Bytes in, bytes out: it
imports no Flutter, no `dart:io` and no `dart:ui`, so the same code runs on the
web, on desktop and mobile, and on a Dart server. It has no editors, no
rendering and no PDF.

## Status

Pre-release (`0.1.0-dev.1`). The package is not published to pub.dev
(`publish_to: none`) until the owner decides. Phase 1 writes XLSX files and
phase 2 reads them. Modifying files, and DOCX, are later phases.

## Installing

Use it as a git dependency:

```yaml
dependencies:
  jet_office:
    git:
      url: https://github.com/a-urel/jet-office.git
```

## Quick start

```dart
final XlsxWriter book = XlsxWriter();
final XlsxSheetWriter sheet = book.addSheet('Accounts');
sheet.columns(const <XlsxColumn?>[
  XlsxColumn(width: 12),
  XlsxColumn(width: 16),
]);
sheet.row(<Object?>[
  'Code',
  'Balance',
], style: const XlsxStyle(font: XlsxFont(bold: true)));
sheet.row(<Object?>['A-1', XlsxDecimal('1234.50')]);
sheet.row(<Object?>['A-2', 99.5]);
sheet.row(<Object?>['Total', const XlsxFormula('SUM(B2:B3)', cached: 1334)]);
final XlsxResult out = book.close();
// out.bytes is the .xlsx file; out.warnings lists what had to be repaired.
```

A cell takes a plain Dart value (`String`, `int`, `double`, `bool`,
`DateTime`) or a wrapper: `XlsxDecimal` for money (a `String` of digits, so no
`double` rounding), `XlsxDate`, `XlsxFormula`, `XlsxHyperlink`, `XlsxRichText`
and `XlsxCell` for a value with its own style. Pass `Decimal.toString()`
to `XlsxDecimal` if you hold amounts as `Decimal`.

## Reading

`XlsxReader` reads an XLSX file from bytes, such as a user's upload for a
data import. Opening it reads only the ZIP directory, the content types, the
package and workbook relationships, the workbook and its styles; a sheet is
parsed lazily as its rows are taken. Reading the quick start's workbook back:

```dart
final XlsxReader reader = XlsxReader(out.bytes);
print(reader.sheets.first.name); // Accounts
for (final XlsxReadRow row in reader.rows('Accounts')) {
  // row.index and cell.column are 0-based: row 0, column 0 is A1.
  for (final XlsxReadCell cell in row.cells) {
    final String formula = cell.formula == null ? '' : ' = ${cell.formula}';
    print('${row.index}:${cell.column} ${cell.value}$formula');
  }
}
// A sheet's warnings are complete once its rows have been read.
for (final XlsxWarning warning in reader.warnings) {
  print(warning.message());
}
```

This prints `1:1 XlsxDecimal(1234.50)` for the balance of `A-1` and
`3:1 XlsxDecimal(1334) = SUM(B2:B3)` for the total: a formula cell's value is
the result the file cached, as the reader does not calculate.

A value is a `String`, a `bool`, an `XlsxDecimal`, a `DateTime`, a
`Duration`, an `XlsxErrorValue` or `null`. A number keeps the file's digits
in an `XlsxDecimal`; `toDouble()` and `toIntOrNull()` convert on request. A
number whose number format shows a date is a UTC `DateTime`, one whose format
shows only a time a `Duration`. A cell also carries its formula text, its
shared or array formula group and its number format (`numberFormatId`,
`numberFormat`, `isDate`), and `reader.merges(name)` lists a sheet's merged
ranges.

The file is treated as untrusted input. A file that cannot be read at all
(not a ZIP, encrypted, a legacy `.xls`, malformed XML, or past one of the
`XlsxReadLimits`) throws an `XlsxReadException` whose `reason` says why. A
cell or sheet that cannot be read exactly is kept as far as possible and
reported in `reader.warnings`, with the same `XlsxWarning` type and locales
the writers use: a formula without a cached result, for example, reads as
`null` with a `formulaWithoutValue` warning.
[`docs/xlsx-reader.md`](docs/xlsx-reader.md) has the rules the reader
enforces.

## List export

`XlsxListExport` writes a whole list in one call: an optional caption, a
frozen header that repeats on every printed page, the rows under an auto
filter, and a totals row built from `SUBTOTAL` formulas, so rows a filter
hides stay out of the total.

```dart
const List<XlsxListColumn> columns = <XlsxListColumn>[
  XlsxListColumn('Code', width: 12),
  XlsxListColumn(
    'Amount',
    width: 16,
    style: XlsxStyle(numFmt: XlsxNumFmt.thousands2),
    totalsFunction: XlsxTotalsFunction.sum,
  ),
];
final XlsxResult out = XlsxListExport(columns, caption: 'Accounts').toXlsx(
  <List<Object?>>[
    <Object?>['A-1', XlsxDecimal('1234.50')],
    <Object?>['A-2', 99.5],
  ],
);
```

Pass `excelTable: true` to get an Excel table instead of a filtered range.
To put a list on a sheet of a bigger workbook, call
`XlsxListExport.writeTo(sheet, rows)`.
[`example/jet_office_example.dart`](example/jet_office_example.dart) does that,
adds a summary sheet written with `XlsxWriter`, and reads the file back with
`XlsxReader`. Run it with `dart run example/jet_office_example.dart`.

## What it writes

The writer supports, by milestone:

- **M1:** values (text, numbers, booleans, dates, decimals, formulas),
  sheets, document properties, streaming output, warnings.
- **M2:** styles, column and row sizes, outlines, sheet views, freeze panes,
  merged cells, the auto filter.
- **M3:** defined names, print areas and titles, hyperlinks, data validation,
  conditional formatting, page setup, headers and footers, protection.
- **M4:** rich text, notes, pictures, tables.
- **M5:** the list export helper, the benchmark and this release.

[`docs/xlsx-writer.md`](docs/xlsx-writer.md) has the full list, the rules the
writer enforces and the port map.

## Warnings and locales

Data the writer has to change to store it (text with characters XML forbids, a
sheet name Excel refuses, a date outside Excel's range) is repaired and
reported, not thrown. `close()` returns the warnings, one per sheet and kind,
with the first cells affected. A message comes in English, German or Turkish.

```dart
final XlsxWriter book = XlsxWriter();
book.addSheet('Notes').row(<Object?>['bad\u0001text']);
for (final XlsxWarning warning in book.close().warnings) {
  print(warning.message(XlsxLocale.tr));
}
```

A programmer error is thrown instead: `ArgumentError` naming the field,
`StateError` for a call out of order and `XlsxLimitError` past an Excel limit.
Those messages are in English only.

## The web, isolates and streaming

The library is web-safe: the tests run on the VM and in Chrome. Every call is
synchronous, so there is no `async` API; an `async` wrapper would not move the
work off your thread. To keep a user interface responsive, run the writer in
an isolate (`Isolate.run`) or a web worker and send the bytes back, and run
the reader there too and send the values back.

`XlsxStreamWriter` sends the file to a sink instead of returning it. Each
finished sheet is compressed and sent to the sink at once, but the open sheet
is still held in memory, so the saving shows across many sheets, not within
one large sheet (see "Reading the figures" in
[`docs/benchmark.md`](docs/benchmark.md)):

```dart
final BytesBuilder file = BytesBuilder(copy: false);
final XlsxStreamWriter book = XlsxStreamWriter(
  ByteConversionSink.withCallback(file.add),
);
final XlsxSheetWriter sheet = book.addSheet('Rows');
for (int i = 0; i < 1000; i++) {
  sheet.row(<Object?>[i, 'row $i']);
}
final List<XlsxWarning> warnings = book.close();
```

The figures for 100,000 rows of 12 columns are in
[`docs/benchmark.md`](docs/benchmark.md). On the machine measured, writing
them took about 1.5 s on the VM and 3.1 s in Chrome, and reading them back
2.7 s on the VM and 3.3 s in Chrome: reading is slower than writing on the
VM, and parsing the sheet XML, not unzipping it, takes most of that time.

A small upload can still cost a lot to read. The reader's default limits let
a file of about 2 MB expand to 256 MiB of XML in its largest single sheet;
reading such a sheet took about 19 s and lifted the browser's heap by about
1 GB ("Worst case" in [`docs/benchmark.md`](docs/benchmark.md)). That is one
sheet: the shared strings part may be as large and is held while a sheet is
read, and a workbook may hold several such sheets, up to `maxTotalBytes`
(1 GiB) of XML in all, each costing as much to read again. If you read
uploads in a browser, run the reader in a web worker, and if your uploads
are small, pass `XlsxReadLimits(maxEntryBytes: ..., maxTotalBytes: ...)`
with lower bounds: time and memory follow the size of the XML.

## How files are verified

- Every generated part is checked for well-formed XML and for the package
  rules by the tests.
- CI validates every fixture with the Open XML SDK against the Microsoft 365
  schemas, and compares LibreOffice's reading of each with the expected
  values.
- Neither is Excel, so the owner opens each writer milestone's fixtures in
  Excel and records the result in
  [`docs/excel-checks.md`](docs/excel-checks.md).
- The reader reads every fixture back to what the writer stored, and reads
  packages shaped like those of LibreOffice, Google Sheets, the .NET Open XML
  SDK and an ERP export. CI also has LibreOffice re-save every fixture as
  XLSX and reads that file back against the expected values.
- Hostile files are tested per limit and per kind of damage, and a seeded
  fuzz test mutates the fixtures and producer packages and requires the
  reader to throw nothing but `XlsxReadException`.
- Files saved by Excel and Google Sheets themselves, with values the owner
  confirms, are still pending.
- Part contents are byte-identical on every platform. The ZIP bytes are
  identical only on one platform, because compression can differ.

## Limits

- XLSX only. No modifying files, no DOCX. The writer writes no charts,
  pivot tables, macros or encryption.
- The reader reads values, formulas, number formats and merged ranges; it
  reads no other styles, notes, pictures or tables, and does not calculate
  formulas. It refuses Strict OOXML, `.xlsb`, legacy `.xls` and encrypted
  files with an `XlsxReadException`.
- The reader gives a cell's value and its number format code, not the text
  Excel shows (`00123`, `28.10.2026`): a number format engine is planned
  after phase 2.
- Uploads are untrusted: the reader stops at the `XlsxReadLimits` it is given
  (by default, for example, 256 MiB per inflated part and a compression ratio
  of 1,000). Lower them for small uploads (see above).
- Sheet protection and workbook protection use Excel's legacy password hash.
  It keeps honest users out; it is not security.
- Nothing is measured, so column widths come from you. A pure-Dart writer has
  no font metrics.
- Excel's own limits apply and throw `XlsxLimitError` (`XlsxLimits`). Text
  past 32,767 characters is cut with a warning.
- A `DateTime` is cut to whole seconds. To keep milliseconds, write the serial
  as a `double` with an `ss.000` number format.

## Licence

Apache License 2.0, see [`LICENSE`](LICENSE). Parts are ported from
`quds_office_engine` (MIT); its licence text is kept in [`NOTICE`](NOTICE).
