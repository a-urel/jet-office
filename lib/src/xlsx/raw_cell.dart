/// A worksheet cell as the file stores it, before it is typed.
///
/// Not ported from Quds; written for jet_office.
///
/// The workbook model keeps what the file stores, not the reader's view of
/// it (decision 0009): a number in a date format stays the digits the file
/// wrote, and the `DateTime` is a view computed on access. A [RawCell] is
/// that stored form: the cell's kind (from its `t`), style index, `<v>` text
/// as written, formula, inline string element and the attributes no typed
/// reader owns. The row walk of `sheet_reader.dart` produces them; the cell
/// decoder's typed step (`decodeRawCell`) turns one into a value.
///
/// This file holds types only. Mapping a `t` attribute to a [RawCellKind]
/// and back happens in `read/cell_decoder.dart`, the one place that reads a
/// cell's `t` (decision 0007).
library;

import '../opc/opaque_xml.dart';

/// What a cell's `t` attribute says its `<v>` holds.
enum RawCellKind {
  /// `t` absent or `n`: a number.
  number,

  /// `t="s"`: an index into the shared-string table.
  sharedString,

  /// `t="b"`: `0` or `1`.
  boolean,

  /// `t="e"`: an error code such as `#N/A`.
  error,

  /// `t="str"`: a formula's text result.
  string,

  /// `t="inlineStr"`: a string held in the cell's `<is>`.
  inlineString,

  /// `t="d"`: an ISO 8601 date and time.
  isoDate,

  /// Any other `t`; the text is in [RawCell.typeText].
  unknown,
}

/// The type of a formula, the `t` attribute of its `<f>`.
enum FormulaType {
  /// A formula of its own cell (`t` absent, `normal` or unknown).
  normal,

  /// `t="shared"`: a master (with `ref`) or a follower of a shared formula.
  shared,

  /// `t="array"`: the master of an array formula.
  array,

  /// `t="dataTable"`: the master of a data table.
  dataTable,
}

/// A cell's `<f>` element as the file stores it.
final class RawFormula {
  /// A formula of [type] with [text], [ref], [si] and the other
  /// [attributes] of its `<f>`.
  const RawFormula({
    required this.type,
    this.text,
    this.ref,
    this.si,
    this.attributes = const <KeptAttribute>[],
  });

  /// The `t` of the `<f>`.
  final FormulaType type;

  /// The formula text, XML-string decoded (`_x0041_` is `A`), or `null`
  /// when the `<f>` is empty (a shared formula's follower, say).
  final String? text;

  /// The `ref` attribute: the range of a shared, array or data-table
  /// master, or `null`.
  final String? ref;

  /// The `si` attribute: the shared group's index as written, or `null`.
  final String? si;

  /// The `<f>`'s other attributes (`ca`, `aca`, `dt2D` and the like), in
  /// source order. Empty unless the row walk kept extras.
  final List<KeptAttribute> attributes;
}

/// A worksheet cell as the file stores it.
final class RawCell {
  /// A cell of [kind] with the given parts; every part is optional.
  const RawCell({
    required this.kind,
    this.style,
    this.value,
    this.formula,
    this.inline,
    this.typeText,
    this.attributes = const <KeptAttribute>[],
  });

  /// What the cell's `t` says its value is.
  final RawCellKind kind;

  /// The style index, the `s` attribute; `null` when there is no `s`, or
  /// when it is not a non-negative integer of at most 9 digits (then it is
  /// kept in [attributes]).
  final int? style;

  /// The `<v>` text as written, before any normalization: for a
  /// [RawCellKind.number] the digits (`1.50` stays `1.50`), for a
  /// [RawCellKind.sharedString] the index. `null` without a `<v>`.
  final String? value;

  /// The `<f>`, or `null` when the cell has none.
  final RawFormula? formula;

  /// The `<is>` element, as written, or `null`.
  final OpaqueXml? inline;

  /// The `t` text when [kind] is [RawCellKind.unknown]; otherwise `null`.
  final String? typeText;

  /// The attributes of the `<c>` no typed reader owns, in source order:
  /// `cm`, `vm`, `ph`, an invalid `s` and any unknown attribute. Empty
  /// unless the row walk kept extras.
  final List<KeptAttribute> attributes;

  /// Whether the cell has no value, formula or inline string. Such a cell
  /// may still carry a [style] or [attributes].
  bool get isEmpty => value == null && formula == null && inline == null;
}
