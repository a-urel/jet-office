/// The Word `MERGEFIELD` instruction: its name, its switches and the
/// translation of `\@` and `\#` pictures to Excel format codes.
///
/// New in jet_office (decision 0024); quds_office_engine has no template
/// fill, so this is not ported from Quds. Parsing is pure and never throws.
/// A switch the fill cannot honour is kept as written in
/// [MergeField.unsupported], so the caller can warn.
library;

import 'package:jet_core/jet_core.dart';

/// A parsed `MERGEFIELD` instruction.
final class MergeField {
  /// Creates a merge field.
  const MergeField({
    required this.name,
    this.before,
    this.after,
    this.dateFormat,
    this.numberFormat,
    this.casing,
    this.unsupported = const <String>[],
  });

  /// The field name as written, unquoted.
  final String name;

  /// The `\b` text: written before a non-empty value.
  final String? before;

  /// The `\f` text: written after a non-empty value.
  final String? after;

  /// The `\@` picture as an Excel format code, or `null`.
  final String? dateFormat;

  /// The `\#` picture as an Excel format code, or `null`.
  final String? numberFormat;

  /// `Upper`, `Lower`, `FirstCap` or `Caps` from `\*`, or `null`.
  final String? casing;

  /// Switches that are not honoured, as written (`\v`, an untranslatable
  /// `\@` or `\#`, another `\*`). `\* MERGEFORMAT` and `\* CHARFORMAT` are
  /// dropped, not listed.
  final List<String> unsupported;
}

/// One word of an instruction: its text without quotes and as written.
class _Word {
  _Word(this.text, this.raw);
  final String text;
  final String raw;
}

List<_Word> _words(String s) {
  final List<_Word> words = <_Word>[];
  int i = 0;
  while (i < s.length) {
    final int c = s.codeUnitAt(i);
    if (c == 0x20 || c == 0xA0 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    final int start = i;
    if (c == 0x22) {
      i++;
      final int open = i;
      while (i < s.length && s.codeUnitAt(i) != 0x22) {
        i++;
      }
      final String text = s.substring(open, i);
      if (i < s.length) i++;
      words.add(_Word(text, s.substring(start, i)));
    } else {
      while (i < s.length) {
        final int d = s.codeUnitAt(i);
        if (d == 0x20 || d == 0xA0 || d == 0x09 || d == 0x0A || d == 0x0D) {
          break;
        }
        i++;
      }
      final String text = s.substring(start, i);
      words.add(_Word(text, text));
    }
  }
  return words;
}

/// The switch letters that take an argument.
const String _takingSwitches = 'bf@#*';

/// Parses [instruction], the text of a field's instruction, as a
/// `MERGEFIELD`; `null` when it is another field or has no name.
///
/// A `\#` picture is read with [locale]'s separators, as Word wrote it in
/// that locale's language: when [locale]'s decimal separator is `,` (Turkish
/// Word's `#.##0,00`), `.` and `,` swap outside quoted text before the
/// picture becomes an Excel code. A switch written without a space before
/// its argument (`\#0.00`, `\*Upper`) takes the rest of the word as its
/// argument; any other word starting with `\` is unsupported.
MergeField? parseMergeField(
  String instruction, {
  FormatLocale locale = FormatLocale.enUS,
}) {
  final List<_Word> words = _words(instruction);
  if (words.isEmpty ||
      words.first.raw.startsWith('"') ||
      words.first.text.toUpperCase() != 'MERGEFIELD') {
    return null;
  }
  String? name;
  String? before;
  String? after;
  String? dateFormat;
  String? numberFormat;
  String? casing;
  final List<String> unsupported = <String>[];
  int i = 1;
  while (i < words.length) {
    final _Word word = words[i];
    i++;
    final bool slash = word.raw.length >= 2 && word.raw.codeUnitAt(0) == 0x5C;
    if (!slash) {
      name ??= word.text;
      continue;
    }
    final String letter = word.raw[1].toLowerCase();
    final bool takes = _takingSwitches.contains(letter);
    if (!takes) {
      unsupported.add(word.raw);
      continue;
    }
    final _Word arg;
    String written = word.raw;
    if (word.raw.length > 2) {
      // `\#0.00`: the switch and its argument in one word.
      final String rest = word.raw.substring(2);
      arg = _Word(_unquoted(rest), rest);
    } else if (i >= words.length) {
      unsupported.add(word.raw);
      continue;
    } else {
      arg = words[i];
      i++;
      written = '${word.raw} ${arg.raw}';
    }
    switch (letter) {
      case 'b':
        before = arg.text;
      case 'f':
        after = arg.text;
      case '@':
        final String? code = _datePicture(arg.text);
        if (code == null) {
          unsupported.add(written);
        } else {
          dateFormat = code;
        }
      case '#':
        final String? code = _numberPicture(
          locale.decimalSeparator == ',' ? _swapSeparators(arg.text) : arg.text,
        );
        if (code == null) {
          unsupported.add(written);
        } else {
          numberFormat = code;
        }
      default:
        switch (arg.text.toLowerCase()) {
          case 'mergeformat' || 'charformat':
            break;
          case 'upper':
            casing = 'Upper';
          case 'lower':
            casing = 'Lower';
          case 'firstcap':
            casing = 'FirstCap';
          case 'caps':
            casing = 'Caps';
          default:
            unsupported.add(written);
        }
    }
  }
  if (name == null || name.isEmpty) return null;
  return MergeField(
    name: name,
    before: before,
    after: after,
    dateFormat: dateFormat,
    numberFormat: numberFormat,
    casing: casing,
    unsupported: unsupported,
  );
}

/// Word's date picture as an Excel code, or `null` when it has a part Excel
/// cannot express (an unknown letter, a 12-hour `h` without `am/pm`).
String? _datePicture(String p) {
  final StringBuffer out = StringBuffer();
  final String lower = p.toLowerCase();
  final bool ampm = lower.contains('am/pm');
  bool hours24 = false;
  bool hours12 = false;
  int i = 0;
  while (i < p.length) {
    final String ch = p[i];
    if (ch == "'") {
      final int end = p.indexOf("'", i + 1);
      final String text = end < 0
          ? p.substring(i + 1)
          : p.substring(i + 1, end);
      if (text.contains('"')) return null;
      out.write('"$text"');
      i = end < 0 ? p.length : end + 1;
      continue;
    }
    if (lower.startsWith('am/pm', i)) {
      out.write('AM/PM');
      i += 5;
      continue;
    }
    if ('.,/-: '.contains(ch)) {
      out.write(ch);
      i++;
      continue;
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(ch)) return null;
    int j = i;
    while (j < p.length && p[j] == ch) {
      j++;
    }
    final int n = j - i;
    switch (ch) {
      case 'd':
        if (n > 4) return null;
        out.write('d' * n);
      case 'M':
        if (n > 4) return null;
        out.write('m' * n);
      case 'y':
        if (n > 4) return null;
        out.write(n <= 2 ? 'yy' : 'yyyy');
      case 'H':
        if (n > 2) return null;
        hours24 = true;
        out.write('h' * n);
      case 'h':
        if (n > 2) return null;
        hours12 = true;
        out.write('h' * n);
      case 'm' || 's':
        if (n > 2) return null;
        out.write(ch * n);
      default:
        return null;
    }
    i = j;
  }
  if (hours12 && !ampm) return null;
  if (hours24 && ampm) return null;
  return out.toString();
}

/// [s] without the quotes around it, when it is quoted.
String _unquoted(String s) {
  if (!s.startsWith('"')) return s;
  final int end = s.indexOf('"', 1);
  return end < 0 ? s.substring(1) : s.substring(1, end);
}

/// [p] with `.` and `,` swapped outside the text quoted in `'`.
String _swapSeparators(String p) {
  final StringBuffer out = StringBuffer();
  bool quoted = false;
  for (int i = 0; i < p.length; i++) {
    final String ch = p[i];
    if (ch == "'") quoted = !quoted;
    out.write(quoted ? ch : (ch == '.' ? ',' : (ch == ',' ? '.' : ch)));
  }
  return out.toString();
}

/// Word's number picture as an Excel code, or `null` when it has a part
/// Excel cannot express (`x`, `\`, or a letter).
String? _numberPicture(String p) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < p.length) {
    final String ch = p[i];
    if (ch == "'") {
      final int end = p.indexOf("'", i + 1);
      final String text = end < 0
          ? p.substring(i + 1)
          : p.substring(i + 1, end);
      if (text.contains('"')) return null;
      out.write('"$text"');
      i = end < 0 ? p.length : end + 1;
      continue;
    }
    if ('0#,.; '.contains(ch)) {
      out.write(ch);
      i++;
      continue;
    }
    if (ch == r'\' ||
        ch == '"' ||
        RegExp(r'\p{L}', unicode: true).hasMatch(ch)) {
      return null;
    }
    out.write('"$ch"');
    i++;
  }
  return out.toString();
}

