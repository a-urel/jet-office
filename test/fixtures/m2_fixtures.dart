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
  _views(),
  _mergesFilter(),
  _formulaXstring(),
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
/// row with a top border whose amount is also italic. The totals row's C5
/// is a styled empty cell, so the border spans A5:C5.
final List<_LayoutRow> _precedenceRows = <_LayoutRow>[
  _row(<Object?>['Item', 'Amount', 'Date'], style: _bold),
  _row(<Object?>['Rent', 1200.5, _day]),
  _row(<Object?>['Fee', 45.25, _day]),
  _row(<Object?>['Date in money', _day, _day]),
  _row(<Object?>[
    'Total',
    const XlsxCell(1245.75, style: _italic),
    const XlsxCell(null, style: _topBorder),
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

/// The rows of `m2_views`' `Frozen` sheet: a header and 40 data rows.
final List<_LayoutRow> _frozenRows = <_LayoutRow>[
  _row(<Object?>['Row', 'Square', 'Label'], style: _bold),
  for (int i = 1; i <= 40; i++) _row(<Object?>[i, i * i, 'Item $i']),
];

final List<_LayoutRow> _splitRows = <_LayoutRow>[
  for (int i = 1; i <= 30; i++) _row(<Object?>['Split $i', i, i * 2]),
];

/// A `0` cell, which the `View` sheet hides, between two others.
final List<_LayoutRow> _viewRows = <_LayoutRow>[
  _row(<Object?>['zoom 85, no gridlines, no headings', 0, 7]),
];

/// Arabic and Hebrew text, written as is.
final List<_LayoutRow> _rtlRows = <_LayoutRow>[
  _row(<Object?>['مرحبا بالعالم', 'שלום עולם', 1]),
];

/// Rows 2 and 3 group under the summary row 1, which sits above them.
final List<_LayoutRow> _outlineRows = <_LayoutRow>[
  _row(<Object?>['summary (above)', 6]),
  _row(<Object?>['detail a', 1], outlineLevel: 1),
  _row(<Object?>['detail b', 5], outlineLevel: 1),
];

final List<_LayoutRow> _hiddenRows = <_LayoutRow>[
  _row(<Object?>['a hidden sheet', 1]),
];

final List<_LayoutRow> _veryHiddenRows = <_LayoutRow>[
  _row(<Object?>['a very hidden sheet', 2]),
];

Fixture _views() {
  final Map<String, List<_LayoutRow>> sheets = <String, List<_LayoutRow>>{
    'Frozen': _frozenRows,
    'Split': _splitRows,
    'View': _viewRows,
    'RTL': _rtlRows,
    'Outline': _outlineRows,
    'Hidden': _hiddenRows,
    'VeryHidden': _veryHiddenRows,
  };
  return Fixture('m2_views', _storedOf(sheets), _expectedOf(sheets), () {
    final XlsxWriter book = XlsxWriter();
    _writeRows(
      book.addSheet('Frozen')..freeze(rows: 1, columns: 1),
      _frozenRows,
    );
    _writeRows(book.addSheet('Split')..split(x: 120, y: 60), _splitRows);
    final XlsxSheetWriter view = book.addSheet('View')
      ..view(
        const XlsxSheetView(
          zoom: 85,
          showGridLines: false,
          showHeadings: false,
          showZeros: false,
        ),
      )
      ..tabColor(const XlsxColor.rgb(0xFF0000));
    _writeRows(view, _viewRows);
    _writeRows(
      book.addSheet('RTL')..view(const XlsxSheetView(rightToLeft: true)),
      _rtlRows,
    );
    _writeRows(
      book.addSheet('Outline')..outlineSummary(below: false),
      _outlineRows,
    );
    _writeRows(
      book.addSheet('Hidden', visibility: XlsxSheetVisibility.hidden),
      _hiddenRows,
    );
    _writeRows(
      book.addSheet('VeryHidden', visibility: XlsxSheetVisibility.veryHidden),
      _veryHiddenRows,
    );
    book.setActiveSheet(view);
    return book.close();
  });
}

/// The rows of `m2_merges_filter`'s `Bob's Data` sheet: a title over A1:D1,
/// a text block over B3:C4, a header at row 6 and 14 data rows under it.
final List<_LayoutRow> _filterRows = <_LayoutRow>[
  _row(
    <Object?>['Quarterly report'],
    style: const XlsxStyle(
      font: XlsxFont(bold: true, size: 14),
      alignment: XlsxAlignment(horizontal: XlsxHorizontalAlignment.center),
    ),
  ),
  _row(<Object?>[]),
  _row(<Object?>[null, 'A merged block of text']),
  _row(<Object?>[]),
  _row(<Object?>[]),
  _row(<Object?>['Id', 'Name', 'Qty', 'Price'], style: _bold),
  for (int i = 1; i <= 14; i++)
    _row(<Object?>[i, 'Item $i', i * 3, i * 2 + 0.5]),
];

final List<_LayoutRow> _plainRows = <_LayoutRow>[
  _row(<Object?>['no filter here', 1]),
  _row(<Object?>['nor here', 2]),
];

/// Merged cells and an auto filter on a sheet whose name needs quoting, and
/// a second sheet with neither, so the filter's defined name must point at
/// tab 0 only.
Fixture _mergesFilter() {
  final Map<String, List<_LayoutRow>> sheets = <String, List<_LayoutRow>>{
    "Bob's Data": _filterRows,
    'Plain': _plainRows,
  };
  return Fixture(
    'm2_merges_filter',
    _storedOf(sheets),
    _expectedOf(sheets),
    () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter data = book.addSheet("Bob's Data");
      _writeRows(data, _filterRows);
      data
        ..merge(XlsxRange.parse('A1:D1'))
        ..merge(XlsxRange.parse('B3:C4'))
        ..autoFilter(XlsxRange.parse('A6:D20'));
      _writeRows(book.addSheet('Plain'), _plainRows);
      return book.close();
    },
  );
}

/// A probe for the parked M1 question: does a reader decode `_xHHHH_` inside
/// `<f>`? A1 is the formula `"_x0041_"`, written as given (a formula is not
/// escaped), and A2 is the same text as a string, which the writer escapes
/// to `_x005F_x0041_`, so a reader shows `_x0041_` for A2. A reader that
/// shows `A` for A1 decodes inside `<f>`; the Excel check records which.
///
/// The second sheet, `_x0041_`, has an auto filter. Its name is written
/// escaped as `_x005F_x0041_` (R22), while its `_xlnm._FilterDatabase` text
/// is a formula like `<f>` and reads `'_x0041_'!$A$1:$B$3` (R10), so the one
/// Excel check settles formulas and defined names together.
Fixture _formulaXstring() => Fixture(
  'm2_formula_xstring',
  <String, List<List<String>>>{
    'Probe': <List<String>>[
      <String>[''],
      <String>['_x005F_x0041_'],
    ],
    '_x0041_': <List<String>>[
      <String>['Key', 'Value'],
      <String>['a', '1'],
      <String>['b', '2'],
    ],
  },
  <String, List<List<Object?>>>{
    'Probe': <List<Object?>>[
      <Object?>['_x0041_'],
      <Object?>['_x0041_'],
    ],
    '_x0041_': <List<Object?>>[
      <Object?>['Key', 'Value'],
      <Object?>['a', 1],
      <Object?>['b', 2],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Probe')
      ..row(<Object?>[const XlsxFormula('"_x0041_"')])
      ..row(<Object?>['_x0041_']);
    book.addSheet('_x0041_')
      ..row(<Object?>['Key', 'Value'])
      ..row(<Object?>['a', 1])
      ..row(<Object?>['b', 2])
      ..autoFilter(XlsxRange.parse('A1:B3'));
    return book.close();
  },
);
