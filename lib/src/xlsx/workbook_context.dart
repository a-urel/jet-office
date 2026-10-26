/// [WorkbookContext], the workbook-level state a sheet writer shares with
/// its workbook writer.
///
/// New in jet_office. Quds' `XlsxSheetBuilder` held its rows and handed them
/// to `XlsxWorkbookBuilder.build`, which serialized everything at the end;
/// here a sheet encodes its cells as they arrive and hands its finished part
/// to the ZIP itself, so it needs the workbook's encoder, styles and ZIP. This
/// class gives it those without exposing the workbook writer's other state.
library;

import '../zip/archive_adapter.dart';
import 'cell_encoder.dart';
import 'shared_strings.dart';
import 'style_registry.dart';
import 'warnings.dart';

/// What every sheet of one workbook shares: the cell encoder with the
/// shared strings, styles and warnings it records into, the ZIP that
/// receives finished parts, and whether the writer has failed.
///
/// One context belongs to one workbook writer, which creates it; a sheet
/// writer keeps a reference to the context of the writer that added it.
final class WorkbookContext {
  /// Creates the context of a workbook whose parts go to [zip], with empty
  /// shared strings, styles and warnings.
  WorkbookContext(this.zip);

  /// The archive that receives each finished part.
  final ZipWriter zip;

  /// The data problems repaired so far, in first-occurrence order.
  final WarningCollector warnings = WarningCollector();

  /// The workbook's distinct strings, written last as `sharedStrings.xml`.
  final SharedStrings strings = SharedStrings();

  /// The workbook's distinct styles, written last as `styles.xml`.
  final StyleRegistry styles = StyleRegistry();

  /// The one cell encoder of the workbook (decision 0002).
  late final CellEncoder encoder = CellEncoder(
    strings: strings,
    styles: styles,
    warnings: warnings,
  );

  /// What the ZIP work threw, once it has failed; the writer is then dead.
  Object? _failure;

  /// Records that handing bytes to the ZIP threw [error]; every later
  /// [checkNotFailed] throws.
  ///
  /// Called only by the workbook writer's ZIP work (`_zipWork` in
  /// `xlsx_writer.dart`). Sheet code reaches the context too, but must not
  /// call this: an error it throws on its own leaves the writer usable.
  void recordFailure(Object error) {
    _failure = error;
  }

  /// Throws a [StateError] naming the earlier error once the writer has
  /// failed (see [recordFailure]).
  void checkNotFailed() {
    final Object? failure = _failure;
    if (failure != null) {
      throw StateError(
        'The writer failed earlier and cannot continue: $failure',
      );
    }
  }
}
