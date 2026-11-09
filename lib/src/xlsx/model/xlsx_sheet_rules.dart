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
///
/// The Excel 2010 rules are in the `extLst`, its own slot of the part: an edit
/// of a format is an edit of each, in one transaction. The getter joins the
/// two (`joinConditionalFormats`).
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
  /// Both are compared as the writer writes them, so a value the getter gave
  /// and one built by hand match the entry (a leading `=` of a formula,
  /// which a file may have, and the fields its type ignores do not count).
  /// Throws an [ArgumentError] when none is equal, a [StateError] for a sheet
  /// that is not a worksheet or has no part and an [XlsxReadException] when
  /// the sheet cannot be read. Whatever it throws, nothing has changed.
  void removeDataValidation(XlsxDataValidation validation) {
    final WorksheetPart part = _editablePart('data validations');
    final ItemGroup<XlsxDataValidation>? group = part.dataValidationGroup;
    final XlsxDataValidation wanted = normalizedValidation(validation);
    int at = -1;
    if (group != null) {
      for (int i = 0; i < group.items.length; i++) {
        final XlsxDataValidation? listed = group.items[i].value;
        if (listed != null && normalizedValidation(listed) == wanted) {
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
  /// unlisted.
  ///
  /// Excel 2010 rules are read from the first `x14:conditionalFormattings` of
  /// the sheet's `extLst`. A data bar with a rule there has that rule's
  /// fields; a color the writer fills for none (a negative fill of red, an
  /// axis of black, a border of the bar's color) reads as none. A rule no
  /// Excel 2007 rule names joins the format with an equal `sqref`, by
  /// priority, else it makes a format of its own after the others. A custom
  /// icon set and a rule of another kind stay as written, unlisted; one with
  /// no `id` or a value the writer refuses, and an element with no usable
  /// `xm:sqref`, too, reported as `featureEntryInvalid` with the detail
  /// `x14:cfRule` or `x14:conditionalFormatting`.
  ///
  /// Unmodifiable. Loads the sheet. Throws an [XlsxReadException] when the
  /// sheet cannot be read.
  List<XlsxConditionalFormat> get conditionalFormats {
    final WorksheetPart? part = _load();
    if (part == null) return List<XlsxConditionalFormat>.unmodifiable(const []);
    return List<XlsxConditionalFormat>.unmodifiable(<XlsxConditionalFormat>[
      for (final JoinedFormat format in _joinedFormats(part))
        _conditionalFormatOf(format),
    ]);
  }

  List<JoinedFormat> _joinedFormats(WorksheetPart part) =>
      joinConditionalFormats(
        part.conditionalBlock,
        part.x14Block,
        part.unlistedX14Links,
      );

  /// The value of [format], each 2007 rule joined with the style its `dxfId`
  /// names and its Excel 2010 half.
  XlsxConditionalFormat _conditionalFormatOf(JoinedFormat format) {
    final StylesPart? styles = _host.styles;
    return XlsxConditionalFormat(format.ranges, <XlsxConditionalRule>[
      for (final JoinedRule rule in format.rules)
        rule.value(
          rule.entry == null ? null : _ruleWithStyle(rule.entry!, styles),
        ),
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
  /// leading `=` of a formula, with none for an icon set's default
  /// thresholds, and with none for a data bar's color the writer fills.
  ///
  /// A data bar and an icon set only Excel 2010 has also get a rule in the
  /// sheet's `extLst`, which joins the file's `x14:conditionalFormattings` or
  /// is made in schema position. Its id is the writer's, with the sheet's
  /// number raised past any id the sheet uses. Such a rule on the `sqref` of
  /// a format the sheet has, with no Excel 2007 rule, reads as part of that
  /// format.
  ///
  /// Throws an [ArgumentError] naming the field, as the writer's
  /// `conditionalFormat` does (`rules[0].rank`, `rules[1].style.numFmt`),
  /// for a format that is not valid, an [XlsxLimitError] when the sheet's
  /// priorities run out, a [StateError] for a sheet that is not a worksheet
  /// or has no part or a styles part the model cannot edit and an
  /// [XlsxReadException] when the sheet cannot be read. Whatever it throws,
  /// nothing has changed.
  void addConditionalFormat(XlsxConditionalFormat format) {
    final WorksheetPart part = _editablePart('conditional formats');
    checkConditionalFormat(format);
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
    final int sheetNumber = _x14SheetNumber(part, format, firstPriority);
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
      final List<WorksheetConditionalFormat> written =
          <WorksheetConditionalFormat>[
            (format: format, dxfIds: dxfIds, firstPriority: firstPriority),
          ];
      final List<OpaqueXml> sources = renderElements(
        (XmlWriter w) => writeConditionalFormats(w, written, sheetNumber),
      );
      if (sources.isNotEmpty) {
        final List<XlsxConditionalRule> rules = normalizedConditionalFormat(
          format,
        ).rules;
        final CfEntry entry = CfEntry(format.ranges, <CfRuleEntry>[
          for (int i = 0; i < rules.length; i++)
            if (!isX14OnlyRule(rules[i]))
              CfRuleEntry(
                withRuleStyle(rules[i], null),
                firstPriority + i,
                dxfId: dxfIds[i],
                x14Id: rules[i] is XlsxDataBar
                    ? x14RuleId(sheetNumber, firstPriority + i - 1)
                    : null,
              ),
        ], sources.single);
        final CfBlock next = CfBlock(<GroupItem<CfEntry>>[
          ...?block?.items,
          GroupItem<CfEntry>(entry, sources.single),
        ]);
        editLayout(
          log,
          part,
          'conditionalFormatting',
          () => part.swapLayout('conditionalFormatting', block, next),
        );
      }
      final List<OpaqueXml> extension = renderElements(
        (XmlWriter w) => writeX14ConditionalFormats(w, written, sheetNumber),
      );
      if (extension.isNotEmpty) {
        final XmlNode? extLst = part.layoutElement('extLst') as XmlNode?;
        final XmlNode next = withX14Format(
          extLst,
          extension.single,
          part.elementPrefix,
        );
        editLayout(
          log,
          part,
          'extLst',
          () => part.swapLayout('extLst', extLst, next),
        );
      }
    });
  }

  /// The sheet number for `x14RuleId`: the sheet's place, raised until no id
  /// of the rules of [format], numbered from [firstPriority], is in use.
  int _x14SheetNumber(
    WorksheetPart part,
    XlsxConditionalFormat format,
    int firstPriority,
  ) {
    int number = _host.sheetIndexOf(this as XlsxSheet) + 1;
    if (!format.rules.any(hasX14Rule)) return number;
    final Set<String> used = part.usedX14Ids;
    bool taken() {
      for (int i = 0; i < format.rules.length; i++) {
        if (hasX14Rule(format.rules[i]) &&
            used.contains(x14RuleId(number, firstPriority + i - 1))) {
          return true;
        }
      }
      return false;
    }

    while (taken()) {
      number++;
    }
    return number;
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

  /// Removes the first format of [conditionalFormats] equal to [format]: its
  /// `<conditionalFormatting>` and its Excel 2010 rules, with an
  /// `x14:conditionalFormatting` left with no rule, the `ext` left with
  /// nothing and an `extLst` left with no `ext`. The other elements, readable
  /// or not, and the other rules of a shared element stay as written and in
  /// their order, and the `<dxf>`s of the styles part stay.
  ///
  /// [format] also matches as the writer writes it, so one built by hand
  /// matches the entry it was added as: a leading `=` of a formula, thresholds
  /// that are an icon set's defaults and a data bar's colors the writer fills
  /// do not count. The value the getter gives matches as it is, whatever the
  /// file wrote.
  ///
  /// Throws an [ArgumentError] when none is equal, a [StateError] for a
  /// sheet that is not a worksheet or has no part and an
  /// [XlsxReadException] when the sheet cannot be read. Whatever it throws,
  /// nothing has changed.
  void removeConditionalFormat(XlsxConditionalFormat format) {
    final WorksheetPart part = _editablePart('conditional formats');
    final XlsxConditionalFormat written = normalizedConditionalFormat(format);
    final List<JoinedFormat> formats = _joinedFormats(part);
    final int at = formats.indexWhere((JoinedFormat joined) {
      final XlsxConditionalFormat listed = _conditionalFormatOf(joined);
      return listed == format || listed == written;
    });
    if (at < 0) {
      throw ArgumentError.value(
        format,
        'format',
        'The sheet "$name" has no equal conditional format.',
      );
    }
    final JoinedFormat found = formats[at];
    final CfBlock? block = part.conditionalBlock;
    final X14Block? x14 = part.x14Block;
    // A half another rule still names stays, with that rule.
    final Set<String?> named = <String?>{
      for (final String id in part.unlistedX14Links) id.toUpperCase(),
      for (final JoinedFormat other in formats)
        if (!identical(other, found))
          for (final JoinedRule rule in other.rules)
            rule.entry?.x14Id?.toUpperCase(),
    };
    final Set<OpaqueXml> gone = <OpaqueXml>{
      for (final JoinedRule rule in found.rules)
        for (final X14Rule half in rule.halves)
          if (rule.entry == null ||
              !named.contains(rule.entry!.x14Id?.toUpperCase()))
            half.source,
    };
    final ChangeLog log = _host.log;
    log.transaction(() {
      if (found.item != null) {
        final CfBlock next = CfBlock(<GroupItem<CfEntry>>[
          for (final GroupItem<CfEntry> item in block!.items)
            if (!identical(item, found.item)) item,
        ]);
        editLayout(
          log,
          part,
          'conditionalFormatting',
          () => part.swapLayout('conditionalFormatting', block, next),
        );
      }
      if (x14 != null && gone.isNotEmpty) {
        final Object? extLst = part.layoutElement('extLst');
        editLayout(
          log,
          part,
          'extLst',
          () => part.swapLayout('extLst', extLst, x14.withoutRules(gone)),
        );
      }
    });
  }
}

/// The `dataValidations` holder of a sheet: each `<dataValidation>` as
/// [shiftedValidation] shifts it, removed when its `sqref` empties, the
/// group going with its last entry; `count` is recomputed when an entry
/// goes. An entry that changes is read again.
final class _ValidationHolder implements ReferenceHolder {
  _ValidationHolder(this._log, this._part, this._sheetName, this._unlexable);

  final ChangeLog _log;
  final WorksheetPart _part;
  final String Function() _sheetName;
  final void Function(String text) _unlexable;

  @override
  String get holderName => 'dataValidations';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    final ItemGroup<XlsxDataValidation>? group = _part.dataValidationGroup;
    if (group == null) return;
    final String host = _sheetName();
    bool changed = false;
    bool removed = false;
    final List<GroupItem<XlsxDataValidation>> items =
        <GroupItem<XlsxDataValidation>>[];
    for (final GroupItem<XlsxDataValidation> item in group.items) {
      if (!item.counted) {
        items.add(item);
        continue;
      }
      final OpaqueXml? next = shiftedValidation(
        item.source,
        mapper,
        host,
        _unlexable,
      );
      if (identical(next, item.source)) {
        items.add(item);
      } else if (next == null) {
        changed = removed = true;
      } else {
        changed = true;
        items.add(
          GroupItem<XlsxDataValidation>(readDataValidation(next).value, next),
        );
      }
    }
    if (!changed) return;
    final ItemGroup<XlsxDataValidation>? next = !items.any((i) => i.counted)
        ? null
        : removed
        ? group.withItems(items)
        : ItemGroup<XlsxDataValidation>(
            group.qualifiedName,
            group.localName,
            group.namespaces,
            group.attributes,
            items,
            edited: group.edited,
          );
    editLayout(
      _log,
      _part,
      'dataValidations',
      () => _part.swapLayout('dataValidations', group, next),
    );
  }
}

/// The `conditionalFormats` holder of a sheet: each
/// `<conditionalFormatting>` as [shiftedConditionalFormatting] shifts it,
/// and each `x14:conditionalFormatting` of the `extLst` as
/// [shiftedX14Element] does; one whose `sqref` empties goes, its rules'
/// `<dxf>`s staying in the styles part.
final class _ConditionalHolder implements ReferenceHolder {
  _ConditionalHolder(this._log, this._part, this._sheetName, this._unlexable);

  final ChangeLog _log;
  final WorksheetPart _part;
  final String Function() _sheetName;
  final void Function(String text) _unlexable;

  @override
  String get holderName => 'conditionalFormats';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    final String host = _sheetName();
    final CfBlock? block = _part.conditionalBlock;
    if (block != null) {
      bool changed = false;
      final List<GroupItem<CfEntry>> items = <GroupItem<CfEntry>>[];
      for (final GroupItem<CfEntry> item in block.items) {
        final OpaqueXml? next = shiftedConditionalFormatting(
          item.source,
          mapper,
          host,
          _unlexable,
        );
        if (identical(next, item.source)) {
          items.add(item);
          continue;
        }
        changed = true;
        if (next != null) {
          items.add(
            GroupItem<CfEntry>(readConditionalFormatting(next).value, next),
          );
        }
      }
      if (changed) {
        editLayout(
          _log,
          _part,
          'conditionalFormatting',
          () => _part.swapLayout(
            'conditionalFormatting',
            block,
            items.isEmpty ? null : CfBlock(items),
          ),
        );
      }
    }
    final X14Block? x14 = _part.x14Block;
    if (x14 == null) return;
    final Object? extLst = _part.layoutElement('extLst');
    final XmlNode? next = x14.withElements(
      (X14Element element) =>
          shiftedX14Element(element.source, mapper, host, _unlexable),
    );
    if (identical(next, extLst)) return;
    editLayout(
      _log,
      _part,
      'extLst',
      () => _part.swapLayout('extLst', extLst, next),
    );
  }
}
