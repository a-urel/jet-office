/// The data validations and conditional formats of an [XlsxSheet]: the
/// members that read, add and remove them.
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
///
/// A conditional format is a `<conditionalFormatting>` of the sheet's first
/// run of them, kept as a [CfBlock]. Its rules hold no style: the getter joins
/// each with its `<dxf>`. A new element is the one the sheet writer writes
/// (`writeConditionalFormats`), with the next priorities of the sheet and the
/// rules' styles appended to the styles part. Those stay when the format is
/// removed, as the part is append-only.
part of 'xlsx_sheet.dart';

/// The data validation and conditional format half of [XlsxSheet].
mixin _SheetRules {
  // What the sheet gives its rules half.
  SheetHost get _host;
  String get name;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);
  StylesPart _stylesFor();
  void _reportInvalid(String what);

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

  /// The conditional formats of the sheet in file order, as the sheet
  /// writer's `conditionalFormat` takes them.
  ///
  /// A `<conditionalFormatting>` that cannot be read (no usable `sqref`, a
  /// rule of an unknown `type`, or a value the writer refuses) is kept as
  /// written, left out here and reported once as `featureEntryInvalid` with
  /// the detail `conditionalFormatting`. A rule whose `dxfId` names no
  /// `<dxf>` reads with no style and is reported the same way, once for the
  /// sheet. `timePeriod`, `containsBlanks`, `notContainsBlanks`,
  /// `containsErrors` and `notContainsErrors` rules read as
  /// [XlsxExpressionRule]s, and stay as written. Only the first run of
  /// adjacent elements is read: one after another element stays as written,
  /// unlisted. Unmodifiable. Loads the sheet. Throws an
  /// [XlsxReadException] when the sheet cannot be read.
  List<XlsxConditionalFormat> get conditionalFormats =>
      List<XlsxConditionalFormat>.unmodifiable(<XlsxConditionalFormat>[
        for (final GroupItem<CfEntry> item
            in _load()?.conditionalBlock?.items ?? const <GroupItem<CfEntry>>[])
          if (item.value != null) _conditionalFormatOf(item.value!),
      ]);

  /// The format of [entry], each rule joined with the style its `dxfId`
  /// names.
  XlsxConditionalFormat _conditionalFormatOf(CfEntry entry) {
    final StylesPart? styles = _host.styles;
    return XlsxConditionalFormat(entry.ranges, <XlsxConditionalRule>[
      for (final CfRuleEntry rule in entry.rules) _ruleWithStyle(rule, styles),
    ]);
  }

  XlsxConditionalRule _ruleWithStyle(CfRuleEntry entry, StylesPart? styles) {
    final XlsxConditionalRule rule = entry.rule;
    final int? id = entry.dxfId;
    if (id == null ||
        rule is XlsxColorScale ||
        rule is XlsxDataBar ||
        rule is XlsxIconSet) {
      return rule;
    }
    final XlsxStyle? style = styles?.differentialStyle(id);
    if (style == null) {
      _reportInvalid('conditionalFormatting');
      return rule;
    }
    return withRuleStyle(rule, style);
  }

  /// Adds [format] after the others, as the sheet writer writes it: its
  /// rules take the priorities after the sheet's highest, and each style a
  /// `<dxf>` of the styles part, an equal one the file has or a new one.
  /// [conditionalFormats] then gives it as the file says it: without a
  /// leading `=` of a formula, and with none for an icon set's default
  /// thresholds.
  ///
  /// Throws an [ArgumentError] naming the field, as the writer's
  /// `conditionalFormat` does (`rules[0].rank`, `rules[1].style.numFmt`),
  /// for a format that is not valid, an [UnsupportedError] for a rule that
  /// needs the Excel 2010 `extLst` (a data bar, an icon set only Excel 2010
  /// has), an [XlsxLimitError] when the sheet's priorities run out, a
  /// [StateError] for a sheet that is not a worksheet or has no part or a
  /// styles part the model cannot edit and an [XlsxReadException] when the
  /// sheet cannot be read. Whatever it throws, nothing has changed.
  void addConditionalFormat(XlsxConditionalFormat format) {
    final WorksheetPart part = _editablePart('conditional formats');
    checkConditionalFormat(format);
    if (format.rules.any(hasX14Rule)) {
      throw UnsupportedError(
        'Adding a data bar or an Excel 2010 icon set is not supported yet.',
      );
    }
    final int firstPriority = part.highestConditionalPriority + 1;
    if (firstPriority + format.rules.length - 1 > maxRulePriority) {
      throw XlsxLimitError('conditional format priorities', maxRulePriority);
    }
    final List<XlsxStyle?> ruleStyles = <XlsxStyle?>[
      for (final XlsxConditionalRule rule in format.rules)
        conditionalRuleStyle(rule),
    ];
    final StylesPart? styles = ruleStyles.nonNulls.isEmpty
        ? null
        : _stylesFor();
    final CfBlock? block = part.conditionalBlock;
    final ChangeLog log = _host.log;
    log.transaction(() {
      final List<int?> dxfIds = <int?>[
        for (int i = 0; i < ruleStyles.length; i++)
          if (ruleStyles[i] == null)
            null
          else
            _appendRuleStyle(log, styles!, ruleStyles[i]!, i),
      ];
      final OpaqueXml source = renderElements(
        (XmlWriter w) =>
            writeConditionalFormats(w, <WorksheetConditionalFormat>[
              (format: format, dxfIds: dxfIds, firstPriority: firstPriority),
            ], _host.sheetIndexOf(this as XlsxSheet) + 1),
      ).single;
      final List<XlsxConditionalRule> rules = normalizedConditionalFormat(
        format,
      ).rules;
      final CfEntry entry = CfEntry(format.ranges, <CfRuleEntry>[
        for (int i = 0; i < rules.length; i++)
          CfRuleEntry(
            withRuleStyle(rules[i], null),
            firstPriority + i,
            dxfId: dxfIds[i],
          ),
      ], source);
      final CfBlock next = CfBlock(<GroupItem<CfEntry>>[
        ...?block?.items,
        GroupItem<CfEntry>(entry, source),
      ]);
      editLayout(
        log,
        part,
        'conditionalFormatting',
        () => part.swapLayout('conditionalFormatting', block, next),
      );
    });
  }

  /// The `<dxf>` of [style], the style of rule [index], appended when the
  /// part has no equal one. An error is named as the writer names it.
  int _appendRuleStyle(
    ChangeLog log,
    StylesPart styles,
    XlsxStyle style,
    int index,
  ) {
    try {
      return appendDifferentialStyle(log, styles, style);
    } on ArgumentError catch (e, stack) {
      Error.throwWithStackTrace(
        ArgumentError.value(
          e.invalidValue,
          'rules[$index].style.${e.name}',
          e.message,
        ),
        stack,
      );
    }
  }

  /// Removes the first format of [conditionalFormats] equal to [format]. The
  /// other elements, readable or not, stay as written and in their order,
  /// and the `<dxf>`s of the styles part stay.
  ///
  /// [format] also matches as the writer writes it, so one built by hand
  /// matches the entry it was added as: a leading `=` of a formula and
  /// thresholds that are an icon set's defaults do not count. The value the
  /// getter gives matches as it is, whatever the file wrote.
  ///
  /// Throws an [ArgumentError] when none is equal, a [StateError] for a
  /// sheet that is not a worksheet or has no part and an
  /// [XlsxReadException] when the sheet cannot be read. Whatever it throws,
  /// nothing has changed.
  void removeConditionalFormat(XlsxConditionalFormat format) {
    final WorksheetPart part = _editablePart('conditional formats');
    final CfBlock? block = part.conditionalBlock;
    final List<GroupItem<CfEntry>> items =
        block?.items ?? const <GroupItem<CfEntry>>[];
    final XlsxConditionalFormat written = normalizedConditionalFormat(format);
    final int at = items.indexWhere((GroupItem<CfEntry> item) {
      final CfEntry? entry = item.value;
      if (entry == null) return false;
      final XlsxConditionalFormat listed = _conditionalFormatOf(entry);
      return listed == format || listed == written;
    });
    if (block == null || at < 0) {
      throw ArgumentError.value(
        format,
        'format',
        'The sheet "$name" has no equal conditional format.',
      );
    }
    final CfBlock next = CfBlock(<GroupItem<CfEntry>>[...items]..removeAt(at));
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(
        log,
        part,
        'conditionalFormatting',
        () => part.swapLayout('conditionalFormatting', block, next),
      );
    });
  }
}
