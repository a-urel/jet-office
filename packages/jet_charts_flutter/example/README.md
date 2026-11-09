# jet_charts_gallery

The gallery for the owner's side-by-side check of `jet_charts_flutter` against
Excel for Mac (owner decision O5 of milestone J3). It is an app,
not published, and nothing depends on it.

- `lib/gallery.dart` holds the 16 charts: the 14 of
  `packages/jet_charts_core/test/support/gallery.dart` (same names and data),
  `one_series` and `turkish_amounts`, each at 360 by 216 points, Excel's
  default chart size.
- `lib/main.dart` is the macOS app: every chart drawn by `JetChart` in the
  Office theme in a 360 by 216 frame, with the overlaps `findOverlaps` finds
  (always 0) and the labels the layout hid, a line that says whether the font
  Aptos Narrow was found, and a switch for Turkish texts and `tr-TR` numbers.
- `tool/write_excel_gallery.dart <dir>` writes `<dir>/gallery.xlsx`, the same
  charts as Excel's own default charts (`lib/src/excel_gallery.dart`).

From the repository root:

```bash
dart run packages/jet_charts_flutter/example/tool/write_excel_gallery.dart build/excel_gallery
dotnet run --project tool/ooxml_validate -- build/excel_gallery
(cd packages/jet_charts_flutter/example && flutter test && flutter run -d macos)
```

The owner's steps, in Turkish, are in `TALIMATLAR.md`; the result goes in
`packages/jet_charts_core/docs/excel-checks.md`, from the owner only.
