/// The package of a DOCX document as the document properties read it.
///
/// New in jet_office; not ported from Quds. `PropertiesState` (shared with
/// workbooks, decision 0012's `common/`) asks its host for the package, the
/// bounds on what a part may hold, and a guarded reader; this answers with a
/// [DocxPackage]'s limits and [DocxReadException]s.
library;

import '../common/properties_parts.dart';
import '../opc/package.dart';
import '../xml/xml_pull_reader.dart';
import 'docx_package.dart';
import 'read_exception.dart';

/// A [DocxPackage] as a [PropertiesSource].
final class DocxPropertiesSource implements PropertiesSource {
  /// The properties source of [_package].
  DocxPropertiesSource(this._package);

  final DocxPackage _package;

  @override
  OpcPackage get package => _package.package;

  /// A properties part lists at most as many entries as a part may.
  @override
  int get maxChildren => _package.limits.maxEntries;

  @override
  int get maxTextLength => _package.limits.maxTextLength;

  @override
  T guard<T>(String part, T Function() body) => _package.guard(part, body);

  @override
  XmlPullReader openXml(String part) => _package.openXml(part);

  @override
  Never limitExceeded(String part, String message) => throw DocxReadException(
    DocxReadFailure.limitExceeded,
    message,
    part: part,
  );
}
