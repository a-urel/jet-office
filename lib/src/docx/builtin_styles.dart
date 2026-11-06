/// Word's built-in styles: the catalog a document draws on when a style is
/// added on demand.
///
/// Not ported from Quds; written for jet_office. The definitions are in
/// `default_styles.dart`, so the blank document and the catalog cannot
/// disagree. The `w:name` of a built-in style is English in every locale.
library;

import '../opc/ooxml.dart' show Ns;
import 'default_styles.dart';
import 'model/styles.dart' show DocxStyleType;

/// A style that Word itself defines, by its id and name in a document
/// saved under the English (en-US) locale.
///
/// A document that lacks one of them can be given Word's own definition of
/// it, with the styles it is based on, that follow it and that it is linked
/// to. Other locales give the same style another id (Turkish `Balk1` for
/// `Heading1`); a document keeps its own ids, and this catalog names only
/// the English ones.
enum DocxBuiltInStyle {
  /// The default paragraph style.
  normal('Normal', 'Normal', DocxStyleType.paragraph),

  /// The default character style, the base of the other character styles.
  defaultParagraphFont(
    'DefaultParagraphFont',
    'Default Paragraph Font',
    DocxStyleType.character,
  ),

  /// The default table style.
  tableNormal('TableNormal', 'Normal Table', DocxStyleType.table),

  /// The default numbering style.
  noList('NoList', 'No List', DocxStyleType.numbering),

  /// Heading level 1.
  heading1('Heading1', 'heading 1', DocxStyleType.paragraph),

  /// Heading level 2.
  heading2('Heading2', 'heading 2', DocxStyleType.paragraph),

  /// Heading level 3.
  heading3('Heading3', 'heading 3', DocxStyleType.paragraph),

  /// Heading level 4.
  heading4('Heading4', 'heading 4', DocxStyleType.paragraph),

  /// Heading level 5.
  heading5('Heading5', 'heading 5', DocxStyleType.paragraph),

  /// Heading level 6.
  heading6('Heading6', 'heading 6', DocxStyleType.paragraph),

  /// Heading level 7.
  heading7('Heading7', 'heading 7', DocxStyleType.paragraph),

  /// Heading level 8.
  heading8('Heading8', 'heading 8', DocxStyleType.paragraph),

  /// Heading level 9.
  heading9('Heading9', 'heading 9', DocxStyleType.paragraph),

  /// The title of a document.
  title('Title', 'Title', DocxStyleType.paragraph),

  /// The subtitle of a document.
  subtitle('Subtitle', 'Subtitle', DocxStyleType.paragraph),

  /// A quotation.
  quote('Quote', 'Quote', DocxStyleType.paragraph),

  /// An emphasised quotation, set off by borders.
  intenseQuote('IntenseQuote', 'Intense Quote', DocxStyleType.paragraph),

  /// A paragraph of a list.
  listParagraph('ListParagraph', 'List Paragraph', DocxStyleType.paragraph),

  /// Emphasis stronger than [emphasis], as a character style.
  intenseEmphasis(
    'IntenseEmphasis',
    'Intense Emphasis',
    DocxStyleType.character,
  ),

  /// A reference set in small capitals and bold, as a character style.
  intenseReference(
    'IntenseReference',
    'Intense Reference',
    DocxStyleType.character,
  ),

  /// Bold text, as a character style.
  strong('Strong', 'Strong', DocxStyleType.character),

  /// Italic text, as a character style.
  emphasis('Emphasis', 'Emphasis', DocxStyleType.character),

  /// A paragraph without space after it and with single line spacing.
  noSpacing('NoSpacing', 'No Spacing', DocxStyleType.paragraph),

  /// A table with single borders on every cell.
  tableGrid('TableGrid', 'Table Grid', DocxStyleType.table),

  /// The paragraph style of a page header.
  header('Header', 'header', DocxStyleType.paragraph),

  /// The paragraph style of a page footer.
  footer('Footer', 'footer', DocxStyleType.paragraph),

  /// The character style of a link.
  hyperlink('Hyperlink', 'Hyperlink', DocxStyleType.character);

  const DocxBuiltInStyle(this.id, this.name, this.type);

  /// The `w:styleId` Word gives the style under the English locale.
  final String id;

  /// The `w:name` of the style, which is English in every locale.
  final String name;

  /// What the style applies to.
  final DocxStyleType type;
}

/// The built-in style whose English id is [id], compared exactly, or `null`.
DocxBuiltInStyle? builtInStyleOfId(String id) => _byEnglishId[id];

final Map<String, DocxBuiltInStyle> _byEnglishId = <String, DocxBuiltInStyle>{
  for (final DocxBuiltInStyle style in DocxBuiltInStyle.values) style.id: style,
};

/// Word's definition of the built-in or linked style [englishId], as a
/// `w:style` element that declares the `w` namespace itself.
///
/// [englishId] is the `w:styleId` of a [DocxBuiltInStyle] or of a style
/// linked to one: `Heading1Char` to `Heading9Char`, `TitleChar`,
/// `SubtitleChar`, `QuoteChar`, `IntenseQuoteChar`, `HeaderChar` and
/// `FooterChar`. The definition refers to other styles by their English ids,
/// all of which are in the catalog too. `Header` and `Footer` carry Word's
/// tab stops for a page of A4 with the margins of a new document (a centre
/// tab at 4536 and a right tab at 9072 twips); on another page they are
/// not at the centre and the edge.
///
/// Throws an [ArgumentError] when the catalog has no style of that id.
String builtInStyleXml(String englishId) {
  final String? xml = _catalog[englishId];
  if (xml == null) {
    throw ArgumentError.value(
      englishId,
      'englishId',
      'Not the id of a built-in style.',
    );
  }
  return xml;
}

/// The ids of the styles [builtInStyleXml] holds a definition of.
Iterable<String> get builtInStyleIds => _catalog.keys;

/// [element] with the `w` namespace declared on it.
String _declared(String element) =>
    element.replaceFirst('<w:style ', '<w:style xmlns:w="${Ns.w}" ');

/// Every definition by id.
final Map<String, String> _catalog = <String, String>{
  for (final MapEntry<String, String> style in <MapEntry<String, String>>[
    ...blankStyleDefinitions.entries,
    ...catalogStyleDefinitions.entries,
  ])
    style.key: _declared(style.value),
};
