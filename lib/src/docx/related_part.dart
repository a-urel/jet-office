/// A part the main document part reaches through a relationship, such as
/// the styles or the numbering part: found when it is there, created at
/// save when it is not.
///
/// Not ported from Quds; written for jet_office.
///
/// [RelatedPart.find] looks at the main part's relationships of one type:
/// external ones are ignored, the first internal one whose target is in the
/// package with the expected content type (and is not the main part
/// itself) is the part, as is one of the generic XML type
/// (`application/xml`, `text/xml`) that no other relationship of the main
/// part targets, and otherwise the first internal one names where
/// the part goes. A document without the part reads it as empty, and
/// [RelatedPart.create] adds it at save, only once it holds something
/// (plan Ruling 7): at the target of a relationship whose part is missing
/// when that target is a legal new part name (`OpcPackage.isNewPartName`),
/// else at the default name with a new relationship, and in both cases with
/// a content type override. Creating at save keeps package edits out of the
/// change log, so an edit rolled back never leaves a part behind.
///
/// A part loaded keeps its bytes until the model says something else: at
/// save, what the model writes is compared with what it wrote when it was
/// read, and when they are the same the file's bytes go out, so a part that
/// was only read loses neither a comment nor a line break (decision 0010).
/// Comparing what is written, rather than tracking edits, covers a set, an
/// added definition and an edit undone alike, whichever member made them.
///
library;

import 'dart:typed_data';

import '../opc/ooxml.dart' show ContentType;
import '../opc/package.dart';
import '../xml/xml_pull_reader.dart';
import 'docx_package.dart';
import 'read_exception.dart';

/// The name of the relationships part of [part], such as
/// `/word/_rels/document.xml.rels` for `/word/document.xml`.
String relationshipsPartOf(String part) {
  final int slash = part.lastIndexOf('/');
  return '${part.substring(0, slash + 1)}_rels/'
      '${part.substring(slash + 1)}.rels';
}

/// The part related to a source part by one relationship type: where it is,
/// or where it goes.
final class RelatedPart {
  RelatedPart._(
    this._package,
    this._source,
    this._relationshipType,
    this._contentType,
    String name, {
    required bool exists,
    required bool related,
  }) : _name = name,
       _exists = exists,
       _related = related;

  /// Finds the part [source] relates to by [relationshipType] in [package]
  /// (see the library documentation); [defaultName] is where it goes when
  /// no relationship names it, and [contentType] its type when it is
  /// created.
  ///
  /// The relationships of [source] are read here: a relationships part that
  /// cannot be read throws a [DocxReadException] naming it.
  factory RelatedPart.find(
    DocxPackage package, {
    required String source,
    required String relationshipType,
    required String defaultName,
    required String contentType,
  }) {
    final OpcPackage opc = package.package;
    final List<OpcRelationship> relationships = package.guard(
      relationshipsPartOf(source),
      () => opc.relationshipsOf(source),
    );
    final String sourceKey = (opc.canonicalPartName(source) ?? source)
        .toLowerCase();
    String? missing;
    for (final OpcRelationship rel in relationships) {
      if (rel.external || rel.type != relationshipType) {
        continue;
      }
      final String target = opc.resolve(source, rel.target);
      final String? actual = opc.canonicalPartName(target);
      if (actual != null) {
        // A part of another type, or the source itself, is not this part:
        // the relationship stays as read and is otherwise ignored. A part
        // of the generic XML type (a producer that wrote no override) is
        // taken when no other relationship of the source targets it.
        final String? type = opc.contentTypeOf(actual);
        final bool generic = type == ContentType.xml || type == 'text/xml';
        if (actual.toLowerCase() == sourceKey ||
            (type != contentType &&
                !(generic &&
                    _onlyTarget(opc, source, relationships, rel, actual)))) {
          continue;
        }
        return RelatedPart._(
          package,
          source,
          relationshipType,
          contentType,
          actual,
          exists: true,
          related: true,
        );
      }
      // A target read from the file is reused only when a part can be
      // created there; otherwise the relationship stays as read and the
      // part goes to the default name with a new relationship.
      // The target as written may name a folder that resolving hides.
      final String written = rel.target.replaceAll(r'\', '/');
      if (!written.endsWith('/') && opc.isNewPartName(target)) {
        missing ??= target;
      }
    }
    return RelatedPart._(
      package,
      source,
      relationshipType,
      contentType,
      missing ?? defaultName,
      exists: false,
      related: missing != null,
    );
  }

  /// The part [name] of [package], found through a relationship the caller
  /// read: a header or footer part, by the id its reference gives. [name] is
  /// the canonical name of a part in the package.
  RelatedPart.named(DocxPackage package, String name)
    : this._(
        package,
        package.mainPart,
        '',
        '',
        name,
        exists: true,
        related: true,
      );

  /// A new header or footer part, not in the package yet, at the free name
  /// [name]: [create] adds it, with a relationship of [relationshipType] from
  /// the main part ([relationshipId]) and [contentType] as its override.
  RelatedPart.added(
    DocxPackage package,
    String name, {
    required String relationshipType,
    required String contentType,
  }) : this._(
         package,
         package.mainPart,
         relationshipType,
         contentType,
         name,
         exists: false,
         related: false,
       );

  final DocxPackage _package;
  final String _source;
  final String _relationshipType;
  final String _contentType;
  String _name;
  bool _exists;
  bool _related;
  String? _relationshipId;

  /// The id of the relationship [create] added, or `null`.
  String? get relationshipId => _relationshipId;

  /// The part's absolute name: where it is, or where [create] puts it.
  String get name => _name;

  /// Whether the part is in the package: found, or created by [create].
  bool get exists => _exists;

  /// Reads the part with [read], inside [DocxPackage.guard], so a failure
  /// of the part's ZIP entry or XML is a [DocxReadException] naming it, as
  /// is any failure to encode what was read, and
  /// gives it the content [read] returns, which the package writes from now
  /// on, as the file's bytes while it writes what it wrote when read. Throws
  /// [StateError] when the part does not [exist][exists].
  T load<T extends PartContent>(T Function(XmlPullReader r) read) {
    if (!_exists) {
      throw StateError('The part "$_name" is not in the package.');
    }
    final DocxPackage package = _package;
    final T content = package.guard(_name, () => read(package.openXml(_name)));
    final String name = _name;
    package.package.setContent(name, _keptUntilChanged(content, name));
    return content;
  }

  /// [content] of the part [name], encoded once to know what it writes as
  /// read. The file decides what that encode meets, so whatever it throws
  /// is a [DocxReadException] naming the part, and the part stays as it
  /// was.
  _KeptUntilChanged _keptUntilChanged(PartContent content, String name) {
    final DocxPackage package = _package;
    try {
      return package.guard(
        name,
        () => _KeptUntilChanged(
          content,
          () => package.package.originalBytes(name),
        ),
      );
    } on DocxReadException {
      rethrow;
    } on Object catch (e) {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The part cannot be written back from what was read: $e',
        part: name,
      );
    }
  }

