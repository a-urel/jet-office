/// The [Fixture] type shared by every milestone's fixture list.
///
/// New in jet_office. A fixture is a deterministic workbook plus what its
/// file stores and what a reader should show; `test/fixtures/fixtures_test.dart`
/// checks every fixture of `allFixtures()`, and `tool/write_fixtures.dart`
/// writes them for the CI validation job. See `m1_fixtures.dart` for the
/// conventions the value maps follow.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

/// A named workbook builder with the values its file stores.
final class Fixture {
  /// Creates a fixture. [run] builds the workbook.
  Fixture(
    this.name,
    this.storedValues,
    this.expectedValues,
    XlsxResult Function() run, {
    this.expectedWarnings = const <XlsxWarningCode, int>{},
  }) : _run = run;

  final XlsxResult Function() _run;

  /// The fixture's name, also its file name stem.
  final String name;

  /// Sheet name (the final, sanitized one) to rows of the text stored in the
  /// file: numbers as in `<v>`, dates as serials, booleans `1`/`0`, strings
  /// after scrubbing and truncation and with `_xHHHH_` look-alikes escaped,
  /// empty cells `''`. Rectangular per sheet. The tests check it against the
  /// file itself.
  final Map<String, List<List<String>>> storedValues;

  /// Sheet name to rows of the values a reader should see, typed: `String`
  /// for text, `num` for numbers and date serials, `bool` for booleans and
  /// `null` for empty cells. A formula cell holds the value Excel or
  /// LibreOffice computes.
  ///
  /// The comparison contract Task 15 implements against LibreOffice's CSV
  /// export: raw (not formatted) values; numbers are equal within a relative
  /// tolerance of 1e-12; a `bool` matches `TRUE`/`FALSE` or `1`/`0`; strings
  /// are equal exactly (a stored string is compared after decoding its
  /// `_xHHHH_` escapes, as a reader does); `null` matches `""`; trailing
  /// empty rows and trailing empty cells are ignored on both sides. A CSV
  /// cannot tell an empty sheet from a sheet whose only cell is `''`, so
  /// both expect no rows; the checker and [storedValues] still tell them
  /// apart.
  final Map<String, List<List<Object?>>> expectedValues;

  /// The warnings [build] must produce, as the total count per code.
  final Map<XlsxWarningCode, int> expectedWarnings;

  /// Builds the workbook and returns its bytes. The same bytes every time.
  Uint8List build() => _run().bytes;

  /// The warnings [build] produces.
  List<XlsxWarning> warnings() => _run().warnings;
}
