/// The defined names of an [XlsxSheet]: the members that read, add and
/// remove the names that belong to the sheet alone.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetNames] in, so these are members of the sheet.
part of 'xlsx_sheet.dart';

/// The defined names half of [XlsxSheet].
mixin _SheetNames {
  // What the sheet gives its names half.
  SheetHost get _host;
  String get name;

  /// The sheet's own names, in file order, as the file has them: those
  /// whose `localSheetId` is this sheet's tab index.
  ///
  /// Excel's built-in names (`_xlnm.Print_Area` and the like) are not
  /// listed, and a name the model cannot read is left out and reported
  /// (`featureEntryInvalid`); both stay in the file as written. Does not
  /// load the sheet. Unmodifiable.
  List<XlsxDefinedName> get definedNames =>
      definedNamesIn(_host.workbookPart, _host.sheetIndexOf(this as XlsxSheet));

  /// Defines [name] for this sheet only, after the names already there; a
  /// workbook name of the same spelling stays and is hidden from formulas
  /// of this sheet.
  ///
  /// Throws an [ArgumentError] naming `name`, `formula` or `comment` for an
  /// invalid name, formula or comment, a name this sheet already has or a
  /// name that a table has, ignoring case; nothing changes then. The save
  /// asks Excel to recalculate every formula, as for
  /// [XlsxWorkbook.defineName].
  void defineName(XlsxDefinedName name) => _recordSheetEdit(
    this,
    XlsxChangeKind.nameChanged,
    () => defineNameIn(
      _host.log,
      _host.workbookPart,
      _host.sheetIndexOf(this as XlsxSheet),
      name,
      _host.checkNotTableName,
    ),
  );

  /// Removes this sheet's name [name], compared ignoring case.
  ///
  /// Throws an [ArgumentError] named `name` when the sheet has no such name
  /// (a built-in name is none, and a workbook name is not the sheet's);
  /// nothing changes then. The save asks for recalculation as
  /// [defineName] does.
  void removeName(String name) => _recordSheetEdit(
    this,
    XlsxChangeKind.nameChanged,
    () => removeNameIn(
      _host.log,
      _host.workbookPart,
      _host.sheetIndexOf(this as XlsxSheet),
      name,
      'the sheet "${this.name}"',
    ),
  );
}
