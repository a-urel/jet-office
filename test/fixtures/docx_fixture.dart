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
    String? libreOfficeText,
    this.libreOfficeTextSkip,
    this.headerFooterText,
    this.expectedWarnings = const <DocxWarningCode, int>{},
  }) : libreOfficeText = libreOfficeText ?? expectedText;

  /// The fixture's name, also its file name stem.
  final String name;

  /// The document's text, as `docxFullText` (`tool/src/text_compare.dart`)
  /// reads it from the saved file: the blocks of the body in order joined by
  /// `\n`, a paragraph as its text ([DocxParagraph.text]: a tab as `\t`, a
  /// line break as `\n`) and a table as a line for each row, its cells joined
  /// by `\t`, as LibreOffice's text export writes them. A cell of several
  /// paragraphs has a line for each, and a cell that continues a vertical
  /// merge is empty.
  ///
  /// The comparison contract of `tool/compare_text.dart` and
  /// `tool/compare_resaved_docx.dart`: LibreOffice ends every paragraph
  /// with `\n` and starts the file with a BOM, so one trailing newline and
  /// a leading BOM are ignored; everything else, edge and double spaces
  /// included, must be equal.
  final String expectedText;

  /// What LibreOffice's text export writes for the document: [expectedText]
  /// unless the document has lists, whose labels LibreOffice writes before
  /// the text of each item (`    • Bullet one`, `    1. Num one`: indented,
  /// with `•` for the Symbol bullet U+F0B7). Pinned from a LibreOffice run.
  ///
  /// `tool/compare_text.dart` compares the export with this; the model's own
  /// text has no labels, so `tool/compare_resaved_docx.dart` and the tests
  /// keep [expectedText].
  final String libreOfficeText;

  /// Why `tool/compare_text.dart` does not compare LibreOffice's text export
  /// of this document, or `null` to compare it. Set where LibreOffice's text
  /// is not a reading of the document that can be pinned (it differs by
  /// version); the fixture's re-save is still compared.
  final String? libreOfficeTextSkip;

  /// What the document's headers and footers show, as `docxStoriesText`
  /// (`tool/src/text_compare.dart`) reads it: a line for each paragraph of each
  /// story each section shows, or `null` for a fixture that has none.
  ///
  /// `tool/write_fixtures.dart` writes it to `<name>.stories.txt`, and
  /// `tool/compare_resaved_docx.dart` compares LibreOffice's re-save with it.
  final String? headerFooterText;

  /// Builds the document and returns the saved file and its warnings. The
  /// same bytes every time.
  final DocxResult Function() build;

  /// The warnings [build] must produce, as the total count per code.
  final Map<DocxWarningCode, int> expectedWarnings;
}
