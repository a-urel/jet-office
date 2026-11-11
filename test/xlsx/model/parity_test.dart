import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart' show Fixture, allFixtures;
import '../../fixtures/m1_fixtures.dart';
import '../../fixtures/m2_fixtures.dart';
import '../../fixtures/m3_fixtures.dart';
import '../../fixtures/m4_fixtures.dart';
import '../../fixtures/m5_fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/zip_builder.dart';

/// Rows of cell values for each sheet, in tab order, as the writer fixture
/// writes them.
typedef _Sheets = List<(String, List<List<Object?>>)>;

/// The fixtures of plain rows, rebuilt with the model.
///
/// The fixtures that set more than cells are in [_scripted].
final Map<String, _Sheets> _rebuilt = <String, _Sheets>{
  'm1_values': <(String, List<List<Object?>>)>[('Values', m1ValuesRows())],
  'm1_dates': <(String, List<List<Object?>>)>[
    ('Dates', <List<Object?>>[m1DatesRow()]),
  ],
  'm2_styles': <(String, List<List<Object?>>)>[
    (
      'Styles',
      <List<Object?>>[
        for (final (Object value, XlsxStyle style, String label)
            in m2StyleRows())
          <Object?>[XlsxCell(value, style: style), label],
      ],
    ),
  ],
  'm1_dirty_text': <(String, List<List<Object?>>)>[
    (
      'Text',
      <List<Object?>>[
        <Object?>['a\u0000b\u0008c\u000Bd'],
        <Object?>['x\uD800y'],
        <Object?>['p\uDC00q'],
        <Object?>['a' * 40000],
        <Object?>['${'a' * 32766}\u{1F600}'],
        <Object?>['  padded  '],
        <Object?>['Şube Müdürü'],
        <Object?>['Straße'],
        <Object?>['\u{1F600} emoji \u{1F468}‍\u{1F469}'],
        <Object?>['_x0041_'],
        <Object?>['a_x00e9_b'],
      ],
    ),
  ],
  'm1_formulas': <(String, List<List<Object?>>)>[
    (
      'Formulas',
      <List<Object?>>[
        <Object?>[
          const XlsxFormula('SUM(1,1)', cached: 2),
          const XlsxFormula('CONCATENATE("hel","lo")', cached: 'hello'),
          const XlsxFormula('AND(TRUE,TRUE)', cached: true),
          const XlsxFormula('1+2'),
        ],
      ],
    ),
  ],
  'm1_empty': <(String, List<List<Object?>>)>[
    ('Empty', <List<Object?>>[]),
    (
      'Nulls',
      <List<Object?>>[
        <Object?>[null, null],
        <Object?>['x'],
      ],
    ),
    (
      'Blank',
      <List<Object?>>[
        <Object?>['a'],
        <Object?>[],
        <Object?>[null, 'b'],
      ],
    ),
    (
      'EmptyString',
      <List<Object?>>[
        <Object?>[''],
      ],
    ),
  ],
};

/// The fixtures that set more than cells, rebuilt with the model in the
/// writer's call order.
final Map<String, XlsxResult Function()> _scripted =
    <String, XlsxResult Function()>{
      'm1_sheets': _sheetsBook,
      'm2_columns_rows': _columnsRowsBook,
      'm2_style_precedence': _precedenceBook,
      'm2_views': _viewsBook,
      'm2_merges_filter': _mergesBook,
      'm2_formula_xstring': _formulaBook,
      'm1_properties': _propertiesBook,
      'm3_names': _namesBook,
      'm3_hyperlinks': _linksBook,
      'm3_validation': _validationBook,
      'm3_conditional': _conditionalBook,
      'm3_conditional_x14': _conditionalX14Book,
      'm3_page_setup': _pageSetupBook,
      'm3_header_footer': _headerFooterBook,
      'm3_protection': _protectionBook,
      'm3_properties': _m3PropertiesBook,
      'm4_rich_text': _richTextBook,
      'm4_notes': _notesBook,
      'm4_images': _imagesBook,
      'm4_tables': _tablesBook,
      'm4_objects': _objectsBook,
      'm5_list_plain': _listPlainBook,
      'm5_list_table': _listTableBook,
    };

