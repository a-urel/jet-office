/// A relationships part (`.rels`).
///
/// Ported from quds_office_engine `lib/src/opc/relationships.dart` at commit 15c5d29.
/// Ported: `RelationshipCollection` and its `toXml`, as the write side only
/// (no parsing, no lookup, no external targets). What changed: ids are
/// assigned by [Relationships.add] as `rId1`, `rId2`, ... in call order, and
/// the part is written to an `XmlWriter`.
library;

import '../xml/xml_writer.dart';
import 'ooxml.dart';

/// Collects the relationships of one source part and writes its `.rels` part.
final class Relationships {
  final List<({String id, String type, String target})> _items =
      <({String id, String type, String target})>[];

  /// Adds a relationship of [type] to [target] and returns its id, `rId1` for
  /// the first call, `rId2` for the second, and so on.
  ///
  /// [target] is written as given, relative to the source part (for example
  /// `worksheets/sheet1.xml`), or to the package root in `_rels/.rels`.
  ///
  /// Throws [ArgumentError] when [type] or [target] is empty; nothing is
  /// added then.
  String add(String type, String target) {
    if (type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'Must not be empty.');
    }
    if (target.isEmpty) {
      throw ArgumentError.value(target, 'target', 'Must not be empty.');
    }
    final String id = 'rId${_items.length + 1}';
    _items.add((id: id, type: type, target: target));
    return id;
  }

  /// Writes the whole part, XML declaration included, to [w].
  void write(XmlWriter w) {
    w.declaration();
    w.start('Relationships');
    w.attribute('xmlns', Ns.packageRel);
    for (final item in _items) {
      w.start('Relationship');
      w.attribute('Id', item.id);
      w.attribute('Type', item.type);
      w.attribute('Target', item.target);
      w.end();
    }
    w.end();
  }
}
