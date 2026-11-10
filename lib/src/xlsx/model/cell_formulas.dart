/// The cell formulas of a sheet as a reference holder: plain, shared, array
/// and data-table formulas rewritten for a structural edit, and a shared
/// group unshared when its master is set.
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import '../../opc/change_log.dart';
import '../../opc/opaque_xml.dart';
import '../cell_ref.dart';
import '../formula/formula_rewrite.dart';
import '../formula/formula_translate.dart';
import '../formula/reference_shift.dart';
import '../limits.dart';
import '../range.dart';
import '../raw_cell.dart';
import 'cell_store.dart';
import 'primitives.dart';
import 'reference_holders.dart';

/// A formula cell found by a walk over the store, at its position before
/// the edit.
typedef _Found = ({int row, int column, RawCell cell});

/// The `cells` holder of a sheet.
///
/// It runs before the cells move: positions are those before the edit, and
/// the cells an edit deletes are left for the move to drop. A plain
/// formula's text goes through the rewriter; an array or data-table
/// formula's text, `ref` (and a data table's `r1`, `r2`) too, and Excel's
/// refusals apply (an edit that deletes part of one, or inserts strictly
/// inside one, throws a [StateError] naming its range). A shared group's
/// master text is rewritten as written at the master and its `ref` shifts
/// as a range; when the master's cell is deleted, the first remaining
/// follower (row major) becomes the master, its text the master's
/// translated by the offset. When the followers would no longer translate
/// to their rewritten formulas (a reference of the master stays while a
/// follower's moves), the group is unshared: every cell takes its own text.
/// A formula the lexer cannot read stays as read and is reported once per
/// cell and edit through [_warnUnlexable].
final class CellFormulaHolder implements ReferenceHolder {
  /// The holder of [_store]'s formulas on the sheet named by [_sheetName],
  /// recording to [_log].
  CellFormulaHolder(
    this._log,
    this._store,
    this._sheetName,
    this._warnUnlexable,
  );

  final ChangeLog _log;
  final CellStore _store;
  final String Function() _sheetName;
  final void Function(String cell) _warnUnlexable;

