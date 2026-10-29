/// The dispatcher that renders any cell value with a parsed format.
///
/// New in jet_office; Quds has no number format engine. [renderValue]
/// takes a value of any supported type, picks the section that applies
/// ([chooseNumberSection], [chooseTextSection]) and hands numbers to
/// [renderNumber]. Text is laid out here; booleans and errors ignore the
/// code and read their words from the locale.
///
/// Interim, until N2: a date or time section shows a number as `General`,
/// and a `DateTime` or `Duration` shows its ISO or `toString` text.
library;

import '../read/read_cell.dart';
import '../values.dart';
import 'excel_number.dart';
import 'format_code.dart';
import 'format_locale.dart';
import 'formatted_value.dart';
import 'general.dart';
import 'number_renderer.dart';
import 'section_choice.dart';

/// Renders [value] with [format].
///
/// `section` is the section used (for its color), or null when none was
/// used; `overflow` is true when Excel shows `#` at any column width.
/// [value] is `null`, a [String], a [bool], an [XlsxErrorValue], an
/// [XlsxDecimal], a [num], a [DateTime] or a [Duration]; any other type is
/// a programmer error and throws [ArgumentError]. Never throws for any
/// code.
({List<XlsxFormatPart> parts, FormatSection? section, bool overflow})
renderValue(
  Object? value,
  ParsedFormat format, {
  required XlsxFormatLocale locale,
  required int generalWidth,
}) {
  List<XlsxFormatPart> plain(String text) => <XlsxFormatPart>[
    XlsxFormatText(text),
  ];
  switch (value) {
    case null:
      return (parts: <XlsxFormatPart>[], section: null, overflow: false);
    case String():
      final FormatSection? section = chooseTextSection(format);
      return (
        parts: section == null ? plain(value) : _renderText(section, value),
        section: section,
        overflow: false,
      );
    case bool():
      return (
        parts: plain(value ? locale.trueText : locale.falseText),
        section: null,
        overflow: false,
      );
    case XlsxErrorValue():
      return (
        parts: plain(locale.errorNames[value.code] ?? value.code),
        section: null,
        overflow: false,
      );
    case XlsxDecimal() || num():
      return _renderNumberValue(value, format, locale, generalWidth);
    case DateTime():
      return (
        parts: plain(value.toIso8601String()),
        section: null,
        overflow: false,
      );
    case Duration():
      return (parts: plain(value.toString()), section: null, overflow: false);
    default:
      throw ArgumentError.value(
        value,
        'value',
        'Expected null, a String, bool, XlsxErrorValue, XlsxDecimal, num, '
            'DateTime or Duration',
      );
  }
}

({List<XlsxFormatPart> parts, FormatSection? section, bool overflow})
_renderNumberValue(
  Object value,
  ParsedFormat format,
  XlsxFormatLocale locale,
  int generalWidth,
) {
  final ExcelNumber? number = ExcelNumber.from(value);
  if (number == null) {
    return (
      parts: <XlsxFormatPart>[
        XlsxFormatText(locale.errorNames['#NUM!'] ?? '#NUM!'),
      ],
      section: null,
      overflow: false,
    );
  }
  final ({FormatSection section, bool showMinus, ExcelNumber value})? chosen =
      chooseNumberSection(format, number);
  if (chosen == null) {
    return (
      parts: <XlsxFormatPart>[const XlsxFormatText('#')],
      section: null,
      overflow: true,
    );
  }
  final FormatSection section = chosen.section;
  // `@` as the only format (spec §5.1) and date or time sections (until
  // N2) show the number as General.
  final bool textOnly =
      format.sections.length == 1 &&
      section.hasText &&
      !section.hasDigits &&
      !section.hasGeneral;
  if (textOnly || section.hasDateTime) {
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
