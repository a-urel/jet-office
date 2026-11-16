/// Template values: the data check, the lookups and the text of a value.
///
/// New in jet_office (decision 0024); quds_office_engine has no template
/// fill, so this is not ported from Quds. A value becomes text through
/// jet_core's `NumberFormatter`, the way the list export shows a cell, so a
/// filled document shows numbers and dates as Excel for Mac does.
library;

import 'package:jet_core/jet_core.dart';

import '../../common/image.dart';
import '../warnings.dart';

/// Throws [ArgumentError], naming the path (`data['a'][2]`), unless [data]
/// holds only values a template can take.
///
/// A value is a `String`, `num`, `FormatDecimal`, `bool`, `DateTime`,
/// `Duration`, `OfficeImage` or `null`, or a `List` or a `Map` with `String`
/// keys of such values. A `Map` or `List` that contains itself, directly or
/// through others, is refused; one shared twice side by side is fine.
void checkTemplateData(Map<String, Object?> data) {
  _check(data, 'data', Set<Object>.identity(), Set<Object>.identity());
}

void _check(Object? value, String path, Set<Object> onPath, Set<Object> done) {
  if (value == null ||
      value is String ||
      value is num ||
      value is FormatDecimal ||
      value is bool ||
      value is DateTime ||
      value is Duration ||
      value is OfficeImage) {
    return;
  }
  if (value is Map || value is List) {
    if (done.contains(value)) return;
    if (!onPath.add(value)) {
      throw ArgumentError.value(
        path,
        'data',
        'The value at $path contains itself.',
      );
    }
    if (value is Map) {
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final Object? key = entry.key;
        if (key is! String) {
          throw ArgumentError.value(
            path,
            'data',
            'A key of the map at $path is not a String: $key '
                '(${key.runtimeType}).',
          );
        }
        _check(entry.value, "$path['$key']", onPath, done);
      }
    } else {
      final List<Object?> list = value as List<Object?>;
      for (int i = 0; i < list.length; i++) {
        _check(list[i], '$path[$i]', onPath, done);
      }
    }
    onPath.remove(value);
    done.add(value);
    return;
  }
  throw ArgumentError.value(
    path,
    'data',
    'The value at $path is a ${value.runtimeType}; a template takes a String, '
        'num, FormatDecimal, bool, DateTime, Duration, OfficeImage, null, or '
        'a List or Map of them.',
  );
}

/// The result of a lookup in the data.
sealed class Lookup {
  const Lookup();
}

/// The data has the value, which may be `null`.
final class Found extends Lookup {
  /// Creates a found result.
  const Found(this.value);

  /// The value.
  final Object? value;
}

/// The data has no value there.
final class Missing extends Lookup {
  /// Creates a missing result.
  const Missing();
}

/// Looks [path] up in [scope], walking `Map` segments; a segment that meets
/// a value that is not a map, or a key the map lacks, is [Missing].
Lookup lookupPath(Map<Object?, Object?> scope, List<String> path) {
  Object? current = scope;
  for (final String segment in path) {
    if (current is! Map) return const Missing();
    if (!current.containsKey(segment)) return const Missing();
    current = current[segment];
  }
  return Found(current);
}

/// Looks the one key [key] up in [scope], as a `MERGEFIELD` does: the key
/// is the whole name, dots included.
Lookup lookupKey(Map<Object?, Object?> scope, String key) =>
    scope.containsKey(key) ? Found(scope[key]) : const Missing();

/// What a value does to a section (spec section 4, T2 plan Ruling 5).
enum SectionEffect {
  /// The content repeats, one copy per item, the item the innermost scope.
  repeat,

  /// The content goes, with both tags.
  remove,

  /// The content shows once. For `{{#name}}` the value is pushed as the
  /// innermost scope, so `{{.}}` shows it; for `{{^name}}` no scope is
  /// pushed.
  once,

  /// The content shows once with the map as the innermost scope.
  scope,
}

