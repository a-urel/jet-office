/// The fixtures of milestone M2 (styling and layout).
///
/// New in jet_office. Each M2 task appends its fixtures to [m2Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M2.
List<Fixture> m2Fixtures() => <Fixture>[_styles()];

/// The text in column A of every row that does not show a number format.
const String _sample = 'Sample 123';

/// One row of `m2_styles`: the value in column A, its style and the label in
/// column B.
typedef _StyleRow = (Object value, XlsxStyle style, String label);

const XlsxColor _blue = XlsxColor.rgb(0x4472C4);
const XlsxColor _yellow = XlsxColor.rgb(0xFFFF00);

/// Every number-format helper of Task 7, with the label it gets.
final List<(XlsxNumFmt, String)> _numberFormats = <(XlsxNumFmt, String)>[
  (XlsxNumFmt.integer, 'integer'),
  (XlsxNumFmt.decimal2, 'decimal2'),
  (XlsxNumFmt.thousands, 'thousands'),
  (XlsxNumFmt.thousands2, 'thousands2'),
  (XlsxNumFmt.scientific, 'scientific'),
  (XlsxNumFmt.fraction, 'fraction'),
  (XlsxNumFmt.time, 'time'),
  (XlsxNumFmt.elapsedTime, 'elapsedTime'),
  (XlsxNumFmt.text, 'text'),
  (XlsxNumFmt.number(decimals: 3, grouping: true), 'number 3 grouped'),
  (XlsxNumFmt.number(decimals: 2, negativeRed: true), 'number 2 red'),
  (XlsxNumFmt.percent(), 'percent'),
  (XlsxNumFmt.percent(decimals: 1), 'percent 1'),
  (XlsxNumFmt.money(symbol: '₺'), 'money ₺'),
  (XlsxNumFmt.money(symbol: r'$', symbolFirst: true), r'money $ first'),
  (
    XlsxNumFmt.money(symbol: '€', decimals: 0, negativeRed: true),
    'money € 0 red',
  ),
];

