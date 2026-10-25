/// The fixtures of milestone M3 (sheet and workbook features).
///
/// New in jet_office. Each M3 task appends its fixtures to [m3Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M3.
List<Fixture> m3Fixtures() => <Fixture>[
  _names(),
  _hyperlinks(),
  _validation(),
  _conditional(),
  _conditionalX14(),
  _pageSetup(),
];

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

/// Hyperlinks of every kind, on `Links`, and the places they go to.
///
/// Row 1 holds a web link whose address has a space (`%20` in the rels
/// part), an e-mail with a subject, a link in the bold column C and a link
/// whose cell font is red. Row 2 holds a link to `'O''Brien'!B2` and one to
/// the workbook name `Target`, which is `'O''Brien'!$C$3`. Excel shows the
/// links blue and underlined, the bold one bold, the red one red and
/// underlined, and follows them on click; a CSV reader sees the display
/// texts, which are the expected values.
Fixture _hyperlinks() => Fixture(
  'm3_hyperlinks',
  <String, List<List<String>>>{
    'Links': <List<String>>[
      <String>[
        'https://example.com/a b',
        'sales@example.com',
        'Bold link',
        'Red link',
      ],
      <String>["O'Brien", 'Target', '', ''],
    ],
    "O'Brien": <List<String>>[
      <String>['top', '', ''],
      <String>['', 'B2', ''],
      <String>['', '', 'C3'],
    ],
  },
  <String, List<List<Object?>>>{
    'Links': <List<Object?>>[
      <Object?>[
        'https://example.com/a b',
        'sales@example.com',
        'Bold link',
        'Red link',
      ],
      <Object?>["O'Brien", 'Target'],
    ],
    "O'Brien": <List<Object?>>[
      <Object?>['top'],
      <Object?>[null, 'B2'],
      <Object?>[null, null, 'C3'],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Links')
      ..columns(<XlsxColumn?>[
        null,
        null,
        const XlsxColumn(style: XlsxStyle(font: XlsxFont(bold: true))),
      ])
      ..row(<Object?>[
        XlsxHyperlink.url('https://example.com/a b'),
        XlsxHyperlink.email(
          'sales@example.com',
          subject: 'Q&A ç',
          tooltip: 'Write to sales',
        ),
        XlsxHyperlink.location('Target', text: 'Bold link'),
        XlsxCell(
          XlsxHyperlink.url('https://example.com/red', text: 'Red link'),
          style: const XlsxStyle(
            font: XlsxFont(color: XlsxColor.rgb(0xFF0000)),
          ),
        ),
      ])
      ..row(<Object?>[
        XlsxHyperlink.sheet("O'Brien", range: XlsxRange.parse('B2')),
        XlsxHyperlink.location('Target'),
      ]);
    book.addSheet("O'Brien")
      ..row(<Object?>['top'])
      ..row(<Object?>[null, 'B2'])
      ..row(<Object?>[null, null, 'C3']);
    book.defineName(const XlsxDefinedName('Target', r"'O''Brien'!$C$3"));
    return book.close();
  },
);

/// Data validation of every kind, on `Form`.
///
/// Row 1 is the header; rows 2 to 10 each hold a label in column A and its
/// validated input cell in column B, which stays empty (a validation only
/// restricts what is typed): a list with a quoted item, a list from the
/// range `D2:D4`, a whole number from 1 to 10 with an input message, a
/// decimal above 0, a date after 24.10.2026, a time before 12:00, a text of
/// at most 5 characters, a custom `ISEVEN(B9)` with a warning-style error,
/// and an `any` validation that only prompts. Excel shows the drop-downs,
/// messages and warning; the values below are what a reader computes.
Fixture _validation() => Fixture(
  'm3_validation',
  <String, List<List<String>>>{
    'Form': <List<String>>[
      <String>['Field', 'Input', '', 'Choices'],
      <String>['Quoted list', '', '', 'red'],
      <String>['List from range', '', '', 'green'],
      <String>['Whole 1 to 10', '', '', 'blue'],
      <String>['Decimal above 0', '', '', ''],
      <String>['Date after 24.10.2026', '', '', ''],
      <String>['Time before 12:00', '', '', ''],
      <String>['Text of at most 5', '', '', ''],
      <String>['Even number', '', '', ''],
      <String>['Prompt only', '', '', ''],
    ],
  },
  <String, List<List<Object?>>>{
    'Form': <List<Object?>>[
      <Object?>['Field', 'Input', null, 'Choices'],
      <Object?>['Quoted list', null, null, 'red'],
      <Object?>['List from range', null, null, 'green'],
      <Object?>['Whole 1 to 10', null, null, 'blue'],
      <Object?>['Decimal above 0'],
      <Object?>['Date after 24.10.2026'],
      <Object?>['Time before 12:00'],
      <Object?>['Text of at most 5'],
      <Object?>['Even number'],
      <Object?>['Prompt only'],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    XlsxRange input(int row) => XlsxRange(row, 1);
    book.addSheet('Form')
      ..row(<Object?>['Field', 'Input', null, 'Choices'])
      ..row(<Object?>['Quoted list', null, null, 'red'])
      ..row(<Object?>['List from range', null, null, 'green'])
      ..row(<Object?>['Whole 1 to 10', null, null, 'blue'])
      ..row(<Object?>['Decimal above 0'])
      ..row(<Object?>['Date after 24.10.2026'])
      ..row(<Object?>['Time before 12:00'])
      ..row(<Object?>['Text of at most 5'])
      ..row(<Object?>['Even number'])
      ..row(<Object?>['Prompt only'])
      ..dataValidation(
        XlsxDataValidation.list(
          <XlsxRange>[input(1)],
          <String>['Fish', 'say "hi"', 'R&D'],
        ),
      )
      ..dataValidation(
        XlsxDataValidation.listFrom(<XlsxRange>[input(2)], r'$D$2:$D$4'),
      )
      ..dataValidation(
        XlsxDataValidation.whole(
          <XlsxRange>[input(3)],
          XlsxComparison.between,
          1,
          b: 10,
          promptTitle: 'Count',
          prompt: 'Enter a whole number from 1 to 10.',
          errorTitle: 'Not allowed',
          error: 'Use 1 to 10.',
        ),
      )
      ..dataValidation(
        XlsxDataValidation.decimal(
          <XlsxRange>[input(4)],
          XlsxComparison.greaterThan,
          0,
        ),
      )
      ..dataValidation(
        XlsxDataValidation.date(
          <XlsxRange>[input(5)],
          XlsxComparison.greaterThan,
          const XlsxDate(2026, 10, 24),
        ),
      )
      ..dataValidation(
        XlsxDataValidation.time(
          <XlsxRange>[input(6)],
          XlsxComparison.lessThan,
          const Duration(hours: 12),
        ),
      )
      ..dataValidation(
        XlsxDataValidation.textLength(
          <XlsxRange>[input(7)],
          XlsxComparison.lessThanOrEqual,
          5,
        ),
      )
      ..dataValidation(
        XlsxDataValidation.custom(
          <XlsxRange>[input(8)],
          'ISEVEN(B9)',
          errorStyle: XlsxValidationErrorStyle.warning,
          errorTitle: 'Odd',
          error: 'The number is not even.',
        ),
      )
      ..dataValidation(
        XlsxDataValidation.any(
          <XlsxRange>[input(9)],
          promptTitle: 'Note',
          prompt: 'Anything goes here.',
        ),
      );
    return book.close();
  },
);

/// The names of the `Scores` rows; `Ana`, `Dana` and `Hanna` contain `an`.
const List<String> _scoreNames = <String>[
  'Ana',
  'Ben',
  'Cem',
  'Dana',
  'Eda',
  'Fred',
  'Gul',
  'Hanna',
  'Ivo',
  'Jale',
  'Kim',
  'Lea',
  'Mert',
  'Nil',
  'Oskar',
  'Pia',
  'Rana',
  'Sven',
  'Tom',
  'Ugur',
];

/// The teams of the `Scores` rows, which repeat; the last row's team,
/// `Gold`, occurs once.
const List<String> _scoreTeams = <String>['Red', 'Blue', 'Green'];

/// Row `i` (0 to 19) of `Scores`: a name, five scores, a team, hours,
/// progress and a rating.
List<Object> _scoreRow(int i) {
  final int n = i + 1;
  return <Object>[
    _scoreNames[i],
    n * 37 % 100,
    (n * 53 + 11) % 100,
    (n * 29 + 7) % 100,
    (n * 61 + 3) % 100,
    if (i == 19) 'Gold' else _scoreTeams[i % 3],
    n * 2,
    n * 17 % 101,
    n * 7 % 5 + 1,
  ];
}

/// Conditional formatting of every kind, on `Scores`.
///
/// Row 1 is the header; rows 2 to 21 hold a name and numbers. Each column
/// has a format of its own kind: A names containing `an` (red), B maths
/// of 70 or more (green), C art above the column average by formula
/// (green), D the top 3 music scores (red), E sport below the average or
/// equal to it (green), F duplicate teams (red, all but `Gold`), G a
/// three-color scale on the hours, H a data bar on the progress and I three
/// arrows on the rating. A second format on `B2:C21`, which overlaps the
/// first, makes scores below 40 bold. Excel shows the colors, bars and
/// icons; the values below are what a reader computes, as conditional
/// formatting changes no value.
Fixture _conditional() {
  final List<List<Object>> rows = <List<Object>>[
    for (int i = 0; i < 20; i++) _scoreRow(i),
  ];
  const List<String> header = <String>[
    'Name',
    'Maths',
    'Art',
    'Music',
    'Sport',
    'Team',
    'Hours',
    'Progress',
    'Rating',
  ];
  return Fixture(
    'm3_conditional',
    <String, List<List<String>>>{
      'Scores': <List<String>>[
        header,
        for (final List<Object> row in rows)
          <String>[for (final Object v in row) '$v'],
      ],
    },
    <String, List<List<Object?>>>{
      'Scores': <List<Object?>>[header, ...rows],
    },
    () {
      final XlsxWriter book = XlsxWriter();
      final XlsxStyle red = XlsxStyle(
        font: XlsxFont(color: XlsxColor.hex('9C0006')),
        fill: XlsxFill.solid(XlsxColor.hex('FFC7CE')),
      );
      final XlsxStyle green = XlsxStyle(
        font: XlsxFont(color: XlsxColor.hex('006100')),
        fill: XlsxFill.solid(XlsxColor.hex('C6EFCE')),
      );
      const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
      XlsxRange column(int c) => XlsxRange(1, c, 20, c);
      final XlsxSheetWriter sheet = book.addSheet('Scores')..row(header);
      rows.forEach(sheet.row);
      void format(XlsxRange range, XlsxConditionalRule rule) =>
          sheet.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[range],
              <XlsxConditionalRule>[rule],
            ),
          );
      format(
        column(0),
        XlsxTextRule(XlsxTextOperator.contains, 'an', style: red),
      );
      format(
        column(1),
        XlsxCellValueRule(
          XlsxComparison.greaterThanOrEqual,
          '70',
          style: green,
        ),
      );
      format(
        column(2),
        XlsxExpressionRule(r'C2>AVERAGE($C$2:$C$21)', style: green),
      );
      format(column(3), XlsxTopBottomRule(rank: 3, style: red));
      format(
        column(4),
        XlsxAverageRule(above: false, orEqual: true, style: green),
      );
      format(column(5), XlsxDuplicateRule(style: red));
      format(
        column(6),
        XlsxColorScale(
          <XlsxCfValue>[
            const XlsxCfValue.min(),
            XlsxCfValue.percentile(50),
            const XlsxCfValue.max(),
          ],
          <XlsxColor>[
            XlsxColor.hex('F8696B'),
            XlsxColor.hex('FFEB84'),
            XlsxColor.hex('63BE7B'),
          ],
        ),
      );
      format(column(7), XlsxDataBar(color: XlsxColor.hex('638EC6')));
      format(column(8), XlsxIconSet(XlsxIconSetType.threeArrows));
      format(
        XlsxRange.parse('B2:C21'),
        const XlsxCellValueRule(XlsxComparison.lessThan, '40', style: bold),
      );
      return book.close();
    },
  );
}

