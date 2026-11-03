/// The checks a merged range must pass, shared by the writer's `merge` and
/// the workbook model's.
///
/// Not ported from Quds; written for jet_office. Quds accepted overlapping
/// merges.
library;

import 'range.dart';

/// Throws an [ArgumentError] named `range` when [range] cannot be merged
/// with the [merges] already made on a sheet whose tables are [tables]: it
/// is a single cell, overlaps a merged range, or overlaps a table. The
/// message names both ranges. [range] must already have passed
/// `validateRange`.
void checkMerge(
  XlsxRange range,
  Iterable<XlsxRange> merges,
  Iterable<({String name, XlsxRange range})> tables,
) {
  if (range.isSingleCell) {
    throw ArgumentError.value(
      range,
      'range',
      'A merged range must cover at least two cells.',
    );
  }
  for (final XlsxRange earlier in merges) {
    if (earlier.overlaps(range)) {
      throw ArgumentError.value(
        range,
        'range',
        'The range ${range.ref} overlaps the merged range ${earlier.ref}.',
      );
    }
  }
  checkNoTableOverlap(range, tables);
}

/// Throws an [ArgumentError] named `range` when [range] overlaps one of
/// [tables], naming both.
void checkNoTableOverlap(
  XlsxRange range,
  Iterable<({String name, XlsxRange range})> tables,
) {
  for (final ({String name, XlsxRange range}) t in tables) {
    if (t.range.overlaps(range)) {
      throw ArgumentError.value(
        range,
        'range',
        'The range ${range.ref} overlaps the table "${t.name}" over '
            '${t.range.ref}.',
      );
    }
  }
}
