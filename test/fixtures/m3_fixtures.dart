/// The fixtures of milestone M3 (sheet and workbook features).
///
/// New in jet_office. Each M3 task appends its fixtures to [m3Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M3.
List<Fixture> m3Fixtures() => <Fixture>[_names(), _hyperlinks(), _validation()];

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
