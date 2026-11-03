/// Opens an untrusted XLSX file: the XLSX view over `OpcPackage`.
///
/// Ported from quds_office_engine `lib/src/opc/content_types.dart` and
/// `lib/src/opc/relationships.dart` at commit 15c5d29, read side only:
/// `ContentTypes.parse`, `contentTypeFor`, `RelationshipCollection.parse` and
/// `resolve`. Those now live in `lib/src/opc/package.dart` and the classes
/// beside it, which hold no spreadsheet knowledge.
///
/// What changed: the ZIP is opened with limits through `ZipReader`; every
/// ZIP and XML failure becomes an [XlsxReadException]; the workbook part is
/// found through the root relationship, wherever it lives, with the content
/// type override as a fallback; Strict OOXML and `.xlsb` are refused;
/// targets are resolved against the source part with `.` and `..` applied,
/// retried percent-decoded, and part names are matched without regard to
/// case or slash direction.
///
/// The ZIP, XML and package failures are mapped to a format-neutral
/// `ReadProblem` by `lib/src/common/read_guard.dart`; this file turns it
/// into an [XlsxReadException] with the XLSX messages.
///
/// @docImport '../../zip/archive_adapter.dart';
library;

import 'dart:typed_data';

import '../../common/read_guard.dart';
import '../../common/zip_limits.dart';
import '../../opc/ooxml.dart' show RelType;
import '../../opc/package.dart';
import '../../xml/xml_pull_reader.dart';
import 'read_exception.dart';
import 'read_limits.dart';

const String _officeDocumentType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'officeDocument';
const String _xlsbType =
    'application/vnd.ms-excel.sheet.binary.macroEnabled.main';
const List<String> _workbookTypes = <String>[
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
  'application/vnd.ms-excel.sheet.macroEnabled.main+xml',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.template.main'
      '+xml',
];

/// The SpreadsheetML main namespace of Strict OOXML, which is not read.
const String strictSpreadsheetNs =
    'http://purl.oclc.org/ooxml/spreadsheetml/main';

/// The failure for a Strict OOXML package, or for its part [part].
XlsxReadException strictUnsupported({String? part}) => XlsxReadException(
  XlsxReadFailure.unsupportedFormat,
  'The workbook is Strict OOXML, which is not supported; save it as an '
  'Excel Workbook (.xlsx).',
  part: part,
);

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

