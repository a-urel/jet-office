/// Opens an untrusted OPC package and resolves its parts and relationships.
///
/// Ported from quds_office_engine `lib/src/opc/content_types.dart` and
/// `lib/src/opc/relationships.dart` at commit 15c5d29, read side only:
/// `ContentTypes.parse`, `contentTypeFor`, `RelationshipCollection.parse` and
/// `resolve`.
///
/// What changed: the ZIP is opened with limits through `ZipReader`; every
/// ZIP and XML failure becomes an [XlsxReadException]; the workbook part is
/// found through the root relationship, wherever it lives, with the content
/// type override as a fallback; Strict OOXML and `.xlsb` are refused;
/// targets are resolved against the source part with `.` and `..` applied,
/// retried percent-decoded, and part names are matched without regard to
/// case or slash direction.
library;

import 'dart:typed_data';

import '../../xml/xml_pull_reader.dart';
import '../../zip/archive_adapter.dart';
import 'read_exception.dart';
import 'read_limits.dart';

const String _officeDocumentType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'officeDocument';
const String _strictOfficeDocumentType =
    'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument';
const String _xlsbType =
    'application/vnd.ms-excel.sheet.binary.macroEnabled.main';
const List<String> _workbookTypes = <String>[
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
  'application/vnd.ms-excel.sheet.macroEnabled.main+xml',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.template.main'
      '+xml',
];
const String _contentTypesPart = '[Content_Types].xml';

/// One internal relationship of a package part.
final class PartRelationship {
  /// Creates a relationship [id] of [type] to the part named [target].
  const PartRelationship(this.id, this.type, this.target);

  /// The relationship id, such as `rId1`.
  final String id;

  /// The relationship type URI.
  final String type;

  /// The target part name, normalized: relative to the package root, with no
  /// leading `/`.
  final String target;
}

/// An opened OPC package: the ZIP, its workbook part and its relationships.
///
/// Opening reads only the ZIP directory, `[Content_Types].xml` and the root
/// relationships. Every failure is an [XlsxReadException]. Callers that read
/// from the XML returned by [openXml] should wrap that work in [guardXml],
/// because some XML errors (a bad entity in character data) only surface
/// while reading.
final class PackageReader {
  /// Opens [bytes] within [limits] and finds the workbook part.
  ///
  /// Throws an [XlsxReadException] when the file is not a readable XLSX.
  PackageReader(Uint8List bytes, XlsxReadLimits limits)
    : _limits = limits,
      _zip = _openZip(bytes, limits) {
    _overrides = _readContentTypes();
    workbookPart = _findWorkbook();
  }

  final XlsxReadLimits _limits;
  final ZipReader _zip;
  late final Map<String, String> _overrides;
  final Map<String, String> _defaults = <String, String>{};

  /// The workbook part name, normalized: no leading `/`.
  late final String workbookPart;

  /// The internal relationships of [part], in file order.
  ///
  /// External targets are left out. A part without a relationships part has
  /// none. Throws an [XlsxReadException] when the relationships part is not
  /// readable XML.
  List<PartRelationship> relationshipsOf(String part) {
    final String source = _normalize(part);
    final int slash = source.lastIndexOf('/');
    final String folder = slash < 0 ? '' : source.substring(0, slash + 1);
    final String name = slash < 0 ? source : source.substring(slash + 1);
    final String relsPart =
        '$folder'
        '_rels/$name.rels';
    if (!_zip.contains(relsPart)) return const <PartRelationship>[];
    final Uint8List bytes = _readEntry(relsPart);
    return guardXml(relsPart, () {
      final XmlPullReader reader = XmlPullReader.fromBytes(
        bytes,
        maxDepth: _limits.maxDepth,
      );
      final List<PartRelationship> result = <PartRelationship>[];
      while (reader.next()) {
        if (reader.eventType != XmlEventType.startElement ||
            reader.localName != 'Relationship') {
          continue;
        }
        final String? id = reader.getAttribute('Id');
        final String? type = reader.getAttribute('Type');
        final String? target = reader.getAttribute('Target');
        if (id == null || type == null || target == null) continue;
        final String? mode = reader.getAttribute('TargetMode');
        if (mode != null && mode.toLowerCase() == 'external') continue;
        result.add(PartRelationship(id, type, _resolve(folder, target)));
      }
      return result;
    });
  }

