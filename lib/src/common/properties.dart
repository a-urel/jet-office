/// Document properties of a workbook or a document (`docProps/core.xml`,
/// `docProps/app.xml` and `docProps/custom.xml`), shared by both formats.
///
/// Ported from quds_office_engine `lib/src/office/office_document_properties.dart` at commit 15c5d29.
/// Ported: the core and extended property parts. What changed: the fields
/// workbooks and documents share are kept, elements are written in one fixed
/// order, the one Excel writes, for both formats, dates appear only when the
/// caller gives them, and all text is checked for characters XML forbids.
/// New: the manager, the content status, the revision, the application and
/// the custom properties (`docProps/custom.xml`), none of which Quds wrote.
library;

import '../opc/ooxml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'name_key.dart';

/// The longest name of a custom document property, in UTF-16 code units.
///
/// jet_office sets 255, the length of Excel's Custom Properties name box.
/// The value is not on Microsoft's "Excel specifications and limits"
/// page. `maxCustomPropertyNameLength` is this value.
const int maxCustomPropertyNameLength = 255;

/// The document properties stored in a workbook or a document, shown by
/// Excel and Word under File > Info.
///
/// Every field is optional; only the fields that are set are written. Text
/// must not contain characters XML cannot represent (control characters other
/// than tab, line feed and carriage return, and lone surrogates); otherwise
/// the workbook writer constructors, `XlsxWriter` and `XlsxStreamWriter`,
/// and the `properties` setters of the models throw an [ArgumentError]. The
/// same check covers [custom].
final class OfficeProperties {
  /// Creates the properties. All fields are optional.
  const OfficeProperties({
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
    this.revision,
    this.application,
    this.created,
    this.modified,
    this.custom = const <String, Object>{},
  });

  /// The title of the workbook or document.
  final String? title;

  /// The subject of the workbook or document.
  final String? subject;

  /// The author of the workbook or document.
  final String? creator;

  /// Keywords, as one string (conventionally separated by semicolons).
  final String? keywords;

  /// A description, shown by Excel and Word as "Comments".
  final String? description;

  /// The name of the person who last modified the workbook or document.
  final String? lastModifiedBy;

  /// The category of the workbook or document.
  final String? category;

  /// The company, written to the extended properties.
  final String? company;

  /// The manager, written to the extended properties.
  final String? manager;

  /// The status of the content, for example `Draft` or `Final`, written to
  /// the core properties as `cp:contentStatus`.
  final String? contentStatus;

  /// How many times the file was saved, as Word counts it, written to the
  /// core properties as `cp:revision`. Not negative: `checkProperties`, the
  /// writer constructors and the setters throw an [ArgumentError] naming
  /// `revision` for a negative one.
  final int? revision;

  /// The application that wrote the file, written to the extended
  /// properties as `Application`. The workbook writers write `jet_office`
  /// when it is null; a model writes it only when it is set, and removes it
  /// for a null.
  final String? application;

  /// When the workbook or document was created. Written in UTC with whole
  /// seconds. When null, no creation date is written, so the file is the
  /// same on every run.
  final DateTime? created;

  /// When the workbook or document was last modified. Written in UTC with
  /// whole seconds. When null, no modification date is written.
  final DateTime? modified;

  /// Custom properties, shown by Excel and Word under File > Info >
  /// Properties > Advanced Properties > Custom, in map order.
  ///
  /// A value is a [String], a finite number, a [bool] or a [DateTime]
  /// (written in UTC with whole seconds). A whole number in the signed
  /// 32-bit range, an [int] or a [double] such as `3.0`, is written as an
  /// integer (`vt:i4`), any other number as a double (`vt:r8`), the same on
  /// the VM and the web.
  /// A name is 1 to 255 UTF-16 code units
  /// (`XlsxLimits.maxCustomPropertyNameLength`), holds no character XML
  /// forbids and is unique ignoring case.
  /// When empty, no custom part is written. The writer constructors and the
  /// setters throw an [ArgumentError] naming `custom` or `custom["<name>"]`
  /// for a bad entry.
  ///
  /// The map is held as given, not copied: the `const` default rules out
  /// `Map.unmodifiable` in the constructor. Do not change it after the
  /// writer is created: the writer checks and renders it then, so a later
  /// change would make this value differ from the file, and its `==` and
  /// `hashCode` change with it.
  final Map<String, Object> custom;

