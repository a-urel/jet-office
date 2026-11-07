/// The tables of an [XlsxSheet]: the member that reads them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetTablesApi] in, so these are members of the sheet.
part of 'xlsx_sheet.dart';

/// The table half of [XlsxSheet].
mixin _SheetTablesApi {
  // What the sheet gives its table half.
  String? get _partName;
  List<({String partName, TablePart table})> _sheetTables();

  /// The tables of the sheet, in the order of the sheet's table
  /// relationships, each as [XlsxTable] types it.
  ///
  /// A table part the model cannot type (a root that is not a SpreadsheetML
  /// `table`, a `ref` that is not a range, or columns that do not match it)
  /// is left out, kept as written, and its name stays taken. A
  /// `totalsRowFunction` no schema value names reads
  /// [XlsxTotalsFunction.none] and is reported once as `featureEntryInvalid`
  /// with the detail `table`. The part's calculated columns, `dataDxfId`,
  /// `xr:uid`, filter criteria and sort state are not in [XlsxTable]; they
  /// stay in the file as read. A sheet without a part has none. Unmodifiable;
  /// a table part is read on first use.
  List<XlsxTable> get tables => _partName == null
      ? const <XlsxTable>[]
      : List<XlsxTable>.unmodifiable(<XlsxTable>[
          for (final ({String partName, TablePart table}) t in _sheetTables())
            t.table.value,
        ]);
}
