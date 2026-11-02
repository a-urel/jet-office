/// The shared-string table of a workbook (`xl/sharedStrings.xml`).
///
/// Ported from quds_office_engine `lib/src/sheet/shared_strings.dart` at commit 15c5d29.
/// Ported: `SharedStringTable.intern`, `values` and `toXml`, as the write
/// side only (no parsing). What changed: the table counts every reference
/// (`count`) apart from the distinct strings (`uniqueCount`), where Quds
/// wrote the same number for both, `xml:space="preserve"` is written only
/// for text with leading or trailing whitespace, and text that looks like an
/// `_xHHHH_` escape is written escaped so readers show it as given. Added:
/// rich text entries, written as runs.
library;

import '../opc/opaque_xml.dart';
import '../xml/xml_writer.dart';
import 'rich_text.dart';

const String _mainNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// Interns the strings of string cells and writes the `sst` part.
///
/// An entry is plain text or an [XlsxRichText]. Text must already be
/// scrubbed and truncated by the cell encoder, and a rich text cleaned (see
/// [cleanRichText]) with its run fonts resolved. The table keeps and
/// deduplicates entries as given; [writeXml] protects text that looks like
/// an `_xHHHH_` escape with `escapeXstring`. Memory grows with the number
/// of distinct entries, not with the number of cells.
final class SharedStrings {
  /// An empty table.
  SharedStrings();

  /// A table of the entries of an opened workbook, in order.
  ///
  /// Every index is kept, duplicates included, so cells that point into the
  /// table stay valid. [raw] holds by index the `<si>` items that are more
  /// than text (runs, phonetic runs); [writeXml] writes them as given, and
  /// [indexOf] never returns them. [indexOf] returns the first plain entry
  /// with a text, and appends one when there is none. [count] starts at the
  /// number of entries, as the references of the opened cells are unknown.
  SharedStrings.seeded(
    List<String> texts, {
    Map<int, OpaqueXml> raw = const <int, OpaqueXml>{},
  }) {
    for (int i = 0; i < texts.length; i++) {
      _entries.add(texts[i]);
      if (!raw.containsKey(i)) _ids.putIfAbsent(texts[i], () => i);
    }
    _raw.addAll(raw);
    _count = texts.length;
  }

  final Map<int, OpaqueXml> _raw = <int, OpaqueXml>{};

  /// The distinct entries in index order: a `String` or an [XlsxRichText].
  final List<Object> _entries = <Object>[];
  final Map<String, int> _ids = <String, int>{};
  final Map<XlsxRichText, int> _richIds = <XlsxRichText, int>{};
  int _count = 0;

  /// The index of [text], adding it on first use. Every call counts as one
  /// reference in [count].
  int indexOf(String text) {
    _count++;
    return _ids[text] ??= _add(text);
  }

  /// The index of the rich text [text], adding it on first use. Every call
  /// counts as one reference in [count].
  ///
  /// Rich entries are deduplicated by `==`. A rich text of one run without
  /// a font is interned as its plain string, and one without runs (all of
  /// them left empty by [cleanRichText]) as the empty string, as [indexOf]
  /// would, so each shares the `<si>` of that string.
  int indexOfRich(XlsxRichText text) {
    final List<XlsxTextRun> runs = text.runs;
    if (runs.isEmpty) return indexOf('');
    if (runs.length == 1 && runs.single.font == null) {
      return indexOf(runs.single.text);
    }
    _count++;
    return _richIds[text] ??= _add(text);
  }

  int _add(Object entry) {
    _entries.add(entry);
    return _entries.length - 1;
  }

  /// The number of entries, that is, [uniqueCount].
  int get length => _entries.length;

  /// The text of the entry at [index], a rich one as its runs joined.
  ///
  /// Throws a [RangeError] when [index] is not an entry.
  String textAt(int index) {
    RangeError.checkValidIndex(index, _entries, 'index', _entries.length);
    final Object entry = _entries[index];
    return entry is XlsxRichText ? entry.text : entry as String;
  }

  /// The number of references so far, that is, of `t="s"` cells.
  int get count => _count;

  /// The number of distinct entries, that is, of `<si>` items.
  int get uniqueCount => _entries.length;

  /// The text of each distinct entry in index order, a rich entry as its
  /// runs joined. A snapshot: a list that cannot be modified and does not
  /// change when entries are added afterwards.
  List<String> get values => List<String>.unmodifiable(<String>[
    for (final Object entry in _entries)
      entry is XlsxRichText ? entry.text : entry as String,
  ]);

  /// Writes the whole part, XML declaration included, to [w].
  void writeXml(XmlWriter w) {
    w.declaration();
    w.start('sst');
    w.attribute('xmlns', _mainNamespace);
    w.attribute('count', '$_count');
    w.attribute('uniqueCount', '${_entries.length}');
    for (int i = 0; i < _entries.length; i++) {
      final OpaqueXml? kept = _raw[i];
      if (kept != null) {
        kept.writeTo(
          w,
          declaredAbove: const <String, String>{'': _mainNamespace},
        );
        continue;
      }
      final Object entry = _entries[i];
      w.start('si');
      if (entry is XlsxRichText) {
        writeTextRuns(w, entry);
      } else {
        writeTextElement(w, entry as String);
      }
      w.end();
    }
    w.end();
  }
}
