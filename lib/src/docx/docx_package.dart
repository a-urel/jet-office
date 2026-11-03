/// Opens an untrusted DOCX file: the DOCX view over `OpcPackage`.
///
/// New in jet_office; not ported from Quds. It follows the XLSX reader's
/// `PackageReader`: the ZIP is opened within limits, every ZIP, XML and
/// package failure becomes a [DocxReadException], and the main document is
/// found through the root relationship wherever it lives. Strict OOXML and
/// a workbook or presentation are refused; a main part of an unexpected or
/// missing content type is read as a Word document with a warning.
library;

import 'dart:typed_data';

import '../common/read_guard.dart';
import '../common/zip_limits.dart';
import '../opc/ooxml.dart' show ContentType, RelType;
import '../opc/package.dart';
import '../xml/xml_pull_reader.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'warnings.dart';

/// The content types of a Word main part (ECMA-376 and MS-DOCX): document,
/// template and their macro-enabled kinds.
const Set<String> _documentTypes = <String>{
  ContentType.wmlDocument,
  ContentType.wmlTemplate,
  ContentType.wmlMacroDocument,
  ContentType.wmlMacroTemplate,
};

/// The main part types of a workbook of any kind, which is refused as XLSX.
const Set<String> _workbookTypes = <String>{
  ContentType.workbook,
  ContentType.smlMacroWorkbook,
  ContentType.smlTemplate,
  ContentType.smlMacroTemplate,
  ContentType.smlBinaryWorkbook,
};

/// The main part types of a presentation of any kind, which is refused as
/// PPTX.
const Set<String> _presentationTypes = <String>{
  ContentType.pmlPresentation,
  ContentType.pmlTemplate,
  ContentType.pmlSlideshow,
  ContentType.pmlMacroPresentation,
  ContentType.pmlMacroTemplate,
  ContentType.pmlMacroSlideshow,
};

/// An opened DOCX package: the ZIP and its main document part.
///
/// Opening reads only the ZIP directory, `[Content_Types].xml` and the
/// root relationships. Every failure is a [DocxReadException]. A part read
/// later can still fail (a damaged entry, XML that breaks halfway), so
/// callers wrap every lazy load, and the reading of what [openXml]
/// returns, in [guard].
final class DocxPackage {
  /// Opens [bytes] within [limits] and finds the main document part,
  /// recording repaired content types in [warnings].
  ///
  /// Throws an [ArgumentError] when a limit is below 1 (see
  /// [DocxReadLimits.check]), and a [DocxReadException] when the file is
  /// not a readable DOCX.
  DocxPackage(
    Uint8List bytes,
    DocxReadLimits limits,
    DocxWarningCollector warnings,
  ) : _limits = _checked(limits),
      _warnings = warnings,
      _package = _open(bytes, limits) {
    final String main = guard('/_rels/.rels', _findMain);
    _main = main;
    _mainContentType = _contentTypeOfMain(main);
  }

  final DocxReadLimits _limits;
  final OpcPackage _package;
  final DocxWarningCollector _warnings;
  // The main part, null only while the constructor looks for it.
  String? _main;
  late final String _mainContentType;

  /// The package underneath, for the document model, which edits and
  /// writes it. Its methods throw `OpcFormatException`; wrap calls that
  /// read in [guard].
  OpcPackage get package => _package;

  /// The main document part's absolute name as the archive spells it, such
  /// as `/word/document.xml`.
  String get mainPart => _main!;

  /// The content type the main part is read as: its declared type when
  /// that is one of the four Word main types, and
  /// [ContentType.wmlDocument] otherwise (a warning says so).
  String get mainContentType => _mainContentType;

  /// The limits the package was opened with.
  DocxReadLimits get limits => _limits;

  /// A pull reader over the XML part [part].
  ///
  /// The part's bytes are inflated, decoded and then dropped. Throws a
  /// [DocxReadException] for a damaged entry or XML that cannot start, and
  /// a [StateError] when there is no such part; check
  /// `package.hasPart` first. Reading from the reader can fail too: do it
  /// inside [guard].
  XmlPullReader openXml(String part) {
    if (!_package.hasPart(part)) {
      throw StateError('The package has no part "$part".');
    }
    return guard(part, () => _package.openXml(part));
  }

  /// Runs [body], turning any ZIP, XML or package failure in it into a
  /// [DocxReadException] that names [part] (an XML failure) or the entry
  /// concerned (a ZIP failure).
  ///
  /// Other exceptions pass through.
  T guard<T>(String part, T Function() body) => guardRead(
    part,
    body,
    (ReadProblem p) => docxReadException(p, _limits, mainPart: _main),
  );

  /// The main part: the first root relationship of the transitional
  /// `officeDocument` type whose target is in the archive.
  String _findMain() {
    String? named;
    for (final OpcRelationship rel in _package.relationshipsOf('')) {
      if (rel.external) continue;
      if (rel.type == RelType.officeDocumentStrict) throw strictDocument();
      if (rel.type != RelType.officeDocument) continue;
      final String target = _package.resolve('', rel.target);
      final String? actual = _package.canonicalPartName(target);
      if (actual != null) return actual;
      named ??= target;
    }
    throw missingDocument(part: named);
  }

  /// The content type [main] is read as, refusing a workbook or a
  /// presentation and warning about any type that is not Word's.
  String _contentTypeOfMain(String main) {
    final String? declared = _package.contentTypeOf(main);
    if (declared == null) {
      _warnings.add(
        DocxWarningCode.contentTypeMissing,
        part: main,
        detail: ContentType.wmlDocument,
      );
      return ContentType.wmlDocument;
    }
    if (_documentTypes.contains(declared)) return declared;
    if (_workbookTypes.contains(declared)) {
      throw workbookNotDocument(main);
    }
    if (_presentationTypes.contains(declared)) {
      throw presentationNotDocument(main);
    }
    _warnings.add(
      DocxWarningCode.mainPartContentTypeUnexpected,
      part: main,
      detail: declared,
    );
    return ContentType.wmlDocument;
  }

  static DocxReadLimits _checked(DocxReadLimits limits) {
    limits.check();
    return limits;
  }

  static OpcPackage _open(Uint8List bytes, DocxReadLimits limits) => guardRead(
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
    (ReadProblem p) => docxReadException(p, limits),
  );
}