/// The fixtures the model does not rebuild, each with its reason.
const Map<String, String> _notRebuilt = <String, String>{
  'c1_kinds':
      'its charts are written by writeDrawingChartSpace into a '
      'test-only host; the model hosts charts in C2',
  'c1_options':
      'its charts are written by writeDrawingChartSpace into a '
      'test-only host; the model hosts charts in C2',
};

/// Where the model's file may differ from the writer's, applied to the
/// expected package, each with its reason. Everything else of the fixture
/// is compared.
final Map<String, Uint8List Function(Uint8List)> _allowed =
    <String, Uint8List Function(Uint8List)>{
      // The active sheet is the fifth part (see [_tabSelected]).
      'm1_sheets': (Uint8List bytes) =>
          _tabSelected(bytes, 'xl/worksheets/sheet5.xml'),
      'm2_views': (Uint8List bytes) =>
          _tabSelected(bytes, 'xl/worksheets/sheet3.xml'),
    };

/// [bytes] with [edit] applied to the text of the [parts] it selects.
Uint8List _edited(
  Uint8List bytes,
  bool Function(String name) parts,
  String Function(String text) edit,
) => buildZipOrdered(<(String, List<int>)>[
  for (final MapEntry<String, Uint8List> p in readXlsxBytes(bytes).entries)
    (p.key, parts(p.key) ? utf8.encode(edit(utf8.decode(p.value))) : p.value),
]);

/// [bytes] with `tabSelected="1"` on the view of the sheet [part].
///
/// Setting `activeSheet` moves `tabSelected` with `activeTab`, as Excel
/// saves them; the writer writes only `activeTab`, which Excel also accepts.
/// The writer's bytes stay as they are, so this difference stays.
Uint8List _tabSelected(Uint8List bytes, String part) => _edited(
  bytes,
  (String name) => name == part,
  (String text) =>
      text.replaceFirst('<sheetView ', '<sheetView tabSelected="1" '),
);

/// Writes [rows] to [sheet] from row 0, as the writer's `row` writes them:
/// the row's attributes first (no style: `setRowFormat` gets none), then each
/// cell. A row's `style` is merged under the cell's own by hand, and `setCell`
/// lays the column's style under that result, as the writer does.
void _writeRows(XlsxSheet sheet, List<M2LayoutRow> rows) {
  for (int r = 0; r < rows.length; r++) {
    final M2LayoutRow row = rows[r];
    sheet.setRowFormat(
      r,
      XlsxRowFormat(
        height: row.height,
        hidden: row.hidden,
        outlineLevel: row.outlineLevel,
        collapsed: row.collapsed,
      ),
    );
    for (int c = 0; c < row.values.length; c++) {
      final Object? value = row.values[c];
      if (value == null) continue;
      final XlsxStyle? own = value is XlsxCell ? value.style : null;
      sheet.setCell(
        r,
        c,
        XlsxCell(
          value is XlsxCell ? value.value : value,
          style: row.style?.merge(own) ?? own,
        ),
      );
    }
  }
}

/// Sets [columns] on [sheet], as the writer's `columns` does.
void _setColumns(XlsxSheet sheet, List<XlsxColumn?> columns) {
  for (int i = 0; i < columns.length; i++) {
    if (columns[i] case final XlsxColumn column) sheet.setColumn(i, column);
  }
}

XlsxResult _sheetsBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  XlsxSheet? active;
  for (final (String asked, String got) in m1SheetNames) {
    final XlsxSheet sheet = book.addSheet(asked);
    sheet.setCell(0, 0, 'asked: $asked');
    if (got == 'şube (2)') active = sheet;
  }
  book.addSheet('Başlangıç', position: 0).setCell(0, 0, 'asked: Başlangıç');
  book.activeSheet = active!;
  return book.save();
}

XlsxResult _columnsRowsBook() {
  final Map<String, List<M2LayoutRow>> rows = m2SheetRows()['m2_columns_rows']!;
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet layout = book.addSheet('Layout');
  _setColumns(layout, m2LayoutColumns);
  _writeRows(layout, rows['Layout']!);
  final XlsxSheet defaults = book.addSheet('Defaults')
    ..setDefaultSizes(rowHeight: 18, columnWidth: 11);
  _writeRows(defaults, rows['Defaults']!);
  return book.save();
}

XlsxResult _precedenceBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet sheet = book.addSheet('Precedence');
  _setColumns(sheet, m2PrecedenceColumns());
  _writeRows(sheet, m2SheetRows()['m2_style_precedence']!['Precedence']!);
  return book.save();
}

