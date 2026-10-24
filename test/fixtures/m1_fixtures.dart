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
/// Whole-number doubles are avoided on purpose: `1.0` prints as `1` on the
/// web and `1.0` on the VM, so the fixtures use `int`s for whole numbers.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

/// A named workbook builder with the values its file stores.
final class Fixture {
  /// Creates a fixture. [run] builds the workbook.
  Fixture(this.name, this.expectedValues, XlsxResult Function() run)
    : _run = run;

  final XlsxResult Function() _run;

  /// The fixture's name, also its file name stem.
  final String name;

  /// Sheet name (the final, sanitized one) to rows of stored cell text.
  final Map<String, List<List<String>>> expectedValues;

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
      ..row(<Object?>['\u{1F600} emoji \u{1F468}‍\u{1F469}']);
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
];

Fixture _sheets() => Fixture(
  'm1_sheets',
  <String, List<List<String>>>{
    for (final (String asked, String got) in _sheetNames)
      got: <List<String>>[
        <String>['asked: $asked'],
      ],
    'Başlangıç': <List<String>>[
      <String>['asked: Başlangıç'],
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
