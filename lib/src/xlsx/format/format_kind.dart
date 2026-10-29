/// Classifies a number format code as a number, a date or a time.
///
/// New in jet_office; Quds has no reader. It extends the idea of phase 1's
/// `isDateFormat` (`number_format.dart`), which asked whether a code shows
/// a date or a time anywhere, by looking at each section of the code on its
/// own and by telling dates from times and elapsed times. Since decision
/// 0008 `isDateFormat` is built on it, and both read the tokens of
/// `parseFormatCode`.
library;

import 'format_code.dart';

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
/// The sections and tokens come from [parseFormatCode], so literals are
/// skipped as the parser skips them, including the word `General` and the
/// markers `AM/PM` and `A/P`; the markers and the era and calendar letters
/// `e`, `g` and `b` count for nothing. An unterminated quote or bracket
/// ends the section, and the code with it.
FormatKind classifyFormatCode(String code) {
  final List<FormatSection> sections = parseFormatCode(code).sections;
  FormatKind? result;
  for (var k = 0; k < sections.length && k < 3; k++) {
    final FormatSection section = sections[k];
    final List<DateToken> tokens = <DateToken>[
      for (final FormatToken token in section.tokens)
        if (token is DateToken && _counted.contains(token.letter)) token,
    ];
    final bool neutral =
        section.hasText ||
        (tokens.isEmpty && (section.hasGeneral || !section.hasDigits));
    if (neutral) continue;
    final FormatKind kind = _kind(tokens);
    if (kind == FormatKind.number) return FormatKind.number;
    if (result != null && result != kind) return FormatKind.number;
    result = kind;
  }
  return result ?? FormatKind.number;
}

/// The date and time letters that decide a section's kind.
const String _counted = 'dmyhs';

/// The kind of a section whose date and time tokens are [tokens].
FormatKind _kind(List<DateToken> tokens) {
  var hasDate = false;
  var hasTime = false;
  for (var k = 0; k < tokens.length; k++) {
    switch (tokens[k].letter) {
      case 'd' || 'y':
        hasDate = true;
      case 'h' || 's':
        hasTime = true;
      default:
        if (_isMinutes(tokens, k)) {
          hasTime = true;
        } else {
          hasDate = true;
        }
    }
  }
  if (hasDate) return FormatKind.date;
  return hasTime ? FormatKind.time : FormatKind.number;
}

/// Whether the `m` token at [k] of [tokens] is minutes rather than a month.
bool _isMinutes(List<DateToken> tokens, int k) {
  final DateToken token = tokens[k];
  if (token.elapsed) return true;
  if (token.length > 2) return false;
  return (k > 0 && tokens[k - 1].letter == 'h') ||
      (k + 1 < tokens.length && tokens[k + 1].letter == 's');
}
