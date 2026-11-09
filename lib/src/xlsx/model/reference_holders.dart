/// The holders of cell references in a workbook, which a structural edit
/// (rows or columns inserted or deleted, a sheet renamed or moved) rewrites
/// through a [ReferenceMapper].
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import '../../opc/change_log.dart';
import '../formula/formula_rewrite.dart';
import '../formula/reference_shift.dart';
import 'xlsx_sheet.dart';

/// Something in the model that stores a reference, a `sqref` or a formula,
/// and rewrites it when a structural edit moves what it points at.
abstract interface class ReferenceHolder {
  /// A short name for messages and the architecture test, such as `cells`.
  String get holderName;

  /// Applies [mapper] inside the current transaction, recording changes.
  ///
  /// [edit] is the sheet-level edit for holders that move positions
  /// (anchors, merges), or `null` for a sheet renamed or moved.
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit);
}

/// A holder whose rewrite is not written yet: it only records each call.
/// Tasks 5 to 9 of W5 replace these one by one.
final class PendingReferenceHolder implements ReferenceHolder {
  /// A pending holder named [holderName].
  PendingReferenceHolder(this.holderName);

  @override
  final String holderName;

  /// Every call of [shiftReferences], in order.
  final List<({ReferenceMapper mapper, ReferenceShift? edit})> calls =
      <({ReferenceMapper mapper, ReferenceShift? edit})>[];

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) =>
      calls.add((mapper: mapper, edit: edit));
}

/// The holder names of a sheet, in the order they are applied.
const List<String> sheetHolderNames = <String>[
  'cells',
  'merges',
  'conditionalFormats',
  'dataValidations',
  'hyperlinks',
  'autoFilter',
  'tables',
  'drawings',
  'notes',
  'views',
];

/// The holder names of the workbook, applied after every sheet's.
const List<String> workbookHolderNames = <String>['definedNames'];

/// The model files under `lib/src/xlsx/model/` that store a reference, a
/// `sqref` or a formula, each with the holder that rewrites it. The
/// architecture test requires every such file to be listed here (or in its
/// own allow-list, with a reason).
const Map<String, String> referenceHolderSources = <String, String>{
  'cell_store.dart': 'cells',
  'worksheet_part.dart': 'merges',
  'xlsx_sheet_merges.dart': 'merges',
  'conditional_elements.dart': 'conditionalFormats',
  'conditional_x14.dart': 'conditionalFormats',
  'validation_elements.dart': 'dataValidations',
  'xlsx_sheet_links.dart': 'hyperlinks',
  'xlsx_sheet_print.dart': 'autoFilter',
  'table_part.dart': 'tables',
  'xlsx_sheet_tables.dart': 'tables',
  'drawing_part.dart': 'drawings',
  'xlsx_sheet_pictures.dart': 'drawings',
  'comments_part.dart': 'notes',
  'vml_part.dart': 'notes',
  'xlsx_sheet_views.dart': 'views',
  'defined_names.dart': 'definedNames',
};

/// Every reference holder of a workbook.
final class ReferenceRegistry {
  /// A registry over [_sheets] (read on each call, so added and removed
  /// sheets count) whose changes go to [_log].
  ReferenceRegistry(this._log, this._sheets);

  final ChangeLog _log;
  final List<XlsxSheet> Function() _sheets;

  final List<ReferenceHolder> _workbookHolders = <ReferenceHolder>[
    for (final String name in workbookHolderNames) PendingReferenceHolder(name),
  ];

  /// The workbook-level holders.
  List<ReferenceHolder> get workbookHolders => _workbookHolders;

  /// Every holder of every sheet (loading each sheet), then of the workbook.
  Iterable<ReferenceHolder> holders() => <ReferenceHolder>[
    for (final XlsxSheet sheet in _sheets()) ...sheetReferenceHolders(sheet),
    ..._workbookHolders,
  ];

  /// Runs [mapper] over every holder in one transaction: if one throws,
  /// every change already made is reverted.
  void apply(ReferenceMapper mapper, ReferenceShift? edit) {
    _log.transaction(() {
      for (final ReferenceHolder holder in holders()) {
        holder.shiftReferences(mapper, edit);
      }
    });
  }
}
