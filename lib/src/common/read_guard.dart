/// Maps the ZIP, XML and package failures of an untrusted file to one
/// format-neutral [ReadProblem], shared by every format's reader.
///
/// Moved from `lib/src/xlsx/read/package_reader.dart`, where the mapping
/// built `XlsxReadException`s directly; not ported from Quds. A
/// [ReadProblem] carries the technical cause only; each format writes its
/// own message from `kind` (an XLSX message names Excel, a DOCX
/// one Word) and throws its own exception.
library;

import '../opc/package.dart';
import '../xml/xml_pull_reader.dart';
import '../zip/archive_adapter.dart';

/// Why a file could not be read, independent of the format.
enum ReadProblemKind {
  /// The bytes are not a ZIP archive.
  notZip,

  /// The archive is damaged, or two entry names collide.
  corruptZip,

  /// The file is password protected.
  encrypted,

  /// The file is an OLE compound file: a legacy binary format such as
  /// `.xls` or `.doc`.
  legacyBinary,

  /// An XML part is not well-formed, has a `DOCTYPE` or is not UTF-8.
  malformedXml,

  /// A read limit was exceeded; the problem's `limit` names it.
  limitExceeded,

  /// The package has no part of the name asked for.
  missingPart,
}

/// A failure to read a file, before a format turns it into its exception.
///
/// `kind` is the category. `part` is the ZIP entry or part concerned, or
/// null when it is the file as a whole. `detail` is the technical cause
/// (the `ZipReadError` or `XmlParseException` message), never advice for
/// the user. `limit` is the name of the limit exceeded (`maxEntries`,
/// `maxEntryBytes`, `maxTotalBytes`, `maxCompressionRatio` or `maxDepth`)
/// for [ReadProblemKind.limitExceeded], and null otherwise.
typedef ReadProblem = ({
  ReadProblemKind kind,
  String? part,
  String detail,
  String? limit,
});

/// The problem [e] reports. Its entry names the part; [part] is the
/// fallback when it names none.
ReadProblem mapZipError(ZipReadError e, {String? part}) {
  final String? entry = e.entry ?? part;
  ReadProblem problem(ReadProblemKind kind, [String? limit]) =>
      (kind: kind, part: entry, detail: e.message, limit: limit);
  switch (e.kind) {
    case ZipReadErrorKind.notZip:
      return problem(ReadProblemKind.notZip);
    case ZipReadErrorKind.corrupt:
    case ZipReadErrorKind.duplicateEntry:
      return problem(ReadProblemKind.corruptZip);
    case ZipReadErrorKind.encrypted:
      return problem(ReadProblemKind.encrypted);
    case ZipReadErrorKind.legacyXls:
      return problem(ReadProblemKind.legacyBinary);
    case ZipReadErrorKind.tooManyEntries:
      return problem(ReadProblemKind.limitExceeded, 'maxEntries');
    case ZipReadErrorKind.entryTooLarge:
      return problem(ReadProblemKind.limitExceeded, 'maxEntryBytes');
    case ZipReadErrorKind.totalTooLarge:
      return problem(ReadProblemKind.limitExceeded, 'maxTotalBytes');
    case ZipReadErrorKind.ratioTooHigh:
      return problem(ReadProblemKind.limitExceeded, 'maxCompressionRatio');
  }
}

/// The problem [e] reports about the XML part [part]: XML nested too deep
/// exceeds the limit `maxDepth`; anything else is malformed XML.
ReadProblem mapXmlError(XmlParseException e, String? part) =>
    e.kind == XmlParseKind.tooDeep
    ? (
        kind: ReadProblemKind.limitExceeded,
        part: part,
        detail: e.message,
        limit: 'maxDepth',
      )
    : (
        kind: ReadProblemKind.malformedXml,
        part: part,
        detail: e.message,
        limit: null,
      );

/// The problem a package failure [e] reports.
///
/// A ZIP cause maps through [mapZipError] with the package's part as the
/// fallback, an XML cause through [mapXmlError] naming [xmlPart] (the part
/// as the caller spelled it) or else the package's part, and anything else
/// is [ReadProblemKind.missingPart].
ReadProblem mapPackageError(OpcFormatException e, {String? xmlPart}) {
  final Object? cause = e.cause;
  if (cause is ZipReadError) return mapZipError(cause, part: e.part);
  if (cause is XmlParseException) return mapXmlError(cause, xmlPart ?? e.part);
  return (
    kind: ReadProblemKind.missingPart,
    part: e.part,
    detail: e.toString(),
    limit: null,
  );
}

/// Runs [body] and throws the exception [onProblem] makes of any ZIP, XML
/// or package failure in it.
///
/// An [XmlParseException] names [part]; a [ZipReadError] names the entry it
/// names itself; an [OpcFormatException] maps through [mapPackageError]
/// with [part] as its `xmlPart`. Other exceptions pass through. Use it
/// around opening a package and around reading from an XML part, because
/// some XML errors (a bad entity in character data) only surface while
/// reading.
T guardRead<T>(
  String? part,
  T Function() body,
  Exception Function(ReadProblem problem) onProblem,
) {
  try {
    return body();
  } on XmlParseException catch (e) {
    throw onProblem(mapXmlError(e, part));
  } on ZipReadError catch (e) {
    throw onProblem(mapZipError(e));
  } on OpcFormatException catch (e) {
    throw onProblem(mapPackageError(e, xmlPart: part));
  }
}
