/// The shared-string table of a workbook (`xl/sharedStrings.xml`).
///
/// Ported from quds_office_engine `lib/src/sheet/shared_strings.dart` at commit 15c5d29.
/// Ported: `SharedStringTable.intern`, `values` and `toXml`, as the write
/// side only (no parsing). What changed: the table counts every reference
/// (`count`) apart from the distinct strings (`uniqueCount`), where Quds
/// wrote the same number for both, and `xml:space="preserve"` is written only
/// for text with leading or trailing whitespace.
library;

import '../xml/xml_writer.dart';

const String _mainNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// Interns the strings of string cells and writes the `sst` part.
///
/// Text must already be scrubbed and truncated by the cell encoder. Memory
/// grows with the number of distinct strings, not with the number of cells.
final class SharedStrings {
  final List<String> _values = <String>[];
  final Map<String, int> _ids = <String, int>{};
  int _count = 0;

  /// The index of [text], adding it on first use. Every call counts as one
  /// reference in [count].
  int indexOf(String text) {
    _count++;
    final int? known = _ids[text];
    if (known != null) return known;
    final int id = _values.length;
    _values.add(text);
    _ids[text] = id;
    return id;
  }

  /// The number of references so far, that is, of `t="s"` cells.
  int get count => _count;

  /// The number of distinct strings, that is, of `<si>` items.
  int get uniqueCount => _values.length;

  /// The distinct strings in index order. The list cannot be modified.
  List<String> get values => List<String>.unmodifiable(_values);

  /// Writes the whole part, XML declaration included, to [w].
  void writeXml(XmlWriter w) {
    w.declaration();
    w.start('sst');
    w.attribute('xmlns', _mainNamespace);
    w.attribute('count', '$_count');
    w.attribute('uniqueCount', '${_values.length}');
    for (final String text in _values) {
      w.start('si');
      w.start('t');
      if (_isPadded(text)) w.attribute('xml:space', 'preserve');
      w.text(text);
      w.end();
      w.end();
    }
    w.end();
  }

  static bool _isPadded(String text) {
    if (text.isEmpty) return false;
    return _isSpace(text.codeUnitAt(0)) ||
        _isSpace(text.codeUnitAt(text.length - 1));
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;
}
