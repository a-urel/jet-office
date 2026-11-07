/// The parts of a new document, written by jet_office with the values of
/// Word for Mac's blank document.
///
/// Not ported from Quds; written for jet_office. A new document looks like
/// Word's current blank document (decision 0010), and its parts are this
/// library's own (decision 0011): the values of the styles, the theme's
/// colours and fonts, the font table and the compatibility settings are
/// those of a blank document saved by Word for Mac 16.114.1 (build
/// 16.114.26102031), kept in `test/fixtures/owner/docx/blank.docx`, which
/// `test/docx/blank_document_oracle_test.dart` compares them with.
///
/// Not carried over from that file: the revision identifiers, the document
/// ids, `w:proofState`, `w:attachedTemplate`, `docProps/` and the regional
/// settings of the machine that saved it. `w:themeFontLang` and every
/// `w:lang` are `en-US` (with `w:eastAsia` `en-US` and `w:bidi` `ar-SA`),
/// and `w:decimalSymbol` and `w:listSeparator` are left out so that Word
/// uses the reader's system values. Style ids and names are Word's en-US
/// ones. `w:compatSetting compatibilityMode` 15 is set, so Word does not
/// open the file in compatibility mode.
///
/// The theme is written here and differs from Word's on purpose: it has no
/// per-script font list, so Word picks those fonts itself, and its format
/// scheme is plain, which only a drawing that uses the theme's effects
/// would show. The latent styles name the styles Word's gallery offers and
/// hide the rest until they are used.
///
/// The section is A4 portrait (`w:pgSz` 11906 by 16838 twips) with the
/// margins, header and footer distances and document grid of that file
/// (spec 4.5). `blank.docx` is A4, so the Letter fallback did not apply.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../opc/ooxml.dart' show ContentType, Ns, RelType;
import '../zip/archive_adapter.dart';
import 'default_styles.dart';

/// The bytes of a new document: a DOCX package of the parts below, with
/// one empty paragraph.
///
/// The package has no `docProps/` part (both are optional in OPC).
Uint8List blankDocumentBytes() {
  final ZipWriter zip = ZipWriter();
  void add(String name, String xml) =>
      zip.add(name, Uint8List.fromList(utf8.encode(xml)));
  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _rootRels);
  add('word/document.xml', blankDocument);
  add('word/_rels/document.xml.rels', _documentRels);
  add('word/styles.xml', blankStyles);
  add('word/settings.xml', blankSettings);
  add('word/webSettings.xml', blankWebSettings);
  add('word/fontTable.xml', blankFontTable);
  add('word/theme/theme1.xml', blankTheme);
  return zip.close()!;
}

const String _declaration =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

const String _contentTypes =
    '$_declaration'
    '<Types xmlns="${Ns.contentTypes}">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="${ContentType.xml}"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '<Override PartName="/word/styles.xml" '
    'ContentType="${ContentType.wmlStyles}"/>'
    '<Override PartName="/word/settings.xml" '
    'ContentType="${ContentType.wmlSettings}"/>'
    '<Override PartName="/word/webSettings.xml" '
    'ContentType="${ContentType.wmlWebSettings}"/>'
    '<Override PartName="/word/fontTable.xml" '
    'ContentType="${ContentType.wmlFontTable}"/>'
    '<Override PartName="/word/theme/theme1.xml" '
    'ContentType="${ContentType.theme}"/>'
    '</Types>';

const String _rootRels =
    '$_declaration'
    '<Relationships xmlns="${Ns.packageRel}">'
    '<Relationship Id="rId1" Type="${RelType.officeDocument}" '
    'Target="word/document.xml"/>'
    '</Relationships>';

const String _documentRels =
    '$_declaration'
    '<Relationships xmlns="${Ns.packageRel}">'
    '<Relationship Id="rId1" Type="${RelType.styles}" Target="styles.xml"/>'
    '<Relationship Id="rId2" Type="${RelType.settings}" '
    'Target="settings.xml"/>'
    '<Relationship Id="rId3" Type="${RelType.webSettings}" '
    'Target="webSettings.xml"/>'
    '<Relationship Id="rId4" Type="${RelType.fontTable}" '
    'Target="fontTable.xml"/>'
    '<Relationship Id="rId5" Type="${RelType.theme}" '
    'Target="theme/theme1.xml"/>'
    '</Relationships>';