  /// Whether the package holds a part named [part], matched without regard
  /// to case or slash direction.
  bool hasPart(String part) => _zip.contains(_normalize(part));

  /// A pull reader over the XML part [part].
  ///
  /// The part's bytes are inflated, decoded and then dropped. Throws an
  /// [XlsxReadException] for a corrupt entry or XML that cannot start, and a
  /// [StateError] when there is no such part; check [hasPart] first.
  XmlPullReader openXml(String part) {
    final String name = _normalize(part);
    if (!_zip.contains(name)) {
      throw StateError('The package has no part "$part".');
    }
    return guardXml(part, () {
      final Uint8List bytes = _readEntry(name);
      return XmlPullReader.fromBytes(bytes, maxDepth: _limits.maxDepth);
    });
  }

  /// Runs [body], mapping an [XmlParseException] or [ZipReadError] to an
  /// [XlsxReadException] that names [part].
  ///
  /// Use it around reading from the reader [openXml] returns.
  T guardXml<T>(String part, T Function() body) {
    try {
      return body();
    } on XmlParseException catch (e) {
      if (e.kind == XmlParseKind.tooDeep) {
        throw XlsxReadException(
          XlsxReadFailure.limitExceeded,
          'Limit maxDepth (${_limits.maxDepth}) exceeded: ${e.message}.',
          part: part,
        );
      }
      throw XlsxReadException(
        XlsxReadFailure.malformedXml,
        'The XML of "$part" cannot be read: ${e.message}.',
        part: part,
      );
    } on ZipReadError catch (e) {
      throw _mapZipError(e);
    }
  }

  Uint8List _readEntry(String name) {
    try {
      return _zip.read(name);
    } on ZipReadError catch (e) {
      throw _mapZipError(e, part: name);
    }
  }

  Map<String, String> _readContentTypes() {
    final Map<String, String> overrides = <String, String>{};
    if (!_zip.contains(_contentTypesPart)) return overrides;
    final Uint8List bytes = _readEntry(_contentTypesPart);
    guardXml(_contentTypesPart, () {
      final XmlPullReader reader = XmlPullReader.fromBytes(
        bytes,
        maxDepth: _limits.maxDepth,
      );
      while (reader.next()) {
        if (reader.eventType != XmlEventType.startElement) continue;
        final String? type = reader.getAttribute('ContentType');
        if (type == null) continue;
        if (reader.localName == 'Default') {
          final String? ext = reader.getAttribute('Extension');
          if (ext != null) _defaults[ext.toLowerCase()] = type;
        } else if (reader.localName == 'Override') {
          final String? part = reader.getAttribute('PartName');
          if (part != null) overrides[_normalize(part).toLowerCase()] = type;
        }
      }
    });
    return overrides;
  }

  String _findWorkbook() {
    String? found;
    if (_zip.contains('_rels/.rels')) {
      // The root relationships belong to the package itself: part ''.
      for (final PartRelationship rel in relationshipsOf('')) {
        if (rel.type == _strictOfficeDocumentType) {
          throw const XlsxReadException(
            XlsxReadFailure.unsupportedFormat,
            'The workbook is Strict OOXML, which is not supported; save it '
            'as an Excel Workbook (.xlsx).',
          );
        }
        if (rel.type == _officeDocumentType && hasPart(rel.target)) {
          found = rel.target;
          break;
        }
      }
    }
    if (found == null) {
      for (final MapEntry<String, String> entry in _overrides.entries) {
        if (_workbookTypes.contains(entry.value) && hasPart(entry.key)) {
          found = _actualName(entry.key);
          break;
        }
      }
    }
    if (found == null) {
      throw const XlsxReadException(
        XlsxReadFailure.missingWorkbook,
        'The package has no workbook part.',
      );
    }
    if (_contentTypeFor(found) == _xlsbType) {
      throw const XlsxReadException(
        XlsxReadFailure.unsupportedFormat,
        'The workbook is a binary .xlsb file, which is not supported; save '
        'it as an Excel Workbook (.xlsx).',
      );
    }
    return found;
  }

