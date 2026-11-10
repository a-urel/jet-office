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
import '../formula/formula_rewrite.dart';
import '../formula/reference_shift.dart';
import '../read/package_reader.dart';
import '../warnings.dart';
import 'chart_references.dart';
import 'defined_names.dart' show DefinedNameHolder;
import 'item_group.dart' show readerOf, rewrittenElement;
import 'opaque_references.dart';
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
  'sparklines',
];

/// The holder names of the workbook, applied after every sheet's.
const List<String> workbookHolderNames = <String>[
  'definedNames',
  'charts',
  'opaqueParts',
];

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
  'xlsx_sheet_notes.dart': 'notes',
  'opaque_references.dart': 'opaqueParts',
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
  /// [reader] gives the package whose charts and opaque parts the `charts`
  /// and `opaqueParts` holders rewrite or warn about, into [warnings];
  /// without both those holders are pending.
  ReferenceRegistry(
    this._log,
    this._sheets, {
    WorkbookPart Function()? workbookPart,
    PackageReader Function()? reader,
    WarningCollector? warnings,
  }) : _warnings = warnings {
    final OpaqueScan? scan = _scan = reader == null || warnings == null
        ? null
        : OpaqueScan(_log, reader, _sheets, _warnPart);
    _workbookHolders = <ReferenceHolder>[
      for (final String name in workbookHolderNames)
        if (name == 'definedNames' && workbookPart != null)
          DefinedNameHolder(_log, workbookPart)
        else if (name == 'charts' && scan != null)
          ChartReferences(scan)
        else if (name == 'opaqueParts' && scan != null)
          OpaqueReferences(scan)
        else
          PendingReferenceHolder(name),
    ];
  }

  final ChangeLog _log;
  final List<XlsxSheet> Function() _sheets;
  final WarningCollector? _warnings;

  /// What the `charts` and `opaqueParts` holders read, once per edit.
  OpaqueScan? _scan;

  late final List<ReferenceHolder> _workbookHolders;

  /// The warnings of the [apply] running, and its mapper and edit.
  List<XlsxWarning>? _applied;
  ReferenceMapper? _mapper;

  /// The workbook-level holders.
  List<ReferenceHolder> get workbookHolders => _workbookHolders;

  /// Every holder of every sheet (loading each sheet), then of the workbook.
  Iterable<ReferenceHolder> holders() => <ReferenceHolder>[
    for (final XlsxSheet sheet in _sheets()) ...sheetReferenceHolders(sheet),
    ..._workbookHolders,
  ];

  /// Runs [mapper] over every holder in one transaction: if one throws,
  /// every change already made is reverted. Returns the warnings the edit
  /// gave: a formula that could not be read (`formulaUnlexable`) and a part
  /// holding a reference the edit could not fix (`referenceNotShifted`,
  /// once per part, its detail `<part>: <edit>`).
  List<XlsxWarning> apply(ReferenceMapper mapper, ReferenceShift? edit) {
    final List<XlsxWarning> applied = _applied = <XlsxWarning>[];
    _mapper = mapper;
    final int before = _warnings?.warnings.length ?? 0;
    _scan?.begin();
    try {
      _log.transaction(() {
        final List<ReferenceHolder> all = holders().toList();
        for (final ReferenceHolder holder in all) {
          if (holder is PreparingReferenceHolder) {
            holder.prepare(mapper, edit);
          }
        }
        for (final ReferenceHolder holder in all) {
          holder.shiftReferences(mapper, edit);
        }
      });
    } finally {
      _applied = null;
      _mapper = null;
    }
    final List<XlsxWarning> all = _warnings?.warnings ?? const <XlsxWarning>[];
    return <XlsxWarning>[
      for (int i = before; i < all.length; i++)
        if (!applied.contains(all[i])) all[i],
      ...applied,
    ];
  }

  /// Reports the part [part] (a part name without a leading `/`) as holding
  /// a reference the running edit could not fix.
  void _warnPart(String part) {
    final WarningCollector? warnings = _warnings;
    final ReferenceMapper? mapper = _mapper;
    final List<XlsxWarning>? applied = _applied;
    if (warnings == null || mapper == null || applied == null) return;
    final String sheet = editedSheetOf(mapper);
    final String detail = '/$part: ${describeEdit(mapper)}';
    warnings.add(
      XlsxWarningCode.referenceNotShifted,
      sheet: sheet,
      detail: detail,
    );
    for (final XlsxWarning w in warnings.warnings.reversed) {
      if (w.code == XlsxWarningCode.referenceNotShifted &&
          w.sheet == sheet &&
          w.detail == detail) {
        if (!applied.contains(w)) applied.add(w);
        return;
      }
    }
    // An eleventh detail joins the warning without one.
    for (final XlsxWarning w in warnings.warnings.reversed) {
      if (w.code == XlsxWarningCode.referenceNotShifted && w.sheet == sheet) {
        if (!applied.contains(w)) applied.add(w);
        return;
      }
    }
  }
}

/// A holder that looks at the workbook before any holder shifts (to see
/// what the edit changes, a table's size, say).
abstract interface class PreparingReferenceHolder implements ReferenceHolder {
  /// Called with the edit's [mapper] and [edit] before any holder's
  /// [shiftReferences].
  void prepare(ReferenceMapper mapper, ReferenceShift? edit);
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
    this.markup,
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

  /// Markup (an element written in the same scope) that takes the place of
  /// the whole element, or `null`.
  final String? markup;
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
    if ((e.remove || e.markup != null) && !atRoot) {
      copyTo(r.eventStart);
      r.skip();
      cursor = r.eventEnd;
      if (e.markup != null) out.write(e.markup);
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

/// The source of [r] (a reader at the start of a document) with each start
/// element edited as [edit] says, every other character copied as read;
/// `null` when nothing changes. [edit] gets the reader on each start
/// element and must not move it. Throws what the reader throws on XML that
/// is not well formed.
String? spliceDocument(
  XmlPullReader r,
  SpliceEdit? Function(XmlPullReader r) edit,
) {
  final StringBuffer out = StringBuffer();
  int cursor = 0;
  bool changed = false;
  void copyTo(int at) {
    out.write(r.sourceText(cursor, at));
    cursor = at;
  }

  while (r.next()) {
    if (r.eventType != XmlEventType.startElement) continue;
    final SpliceEdit? e = edit(r);
    if (e == null) continue;
    if (e.remove || e.markup != null) {
      copyTo(r.eventStart);
      r.skip();
      cursor = r.eventEnd;
      if (e.markup != null) out.write(e.markup);
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
    if (r.isEmptyElement || text == null) continue;
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
  }
  if (!changed) return null;
  copyTo(r.sourceLength);
  return out.toString();
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

/// [text], a formula decoded as read, rewritten by [rewrite] (on its
/// `_xHHHH_`-decoded form) and escaped as the writer escapes a formula;
/// `null` when it does not change.
String? rewrittenFormulaMarkup(String text, String? Function(String) rewrite) {
  final String? next = rewrite(decodeXstring(text));
  return next == null ? null : escapeFormulaText(scrubXmlText(next).text);
}
