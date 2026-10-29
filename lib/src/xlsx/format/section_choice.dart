/// Which section of a format code a value takes.
///
/// New in jet_office; Quds has no number format engine. A code holds up to
/// four sections, for positive numbers, negative numbers, zero and text.
/// The text section is always the last: the fourth, or with fewer the last
/// one when it holds `@` and has no condition (SheetJS SSF's rule; Microsoft
/// puts text last). Numbers then choose among the sections before it, by
/// the rules for that many sections. With `[...]` conditions on the first
/// two sections the implied rules are replaced: the first section whose
/// condition holds wins, then the second if it holds or has none, then the
/// third. A code whose only section has a condition is read as that
/// section followed by `General`, as Excel repairs `[>100]0` to
/// `[>100]0;General`. The rules follow Excel for Mac
/// as described in `docs/decisions/0008`.
library;

import 'excel_number.dart';
import 'format_code.dart';

/// The section the number [value] takes in [format], or null when none does
/// (every conditional section fails and there is no third to fall back on).
///
/// The result's `value` is the absolute value of [value], and `showMinus`
/// says whether the renderer prints a `-` before it: true for a negative
/// number the section does not write a sign for. A section chosen for a
/// negative number by its position (the second of a code without
/// conditions) or by a condition that only negatives meet writes its own
/// sign, so `showMinus` is false there.
///
/// The text section ([chooseTextSection]) never takes a number: `0;@`
/// shows -5 as `-5` with its one number section, and `0;-0;@` shows 0 with
/// the first section, as a two-section code would. A code whose only
/// section holds `@` is how a number is shown as `General`; this returns
/// that section and the renderer decides. An invalid [format] is not
/// special-cased: callers render it as `General` first.
({FormatSection section, bool showMinus, ExcelNumber value})?
chooseNumberSection(ParsedFormat format, ExcelNumber value) {
  final List<FormatSection> all = format.sections;
  final List<FormatSection> sections =
      all.length == 1 && all[0].condition != null
      ? <FormatSection>[all[0], _general]
      : all.length > 1 && all.length < 4 && _isText(all.last)
      ? all.sublist(0, all.length - 1)
      : all;
  final int sign = value.isZero ? 0 : (value.negative ? -1 : 1);
  final ExcelNumber magnitude = value.abs();

  ({FormatSection section, bool showMinus, ExcelNumber value}) pick(
    FormatSection section,
    bool showMinus,
  ) => (section: section, showMinus: showMinus, value: magnitude);

  final bool conditional =
      sections[0].condition != null ||
      (sections.length > 1 && sections[1].condition != null);

  if (!conditional) {
    if (sections.length == 1) return pick(sections[0], sign < 0);
    if (sign < 0) return pick(sections[1], false);
    if (sign == 0 && sections.length >= 3) return pick(sections[2], false);
    return pick(sections[0], false);
  }

  final FormatSection first = sections[0];
  if (_holds(first.condition, value)) {
    return pick(first, sign < 0 && !_onlyNegatives(first.condition));
  }
  if (sections.length > 1) {
    final FormatSection second = sections[1];
    if (_holds(second.condition, value)) {
      final bool minus = second.condition == null && sections.length == 2
          ? _autoMinusAfter(first.condition!)
          : !_onlyNegatives(second.condition);
      return pick(second, sign < 0 && minus);
    }
  }
  if (sections.length > 2) return pick(sections[2], sign < 0);
  return null;
}

/// The `General` section Excel appends to a code whose only section has a
/// condition.
final FormatSection _general = FormatSection(const <FormatToken>[
  GeneralToken(),
]);

/// The section text takes in [format], or null to show the text unchanged.
///
/// That is the fourth section when there is one; otherwise the last
/// section if it holds an `@` and has no condition, never an earlier one
/// (`"x"@;0` shows text unchanged). A conditional section never takes
/// text.
FormatSection? chooseTextSection(ParsedFormat format) {
  final List<FormatSection> sections = format.sections;
  if (sections.length >= 4) return sections[3];
  return _isText(sections.last) ? sections.last : null;
}

/// Whether [section], the last of fewer than four, is the text section.
bool _isText(FormatSection section) =>
    section.hasText && section.condition == null;

/// Whether [condition] holds for [value]; no condition always holds.
bool _holds(FormatCondition? condition, ExcelNumber value) {
  if (condition == null) return true;
  final int c = value.compareTo(condition.value);
  return switch (condition.op) {
    '=' => c == 0,
    '<' => c < 0,
    '>' => c > 0,
    '<=' => c <= 0,
    '>=' => c >= 0,
    '<>' => c != 0,
    _ => false,
  };
}

/// Whether [condition] can only be met by negative numbers, so the section
/// writes its own sign: `<x` with x <= 0, `<=x` or `=x` with x < 0.
bool _onlyNegatives(FormatCondition? condition) {
  if (condition == null) return false;
  final ExcelNumber v = condition.value;
  final bool isNegative = v.negative && !v.isZero;
  return switch (condition.op) {
    '<' => isNegative || v.isZero,
    '<=' || '=' => isNegative,
    _ => false,
  };
}

/// Whether the unconditioned second section of a two-section code prints the
/// automatic minus, given the first section's [condition]: only for `=`, `>`
/// or `>=` against a value of zero or more.
bool _autoMinusAfter(FormatCondition condition) {
  final ExcelNumber v = condition.value;
  final bool nonNegative = v.isZero || !v.negative;
  return nonNegative &&
      (condition.op == '=' || condition.op == '>' || condition.op == '>=');
}
