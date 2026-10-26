/// The fixtures of milestone M4 (rich text, notes, pictures and tables).
///
/// New in jet_office. Each M4 task appends its fixtures to [m4Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M4.
List<Fixture> m4Fixtures() => <Fixture>[_richText()];

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
