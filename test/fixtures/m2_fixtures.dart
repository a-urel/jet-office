/// The fixtures of milestone M2 (styling and layout).
///
/// New in jet_office. Each M2 task appends its fixtures to [m2Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M2.
List<Fixture> m2Fixtures() => <Fixture>[
  _styles(),
  _columnsRows(),
  _stylePrecedence(),
];

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

/// A sheet written by the layout fixtures: its rows, each with the values
/// from column A on and the options of `XlsxSheetWriter.row`.
typedef _LayoutRow = ({
  List<Object?> values,
  XlsxStyle? style,
  double? height,
  bool hidden,
  int outlineLevel,
  bool collapsed,
});

_LayoutRow _row(
  List<Object?> values, {
  XlsxStyle? style,
  double? height,
  bool hidden = false,
  int outlineLevel = 0,
  bool collapsed = false,
}) => (
  values: values,
  style: style,
  height: height,
  hidden: hidden,
  outlineLevel: outlineLevel,
  collapsed: collapsed,
);

/// Writes [rows] to [sheet].
void _writeRows(XlsxSheetWriter sheet, List<_LayoutRow> rows) {
  for (final _LayoutRow r in rows) {
    sheet.row(
      r.values,
      style: r.style,
      height: r.height,
      hidden: r.hidden,
      outlineLevel: r.outlineLevel,
      collapsed: r.collapsed,
    );
  }
}

/// The value inside [cell], unwrapping an [XlsxCell].
Object? _unwrap(Object? cell) => cell is XlsxCell ? cell.value : cell;

/// The stored text of every sheet in [sheets], padded to a rectangle.
Map<String, List<List<String>>> _storedOf(
  Map<String, List<_LayoutRow>> sheets,
) => <String, List<List<String>>>{
  for (final MapEntry<String, List<_LayoutRow>> e in sheets.entries)
    e.key: _rectangle(e.value, (Object? v) => v == null ? '' : _stored(v)),
};

/// The expected values of every sheet in [sheets], padded to a rectangle.
Map<String, List<List<Object?>>> _expectedOf(
  Map<String, List<_LayoutRow>> sheets,
) => <String, List<List<Object?>>>{
  for (final MapEntry<String, List<_LayoutRow>> e in sheets.entries)
    e.key: _rectangle(e.value, (Object? v) => v == null ? null : _expected(v)),
};

List<List<T>> _rectangle<T>(List<_LayoutRow> rows, T Function(Object?) f) {
  int width = 0;
  for (final _LayoutRow r in rows) {
    if (r.values.length > width) width = r.values.length;
  }
  return <List<T>>[
    for (final _LayoutRow r in rows)
      <T>[
        for (int c = 0; c < width; c++)
          f(c < r.values.length ? _unwrap(r.values[c]) : null),
      ],
  ];
}

/// The rows of `m2_columns_rows`' first sheet: row heights, a hidden row,
/// and a collapsed outer group (rows 5 to 7, summary row 8) holding an
/// expanded inner group (rows 5 and 6, summary row 7).
final List<_LayoutRow> _layoutRows = <_LayoutRow>[
  _row(<Object?>[
    'width 5',
    'width 12',
    'width 40',
    'width 255',
    'hidden column',
    'level 1',
    'level 2',
    'level 2',
  ]),
  _row(<Object?>['height 30', 1], height: 30),
  _row(<Object?>['height 5', 2], height: 5),
  _row(<Object?>['hidden row', 3], hidden: true),
  _row(<Object?>['detail a', 10], hidden: true, outlineLevel: 2),
  _row(<Object?>['detail b', 20], hidden: true, outlineLevel: 2),
  _row(<Object?>['subtotal', 30], hidden: true, outlineLevel: 1),
  _row(<Object?>['total (collapsed)', 30], collapsed: true),
];

final List<_LayoutRow> _defaultSizeRows = <_LayoutRow>[
  _row(<Object?>['default row height 18', 'default column width 11']),
  _row(<Object?>[1, 2]),
];

Fixture _columnsRows() {
  final Map<String, List<_LayoutRow>> sheets = <String, List<_LayoutRow>>{
    'Layout': _layoutRows,
    'Defaults': _defaultSizeRows,
  };
  return Fixture('m2_columns_rows', _storedOf(sheets), _expectedOf(sheets), () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter layout = book.addSheet('Layout')
      ..columns(const <XlsxColumn?>[
        XlsxColumn(width: 5),
        XlsxColumn(width: 12),
        XlsxColumn(width: 40),
        XlsxColumn(width: 255),
        XlsxColumn(hidden: true),
        XlsxColumn(outlineLevel: 1),
        XlsxColumn(outlineLevel: 2),
        XlsxColumn(outlineLevel: 2),
      ]);
    _writeRows(layout, _layoutRows);
    final XlsxSheetWriter defaults = book.addSheet('Defaults')
      ..defaultSizes(rowHeight: 18, columnWidth: 11);
    _writeRows(defaults, _defaultSizeRows);
    return book.close();
  });
}

const XlsxStyle _bold = XlsxStyle(font: XlsxFont(bold: true));
const XlsxStyle _italic = XlsxStyle(font: XlsxFont(italic: true));
const XlsxStyle _topBorder = XlsxStyle(
  border: XlsxBorder(top: XlsxBorderSide(style: XlsxBorderStyle.thin)),
);
const XlsxDate _day = XlsxDate(2026, 10, 24);

/// The rows of `m2_style_precedence`: under a money column B and a date
/// column C, a bold header row, a date in the money column, and a totals
/// row with a top border whose amount is also italic.
final List<_LayoutRow> _precedenceRows = <_LayoutRow>[
  _row(<Object?>['Item', 'Amount', 'Date'], style: _bold),
  _row(<Object?>['Rent', 1200.5, _day]),
  _row(<Object?>['Fee', 45.25, _day]),
  _row(<Object?>['Date in money', _day, _day]),
  _row(<Object?>[
    'Total',
    const XlsxCell(1245.75, style: _italic),
  ], style: _topBorder),
];

Fixture _stylePrecedence() {
  final Map<String, List<_LayoutRow>> sheets = <String, List<_LayoutRow>>{
    'Precedence': _precedenceRows,
  };
  return Fixture(
    'm2_style_precedence',
    _storedOf(sheets),
    _expectedOf(sheets),
    () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('Precedence')
        ..columns(<XlsxColumn?>[
          null,
          XlsxColumn(
            width: 14,
            style: XlsxStyle(numFmt: XlsxNumFmt.money(symbol: '€')),
          ),
          const XlsxColumn(
            width: 12,
            style: XlsxStyle(numFmt: XlsxNumFmt.custom('yyyy-mm-dd')),
          ),
        ]);
      _writeRows(sheet, _precedenceRows);
      return book.close();
    },
    expectedWarnings: <XlsxWarningCode, int>{
      XlsxWarningCode.dateInNonDateFormat: 1,
    },
  );
}