XlsxResult _viewsBook() {
  final Map<String, List<M2LayoutRow>> rows = m2SheetRows()['m2_views']!;
  final XlsxWorkbook book = XlsxWorkbook();
  XlsxSheet add(String name) {
    final XlsxSheet sheet = book.addSheet(name);
    _writeRows(sheet, rows[name]!);
    return sheet;
  }

  add('Frozen').view = const XlsxSheetView(
    pane: XlsxPane.frozen(rows: 1, columns: 1),
  );
  add('Split').view = const XlsxSheetView(pane: XlsxPane.split(x: 120, y: 60));
  final XlsxSheet view = add('View')
    ..view = const XlsxSheetView(
      zoom: 85,
      showGridLines: false,
      showHeadings: false,
      showZeros: false,
    )
    ..tabColor = const XlsxColor.rgb(0xFF0000);
  add('RTL').view = const XlsxSheetView(rightToLeft: true);
  add('Outline').setOutlineSummary(below: false);
  add('Hidden').visibility = XlsxSheetVisibility.hidden;
  add('VeryHidden').visibility = XlsxSheetVisibility.veryHidden;
  book.activeSheet = view;
  return book.save();
}

XlsxResult _mergesBook() {
  final Map<String, List<M2LayoutRow>> rows =
      m2SheetRows()['m2_merges_filter']!;
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet data = book.addSheet("Bob's Data");
  _writeRows(data, rows["Bob's Data"]!);
  data
    ..merge(XlsxRange.parse('A1:D1'))
    ..merge(XlsxRange.parse('B3:C4'));
  data.autoFilter = XlsxRange.parse('A6:D20');
  _writeRows(book.addSheet('Plain'), rows['Plain']!);
  return book.save();
}

XlsxResult _formulaBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Probe'), <List<Object?>>[
    <Object?>[const XlsxFormula('"_x0041_"')],
    <Object?>['_x0041_'],
  ]);
  _fill(book.addSheet('_x0041_'), <List<Object?>>[
    <Object?>['Key', 'Value'],
    <Object?>['a', 1],
    <Object?>['b', 2],
  ]).autoFilter = XlsxRange.parse(
    'A1:B3',
  );
  return book.save();
}

XlsxResult _propertiesBook() {
  final XlsxWorkbook book = XlsxWorkbook()..properties = m1Properties();
  book.addSheet('Props').setCell(0, 0, 'properties');
  return book.save();
}

XlsxResult _namesBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet data = _fill(book.addSheet('Data'), <List<Object?>>[
    <Object?>[const XlsxFormula('TaxRate*100', cached: 18), 'Tax percent'],
    <Object?>['Local', 5],
  ]);
  final XlsxSheet other = _fill(book.addSheet("O'Brien"), <List<Object?>>[
    <Object?>['Id', 'Name', null, 'Note'],
    <Object?>[1, 'one', null, 'a'],
    <Object?>[2, 'two', null, 'b'],
    <Object?>[3, 'three'],
  ]);
  // The writer's output order: the workbook's names, then each tab's.
  book.defineName(const XlsxDefinedName('TaxRate', '0.18'));
  data.defineName(const XlsxDefinedName('Local', r'Data!$B$2'));
  other
    ..printArea = <XlsxRange>[
      XlsxRange.parse('A1:B4'),
      XlsxRange.parse('D1:D3'),
    ]
    ..setPrintTitles(rows: (0, 0), columns: (0, 0));
  return book.save();
}

XlsxResult _linksBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet links = book.addSheet('Links');
  _setColumns(links, m3LinkColumns);
  _fill(links, m3LinkRows());
  _fill(book.addSheet("O'Brien"), <List<Object?>>[
    <Object?>['top'],
    <Object?>[null, 'B2'],
    <Object?>[null, null, 'C3'],
  ]);
  book.defineName(const XlsxDefinedName('Target', r"'O''Brien'!$C$3"));
  return book.save();
}

XlsxResult _validationBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet form = _fill(book.addSheet('Form'), m3ValidationRows);
  m3Validations().forEach(form.addDataValidation);
  return book.save();
}

XlsxResult _conditionalBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet sheet = _fill(book.addSheet('Scores'), <List<Object?>>[
    m3ScoreHeader,
    ...m3ScoreRows(),
  ]);
  m3ScoreFormats().forEach(sheet.addConditionalFormat);
  return book.save();
}

