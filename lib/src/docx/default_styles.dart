/// The style definitions of a new document and of the built-in catalog.
///
/// Not ported from Quds; written for jet_office. Each definition is built
/// here from its values, so that a new document looks like Word's blank
/// one (decision 0011). The values are those of Word for Mac 16.114, read
/// from `test/fixtures/owner/docx/blank.docx` and `builtins.docx`;
/// `test/docx/blank_document_oracle_test.dart` and
/// `test/docx/builtin_styles_oracle_test.dart` compare them with those
/// files. Ids and linked names are Word's en-US ones in every locale.
library;

/// The heading colour: accent 1, darkened.
const String _accentDark =
    '<w:color w:val="0F4761" w:themeColor="accent1" w:themeShade="BF"/>';

/// Text 1, lightened by [tint]; [rgb] is the colour that gives.
String _textTint(String rgb, String tint) =>
    '<w:color w:val="$rgb" w:themeColor="text1" w:themeTint="$tint"/>';

const String _headingFonts =
    '<w:rFonts w:asciiTheme="majorHAnsi" w:eastAsiaTheme="majorEastAsia" '
    'w:hAnsiTheme="majorHAnsi" w:cstheme="majorBidi"/>';

const String _complexFonts =
    '<w:rFonts w:eastAsiaTheme="majorEastAsia" w:cstheme="majorBidi"/>';

const String _bold = '<w:b/><w:bCs/>';
const String _italic = '<w:i/><w:iCs/>';

/// The size [halfPoints], for Latin and complex scripts.
String _size(int halfPoints) =>
    '<w:sz w:val="$halfPoints"/><w:szCs w:val="$halfPoints"/>';

const String _singleSpaced =
    '<w:spacing w:after="0" w:line="240" w:lineRule="auto"/>';

/// A `w:style` element; its children follow the schema's order.
String _style(
  String type,
  String id,
  String name, {
  bool isDefault = false,
  bool custom = false,
  String? basedOn,
  String? next,
  String? link,
  int? priority,
  bool semiHidden = false,
  bool unhideWhenUsed = false,
  bool quick = false,
  String paragraph = '',
  String run = '',
  String table = '',
}) {
  final StringBuffer xml = StringBuffer('<w:style w:type="$type"');
  if (isDefault) xml.write(' w:default="1"');
  if (custom) xml.write(' w:customStyle="1"');
  xml.write(' w:styleId="$id"><w:name w:val="$name"/>');
  if (basedOn != null) xml.write('<w:basedOn w:val="$basedOn"/>');
  if (next != null) xml.write('<w:next w:val="$next"/>');
  if (link != null) xml.write('<w:link w:val="$link"/>');
  if (priority != null) xml.write('<w:uiPriority w:val="$priority"/>');
  if (semiHidden) xml.write('<w:semiHidden/>');
  if (unhideWhenUsed) xml.write('<w:unhideWhenUsed/>');
  if (quick) xml.write('<w:qFormat/>');
  if (paragraph.isNotEmpty) xml.write('<w:pPr>$paragraph</w:pPr>');
  if (run.isNotEmpty) xml.write('<w:rPr>$run</w:rPr>');
  if (table.isNotEmpty) xml.write('<w:tblPr>$table</w:tblPr>');
  xml.write('</w:style>');
  return xml.toString();
}

/// A paragraph style and the character style linked to it, as id and
/// element, both with the run properties [run].
Map<String, String> _linked(
  String id,
  String name,
  String charName, {
  required int priority,
  bool hidden = false,
  String paragraph = '',
  String run = '',
}) => <String, String>{
  id: _style(
    'paragraph',
    id,
    name,
    basedOn: 'Normal',
    next: 'Normal',
    link: '${id}Char',
    priority: priority,
    semiHidden: hidden,
    unhideWhenUsed: hidden,
    quick: true,
    paragraph: paragraph,
    run: run,
  ),
  '${id}Char': _style(
    'character',
    '${id}Char',
    charName,
    custom: true,
    basedOn: 'DefaultParagraphFont',
    link: id,
    priority: priority,
    semiHidden: hidden,
    run: run,
  ),
};

