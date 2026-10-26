/// The fixtures of milestone M4 (rich text, notes, pictures and tables).
///
/// New in jet_office. Each M4 task appends its fixtures to [m4Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M4.
List<Fixture> m4Fixtures() => <Fixture>[_richText(), _notes()];

/// Rich text cells, one per row of the sheet `Rich`.
///
/// A1 is a bold run and a plain run. A2 is an italic red run and an
/// underlined one. A3 is `x²`, written as `x` and a superscript `2`. A4 is a
/// bold run and a plain run in a cell styled Arial 14, so the bold run is
/// Arial 14 bold (Decision 3). A5 is a rich text of one run without a font,
/// which shares the shared string of A6's plain text. A file stores, and a
/// reader shows, each cell's runs joined.
Fixture _richText() => Fixture(
  'm4_rich_text',
  <String, List<List<String>>>{
    'Rich': <List<String>>[
      <String>['Total: 42'],
      <String>['Red italic and underlined'],
      <String>['x2'],
      <String>['Bold in Arial 14'],
      <String>['Same text'],
      <String>['Same text'],
    ],
  },
  <String, List<List<Object?>>>{
    'Rich': <List<Object?>>[
      <Object?>['Total: 42'],
      <Object?>['Red italic and underlined'],
      <Object?>['x2'],
      <Object?>['Bold in Arial 14'],
      <Object?>['Same text'],
      <Object?>['Same text'],
    ],
  },
  () {
    const XlsxFont bold = XlsxFont(bold: true);
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Rich')
      ..row(<Object?>[
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('Total: ', font: bold),
          XlsxTextRun('42'),
        ]),
      ])
      ..row(<Object?>[
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
      ])
      ..row(<Object?>[
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('x'),
          XlsxTextRun('2', font: XlsxFont(script: XlsxFontScript.superscript)),
        ]),
      ])
      ..row(<Object?>[
        XlsxCell(
          XlsxRichText(const <XlsxTextRun>[
            XlsxTextRun('Bold', font: bold),
            XlsxTextRun(' in Arial 14'),
          ]),
          style: const XlsxStyle(font: XlsxFont(name: 'Arial', size: 14)),
        ),
      ])
      ..row(<Object?>[
        XlsxRichText(const <XlsxTextRun>[XlsxTextRun('Same text')]),
      ])
      ..row(<Object?>['Same text']);
    return book.close();
  },
);

/// Notes on two sheets.
///
/// `Notes` has a plain note by `Ahmet` on B2, a rich note on C3 (a bold
/// `Ahmet:` line, then the text) and a visible note by `Ayse Yilmaz` on D4,
/// each cell holding a value. `Edges` has notes on `XFD1` and `A1048576`,
/// whose boxes Excel must open inside the sheet; only A1 and B1 hold
/// values, so the stored values stay small, and the notes are added after
/// the rows, as trailer settings. A reader shows the cell values; the notes
/// are pinned in `fixtures_test.dart`.
Fixture _notes() => Fixture(
  'm4_notes',
  <String, List<List<String>>>{
    'Notes': <List<String>>[
      <String>['', '', '', ''],
      <String>['', 'Plain', '', ''],
      <String>['', '', 'Rich', ''],
      <String>['', '', '', 'Visible'],
    ],
    'Edges': <List<String>>[
      <String>['Note on XFD1', 'Note on A1048576'],
    ],
  },
  <String, List<List<Object?>>>{
    'Notes': <List<Object?>>[
      <Object?>[],
      <Object?>[null, 'Plain'],
      <Object?>[null, null, 'Rich'],
      <Object?>[null, null, null, 'Visible'],
    ],
    'Edges': <List<Object?>>[
      <Object?>['Note on XFD1', 'Note on A1048576'],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Notes')
      ..blankRow()
      ..row(<Object?>[null, 'Plain'])
      ..note(1, 1, XlsxNote.plain('Check this', author: 'Ahmet'))
      ..row(<Object?>[null, null, 'Rich'])
      ..note(
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
      ..row(<Object?>[null, null, null, 'Visible'])
      ..note(
        3,
        3,
        XlsxNote.plain('Always shown', author: 'Ayse Yilmaz', visible: true),
      );
    book.addSheet('Edges')
      ..row(<Object?>['Note on XFD1', 'Note on A1048576'])
      ..note(0, 16383, XlsxNote.plain('The last column', author: 'Ahmet'))
      ..note(1048575, 0, XlsxNote.plain('The last row', author: 'Ahmet'));
    return book.close();
  },
);
