/// Deterministic M1 workbooks and the cell values each file stores.
///
/// Task 15 opens every fixture in LibreOffice and compares its CSV export of
/// each sheet with [Fixture.expectedValues]. The expectations therefore
/// describe what the file contains, not what the caller passed in: numbers
/// as the encoder writes them in `<v>` (a whole date serial is an integer),
/// dates as serials, booleans as `1`/`0`, strings after scrubbing and
/// truncation, and empty cells as `''`. Each sheet's rows form a rectangle
/// that ends at the last row and column holding a cell.
///
/// Excel and LibreOffice decode `_xHHHH_` in cell text (ST_Xstring), so the
/// writer stores text that looks like such an escape with its `_` escaped as
/// `_x005F_`. [Fixture.storedValues] hold that stored form, while
/// [Fixture.expectedValues] hold the text a reader shows, which is the text
/// the caller passed in.
///
/// Whole-number doubles are avoided on purpose: `1.0` prints as `1` on the
/// web and `1.0` on the VM, so the fixtures use `int`s for whole numbers.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

/// A named workbook builder with the values its file stores.
final class Fixture {
  /// Creates a fixture. [run] builds the workbook.
  Fixture(
    this.name,
    this.storedValues,
    this.expectedValues,
    XlsxResult Function() run,
  ) : _run = run;

  final XlsxResult Function() _run;

  /// The fixture's name, also its file name stem.
  final String name;

  /// Sheet name (the final, sanitized one) to rows of the text stored in the
  /// file: numbers as in `<v>`, dates as serials, booleans `1`/`0`, strings
  /// after scrubbing and truncation and with `_xHHHH_` look-alikes escaped,
  /// empty cells `''`. Rectangular per sheet. The tests check it against the
  /// file itself.
  final Map<String, List<List<String>>> storedValues;

  /// Sheet name to rows of the values a reader should see, typed: `String`
  /// for text, `num` for numbers and date serials, `bool` for booleans and
  /// `null` for empty cells. A formula cell holds the value Excel or
  /// LibreOffice computes.
  ///
  /// The comparison contract Task 15 implements against LibreOffice's CSV
  /// export: raw (not formatted) values; numbers are equal within a relative
  /// tolerance of 1e-12; a `bool` matches `TRUE`/`FALSE` or `1`/`0`; strings
  /// are equal exactly (a stored string is compared after decoding its
  /// `_xHHHH_` escapes, as a reader does); `null` matches `""`; trailing
  /// empty rows and trailing empty cells are ignored on both sides. A CSV
  /// cannot tell an empty sheet from a sheet whose only cell is `''`, so
  /// both expect no rows; the checker and [storedValues] still tell them
  /// apart.
  final Map<String, List<List<Object?>>> expectedValues;

  /// Builds the workbook and returns its bytes. The same bytes every time.
  Uint8List build() => _run().bytes;

  /// The warnings [build] produces.
  List<XlsxWarning> warnings() => _run().warnings;
}

/// The seven fixtures of milestone M1.
List<Fixture> m1Fixtures() => <Fixture>[
  _values(),
  _dirtyText(),
  _sheets(),
  _formulas(),
  _empty(),
  _properties(),
  _dates(),
];

XlsxResult _make(
  void Function(XlsxWriter book) script, {
  XlsxProperties properties = const XlsxProperties(),
}) {
  final XlsxWriter book = XlsxWriter(properties: properties);
  script(book);
  return book.close();
}

const XlsxStyle _twoDecimals = XlsxStyle(numFmt: XlsxNumFmt.custom('#,##0.00'));

Fixture _values() => Fixture(
  'm1_values',
  <String, List<List<String>>>{
    'Values': <List<String>>[
      <String>[
        'int',
        'double',
        'negative',
        'true',
        'false',
        'text',
        'decimal',
        'date',
        'datetime',
        'styled',
        'gap',
        'big',
      ],
      <String>[
        '42',
        '3.14159',
        '-0.25',
        '1',
        '0',
        'plain text',
        '1234.50',
        '46319',
        '46319.572916666664',
        '1234.5',
        '',
        '9007199254740992',
      ],
    ],
  },
  <String, List<List<Object?>>>{
    'Values': <List<Object?>>[
      <Object?>[
        'int',
        'double',
        'negative',
        'true',
        'false',
        'text',
        'decimal',
        'date',
        'datetime',
        'styled',
        'gap',
        'big',
      ],
      <Object?>[
        42,
        3.14159,
        -0.25,
        true,
        false,
        'plain text',
        1234.5,
        46319,
        46319.5729166666,
        1234.5,
        null,
        9007199254740992,
      ],
    ],
  },
  () => _make((XlsxWriter book) {
    book.addSheet('Values')
      ..row(<Object?>[
        'int',
        'double',
        'negative',
        'true',
        'false',
        'text',
        'decimal',
        'date',
        'datetime',
        'styled',
        'gap',
        'big',
      ])
      ..row(<Object?>[
        42,
        3.14159,
        -0.25,
        true,
        false,
        'plain text',
        XlsxDecimal('1234.50'),
        const XlsxDate(2026, 10, 24),
        DateTime(2026, 10, 24, 13, 45),
        const XlsxCell(1234.5, style: _twoDecimals),
        null,
        9007199254740992,
      ]);
  }),
);

