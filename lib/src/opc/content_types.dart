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
/// Output is deterministic: defaults are sorted by extension and overrides by
/// part name (plain string order), whatever the order they were added in.
final class ContentTypes {
  final Map<String, String> _defaults = <String, String>{};
  final Map<String, String> _overrides = <String, String>{};

  /// Declares [type] for every part whose name ends in [extension] (without
  /// the dot). A later call for the same extension replaces the earlier one.
  void addDefault(String extension, String type) {
    _defaults[extension] = type;
  }

  /// Declares [type] for the single part named [partName], an absolute name
  /// such as `/xl/workbook.xml`. A later call for the same name replaces the
  /// earlier one.
  void addOverride(String partName, String type) {
    _overrides[partName] = type;
  }

  /// Writes the whole part, XML declaration included, to [w].
  void write(XmlWriter w) {
    w.declaration();
    w.start('Types');
    w.attribute('xmlns', Ns.contentTypes);
    for (final String extension in _sortedKeys(_defaults)) {
      w.start('Default');
      w.attribute('Extension', extension);
      w.attribute('ContentType', _defaults[extension]!);
      w.end();
    }
    for (final String partName in _sortedKeys(_overrides)) {
      w.start('Override');
      w.attribute('PartName', partName);
      w.attribute('ContentType', _overrides[partName]!);
      w.end();
    }
    w.end();
  }

  static List<String> _sortedKeys(Map<String, String> map) =>
      map.keys.toList()..sort();
}