/// The rows of `m2_styles`, top to bottom.
List<_StyleRow> _styleRows() => <_StyleRow>[
  // Fonts.
  (_sample, const XlsxStyle(font: XlsxFont(bold: true)), 'font bold'),
  (_sample, const XlsxStyle(font: XlsxFont(italic: true)), 'font italic'),
  for (final XlsxUnderline u in XlsxUnderline.values)
    if (u != XlsxUnderline.none)
      (_sample, XlsxStyle(font: XlsxFont(underline: u)), 'underline ${u.name}'),
  (_sample, const XlsxStyle(font: XlsxFont(strike: true)), 'font strike'),
  (
    _sample,
    const XlsxStyle(font: XlsxFont(script: XlsxFontScript.superscript)),
    'font superscript',
  ),
  (
    _sample,
    const XlsxStyle(font: XlsxFont(script: XlsxFontScript.subscript)),
    'font subscript',
  ),
  (_sample, const XlsxStyle(font: XlsxFont(size: 18)), 'font size 18'),
  (
    _sample,
    const XlsxStyle(font: XlsxFont(color: XlsxColor.theme(4, tint: 0.4))),
    'font theme 4 tint 0.4',
  ),
  (_sample, const XlsxStyle(font: XlsxFont(name: 'Arial')), 'font Arial'),
  // Pattern fills.
  for (final XlsxPatternType type in XlsxPatternType.values)
    (
      _sample,
      XlsxStyle(
        fill: XlsxFill.pattern(type, foreground: _blue, background: _yellow),
      ),
      'pattern ${type.name}',
    ),
  // Gradient fills.
  (
    _sample,
    XlsxStyle(
      fill: XlsxGradientFill.linear(
        degree: 90,
        stops: const <XlsxGradientStop>[
          XlsxGradientStop(0, _yellow),
          XlsxGradientStop(1, _blue),
        ],
      ),
    ),
    'gradient linear 90',
  ),
  (
    _sample,
    XlsxStyle(
      fill: XlsxGradientFill.path(
        left: 0.5,
        right: 0.5,
        top: 0.5,
        bottom: 0.5,
        stops: const <XlsxGradientStop>[
          XlsxGradientStop(0, _yellow),
          XlsxGradientStop(1, _blue),
        ],
      ),
    ),
    'gradient path',
  ),
  // Borders.
  for (final XlsxBorderStyle style in XlsxBorderStyle.values)
    if (style != XlsxBorderStyle.none)
      (
        _sample,
        XlsxStyle(
          border: XlsxBorder.all(XlsxBorderSide(style: style, color: _blue)),
        ),
        'border ${style.name}',
      ),
  (
    _sample,
    const XlsxStyle(
      border: XlsxBorder(
        diagonal: XlsxBorderSide(style: XlsxBorderStyle.thin),
        diagonalUp: true,
      ),
    ),
    'border diagonal up',
  ),
  (
    _sample,
    const XlsxStyle(
      border: XlsxBorder(
        diagonal: XlsxBorderSide(style: XlsxBorderStyle.thin),
        diagonalDown: true,
      ),
    ),
    'border diagonal down',
  ),
  // Alignment.
  for (final XlsxHorizontalAlignment h in XlsxHorizontalAlignment.values)
    (
      _sample,
      XlsxStyle(alignment: XlsxAlignment(horizontal: h)),
      'horizontal ${h.name}',
    ),
  for (final XlsxVerticalAlignment v in XlsxVerticalAlignment.values)
    (
      _sample,
      XlsxStyle(alignment: XlsxAlignment(vertical: v)),
      'vertical ${v.name}',
    ),
  (
    'Sample text long enough to wrap onto more lines',
    const XlsxStyle(alignment: XlsxAlignment(wrapText: true)),
    'wrap text',
  ),
  (
    _sample,
    const XlsxStyle(
      alignment: XlsxAlignment(
        horizontal: XlsxHorizontalAlignment.left,
        indent: 3,
      ),
    ),
    'indent 3',
  ),
  (
    _sample,
    const XlsxStyle(alignment: XlsxAlignment(textRotation: 45)),
    'rotation 45',
  ),
  (
    _sample,
    const XlsxStyle(
      alignment: XlsxAlignment(textRotation: XlsxAlignment.verticalText),
    ),
    'vertical text',
  ),
  (
    _sample,
    const XlsxStyle(alignment: XlsxAlignment(shrinkToFit: true)),
    'shrink to fit',
  ),
  (
    _sample,
    const XlsxStyle(
      alignment: XlsxAlignment(readingOrder: XlsxReadingOrder.rightToLeft),
    ),
    'reading order RTL',
  ),
  // Protection.
  (
    _sample,
    const XlsxStyle(protection: XlsxProtection(locked: false)),
    'locked false',
  ),
  (
    _sample,
    const XlsxStyle(protection: XlsxProtection(hidden: true)),
    'hidden true',
  ),
  // Number formats, each on a number and on a date.
  for (final (XlsxNumFmt format, String name) in _numberFormats) ...<_StyleRow>[
    (1234.5, XlsxStyle(numFmt: format), 'numFmt $name on 1234.5'),
    (
      const XlsxDate(2026, 10, 24),
      XlsxStyle(numFmt: format),
      'numFmt $name on 2026-10-24',
    ),
  ],
];

/// The text `<v>` stores for [value]: a date as its serial.
String _stored(Object value) => value is XlsxDate ? '46319' : '$value';

/// What a reader shows for [value]: a date as its serial.
Object _expected(Object value) => value is XlsxDate ? 46319 : value;

Fixture _styles() {
  final List<_StyleRow> rows = _styleRows();
  return Fixture(
    'm2_styles',
    <String, List<List<String>>>{
      'Styles': <List<String>>[
        for (final (Object value, _, String label) in rows)
          <String>[_stored(value), label],
      ],
    },
    <String, List<List<Object?>>>{
      'Styles': <List<Object?>>[
        for (final (Object value, _, String label) in rows)
          <Object?>[_expected(value), label],
      ],
    },
    () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('Styles');
      for (final (Object value, XlsxStyle style, String label) in rows) {
        sheet.row(<Object?>[XlsxCell(value, style: style), label]);
      }
      return book.close();
    },
    // A date in each of the 14 formats that show no date: all but `time`
    // and `elapsedTime`.
    expectedWarnings: <XlsxWarningCode, int>{
      XlsxWarningCode.dateInNonDateFormat: 14,
    },
  );
}
