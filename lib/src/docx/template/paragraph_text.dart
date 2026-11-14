/// The searchable text of a paragraph, mapped back to its runs.
///
/// New in jet_office (decision 0024, spec sections 5.1 and 5.2, Ruling 6);
/// quds_office_engine has no template fill, so this is not ported from Quds.
/// Word splits one tag over several runs, so the template fill scans the
/// paragraph's text as a whole and needs every character's run to edit it.
/// The text is divided into segments; a tag may not cross from one segment to
/// another, because the two sides are not one stretch of editable text (a
/// hyperlink's edge, a tab, a field result, a tracked insertion).
library;

import '../../opc/ooxml.dart' show Ns;
import '../model/blocks.dart';
import '../model/inlines.dart';
import '../model/run_content.dart';

/// The character standing for a position that holds no text of its own: a tab,
/// a break, a picture, a field mark or opaque run content. No tag body may
/// hold it, so a tag that meets it is malformed.
const String nonText = '￼';

/// What a stretch of the paragraph's text is.
enum Region {
  /// Text of a run that is the paragraph's own or a typed hyperlink's: a tag
  /// in it can be filled in place.
  fillable,

  /// The cached result of a field (instruction text never counts).
  fieldResult,

  /// Text inside a tracked insertion or a move (`w:ins`, `w:moveTo`).
  revision,

  /// Text inside a content control (`w:sdt`).
  contentControl,

  /// Visible text inside any other inline the model keeps opaque.
  opaque,
}

/// One position of a [ParagraphText]: a character of a `DocxText`, or
/// [nonText].
final class TextPosition {
  /// Creates a position.
  const TextPosition({
    required this.run,
    required this.contentIndex,
    required this.offset,
    required this.segment,
    required this.region,
  });

  /// The run holding the character, only for a [Region.fillable] position
  /// that comes from a `DocxText`; `null` for every other position.
  final DocxRun? run;

  /// The index of the `DocxText` in the run's content, only for a
  /// [Region.fillable] position that comes from a `DocxText`; -1 otherwise.
  final int contentIndex;

  /// The index of the character in that `DocxText`'s text, only for a
  /// [Region.fillable] position that comes from a `DocxText`; -1 otherwise.
  final int offset;

  /// The number of the segment the position is in. Two positions can be one
  /// tag's only when their segments are equal.
  final int segment;

  /// What the position's text is.
  final Region region;
}

/// The text of a paragraph a tag scan reads, and where each character is.
final class ParagraphText {
  ParagraphText._(this.text, this.positions);

  /// The scanned text: every visible character of the paragraph's inlines in
  /// order, [nonText] for a position without text of its own.
  final String text;

  /// One entry for each UTF-16 unit of [text], so
  /// `positions.length == text.length`.
  final List<TextPosition> positions;

  /// What stops the span `[start, end)` of [text] from being filled in place.
  ///
  /// When every position of the span is in one segment, that segment's region
  /// and `crossesBoundary: false`. Otherwise `crossesBoundary: true` and the
  /// first region other than [Region.fillable] met in the span, or
  /// [Region.fillable] when there is none. A span is fillable exactly when
  /// `region == Region.fillable && !crossesBoundary`.
  ///
  /// An empty span is fillable. Throws [RangeError] when the span is not
  /// inside [text].
  ({Region region, bool crossesBoundary}) spanOf(int start, int end) {
    RangeError.checkValidRange(start, end, text.length, 'start', 'end');
    if (start == end) return (region: Region.fillable, crossesBoundary: false);
    final int segment = positions[start].segment;
    Region? other;
    bool crosses = false;
    for (int i = start; i < end; i++) {
      final TextPosition p = positions[i];
      if (p.segment != segment) crosses = true;
      if (p.region != Region.fillable) other ??= p.region;
    }
    if (!crosses) {
      return (region: positions[start].region, crossesBoundary: false);
    }
    return (region: other ?? Region.fillable, crossesBoundary: true);
  }
}

/// The inlines that add no text and do not end a segment: bookmark marks and
/// the `w:` elements Word scatters through a split tag (Ruling 6).
const Set<String> _transparent = <String>{
  'proofErr',
  'commentRangeStart',
  'commentRangeEnd',
  'del',
  'moveFrom',
  'moveFromRangeStart',
  'moveFromRangeEnd',
  'moveToRangeStart',
  'moveToRangeEnd',
  'permStart',
  'permEnd',
};

/// The searchable text of [paragraph] and the position of each character.
///
/// Never throws; a paragraph without inlines gives an empty text.
ParagraphText paragraphTextOf(DocxParagraph paragraph) {
  final _Builder b = _Builder();
  b.walk(paragraph.inlines, Region.fillable);
  return ParagraphText._(b.buffer.toString(), b.positions);
}

final class _Builder {
  final StringBuffer buffer = StringBuffer();
  final List<TextPosition> positions = <TextPosition>[];
  int _segment = 0;

  void _cut() => _segment++;

  void _add(String char, DocxRun? run, int index, int offset, Region region) {
    buffer.write(char);
    positions.add(
      TextPosition(
        run: run,
        contentIndex: index,
        offset: offset,
        segment: _segment,
        region: region,
      ),
    );
  }

  void _addText(String text, Region region, {DocxRun? run, int index = -1}) {
    for (int i = 0; i < text.length; i++) {
      final bool typed = run != null && region == Region.fillable;
      _add(
        text[i],
        typed ? run : null,
        typed ? index : -1,
        typed ? i : -1,
        region,
      );
    }
  }

  void walk(List<DocxInline> inlines, Region region) {
    for (final DocxInline inline in inlines) {
      switch (inline) {
        case DocxRun():
          _run(inline, region);
        case DocxHyperlink():
          _cut();
          walk(inline.inlines, region);
          _cut();
        case DocxField():
          _cut();
          walk(inline.result, Region.fieldResult);
          _cut();
        case DocxBookmarkStart() || DocxBookmarkEnd():
          break;
        case DocxOpaqueInline():
          _opaque(inline);
      }
    }
  }

  void _run(DocxRun run, Region region) {
    final List<DocxRunContent> content = run.content;
    for (int i = 0; i < content.length; i++) {
      final DocxRunContent c = content[i];
      switch (c) {
        case DocxText():
          _addText(c.text, region, run: run, index: i);
        case DocxFieldInstruction():
          // Instruction text is never visible, but a tag may not span it:
          // replacing the span would remove the run that holds it.
          _cut();
        default:
          // A tab, break, picture, field mark or opaque content: one
          // position of its own, which ends the segment on both sides.
          _cut();
          _add(nonText, null, -1, -1, region);
          _cut();
      }
    }
  }

  void _opaque(DocxOpaqueInline inline) {
    if (inline.namespaceUri == Ns.w &&
        _transparent.contains(inline.localName)) {
      return;
    }
    _cut();
    final Region region = inline.namespaceUri != Ns.w
        ? Region.opaque
        : switch (inline.localName) {
            'ins' || 'moveTo' => Region.revision,
            'sdt' => Region.contentControl,
            _ => Region.opaque,
          };
    _addText(inline.text, region);
    _cut();
  }
}
