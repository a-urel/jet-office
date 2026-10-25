/// The fixtures of milestone M3 (sheet and workbook features).
///
/// New in jet_office. Each M3 task appends its fixtures to [m3Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M3.
List<Fixture> m3Fixtures() => <Fixture>[_names()];

/// Defined names, a print area and print titles.
///
/// The workbook name `TaxRate` is `0.18`, and `Data!A1` uses it:
/// `TaxRate*100`. `Data` has the sheet-scoped name `Local`, which stands for
/// `Data!$B$2`. `O'Brien`, a name that needs quoting, has a print area of two
/// ranges and print titles of its header row and first column, so the
/// workbook's `_xlnm.Print_Area` and `_xlnm.Print_Titles` must be quoted,
/// absolute and scoped to its tab (1). Excel's Name Manager and Page Setup
/// show them; the values below are what a reader computes.
Fixture _names() => Fixture(
  'm3_names',
  <String, List<List<String>>>{
    'Data': <List<String>>[
      <String>['18', 'Tax percent'],
      <String>['Local', '5'],
    ],
    "O'Brien": <List<String>>[
      <String>['Id', 'Name', '', 'Note'],
      <String>['1', 'one', '', 'a'],
      <String>['2', 'two', '', 'b'],
      <String>['3', 'three', '', ''],
    ],
  },
  <String, List<List<Object?>>>{
    'Data': <List<Object?>>[
      <Object?>[18, 'Tax percent'],
      <Object?>['Local', 5],
    ],
    "O'Brien": <List<Object?>>[
      <Object?>['Id', 'Name', null, 'Note'],
      <Object?>[1, 'one', null, 'a'],
      <Object?>[2, 'two', null, 'b'],
      <Object?>[3, 'three'],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Data')
      ..row(<Object?>[
        const XlsxFormula('TaxRate*100', cached: 18),
        'Tax percent',
      ])
      ..row(<Object?>['Local', 5])
      ..defineName(const XlsxDefinedName('Local', r'Data!$B$2'));
    book.addSheet("O'Brien")
      ..row(<Object?>['Id', 'Name', null, 'Note'])
      ..row(<Object?>[1, 'one', null, 'a'])
      ..row(<Object?>[2, 'two', null, 'b'])
      ..row(<Object?>[3, 'three'])
      ..printArea(<XlsxRange>[
        XlsxRange.parse('A1:B4'),
        XlsxRange.parse('D1:D3'),
      ])
      ..printTitles(rows: (0, 0), columns: (0, 0));
    book.defineName(const XlsxDefinedName('TaxRate', '0.18'));
    return book.close();
  },
);