/// 32,766 `a`s then an emoji: 32,768 code units, and a cut at 32,767 would
/// split the emoji's surrogate pair.
final String _pairAtLimit = '${'a' * 32766}\u{1F600}';

Fixture _dirtyText() => Fixture(
  'm1_dirty_text',
  <String, List<List<String>>>{
    'Text': <List<String>>[
      <String>['abcd'],
      <String>['xy'],
      <String>['pq'],
      <String>['a' * 32767],
      <String>['a' * 32766],
      <String>['  padded  '],
      <String>['Şube Müdürü'],
      <String>['Straße'],
      <String>['\u{1F600} emoji \u{1F468}‍\u{1F469}'],
      <String>['_x005F_x0041_'],
      <String>['a_x005F_x00e9_b'],
    ],
  },
  <String, List<List<Object?>>>{
    'Text': <List<Object?>>[
      <Object?>['abcd'],
      <Object?>['xy'],
      <Object?>['pq'],
      <Object?>['a' * 32767],
      <Object?>['a' * 32766],
      <Object?>['  padded  '],
      <Object?>['Şube Müdürü'],
      <Object?>['Straße'],
      <Object?>['\u{1F600} emoji \u{1F468}\u200D\u{1F469}'],
      <Object?>['_x0041_'],
      <Object?>['a_x00e9_b'],
    ],
  },
  () => _make((XlsxWriter book) {
    book.addSheet('Text')
      ..row(<Object?>['a\u0000b\u0008c\u000Bd']) // control characters
      ..row(<Object?>['x\uD800y']) // lone high surrogate
      ..row(<Object?>['p\uDC00q']) // lone low surrogate
      ..row(<Object?>['a' * 40000]) // cut to the cell limit
      ..row(<Object?>[_pairAtLimit]) // cut before the surrogate pair
      ..row(<Object?>['  padded  '])
      ..row(<Object?>['Şube Müdürü'])
      ..row(<Object?>['Straße'])
      ..row(<Object?>['\u{1F600} emoji \u{1F468}‍\u{1F469}'])
      ..row(<Object?>['_x0041_']) // shown as typed, not as `A`
      ..row(<Object?>['a_x00e9_b']); // shown as typed, not as `aéb`
  }),
);

/// The names asked for, in order, and the names the file gets.
const List<(String, String)> _sheetNames = <(String, String)>[
  ('Özet', 'Özet'),
  ('a/b', 'a_b'),
  ('A_B', 'A_B (2)'),
  ('ŞUBE', 'ŞUBE'),
  ('şube', 'şube (2)'),
  ('LİSTE', 'LİSTE'),
  ('liste', 'liste (2)'),
  ('STRASSE', 'STRASSE'),
  ('straße', 'straße (2)'),
  ('', 'Sheet10'),
  ('History', 'History (2)'),
  ('this name is far longer than allowed', 'this name is far longer than al'),
  // Written verbatim (ruling R19); docs/excel-checks.md asks how Excel
  // shows it.
  ('_x0041_', '_x0041_'),
];

/// [text] as the writer stores it in a cell: an `_` that starts an
/// `_xHHHH_` look-alike is escaped as `_x005F_`.
String _storedText(String text) =>
    text.replaceAll(RegExp(r'_(?=x[0-9A-Fa-f]{4}_)'), '_x005F_');

Fixture _sheets() => Fixture(
  'm1_sheets',
  <String, List<List<String>>>{
    for (final (String asked, String got) in _sheetNames)
      got: <List<String>>[
        <String>['asked: ${_storedText(asked)}'],
      ],
    'Başlangıç': <List<String>>[
      <String>['asked: Başlangıç'],
    ],
  },
  <String, List<List<Object?>>>{
    for (final (String asked, String got) in _sheetNames)
      got: <List<Object?>>[
        <Object?>['asked: $asked'],
      ],
    'Başlangıç': <List<Object?>>[
      <Object?>['asked: Başlangıç'],
    ],
  },
  () => _make((XlsxWriter book) {
    XlsxSheetWriter? active;
    for (final (String asked, String got) in _sheetNames) {
      final XlsxSheetWriter sheet = book.addSheet(asked);
      sheet.row(<Object?>['asked: $asked']);
      if (got == 'şube (2)') active = sheet;
    }
    book.addSheet('Başlangıç', position: 0).row(<Object?>['asked: Başlangıç']);
    book.setActiveSheet(active!);
  }),
);

