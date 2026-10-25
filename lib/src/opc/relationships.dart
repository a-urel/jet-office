/// A relationships part (`.rels`).
///
/// Ported from quds_office_engine `lib/src/opc/relationships.dart` at commit 15c5d29.
/// Ported: `RelationshipCollection` and its `toXml`, as the write side only
/// (no parsing, no lookup). What changed: ids are
/// assigned by [Relationships.add] as `rId1`, `rId2`, ... in call order
/// unless the caller gives one, and the part is written to an `XmlWriter`.
library;

import '../xml/xml_writer.dart';
import 'ooxml.dart';

/// Collects the relationships of one source part and writes its `.rels` part.
final class Relationships {
  final List<({String id, String type, String target, bool external})> _items =
      <({String id, String type, String target, bool external})>[];
  final Set<String> _ids = <String>{};

  /// Adds a relationship of [type] to [target] and returns its id.
  ///
  /// Without [id], the id is the first of `rId1`, `rId2`, ... that no
  /// relationship of this part uses yet, so automatic ids never collide with
  /// explicit ones. With [id], that id is used as given; the caller owns its
  /// meaning, for example a part that another part refers to by id.
  ///
  /// [target] is written as given, relative to the source part (for example
  /// `worksheets/sheet1.xml`), or to the package root in `_rels/.rels`.
  ///
  /// With [external], the relationship is written with
  /// `TargetMode="External"` and [target] is an address outside the package,
  /// such as a URL.
  ///
  /// Throws [ArgumentError] when [type], [target] or [id] is empty, or when
  /// [id] is already in use; nothing is added then.
  String add(String type, String target, {String? id, bool external = false}) {
    if (type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'Must not be empty.');
    }
    if (target.isEmpty) {
      throw ArgumentError.value(target, 'target', 'Must not be empty.');
    }
    String chosen;
    if (id != null) {
      if (id.isEmpty) {
        throw ArgumentError.value(id, 'id', 'Must not be empty.');
      }
      if (_ids.contains(id)) {
        throw ArgumentError.value(id, 'id', 'Is already used.');
      }
      chosen = id;
    } else {
      int n = _items.length + 1;
      while (_ids.contains('rId$n')) {
        n++;
      }
      chosen = 'rId$n';
    }
    _ids.add(chosen);
    _items.add((id: chosen, type: type, target: target, external: external));
    return chosen;
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
      if (item.external) w.attribute('TargetMode', 'External');
      w.end();
    }
    w.end();
  }
}
