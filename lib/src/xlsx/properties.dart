/// Document properties of a workbook (`docProps/core.xml` and
/// `docProps/app.xml`).
///
/// Ported from quds_office_engine `lib/src/office/office_document_properties.dart` at commit 15c5d29.
/// Ported: the core and extended property parts. What changed: only the
/// fields a workbook needs are kept, elements are written in the order Excel
/// writes them, dates appear only when the caller gives them, and all text is
/// checked for characters XML forbids.
library;

import '../opc/ooxml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';

/// The document properties stored in a workbook, shown by Excel under
/// File > Info.
///
/// Every field is optional; only the fields that are set are written. Text
/// must not contain characters XML cannot represent (control characters other
/// than tab, line feed and carriage return, and lone surrogates); otherwise
/// the writer constructors, `XlsxWriter` and `XlsxStreamWriter`, throw an
/// [ArgumentError].
final class XlsxProperties {
  /// Creates the properties. All fields are optional.
  const XlsxProperties({
    this.title,
    this.subject,
    this.creator,
    this.keywords,
    this.description,
    this.lastModifiedBy,
    this.category,
    this.company,
    this.created,
    this.modified,
  });

  /// The title of the workbook.
  final String? title;

  /// The subject of the workbook.
  final String? subject;

  /// The author of the workbook.
  final String? creator;

  /// Keywords, as one string (conventionally separated by semicolons).
  final String? keywords;

  /// A description, shown by Excel as "Comments".
  final String? description;

  /// The name of the person who last modified the workbook.
  final String? lastModifiedBy;

  /// The category of the workbook.
  final String? category;

  /// The company, written to the extended properties.
  final String? company;

  /// When the workbook was created. Written in UTC with whole seconds. When
  /// null, no creation date is written, so the file is the same on every run.
  final DateTime? created;

  /// When the workbook was last modified. Written in UTC with whole seconds.
  /// When null, no modification date is written.
  final DateTime? modified;
}

/// Writes `docProps/core.xml`, with only the fields set in [p].
///
/// Throws [ArgumentError] when a text field holds forbidden characters.
void writeCoreProperties(XmlWriter w, XlsxProperties p) {
  w.declaration();
  w.start('cp:coreProperties');
  w.attribute('xmlns:cp', Ns.core);
  w.attribute('xmlns:dc', Ns.dc);
  w.attribute('xmlns:dcterms', Ns.dcterms);
  w.attribute('xmlns:dcmitype', Ns.dcmitype);
  w.attribute('xmlns:xsi', Ns.xsi);
  _text(w, 'dc:title', p.title);
  _text(w, 'dc:subject', p.subject);
  _text(w, 'dc:creator', p.creator);
  _text(w, 'cp:keywords', p.keywords);
  _text(w, 'dc:description', p.description);
  _text(w, 'cp:lastModifiedBy', p.lastModifiedBy);
  _text(w, 'cp:category', p.category);
  _date(w, 'dcterms:created', p.created);
  _date(w, 'dcterms:modified', p.modified);
  w.end();
}

/// Writes `docProps/app.xml`: the application name and, when set, the
/// company of [p].
///
/// Throws [ArgumentError] when the company holds forbidden characters.
void writeAppProperties(XmlWriter w, XlsxProperties p) {
  w.declaration();
  w.start('Properties');
  w.attribute('xmlns', Ns.extendedProperties);
  _text(w, 'Application', 'jet_office');
  _text(w, 'Company', p.company);
  w.end();
}

void _text(XmlWriter w, String name, String? value) {
  if (value == null) return;
  final ScrubResult scrubbed = scrubXmlText(value);
  if (scrubbed.removed != 0) {
    throw ArgumentError.value(
      value,
      name,
      'Contains characters XML forbids (control characters or lone '
      'surrogates).',
    );
  }
  w.start(name);
  w.text(value);
  w.end();
}

void _date(XmlWriter w, String name, DateTime? value) {
  if (value == null) return;
  w.start(name);
  w.attribute('xsi:type', 'dcterms:W3CDTF');
  w.text(_w3cdtf(value));
  w.end();
}

String _w3cdtf(DateTime value) {
  final DateTime u = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final String year = u.year.toString().padLeft(4, '0');
  return '$year-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}