Fixture _formulas() => Fixture(
  'm1_formulas',
  <String, List<List<String>>>{
    'Formulas': <List<String>>[
      <String>['2', 'hello', '1', ''],
    ],
  },
  <String, List<List<Object?>>>{
    'Formulas': <List<Object?>>[
      <Object?>[2, 'hello', true, 3],
    ],
  },
  () => _make((XlsxWriter book) {
    book.addSheet('Formulas').row(<Object?>[
      const XlsxFormula('SUM(1,1)', cached: 2),
      const XlsxFormula('CONCATENATE("hel","lo")', cached: 'hello'),
      const XlsxFormula('AND(TRUE,TRUE)', cached: true),
      const XlsxFormula('1+2'),
    ]);
  }),
);

Fixture _empty() => Fixture(
  'm1_empty',
  <String, List<List<String>>>{
    'Empty': <List<String>>[],
    'Nulls': <List<String>>[
      <String>[''],
      <String>['x'],
    ],
    'Blank': <List<String>>[
      <String>['a', ''],
      <String>['', ''],
      <String>['', 'b'],
    ],
    'EmptyString': <List<String>>[
      <String>[''],
    ],
  },
  // Trailing empty rows and cells are ignored, so `Empty` and `EmptyString`
  // both expect no rows (a CSV cannot tell them apart); `storedValues` and
  // the checker still do.
  <String, List<List<Object?>>>{
    'Empty': <List<Object?>>[],
    'Nulls': <List<Object?>>[
      <Object?>[null],
      <Object?>['x'],
    ],
    'Blank': <List<Object?>>[
      <Object?>['a', null],
      <Object?>[null, null],
      <Object?>[null, 'b'],
    ],
    'EmptyString': <List<Object?>>[],
  },
  () => _make((XlsxWriter book) {
    book.addSheet('Empty');
    book.addSheet('Nulls')
      ..row(<Object?>[null, null])
      ..row(<Object?>['x']);
    book.addSheet('Blank')
      ..row(<Object?>['a'])
      ..blankRow()
      ..row(<Object?>[null, 'b']);
    book.addSheet('EmptyString').row(<Object?>['']);
  }),
);

Fixture _properties() => Fixture(
  'm1_properties',
  <String, List<List<String>>>{
    'Props': <List<String>>[
      <String>['properties'],
    ],
  },
  <String, List<List<Object?>>>{
    'Props': <List<Object?>>[
      <Object?>['properties'],
    ],
  },
  () => _make(
    (XlsxWriter book) {
      book.addSheet('Props').row(<Object?>['properties']);
    },
    properties: XlsxProperties(
      title: 'Quarterly report',
      subject: 'Sales',
      creator: 'Ahmet Urel',
      keywords: 'sales; q3',
      description: 'A test workbook',
      lastModifiedBy: 'jet_office',
      category: 'Reports',
      company: 'Jetronik',
      created: DateTime.utc(2026, 10, 24, 8, 30),
      modified: DateTime.utc(2026, 10, 24, 9, 45, 30),
    ),
  ),
);

Fixture _dates() => Fixture(
  'm1_dates',
  <String, List<List<String>>>{
    'Dates': <List<String>>[
      <String>[
        '59',
        '61',
        '46319',
        '46319.999999988424',
        '1850-06-15T00:00:00.000',
        '46319',
      ],
    ],
  },
  <String, List<List<Object?>>>{
    'Dates': <List<Object?>>[
      <Object?>[
        59,
        61,
        46319,
        46319.99999998842,
        '1850-06-15T00:00:00.000',
        46319,
      ],
    ],
  },
  () => _make((XlsxWriter book) {
    book.addSheet('Dates').row(<Object?>[
      const XlsxDate(1900, 2, 28),
      const XlsxDate(1900, 3, 1),
      DateTime(2026, 10, 24),
      DateTime(2026, 10, 24, 23, 59, 59, 999),
      DateTime(1850, 6, 15), // before 1900: ISO text and a warning
      const XlsxCell(XlsxDate(2026, 10, 24), style: _twoDecimals),
    ]);
  }),
);
