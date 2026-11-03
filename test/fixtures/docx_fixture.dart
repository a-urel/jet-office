/// The [DocxFixture] type of the DOCX milestones' fixture lists.
///
/// New in jet_office. A fixture is a deterministic document plus the text a
/// reader should find in it; `test/docx/round_trip_test.dart` checks every
/// fixture of `docxFixtures()`, and `tool/write_fixtures.dart` writes them
/// for the CI validation job, beside the XLSX ones of [Fixture].
///
/// @docImport 'fixture.dart';
library;

import 'package:jet_office/jet_office.dart';

/// A named document builder with the text it holds.
final class DocxFixture {
  /// Creates a fixture. [build] builds the document.
  const DocxFixture(
    this.name,
    this.expectedText,
    this.build, {
    this.expectedWarnings = const <DocxWarningCode, int>{},
  });

  /// The fixture's name, also its file name stem.
  final String name;

  /// The document's text: the text of each paragraph of the body
  /// ([DocxParagraph.text]: a tab as `\t`, a line break as `\n`), joined by
  /// `\n`, as LibreOffice's text export writes them.
  ///
  /// The comparison contract of `tool/compare_text.dart` and
  /// `tool/compare_resaved_docx.dart`: LibreOffice ends every paragraph
  /// with `\n` and starts the file with a BOM, so one trailing newline and
  /// a leading BOM are ignored; everything else, edge and double spaces
  /// included, must be equal. A D1 fixture holds paragraphs only, so no
  /// table text has to be agreed on.
  final String expectedText;

  /// Builds the document and returns the saved file and its warnings. The
  /// same bytes every time.
  final DocxResult Function() build;

  /// The warnings [build] must produce, as the total count per code.
  final Map<DocxWarningCode, int> expectedWarnings;
}
