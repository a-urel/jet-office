/// Test helper: hand-made producer variants of the `d1_paragraphs` fixture
/// (spec 9, "Producer variants"), built in memory so they run in Chrome.
///
/// Each variant holds the paragraphs of `d1Paragraphs` in a package laid
/// out as some producer other than the model would write it: another
/// prefix for WordprocessingML, a default namespace, a missing content type
/// override, LibreOffice's and Google Docs' part layouts, and a
/// macro-enabled `.docm`. `test/docx/producer_variants_test.dart` opens
/// each, checks its blocks against `d1_paragraphs` and its save against
/// its input. The layouts follow files those producers write, reduced to
/// what tells them apart; the parts the model never parses (styles,
/// settings, fonts) are kept small.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';

import '../../fixtures/docx_fixtures.dart';
import 'docx_builder.dart';

/// One producer variant: its name, the DOCX file and the warning codes
/// opening it must report, in order.
final class ProducerVariant {
  /// Creates a variant.
  const ProducerVariant(
    this.name,
    this.bytes, {
    this.warnings = const <DocxWarningCode>[],
  });

  /// The variant's name.
  final String name;

  /// The DOCX file.
  final Uint8List bytes;

  /// The codes of the warnings opening the file reports, in order.
  final List<DocxWarningCode> warnings;
}

/// The relationship type of a VBA project (MS-OVBA, MS-DOCX).
const String _vbaRel =
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject';

/// The content type of a VBA project.
const String _vbaType = 'application/vnd.ms-office.vbaProject';

/// The variants, in a fixed order.
List<ProducerVariant> producerVariants() => <ProducerVariant>[
  ProducerVariant(
    'ns0_prefix',
    buildDocx(
      document:
          '<ns0:document xmlns:ns0="${Ns.w}"><ns0:body>'
          '${_paragraphs(element: 'ns0:', attribute: 'ns0:')}'
          '</ns0:body></ns0:document>',
    ),
  ),
  ProducerVariant(
    'default_namespace',
    buildDocx(
      // An unprefixed attribute is in no namespace, so w:val keeps a prefix.
      document:
          '<document xmlns="${Ns.w}" xmlns:w="${Ns.w}"><body>'
          '${_paragraphs(element: '', attribute: 'w:')}'
          '</body></document>',
    ),
  ),
  ProducerVariant(
    'no_override',
    buildDocx(document: _wDocument(_paragraphs()), contentType: null),
    warnings: const <DocxWarningCode>[DocxWarningCode.contentTypeMissing],
  ),
  ProducerVariant('libreoffice', buildZip(_libreOffice())),
  ProducerVariant('google_docs', buildZip(_googleDocs())),
  ProducerVariant('docm', buildZip(_docm())),
  ProducerVariant(
    'google_docs_no_numbering',
    buildZip(_googleDocs(numbering: false)),
  ),
];

/// The `w:p` elements of `d1Paragraphs`, with [element] and [attribute] as
/// the prefixes (each with its colon, or empty), [runProperties] inside
/// every run and [textAttributes] on every `w:t`.
String _paragraphs({
  String element = 'w:',
  String attribute = 'w:',
  String runProperties = '',
  String textAttributes = '',
}) {
  final String p = element;
  final StringBuffer out = StringBuffer();
  for (final (String? style, String text) in d1Paragraphs) {
    final String pPr = style == null
        ? ''
        : '<${p}pPr><${p}pStyle ${attribute}val="$style"/></${p}pPr>';
    if (text.isEmpty) {
      out.write(pPr.isEmpty ? '<${p}p/>' : '<${p}p>$pPr</${p}p>');
    } else {
      out.write(
        '<${p}p>$pPr<${p}r>$runProperties'
        '<${p}t$textAttributes>$text</${p}t></${p}r></${p}p>',
      );
    }
  }
  return out.toString();
}

