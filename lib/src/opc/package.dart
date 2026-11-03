/// A format-neutral Open Packaging Conventions package: parts, content types
/// and relationships.
///
/// Not ported from Quds; written for jet_office.
///
/// `OpcPackage.read` opens a ZIP and reads only `[Content_Types].xml`;
/// everything else is loaded on demand. A part keeps its original bytes until
/// a model replaces them with `setContent`, so a package that is
/// read and written again carries every part the library does not understand,
/// byte for byte. `[Content_Types].xml` and the `.rels` parts are package
/// metadata, not parts: they are not in `partNames` and
/// `writeTo` always writes them from the model, with the unknown
/// defaults, overrides and relationships kept.
///
/// Part names are absolute (`/xl/workbook.xml`) and matched without regard to
/// case or slash direction. Nothing here knows about spreadsheets, and
/// nothing under `lib/src/opc` imports `lib/src/xlsx`.
library;

import 'dart:typed_data';

import '../xml/utf8_buffer.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import '../zip/archive_adapter.dart';
import 'content_types.dart';
import 'relationships.dart';

export 'relationships.dart' show OpcRelationship;

const String _contentTypesPart = '[Content_Types].xml';

/// What a model gives a part to be written: its XML or other content as
/// UTF-8 chunks.
abstract interface class PartContent {
  /// The part's bytes as UTF-8 chunks, in order. The chunks are written
  /// back to back, so they may split anywhere.
  List<Uint8List> encode();
}

/// The kinds of failure of an [OpcFormatException].
enum OpcFormatKind {
  /// The ZIP entry cannot be read; [OpcFormatException.cause] is the
  /// `ZipReadError`.
  zip,

  /// A package XML part cannot be read; [OpcFormatException.cause] is the
  /// `XmlParseException`.
  xml,

  /// There is no such part.
  missingPart,
}

/// A package could not be read.
///
/// It is the only exception [OpcPackage] throws for what a file contains.
final class OpcFormatException implements Exception {
  /// Creates an exception of [kind] about [part], caused by [cause].
  const OpcFormatException(this.kind, {this.part, this.cause});

  /// What went wrong.
  final OpcFormatKind kind;

  /// The ZIP entry name concerned, without a leading `/`, when known.
  final String? part;

  /// The underlying `ZipReadError` or `XmlParseException`, when there is
  /// one.
  final Object? cause;

  @override
  String toString() =>
      'OpcFormatException(${kind.name}'
      '${part == null ? '' : ', $part'}'
      '${cause == null ? '' : ': $cause'})';
}

/// One part of the package.
final class _Part {
  _Part(this.name, this.zipName);

  /// The absolute name, as stored or as added.
  final String name;

  /// The ZIP entry name when the part came from the file, else `null`.
  final String? zipName;

  PartContent? content;
}

/// An OPC package held in memory.
///
/// Parts load lazily; see the library documentation. Methods that take a part
/// name accept it with or without a leading `/` and with `\` for `/`.
final class OpcPackage {
  OpcPackage._(this._zip, this._maxDepth, this._contentTypes) {
    if (_zip != null) {
      for (final String name in _zip.names) {
        final String key = _key(name);
        if (key == _contentTypesPart.toLowerCase()) continue;
        final String? source = _sourceOfRels(name);
        if (source != null) {
          _relsEntries[_key(source)] = name;
          continue;
        }
        _parts[key] = _Part('/${_plain(name)}', name);
      }
    }
  }

  /// Opens [zip], reading `[Content_Types].xml` (a missing one is read as
  /// empty).
  ///
  /// XML deeper than [maxDepth] is refused. Throws an [OpcFormatException]
  /// when the content types part cannot be read.
  factory OpcPackage.read(ZipReader zip, {required int maxDepth}) {
    ContentTypes types = ContentTypes();
    if (zip.contains(_contentTypesPart)) {
      final Uint8List bytes = _readEntry(zip, _contentTypesPart);
      types = _parseXml(
        _contentTypesPart,
        () => ContentTypes.parse(_pull(bytes, maxDepth)),
      );
    }
    return OpcPackage._(zip, maxDepth, types);
  }

