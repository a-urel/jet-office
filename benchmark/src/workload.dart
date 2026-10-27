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

const XlsxStyle _money = XlsxStyle(numFmt: XlsxNumFmt.custom('#,##0.00'));
const XlsxStyle _date = XlsxStyle(numFmt: XlsxNumFmt.custom('yyyy-mm-dd'));
const XlsxStyle _stamp = XlsxStyle(
  numFmt: XlsxNumFmt.custom('yyyy-mm-dd hh:mm'),
);
const XlsxStyle _header = XlsxStyle(font: XlsxFont(bold: true));

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
  sheet.columns(<XlsxColumn?>[
    const XlsxColumn(width: 12),
    const XlsxColumn(width: 12),
    const XlsxColumn(width: 10),
    const XlsxColumn(width: 12, style: _money),
    const XlsxColumn(width: 12),
    const XlsxColumn(width: 18, style: _stamp),
    const XlsxColumn(width: 12, style: _date),
    const XlsxColumn(width: 8),
    const XlsxColumn(width: 12),
    const XlsxColumn(width: 12),
    const XlsxColumn(width: 14),
    const XlsxColumn(width: 12),
  ]);
  sheet.row(<Object?>[
    'Id', 'Name', 'Number', 'Amount', 'Decimal', 'Stamp', //
    'Date', 'Even', 'Category', 'Product', 'Note', 'Money',
  ], style: _header);
  final DateTime start = DateTime(2026, 1, 1);
  for (int r = 1; r <= rows; r++) {
    sheet.row(<Object?>[
      'C-$r',
      _names[r % 50],
      r,
      r * 1.25,
      XlsxDecimal('$r.50'),
      start.add(Duration(minutes: r)),
      XlsxDate(2026, 1 + r % 12, 1 + r % 28),
      r.isEven,
      _categories[r % 10],
      XlsxFormula('C$r*D$r'),
      r % 3 == 0 ? null : 'note ${r % 1000}',
      XlsxCell(r * 3, style: _money),
    ]);
    onRow(r);
  }
}