/// A `w:document` holding [body] and, when given, [sectPr], with the
/// namespace declarations [namespaces] (`w` is always declared).
String _wDocument(String body, {String namespaces = '', String sectPr = ''}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:document xmlns:w="${Ns.w}"$namespaces>'
    '<w:body>$body$sectPr</w:body></w:document>';

/// A `[Content_Types].xml` with [defaults] (extension to type) and
/// [overrides] (part name to type).
List<int> _types(
  Map<String, String> defaults,
  Map<String, String> overrides,
) => utf8.encode(
  '<?xml version="1.0" encoding="UTF-8"?>\n'
  '<Types xmlns="$contentTypesNs">'
  '${<String>[for (final MapEntry<String, String> d in defaults.entries) '<Default Extension="${d.key}" ContentType="${d.value}"/>'].join()}'
  '${<String>[for (final MapEntry<String, String> o in overrides.entries) '<Override PartName="${o.key}" ContentType="${o.value}"/>'].join()}'
  '</Types>',
);

/// A relationships part of [rels], each `(id, type, target)`.
List<int> _rels(List<(String, String, String)> rels) => utf8.encode(
  '<?xml version="1.0" encoding="UTF-8"?>\n'
  '<Relationships xmlns="$packageRelsNs">'
  '${<String>[for (final (String id, String type, String target) in rels) '<Relationship Id="$id" Type="$type" Target="$target"/>'].join()}'
  '</Relationships>',
);

/// A small part whose root is `w:<root>`, for the parts the model copies.
List<int> _wPart(String root, [String content = '']) => utf8.encode(
  '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
  '<w:$root xmlns:w="${Ns.w}">$content</w:$root>',
);

/// LibreOffice Writer's layout: its document properties, every part
/// overridden, `xml` defaulting to `application/xml`, the officeDocument
/// relationship third, its namespace set on `w:document` without `w14`,
/// a `w:pStyle` and empty `w:rPr` on every paragraph and run, and its
/// section properties.
Map<String, List<int>> _libreOffice() => <String, List<int>>{
  '[Content_Types].xml': _types(
    <String, String>{
      'fntdata': 'application/x-fontdata',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'rels': ContentType.relationships,
      'xml': 'application/xml',
    },
    <String, String>{
      '/docProps/core.xml':
          'application/vnd.openxmlformats-package.core-properties+xml',
      '/docProps/app.xml':
          'application/vnd.openxmlformats-officedocument.extended-properties'
          '+xml',
      '/word/styles.xml': ContentType.wmlStyles,
      '/word/fontTable.xml': ContentType.wmlFontTable,
      '/word/settings.xml': ContentType.wmlSettings,
      '/word/document.xml': ContentType.wmlDocument,
    },
  ),
  '_rels/.rels': _rels(<(String, String, String)>[
    (
      'rId1',
      'http://schemas.openxmlformats.org/package/2006/relationships/'
          'metadata/core-properties',
      'docProps/core.xml',
    ),
    (
      'rId2',
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'extended-properties',
      'docProps/app.xml',
    ),
    ('rId3', RelType.officeDocument, 'word/document.xml'),
  ]),
  'docProps/app.xml': utf8.encode(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/'
    '2006/extended-properties"><Template></Template><TotalTime>0</TotalTime>'
    '<Application>LibreOffice/25.8.2.2\$MacOSX_AARCH64 LibreOffice_project/'
    '</Application></Properties>',
  ),
  'docProps/core.xml': utf8.encode(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/'
    '2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/'
    '1.1/"><dc:language>en-US</dc:language><cp:revision>1</cp:revision>'
    '</cp:coreProperties>',
  ),
  'word/_rels/document.xml.rels': _rels(<(String, String, String)>[
    (
      'rId1',
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'styles',
      'styles.xml',
    ),
    (
      'rId2',
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'fontTable',
      'fontTable.xml',
    ),
    (
      'rId3',
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'settings',
      'settings.xml',
    ),
  ]),
  'word/document.xml': utf8.encode(
    _wDocument(
      _paragraphs(runProperties: '<w:rPr></w:rPr>'),
      namespaces:
          ' xmlns:o="urn:schemas-microsoft-com:office:office"'
          ' xmlns:r="${Ns.rel}"'
          ' xmlns:v="urn:schemas-microsoft-com:vml"'
          ' xmlns:w10="urn:schemas-microsoft-com:office:word"'
          ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/'
          'wordprocessingDrawing"'
          ' xmlns:wps="http://schemas.microsoft.com/office/word/2010/'
          'wordprocessingShape"'
          ' xmlns:wpg="http://schemas.microsoft.com/office/word/2010/'
          'wordprocessingGroup"'
          ' xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/'
          '2006"'
          ' xmlns:wp14="http://schemas.microsoft.com/office/word/2010/'
          'wordprocessingDrawing"'
          ' mc:Ignorable="wp14"',
      sectPr:
          '<w:sectPr><w:type w:val="nextPage"/>'
          '<w:pgSz w:w="11906" w:h="16838"/>'
          '<w:pgMar w:left="1134" w:right="1134" w:gutter="0" w:header="0" '
          'w:top="1134" w:footer="0" w:bottom="1134"/>'
          '<w:pgNumType w:fmt="decimal"/><w:formProt w:val="false"/>'
          '<w:textDirection w:val="lrTb"/>'
          '<w:docGrid w:type="default" w:linePitch="100" w:charSpace="0"/>'
          '</w:sectPr>',
    ),
  ),
  'word/fontTable.xml': _wPart(
    'fonts',
    '<w:font w:name="Liberation Serif"><w:charset w:val="00"/>'
        '<w:family w:val="roman"/><w:pitch w:val="variable"/></w:font>',
  ),
  'word/settings.xml': _wPart(
    'settings',
    '<w:zoom w:percent="100"/><w:defaultTabStop w:val="709"/>'
        '<w:compat><w:compatSetting w:name="compatibilityMode" '
        'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/>'
        '</w:compat>',
  ),
  'word/styles.xml': _wPart(
    'styles',
    '<w:style w:type="paragraph" w:styleId="Normal"><w:name w:val="Normal"/>'
        '<w:qFormat/></w:style>',
  ),
};

/// Google Docs' layout: the main part named by an absolute target, ids
/// `rId1`, `rId2`… in the order of the parts, no `settings.xml`, a
/// `numbering.xml`, `xml:space="preserve"` on every `w:t` and
/// `w:rtl w:val="0"` in every run. Without [numbering] (the
/// `google_docs_no_numbering` variant) the package has no `numbering.xml`,
/// no relationship to one and no content type override for one, as a
/// Google Docs export of a document with no list has.
Map<String, List<int>> _googleDocs({
  bool numbering = true,
}) => <String, List<int>>{
  '[Content_Types].xml': _types(
    <String, String>{
      'rels': ContentType.relationships,
      'xml': 'application/xml',
    },
    <String, String>{
      if (numbering)
        '/word/numbering.xml':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.'
            'numbering+xml',
      '/word/styles.xml': ContentType.wmlStyles,
      '/word/fontTable.xml': ContentType.wmlFontTable,
      '/word/document.xml': ContentType.wmlDocument,
    },
  ),
  '_rels/.rels': _rels(<(String, String, String)>[
    ('rId1', RelType.officeDocument, '/word/document.xml'),
  ]),
  'word/_rels/document.xml.rels': _rels(<(String, String, String)>[
    (
      'rId1',
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'fontTable',
      'fontTable.xml',
    ),
    if (numbering)
      (
        'rId2',
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
            'numbering',
        'numbering.xml',
      ),
    (
      numbering ? 'rId3' : 'rId2',
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
          'styles',
      'styles.xml',
    ),
  ]),
  'word/document.xml': utf8.encode(
    _wDocument(
      _paragraphs(
        runProperties: '<w:rPr><w:rtl w:val="0"/></w:rPr>',
        textAttributes: ' xml:space="preserve"',
      ),
      namespaces:
          ' xmlns:r="${Ns.rel}"'
          ' xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/'
          '2006"'
          ' xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"'
          ' mc:Ignorable="w14"',
      sectPr:
          '<w:sectPr><w:pgSz w:w="12240" w:h="15840" w:orient="portrait"/>'
          '<w:pgMar w:bottom="1440" w:top="1440" w:left="1440" '
          'w:right="1440" w:header="720" w:footer="720"/>'
          '<w:pgNumType w:start="1"/></w:sectPr>',
    ),
  ),
  'word/fontTable.xml': _wPart('fonts', '<w:font w:name="Arial"/>'),
  if (numbering) 'word/numbering.xml': _wPart('numbering'),
  'word/styles.xml': _wPart(
    'styles',
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="normal"/></w:style>',
  ),
};

/// A macro-enabled document: the main part typed as one, and a VBA project
/// the model never reads, which must come back byte for byte.
Map<String, List<int>> _docm() => <String, List<int>>{
  '[Content_Types].xml': _types(
    <String, String>{
      'bin': _vbaType,
      'rels': ContentType.relationships,
      'xml': 'application/xml',
    },
    <String, String>{'/word/document.xml': ContentType.wmlMacroDocument},
  ),
  '_rels/.rels': _rels(<(String, String, String)>[
    ('rId1', RelType.officeDocument, 'word/document.xml'),
  ]),
  'word/_rels/document.xml.rels': _rels(<(String, String, String)>[
    ('rId1', _vbaRel, 'vbaProject.bin'),
  ]),
  'word/document.xml': utf8.encode(
    _wDocument(_paragraphs(), namespaces: ' xmlns:r="${Ns.rel}"'),
  ),
  'word/vbaProject.bin': <int>[
    ...cfbSignature,
    for (int i = 0; i < 504; i++) (i * 31 + 7) & 0xFF,
  ],
};
