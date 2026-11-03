/// The exception the DOCX reader throws for a file it cannot read at all,
/// and the DOCX wording of every failure.
///
/// New in jet_office; not ported from Quds. The ZIP, XML and package
/// failures arrive as a format-neutral `ReadProblem`
/// (`lib/src/common/read_guard.dart`); [docxReadException] words them for
/// a Word user. No message advises `.xls`, `.xlsx` or Excel: the shared
/// detail of a legacy file names `.xls`, so that failure has its own text.
library;

import '../common/read_guard.dart';
import '../xml/xml_pull_reader.dart' show isUnsafeInMessage;
import 'read_limits.dart';

/// Why a [DocxReadException] was thrown.
enum DocxReadFailure {
  /// The bytes are not a ZIP archive.
  notZip,

  /// The ZIP archive is damaged: bad structure, size or CRC, an entry that
  /// cannot be inflated, or two entry names that collide.
  corruptZip,

  /// The file is an encrypted (password protected) Office file.
  encrypted,

  /// The file is a legacy binary Word document (`.doc`), or another OLE
  /// compound file.
  legacyDoc,

  /// The package is a format the reader does not read: Strict OOXML, or a
  /// workbook (XLSX) or presentation (PPTX) instead of a document.
  unsupportedFormat,

  /// The package has no main document part: no root relationship names
  /// one, or the part it names is not in the archive.
  missingDocument,

  /// An XML part is not well-formed, has a `DOCTYPE` or is not UTF-8.
  malformedXml,

  /// A limit of [DocxReadLimits] was exceeded.
  limitExceeded,
}

/// Thrown when a file cannot be read as a DOCX at all.
///
/// A repairable problem in the content is a warning, not this exception.
/// The bytes come from outside the program, so this is a data problem.
final class DocxReadException implements Exception {
  /// Creates an exception of [reason], described by [message], about the
  /// package part [part] (`null` when it concerns the file as a whole).
  ///
  /// [part] is made absolute, shortened and cleaned for display, see
  /// [part].
  DocxReadException(this.reason, this.message, {String? part})
    : part = part == null ? null : _displayPart(part);

  /// The category of the failure.
  final DocxReadFailure reason;

  /// The absolute name of the package part the failure concerns, such as
  /// `/word/document.xml`, or `null`.
  ///
  /// This is for display only. A part name comes from the file, so it is
  /// cut to 256 UTF-16 code units (a surrogate pair is never split)
  /// followed by `…`, and control characters, line and paragraph separators
  /// and bidirectional controls are replaced by U+FFFD.
  final String? part;

  /// An English description for developers and logs. For
  /// [DocxReadFailure.limitExceeded] it names the limit.
  ///
  /// Text taken from the file is quoted short and on one line by the
  /// parser; [part] is not repeated in it.
  final String message;

  @override
  String toString() =>
      'DocxReadException(${reason.name}'
      '${part == null ? '' : ', $part'}): $message';
}

/// The message of [DocxReadFailure.legacyDoc].
const String legacyDocMessage =
    'The file is a legacy Word document (.doc), not a DOCX; save it as a '
    'Word Document (.docx).';

/// The message of [DocxReadFailure.encrypted].
const String encryptedMessage =
    'The file is an encrypted (password protected) Office file.';

/// The failure for a Strict OOXML package.
DocxReadException strictDocument() => DocxReadException(
  DocxReadFailure.unsupportedFormat,
  'The document is Strict OOXML, which is not supported; save it as a Word '
  'Document (.docx).',
);

/// The failure for a package whose main part [part] is a workbook.
///
/// The content type is not quoted: an Excel type would name Excel.
DocxReadException workbookNotDocument(String part) => DocxReadException(
  DocxReadFailure.unsupportedFormat,
  'The file is an XLSX workbook, not a DOCX.',
  part: part,
);

/// The failure for a package whose main part [part] is a presentation.
DocxReadException presentationNotDocument(String part) => DocxReadException(
  DocxReadFailure.unsupportedFormat,
  'The file is a PPTX presentation, not a DOCX.',
  part: part,
);

/// The failure for a package with no main document part; [part] is the
/// part a root relationship names but the archive lacks, if any.
DocxReadException missingDocument({String? part}) => DocxReadException(
  DocxReadFailure.missingDocument,
  part == null
      ? 'The package has no main document part.'
      : 'The main document part named by the package relationships is not '
            'in the archive.',
  part: part,
);

/// The [DocxReadException] for [p], read within [limits].
///
/// A missing part is [DocxReadFailure.missingDocument] when it is
/// [mainPart] (an absolute name, compared without regard to case or a
/// leading `/`), and [DocxReadFailure.malformedXml] otherwise, as for XLSX.
DocxReadException docxReadException(
  ReadProblem p,
  DocxReadLimits limits, {
  String? mainPart,
}) {
  DocxReadException fail(DocxReadFailure reason, String message) =>
      DocxReadException(reason, message, part: p.part);
  return switch (p.kind) {
    ReadProblemKind.notZip => fail(
      DocxReadFailure.notZip,
      'The file is not a DOCX: it is not a ZIP archive.',
    ),
    ReadProblemKind.corruptZip => fail(
      DocxReadFailure.corruptZip,
      'The ZIP archive is damaged: ${p.detail}',
    ),
    ReadProblemKind.encrypted => fail(
      DocxReadFailure.encrypted,
      encryptedMessage,
    ),
    ReadProblemKind.legacyBinary => fail(
      DocxReadFailure.legacyDoc,
      legacyDocMessage,
    ),
    ReadProblemKind.limitExceeded when p.limit == ReadLimit.maxDepth => fail(
      DocxReadFailure.limitExceeded,
      'Limit maxDepth (${limits.maxDepth}) exceeded: ${p.detail}.',
    ),
    ReadProblemKind.limitExceeded => fail(
      DocxReadFailure.limitExceeded,
      'Limit ${p.limit?.name} exceeded: ${p.detail}',
    ),
    ReadProblemKind.malformedXml => fail(
      DocxReadFailure.malformedXml,
      'The XML cannot be read: ${p.detail}.',
    ),
    ReadProblemKind.missingPart
        when mainPart != null && _samePart(p.part, mainPart) =>
      missingDocument(part: mainPart),
    ReadProblemKind.missingPart => fail(
      DocxReadFailure.malformedXml,
      'The package has no such part.',
    ),
  };
}

/// Whether [a] and [b] name the same part: case, a leading `/` and slash
/// direction aside.
bool _samePart(String? a, String b) {
  if (a == null) return false;
  String key(String name) {
    final String slashed = name.replaceAll(r'\', '/');
    return (slashed.startsWith('/') ? slashed.substring(1) : slashed)
        .toLowerCase();
  }

  return key(a) == key(b);
}

/// The most UTF-16 code units of a part name an exception keeps, its
/// leading `/` included.
const int _partLength = 256;

/// [name] with a leading `/`, cut to [_partLength] code units plus `…` and
/// made safe to print.
String _displayPart(String name) {
  final String absolute = name.startsWith('/') ? name : '/$name';
  int end = absolute.length;
  bool cut = false;
  if (end > _partLength) {
    end = _partLength;
    final int last = absolute.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    cut = true;
  }
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < end; i++) {
    final int ch = absolute.codeUnitAt(i);
    out.writeCharCode(isUnsafeInMessage(ch) ? 0xFFFD : ch);
  }
  if (cut) out.write('…');
  return out.toString();
}
