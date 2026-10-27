/// The fixtures of milestone M5 (the list export helper).
///
/// New in jet_office. Each M5 task appends its fixtures to [m5Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M5.
List<Fixture> m5Fixtures() => <Fixture>[_listPlain(), _listTable()];

/// The account rows of `m5_list_plain`: code, name, balance and the date
/// the account was opened, whose serial is the last entry (`null` for no
/// date).
const List<(String, String, num, XlsxDate?, int?)> _accounts =
    <(String, String, num, XlsxDate?, int?)>[
      ('A-001', 'Anadolu Bank', 1250.5, XlsxDate(2024, 1, 15), 45306),
      ('A-002', 'Bosphorus Trade', -320.75, XlsxDate(2024, 2, 3), 45325),
      ('A-003', 'Cappadocia Tours', 0, XlsxDate(2024, 3, 28), 45379),
      ('A-004', 'Delta Logistics', 98765.43, XlsxDate(2024, 4, 9), 45391),
      ('A-005', 'Ege Textiles', 15.2, null, null),
      ('A-006', 'Fırat Energy', 4200, XlsxDate(2024, 6, 30), 45473),
      ('A-007', 'Galata Café', -1500, XlsxDate(2024, 7, 1), 45474),
      ('A-008', 'Haliç Marine', 333.33, XlsxDate(2024, 8, 12), 45516),
      ('A-009', 'İzmir Foods', 7.07, XlsxDate(2024, 9, 23), 45558),
      ('A-010', 'Kars Dairy', 120, XlsxDate(2024, 10, 31), 45596),
      ('A-011', 'Lycia Travel', 2500.99, XlsxDate(2024, 11, 11), 45607),
      ('A-012', 'Marmara Glass', 64.5, XlsxDate(2024, 12, 24), 45650),
    ];

/// A plain list export (Task 3 of the M5 plan) on two sheets.
///
/// `Accounts`: the caption `Accounts` in row 1, the header in row 2, the
/// twelve rows of [_accounts] in rows 3 to 14, and the totals in row 15:
/// `Total`, `SUBTOTAL(109,C3:C14)` and `SUBTOTAL(103,D3:D14)`. The balances
/// sum to 105436.27; eleven accounts have an opening date. `Empty`: the
/// same list without rows, so one empty data row (row 3) and totals over
/// it, both 0. Formula cells store no cached value; their expected values
/// are what LibreOffice computes.
Fixture _listPlain() => Fixture(
  'm5_list_plain',
  <String, List<List<String>>>{
    'Accounts': <List<String>>[
      <String>['Accounts', '', '', ''],
      <String>['Code', 'Name', 'Balance', 'Opened'],
      for (final (String, String, num, XlsxDate?, int?) a in _accounts)
        <String>[a.$1, a.$2, '${a.$3}', a.$5 == null ? '' : '${a.$5}'],
      <String>['Total', '', '', ''],
    ],
    'Empty': <List<String>>[
      <String>['Accounts', '', '', ''],
      <String>['Code', 'Name', 'Balance', 'Opened'],
      <String>['', '', '', ''],
      <String>['Total', '', '', ''],
    ],
  },
  <String, List<List<Object?>>>{
    'Accounts': <List<Object?>>[
      <Object?>['Accounts'],
      <Object?>['Code', 'Name', 'Balance', 'Opened'],
      for (final (String, String, num, XlsxDate?, int?) a in _accounts)
        <Object?>[a.$1, a.$2, a.$3, a.$5],
      <Object?>['Total', null, 105436.27, 11],
    ],
    'Empty': <List<Object?>>[
      <Object?>['Accounts'],
      <Object?>['Code', 'Name', 'Balance', 'Opened'],
      <Object?>[],
      <Object?>['Total', null, 0, 0],
    ],
  },
  () {
    final XlsxListExport export = XlsxListExport(<XlsxListColumn>[
      const XlsxListColumn('Code', width: 10),
      const XlsxListColumn('Name', width: 30),
      XlsxListColumn(
        'Balance',
        width: 16,
        style: XlsxStyle(numFmt: XlsxNumFmt.money()),
        totalsFunction: XlsxTotalsFunction.sum,
      ),
      const XlsxListColumn(
        'Opened',
        width: 12,
        style: XlsxStyle(numFmt: XlsxNumFmt.localeShortDate),
        totalsFunction: XlsxTotalsFunction.count,
      ),
    ], caption: 'Accounts');
    final XlsxWriter book = XlsxWriter();
    export.writeTo(book.addSheet('Accounts'), <List<Object?>>[
      for (final (String, String, num, XlsxDate?, int?) a in _accounts)
        <Object?>[a.$1, a.$2, a.$3, a.$4],
    ]);
    export.writeTo(book.addSheet('Empty'), const <List<Object?>>[]);
    return book.close();
  },
);

/// The `Accounts` list of `m5_list_plain` as an Excel table (Task 4 of the
/// M5 plan), sheet `Accounts`: the caption in row 1, the table `Accounts` in
/// A2:D15 with the header in row 2, the twelve rows in rows 3 to 14 and the
/// totals row 15, in table style Medium 2. The writer fills in the totals
/// (`Total`, `SUBTOTAL(109,C3:C14)`, `SUBTOTAL(103,D3:D14)`); the expected
/// values are what LibreOffice computes.
Fixture _listTable() => Fixture(
  'm5_list_table',
  <String, List<List<String>>>{
    'Accounts': <List<String>>[
      <String>['Accounts', '', '', ''],
      <String>['Code', 'Name', 'Balance', 'Opened'],
      for (final (String, String, num, XlsxDate?, int?) a in _accounts)
        <String>[a.$1, a.$2, '${a.$3}', a.$5 == null ? '' : '${a.$5}'],
      <String>['Total', '', '', ''],
    ],
  },
  <String, List<List<Object?>>>{
    'Accounts': <List<Object?>>[
      <Object?>['Accounts'],
      <Object?>['Code', 'Name', 'Balance', 'Opened'],
      for (final (String, String, num, XlsxDate?, int?) a in _accounts)
        <Object?>[a.$1, a.$2, a.$3, a.$5],
      <Object?>['Total', null, 105436.27, 11],
    ],
  },
  () {
    final XlsxListExport export = XlsxListExport(
      <XlsxListColumn>[
        const XlsxListColumn('Code', width: 10),
        const XlsxListColumn('Name', width: 30),
        XlsxListColumn(
          'Balance',
          width: 16,
          style: XlsxStyle(numFmt: XlsxNumFmt.money()),
          totalsFunction: XlsxTotalsFunction.sum,
        ),
        const XlsxListColumn(
          'Opened',
          width: 12,
          style: XlsxStyle(numFmt: XlsxNumFmt.localeShortDate),
          totalsFunction: XlsxTotalsFunction.count,
        ),
      ],
      caption: 'Accounts',
      excelTable: true,
      tableName: 'Accounts',
      tableStyle: XlsxTableStyle.medium(2),
    );
    final XlsxWriter book = XlsxWriter();
    export.writeTo(book.addSheet('Accounts'), <List<Object?>>[
      for (final (String, String, num, XlsxDate?, int?) a in _accounts)
        <Object?>[a.$1, a.$2, a.$3, a.$4],
    ]);
    return book.close();
  },
);
