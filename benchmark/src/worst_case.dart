/// The worst case under the reader's default limits: one sheet of about
/// 250 MiB of XML, just under `maxEntryBytes` (256 MiB).
///
/// New in jet_office. The sheet is rows of twelve `<c><v>1</v></c>` cells
/// without `r` (allowed since R2), so more rows than Excel's 1,048,576 fit;
/// the package around it is the minimal one the reader tests build
/// (`test/xlsx/read/support/workbook_builder.dart`), deflated by
/// `package:archive` at its default level.
library;

import 'dart:typed_data';

import '../../test/xlsx/read/support/workbook_builder.dart';

/// The most bytes the sheet part's XML may take: 250 MiB.
const int worstCaseTargetBytes = 250 * 1024 * 1024;

/// One row of the worst case: twelve cells holding the number 1, no `r`.
final String worstCaseRow = '<row>${'<c><v>1</v></c>' * 12}</row>';

/// The rows of the worst case's sheet: as many as fit in
/// [worstCaseTargetBytes] with the worksheet's own elements.
int worstCaseRows() =>
    (worstCaseTargetBytes - worksheet('').length) ~/ worstCaseRow.length;

/// Builds the worst case's package: one sheet `Data` of [worstCaseRows] rows.
///
/// The sheet's XML (about 250 MiB) is built as one string and dropped when
/// this returns; only the deflated package is kept.
Uint8List buildWorstCase() => buildWorkbook(<String, String?>{
  'Data': worksheet(worstCaseRow * worstCaseRows()),
});