  /// A package with no parts, for writing a new one.
  factory OpcPackage.empty() => OpcPackage._(null, 256, ContentTypes());

  final ZipReader? _zip;
  final int _maxDepth;
  final ContentTypes _contentTypes;
  final Map<String, _Part> _parts = <String, _Part>{};
  // Lower-cased source part name (no slash, '' for the package) to the ZIP
  // entry of its relationships, for entries not parsed yet.
  final Map<String, String> _relsEntries = <String, String>{};
  // Parsed or created relationships by the same key, in first-use order.
  final Map<String, ({String source, Relationships rels, bool fromInput})>
  _rels = <String, ({String source, Relationships rels, bool fromInput})>{};

  /// The names of the parts, in original ZIP order, then added parts in the
  /// order they were added. Absolute, as stored.
  Iterable<String> get partNames => _parts.values.map((_Part p) => p.name);

  /// The lower-cased absolute names that have a content type override, in
  /// file order. A name need not belong to a part.
  Iterable<String> get overridePartNames => _contentTypes.overrideNames;

  /// Whether the package has a part named [name].
  bool hasPart(String name) => _parts.containsKey(_key(name));

  /// The part's name spelled as stored, or `null` when there is no such part.
  String? canonicalPartName(String name) => _parts[_key(name)]?.name;

  /// The content type of the part [name]: its override, else the default for
  /// its extension, else `null`.
  String? contentTypeOf(String name) => _contentTypes.typeOf(name);

  /// Whether a model gave the part its content ([setContent] or [addPart]).
  ///
  /// False for an unknown name and for package metadata.
  bool isLoaded(String name) => _parts[_key(name)]?.content != null;

  /// The part's original bytes from the file: inflated, CRC-checked and not
  /// cached, so each call inflates again.
  ///
  /// Throws an [OpcFormatException] of kind `missingPart` for an unknown
  /// part or one that was added, and of kind `zip` for a corrupt entry.
  Uint8List originalBytes(String name) {
    final String? zipName = _parts[_key(name)]?.zipName;
    if (zipName == null) {
      throw OpcFormatException(
        OpcFormatKind.missingPart,
        part: _key(name).isEmpty ? null : _plain(name),
      );
    }
    return _readEntry(_zip!, zipName);
  }

  /// A pull reader over the part [name], from its content when a model set
  /// it, else from its original bytes.
  ///
  /// Throws an [OpcFormatException] for an unknown part, a corrupt entry or
  /// XML that cannot start. XML errors that only surface while reading are
  /// [XmlParseException]s from the returned reader.
  XmlPullReader openXml(String name) {
    final _Part? part = _parts[_key(name)];
    if (part == null) {
      throw OpcFormatException(OpcFormatKind.missingPart, part: _plain(name));
    }
    final PartContent? content = part.content;
    final Uint8List bytes;
    if (content == null) {
      bytes = _readEntry(_zip!, part.zipName!);
    } else {
      final BytesBuilder builder = BytesBuilder(copy: false);
      content.encode().forEach(builder.add);
      bytes = builder.takeBytes();
    }
    return _parseXml(_plain(name), () => _pull(bytes, _maxDepth));
  }

  /// The relationships of [source], in file order, external ones included.
  ///
  /// [source] is a part name, or `''` for the package root. A part without a
  /// relationships part has none. Targets are as the file states them; see
  /// [resolve]. Throws an [OpcFormatException] when the relationships part
  /// cannot be read.
  List<OpcRelationship> relationshipsOf(String source) {
    final Relationships? rels = _relsOf(source, create: false);
    return rels == null ? const <OpcRelationship>[] : rels.items;
  }