/// Heading [level]: keeps with what follows, and is hidden from the gallery
/// below level 1 until it is used.
Map<String, String> _heading(
  int level, {
  int? before,
  required int after,
  required String run,
}) => _linked(
  'Heading$level',
  'heading $level',
  'Heading $level Char',
  priority: 9,
  hidden: level > 1,
  paragraph:
      '<w:keepNext/><w:keepLines/><w:spacing'
      '${before == null ? '' : ' w:before="$before"'} w:after="$after"/>'
      '<w:outlineLvl w:val="${level - 1}"/>',
  run: run,
);

/// A style Word keeps out of the way until it is needed.
String _hiddenDefault(String type, String id, String name, int priority) =>
    _style(
      type,
      id,
      name,
      isDefault: true,
      priority: priority,
      semiHidden: true,
      unhideWhenUsed: true,
    );

/// A cell margin of [width] twips.
String _margin(String side, int width) =>
    '<w:$side w:w="$width" w:type="dxa"/>';

/// The styles of a new document, by id.
final Map<String, String> blankStyleDefinitions = <String, String>{
  'Normal': _style(
    'paragraph',
    'Normal',
    'Normal',
    isDefault: true,
    quick: true,
  ),
  'DefaultParagraphFont': _style(
    'character',
    'DefaultParagraphFont',
    'Default Paragraph Font',
    isDefault: true,
    priority: 1,
    semiHidden: true,
    unhideWhenUsed: true,
  ),
  'TableNormal': _style(
    'table',
    'TableNormal',
    'Normal Table',
    isDefault: true,
    priority: 99,
    semiHidden: true,
    unhideWhenUsed: true,
    table:
        '<w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar>'
        '${_margin('top', 0)}${_margin('left', 108)}'
        '${_margin('bottom', 0)}${_margin('right', 108)}</w:tblCellMar>',
  ),
  'NoList': _hiddenDefault('numbering', 'NoList', 'No List', 99),
  ..._heading(
    1,
    before: 360,
    after: 80,
    run: '$_headingFonts$_accentDark${_size(40)}',
  ),
  ..._heading(
    2,
    before: 160,
    after: 80,
    run: '$_headingFonts$_accentDark${_size(32)}',
  ),
  ..._heading(
    3,
    before: 160,
    after: 80,
    run: '$_complexFonts$_accentDark${_size(28)}',
  ),
  ..._heading(
    4,
    before: 80,
    after: 40,
    run: '$_complexFonts$_italic$_accentDark',
  ),
  ..._heading(5, before: 80, after: 40, run: '$_complexFonts$_accentDark'),
  ..._heading(
    6,
    before: 40,
    after: 0,
    run: '$_complexFonts$_italic${_textTint('595959', 'A6')}',
  ),
  ..._heading(
    7,
    before: 40,
    after: 0,
    run: '$_complexFonts${_textTint('595959', 'A6')}',
  ),
  ..._heading(
    8,
    after: 0,
    run: '$_complexFonts$_italic${_textTint('272727', 'D8')}',
  ),
  ..._heading(9, after: 0, run: '$_complexFonts${_textTint('272727', 'D8')}'),
  ..._linked(
    'Title',
    'Title',
    'Title Char',
    priority: 10,
    paragraph:
        '<w:spacing w:after="80" w:line="240" w:lineRule="auto"/>'
        '<w:contextualSpacing/>',
    run:
        '$_headingFonts<w:spacing w:val="-10"/><w:kern w:val="28"/>'
        '${_size(56)}',
  ),
  ..._linked(
    'Subtitle',
    'Subtitle',
    'Subtitle Char',
    priority: 11,
    paragraph: '<w:numPr><w:ilvl w:val="1"/></w:numPr>',
    run:
        '$_complexFonts${_textTint('595959', 'A6')}'
        '<w:spacing w:val="15"/>${_size(28)}',
  ),
  ..._linked(
    'Quote',
    'Quote',
    'Quote Char',
    priority: 29,
    paragraph: '<w:spacing w:before="160"/><w:jc w:val="center"/>',
    run: '$_italic${_textTint('404040', 'BF')}',
  ),
  ..._linked(
    'IntenseQuote',
    'Intense Quote',
    'Intense Quote Char',
    priority: 30,
    paragraph:
        '<w:pBdr>${_accentRule('top')}${_accentRule('bottom')}</w:pBdr>'
        '<w:spacing w:before="360" w:after="360"/>'
        '<w:ind w:left="864" w:right="864"/><w:jc w:val="center"/>',
    run: '$_italic$_accentDark',
  ),
  'ListParagraph': _style(
    'paragraph',
    'ListParagraph',
    'List Paragraph',
    basedOn: 'Normal',
    priority: 34,
    quick: true,
    paragraph: '<w:ind w:left="720"/><w:contextualSpacing/>',
  ),
  'IntenseEmphasis': _character(
    'IntenseEmphasis',
    'Intense Emphasis',
    21,
    '$_italic$_accentDark',
  ),
  'IntenseReference': _character(
    'IntenseReference',
    'Intense Reference',
    32,
    '$_bold<w:smallCaps/>$_accentDark<w:spacing w:val="5"/>',
  ),
};