/// The `w` namespace with `w14`, which `w:docDefaults` uses for ligatures.
const String _stylesRoot =
    '<w:styles xmlns:mc="${Ns.mc}" xmlns:w="${Ns.w}" '
    'xmlns:w14="${Ns.w14}" '
    'mc:Ignorable="w14">';

const String _docDefaults =
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:asciiTheme="minorHAnsi" w:eastAsiaTheme="minorHAnsi" '
    'w:hAnsiTheme="minorHAnsi" w:cstheme="minorBidi"/><w:kern w:val="2"/>'
    '<w:sz w:val="24"/><w:szCs w:val="24"/>'
    '<w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/>'
    '<w14:ligatures w14:val="standardContextual"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr>'
    '<w:spacing w:after="160" w:line="278" w:lineRule="auto"/></w:pPr>'
    '</w:pPrDefault></w:docDefaults>';

/// The styles Word offers without being asked, by name and priority. A
/// latent style not named here stays hidden until it is used.
const Map<String, int> _galleryStyles = <String, int>{
  'Normal': 0,
  'heading 1': 9,
  'Title': 10,
  'Subtitle': 11,
  'Subtle Emphasis': 19,
  'Emphasis': 20,
  'Intense Emphasis': 21,
  'Strong': 22,
  'Quote': 29,
  'Intense Quote': 30,
  'Subtle Reference': 31,
  'Intense Reference': 32,
  'Book Title': 33,
  'List Paragraph': 34,
  'No Spacing': 1,
};

/// The styles that join the gallery once they are used, by name and
/// priority.
const Map<String, int> _galleryOnceUsed = <String, int>{
  'heading 2': 9,
  'heading 3': 9,
  'heading 4': 9,
  'heading 5': 9,
  'heading 6': 9,
  'heading 7': 9,
  'heading 8': 9,
  'heading 9': 9,
  'caption': 35,
  'TOC Heading': 39,
};

String _latentStyles() {
  final StringBuffer xml = StringBuffer(
    '<w:latentStyles w:defLockedState="0" w:defUIPriority="99" '
    'w:defSemiHidden="1" w:defUnhideWhenUsed="1" w:defQFormat="0" '
    'w:count="376">',
  );
  _galleryStyles.forEach((String name, int priority) {
    xml.write(
      '<w:lsdException w:name="$name" w:semiHidden="0" '
      'w:uiPriority="$priority" w:unhideWhenUsed="0" w:qFormat="1"/>',
    );
  });
  _galleryOnceUsed.forEach((String name, int priority) {
    xml.write(
      '<w:lsdException w:name="$name" w:uiPriority="$priority" '
      'w:qFormat="1"/>',
    );
  });
  xml.write('</w:latentStyles>');
  return xml.toString();
}

/// `word/styles.xml`: the document defaults, the latent styles and the
/// styles of a new document.
final String blankStyles =
    '$_declaration$_stylesRoot$_docDefaults${_latentStyles()}'
    '${blankStyleDefinitions.values.join()}</w:styles>';

/// A `w:compatSetting` of Word's own namespace.
String _compat(String name, int value) =>
    '<w:compatSetting w:name="$name" '
    'w:uri="http://schemas.microsoft.com/office/word" w:val="$value"/>';

