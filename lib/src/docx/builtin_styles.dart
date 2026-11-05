/// Word's built-in styles: the catalog a document draws on when a style is
/// added on demand.
///
/// Not ported from Quds; written for jet_office. The definitions of the
/// styles that a new document holds are taken at run time from
/// [blankStyles], so the blank document and the catalog cannot disagree.
/// The others (`NoSpacing`, `Strong`, `Emphasis`, `TableGrid`, `Hyperlink`,
/// `Header`, `Footer` and the linked `HeaderChar` and `FooterChar`) are
/// constants transcribed from `test/fixtures/owner/docx/builtins.docx`,
/// saved by Microsoft Word for Mac 16.114 with the personal information
/// removed. Removed from them: the revision identifiers (`w:rsid`). The
/// file was saved on a Turkish system, so its style ids and the names of
/// its linked character styles were Turkish (`stBilgi`, `Üst Bilgi Char`);
/// they are written as Word's en-US ones (`Header`, `Header Char`), the
/// same way as in `blank_document.dart`. The `w:name` of a built-in style
/// is English in every locale, so those are the file's own.
///
/// Whether Word's style XML may ship in an Apache-2.0 package is an open
/// question for the owner (`NOTICE`).
library;

import '../opc/ooxml.dart' show Ns;
import 'blank_document.dart' show blankStyles;
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

/// The styles of the catalog that a new document holds, which are taken from
/// [blankStyles].
final RegExp _styleElement = RegExp(
  r'<w:style [^>]*w:styleId="([^"]+)">.*?</w:style>',
  dotAll: true,
);

/// [element] with the `w` namespace declared on it.
String _declared(String element) =>
    element.replaceFirst('<w:style ', '<w:style xmlns:w="${Ns.w}" ');

/// Every definition by id: those of [blankStyles] (parsed once, here) and
/// the constants below.
final Map<String, String> _catalog = () {
  final Map<String, String> catalog = <String, String>{};
  const Set<String> blankIds = <String>{
    'Normal',
    'DefaultParagraphFont',
    'TableNormal',
    'NoList',
    'Title',
    'TitleChar',
    'Subtitle',
    'SubtitleChar',
    'Quote',
    'QuoteChar',
    'IntenseQuote',
    'IntenseQuoteChar',
    'ListParagraph',
    'IntenseEmphasis',
    'IntenseReference',
    'Heading1',
    'Heading2',
    'Heading3',
    'Heading4',
    'Heading5',
    'Heading6',
    'Heading7',
    'Heading8',
    'Heading9',
    'Heading1Char',
    'Heading2Char',
    'Heading3Char',
    'Heading4Char',
    'Heading5Char',
    'Heading6Char',
    'Heading7Char',
    'Heading8Char',
    'Heading9Char',
  };
  for (final RegExpMatch m in _styleElement.allMatches(blankStyles)) {
    final String id = m.group(1)!;
    if (blankIds.contains(id)) catalog[id] = _declared(m.group(0)!);
  }
  for (final String element in <String>[
    _noSpacing,
    _strong,
    _emphasis,
    _tableGrid,
    _hyperlink,
    _header,
    _headerChar,
    _footer,
    _footerChar,
  ]) {
    final String id = _styleElement.firstMatch(element)!.group(1)!;
    catalog[id] = _declared(element);
  }
  return catalog;
}();

const String _noSpacing =
    r'<w:style w:type="paragraph" w:styleId="NoSpacing">'
    r'<w:name w:val="No Spacing"/><w:uiPriority w:val="1"/><w:qFormat/>'
    r'<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
    r'</w:pPr></w:style>';

const String _strong =
    r'<w:style w:type="character" w:styleId="Strong">'
    r'<w:name w:val="Strong"/><w:basedOn w:val="DefaultParagraphFont"/>'
    r'<w:uiPriority w:val="22"/><w:qFormat/><w:rPr><w:b/><w:bCs/>'
    r'</w:rPr></w:style>';

const String _emphasis =
    r'<w:style w:type="character" w:styleId="Emphasis">'
    r'<w:name w:val="Emphasis"/>'
    r'<w:basedOn w:val="DefaultParagraphFont"/>'
    r'<w:uiPriority w:val="20"/><w:qFormat/><w:rPr><w:i/><w:iCs/>'
    r'</w:rPr></w:style>';

const String _tableGrid =
    r'<w:style w:type="table" w:styleId="TableGrid">'
    r'<w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/>'
    r'<w:uiPriority w:val="39"/><w:pPr>'
    r'<w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
    r'<w:tblPr><w:tblBorders>'
    r'<w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    r'<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    r'<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    r'<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    r'<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    r'<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    r'</w:tblBorders></w:tblPr></w:style>';

const String _hyperlink =
    r'<w:style w:type="character" w:styleId="Hyperlink">'
    r'<w:name w:val="Hyperlink"/>'
    r'<w:basedOn w:val="DefaultParagraphFont"/>'
    r'<w:uiPriority w:val="99"/><w:unhideWhenUsed/><w:rPr>'
    r'<w:color w:val="467886" w:themeColor="hyperlink"/>'
    r'<w:u w:val="single"/></w:rPr></w:style>';

const String _header =
    r'<w:style w:type="paragraph" w:styleId="Header">'
    r'<w:name w:val="header"/><w:basedOn w:val="Normal"/>'
    r'<w:link w:val="HeaderChar"/><w:uiPriority w:val="99"/>'
    r'<w:unhideWhenUsed/><w:pPr><w:tabs>'
    r'<w:tab w:val="center" w:pos="4536"/>'
    r'<w:tab w:val="right" w:pos="9072"/></w:tabs>'
    r'<w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
    r'</w:style>';

const String _headerChar =
    r'<w:style w:type="character" w:customStyle="1" '
    r'w:styleId="HeaderChar">'
    r'<w:name w:val="Header Char"/>'
    r'<w:basedOn w:val="DefaultParagraphFont"/><w:link w:val="Header"/>'
    r'<w:uiPriority w:val="99"/></w:style>';

const String _footer =
    r'<w:style w:type="paragraph" w:styleId="Footer">'
    r'<w:name w:val="footer"/><w:basedOn w:val="Normal"/>'
    r'<w:link w:val="FooterChar"/><w:uiPriority w:val="99"/>'
    r'<w:unhideWhenUsed/><w:pPr><w:tabs>'
    r'<w:tab w:val="center" w:pos="4536"/>'
    r'<w:tab w:val="right" w:pos="9072"/></w:tabs>'
    r'<w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
    r'</w:style>';

const String _footerChar =
    r'<w:style w:type="character" w:customStyle="1" '
    r'w:styleId="FooterChar">'
    r'<w:name w:val="Footer Char"/>'
    r'<w:basedOn w:val="DefaultParagraphFont"/><w:link w:val="Footer"/>'
    r'<w:uiPriority w:val="99"/></w:style>';
