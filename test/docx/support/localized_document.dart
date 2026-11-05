/// Test helper: Word-like DOCX packages in memory whose style ids are not
/// the English ones, as Word writes them under a Turkish or a German system.
/// A built-in style keeps its English `w:name` there, and its `w:styleId`
/// is derived from the localized name. Nothing touches the file system, so
/// it runs in Chrome.
library;

import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import 'styles_documents.dart';

/// A `w:style` of [type] with the id [id] and the name [name]; [attributes]
/// and [children] are written as given.
String styleXml(
  String type,
  String id,
  String name, {
  String attributes = '',
  String children = '',
}) =>
    '<w:style w:type="$type"$attributes w:styleId="$id">'
    '<w:name w:val="$name"/>$children</w:style>';

/// A `styles.xml` that holds [styles] and nothing else.
String stylesXmlOf(Iterable<String> styles) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<w:styles xmlns:w="${Ns.w}">${styles.join()}</w:styles>';

const String _default = ' w:default="1"';

/// The body of [localizedWordDocx] and [germanStyleDocx]: a paragraph that
/// names `Heading3`, which neither document defines, one whose run names
/// `Yok`, which none does, and a plain paragraph.
const String localizedDocumentXml =
    '<w:document xmlns:w="${Ns.w}"><w:body>'
    '<w:p><w:pPr><w:pStyle w:val="Heading3"/></w:pPr>'
    '<w:r><w:t>Okunan</w:t></w:r></w:p>'
    '<w:p><w:r><w:rPr><w:rStyle w:val="Yok"/></w:rPr>'
    '<w:t>Karakter</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>Metin</w:t></w:r></w:p>'
    '</w:body></w:document>';

/// A Word-like package as a Turkish Word writes it: `Normal` (default),
/// `Balk1` named `heading 1`, `KonuBal` named `Title`, `ListeParagraf` named
/// `List Paragraph`, `VarsaylanParagrafYazTipi` (default character),
/// `NormalTablo` (default table), `ListeYok` (default numbering), and
/// `Heading2` named `My heading`, a custom style squatting an English id.
Uint8List localizedWordDocx() => docxWithStyles(
  document: localizedDocumentXml,
  styles: stylesXmlOf(<String>[
    styleXml('paragraph', 'Normal', 'Normal', attributes: _default),
    styleXml(
      'paragraph',
      'Balk1',
      'heading 1',
      children: '<w:basedOn w:val="Normal"/>',
    ),
    styleXml(
      'paragraph',
      'KonuBal',
      'Title',
      children: '<w:basedOn w:val="Normal"/>',
    ),
    styleXml(
      'paragraph',
      'ListeParagraf',
      'List Paragraph',
      children: '<w:basedOn w:val="Normal"/>',
    ),
    styleXml(
      'character',
      'VarsaylanParagrafYazTipi',
      'Default Paragraph Font',
      attributes: _default,
    ),
    styleXml('table', 'NormalTablo', 'Normal Table', attributes: _default),
    styleXml('numbering', 'ListeYok', 'No List', attributes: _default),
    styleXml(
      'paragraph',
      'Heading2',
      'My heading',
      attributes: ' w:customStyle="1"',
      children: '<w:basedOn w:val="Normal"/>',
    ),
  ]),
);

/// A package with German Word's ids: `Standard` named `Normal` (default),
/// `berschrift1` named `heading 1`, `berschrift2` named `Heading 2` (the
/// case differs on purpose), `Absatz-Standardschriftart` named `Default
/// Paragraph Font` (default character), `NormaleTabelle` named `Normal
/// Table` (default table), and `Gliederung` named `Chapter` with
/// `w:outlineLvl w:val="0"`, a custom style with an outline level.
Uint8List germanStyleDocx() => docxWithStyles(
  document: localizedDocumentXml,
  styles: stylesXmlOf(<String>[
    styleXml(
      'paragraph',
      'Gliederung',
      'Chapter',
      attributes: ' w:customStyle="1"',
      children:
          '<w:basedOn w:val="Standard"/>'
          '<w:pPr><w:outlineLvl w:val="0"/></w:pPr>',
    ),
    styleXml('paragraph', 'Standard', 'Normal', attributes: _default),
    styleXml(
      'paragraph',
      'berschrift1',
      'heading 1',
      children: '<w:basedOn w:val="Standard"/>',
    ),
    styleXml(
      'paragraph',
      'berschrift2',
      'Heading 2',
      children: '<w:basedOn w:val="Standard"/>',
    ),
    styleXml(
      'character',
      'Absatz-Standardschriftart',
      'Default Paragraph Font',
      attributes: _default,
    ),
    styleXml('table', 'NormaleTabelle', 'Normal Table', attributes: _default),
  ]),
);
