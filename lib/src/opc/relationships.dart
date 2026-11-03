/// A relationships part (`.rels`).
///
/// Ported from quds_office_engine `lib/src/opc/relationships.dart` at commit 15c5d29.
/// Ported: `RelationshipCollection` and its `toXml`. What changed: ids are
/// assigned by [Relationships.add] as `rId1`, `rId2`, ... in call order unless
/// the caller gives one, a relationship can be external (a hyperlink), and the
/// part is written to an `XmlWriter`. New, not from Quds: the read side
/// ([Relationships.parse], [Relationships.items],
/// [Relationships.removeWhere]), which keeps every
/// relationship of a file, whatever its type.
library;

import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'ooxml.dart';

/// One relationship of a source part, as the file states it.
///
/// `target` is not resolved: it is relative to the source part (or absolute
/// when it starts with `/`), or an outside address when `external`.
typedef OpcRelationship = ({
  String id,
  String type,
  String target,
  bool external,
});

/// Collects the relationships of one source part and writes its `.rels` part.
final class Relationships {
  /// An empty collection, for writing a new part.
  Relationships();

  /// Reads a `.rels` part from [reader], keeping every relationship.
  ///
  /// A relationship without `Id`, `Type` or `Target` is skipped. The mode
  /// `External` (in any case) makes it external. Ids are kept as read, even
  /// when a file repeats one. Throws what [reader] throws.
  factory Relationships.parse(XmlPullReader reader) {
    final Relationships rels = Relationships();
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.localName != 'Relationship') {
        continue;
      }
      final String? id = reader.getAttribute('Id');
      final String? type = reader.getAttribute('Type');
      final String? target = reader.getAttribute('Target');
      if (id == null || type == null || target == null) continue;
      final String? mode = reader.getAttribute('TargetMode');
      rels._ids.add(id);
      rels._items.add((
        id: id,
        type: type,
        target: target,
        external: mode != null && mode.toLowerCase() == 'external',
      ));
    }
    return rels;
  }

  final List<OpcRelationship> _items = <OpcRelationship>[];
  final Set<String> _ids = <String>{};

  /// The relationships, in the order they were read or added.
  List<OpcRelationship> get items => List<OpcRelationship>.unmodifiable(_items);

  /// Whether a relationship uses [id].
  bool hasId(String id) => _ids.contains(id);

  /// Removes every relationship for which [test] is true.
  void removeWhere(bool Function(OpcRelationship) test) {
    _items.removeWhere(test);
    _ids
      ..clear()
      ..addAll(_items.map((OpcRelationship r) => r.id));
  }

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