XlsxResult _conditionalX14Book() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet sheet = _fill(book.addSheet('Bars'), <List<Object?>>[
    m3BarHeader,
    ...m3BarRows(),
  ]);
  m3BarFormats().forEach(sheet.addConditionalFormat);
  return book.save();
}

XlsxResult _pageSetupBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Landscape'), <List<Object?>>[
    <Object?>['a', 'b', 'c'],
    ...m3PageRows,
  ]).pageSetup = m3LandscapeSetup;
  _fill(book.addSheet('Scaled'), m3PageRows).pageSetup = m3ScaledSetup;
  return book.save();
}

XlsxResult _headerFooterBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Report'), m3ReportRows()).headerFooter =
      m3ReportHeaderFooter();
  return book.save();
}

XlsxResult _protectionBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Locked'), m3LockedRows).protection = m3SheetProtection;
  book.protection = m3WorkbookProtection;
  return book.save();
}

XlsxResult _m3PropertiesBook() {
  final XlsxWorkbook book = XlsxWorkbook()..properties = m3Properties();
  _fill(book.addSheet('Info'), <List<Object?>>[
    <Object?>['Properties', 'set'],
  ]);
  return book.save();
}

XlsxResult _richTextBook() {
  const XlsxFont bold = XlsxFont(bold: true);
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Rich'), <List<Object?>>[
    <Object?>[
      XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('Total: ', font: bold),
        XlsxTextRun('42'),
      ]),
    ],
    <Object?>[
      XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun(
          'Red italic',
          font: XlsxFont(italic: true, color: XlsxColor.rgb(0xFF0000)),
        ),
        XlsxTextRun(
          ' and underlined',
          font: XlsxFont(underline: XlsxUnderline.single),
        ),
      ]),
    ],
    <Object?>[
      XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('x'),
        XlsxTextRun('2', font: XlsxFont(script: XlsxFontScript.superscript)),
      ]),
    ],
    <Object?>[
      XlsxCell(
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('Bold', font: bold),
          XlsxTextRun(' in Arial 14'),
        ]),
        style: const XlsxStyle(font: XlsxFont(name: 'Arial', size: 14)),
      ),
    ],
    <Object?>[
      XlsxRichText(const <XlsxTextRun>[XlsxTextRun('Same text')]),
    ],
    <Object?>['Same text'],
  ]);
  return book.save();
}

XlsxResult _notesBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Notes'), <List<Object?>>[
      <Object?>[],
      <Object?>[null, 'Plain'],
      <Object?>[null, null, 'Rich'],
      <Object?>[null, null, null, 'Visible'],
    ])
    ..setNote(1, 1, XlsxNote.plain('Check this', author: 'Ahmet'))
    ..setNote(
      2,
      2,
      XlsxNote(
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('Ahmet:', font: XlsxFont(bold: true)),
          XlsxTextRun('\nThe total is checked.'),
        ]),
        author: 'Ahmet',
      ),
    )
    ..setNote(
      3,
      3,
      XlsxNote.plain('Always shown', author: 'Ayse Yilmaz', visible: true),
    );
  _fill(book.addSheet('Right'), <List<Object?>>[
    <Object?>['Note on XFD1', 'The last column'],
  ]).setNote(0, 16383, XlsxNote.plain('The last column', author: 'Ahmet'));
  _fill(book.addSheet('Bottom'), <List<Object?>>[
    <Object?>['Note on A1048576', 'The last row'],
  ]).setNote(1048575, 0, XlsxNote.plain('The last row', author: 'Ahmet'));
  return book.save();
}

XlsxResult _imagesBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Pictures'), <List<Object?>>[
      <Object?>[],
      <Object?>['PNG at B2, JPEG at E2'],
      <Object?>[],
      <Object?>[],
      <Object?>[],
      <Object?>['PNG over B6:D10'],
    ])
    ..addPicture(
      XlsxPicture(
        OfficeImage(png4x2),
        const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1)),
      ),
    )
    ..addPicture(
      XlsxPicture(
        OfficeImage(jpeg3x5),
        const XlsxOneCellAnchor(XlsxAnchorPoint(1, 4), width: 60),
      ),
    )
    ..addPicture(
      XlsxPicture(
        OfficeImage(png4x2),
        XlsxTwoCellAnchor.range(
          XlsxRange.parse('B6:D10'),
          resize: XlsxPictureResize.move,
        ),
        description: 'The PNG over B6:D10',
      ),
    );
  _fill(book.addSheet('Again'), <List<Object?>>[
    <Object?>[],
    <Object?>['The same PNG at A1'],
  ]).addPicture(
    XlsxPicture(
      OfficeImage(png4x2),
      const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
    ),
  );
  return book.save();
}

