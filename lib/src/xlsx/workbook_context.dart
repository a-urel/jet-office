/// [WorkbookContext], the workbook-level state a sheet writer shares with
/// its workbook writer, and [PackageContentTypes], the content types the
/// sheets add to the package.
///
/// New in jet_office. Quds' `XlsxSheetBuilder` held its rows and handed them
/// to `XlsxWorkbookBuilder.build`, which serialized everything at the end;
/// here a sheet encodes its cells as they arrive and hands its finished part
/// to the ZIP itself, so it needs the workbook's encoder, styles and ZIP. This
/// class gives it those without exposing the workbook writer's other state.
/// A finished sheet's parts beyond the worksheet (drawings, notes, tables)
/// need content types, which the workbook writes only at `close()`; the
/// sheet records them in [WorkbookContext.contentTypes].
library;

import 'dart:collection';

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

  /// The content types of the parts the sheets wrote beyond the worksheets,
  /// which `close()` adds to `[Content_Types].xml`.
  final PackageContentTypes contentTypes = PackageContentTypes();

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

/// The default and override content types the sheets of one workbook
/// register for the parts they write, such as `png` images or a table part.
///
/// Both are kept in the order first registered; `writeContentTypes` writes
/// them with the workbook's own. Nothing is checked here: the values come
/// from the writer's own constants, not from the caller.
final class PackageContentTypes {
  final Map<String, String> _defaults = <String, String>{};
  final Map<String, String> _overrides = <String, String>{};

  /// Declares [type] for every part whose name ends in [extension] (without
  /// the dot). The first registration wins: a later one for the same
  /// extension changes nothing, so each sheet may register what it uses.
  void addDefault(String extension, String type) {
    _defaults.putIfAbsent(extension, () => type);
  }

  /// Declares [type] for the single part named [partName], an absolute name
  /// such as `/xl/tables/table1.xml`. The first registration wins, as with
  /// [addDefault].
  void addOverride(String partName, String type) {
    _overrides.putIfAbsent(partName, () => type);
  }

  /// The extensions and their types, in first-registration order; a view
  /// that cannot be changed.
  Map<String, String> get defaults => UnmodifiableMapView(_defaults);

  /// The part names and their types, in first-registration order; a view
  /// that cannot be changed.
  Map<String, String> get overrides => UnmodifiableMapView(_overrides);
}
