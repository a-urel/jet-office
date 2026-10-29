/// Classifies a number format code as a number, a date or a time.
///
/// New in jet_office; Quds has no reader. It extends the idea of phase 1's
/// `isDateFormat` (`number_format.dart`), which asks whether a code shows a
/// date or a time anywhere, by looking at each section of the code on its
/// own and by telling dates from times and elapsed times.
library;

/// What a number format code makes a cell value show.
enum FormatKind {
  /// A number, text or `General`, or a mix of sections that is not one kind.
  number,

  /// A date, possibly with a time of day.
  date,

  /// A time of day or an elapsed time, with no date part.
  time,
}

/// Classifies the number format [code] by its first three sections.
///
/// Sections are separated by `;` outside quoted literals (`"..."`), the
/// character after `\`, `_` or `*`, and `[...]` brackets. Only the first
/// three count; the fourth is text. A section is neutral when it holds `@`
/// outside literals, or when it has no date or time token and either is
/// `General` or has no digit placeholder (`0`, `#` or `?` outside
/// literals), so an empty section and one of literals only (`"-"`) are
/// neutral. Otherwise it is a date when it has `d`, `y` or a month, a time
/// when it has only hours, minutes and seconds, and a number when it has
/// none of them.
///
/// The result is [FormatKind.date] (or [FormatKind.time]) when at least one
/// section is not neutral and every section that is not neutral is a date
/// (or every one is a time); otherwise [FormatKind.number]. So
/// `yyyy-mm-dd;@`, `yyyy-mm-dd;"-"` and `dd.mm.yyyy;;"-"` are dates, while
/// `yyyy-mm-dd;h:mm`, `0.00;0.00;h:mm` and `0;"-"` are numbers, and so is a
/// code of neutral sections only (`"abc"`).
///
/// Within a section, `m` is minutes when the previous token is `h` or the
/// next is `s` (an elapsed `[h]` or `[s]` counts), and a month otherwise; a
/// run of three or more is always a month. An elapsed `[m]` is minutes.
/// Literals are skipped as `isDateFormat` skips them, including the word
/// `General` and the markers `AM/PM` and `A/P`. An unterminated quote or
/// bracket ends the section, and the code with it.
FormatKind classifyFormatCode(String code) {
  final List<_Section> sections = <_Section>[];
  var section = _Section();
  var i = 0;
  var ended = false;
  while (i < code.length && !ended) {
    final String c = code[i];
    if (c == ';') {
      sections.add(section);
      if (sections.length == 3) return _combine(sections);
      section = _Section();
      i++;
    } else if (c == '"') {
      final int close = code.indexOf('"', i + 1);
      if (close < 0) {
        ended = true;
      } else {
        i = close + 1;
      }
    } else if (c == r'\' || c == '_' || c == '*') {
      // The next character is a literal, a width or a fill; a lone one at
      // the end is skipped harmlessly.
      i += 2;
    } else if (c == '[') {
      final int close = code.indexOf(']', i + 1);
      if (close < 0) {
        ended = true;
      } else {
        section.addBracket(code.substring(i + 1, close));
        i = close + 1;
      }
    } else if (_isWordAt(code, i, _generalWord)) {
      section.hasGeneral = true;
      i += _generalWord.length;
    } else if (_isWordAt(code, i, _amPm)) {
      i += _amPm.length;
    } else if (_isWordAt(code, i, _aP)) {
      i += _aP.length;
    } else if (c == '@') {
      section.hasAt = true;
      i++;
    } else if (_tokenLetters.contains(c)) {
      final String letter = c.toLowerCase();
      var end = i + 1;
      while (end < code.length && code[end].toLowerCase() == letter) {
        end++;
      }
      section.tokens.add(_Token(letter, end - i, elapsed: false));
      i = end;
    } else {
      if (_digitPlaceholders.contains(c)) section.hasDigit = true;
      i++;
    }
  }
  sections.add(section);
  return _combine(sections);
}

const String _generalWord = 'general';
const String _amPm = 'am/pm';
const String _aP = 'a/p';
const String _tokenLetters = 'dmyhsDMYHS';
const String _digitPlaceholders = '0#?';

/// Whether [code] holds the lowercase [word] at [i], in any case.
bool _isWordAt(String code, int i, String word) =>
    i + word.length <= code.length &&
    code.substring(i, i + word.length).toLowerCase() == word;

/// A run of one date or time letter, in lowercase.
final class _Token {
  _Token(this.letter, this.length, {required this.elapsed});

  final String letter;
  final int length;

  /// Whether the run was a bracketed elapsed-time token such as `[h]`.
  final bool elapsed;
}

/// What a scan collects from one section of a format code.
final class _Section {
  final List<_Token> tokens = <_Token>[];
  bool hasAt = false;
  bool hasGeneral = false;

  /// Whether a digit placeholder (`0`, `#` or `?`) was seen outside
  /// literals.
  bool hasDigit = false;

  void addBracket(String content) {
    final String lower = content.toLowerCase();
    if (lower.isNotEmpty &&
        'hms'.contains(lower[0]) &&
        lower.split('').every((String ch) => ch == lower[0])) {
      tokens.add(_Token(lower[0], lower.length, elapsed: true));
    }
  }

  bool get isNeutral => hasAt || (tokens.isEmpty && (hasGeneral || !hasDigit));

  FormatKind get kind {
    var hasDate = false;
    var hasTime = false;
    for (var k = 0; k < tokens.length; k++) {
      final _Token token = tokens[k];
      switch (token.letter) {
        case 'd' || 'y':
          hasDate = true;
        case 'h' || 's':
          hasTime = true;
        default:
          if (_isMinutes(k)) {
            hasTime = true;
          } else {
            hasDate = true;
          }
      }
    }
    if (hasDate) return FormatKind.date;
    return hasTime ? FormatKind.time : FormatKind.number;
  }

  /// Whether the `m` token at [k] is minutes rather than a month.
  bool _isMinutes(int k) {
    final _Token token = tokens[k];
    if (token.elapsed) return true;
    if (token.length > 2) return false;
    return (k > 0 && tokens[k - 1].letter == 'h') ||
        (k + 1 < tokens.length && tokens[k + 1].letter == 's');
  }
}

FormatKind _combine(List<_Section> sections) {
  FormatKind? result;
  for (final _Section section in sections) {
    if (section.isNeutral) continue;
    final FormatKind kind = section.kind;
    if (kind == FormatKind.number) return FormatKind.number;
    if (result != null && result != kind) return FormatKind.number;
    result = kind;
  }
  return result ?? FormatKind.number;
}
