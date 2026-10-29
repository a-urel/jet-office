/// The dispatcher that renders any cell value with a parsed format.
///
/// New in jet_office; Quds has no number format engine. [renderValue]
/// takes a value of any supported type, picks the section that applies
/// ([chooseNumberSection], [chooseTextSection]) and hands numbers to
/// [renderNumber], or to [renderDate] when the section has date or time
/// tokens. A `DateTime` or `Duration` becomes its serial first
/// ([dateTimeToSerial], [durationToSerial]) and then takes the number
/// path. Text is laid out here; booleans and errors ignore the code and
/// read their words from the locale.
library;

import '../read/read_cell.dart';
import '../values.dart';
import '../warnings.dart';
import 'date_renderer.dart';
import 'excel_date.dart';
import 'excel_number.dart';
import 'format_code.dart';
import 'format_locale.dart';
import 'formatted_value.dart';
import 'general.dart';
import 'number_renderer.dart';
import 'section_choice.dart';

/// What [renderValue] produces.
///
/// `parts` is the rendered text; `section` is the section used (for its
/// color), or null when none was used; `overflow` is true when Excel shows
/// `#` at any column width; `warning` is
/// [XlsxWarningCode.numberFormatUnsupported] when the section used asks
/// for something the engine does not render ([sectionWarning]), else null.
typedef RenderedValue = ({
  List<XlsxFormatPart> parts,
  FormatSection? section,
  bool overflow,
  XlsxWarningCode? warning,
});

/// Renders [value] with [format].
///
/// [value] is `null`, a [String], a [bool], an [XlsxErrorValue], an
/// [XlsxDecimal], a [num], a [DateTime] or a [Duration]; any other type is
/// a programmer error and throws [ArgumentError]. A [DateTime] is its
/// serial in the date system of [date1904], a [Duration] its length in
/// days; both then render as that number. A date or time section gets the
/// signed serial, so a negative value shows `#` there even in an explicit
/// negative section (in the 1904 system a time-only section shows it with
/// a minus). Never throws for any code.
RenderedValue renderValue(
  Object? value,
  ParsedFormat format, {
  required XlsxFormatLocale locale,
  required int generalWidth,
  required bool date1904,
}) {
  RenderedValue plain(String text) => (
    parts: <XlsxFormatPart>[XlsxFormatText(text)],
    section: null,
    overflow: false,
    warning: null,
  );
  switch (value) {
    case null:
      return (
        parts: <XlsxFormatPart>[],
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
    case XlsxErrorValue():
      return plain(locale.errorNames[value.code] ?? value.code);
    case XlsxDecimal() || num():
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
        'Expected null, a String, bool, XlsxErrorValue, XlsxDecimal, num, '
            'DateTime or Duration',
      );
  }
}

RenderedValue _overflow(FormatSection? section, XlsxWarningCode? warning) => (
  parts: <XlsxFormatPart>[const XlsxFormatText('#')],
  section: section,
  overflow: true,
  warning: warning,
);

RenderedValue _renderNumberValue(
  ExcelNumber number,
  ParsedFormat format,
  XlsxFormatLocale locale,
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
    final ({List<XlsxFormatPart> parts, XlsxWarningCode? warning})? date =
        renderDate(section, number, locale: locale, date1904: date1904);
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
  final XlsxWarningCode? warning = sectionWarning(
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
    final String text = renderGeneral(
      chosen.value,
      width: generalWidth,
      locale: locale,
    );
    final bool minus = chosen.showMinus && !chosen.value.isZero;
    return (
      parts: <XlsxFormatPart>[XlsxFormatText(minus ? '-$text' : text)],
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
List<XlsxFormatPart> _renderText(FormatSection section, String text) {
  final List<XlsxFormatPart> parts = <XlsxFormatPart>[];
  final StringBuffer run = StringBuffer();
  void flush() {
    if (run.isEmpty) return;
    parts.add(XlsxFormatText(run.toString()));
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
        parts.add(XlsxFormatPadding(char));
      case FillToken(:final String char):
        flush();
        parts.add(XlsxFormatFill(char));
      default:
        break;
    }
  }
  flush();
  return parts;
}