XlsxResult _tablesBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('Sales'), <List<Object?>>[
      <Object?>['Region', 'Amount'],
      <Object?>['North', 120, 'Checked', null, 'Paper', 15],
      <Object?>['South', 80, null, null, 'Ink', 30.5],
      <Object?>['East', 45.5],
    ])
    ..addTable(
      XlsxTable('Sales', XlsxRange.parse('A1:C5'), const <XlsxTableColumn>[
        XlsxTableColumn('Region', totalsLabel: 'Total'),
        XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
        XlsxTableColumn('Note'),
      ], totalsRow: true),
    )
    ..addTable(
      XlsxTable('Costs', XlsxRange.parse('E1:F3'), const <XlsxTableColumn>[
        XlsxTableColumn('Item'),
        XlsxTableColumn('Cost'),
      ], style: XlsxTableStyle.light(9, showColumnStripes: true)),
    );
  _fill(book.addSheet('Plain'), <List<Object?>>[
    <Object?>[1, 2],
    <Object?>[3, 4],
  ]).addTable(
    XlsxTable(
      'Numbers',
      XlsxRange.parse('A1:B2'),
      const <XlsxTableColumn>[XlsxTableColumn('X'), XlsxTableColumn('Y')],
      headerRow: false,
      style: null,
    ),
  );
  return book.save();
}

XlsxResult _objectsBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _fill(book.addSheet('All'), <List<Object?>>[
      <Object?>[
        XlsxHyperlink.url('https://example.com/a', text: 'Site A'),
        XlsxHyperlink.url('https://example.com/b', text: 'Site B'),
        'Noted',
      ],
      <Object?>[],
      <Object?>[],
      <Object?>['Bolt', 10, null, 'B-1', 0.25],
      <Object?>['Nut', 25, null, 'N-1', 0.1],
    ])
    ..setNote(0, 2, XlsxNote.plain('Check C1', author: 'Ahmet'))
    ..addPicture(
      XlsxPicture(
        OfficeImage(png4x2),
        const XlsxOneCellAnchor(XlsxAnchorPoint(1, 6)),
      ),
    )
    ..addTable(
      XlsxTable('Stock', XlsxRange.parse('A3:B5'), const <XlsxTableColumn>[
        XlsxTableColumn('Item'),
        XlsxTableColumn('Qty'),
      ]),
    )
    ..addTable(
      XlsxTable('Prices', XlsxRange.parse('D3:E5'), const <XlsxTableColumn>[
        XlsxTableColumn('Code'),
        XlsxTableColumn('Price'),
      ]),
    );
  _fill(book.addSheet('More'), <List<Object?>>[
    <Object?>['One note'],
  ]).setNote(0, 0, XlsxNote.plain('The second sheet', author: 'Ahmet'));
  return book.save();
}