/// What [value], found in the data, does to a section: `{{#name}}`, or
/// `{{^name}}` when [inverted].
///
/// A non-empty `List` repeats, its elements the items; a `Map`, empty too, is
/// a scope, the map the one item; `false`, `null`, `''` and an empty `List`
/// remove, with no items; any other value (`true`, any `num`, `0` too, a
/// `FormatDecimal`, a non-empty `String`, a `DateTime`, a `Duration`, an
/// `OfficeImage`) shows once, the value the one item. An inverted section
/// shows once, with no items, exactly when the section would remove, and
/// removes otherwise. A missing name is not a value: the caller handles it
/// (Ruling 12). Never throws.
({SectionEffect effect, List<Object?> items}) sectionEffect(
  Object? value, {
  required bool inverted,
}) {
  final bool removes =
      value == null ||
      value == false ||
      (value is String && value.isEmpty) ||
      (value is List && value.isEmpty);
  if (inverted) {
    return removes
        ? (effect: SectionEffect.once, items: const <Object?>[])
        : (effect: SectionEffect.remove, items: const <Object?>[]);
  }
  if (removes) return (effect: SectionEffect.remove, items: const <Object?>[]);
  if (value is List) {
    return (effect: SectionEffect.repeat, items: List<Object?>.of(value));
  }
  if (value is Map) {
    return (effect: SectionEffect.scope, items: <Object?>[value]);
  }
  return (effect: SectionEffect.once, items: <Object?>[value]);
}

/// Looks [path] up through [scopes], the data first and the innermost scope
/// last (Ruling 6).
///
/// The first segment is looked up in each scope from the innermost outward,
/// skipping a scope that is not a `Map`; the first map that has the key
/// decides, and the rest of the path is walked in it with no further
/// fallback, [Missing] if it breaks. An empty [path] is the innermost scope
/// itself, as `{{.}}` reads it. No scopes find nothing. Never throws.
Lookup lookupInScopes(List<Object?> scopes, List<String> path) {
  if (scopes.isEmpty) return const Missing();
  if (path.isEmpty) return Found(scopes.last);
  for (int i = scopes.length - 1; i >= 0; i--) {
    final Object? scope = scopes[i];
    if (scope is Map && scope.containsKey(path.first)) {
      return lookupPath(scope, path);
    }
  }
  return const Missing();
}

/// Looks the one key [key] up through [scopes], as a `MERGEFIELD` does: the
/// key is the whole name, dots included, looked up in each `Map` scope from
/// the innermost outward (Ruling 6). Never throws.
Lookup lookupKeyInScopes(List<Object?> scopes, String key) {
  for (int i = scopes.length - 1; i >= 0; i--) {
    final Object? scope = scopes[i];
    if (scope is Map && scope.containsKey(key)) return Found(scope[key]);
  }
  return const Missing();
}

/// A value as text, or the reason it is not text.
final class ValueText {
  /// Creates a result.
  const ValueText({this.text, this.problem, this.formatWarning});

  /// The text, or `null` when the value is not text.
  final String? text;

  /// Why [text] is `null`: `templateValueNotText`.
  final DocxWarningCode? problem;

  /// The formatter's warning for the format code, when it gave one.
  final FormatWarning? formatWarning;
}

/// The text of [value] with the Excel format code [format].
///
/// A `String` is itself without a [format]; with one it goes through the
/// formatter, which applies a code to text as Excel does. A `num`,
/// `FormatDecimal` or `bool` shows with [format] or `General`; a `DateTime`
/// without a code shows as Excel's built-in format 14, a `Duration` as
/// `[h]:mm:ss`; `null` is the empty text. A `List`, a `Map` or an
/// `OfficeImage` is not text.
ValueText valueText(Object? value, String? format, NumberFormatter formatter) {
  if (value == null) return const ValueText(text: '');
  if (value is String && format == null) return ValueText(text: value);
  if (value is String ||
      value is num ||
      value is FormatDecimal ||
      value is bool ||
      value is DateTime ||
      value is Duration) {
    final FormattedValue result;
    if (format != null) {
      result = formatter.format(value, numberFormat: format);
    } else if (value is DateTime) {
      result = formatter.format(value, numberFormatId: 14);
    } else if (value is Duration) {
      result = formatter.format(value, numberFormat: '[h]:mm:ss');
    } else {
      result = formatter.format(value);
    }
    return ValueText(text: result.text, formatWarning: result.warning);
  }
  return const ValueText(problem: DocxWarningCode.templateValueNotText);
}