  @override
  String get holderName => 'cells';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    if (!_store.hasFormulas) return;
    final String host = _sheetName();
    final ReferenceShift? local =
        edit != null && edit.sheet.toLowerCase() == host.toLowerCase()
        ? edit
        : null;
    final List<_Found> found = <_Found>[
      for (final int row in _store.rowIndexes.toList()) ..._formulasOfRow(row),
    ];
    if (local != null) _refuse(found, local);
    final Set<int> unlexable = <int>{};
    String? rewrite(String text, int row, int column) => rewriteFormula(
      text,
      mapper,
      host,
      onUnlexable: (_) => unlexable.add(_key(row, column)),
      row: row,
      column: column,
    );
    final Map<String, List<_Found>> followers = <String, List<_Found>>{};
    for (final _Found f in found) {
      final RawFormula formula = f.cell.formula!;
      if (formula.type == FormulaType.shared && formula.ref == null) {
        final String? key = _siKey(formula.si);
        if (key != null) (followers[key] ??= <_Found>[]).add(f);
      }
    }
    for (final _Found f in found) {
      if (local != null && local.shiftCell(f.row, f.column) == null) continue;
      final RawFormula formula = f.cell.formula!;
      switch (formula.type) {
        case FormulaType.normal:
          final String? text = formula.text;
          final String? moved = text == null
              ? null
              : rewrite(text, f.row, f.column);
          if (moved != null) _set(f, _withText(formula, moved));
        case FormulaType.array || FormulaType.dataTable:
          _shiftGroupMaster(f, local, rewrite);
        case FormulaType.shared:
          break;
      }
    }
    for (final _Found f in found) {
      final RawFormula formula = f.cell.formula!;
      if (formula.type != FormulaType.shared || formula.ref == null) continue;
      final XlsxRange? range = _range(formula.ref!);
      if (range == null) {
        if ((followers[_siKey(formula.si)] ?? const <_Found>[]).isNotEmpty) {
          throw _orphaning(f.row, f.column, host, 'its range cannot be read');
        }
        continue;
      }
      final List<_Found> members = <_Found>[
        f,
        for (final _Found g
            in followers[_siKey(formula.si)] ?? const <_Found>[])
          if (_inside(range, g.row, g.column)) g,
      ]..sort(_rowMajor);
      _shiftShared(f, range, members, local, host, rewrite, unlexable);
    }
    for (final int k in unlexable.toList()..sort()) {
      _warnUnlexable(
        cellRef(k ~/ XlsxLimits.maxColumns, k % XlsxLimits.maxColumns),
      );
    }
  }

  List<_Found> _formulasOfRow(int row) {
    final List<_Found> out = <_Found>[];
    _store.forEachInRow(row, (int column, RawCell cell) {
      if (cell.formula != null) {
        out.add((row: row, column: column, cell: cell));
      }
    });
    return out;
  }

  /// Throws a [StateError] when [edit] deletes part of an array or data
  /// table, or inserts strictly inside one, as Excel refuses.
  static void _refuse(List<_Found> found, ReferenceShift edit) {
    final bool rows = edit.axis == ShiftAxis.rows;
    for (final _Found f in found) {
      final RawFormula formula = f.cell.formula!;
      if (formula.type != FormulaType.array &&
          formula.type != FormulaType.dataTable) {
        continue;
      }
      final XlsxRange? range = formula.ref == null
          ? XlsxRange(f.row, f.column)
          : _range(formula.ref!);
      if (range == null) continue;
      final int first = (rows ? range.firstRow : range.firstColumn) + 1;
      final int last = (rows ? range.lastRow : range.lastColumn) + 1;
      final bool refused;
      if (edit.count > 0) {
        refused = first < edit.index && edit.index <= last;
      } else {
        final int end = edit.index - edit.count - 1;
        final bool meets = edit.index <= last && end >= first;
        final bool covers = edit.index <= first && end >= last;
        refused = meets && !covers;
      }
      if (refused) {
        final String what = formula.type == FormulaType.array
            ? 'an array formula'
            : 'a data table';
        throw StateError(
          'Cannot change part of $what: the edit cuts through ${range.ref} '
          'on sheet "${edit.sheet}".',
        );
      }
    }
  }

  void _shiftGroupMaster(
    _Found f,
    ReferenceShift? local,
    String? Function(String, int, int) rewrite,
  ) {
    final RawFormula formula = f.cell.formula!;
    final String? text = formula.text;
    final String? movedText = text == null
        ? null
        : rewrite(text, f.row, f.column);
    String? movedRef;
    final String? ref = formula.ref;
    final XlsxRange? range = ref == null ? null : _range(ref);
    if (local != null && range != null) {
      final XlsxRange? shifted = local.shiftRange(range);
      if (shifted != null && shifted.ref != range.ref) movedRef = shifted.ref;
    }
    bool attributesChanged = false;
    final List<KeptAttribute> attributes = <KeptAttribute>[
      for (final KeptAttribute a in formula.attributes)
        if (formula.type == FormulaType.dataTable &&
            a.namespaceUri.isEmpty &&
            (a.qualifiedName == 'r1' || a.qualifiedName == 'r2'))
          switch (rewrite(a.value, f.row, f.column)) {
            null => a,
            final String v => () {
              attributesChanged = true;
              return (
                qualifiedName: a.qualifiedName,
                namespaceUri: a.namespaceUri,
                value: v,
              );
            }(),
          }
        else
          a,
    ];
    if (movedText == null && movedRef == null && !attributesChanged) return;
    _set(
      f,
      RawFormula(
        type: formula.type,
        text: movedText ?? text,
        ref: movedRef ?? ref,
        si: formula.si,
        attributes: attributesChanged ? attributes : formula.attributes,
      ),
    );
  }

  /// Rewrites the shared group whose master is [master] (of [range]) and
  /// whose cells, the master included, are [members] in row-major order.
  void _shiftShared(
    _Found master,
    XlsxRange range,
    List<_Found> members,
    ReferenceShift? local,
    String host,
    String? Function(String, int, int) rewrite,
    Set<int> unlexable,
  ) {
    final RawFormula formula = master.cell.formula!;
    final String? text = formula.text;
    ({int row, int column})? after(_Found f) => local == null
        ? (row: f.row, column: f.column)
        : local.shiftCell(f.row, f.column);
    final List<_Found> kept = <_Found>[
      for (final _Found m in members)
        if (after(m) != null) m,
    ];
    if (kept.isEmpty) return;
    final XlsxRange? newRange = local == null ? range : local.shiftRange(range);
    if (newRange == null) return;
    // The formula each kept cell must hold after the edit: the master's
    // text translated to the cell before the edit, then rewritten.
    final List<String> expected = <String>[];
    bool readable = text != null;
    if (readable) {
      for (final _Found m in kept) {
        final String? moved = translateFormula(
          text,
          m.row - master.row,
          m.column - master.column,
          host,
        );
        if (moved == null) {
          readable = false;
          break;
        }
        expected.add(rewrite(moved, m.row, m.column) ?? moved);
      }
    }
    if (!readable) {
      final bool masterKept =
          kept.first.row == master.row && kept.first.column == master.column;
      // No follower can take a text that cannot be translated.
      if (!masterKept) {
        throw _orphaning(
          master.row,
          master.column,
          host,
          'the edit deletes it and its formula cannot be read',
        );
      }
      if (text != null) unlexable.add(_key(master.row, master.column));
      // The text cannot be rewritten; the range still moves with the cells.
      if (masterKept && newRange.ref != formula.ref) {
        _set(master, _withRef(formula, newRange.ref));
      }
      return;
    }
    final _Found head = kept.first;
    final ({int row, int column}) headAt = after(head)!;
    final String headText = expected.first;
    bool consistent = true;
    for (int i = 1; i < kept.length; i++) {
      final ({int row, int column}) at = after(kept[i])!;
      final String? translated = translateFormula(
        headText,
        at.row - headAt.row,
        at.column - headAt.column,
        host,
      );
      if (translated != expected[i]) {
        consistent = false;
        break;
      }
    }
    if (!consistent) {
      for (int i = 0; i < kept.length; i++) {
        _set(
          kept[i],
          RawFormula(
            type: FormulaType.normal,
            text: expected[i],
            attributes: kept[i].cell.formula!.attributes,
          ),
        );
      }
      return;
    }
    final RawFormula headFormula = RawFormula(
      type: FormulaType.shared,
      text: headText,
      ref: newRange.ref,
      si: formula.si,
      attributes: formula.attributes,
    );
    final RawFormula current = head.cell.formula!;
    final bool promoted =
        head.row != master.row || head.column != master.column;
    if (promoted ||
        current.text != headFormula.text ||
        current.ref != headFormula.ref) {
      _set(head, headFormula);
    }
  }

  void _set(_Found f, RawFormula formula) => setStoredCell(
    _log,
    _store,
    f.row,
    f.column,
    withFormula(f.cell, formula),
  );
}

