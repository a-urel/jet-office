/// The benchmark's workload: one sheet of mixed columns.
///
/// New in jet_office. Both writers of the benchmark write exactly this, so
/// their times and memory figures compare like for like.
library;

import 'package:jet_office/jet_office.dart';

const List<String> _names = <String>[
  'Aylin', 'Berk', 'Cem', 'Deniz', 'Ece', 'Fatih', 'Gizem', 'Hakan', 'Irmak', //
  'Jale', 'Kerem', 'Leyla', 'Mert', 'Nehir', 'Oguz', 'Pelin', 'Rana', 'Selim',
  'Tuba', 'Umut', 'Vildan', 'Yasin', 'Zeynep', 'Anna', 'Ben', 'Clara', 'David',
  'Elena', 'Felix', 'Greta', 'Hugo', 'Ida', 'Jonas', 'Klara', 'Lukas', 'Mia',
  'Noah', 'Olga', 'Paul', 'Quinn', 'Rosa', 'Sven', 'Tilda', 'Uwe', 'Vera',
  'Willi', 'Xaver', 'Yara', 'Zoe', 'Emil',
];

const List<String> _categories = <String>[
  'Food', 'Drink', 'Travel', 'Rent', 'Tools', 'Books', 'Music', 'Games',
  'Health', 'Other', //
];

/// The money format of the `Amount` and `Money` columns.
const XlsxStyle workloadMoney = XlsxStyle(
  numFmt: XlsxNumFmt.custom('#,##0.00'),
);
const XlsxStyle _date = XlsxStyle(numFmt: XlsxNumFmt.custom('yyyy-mm-dd'));
const XlsxStyle _stamp = XlsxStyle(
  numFmt: XlsxNumFmt.custom('yyyy-mm-dd hh:mm'),
);

/// The style of the header row.
const XlsxStyle workloadHeaderStyle = XlsxStyle(font: XlsxFont(bold: true));

/// The 12 columns' widths and styles, in order.
const List<XlsxColumn> workloadColumns = <XlsxColumn>[
  XlsxColumn(width: 12),
  XlsxColumn(width: 12),
  XlsxColumn(width: 10),
  XlsxColumn(width: 12, style: workloadMoney),
  XlsxColumn(width: 12),
  XlsxColumn(width: 18, style: _stamp),
  XlsxColumn(width: 12, style: _date),
  XlsxColumn(width: 8),
  XlsxColumn(width: 12),
  XlsxColumn(width: 12),
  XlsxColumn(width: 14),
  XlsxColumn(width: 12),
];

/// The header row's 12 texts.
const List<String> workloadHeader = <String>[
  'Id', 'Name', 'Number', 'Amount', 'Decimal', 'Stamp', //
  'Date', 'Even', 'Category', 'Product', 'Note', 'Money',
];

/// The first moment of the `Stamp` column; row `r` is `r` minutes later.
final DateTime workloadStart = DateTime(2026, 1, 1);

/// The 12 values of data row [r] (1-based), the last of them an [XlsxCell]
/// with a style and the `Note` one `null` when `r % 3 == 0`.
List<Object?> workloadRow(int r) => <Object?>[
  'C-$r',
  _names[r % 50],
  r,
  r * 1.25,
  XlsxDecimal('$r.50'),
  workloadStart.add(Duration(minutes: r)),
  XlsxDate(2026, 1 + r % 12, 1 + r % 28),
  r.isEven,
  _categories[r % 10],
  XlsxFormula('C$r*D$r'),
  r % 3 == 0 ? null : 'note ${r % 1000}',
  XlsxCell(r * 3, style: workloadMoney),
];

/// Writes a header row and then [rows] data rows of 12 columns to [sheet].
///
/// Column widths, a money format and two date formats are set first. After
/// each data row `r` (1-based) [onRow] is called with `r`, so the caller can
/// sample memory.
void writeWorkload(
  XlsxSheetWriter sheet,
  int rows,
  void Function(int row) onRow,
) {
  sheet.columns(workloadColumns);
  sheet.row(workloadHeader, style: workloadHeaderStyle);
  for (int r = 1; r <= rows; r++) {
    sheet.row(workloadRow(r));
    onRow(r);
  }
}
