/// The `[Content_Types].xml` part of a package.
///
/// Ported from quds_office_engine `lib/src/opc/content_types.dart` at commit 15c5d29.
/// Ported: `ContentTypes.setDefault`, `setOverride` and `toXml`, as the write
/// side only (no parsing, no lookup). What changed: the methods are named
/// [ContentTypes.addDefault] and [ContentTypes.addOverride], and the part is
/// written to an `XmlWriter`.
library;

import '../xml/xml_writer.dart';
import 'ooxml.dart';

/// Collects the default and override content types and writes the part.
///
/// Extensions and part names are case-insensitive in OPC, so `xml` and `XML`
/// are the same key here. When case variants are added, the first spelling
/// wins: it is the one written, and a later variant with the same type is
/// ignored.
/// Output is deterministic: defaults are sorted by extension and overrides by
/// part name (plain string order), whatever the order they were added in.
final class ContentTypes {
  // Lower-cased key to the first-given spelling and its type.
  final Map<String, ({String key, String type})> _defaults =
      <String, ({String key, String type})>{};
  final Map<String, ({String key, String type})> _overrides =
      <String, ({String key, String type})>{};

  /// Declares [type] for every part whose name ends in [extension] (without
  /// the dot).
  ///
  /// Adding the same extension again with the same type does nothing. Throws
  /// [ArgumentError] when [extension] is empty or contains a dot, and
  /// [StateError] when the extension already has a different type.
  void addDefault(String extension, String type) {
    if (extension.isEmpty || extension.contains('.')) {
      throw ArgumentError.value(
        extension,
        'extension',
        'Must be non-empty and written without a dot.',
      );
    }
    _add(_defaults, extension, type, 'extension');
  }

  /// Declares [type] for the single part named [partName], an absolute name
  /// such as `/xl/workbook.xml`.
  ///
  /// Adding the same part again with the same type does nothing. Throws
  /// [ArgumentError] when [partName] does not start with `/`, and
  /// [StateError] when the part already has a different type.
  void addOverride(String partName, String type) {
    if (!partName.startsWith('/')) {
      throw ArgumentError.value(
        partName,
        'partName',
        'Must be an absolute part name starting with "/".',
      );
    }
    _add(_overrides, partName, type, 'part');
  }

  /// Writes the whole part, XML declaration included, to [w].
  void write(XmlWriter w) {
    w.declaration();
    w.start('Types');
    w.attribute('xmlns', Ns.contentTypes);
    for (final entry in _sorted(_defaults)) {
      w.start('Default');
      w.attribute('Extension', entry.key);
      w.attribute('ContentType', entry.type);
      w.end();
    }
    for (final entry in _sorted(_overrides)) {
      w.start('Override');
      w.attribute('PartName', entry.key);
      w.attribute('ContentType', entry.type);
      w.end();
    }
    w.end();
  }

  static void _add(
    Map<String, ({String key, String type})> map,
    String key,
    String type,
    String what,
  ) {
    final String folded = key.toLowerCase();
    final known = map[folded];
    if (known == null) {
      map[folded] = (key: key, type: type);
    } else if (known.type.toLowerCase() != type.toLowerCase()) {
      throw StateError(
        'The $what "$key" already has the content type "${known.type}" '
        '(first given as "${known.key}"); cannot give it "$type".',
      );
    }
  }

  static List<({String key, String type})> _sorted(
    Map<String, ({String key, String type})> map,
  ) => map.values.toList()..sort((a, b) => a.key.compareTo(b.key));
}