/// Unshares the shared group whose master is the cell at [row], [column] of
/// [store] on the sheet [hostSheet]: every follower takes its translated
/// text as a plain formula, as Excel writes the followers when a master is
/// edited. The master itself is left for the caller to set. Records to
/// [log]; call inside a transaction. Throws a [StateError] when the
/// master's text cannot be read, before anything changes.
void unshareSharedGroup(
  ChangeLog log,
  CellStore store,
  int row,
  int column,
  String hostSheet,
) {
  final RawFormula master = store.cellAt(row, column)!.formula!;
  final XlsxRange? range = _range(master.ref!);
  final String? key = _siKey(master.si);
  if (key == null) return;
  if (range == null) {
    bool followed = false;
    for (final int r in store.rowIndexes) {
      store.forEachInRow(r, (int c, RawCell cell) {
        final RawFormula? f = cell.formula;
        followed |=
            f != null &&
            f.type == FormulaType.shared &&
            f.ref == null &&
            _siKey(f.si) == key;
      });
      if (followed) {
        throw _orphaning(row, column, hostSheet, 'its range cannot be read');
      }
    }
    return;
  }
  final List<_Found> followers = <_Found>[];
  for (final int r in store.rowIndexes) {
    if (r < range.firstRow || r > range.lastRow) continue;
    store.forEachInRow(r, (int c, RawCell cell) {
      final RawFormula? f = cell.formula;
      if (f != null &&
          f.type == FormulaType.shared &&
          f.ref == null &&
          _siKey(f.si) == key &&
          _inside(range, r, c)) {
        followers.add((row: r, column: c, cell: cell));
      }
    });
  }
  if (followers.isEmpty) return;
  final String? text = master.text;
  final List<String> texts = <String>[];
  for (final _Found f in followers) {
    final String? moved = text == null
        ? null
        : translateFormula(text, f.row - row, f.column - column, hostSheet);
    if (moved == null) {
      throw StateError(
        'Cannot change the shared formula master at ${cellRef(row, column)} '
        'on sheet "$hostSheet": its formula cannot be read to give the '
        'other cells of its group their own formulas.',
      );
    }
    texts.add(moved);
  }
  for (int i = 0; i < followers.length; i++) {
    final _Found f = followers[i];
    setStoredCell(
      log,
      store,
      f.row,
      f.column,
      withFormula(
        f.cell,
        RawFormula(
          type: FormulaType.normal,
          text: texts[i],
          attributes: f.cell.formula!.attributes,
        ),
      ),
    );
  }
}