/// `word/settings.xml`.
final String blankSettings =
    '$_declaration<w:settings xmlns:w="${Ns.w}">'
    '<w:zoom w:percent="100"/><w:defaultTabStop w:val="708"/>'
    '<w:hyphenationZone w:val="425"/>'
    '<w:characterSpacingControl w:val="doNotCompress"/><w:compat>'
    '${_compat('compatibilityMode', 15)}'
    '${_compat('overrideTableStyleFontSizeAndJustification', 1)}'
    '${_compat('enableOpenTypeFeatures', 1)}'
    '${_compat('doNotFlipMirrorIndents', 1)}'
    '${_compat('differentiateMultirowTableHeaders', 1)}'
    '${_compat('useWord2013TrackBottomHyphenation', 0)}'
    '</w:compat><w:themeFontLang w:val="en-US"/>'
    '<w:clrSchemeMapping w:bg1="light1" w:t1="dark1" w:bg2="light2" '
    'w:t2="dark2" w:accent1="accent1" w:accent2="accent2" '
    'w:accent3="accent3" w:accent4="accent4" w:accent5="accent5" '
    'w:accent6="accent6" w:hyperlink="hyperlink" '
    'w:followedHyperlink="followedHyperlink"/></w:settings>';

/// A `w:font` entry: the metrics Word uses to substitute a missing font.
String _font(
  String name, {
  required String panose,
  required String family,
  required List<String> signature,
}) =>
    '<w:font w:name="$name"><w:panose1 w:val="$panose"/>'
    '<w:charset w:val="00"/><w:family w:val="$family"/>'
    '<w:pitch w:val="variable"/><w:sig w:usb0="${signature[0]}" '
    'w:usb1="${signature[1]}" w:usb2="00000000" w:usb3="00000000" '
    'w:csb0="${signature[2]}" w:csb1="00000000"/></w:font>';

const List<String> _aptosSignature = <String>[
  '20000287',
  '00000003',
  '0000019F',
];

/// `word/fontTable.xml`.
final String blankFontTable =
    '$_declaration<w:fonts xmlns:w="${Ns.w}">'
    '${_font('Aptos', panose: '020B0004020202020204', family: 'swiss', signature: _aptosSignature)}'
    '${_font('Times New Roman', panose: '02020603050405020304', family: 'roman', signature: const <String>['00000003', '00000000', '00000001'])}'
    '${_font('Aptos Display', panose: '020B0004020202020204', family: 'swiss', signature: _aptosSignature)}'
    '</w:fonts>';

/// `word/webSettings.xml`.
const String blankWebSettings =
    '$_declaration<w:webSettings xmlns:w="${Ns.w}">'
    '<w:optimizeForBrowser/><w:allowPNG/></w:webSettings>';

/// A theme colour slot holding the colour [rgb].
String _rgb(String slot, String rgb) =>
    '<a:$slot><a:srgbClr val="$rgb"/></a:$slot>';

/// A theme colour slot that follows the system colour [name].
String _system(String slot, String name, String last) =>
    '<a:$slot><a:sysClr val="$name" lastClr="$last"/></a:$slot>';

const String _themeFill =
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>';

/// A theme line of [width] EMU.
String _themeLine(int width) => '<a:ln w="$width">$_themeFill</a:ln>';

const String _themeEffect = '<a:effectStyle><a:effectLst/></a:effectStyle>';

/// A font scheme entry with the Latin font [typeface].
String _themeFont(String element, String typeface) =>
    '<a:$element><a:latin typeface="$typeface"/><a:ea typeface=""/>'
    '<a:cs typeface=""/></a:$element>';

/// `word/theme/theme1.xml`: Word's current colours, Aptos for body and
/// headings, and a plain format scheme (the schema asks for three of each).
final String blankTheme =
    '$_declaration<a:theme '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'name="jet_office"><a:themeElements><a:clrScheme name="jet_office">'
    '${_system('dk1', 'windowText', '000000')}'
    '${_system('lt1', 'window', 'FFFFFF')}'
    '${_rgb('dk2', '0E2841')}${_rgb('lt2', 'E8E8E8')}'
    '${_rgb('accent1', '156082')}${_rgb('accent2', 'E97132')}'
    '${_rgb('accent3', '196B24')}${_rgb('accent4', '0F9ED5')}'
    '${_rgb('accent5', 'A02B93')}${_rgb('accent6', '4EA72E')}'
    '${_rgb('hlink', '467886')}${_rgb('folHlink', '96607D')}'
    '</a:clrScheme><a:fontScheme name="jet_office">'
    '${_themeFont('majorFont', 'Aptos Display')}'
    '${_themeFont('minorFont', 'Aptos')}'
    '</a:fontScheme><a:fmtScheme name="jet_office"><a:fillStyleLst>'
    '$_themeFill$_themeFill$_themeFill</a:fillStyleLst><a:lnStyleLst>'
    '${_themeLine(6350)}${_themeLine(12700)}${_themeLine(19050)}'
    '</a:lnStyleLst><a:effectStyleLst>'
    '$_themeEffect$_themeEffect$_themeEffect</a:effectStyleLst>'
    '<a:bgFillStyleLst>$_themeFill$_themeFill$_themeFill</a:bgFillStyleLst>'
    '</a:fmtScheme></a:themeElements></a:theme>';