  /// Adds the part with [content] when it is not in the package yet, with
  /// its content type override and, unless a relationship already names
  /// it, a relationship from the source part. Does nothing when it
  /// [exists].
  ///
  /// When [name] is taken by a part no relationship of this type names,
  /// or by another part created at the same missing target, the part gets
  /// the next free name (`styles2.xml`) and a relationship of its own; a
  /// relationship read keeps its target. A new relationship takes no id of
  /// [reservedIds].
  void create(
    PartContent content, {
    Set<String> reservedIds = const <String>{},
  }) {
    if (_exists) {
      return;
    }
    final OpcPackage opc = _package.package;
    final String added = opc.addPart(_name, _contentType, content);
    // A relationship names the part only where it was created: when the
    // name was taken meanwhile (another part reused the same missing
    // target), the part got the next free name, and the relationship read
    // stays as it was beside a new one.
    if (!_related || added.toLowerCase() != _name.toLowerCase()) {
      _relationshipId = opc.addRelationship(
        _source,
        type: _relationshipType,
        target: relationshipTargetFrom(_source, added),
        reservedIds: reservedIds,
      );
    }
    _name = added;
    _exists = true;
    _related = true;
  }

  /// Whether [part] is targeted by no internal relationship of [source]
  /// in [relationships] other than [rel].
  static bool _onlyTarget(
    OpcPackage opc,
    String source,
    List<OpcRelationship> relationships,
    OpcRelationship rel,
    String part,
  ) {
    final String key = part.toLowerCase();
    for (final OpcRelationship other in relationships) {
      if (identical(other, rel) || other.external) {
        continue;
      }
      final String? target = opc.canonicalPartName(
        opc.resolve(source, other.target),
      );
      if (target != null && target.toLowerCase() == key) {
        return false;
      }
    }
    return true;
  }
}

/// The content of a part read from the file: [_model], or the file's bytes
/// while [_model] writes what it wrote when it was read.
final class _KeptUntilChanged implements PartContent {
  _KeptUntilChanged(this._model, this._original)
    : _asRead = _joined(_model.encode());

  final PartContent _model;

  /// The part's bytes in the file.
  final Uint8List Function() _original;

  /// What [_model] wrote before any edit.
  final Uint8List _asRead;

  @override
  List<Uint8List> encode() {
    final List<Uint8List> written = _model.encode();
    return _same(_joined(written), _asRead)
        ? <Uint8List>[_original()]
        : written;
  }

  static Uint8List _joined(List<Uint8List> chunks) {
    final BytesBuilder out = BytesBuilder(copy: false);
    chunks.forEach(out.add);
    return out.takeBytes();
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// The relationship target of [part] from [source], both part names:
/// relative when [part] is in the folder of [source] or below, absolute
/// otherwise.
String relationshipTargetFrom(String source, String part) {
  final int slash = source.lastIndexOf('/');
  final String folder = source.substring(0, slash + 1);
  final String absolute = part.startsWith('/') ? part : '/$part';
  final String from = folder.startsWith('/') ? folder : '/$folder';
  return absolute.toLowerCase().startsWith(from.toLowerCase())
      ? absolute.substring(from.length)
      : absolute;
}