  /// The absolute part name that [target], a relationship target of
  /// [source], points at.
  ///
  /// A target starting with `/` is from the package root; otherwise it is
  /// relative to the folder of [source] (`''` is the package root). `.` and
  /// `..` are applied, `\` is read as `/`, and a result that names no part is
  /// retried percent-decoded. When neither names a part, the literal result
  /// is returned. The spelling is the target's, not the part's; use
  /// [canonicalPartName] for that.
  String resolve(String source, String target) {
    final String name = _plain(source);
    final int slash = name.lastIndexOf('/');
    final String folder = slash < 0 ? '' : name.substring(0, slash + 1);
    final String slashed = target.replaceAll(r'\', '/');
    final String joined = slashed.startsWith('/') ? slashed : '$folder$slashed';
    final String resolved = _applySegments(joined);
    if (_parts.containsKey(resolved.toLowerCase())) return '/$resolved';
    try {
      final String decoded = _applySegments(Uri.decodeFull(joined));
      if (_parts.containsKey(decoded.toLowerCase())) return '/$decoded';
    } on ArgumentError {
      // Not valid percent-encoding: keep the literal name.
    } on FormatException {
      // The escapes do not decode to UTF-8: keep the literal name.
    }
    return '/$resolved';
  }

  /// Gives the existing part [name] new content, which is written instead of
  /// its original bytes. The part is loaded from now on.
  ///
  /// Throws [ArgumentError] when there is no such part.
  void setContent(String name, PartContent content) {
    final _Part? part = _parts[_key(name)];
    if (part == null) {
      throw ArgumentError.value(name, 'name', 'The package has no such part.');
    }
    part.content = content;
  }

  /// Whether [name] can name a new part as given: it names no part yet, is
  /// not a folder (empty, or ending with `/`), is neither
  /// `[Content_Types].xml` nor a relationships part (`_rels/….rels`), no
  /// part lives under it (`/word` while `/word/document.xml` exists), and it
  /// does not live under a part. Names are compared without regard to case
  /// or slash direction. A name holding `%` is refused, since it may be
  /// percent-encoded (`%5BContent_Types%5D.xml`).
  ///
  /// A relationship target read from a file is untrusted: check it with
  /// this before [addPart] creates a part at it, since [addPart] throws on
  /// package metadata and a name that is a prefix of another part's makes
  /// an invalid package.
  bool isNewPartName(String name) {
    final String slashed = name.replaceAll(r'\', '/');
    final String plain = _plain(slashed);
    if (plain.isEmpty ||
        slashed.endsWith('/') ||
        plain.contains('%') ||
        plain.toLowerCase() == _contentTypesPart.toLowerCase() ||
        _sourceOfRels(plain) != null) {
      return false;
    }
    final String key = plain.toLowerCase();
    if (_parts.containsKey(key)) {
      return false;
    }
    final String below = '$key/';
    for (final String other in _parts.keys) {
      if (other.startsWith(below) || key.startsWith('$other/')) {
        return false;
      }
    }
    return true;
  }

  /// Adds a part of [contentType] with [content] and returns its name.
  ///
  /// When [preferredName] is taken, its number is raised until the name is
  /// free: `/xl/worksheets/sheet3.xml` becomes `sheet4.xml`, and a name
  /// without a number gets `2`, `3` and so on. Names are compared without
  /// regard to case. The content type is declared as an override.
  ///
  /// Throws [ArgumentError] when [preferredName] is empty, names a folder, or
  /// is `[Content_Types].xml` or a relationships part.
  String addPart(
    String preferredName,
    String contentType,
    PartContent content,
  ) {
    final String plain = _plain(preferredName);
    if (plain.isEmpty ||
        plain.endsWith('/') ||
        plain.toLowerCase() == _contentTypesPart.toLowerCase() ||
        _sourceOfRels(plain) != null) {
      throw ArgumentError.value(
        preferredName,
        'preferredName',
        'Must name a part, not a folder or package metadata.',
      );
    }
    String name = plain;
    if (_parts.containsKey(name.toLowerCase())) {
      final int slash = name.lastIndexOf('/') + 1;
      final int dot = name.lastIndexOf('.');
      final int end = dot > slash ? dot : name.length;
      int digits = end;
      while (digits > slash && _isDigit(name.codeUnitAt(digits - 1))) {
        digits--;
      }
      final String stem = name.substring(0, digits);
      final String ext = name.substring(end);
      int n = digits == end ? 2 : int.parse(name.substring(digits, end)) + 1;
      while (_parts.containsKey('$stem$n$ext'.toLowerCase())) {
        n++;
      }
      name = '$stem$n$ext';
    }
    final _Part part = _Part('/$name', null)..content = content;
    _parts[name.toLowerCase()] = part;
    _contentTypes.replaceOverride(part.name, contentType);
    return part.name;
  }

  /// Adds a relationship to [source] (a part name, or `''` for the package
  /// root) and returns its id: `rId<n>` with the lowest free `n`.
  ///
  /// [target] is written as given, relative to [source] or absolute. With
  /// [external] it is an outside address. Throws [ArgumentError] when
  /// [source] is neither `''` nor a part, or [type] or [target] is empty, and
  /// an [OpcFormatException] when the existing relationships cannot be read.
  String addRelationship(
    String source, {
    required String type,
    required String target,
    bool external = false,
  }) {
    if (_key(source).isNotEmpty && !hasPart(source)) {
      throw ArgumentError.value(
        source,
        'source',
        'The package has no such part.',
      );
    }
    final Relationships rels = _relsOf(source, create: true)!;
    int n = 1;
    while (rels.hasId('rId$n')) {
      n++;
    }
    return rels.add(type, target, id: 'rId$n', external: external);
  }

  /// Removes the part [name], its content type override, its own
  /// relationships and every relationship that targets it. An unknown name
  /// does nothing.
  ///
  /// Without [sources] it reads every relationships part of the package, so
  /// it throws an [OpcFormatException] when one cannot be read. With
  /// [sources] (part names, `''` for the package root) only the
  /// relationships of those sources are read and searched; the caller
  /// vouches that no other part refers to [name], and every other
  /// relationships part stays as it was, an unread one byte for byte.
  void removePart(String name, {Iterable<String>? sources}) {
    final String key = _key(name);
    final _Part? part = _parts[key];
    if (part == null) return;
    final List<String> sourceKeys = sources == null
        ? <String>{..._relsEntries.keys, ..._rels.keys}.toList()
        : <String>[
            for (final String source in sources)
              if (_relsEntries.containsKey(_key(source)) ||
                  _rels.containsKey(_key(source)))
                _key(source),
          ];
    for (final String sourceKey in sourceKeys) {
      // The part's own relationships go with it; never parse them.
      if (sourceKey == key) continue;
      final String source = _sourceName(sourceKey);
      _relsOf(source, create: false)!.removeWhere(
        (OpcRelationship r) =>
            !r.external && _key(resolve(source, r.target)) == key,
      );
    }
    _parts.remove(key);
    _contentTypes.removeOverride(part.name);
    _rels.remove(key);
    _relsEntries.remove(key);
  }

  /// Checks that every entry of the input archive can be read (declared
  /// size and CRC-32), parsing and keeping nothing, so that [writeTo] cannot
  /// fail on a part never loaded. A package without input has nothing to
  /// check.
  ///
  /// Throws an [OpcFormatException] of kind [OpcFormatKind.zip] naming the
  /// first damaged entry.
  void verifyEntries() {
    final ZipReader? zip = _zip;
    if (zip == null) return;
    try {
      zip.verifyEntries();
    } on ZipReadError catch (e) {
      throw OpcFormatException(OpcFormatKind.zip, part: e.entry, cause: e);
    }
  }

  /// Writes the package to [zip]: `[Content_Types].xml`, the relationships
  /// parts, then every part in [partNames] order,
  /// from its content when a model set it, else from its original bytes.
  ///
  /// A relationships part of the input that was never parsed is copied from
  /// its original bytes, so a malformed one does not stop the write. Throws
  /// an [OpcFormatException] when an entry cannot be read. The archive is
  /// incomplete then; abandon it.
  void writeTo(ZipWriter zip) {
    final Utf8Buffer types = Utf8Buffer();
    _contentTypes.write(XmlWriter(types));
    zip.addChunks(_contentTypesPart, types.takeChunks());

    // Package relationships first, then the rest. An input part never
    // parsed is copied from its bytes; a parsed or new one is written from
    // the model (an input one even when empty, a new empty one not at all).
    final List<String> all = <String>[..._relsEntries.keys, ..._rels.keys];
    final List<String> keys = <String>[
      ...all.where((String k) => k.isEmpty),
      ...all.where((String k) => k.isNotEmpty),
    ];
    for (final String key in keys) {
      final String? pending = _relsEntries[key];
      if (pending != null) {
        zip.add(pending, _readEntry(_zip!, pending));
        continue;
      }
      final entry = _rels[key]!;
      if (entry.rels.items.isEmpty && !entry.fromInput) continue;
      final Utf8Buffer out = Utf8Buffer();
      entry.rels.write(XmlWriter(out));
      zip.addChunks(_relsName(entry.source), out.takeChunks());
    }

    for (final _Part part in _parts.values) {
      final String entry = part.name.substring(1);
      final PartContent? content = part.content;
      if (content != null) {
        zip.addChunks(entry, content.encode());
      } else {
        zip.add(entry, _readEntry(_zip!, part.zipName!));
      }
    }
  }

  /// The relationships of [source], parsed on first use.
  Relationships? _relsOf(String source, {required bool create}) {
    final String plain = _plain(source);
    final String key = plain.toLowerCase();
    final known = _rels[key];
    if (known != null) return known.rels;
    final String? entry = _relsEntries[key];
    Relationships? rels;
    if (entry != null) {
      final Uint8List bytes = _readEntry(_zip!, entry);
      rels = _parseXml(
        _relsName(plain),
        () => Relationships.parse(_pull(bytes, _maxDepth)),
      );
      _relsEntries.remove(key);
    } else if (create) {
      rels = Relationships();
    }
    if (rels != null) {
      _rels[key] = (source: plain, rels: rels, fromInput: entry != null);
    }
    return rels;
  }

  /// The source part name (no slash) for the lower-cased [key], from the
  /// parsed or pending relationships.
  String _sourceName(String key) {
    final known = _rels[key];
    if (known != null) return known.source;
    final String entry = _relsEntries[key]!;
    return _sourceOfRels(entry)!;
  }

  static String _relsName(String source) {
    final int slash = source.lastIndexOf('/');
    final String folder = slash < 0 ? '' : source.substring(0, slash + 1);
    final String name = slash < 0 ? source : source.substring(slash + 1);
    return '${folder}_rels/$name.rels';
  }

  /// The source part of a relationships entry name (`''` for the package),
  /// or `null` when [name] is not `<folder>/_rels/<name>.rels`.
  static String? _sourceOfRels(String name) {
    final String plain = _plain(name);
    if (!plain.toLowerCase().endsWith('.rels')) return null;
    final int slash = plain.lastIndexOf('/');
    final String folder = slash < 0 ? '' : plain.substring(0, slash);
    final String file = plain.substring(slash + 1, plain.length - 5);
    final int up = folder.lastIndexOf('/');
    final String last = up < 0 ? folder : folder.substring(up + 1);
    if (last.toLowerCase() != '_rels') return null;
    final String parent = up < 0 ? '' : folder.substring(0, up + 1);
    return '$parent$file';
  }

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// [name] with `/` separators and no leading `/`.
  static String _plain(String name) =>
      name.replaceAll(r'\', '/').replaceFirst(RegExp('^/+'), '');

  static String _key(String name) => _plain(name).toLowerCase();

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

  static XmlPullReader _pull(Uint8List bytes, int maxDepth) =>
      XmlPullReader.fromBytes(bytes, maxDepth: maxDepth);

  static Uint8List _readEntry(ZipReader zip, String name) {
    try {
      return zip.read(name);
    } on ZipReadError catch (e) {
      throw OpcFormatException(OpcFormatKind.zip, part: name, cause: e);
    }
  }

  static T _parseXml<T>(String part, T Function() body) {
    try {
      return body();
    } on XmlParseException catch (e) {
      throw OpcFormatException(OpcFormatKind.xml, part: part, cause: e);
    }
  }
}
