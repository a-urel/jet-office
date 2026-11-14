/// Replacing one template tag that Word split over several runs.
///
/// New in jet_office (decision 0024, spec section 5.3, Ruling 6);
/// quds_office_engine has no template fill, so this is not ported from Quds.
/// The run at the tag's first brace keeps its properties and takes the value,
/// so the filled text looks as the author formatted the tag's start; the runs
/// the tag covered wholly are removed, and every inline that adds no text of
/// its own (bookmark marks, spelling marks, comment ranges) stays where it is.
library;

import '../model/inlines.dart';
import '../model/run_content.dart';
import 'paragraph_text.dart';

/// Replaces the fillable span `[start, end)` of [map] by [value]: the run at
/// [start] keeps its properties and takes its text before the span then
/// [value]; the run at `end - 1` keeps its text after the span; runs wholly
/// inside are removed; transparent inlines stay where they are.
///
/// [value] is split into text, tabs and breaks and scrubbed as `DocxRun.text`
/// is, so the save reports the characters it removes. The content of the
/// start run before the tag's first text, and of the end run after its last,
/// stays (a tab before the tag in the same run). An end run left with nothing
/// is removed.
///
/// Replace the spans of one paragraph from the last to the first: the start
/// run's text node that holds the span's first character keeps its index and
/// its text before the span, so the positions of earlier spans stay valid.
///
/// The edit is made as [map] was read; edit nothing else of the paragraph
/// between reading it and calling this. Throws [ArgumentError] for a span
/// that is empty, not inside the text or not fillable
/// (`map.spanOf(start, end)`).
void replaceSpan(ParagraphText map, int start, int end, String value) {
  if (start < 0 || end > map.text.length || start >= end) {
    throw ArgumentError.value(
      '[$start, $end)',
      'span',
      'must be a non-empty span inside the text',
    );
  }
  final ({Region region, bool crossesBoundary}) kind = map.spanOf(start, end);
  if (kind.region != Region.fillable || kind.crossesBoundary) {
    throw ArgumentError.value(
      '[$start, $end)',
      'span',
      'must be fillable in place (region ${kind.region.name}, '
          'crossesBoundary ${kind.crossesBoundary})',
    );
  }
  final TextPosition first = map.positions[start];
  final TextPosition last = map.positions[end - 1];
  final DocxRun startRun = first.run!;
  final DocxRun endRun = last.run!;
  final String prefix = _textAt(
    startRun,
    first.contentIndex,
  ).substring(0, first.offset);
  final String suffix = _textAt(
    endRun,
    last.contentIndex,
  ).substring(last.offset + 1);
  final List<DocxRunContent> before = startRun.content.sublist(
    0,
    first.contentIndex,
  );
  final List<DocxRunContent> after = endRun.content.sublist(
    last.contentIndex + 1,
  );

  if (identical(startRun, endRun)) {
    setRunContent(startRun, before, '$prefix$value$suffix', after);
    return;
  }

  // Runs wholly inside: neither end run, found by their positions.
  final List<DocxRun> inside = <DocxRun>[];
  for (int i = start + 1; i < end - 1; i++) {
    final DocxRun? run = map.positions[i].run;
    if (run == null ||
        identical(run, startRun) ||
        identical(run, endRun) ||
        inside.any((DocxRun r) => identical(r, run))) {
      continue;
    }
    inside.add(run);
  }

  setRunContent(startRun, before, '$prefix$value', const <DocxRunContent>[]);
  for (final DocxRun run in inside) {
    removeHeldInline(run);
  }
  if (suffix.isEmpty && after.isEmpty) {
    removeHeldInline(endRun);
  } else {
    setRunContent(endRun, const <DocxRunContent>[], suffix, after);
  }
}

String _textAt(DocxRun run, int contentIndex) =>
    (run.content[contentIndex] as DocxText).text;
