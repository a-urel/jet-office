# Owner files

Real `.xlsx` files saved by Excel and Google Sheets, each with the values
the owner confirmed. `test/xlsx/read/owner_files_test.dart` (VM only) reads
every file listed in `manifest.json` with `XlsxReader` and compares it with
its `.expected.json`. While the manifest is `[]` the test only prints
`owner files pending`. Why these files exist: decision 0007; the plan's
ruling 12.

Every `*.xlsx` and `*.expected.json` here must be listed in
`manifest.json` (by `.xlsx` name) and have its partner, or the test fails.
`README.md` and `manifest.json` are the only other files that belong here.

## The files

Both programs make the same two workbooks, so a difference between the
producers shows up as a difference between files, not in the data. Save
each file as the program writes it and commit it unmodified. For Google
Sheets use File, Download, Microsoft Excel (.xlsx).

1. `excel_products.xlsx` and `gsheets_products.xlsx`. Sheet `Ürünler`,
   about 30 rows, header in row 1:
   - A `Kod`: text with leading zeros (`00123`).
   - B `Barkod`: a 13-digit number (`8690000000017`) shown with format `0`.
   - C `Ürün adı`: Turkish letters (`İıĞğŞşÇçÖöÜü`); one cell with a line
     break; one rich-text cell (part bold).
   - D `Fiyat`: two decimals in a ₺ currency format; one price `0.10`, one
     `1234567.89`.
   - E `KDV`: a percent (`20%`).
   - F `Fiyat (KDV dahil)`: the formula `=D2*(1+E2)`.
   - G `Kategori`: merged down over 3 rows, twice.
   - H `Stok`: integers, one negative, one empty cell.
   - I `Eklenme`: a date `28.10.2026`.
   - J `Güncelleme`: date and time `28.10.2026 13:45`.
   - K `Aktif`: `TRUE` and `FALSE`.
   - L `Not`: one `#N/A` from `=NA()`.
   - One hidden row. A second sheet `Gizli`, hidden, with one cell.
2. `excel_customers.xlsx` and `gsheets_customers.xlsx`. Sheet
   `Müşteriler`, about 20 rows, row 1 the header with `A1:B1` merged:
   - A `No`: an integer.
   - B `Unvan`: text with `&`, `<` and quotes.
   - C `Vergi No`: 10 digits with a leading zero, as text.
   - D `Telefon`: `+90 532 ...` text.
   - E `E-posta`; F `Şehir`.
   - G `Bakiye`: negative and positive amounts, currency format.
   - H `Müşteri olduğu tarih`: dates in `dd.mm.yyyy`.
   - I `Son arama`: a time only, `h:mm`.
   - J `Süre`: an elapsed time `[h]:mm` over 24 hours.
   - K `Açıklama`: one text over 300 characters; rows 8 and 9 empty.
3. Optional, `erp_export.xlsx`: any real export from a supplier or
   accounting system, anonymized, handled the same way.

## Draft, confirm, add

1. Put the file here and run

   ```bash
   dart run tool/draft_expected.dart test/fixtures/owner/excel_products.xlsx
   ```

   It writes `excel_products.expected.json` beside the file (it refuses to
   overwrite one) and prints a review table, `Sheet!Cell  type  value
   format  formula`, plus merges, hidden rows (numbered as the program
   numbers them, from 1) and warnings.
2. Open the file in the program that made it and tick **every** line of the
   table against what the program shows: the text, the number, the date
   and time, the format the program displays, the formula. The draft is
   the reader's own answer; a draft confirmed without looking encodes the
   reader's mistakes. Edit the JSON wherever the program disagrees (that
   disagreement is a reader defect: report it, do not hide it).
3. Set `"producer"` to program, version and platform (such as
   `Microsoft Excel for Mac 16.90`) and `"confirmedBy"` to `"owner"`. The
   test refuses a `confirmedBy` that is not exactly `"owner"`, an empty
   `producer`, and a `file` that is not the `.xlsx` name.
4. Add the `.xlsx` name to `manifest.json`, run the quality gate, commit.

## The `.expected.json` format

```json
{
  "file": "excel_products.xlsx",
  "producer": "Microsoft Excel for Mac 16.90",
  "confirmedBy": "owner",
  "date1904": false,
  "sheets": [
    {
      "name": "Ürünler",
      "visibility": "visible",
      "merges": ["G2:G4"],
      "hiddenRows": [9],
      "rows": [
        ["Kod", "Ürün adı", "Fiyat", "KDV", "Tarih", "Aktif"],
        ["00123", "Çay 500 g", {"n": "149.90", "format": "#,##0.00 ₺"},
         {"n": "0.2"}, {"date": "2026-10-28"}, true],
        ["00124", null, {"n": "12", "formula": "B3*2"},
         {"error": "#N/A"}, {"date": "2026-10-28T13:45:00"},
         {"duration": "13:30:00"}]
      ]
    }
  ],
  "warnings": []
}
```

- `rows[0]` is sheet row 1; `null` or a missing trailing cell is no cell.
  The file must have no cell where the JSON has none (a styled empty cell
  with no value and no formula counts as none).
- A JSON string is text; `true` and `false` are booleans.
- Any other cell is an object holding one of: `"s"` (text), `"n"` (decimal
  digits as a string, compared by value with a relative tolerance of
  1e-12), `"b"` (boolean), `"date"` (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS`,
  within one second, because Excel rounds what it shows), `"duration"`
  (`[-]H:MM:SS`, within one second) or `"error"`
  (the code, such as `#N/A`); or none of them, for a formula whose result
  the file does not store. `{"n": 1}` is an error: digits are a string.
- Optional on an object cell: `"formula"` (exact text, no `=`) and
  `"format"` (the exact number format code). A formula in the file must
  appear here; a missing `"format"` is not checked.
- `merges` (A1 ranges), `hiddenRows` (0-based) and `visibility`
  (`visible`, `hidden`, `veryHidden`) default to none, none and `visible`.
  `date1904` defaults to false.
- `warnings` is a list of `{"code": name, "count": n}`, the code being an
  `XlsxWarningCode` name and the count the sum over all cells. The default,
  `[]`, means the file reads with no warning at all.
- Any other key is an error that names its path, such as
  `sheets[0].rows[3][2].n`.