  /// These properties with each field the call gives replaced and every
  /// other field kept, so a caller changing one field does not copy the rest
  /// by hand.
  ///
  /// A parameter that is `null`, or left out, keeps the field: this method
  /// cannot clear one. To remove a field, build the properties with the
  /// constructor, which leaves it `null`. [custom] is replaced as a whole
  /// (the map given, held as given, not merged with the old one); left out,
  /// the copy shares this one's map. The values are not checked here: the
  /// writer constructors and the `properties` setters check them, as for any
  /// [OfficeProperties].
  OfficeProperties copyWith({
    String? title,
    String? subject,
    String? creator,
    String? keywords,
    String? description,
    String? lastModifiedBy,
    String? category,
    String? company,
    String? manager,
    String? contentStatus,
    int? revision,
    String? application,
    DateTime? created,
    DateTime? modified,
    Map<String, Object>? custom,
  }) => OfficeProperties(
    title: title ?? this.title,
    subject: subject ?? this.subject,
    creator: creator ?? this.creator,
    keywords: keywords ?? this.keywords,
    description: description ?? this.description,
    lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    category: category ?? this.category,
    company: company ?? this.company,
    manager: manager ?? this.manager,
    contentStatus: contentStatus ?? this.contentStatus,
    revision: revision ?? this.revision,
    application: application ?? this.application,
    created: created ?? this.created,
    modified: modified ?? this.modified,
    custom: custom ?? this.custom,
  );