/// The Excel 2010 data bars and icon sets, on `Bars`.
///
/// Row 1 is the header; rows 2 to 22 hold the values -50 to 50 in steps of
/// 5, the same in every column. A has a blue data bar with a red negative
/// fill and the axis in the middle of the cell; B a solid green bar with a
/// border; C three stars, D three triangles and E five boxes, icon sets
/// that only Excel 2010 and later show. Excel draws the bars and icons;
/// the values below are what a reader computes, as conditional formatting
/// changes no value.
Fixture _conditionalX14() {
  final List<List<int>> rows = <List<int>>[
    for (int v = -50; v <= 50; v += 5) <int>[v, v, v, v, v],
  ];
  const List<String> header = <String>[
    'Bar',
    'Solid',
    'Stars',
    'Triangles',
    'Boxes',
  ];
  return Fixture(
    'm3_conditional_x14',
    <String, List<List<String>>>{
      'Bars': <List<String>>[
        header,
        for (final List<int> row in rows)
          <String>[for (final int v in row) '$v'],
      ],
    },
    <String, List<List<Object?>>>{
      'Bars': <List<Object?>>[header, ...rows],
    },
    () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('Bars')..row(header);
      rows.forEach(sheet.row);
      void format(int column, XlsxConditionalRule rule) =>
          sheet.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[XlsxRange(1, column, rows.length, column)],
              <XlsxConditionalRule>[rule],
            ),
          );
      format(
        0,
        XlsxDataBar(
          color: XlsxColor.hex('638EC6'),
          negativeFillColor: XlsxColor.hex('FF0000'),
          axis: XlsxDataBarAxis.middle,
        ),
      );
      format(
        1,
        XlsxDataBar(
          color: XlsxColor.hex('63C384'),
          gradient: false,
          border: true,
        ),
      );
      format(2, XlsxIconSet(XlsxIconSetType.threeStars));
      format(3, XlsxIconSet(XlsxIconSetType.threeTriangles));
      format(4, XlsxIconSet(XlsxIconSetType.fiveBoxes));
      return book.close();
    },
  );
}

