/// Document properties of a workbook (`docProps/core.xml`,
/// `docProps/app.xml` and `docProps/custom.xml`).
///
/// Ported from quds_office_engine `lib/src/office/office_document_properties.dart` at commit 15c5d29.
/// Ported: the core and extended property parts. What changed: only the
/// fields a workbook needs are kept, elements are written in the order Excel
/// writes them, dates appear only when the caller gives them, and all text is
/// checked for characters XML forbids. New: the manager, the content status
/// and the custom properties (`docProps/custom.xml`), none of which Quds
/// wrote.
library;

import '../opc/ooxml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'limits.dart';
import 'sheet_name.dart';

/// The document properties stored in a workbook, shown by Excel under
/// File > Info.
///
/// Every field is optional; only the fields that are set are written. Text
/// must not contain characters XML cannot represent (control characters other
/// than tab, line feed and carriage return, and lone surrogates); otherwise
/// the writer constructors, `XlsxWriter` and `XlsxStreamWriter`, throw an
/// [ArgumentError]. The same constructors check [custom].
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
    this.manager,
    this.contentStatus,
    this.created,
    this.modified,
    this.custom = const <String, Object>{},
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

  /// The manager, written to the extended properties.
  final String? manager;

  /// The status of the content, for example `Draft` or `Final`, written to
  /// the core properties as `cp:contentStatus`.
  final String? contentStatus;

  /// When the workbook was created. Written in UTC with whole seconds. When
  /// null, no creation date is written, so the file is the same on every run.
  final DateTime? created;

  /// When the workbook was last modified. Written in UTC with whole seconds.
  /// When null, no modification date is written.
  final DateTime? modified;

  /// Custom properties, shown by Excel under File > Info > Properties >
  /// Advanced Properties > Custom, in map order.
  ///
  /// A value is a [String], a finite number, a [bool] or a [DateTime]
  /// (written in UTC with whole seconds). A whole number in the signed
  /// 32-bit range, an [int] or a [double] such as `3.0`, is written as an
  /// integer (`vt:i4`), any other number as a double (`vt:r8`), the same on
  /// the VM and the web.
  /// A name is 1 to [XlsxLimits.maxCustomPropertyNameLength] UTF-16 code
  /// units, holds no character XML forbids and is unique ignoring case.
  /// When empty, no custom part is written. The writer constructors throw an
  /// [ArgumentError] naming `custom` or `custom["<name>"]` for a bad entry.
  ///
  /// The map is held as given, not copied: the `const` default rules out
  /// `Map.unmodifiable` in the constructor. Do not change it after the
  /// writer is created: the writer checks and renders it then, so a later
  /// change would make this value differ from the file, and its `==` and
  /// `hashCode` change with it.
  final Map<String, Object> custom;

  @override
  bool operator ==(Object other) {
    if (other is! XlsxProperties) return false;
    if (other.title != title ||
        other.subject != subject ||
        other.creator != creator ||
        other.keywords != keywords ||
        other.description != description ||
        other.lastModifiedBy != lastModifiedBy ||
        other.category != category ||
        other.company != company ||
        other.manager != manager ||
        other.contentStatus != contentStatus ||
        other.created != created ||
        other.modified != modified ||
        other.custom.length != custom.length) {
      return false;
    }
    final Iterator<MapEntry<String, Object>> mine = custom.entries.iterator;
    final Iterator<MapEntry<String, Object>> theirs =
        other.custom.entries.iterator;
    while (mine.moveNext() && theirs.moveNext()) {
      if (mine.current.key != theirs.current.key ||
          mine.current.value != theirs.current.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    title,
    subject,
    creator,
    keywords,
    description,
    lastModifiedBy,
    category,
    company,
    manager,
    contentStatus,
    created,
    modified,
    Object.hashAll(<Object>[
      for (final MapEntry<String, Object> e in custom.entries) ...<Object>[
        e.key,
        e.value,
      ],
    ]),
  );

  @override
  String toString() =>
      'XlsxProperties(title: $title, subject: $subject, creator: $creator, '
      'keywords: $keywords, description: $description, '
      'lastModifiedBy: $lastModifiedBy, category: $category, '
      'company: $company, manager: $manager, '
      'contentStatus: $contentStatus, created: $created, '
      'modified: $modified, custom: $custom)';
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
  _text(w, 'cp:contentStatus', p.contentStatus);
  _date(w, 'dcterms:created', p.created);
  _date(w, 'dcterms:modified', p.modified);
  w.end();
}

/// Writes `docProps/app.xml`: the application name and, when set, the
/// company and manager of [p].
///
/// Throws [ArgumentError] when the company or manager holds forbidden
/// characters.
void writeAppProperties(XmlWriter w, XlsxProperties p) {
  w.declaration();
  w.start('Properties');
  w.attribute('xmlns', Ns.extendedProperties);
  _text(w, 'Application', 'jet_office');
  _text(w, 'Company', p.company);
  _text(w, 'Manager', p.manager);
  w.end();
}

/// The format id every custom property carries (the "user defined
/// properties" property set).
const String _customFormatId = '{D5CDD505-2E9C-101B-9397-08002B2CF9AE}';

/// Writes `docProps/custom.xml`: one `property` per entry of [p]'s `custom`
/// map, with `pid` from 2 in map order.
///
/// Throws [ArgumentError] naming `custom` for a name that is empty, longer
/// than [XlsxLimits.maxCustomPropertyNameLength], holds forbidden characters
/// or repeats an earlier name ignoring case, and naming `custom["<name>"]`
/// for a value that is not a [String], a finite number, a [bool] or a
/// [DateTime], or a string holding forbidden characters. Check everything
/// before writing, so a throw leaves no partial part.
///
/// A whole number within the signed 32-bit range, an [int] or a [double]
/// such as `3.0`, is written `vt:i4`; any other finite number, [int] or
/// [double], is `vt:r8`, so no finite number throws. The VM and the web
/// agree, although a whole [double] is an [int] on the web: `3.0` is
/// `vt:i4` and `0.5` and `3e9` are `vt:r8` on both.
void writeCustomProperties(XmlWriter w, XlsxProperties p) {
  final Set<String> seen = <String>{};
  for (final MapEntry<String, Object> e in p.custom.entries) {
    _checkCustomName(e.key, seen);
    _checkCustomValue(e.key, e.value);
  }
  w.declaration();
  w.start('Properties');
  w.attribute('xmlns', Ns.customProperties);
  w.attribute('xmlns:vt', Ns.docPropsVTypes);
  int pid = 2;
  for (final MapEntry<String, Object> e in p.custom.entries) {
    w.start('property');
    w.attribute('fmtid', _customFormatId);
    w.attribute('pid', '${pid++}');
    w.attribute('name', e.key);
    final Object v = e.value;
    switch (v) {
      case String():
        w.start('vt:lpwstr');
        w.text(v);
      case num() when _isI4(v):
        w.start('vt:i4');
        // toInt: on the web -0.0 is an int that prints as "-0.0".
        w.text('${v.toInt()}');
      case num():
        w.start('vt:r8');
        w.text(formatXmlDouble(v.toDouble()));
      case bool():
        w.start('vt:bool');
        w.text(v ? 'true' : 'false');
      case DateTime():
        w.start('vt:filetime');
        w.text(_w3cdtf(v));
      default:
        throw StateError('unreachable: checked above');
    }
    w.end();
    w.end();
  }
  w.end();
}

/// Whether [value], a finite number, is written `vt:i4`: a whole number,
/// an [int] or a [double] such as `3.0`, in the signed 32-bit range.
///
/// A whole [double] counts, so the VM writes what the web writes, where
/// it is an [int]. The range is tested first, so `truncate` cannot
/// overflow.
bool _isI4(num value) =>
    value >= -2147483648 && value <= 2147483647 && value == value.truncate();

void _checkCustomName(String name, Set<String> seen) {
  if (name.isEmpty) {
    throw ArgumentError.value(name, 'custom', 'A name must not be empty.');
  }
  if (name.length > XlsxLimits.maxCustomPropertyNameLength) {
    throw ArgumentError.value(
      '${name.length} characters',
      'custom',
      'A name has at most ${XlsxLimits.maxCustomPropertyNameLength} '
          'characters.',
    );
  }
  if (scrubXmlText(name).removed != 0) {
    throw ArgumentError.value(
      name,
      'custom',
      'A name contains characters XML forbids (control characters or lone '
          'surrogates).',
    );
  }
  if (!seen.add(sheetNameKey(name))) {
    throw ArgumentError.value(
      name,
      'custom',
      'Two names are equal ignoring case.',
    );
  }
}

void _checkCustomValue(String name, Object value) {
  final String field = 'custom["$name"]';
  switch (value) {
    case String():
      if (scrubXmlText(value).removed != 0) {
        throw ArgumentError.value(
          value,
          field,
          'Contains characters XML forbids (control characters or lone '
          'surrogates).',
        );
      }
    case num():
      if (!value.isFinite) {
        throw ArgumentError.value(value, field, 'A number must be finite.');
      }
    case bool() || DateTime():
      break;
    default:
      throw ArgumentError.value(
        value,
        field,
        'A value is a String, an int, a double, a bool or a DateTime, not '
        '${value.runtimeType}.',
      );
  }
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