bool _turkish(FormatLocale locale) =>
    locale.lcid == 1055 || locale.lcid == 1068;

String _upper(String s, bool tr) {
  if (!tr) return s.toUpperCase();
  return s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
}

String _lower(String s, bool tr) {
  if (!tr) return s.toLowerCase();
  return s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
}

bool _isSpace(int rune) =>
    rune == 0x20 ||
    rune == 0xA0 ||
    rune == 0x09 ||
    rune == 0x0A ||
    rune == 0x0D;

/// [text] with Word's casing switch [casing] (`Upper`, `Lower`, `FirstCap`
/// or `Caps`) applied under [locale]: Turkish rules (`i` and `İ`, `ı` and
/// `I`) for lcid 1055 and 1068, Dart's otherwise. `FirstCap` upper-cases the
/// first character of the text, `Caps` that of each word; the rest is kept.
/// Another [casing] returns [text] unchanged.
String applyCasing(String text, String casing, FormatLocale locale) {
  final bool tr = _turkish(locale);
  switch (casing) {
    case 'Upper':
      return _upper(text, tr);
    case 'Lower':
      return _lower(text, tr);
    case 'FirstCap':
      if (text.isEmpty) return text;
      final int n = String.fromCharCode(text.runes.first).length;
      return _upper(text.substring(0, n), tr) + text.substring(n);
    case 'Caps':
      final StringBuffer out = StringBuffer();
      bool start = true;
      for (final int rune in text.runes) {
        final String ch = String.fromCharCode(rune);
        if (_isSpace(rune)) {
          start = true;
          out.write(ch);
        } else {
          out.write(start ? _upper(ch, tr) : ch);
          start = false;
        }
      }
      return out.toString();
    default:
      return text;
  }
}
