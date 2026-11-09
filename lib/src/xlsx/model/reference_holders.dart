/// The holders of cell references in a workbook, which a structural edit
/// (rows or columns inserted or deleted, a sheet renamed or moved) rewrites
/// through a [ReferenceMapper].
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import '../../opc/change_log.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../formula/formula_reference.dart';
import '../formula/formula_rewrite.dart';
import '../formula/reference_shift.dart';
import '../limits.dart';
import '../range.dart';
import 'defined_names.dart' show DefinedNameHolder;
import 'item_group.dart' show readerOf, rewrittenElement;
import 'validation_elements.dart' show parseSqref;
import 'workbook_part.dart';
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
/// Tasks 6 to 9 of W5 replace these one by one.
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
  'cell_formulas.dart': 'cells',
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
  ///
  /// [workbookPart] gives the workbook part whose defined names the
  /// `definedNames` holder rewrites; without it that holder is pending.
  ReferenceRegistry(
    this._log,
    this._sheets, {
    WorkbookPart Function()? workbookPart,
  }) : _workbookHolders = <ReferenceHolder>[
         for (final String name in workbookHolderNames)
           if (name == 'definedNames' && workbookPart != null)
             DefinedNameHolder(_log, workbookPart)
           else
             PendingReferenceHolder(name),
       ];

  final ChangeLog _log;
  final List<XlsxSheet> Function() _sheets;

  final List<ReferenceHolder> _workbookHolders;

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

/// What [spliceElement] does to one element: give attributes without a
/// namespace new values, replace its text, or remove it.
final class SpliceEdit {
  /// An edit setting [attributes] (raw values, escaped here), replacing the
  /// text through [text], or removing the element when [remove] is true.
  const SpliceEdit({
    this.attributes = const <String, String>{},
    this.text,
    this.remove = false,
  });

  /// Removes the element.
  static const SpliceEdit removal = SpliceEdit(remove: true);

  /// New values of attributes the element has; one it lacks is not added.
  final Map<String, String> attributes;

  /// The new markup (already escaped) of the element's text, given the text
  /// as read (entities decoded), or `null` to keep it. Not called for an
  /// element with child elements or none of its own.
  final String? Function(String text)? text;

  /// Whether the element goes.
  final bool remove;
}

/// [element] with each descendant (and itself, at level 0) edited as [edit]
/// says, every other character copied as read; [element] itself when
/// nothing changes. [edit] gets the reader on each start element with its
/// level below [element], and must not move it. The root is never removed.
OpaqueXml spliceElement(
  OpaqueXml element,
  SpliceEdit? Function(XmlPullReader r, int level) edit,
) {
  final XmlPullReader r = readerOf(element);
  final int rootDepth = r.depth;
  final int start = r.eventStart;
  final StringBuffer out = StringBuffer();
  int cursor = start;
  bool changed = false;
  void copyTo(int at) {
    out.write(r.sourceText(cursor, at));
    cursor = at;
  }

  bool first = true;
  while (first || r.next()) {
    final bool atRoot = first;
    first = false;
    if (r.eventType == XmlEventType.endElement && r.depth < rootDepth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    final SpliceEdit? e = edit(r, r.depth - rootDepth);
    if (e == null) {
      if (atRoot && r.isEmptyElement) {
        r.next();
        break;
      }
      continue;
    }
    if (e.remove && !atRoot) {
      copyTo(r.eventStart);
      r.skip();
      cursor = r.eventEnd;
      changed = true;
      continue;
    }
    final String tag = r.sourceText(r.eventStart, r.eventEnd);
    final String newTag = _withAttributes(tag, e.attributes);
    if (newTag != tag) {
      copyTo(r.eventStart);
      out.write(newTag);
      cursor = r.eventEnd;
      changed = true;
    }
    final String? Function(String text)? text = e.text;
    if (r.isEmptyElement) {
      r.next();
      if (atRoot) break;
      continue;
    }
    if (text == null) continue;
    final int textStart = r.eventEnd;
    final int depth = r.depth;
    final StringBuffer read = StringBuffer();
    bool nested = false;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType == XmlEventType.startElement) {
        nested = true;
      } else if (r.eventType == XmlEventType.characters ||
          r.eventType == XmlEventType.cdata) {
        read.write(r.text);
      }
    }
    final String? markup = nested ? null : text(read.toString());
    if (markup != null) {
      copyTo(textStart);
      out.write(markup);
      cursor = r.eventStart;
      changed = true;
    }
    if (atRoot) break;
  }
  if (!changed) return element;
  copyTo(r.eventEnd);
  return rewrittenElement(element, out.toString());
}

/// [tag], a start tag as written, with the attributes of [values] (without
/// a namespace) holding the new values.
String _withAttributes(String tag, Map<String, String> values) {
  String next = tag;
  values.forEach((String name, String value) {
    final RegExp pattern = RegExp(
      '(\\s${RegExp.escape(name)}\\s*=\\s*)("[^"]*"|\'[^\']*\')',
    );
    next = next.replaceFirstMapped(
      pattern,
      (Match m) => '${m[1]}"${escapeXmlAttribute(value)}"',
    );
  });
  return next;
}