/// A list of `m5_list_plain` and `m5_list_table`, as `XlsxListExport` writes
/// it, with the model's calls.
///
/// The caption in row 1, the header in row 2, [data] from row 3 (none: one
/// empty row) and the totals row `Total`, the sum of the balances and the
/// count of the dates. A column's width and style, a frozen header and the
/// header row as print titles come first. A plain list styles the header and
/// totals bold and filters the data rows; with [table] the header and totals
/// are plain and the table covers them. A row's style is laid under each
/// cell's; the model lays the column's under both.
XlsxSheet _listSheet(
  XlsxWorkbook book,
  String name,
  List<List<Object?>> data, {
  XlsxTableStyle? table,
}) {
  const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
  const XlsxStyle general = XlsxStyle(numFmt: XlsxNumFmt.general);
  final XlsxSheet sheet = book.addSheet(name);
  _setColumns(sheet, <XlsxColumn?>[
    const XlsxColumn(width: 10),
    const XlsxColumn(width: 30),
    XlsxColumn(width: 16, style: XlsxStyle(numFmt: XlsxNumFmt.money())),
    const XlsxColumn(
      width: 12,
      style: XlsxStyle(numFmt: XlsxNumFmt.localeShortDate),
    ),
  ]);
  sheet.view = const XlsxSheetView(pane: XlsxPane.frozen(rows: 2));
  void row(int r, List<Object?> values, XlsxStyle? style) {
    for (int c = 0; c < values.length; c++) {
      final Object? value = values[c];
      if (value == null) continue;
      final XlsxStyle? own = value is XlsxCell ? value.style : null;
      sheet.setCell(
        r,
        c,
        XlsxCell(
          value is XlsxCell ? value.value : value,
          style: style?.merge(own) ?? own,
        ),
      );
    }
  }

  final int lastData = data.isEmpty ? 2 : data.length + 1;
  row(0, <Object?>[
    'Accounts',
  ], const XlsxStyle(font: XlsxFont(bold: true, size: 14)));
  final XlsxCell count = XlsxCell(
    XlsxFormula('SUBTOTAL(103,D3:D${lastData + 1})'),
    style: general,
  );
  for (int i = 0; i < data.length; i++) {
    row(i + 2, data[i], null);
  }
  if (table == null) {
    row(1, <Object?>['Code', 'Name', 'Balance', 'Opened'], bold);
    row(lastData + 1, <Object?>[
      'Total',
      null,
      XlsxFormula('SUBTOTAL(109,C3:C${lastData + 1})'),
      count,
    ], bold);
    sheet.autoFilter = XlsxRange(1, 0, lastData, 3);
  } else {
    sheet.addTable(
      XlsxTable(
        'Accounts',
        XlsxRange(1, 0, lastData + 1, 3),
        const <XlsxTableColumn>[
          XlsxTableColumn('Code', totalsLabel: 'Total'),
          XlsxTableColumn('Name'),
          XlsxTableColumn('Balance', totalsFunction: XlsxTotalsFunction.sum),
          XlsxTableColumn('Opened', totalsFunction: XlsxTotalsFunction.count),
        ],
        totalsRow: true,
        style: table,
      ),
    );
    // The table fills in its header and totals cells, the count in the
    // column's date format (the writer's own `table` does the same). The
    // list export chooses General for a count total (`_plainNumber` in
    // list_export.dart), so a model caller sets that style after the table.
    sheet.setCell(lastData + 1, 3, count);
  }
  // After the filter: the writer lists `_FilterDatabase` before the titles.
  sheet.setPrintTitles(rows: (1, 1));
  return sheet;
}

List<List<Object?>> _accountRows() => <List<Object?>>[
  for (final (String, String, num, XlsxDate?, int?) a in m5Accounts)
    <Object?>[a.$1, a.$2, a.$3, a.$4],
];

XlsxResult _listPlainBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _listSheet(book, 'Accounts', _accountRows());
  _listSheet(book, 'Empty', const <List<Object?>>[]);
  return book.save();
}

XlsxResult _listTableBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  _listSheet(book, 'Accounts', _accountRows(), table: XlsxTableStyle.medium(2));
  return book.save();
}

/// Sets [rows] on [sheet] from row 0 and returns it.
XlsxSheet _fill(XlsxSheet sheet, List<List<Object?>> rows) {
  for (int r = 0; r < rows.length; r++) {
    for (int c = 0; c < rows[r].length; c++) {
      sheet.setCell(r, c, rows[r][c]);
    }
  }
  return sheet;
}

/// Builds [sheets] with the model.
XlsxResult _build(_Sheets sheets) {
  final XlsxWorkbook book = XlsxWorkbook();
  for (final (String name, List<List<Object?>> rows) in sheets) {
    _fill(book.addSheet(name), rows);
  }
  return book.save();
}

Map<XlsxWarningCode, int> _totals(
  List<XlsxWarning> warnings,
) => <XlsxWarningCode, int>{
  for (final XlsxWarningCode code in warnings.map((XlsxWarning w) => w.code))
    code: warnings
        .where((XlsxWarning w) => w.code == code)
        .fold(0, (int sum, XlsxWarning w) => sum + w.count),
};

