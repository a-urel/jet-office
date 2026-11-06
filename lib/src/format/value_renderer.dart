/// The dispatcher that renders any cell value with a parsed format.
///
/// Moved from jet_office's lib/src/xlsx/format/ at commit 632115d; written
/// there, not ported from Quds.
///
/// [renderValue]
/// takes a value of any supported type, picks the section that applies
/// ([chooseNumberSection], [chooseTextSection]) and hands numbers to
/// [renderNumber], or to [renderDate] when the section has date or time
/// tokens. A `DateTime` or `Duration` becomes its serial first
/// ([dateTimeToSerial], [durationToSerial]) and then takes the number
/// path. Text is laid out here; booleans and errors ignore the code and
/// read their words from the locale.
library;

import 'date_renderer.dart';
import 'excel_date.dart';
import 'excel_number.dart';
import 'format_code.dart';
import 'format_locale.dart';
import 'format_value.dart';
import 'formatted_value.dart';
import 'general.dart';
import 'number_renderer.dart';
import 'section_choice.dart';

/// What [renderValue] produces.
///
/// `parts` is the rendered text; `section` is the section used (for its
/// color), or null when none was used; `overflow` is true when Excel shows
/// `#` at any column width; `warning` is
/// [FormatWarning.unsupported] when the section used asks
/// for something the engine does not render ([sectionWarning]), else null.
typedef RenderedValue = ({
  List<FormatPart> parts,
  FormatSection? section,
  bool overflow,
  FormatWarning? warning,
});

/// Renders [value] with [format].
///
/// [value] is `null`, a [String], a [bool], a [FormatErrorValue], an
/// [FormatDecimal], a [num], a [DateTime] or a [Duration]; any other type is
/// a programmer error and throws [ArgumentError]. A [DateTime] is its
/// serial in the date system of [date1904], a [Duration] its length in
/// days; both then render as that number. A date or time section gets the
/// signed serial, so a negative value shows `#` there even in an explicit
/// negative section (in the 1904 system any date or time section shows
/// it with a minus). Never throws for any code.
RenderedValue renderValue(
  Object? value,
  ParsedFormat format, {
  required FormatLocale locale,
  required int generalWidth,
  required bool date1904,
}) {
  RenderedValue plain(String text) => (
    parts: <FormatPart>[FormatText(text)],
    section: null,
    overflow: false,
    warning: null,
  );
  switch (value) {
    case null:
      return (
        parts: <FormatPart>[],
        section: null,
        overflow: false,
        warning: null,
      );
    case String():
      final FormatSection? section = chooseTextSection(format);
      if (section == null) return plain(value);
      return (
        parts: _renderText(section, value),
        section: section,
        overflow: false,
        warning: null,
      );
    case bool():
      return plain(value ? locale.trueText : locale.falseText);
    case FormatErrorValue():
      return plain(locale.errorNames[value.code] ?? value.code);
    case FormatDecimal() || num():
      final ExcelNumber? number = ExcelNumber.from(value);
      if (number == null) return plain(locale.errorNames['#NUM!'] ?? '#NUM!');
      return _renderNumberValue(number, format, locale, generalWidth, date1904);
    case DateTime():
      return _renderNumberValue(
        dateTimeToSerial(value, date1904: date1904),
        format,
        locale,
        generalWidth,
        date1904,
      );
    case Duration():
      return _renderNumberValue(
        durationToSerial(value),
        format,
        locale,
        generalWidth,
        date1904,
      );
    default:
      throw ArgumentError.value(
        value,
        'value',
        'Expected null, a String, bool, FormatErrorValue, FormatDecimal, num, '
            'DateTime or Duration',
      );
  }
}

RenderedValue _overflow(FormatSection? section, FormatWarning? warning) => (
  parts: <FormatPart>[const FormatText('#')],
  section: section,
  overflow: true,
  warning: warning,
);

RenderedValue _renderNumberValue(
  ExcelNumber number,
  ParsedFormat format,
  FormatLocale locale,
  int generalWidth,
  bool date1904,
) {
  final ({FormatSection section, bool showMinus, ExcelNumber value})? chosen =
      chooseNumberSection(format, number);
  if (chosen == null) return _overflow(null, null);
  final FormatSection section = chosen.section;
  if (section.hasDateTime) {
    // Ruling 4: the date renderer gets the signed number, so an explicit
    // negative section does not hide the sign.
    final ({List<FormatPart> parts, FormatWarning? warning})? date = renderDate(
      section,
      number,
      locale: locale,
      date1904: date1904,
    );
    if (date == null) {
      return _overflow(
        section,
        sectionWarning(section, date: true, locale: locale),
      );
    }
    return (
      parts: date.parts,
      section: section,
      overflow: false,
      warning: date.warning,
    );
  }
  final FormatWarning? warning = sectionWarning(
    section,
    date: false,
    locale: locale,
  );
  // `@` as the only format (spec §5.1) shows the number as General.
  final bool textOnly =
      format.sections.length == 1 &&
      section.hasText &&
      !section.hasDigits &&
      !section.hasGeneral;
  if (textOnly) {
    final bool minus = chosen.showMinus && !chosen.value.isZero;
    final String text = renderGeneral(
      chosen.value,
      width: generalWidth,
      locale: locale,
      minus: minus,
    );
    return (
      parts: <FormatPart>[FormatText(minus ? '-$text' : text)],
      section: section,
      overflow: false,
      warning: warning,
    );
  }
  return (
    parts: renderNumber(
      section,
      chosen.value,
      showMinus: chosen.showMinus,
      locale: locale,
      generalWidth: generalWidth,
    ),
    section: section,
    overflow: false,
    warning: warning,
  );
}

/// How many characters the text [section] adds to a text of [length]
/// characters: its literals (a padding counts one, a fill none) and each
/// `@` after the first. The first `@` shows the value itself, so it adds
/// nothing; a section without `@` shows only its literals.
///
/// The formatter checks this against its output bound before
/// [renderValue] builds the text, so `@` repeated on a long text costs no
/// memory.
int addedTextLength(FormatSection section, int length) {
  var added = 0;
  var ats = 0;
  for (final FormatToken token in section.tokens) {
    switch (token) {
      case TextToken():
        ats++;
      case LiteralToken(text: final String literal):
        added += literal.length;
      case LocaleTagToken(:final String currency):
        added += currency.length;
      case PaddingToken():
        added++;
      default:
        break;
    }
  }
  return ats > 1 ? added + (ats - 1) * length : added;
}

/// Lays [text] out in the text [section]: `@` shows [text], literals,
/// padding and fill are kept, and adjacent text is merged.
List<FormatPart> _renderText(FormatSection section, String text) {
  final List<FormatPart> parts = <FormatPart>[];
  final StringBuffer run = StringBuffer();
  void flush() {
    if (run.isEmpty) return;
    parts.add(FormatText(run.toString()));
    run.clear();
  }

  for (final FormatToken token in section.tokens) {
    switch (token) {
      case TextToken():
        run.write(text);
      case LiteralToken(text: final String literal):
        run.write(literal);
      case LocaleTagToken(:final String currency):
        run.write(currency);
      case PaddingToken(:final String char):
        flush();
        parts.add(FormatPadding(char));
      case FillToken(:final String char):
        flush();
        parts.add(FormatFill(char));
      default:
        break;
    }
  }
  flush();
  return parts;
}