/// The formula [text] of something that covers [sqref] (before the edit)
/// and [nextSqref] (after it), stored relative to the first cell of its
/// first range as Excel stores the formulas of validations and rules,
/// rewritten for [mapper]; `null` when it does not change.
///
/// On a row or column edit of [host], a relative row (column) of a
/// reference to [host] keeps its offset from that first cell, so each
/// covered cell keeps testing what it tested; an absolute one shifts as
/// [ReferenceShift] shifts it (a `$` range as a span, a lone `$` end as one
/// row or column, `#REF!` when deleted). Every other reference, and every
/// reference for any other edit, goes through [mapper] as written.
String? rewriteAnchoredFormula(
  String text,
  ReferenceMapper mapper,
  String host,
  String sqref,
  String nextSqref, {
  void Function(String formula)? onUnlexable,
}) {
  final ({int row, int column})? from = _firstCell(sqref);
  final ({int row, int column})? to = _firstCell(nextSqref);
  final ReferenceMapper used =
      mapper is ReferenceShift &&
          mapper.sheet.toLowerCase() == host.toLowerCase() &&
          from != null &&
          to != null
      ? _AnchoredShift(
          mapper,
          host,
          mapper.axis == ShiftAxis.rows
              ? to.row - from.row
              : to.column - from.column,
        )
      : mapper;
  return rewriteFormula(text, used, host, onUnlexable: onUnlexable);
}

/// The first cell (1-based) of the first range of [sqref], or `null`.
({int row, int column})? _firstCell(String sqref) =>
    switch (parseSqref(sqref)) {
      final List<XlsxRange> ranges => (
        row: ranges.first.firstRow + 1,
        column: ranges.first.firstColumn + 1,
      ),
      null => null,
    };

/// [_shift] with the relative rows (columns) of references to [_host]
/// moved by [_delta] instead: see [rewriteAnchoredFormula].
final class _AnchoredShift implements ReferenceMapper {
  _AnchoredShift(this._shift, this._host, this._delta);

  final ReferenceShift _shift;
  final String _host;
  final int _delta;

  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String hostSheet) {
    final bool local =
        ref.externalIndex == null &&
        (ref.sheet == null ||
            ref.lastSheet == null &&
                ref.sheet!.toLowerCase() == _host.toLowerCase());
    if (!local) return _shift.mapReference(ref, hostSheet);
    final bool rows = _shift.axis == ShiftAxis.rows;
    final int? first = rows ? ref.firstRow : ref.firstColumn;
    final int? last = rows ? ref.lastRow : ref.lastColumn;
    if (first == null || last == null) {
      return _shift.mapReference(ref, hostSheet);
    }
    final bool absFirst = rows ? ref.absFirstRow : ref.absFirstColumn;
    final bool absLast = rows ? ref.absLastRow : ref.absLastColumn;
    if (absFirst && absLast) return _shift.mapReference(ref, hostSheet);
    final int limit = rows ? XlsxLimits.maxRows : XlsxLimits.maxColumns;
    int? moved(int value, bool absolute) {
      if (absolute) {
        final XlsxRange? r = _shift.shiftRange(
          rows ? XlsxRange(value - 1, 0) : XlsxRange(0, value - 1),
        );
        if (r == null) return null;
        return (rows ? r.firstRow : r.firstColumn) + 1;
      }
      final int next = value + _delta;
      return next < 1 || next > limit ? null : next;
    }

    final int? f = moved(first, absFirst);
    final int? l = moved(last, absLast);
    if (f == null || l == null) return const FormulaReferenceResult.refError();
    if (f == first && l == last) return null;
    return FormulaReferenceResult.to(
      FormulaReference(
        form: ref.form,
        sheet: ref.sheet,
        lastSheet: ref.lastSheet,
        externalIndex: ref.externalIndex,
        firstRow: rows ? f : ref.firstRow,
        lastRow: rows ? l : ref.lastRow,
        firstColumn: rows ? ref.firstColumn : f,
        lastColumn: rows ? ref.lastColumn : l,
        absFirstRow: ref.absFirstRow,
        absLastRow: ref.absLastRow,
        absFirstColumn: ref.absFirstColumn,
        absLastColumn: ref.absLastColumn,
      ),
    );
  }

  @override
  String? mapSheetName(String sheet) => null;

  @override
  String? mapStructured(String table, String spec, String hostSheet) => null;
}

/// [text], a formula decoded as read, rewritten by [rewrite] (on its
/// `_xHHHH_`-decoded form) and escaped as the writer escapes a formula;
/// `null` when it does not change.
String? rewrittenFormulaMarkup(String text, String? Function(String) rewrite) {
  final String? next = rewrite(decodeXstring(text));
  return next == null ? null : escapeFormulaText(scrubXmlText(next).text);
}
