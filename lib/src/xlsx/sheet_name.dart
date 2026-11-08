/// Sheet-name sanitizing and uniqueness for the XLSX writer.
///
/// Ported from quds_office_engine `lib/src/builders/office_markup.dart` at commit 15c5d29.
/// Ported: `OfficeMarkup.sheetName`. What changed: names are made unique
/// (Excel compares them case-insensitively, Quds did not check), leading and
/// trailing apostrophes are removed, the reserved name `History` is avoided,
/// forbidden XML characters are scrubbed first, truncation never splits a
/// surrogate pair, and every change is reported as a warning.
library;

import '../common/name_key.dart';
import '../xml/xml_escape.dart';
import 'limits.dart';
import 'warnings.dart';

/// Sheet names Excel reserves for itself, as comparison keys.
final Set<String> _reservedKeys = <String>{sheetNameKey('History')};

const int _apostrophe = 0x27;

/// The key under which Excel considers two sheet names equal: see
/// [officeNameKey], which holds the folding for every Office name.
String sheetNameKey(String name) => officeNameKey(name);

bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

/// The first [max] UTF-16 code units of [text], less one when the cut would
/// separate a surrogate pair. [text] must hold no lone surrogates.
String _truncate(String text, int max) {
  if (text.length <= max) return text;
  int end = max;
  if (end > 0 && _isHigh(text.codeUnitAt(end - 1))) end--;
  return text.substring(0, end);
}

/// Removes surrounding whitespace and apostrophes until neither is left, so
/// `' ' x` becomes `x`.
String _trimStable(String text) {
  String current = text.trim();
  while (true) {
    int start = 0;
    int end = current.length;
    while (start < end && current.codeUnitAt(start) == _apostrophe) {
      start++;
    }
    while (end > start && current.codeUnitAt(end - 1) == _apostrophe) {
      end--;
    }
    final String next = current.substring(start, end).trim();
    if (next == current) return current;
    current = next;
  }
}

/// Turns the sheet names callers ask for into the unique, valid names of a
/// workbook.
///
/// One namer serves one workbook. [assign] is called once per sheet, in
/// order, and records a warning for each name it had to change.
final class SheetNamer {
  /// Creates a namer that reports to [warnings].
  SheetNamer(WarningCollector warnings) : _warnings = warnings;

  final WarningCollector _warnings;
  final Set<String> _taken = <String>{};
  int _assigned = 0;

  /// Returns the name the sheet [requested] gets in the file.
  ///
  /// The name is cleaned in this order: forbidden XML characters are removed;
  /// each of `[ ] : * ? / \` becomes `_`; surrounding whitespace and
  /// apostrophes are removed; an empty result becomes `Sheet{n}`, where n is
  /// the number of sheets named so far plus one; the result is cut to
  /// [XlsxLimits.maxSheetNameLength] UTF-16 code units without splitting a
  /// surrogate pair. Any change records
  /// [XlsxWarningCode.sheetNameChanged].
  ///
  /// The name must then differ from every earlier name and from the reserved
  /// `History`, ignoring case (see [sheetNameKey]). A clash appends ` (2)`,
  /// ` (3)` and so on, shortening the name so that it still fits; this
  /// records [XlsxWarningCode.sheetNameDuplicated], after any
  /// [XlsxWarningCode.sheetNameChanged] of the same call. Both warnings carry
  /// the final name as `sheet` and [requested] as `originalName`.
  String assign(String requested) {
    String name = scrubXmlText(requested).text;
    name = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), '_');
    name = _trimStable(name);
    name = _trimStable(_truncate(name, XlsxLimits.maxSheetNameLength));
    if (name.isEmpty) name = 'Sheet${_assigned + 1}';
    final bool changed = name != requested;

    String unique = name;
    final bool clash = _isTaken(unique);
    if (clash) {
      for (int n = 2; ; n++) {
        final String suffix = ' ($n)';
        // Trimmed again, so a cut that ends in a space (or an apostrophe)
        // never leaves a double space before the suffix.
        final String base = _trimStable(
          _truncate(name, XlsxLimits.maxSheetNameLength - suffix.length),
        );
        unique = '$base$suffix';
        if (!_isTaken(unique)) break;
      }
    }

    _taken.add(sheetNameKey(unique));
    _assigned++;
    if (changed) {
      _warnings.add(
        XlsxWarningCode.sheetNameChanged,
        sheet: unique,
        originalName: requested,
      );
    }
    if (clash) {
      _warnings.add(
        XlsxWarningCode.sheetNameDuplicated,
        sheet: unique,
        originalName: requested,
      );
    }
    return unique;
  }

  /// Records [name], a sheet the workbook already has, as taken without
  /// changing it or warning, so later [assign] calls avoid it. It counts as
  /// a named sheet for the `Sheet{n}` of an empty name.
  ///
  /// The workbook model calls it for each sheet of an opened file, whose
  /// names it keeps as they are, even when Excel would refuse them.
  void reserve(String name) {
    _taken.add(sheetNameKey(name));
    _assigned++;
  }

  bool _isTaken(String name) {
    final String key = sheetNameKey(name);
    return _taken.contains(key) || _reservedKeys.contains(key);
  }
}
