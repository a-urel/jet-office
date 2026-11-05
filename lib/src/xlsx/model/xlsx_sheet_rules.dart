/// The data validations of an [XlsxSheet]: the members that read, add and
/// remove them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetRules] in, so these are members of the sheet.
///
/// A validation is a `<dataValidation>` of the sheet's first
/// `<dataValidations>`, kept as an [ItemGroup] of [XlsxDataValidation]. An
/// entry the model cannot read stays where it is, is counted and is left out
/// of the typed list. A new entry is the element the sheet writer writes
/// (`writeDataValidation`); `count` is recomputed, and what the group and the
/// other entries carry (`disablePrompts`, `xWindow`, `yWindow`, `imeMode`) is
/// kept.
part of 'xlsx_sheet.dart';

/// The data validation half of [XlsxSheet].
mixin _SheetRules {
  // What the sheet gives its rules half.
  SheetHost get _host;
  String get name;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);

  /// The validations of the sheet in file order, as the sheet writer's
  /// `dataValidation` takes them.
  ///
  /// A `<dataValidation>` that cannot be read (no usable `sqref`, an unknown
  /// `type`, `errorStyle` or `operator`) is kept as written, left out here
  /// and reported once as `featureEntryInvalid` with the detail
  /// `dataValidation`. A flag the file leaves out reads as the schema's
  /// default (`allowBlank` false), and `showDropDown="1"` reads as
  /// `showDropDownArrow: false`. Only the first `<dataValidations>` is read;
  /// Excel 2010 validations (`x14:dataValidations`) stay as written.
  /// Unmodifiable. Loads the sheet. Throws an [XlsxReadException] when the
  /// sheet cannot be read.
  List<XlsxDataValidation> get dataValidations =>
      List<XlsxDataValidation>.unmodifiable(
        _load()?.dataValidationGroup?.values ?? const <XlsxDataValidation>[],
      );

  /// Adds [validation] after the others, as the sheet writer writes it: the
  /// `<dataValidations>` is made in schema position when the sheet has none
  /// and its `count` is recomputed.
  ///
  /// Throws an [ArgumentError] naming the field, as the writer's
  /// `dataValidation` does, for a validation that is not valid (a range
  /// outside the sheet or overlapping one of this or of a readable earlier
  /// validation, a formula, a message that is too long, ...), a [StateError]
  /// for a sheet that is not a worksheet or has no part and an
  /// [XlsxReadException] when the sheet cannot be read. Whatever it throws,
  /// nothing has changed.
  void addDataValidation(XlsxDataValidation validation) {
    final WorksheetPart part = _editablePart('data validations');
    final ItemGroup<XlsxDataValidation>? group = part.dataValidationGroup;
    checkDataValidation(
      validation,
      group?.values ?? const <XlsxDataValidation>[],
    );
    final GroupItem<XlsxDataValidation> item = GroupItem<XlsxDataValidation>(
      normalizedValidation(validation),
      renderElements(
        (XmlWriter w) => writeDataValidation(w, validation),
      ).single,
    );
    final ItemGroup<XlsxDataValidation> next = group == null
        ? ItemGroup<XlsxDataValidation>(
            '${part.elementPrefix}dataValidations',
            'dataValidations',
            const <String, String>{},
            const <KeptAttribute>[],
            <GroupItem<XlsxDataValidation>>[item],
            edited: true,
          )
        : group.withItems(<GroupItem<XlsxDataValidation>>[
            ...group.items,
            item,
          ]);
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(
        log,
        part,
        'dataValidations',
        () => part.swapLayout('dataValidations', group, next),
      );
    });
  }

  /// Removes the first validation of [dataValidations] equal to
  /// [validation], the group going with its last entry. The other entries,
  /// readable or not, stay as written and `count` is recomputed.
  ///
  /// [validation] is compared as the writer writes it, so one built by hand
  /// matches the entry it was added as (a leading `=` of a formula and the
  /// fields its type ignores do not count). Throws an [ArgumentError] when
  /// none is equal, a [StateError] for a sheet that is not a worksheet or
  /// has no part and an [XlsxReadException] when the sheet cannot be read.
  /// Whatever it throws, nothing has changed.
  void removeDataValidation(XlsxDataValidation validation) {
    final WorksheetPart part = _editablePart('data validations');
    final ItemGroup<XlsxDataValidation>? group = part.dataValidationGroup;
    final XlsxDataValidation wanted = normalizedValidation(validation);
    int at = -1;
    if (group != null) {
      for (int i = 0; i < group.items.length; i++) {
        if (group.items[i].value == wanted) {
          at = i;
          break;
        }
      }
    }
    if (group == null || at < 0) {
      throw ArgumentError.value(
        validation,
        'validation',
        'The sheet "$name" has no equal data validation.',
      );
    }
    final List<GroupItem<XlsxDataValidation>> rest =
        <GroupItem<XlsxDataValidation>>[...group.items]..removeAt(at);
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(
        log,
        part,
        'dataValidations',
        () => part.swapLayout(
          'dataValidations',
          group,
          rest.isEmpty ? null : group.withItems(rest),
        ),
      );
    });
  }
}
