/// Rich text: cell text in runs, each run with its own font.
///
/// New in jet_office; quds_office_engine has no rich text writer.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'font.dart';
import 'limits.dart';

/// One run of an [XlsxRichText]: a piece of text and its font.
///
/// A run without a [font] shows the font of the cell it is in. A run with a
/// font shows that font merged over the cell's font (see [XlsxFont.merge]):
/// a field the run's font sets wins, one it leaves `null` is the cell's.
/// The `const` constructor cannot check the font; the writer does, when the
/// cell is written.
final class XlsxTextRun {
  /// Creates a run of [text], in [font] when given.
  const XlsxTextRun(this.text, {this.font});

  /// The text of the run.
  final String text;

  /// The font of the run, merged over the cell's font, or `null` for the
  /// cell's font.
  final XlsxFont? font;

  @override
  bool operator ==(Object other) =>
      other is XlsxTextRun && other.text == text && other.font == font;

  @override
  int get hashCode => Object.hash(text, font);

  @override
  String toString() => 'XlsxTextRun($text, font: $font)';
}

/// Text in runs that each have their own font, a cell value.
///
/// For example a bold label and a plain number in one cell:
///
/// ```dart
/// XlsxRichText([
///   XlsxTextRun('Total: ', font: XlsxFont(bold: true)),
///   XlsxTextRun('42'),
/// ])
/// ```
///
/// A cell shows the runs one after another; [text] is what they read
/// together. The writer refuses a rich text without runs, and it treats the
/// text of the runs as data, like a plain string: characters XML forbids
/// are removed and text past 32,767 UTF-16 code units is cut, with
/// warnings. A run with no text, as given or after that, is left out
/// without a warning, and a rich text left with no runs is written as the
/// empty string.
final class XlsxRichText {
  /// Creates a rich text of [runs], holding an unmodifiable copy of the
  /// list.
  XlsxRichText(List<XlsxTextRun> runs)
    : runs = List<XlsxTextRun>.unmodifiable(runs);

  /// The runs, in reading order.
  final List<XlsxTextRun> runs;

  /// The text of the runs joined, as the cell reads.
  String get text => runs.map((XlsxTextRun run) => run.text).join();

  @override
  bool operator ==(Object other) {
    if (other is! XlsxRichText || other.runs.length != runs.length) {
      return false;
    }
    for (int i = 0; i < runs.length; i++) {
      if (other.runs[i] != runs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'XlsxRichText($runs)';
}

/// [text] made fit for a cell: the characters XML forbids removed from each
/// run, the whole cut to [XlsxLimits.maxCellTextLength] UTF-16 code units,
/// and no run left empty.
///
/// Each run is scrubbed on its own, because each becomes its own `<t>`: a
/// surrogate pair split across two runs loses both halves. `removed` counts
/// the code units removed from all runs. The limit applies to the scrubbed
/// text. The cut falls inside the run that crosses the limit, one unit
/// earlier when it would split a surrogate pair, and the runs after it are
/// dropped. `truncated` says whether anything was cut. A run whose text is
/// empty, as given or once scrubbed or cut, is dropped as well, and counts
/// in neither: an empty run is an empty `<t>`, which Excel is reported to
/// repair (XlsxWriter, tested against Excel, refuses an empty fragment).
/// When every run is empty the result has no runs. [text] itself is
/// returned when nothing changes.
({XlsxRichText text, int removed, bool truncated}) cleanRichText(
  XlsxRichText text,
) {
  final List<XlsxTextRun> runs = <XlsxTextRun>[];
  int removed = 0;
  int length = 0;
  bool truncated = false;
  for (final XlsxTextRun run in text.runs) {
    final ScrubResult scrubbed = scrubXmlText(run.text);
    removed += scrubbed.removed;
    if (truncated) continue;
    String kept = scrubbed.text;
    final int room = XlsxLimits.maxCellTextLength - length;
    if (kept.length > room) {
      truncated = true;
      int cut = room;
      // A high surrogate in the last kept unit would lose its low half.
      if (cut > 0) {
        final int last = kept.codeUnitAt(cut - 1);
        if (last >= 0xD800 && last <= 0xDBFF) cut--;
      }
      kept = kept.substring(0, cut);
    }
    if (kept.isEmpty) continue;
    length += kept.length;
    runs.add(
      identical(kept, run.text) ? run : XlsxTextRun(kept, font: run.font),
    );
  }
  // Without removal or a cut, a run is missing only when it was empty.
  if (removed == 0 && !truncated && runs.length == text.runs.length) {
    return (text: text, removed: 0, truncated: false);
  }
  return (text: XlsxRichText(runs), removed: removed, truncated: truncated);
}

/// Writes [text] as one `<r>` per run: an `<rPr>` for a run with a font
/// (see [writeRunPropertiesXml]), then its `<t>` (see [writeTextElement]).
///
/// A run's font is written as given, so the caller resolves it first. The
/// text must be clean (see [cleanRichText]).
void writeTextRuns(XmlWriter w, XlsxRichText text) {
  for (final XlsxTextRun run in text.runs) {
    w.start('r');
    final XlsxFont? font = run.font;
    if (font != null) writeRunPropertiesXml(w, font);
    writeTextElement(w, run.text);
    w.end();
  }
}

/// Writes [text] as a `<t>` element (`ST_Xstring`), through
/// [escapeXstring] so text that looks like an `_xHHHH_` escape reads as
/// given, with `xml:space="preserve"` when the text starts or ends with
/// whitespace, which a reader would otherwise drop.
///
/// [text] must already be scrubbed with [scrubXmlText].
void writeTextElement(XmlWriter w, String text) {
  w.start('t');
  if (_isPadded(text)) w.attribute('xml:space', 'preserve');
  w.text(escapeXstring(text));
  w.end();
}

bool _isPadded(String text) {
  if (text.isEmpty) return false;
  return _isSpace(text.codeUnitAt(0)) ||
      _isSpace(text.codeUnitAt(text.length - 1));
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;