/// The line above or below an intense quote.
String _accentRule(String side) =>
    '<w:$side w:val="single" w:sz="4" w:space="10" w:color="0F4761" '
    'w:themeColor="accent1" w:themeShade="BF"/>';

/// A character style in the gallery.
String _character(String id, String name, int priority, String run) => _style(
  'character',
  id,
  name,
  basedOn: 'DefaultParagraphFont',
  priority: priority,
  quick: true,
  run: run,
);

/// A page header or footer: `Header` and `Footer` set a centre and a right
/// tab for A4 with the margins of a new document.
Map<String, String> _pageStyle(String id, String name) => <String, String>{
  id: _style(
    'paragraph',
    id,
    name,
    basedOn: 'Normal',
    link: '${id}Char',
    priority: 99,
    unhideWhenUsed: true,
    paragraph:
        '<w:tabs><w:tab w:val="center" w:pos="4536"/>'
        '<w:tab w:val="right" w:pos="9072"/></w:tabs>$_singleSpaced',
  ),
  '${id}Char': _style(
    'character',
    '${id}Char',
    '$id Char',
    custom: true,
    basedOn: 'DefaultParagraphFont',
    link: id,
    priority: 99,
  ),
};

/// A single border of the table grid.
String _gridLine(String side) =>
    '<w:$side w:val="single" w:sz="4" w:space="0" w:color="auto"/>';

/// The styles of the catalog that a new document does not hold, by id.
final Map<String, String> catalogStyleDefinitions = <String, String>{
  'NoSpacing': _style(
    'paragraph',
    'NoSpacing',
    'No Spacing',
    priority: 1,
    quick: true,
    paragraph: _singleSpaced,
  ),
  'Strong': _character('Strong', 'Strong', 22, _bold),
  'Emphasis': _character('Emphasis', 'Emphasis', 20, _italic),
  'TableGrid': _style(
    'table',
    'TableGrid',
    'Table Grid',
    basedOn: 'TableNormal',
    priority: 39,
    paragraph: _singleSpaced,
    table:
        '<w:tblBorders>${_gridLine('top')}${_gridLine('left')}'
        '${_gridLine('bottom')}${_gridLine('right')}'
        '${_gridLine('insideH')}${_gridLine('insideV')}</w:tblBorders>',
  ),
  'Hyperlink': _style(
    'character',
    'Hyperlink',
    'Hyperlink',
    basedOn: 'DefaultParagraphFont',
    priority: 99,
    unhideWhenUsed: true,
    run:
        '<w:color w:val="467886" w:themeColor="hyperlink"/><w:u w:val="single"/>',
  ),
  ..._pageStyle('Header', 'header'),
  ..._pageStyle('Footer', 'footer'),
};