/// `word/document.xml`: one empty paragraph and the A4 portrait section
/// of Word's blank document.
const String blankDocument =
    r'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    r'<w:document '
    r'xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingC'
    r'anvas" '
    r'xmlns:cx="http://schemas.microsoft.com/office/drawing/2014/chartex" '
    r'xmlns:cx1="http://schemas.microsoft.com/office/drawing/2015/9/8/chartex"'
    r' xmlns:cx2="http://schemas.microsoft.com/office/drawing/2015/10/21/chart'
    r'ex" '
    r'xmlns:cx3="http://schemas.microsoft.com/office/drawing/2016/5/9/chartex"'
    r' xmlns:cx4="http://schemas.microsoft.com/office/drawing/2016/5/10/charte'
    r'x" '
    r'xmlns:cx5="http://schemas.microsoft.com/office/drawing/2016/5/11/chartex'
    r'" '
    r'xmlns:cx6="http://schemas.microsoft.com/office/drawing/2016/5/12/chartex'
    r'" '
    r'xmlns:cx7="http://schemas.microsoft.com/office/drawing/2016/5/13/chartex'
    r'" '
    r'xmlns:cx8="http://schemas.microsoft.com/office/drawing/2016/5/14/chartex'
    r'" '
    r'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
    r'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" '
    r'xmlns:aink="http://schemas.microsoft.com/office/drawing/2016/ink" '
    r'xmlns:am3d="http://schemas.microsoft.com/office/drawing/2017/model3d" '
    r'xmlns:oel="http://schemas.microsoft.com/office/2019/extlst" '
    r'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relations'
    r'hips" '
    r'xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessing'
    r'Drawing" '
    r'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessin'
    r'gDrawing" '
    r'xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingG'
    r'roup" '
    r'xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingI'
    r'nk" '
    r'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingS'
    r'hape" xmlns:o="urn:schemas-microsoft-com:office:office" '
    r'xmlns:v="urn:schemas-microsoft-com:vml" '
    r'xmlns:w10="urn:schemas-microsoft-com:office:word" '
    r'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:w14="${Ns.w14}" '
    r'xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" '
    r'xmlns:w16cex="http://schemas.microsoft.com/office/word/2018/wordml/cex" '
    r'xmlns:w16cid="http://schemas.microsoft.com/office/word/2016/wordml/cid" '
    r'xmlns:w16="http://schemas.microsoft.com/office/word/2018/wordml" '
    r'xmlns:w16sdtdh="http://schemas.microsoft.com/office/word/2020/wordml/sdt'
    r'datahash" '
    r'xmlns:w16sdtfl="http://schemas.microsoft.com/office/word/2024/wordml/sdt'
    r'formatlock" '
    r'xmlns:w16se="http://schemas.microsoft.com/office/word/2015/wordml/symex"'
    r' xmlns:w16du="http://schemas.microsoft.com/office/word/2023/wordml/word1'
    r'6du" xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml" '
    r'mc:Ignorable="w14 w15 w16se w16cid w16 w16cex w16sdtdh w16sdtfl w16du '
    r'wp14">'
    r'<w:body><w:p/><w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
    r'<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
    r'w:header="708" w:footer="708" w:gutter="0"/>'
    r'<w:cols w:space="708"/><w:docGrid w:linePitch="360"/></w:sectPr>'
    r'</w:body></w:document>';