  @override
  bool operator ==(Object other) {
    if (other is! OfficeProperties) return false;
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
        other.revision != revision ||
        other.application != application ||
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
    revision,
    application,
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
      'OfficeProperties(title: $title, subject: $subject, creator: $creator, '
      'keywords: $keywords, description: $description, '
      'lastModifiedBy: $lastModifiedBy, category: $category, '
      'company: $company, manager: $manager, '
      'contentStatus: $contentStatus, revision: $revision, '
      'application: $application, created: $created, '
      'modified: $modified, custom: $custom)';
}

/// Throws what the writer constructors throw for a bad [p]: an
/// [ArgumentError] naming the field when a text field holds characters XML
/// forbids or the revision is negative, naming `custom` or
/// `custom["<name>"]` for a bad custom entry.
///
/// It runs the checks of [writeCoreProperties], [writeAppProperties] and
/// [writeCustomProperties] without writing anything, so a setter can refuse
/// a value before it changes the model.
void checkProperties(OfficeProperties p) {
  _checkText('dc:title', p.title);
  _checkText('dc:subject', p.subject);
  _checkText('dc:creator', p.creator);
  _checkText('cp:keywords', p.keywords);
  _checkText('dc:description', p.description);
  _checkText('cp:lastModifiedBy', p.lastModifiedBy);
  _checkText('cp:category', p.category);
  _checkText('cp:contentStatus', p.contentStatus);
  _checkText('Company', p.company);
  _checkText('Manager', p.manager);
  _checkText('Application', p.application);
  _checkRevision(p.revision);
  final Set<String> seen = <String>{};
  for (final MapEntry<String, Object> e in p.custom.entries) {
    _checkCustomName(e.key, seen);
    _checkCustomValue(e.key, e.value);
  }
}

/// Writes `docProps/core.xml`, with only the fields set in [p].
///
/// Throws [ArgumentError] when a text field holds forbidden characters.
void writeCoreProperties(XmlWriter w, OfficeProperties p) {
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
  _revision(w, p.revision);
  _text(w, 'cp:category', p.category);
  _text(w, 'cp:contentStatus', p.contentStatus);
  _date(w, 'dcterms:created', p.created);
  _date(w, 'dcterms:modified', p.modified);
  w.end();
}

/// Writes `docProps/app.xml`: the application name and, when set, the
/// company and manager of [p].
///
/// The application is [OfficeProperties.application], or
/// [fallbackApplication] when that is null (no `Application` when both
/// are). Throws [ArgumentError] when the application, company or manager
/// holds forbidden characters.
void writeAppProperties(
  XmlWriter w,
  OfficeProperties p, {
  String? fallbackApplication = 'jet_office',
}) {
  w.declaration();
  w.start('Properties');
  w.attribute('xmlns', Ns.extendedProperties);
  _text(w, 'Application', p.application ?? fallbackApplication);
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
/// than [maxCustomPropertyNameLength], holds forbidden characters
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
void writeCustomProperties(XmlWriter w, OfficeProperties p) {
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
        w.text(w3cdtf(v));
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
  if (name.length > maxCustomPropertyNameLength) {
    throw ArgumentError.value(
      '${name.length} characters',
      'custom',
      'A name has at most $maxCustomPropertyNameLength '
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
  if (!seen.add(officeNameKey(name))) {
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

void _checkRevision(int? value) {
  if (value != null && value < 0) {
    throw ArgumentError.value(value, 'revision', 'Must not be negative.');
  }
}

void _revision(XmlWriter w, int? value) {
  if (value == null) return;
  _checkRevision(value);
  w.start('cp:revision');
  w.text('$value');
  w.end();
}

void _checkText(String name, String? value) {
  if (value == null) return;
  if (scrubXmlText(value).removed != 0) {
    throw ArgumentError.value(
      value,
      name,
      'Contains characters XML forbids (control characters or lone '
      'surrogates).',
    );
  }
}

void _text(XmlWriter w, String name, String? value) {
  if (value == null) return;
  _checkText(name, value);
  w.start(name);
  w.text(value);
  w.end();
}

void _date(XmlWriter w, String name, DateTime? value) {
  if (value == null) return;
  w.start(name);
  w.attribute('xsi:type', 'dcterms:W3CDTF');
  w.text(w3cdtf(value));
  w.end();
}

/// [value] as the W3CDTF text of a core date or a custom `vt:filetime`: UTC,
/// whole seconds, `2026-10-24T09:30:00Z`.
String w3cdtf(DateTime value) {
  final DateTime u = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final String year = u.year.toString().padLeft(4, '0');
  return '$year-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// Reads [text] as a W3CDTF date (`2026-10-24T09:30:00Z`, with an offset,
/// with fractions of a second, without a zone, or a date or year alone) in
/// UTC; `null` when it is not one. A text without a zone is read as UTC.
DateTime? parseW3cdtf(String text) {
  final RegExpMatch? m = _w3cdtfPattern.firstMatch(text.trim());
  if (m == null) return null;
  int part(int group, int fallback) =>
      m.group(group) == null ? fallback : int.parse(m.group(group)!);
  final int year = int.parse(m.group(1)!);
  final int month = part(2, 1);
  final int day = part(3, 1);
  final int hour = part(4, 0);
  final int minute = part(5, 0);
  final int second = part(6, 0);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final String? fraction = m.group(7);
  final int millis = fraction == null
      ? 0
      : int.parse(fraction.padRight(3, '0').substring(0, 3));
  final DateTime utc = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    millis,
  );
  // A day the month lacks would roll over into the next month.
  if (utc.month != month || utc.day != day) return null;
  final String? zone = m.group(8);
  if (zone == null || zone == 'Z') return utc;
  final int sign = zone.startsWith('-') ? -1 : 1;
  final String digits = zone.substring(1).replaceAll(':', '');
  final int offset =
      int.parse(digits.substring(0, 2)) * 60 + int.parse(digits.substring(2));
  return utc.subtract(Duration(minutes: sign * offset));
}

final RegExp _w3cdtfPattern = RegExp(
  r'^(\d{4})(?:-(\d{2})(?:-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})'
  r'(?:[.,](\d+))?)?(Z|[+-]\d{2}:?\d{2})?)?)?)?$',
);