/// An opened XLSX package: the ZIP, its workbook part and its relationships.
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
      _package = _open(bytes, limits) {
    workbookPart = _findWorkbook();
  }

  final XlsxReadLimits _limits;
  final OpcPackage _package;

  /// The workbook part name, normalized: no leading `/`.
  late final String workbookPart;

  /// The limits the package was opened with.
  XlsxReadLimits get limits => _limits;

  /// The package underneath, for the workbook model, which edits and writes
  /// it. Its methods throw `OpcFormatException`; wrap calls that read in
  /// [guardXml].
  OpcPackage get package => _package;

  /// The internal relationships of [part], in file order.
  ///
  /// External targets are left out. A part without a relationships part has
  /// none. Throws an [XlsxReadException] when the relationships part is not
  /// readable XML.
  List<PartRelationship> relationshipsOf(String part) {
    final List<OpcRelationship> all = _guard(
      null,
      () => _package.relationshipsOf(part),
    );
    return <PartRelationship>[
      for (final OpcRelationship r in all)
        if (!r.external)
          PartRelationship(
            r.id,
            r.type,
            _strip(_package.resolve(part, r.target)),
          ),
    ];
  }

  /// Whether the package holds a part named [part], matched without regard
  /// to case or slash direction.
  bool hasPart(String part) => _package.hasPart(part);

  /// A pull reader over the XML part [part].
  ///
  /// The part's bytes are inflated, decoded and then dropped. Throws an
  /// [XlsxReadException] for a corrupt entry or XML that cannot start, and a
  /// [StateError] when there is no such part; check [hasPart] first.
  XmlPullReader openXml(String part) {
    if (!_package.hasPart(part)) {
      throw StateError('The package has no part "$part".');
    }
    return guardXml(part, () => _package.openXml(part));
  }

  /// Checks that every entry of the file can be read, as `ZipReader.read`
  /// checks one: the declared size and the CRC-32. Nothing is parsed or
  /// kept. The workbook model calls it from `open`, so saving cannot meet a
  /// damaged part it never loaded.
  ///
  /// Throws an [XlsxReadException] of [XlsxReadFailure.corruptZip] naming
  /// the first damaged entry.
  void verifyEntries() => _guard(null, _package.verifyEntries);

  /// Runs [body], mapping an [XmlParseException] or [ZipReadError] to an
  /// [XlsxReadException] that names [part].
  ///
  /// Use it around reading from the reader [openXml] returns.
  T guardXml<T>(String part, T Function() body) => _guard(part, body);

  T _guard<T>(String? part, T Function() body) =>
      guardRead(part, body, (ReadProblem p) => _exception(p, _limits));

  String _findWorkbook() {
    String? found;
    for (final PartRelationship rel in relationshipsOf('')) {
      if (rel.type == RelType.officeDocumentStrict) {
        throw strictUnsupported();
      }
      if (rel.type == _officeDocumentType && hasPart(rel.target)) {
        found = rel.target;
        break;
      }
    }
    if (found == null) {
      for (final String name in _package.overridePartNames) {
        final String? actual = _package.canonicalPartName(name);
        if (actual == null) continue;
        if (_workbookTypes.contains(_package.contentTypeOf(actual))) {
          found = _strip(actual);
          break;
        }
      }
    }
    if (found == null) {
      throw XlsxReadException(
        XlsxReadFailure.missingWorkbook,
        'The package has no workbook part.',
      );
    }
    if ((_package.contentTypeOf(found) ?? 'application/octet-stream') ==
        _xlsbType) {
      throw XlsxReadException(
        XlsxReadFailure.unsupportedFormat,
        'The workbook is a binary .xlsb file, which is not supported; save '
        'it as an Excel Workbook (.xlsx).',
      );
    }
    return found;
  }

  /// [name] without its leading `/`.
  static String _strip(String name) =>
      name.startsWith('/') ? name.substring(1) : name;

  static OpcPackage _open(Uint8List bytes, XlsxReadLimits limits) => guardRead(
    null,
    () => OpcPackage.read(
      openZip(bytes, (
        maxEntries: limits.maxEntries,
        maxEntryBytes: limits.maxEntryBytes,
        maxTotalBytes: limits.maxTotalBytes,
        maxCompressionRatio: limits.maxCompressionRatio,
      )),
      maxDepth: limits.maxDepth,
    ),
    (ReadProblem p) => _exception(p, limits),
  );

  /// The [XlsxReadException] for [p]: its messages name the XLSX limits
  /// and are exactly those the reader gave before the mapping moved to
  /// `lib/src/common`.
  static XlsxReadException _exception(ReadProblem p, XlsxReadLimits limits) {
    XlsxReadException fail(XlsxReadFailure reason, String message) =>
        XlsxReadException(reason, message, part: p.part);
    return switch (p.kind) {
      ReadProblemKind.notZip => fail(XlsxReadFailure.notZip, p.detail),
      ReadProblemKind.corruptZip => fail(XlsxReadFailure.corruptZip, p.detail),
      ReadProblemKind.encrypted => fail(XlsxReadFailure.encrypted, p.detail),
      ReadProblemKind.legacyBinary => fail(XlsxReadFailure.legacyXls, p.detail),
      ReadProblemKind.limitExceeded when p.limit == ReadLimit.maxDepth => fail(
        XlsxReadFailure.limitExceeded,
        'Limit maxDepth (${limits.maxDepth}) exceeded: ${p.detail}.',
      ),
      ReadProblemKind.limitExceeded => fail(
        XlsxReadFailure.limitExceeded,
        'Limit ${p.limit?.name} exceeded: ${p.detail}',
      ),
      ReadProblemKind.malformedXml => fail(
        XlsxReadFailure.malformedXml,
        'The XML cannot be read: ${p.detail}.',
      ),
      ReadProblemKind.missingPart => fail(
        XlsxReadFailure.malformedXml,
        'The package has no such part.',
      ),
    };
  }
}