  /// The ZIP entry name that matches [lowerCased], as stored.
  String _actualName(String lowerCased) {
    for (final String name in _zip.names) {
      if (name.toLowerCase() == lowerCased) return name;
    }
    return lowerCased;
  }

  String _contentTypeFor(String part) {
    final String key = _normalize(part).toLowerCase();
    final String? override = _overrides[key];
    if (override != null) return override;
    final int dot = key.lastIndexOf('.');
    if (dot < 0 || dot == key.length - 1) return 'application/octet-stream';
    return _defaults[key.substring(dot + 1)] ?? 'application/octet-stream';
  }

  /// Resolves [target] against [folder] (ending in `/`, or empty), applying
  /// `.` and `..`; a leading `/` means the package root. A target missing
  /// from the ZIP is retried percent-decoded.
  String _resolve(String folder, String target) {
    final String slashed = target.replaceAll(r'\', '/');
    final String joined = slashed.startsWith('/') ? slashed : '$folder$slashed';
    final String resolved = _applySegments(joined);
    if (_zip.contains(resolved)) return resolved;
    try {
      final String decoded = _applySegments(Uri.decodeFull(joined));
      if (_zip.contains(decoded)) return decoded;
    } on ArgumentError {
      // Not valid percent-encoding: keep the literal name.
    } on FormatException {
      // The escapes do not decode to UTF-8: keep the literal name.
    }
    return resolved;
  }

  static String _applySegments(String path) {
    final List<String> out = <String>[];
    for (final String segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(segment);
    }
    return out.join('/');
  }

  /// [part] as a package-root-relative name with `/` separators.
  static String _normalize(String part) =>
      part.replaceAll(r'\', '/').replaceFirst(RegExp('^/+'), '');

  static ZipReader _openZip(Uint8List bytes, XlsxReadLimits limits) {
    try {
      return ZipReader(
        bytes,
        maxEntries: limits.maxEntries,
        maxEntryBytes: limits.maxEntryBytes,
        maxTotalBytes: limits.maxTotalBytes,
        maxCompressionRatio: limits.maxCompressionRatio,
      );
    } on ZipReadError catch (e) {
      throw _mapZipError(e);
    }
  }

  static XlsxReadException _mapZipError(ZipReadError e, {String? part}) {
    final String? entry = e.entry ?? part;
    XlsxReadException limit(String name) => XlsxReadException(
      XlsxReadFailure.limitExceeded,
      'Limit $name exceeded: ${e.message}',
      part: entry,
    );
    switch (e.kind) {
      case ZipReadErrorKind.notZip:
        return XlsxReadException(
          XlsxReadFailure.notZip,
          e.message,
          part: entry,
        );
      case ZipReadErrorKind.corrupt:
      case ZipReadErrorKind.duplicateEntry:
        return XlsxReadException(
          XlsxReadFailure.corruptZip,
          e.message,
          part: entry,
        );
      case ZipReadErrorKind.encrypted:
        return XlsxReadException(
          XlsxReadFailure.encrypted,
          e.message,
          part: entry,
        );
      case ZipReadErrorKind.legacyXls:
        return XlsxReadException(
          XlsxReadFailure.legacyXls,
          e.message,
          part: entry,
        );
      case ZipReadErrorKind.tooManyEntries:
        return limit('maxEntries');
      case ZipReadErrorKind.entryTooLarge:
        return limit('maxEntryBytes');
      case ZipReadErrorKind.totalTooLarge:
        return limit('maxTotalBytes');
      case ZipReadErrorKind.ratioTooHigh:
        return limit('maxCompressionRatio');
    }
  }
}
