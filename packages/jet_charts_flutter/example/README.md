# jet_charts_gallery

The gallery for the owner's side-by-side check of `jet_charts_flutter` against
Excel for Mac (owner decision O5 of milestone J3). It is an app,
not published, and nothing depends on it.

- `lib/gallery.dart` holds the 30 charts: the 14 J3 charts of
  `packages/jet_charts_core/test/support/gallery.dart` (same names and data),
  `one_series` and `turkish_amounts`, then that file's 14 J4 charts (a smooth
  line, translucent areas, pies, donuts, sparklines, scatter charts,
  combination charts and a secondary value axis; same names, data and
  themes). Each is 360 by 216 points, Excel's default chart size, but a
  sparkline, 120 by 40.
- `lib/main.dart` is the macOS app: every chart drawn by `JetChart` in the
  Office theme (`area_translucent` and `sparkline_area` with the area opacity
  of their core theme) at its size, with the overlaps `findOverlaps` finds
  (always 0) and the labels the layout hid, a line that says whether the font
  Aptos Narrow was found, and a switch for Turkish texts and `tr-TR` numbers.
  Its "Monépro look" page (`lib/monepro.dart`) draws `donut_center`,
  `sparkline_area`, `line_smooth` and `combo_column_line` in an app theme of
  `ChartTheme.fromColors`, light and dark, in the font family `DM Sans`, which
  the app does not bundle: the page says whether it was found. Excel has no
  such theme; the page is only looked at.
- `tool/write_excel_gallery.dart <dir>` writes `<dir>/gallery.xlsx`, the same
  charts as Excel's own default charts (`lib/src/excel_gallery.dart`), a
  sparkline as Excel's own sparkline in cell D2. The J4 kinds' XML is an
  estimate until the owner's E1 file (`chart_reference_j4.xlsx`) is read.

From the repository root:

```bash
dart run packages/jet_charts_flutter/example/tool/write_excel_gallery.dart build/excel_gallery
dotnet run --project tool/ooxml_validate -- build/excel_gallery
(cd packages/jet_charts_flutter/example && flutter test && flutter run -d macos)
```

The owner's steps, in Turkish, are in `TALIMATLAR.md`; the result goes in
`packages/jet_charts_core/docs/excel-checks.md`, from the owner only.
