/// The key under which Office compares two names ignoring case.
///
/// Not ported from Quds; written for jet_office. It was `sheetNameKey`
/// (`lib/src/xlsx/sheet_name.dart`), which now calls it, so a custom document
/// property of either format is compared the way Excel compares sheet names.
library;

/// The key under which Office considers two names equal ignoring case.
///
/// Excel compares sheet names case-insensitively. Dart's `toUpperCase()`
/// differs between platforms for a few letters: it keeps `ß`, and it leaves
/// the Turkish `İ` and `ı` apart from `I`. The key maps those letters first,
/// so `liste`/`LİSTE` and `straße`/`STRASSE` clash on every platform. The
/// folding is deliberately generous: an extra rename never makes Excel refuse
/// a file, a missed one does.
///
/// The Kelvin sign (U+212A) is mapped to `K` too. It is already an
/// upper-case letter, so `toUpperCase()` keeps it apart from `K`, but Excel
/// refuses a Kelvin-sign sheet name when a sheet `K` exists (checked by hand
/// in Excel for the web, see `docs/excel-checks.md`). The long s (U+017F)
/// needs no mapping: `toUpperCase()` gives `S`, so it clashes with `s` and
/// `S` already.
String officeNameKey(String name) => name
    .replaceAll('İ', 'I')
    .replaceAll('ı', 'I')
    .replaceAll('ß', 'SS')
    .replaceAll('ẞ', 'SS')
    .replaceAll('\u212A', 'K')
    .toUpperCase();