/// Page setup on two sheets.
///
/// `Landscape` prints on A4 landscape, fitted one page wide, centered, with
/// gridlines; `Scaled` prints at 85 %, with narrow margins, from page 3,
/// over then down. Page setup changes no value, so the values below are what
/// a reader computes; Excel's Page Setup dialog and Print Preview show the
/// settings.
Fixture _pageSetup() {
  const List<List<int>> rows = <List<int>>[
    <int>[1, 2, 3],
    <int>[4, 5, 6],
  ];
  return Fixture(
    'm3_page_setup',
    <String, List<List<String>>>{
      'Landscape': <List<String>>[
        <String>['a', 'b', 'c'],
        <String>['1', '2', '3'],
        <String>['4', '5', '6'],
      ],
      'Scaled': <List<String>>[
        <String>['1', '2', '3'],
        <String>['4', '5', '6'],
      ],
    },
    <String, List<List<Object?>>>{
      'Landscape': <List<Object?>>[
        <Object?>['a', 'b', 'c'],
        ...rows,
      ],
      'Scaled': <List<Object?>>[...rows],
    },
    () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter landscape = book.addSheet('Landscape')
        ..row(<Object?>['a', 'b', 'c']);
      rows.forEach(landscape.row);
      landscape.pageSetup(
        const XlsxPageSetup(
          orientation: XlsxOrientation.landscape,
          paperSize: XlsxPaperSize.a4,
          fitToWidth: 1,
          centerHorizontally: true,
          printGridLines: true,
        ),
      );
      final XlsxSheetWriter scaled = book.addSheet('Scaled');
      rows.forEach(scaled.row);
      scaled.pageSetup(
        const XlsxPageSetup(
          scale: 85,
          firstPageNumber: 3,
          pageOrder: XlsxPageOrder.overThenDown,
          margins: XlsxPageMargins(
            left: 0.25,
            right: 0.25,
            top: 0.5,
            bottom: 0.5,
            header: 0.2,
            footer: 0.2,
          ),
        ),
      );
      return book.close();
    },
  );
}