/// The refusal of an edit that would leave the followers of the shared
/// master at [row], [column] without a master.
StateError _orphaning(int row, int column, String sheet, String why) =>
    StateError(
      'Cannot change the shared formula master at ${cellRef(row, column)} '
      'on sheet "$sheet": $why, and other cells of its group follow it.',
    );

/// [cell] with [formula] in place of its own.
RawCell withFormula(RawCell cell, RawFormula formula) => RawCell(
  kind: cell.kind,
  style: cell.style,
  value: cell.value,
  formula: formula,
  inline: cell.inline,
  typeText: cell.typeText,
  attributes: cell.attributes,
  extraChildren: cell.extraChildren,
);

RawFormula _withText(RawFormula f, String text) => RawFormula(
  type: f.type,
  text: text,
  ref: f.ref,
  si: f.si,
  attributes: f.attributes,
);

RawFormula _withRef(RawFormula f, String ref) => RawFormula(
  type: f.type,
  text: f.text,
  ref: ref,
  si: f.si,
  attributes: f.attributes,
);

int _key(int row, int column) => row * XlsxLimits.maxColumns + column;

int _rowMajor(_Found a, _Found b) =>
    a.row != b.row ? a.row - b.row : a.column - b.column;

bool _inside(XlsxRange r, int row, int column) =>
    row >= r.firstRow &&
    row <= r.lastRow &&
    column >= r.firstColumn &&
    column <= r.lastColumn;

XlsxRange? _range(String ref) {
  try {
    return XlsxRange.parse(ref);
  } on ArgumentError {
    return null;
  }
}

/// [si] as a group key: the integer it writes, or `null` when it is none.
String? _siKey(String? si) {
  if (si == null) return null;
  final int? n = int.tryParse(si);
  return n == null || n < 0 ? null : '$n';
}