void main() {
  group('fixtures built with the model equal the writer\'s', () {
    for (final Fixture f in <Fixture>[
      ...m1Fixtures(),
      ...m2Fixtures(),
      ...m3Fixtures(),
      ...m4Fixtures(),
      ...m5Fixtures(),
    ]) {
      final _Sheets? sheets = _rebuilt[f.name];
      final XlsxResult Function()? script = _scripted[f.name];
      if (sheets == null && script == null) continue;
      test(f.name, () {
        final Uint8List writer = f.build();
        final XlsxResult model = script == null ? _build(sheets!) : script();
        expect(
          comparePackages(
            _allowed[f.name]?.call(writer) ?? writer,
            model.bytes,
            // The model writes each row's spans; the writer writes none.
            ignoreBookkeeping: true,
          ),
          isEmpty,
        );
        expect(_totals(model.warnings), f.expectedWarnings);
      });
    }
  });

  group('a date Excel cannot show, inside an XlsxCell, is the writer\'s', () {
    const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
    const XlsxStyle money = XlsxStyle(numFmt: XlsxNumFmt.custom('#,##0.00'));
    final Map<String, Object?> dates = <String, Object?>{
      'a DateTime': DateTime(1850, 6, 15, 8, 30),
      'an XlsxDate': const XlsxDate(1850, 6, 15),
    };
    for (final MapEntry<String, Object?> date in dates.entries) {
      for (final (String name, XlsxStyle? cell, XlsxStyle? row, XlsxStyle? col)
          in <(String, XlsxStyle?, XlsxStyle?, XlsxStyle?)>[
            ('without a style', null, null, null),
            ('with a style', bold, null, null),
            ('with a number format', money, null, null),
            ('on a styled row', null, bold, null),
            ('in a styled column', null, null, money),
            ('in all three layers', bold, money, bold),
          ]) {
        test('${date.key} $name', () {
          final XlsxCell value = XlsxCell(date.value, style: cell);
          final XlsxWriter writer = XlsxWriter();
          writer.addSheet('Dates')
            ..columns(<XlsxColumn?>[XlsxColumn(style: col)])
            ..row(<Object?>[value], style: row);
          final XlsxResult written = writer.close();

          final XlsxWorkbook book = XlsxWorkbook();
          final XlsxSheet sheet = book.addSheet('Dates');
          sheet.setColumn(0, XlsxColumn(style: col));
          sheet.setCell(
            0,
            0,
            XlsxCell(date.value, style: row?.merge(cell) ?? cell),
          );
          final XlsxResult model = book.save();

          expect(
            comparePackages(
              written.bytes,
              model.bytes,
              ignoreBookkeeping: true,
            ),
            isEmpty,
          );
          expect(_totals(model.warnings), _totals(written.warnings));
          expect(
            _totals(model.warnings),
            containsPair(XlsxWarningCode.dateOutsideExcelRange, 1),
          );
        });
      }
    }
  });

  test('an Excel 2010 rule on a later sheet has the writer\'s id', () {
    final XlsxConditionalFormat stars = XlsxConditionalFormat(
      <XlsxRange>[XlsxRange.parse('A1:A3')],
      <XlsxConditionalRule>[XlsxIconSet(XlsxIconSetType.threeStars)],
    );
    final XlsxConditionalFormat bar = XlsxConditionalFormat(
      <XlsxRange>[XlsxRange.parse('B1:B3')],
      <XlsxConditionalRule>[XlsxDataBar(color: XlsxColor.hex('638EC6'))],
    );
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('One').conditionalFormat(bar);
    writer.addSheet('Two')
      ..conditionalFormat(stars)
      ..conditionalFormat(bar);
    final XlsxWorkbook book = XlsxWorkbook();
    book.addSheet('One').addConditionalFormat(bar);
    book.addSheet('Two')
      ..addConditionalFormat(stars)
      ..addConditionalFormat(bar);
    expect(
      comparePackages(
        writer.close().bytes,
        book.save().bytes,
        ignoreBookkeeping: true,
      ),
      isEmpty,
    );
  });

  test('every fixture is rebuilt with the model or named with a reason', () {
    final Set<String> names = <String>{
      for (final Fixture f in allFixtures()) f.name,
    };
    final Set<String> rebuilt = <String>{..._rebuilt.keys, ..._scripted.keys};
    expect(names, containsAll(rebuilt));
    expect(names, containsAll(_notRebuilt.keys));
    expect(_scripted.keys, containsAll(_allowed.keys));
    expect(rebuilt.intersection(_notRebuilt.keys.toSet()), isEmpty);
    expect(
      names.difference(rebuilt).difference(_notRebuilt.keys.toSet()),
      isEmpty,
    );
  });
}
