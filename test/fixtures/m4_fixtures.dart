/// The fixtures of milestone M4 (rich text, notes, pictures and tables).
///
/// New in jet_office. Each M4 task appends its fixtures to [m4Fixtures]; they
/// follow the conventions documented in `m1_fixtures.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import 'fixture.dart';

/// The fixtures of milestone M4.
List<Fixture> m4Fixtures() => <Fixture>[
  _richText(),
  _notes(),
  _images(),
  _tables(),
  _objects(),
];

/// A real 4 × 2 PNG, 87 bytes: 8-bit RGB, each pixel's red rising from 0
/// to 255 across, green from 0 to 255 down, blue 128.
///
/// Made with Python's standard library (Python 3.9.6) by
/// `python3 png.py 4 2 > png4x2.png`, `png.py` being:
///
/// ```python
/// import struct, sys, zlib
/// w, h = int(sys.argv[1]), int(sys.argv[2])
/// def chunk(kind, data):
///     body = kind + data
///     crc = struct.pack('>I', zlib.crc32(body))
///     return struct.pack('>I', len(data)) + body + crc
/// rows = b''.join(
///     b'\0' + b''.join(
///         bytes((255 * x // (w - 1), 255 * y // (h - 1), 128))
///         for x in range(w))
///     for y in range(h))
/// ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
/// sys.stdout.buffer.write(
///     b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
///     + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))
/// ```
///
/// Checked with a decoder: `sips -g pixelWidth -g pixelHeight png4x2.png`
/// (macOS 27.0.1, sips-316) reads 4 × 2, `sips -s format bmp` decodes it,
/// and the CRCs of its three chunks recompute with `zlib.crc32`.
final Uint8List png4x2 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAHklEQVR42gXBAQEAAAiDMEra'
  'hzwviRvg4TCEvFyWD3fSC/l5cHwkAAAAAElFTkSuQmCC',
);

/// A real 3 × 5 baseline JPEG, 852 bytes: its frame header is SOF0, after
/// the JFIF, Exif and Photoshop segments `sips` writes.
///
/// Made from `python3 png.py 3 5 > png3x5.png` (see [png4x2]) with
/// `sips -s format jpeg png3x5.png --out jpeg3x5.jpeg` (macOS 27.0.1,
/// sips-316). Checked with decoders: `sips -g pixelWidth -g pixelHeight`
/// reads 3 × 5 and `djpeg` (libjpeg-turbo 3.2.0) decodes it to a 3 × 5
/// image.
final Uint8List jpeg3x5 = base64Decode(
  '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAA'
  'AAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAA6ADAAQAAAABAAAABQAAAAD/7QA4UGhvdG9z'
  'aG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgA'
  'BQADAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIB'
  'AwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYX'
  'GBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeI'
  'iYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn'
  '6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIB'
  'AgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDTh'
  'JfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWG'
  'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm'
  '5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgK'
  'CgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQ'
  'EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwD'
  'AQACEQMRAD8A+zvhn+xl8LD4D0X5P+Xcf8s19T713X/DGPws/uf+Q1/xr6C+Gf8AyIWif9e4'
  '/ma7qv5IzbxGzz61V/2ufxS6+bPvPD3xZ4k/sDL/APbp/wAGl1/uRP/Z',
);

/// Rich text cells, one per row of the sheet `Rich`.
///
/// A1 is a bold run and a plain run. A2 is an italic red run and an
/// underlined one. A3 is `x²`, written as `x` and a superscript `2`. A4 is a
/// bold run and a plain run in a cell styled Arial 14, so the bold run is
/// Arial 14 bold (Decision 3) and the plain run carries Arial 14 too, which
/// Excel would otherwise draw in its default Calibri 11. A5 is a rich text of one run without a font,
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

/// Notes on three sheets.
///
/// `Notes` has a plain note by `Ahmet` on B2, a rich note on C3 (a bold
/// `Ahmet:` line, then the text) and a visible note by `Ayse Yilmaz` on D4,
/// each cell holding a value. `Right` has a note on `XFD1` and `Bottom` one
/// on `A1048576`, whose boxes Excel must open inside the sheet. On both,
/// only A1 and B1 hold values, so the stored values stay small, and the
/// note is added after the row, as a trailer setting.
///
/// The two edge notes are on separate sheets (Ruling R8 of the M4 plan):
/// LibreOffice's CSV export counts notes in a sheet's area and pads every
/// row to it, so notes on XFD1 and A1048576 on one sheet would export
/// 1,048,576 rows of 16,384 fields, about 17 GB. Apart, `Right` exports one
/// row of 16,384 fields and `Bottom` 1,048,576 rows of two. A reader shows
/// the cell values; the notes are pinned in `fixtures_test.dart`.
Fixture _notes() => Fixture(
  'm4_notes',
  <String, List<List<String>>>{
    'Notes': <List<String>>[
      <String>['', '', '', ''],
      <String>['', 'Plain', '', ''],
      <String>['', '', 'Rich', ''],
      <String>['', '', '', 'Visible'],
    ],
    'Right': <List<String>>[
      <String>['Note on XFD1', 'The last column'],
    ],
    'Bottom': <List<String>>[
      <String>['Note on A1048576', 'The last row'],
    ],
  },
  <String, List<List<Object?>>>{
    'Notes': <List<Object?>>[
      <Object?>[],
      <Object?>[null, 'Plain'],
      <Object?>[null, null, 'Rich'],
      <Object?>[null, null, null, 'Visible'],
    ],
    'Right': <List<Object?>>[
      <Object?>['Note on XFD1', 'The last column'],
    ],
    'Bottom': <List<Object?>>[
      <Object?>['Note on A1048576', 'The last row'],
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
    book.addSheet('Right')
      ..row(<Object?>['Note on XFD1', 'The last column'])
      ..note(0, 16383, XlsxNote.plain('The last column', author: 'Ahmet'));
    book.addSheet('Bottom')
      ..row(<Object?>['Note on A1048576', 'The last row'])
      ..note(1048575, 0, XlsxNote.plain('The last row', author: 'Ahmet'));
    return book.close();
  },
);

/// Pictures on two sheets, all showing [png4x2] and [jpeg3x5].
///
/// `Pictures` has the PNG at B2 in its own size (4 × 2 pixels), the JPEG at
/// E2 60 pixels wide (100 high, its aspect kept) and the PNG stretched over
/// B6:D10, moving with its cells but keeping its size
/// ([XlsxPictureResize.move]), described for Alt Text. `Again` has the same
/// PNG `Uint8List` at A1, so the file holds one PNG and one JPEG part, both
/// drawings pointing at the PNG. Labels in column A give a reader something
/// to show; the pictures are pinned in `fixtures_test.dart`.
Fixture _images() => Fixture(
  'm4_images',
  <String, List<List<String>>>{
    'Pictures': <List<String>>[
      <String>[''],
      <String>['PNG at B2, JPEG at E2'],
      <String>[''],
      <String>[''],
      <String>[''],
      <String>['PNG over B6:D10'],
    ],
    'Again': <List<String>>[
      <String>[''],
      <String>['The same PNG at A1'],
    ],
  },
  <String, List<List<Object?>>>{
    'Pictures': <List<Object?>>[
      <Object?>[],
      <Object?>['PNG at B2, JPEG at E2'],
      <Object?>[],
      <Object?>[],
      <Object?>[],
      <Object?>['PNG over B6:D10'],
    ],
    'Again': <List<Object?>>[
      <Object?>[],
      <Object?>['The same PNG at A1'],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Pictures')
      ..blankRow()
      ..row(<Object?>['PNG at B2, JPEG at E2'])
      ..blankRow()
      ..blankRow()
      ..blankRow()
      ..row(<Object?>['PNG over B6:D10'])
      ..picture(
        XlsxPicture(
          XlsxImage(png4x2),
          const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1)),
        ),
      )
      ..picture(
        XlsxPicture(
          XlsxImage(jpeg3x5),
          const XlsxOneCellAnchor(XlsxAnchorPoint(1, 4), width: 60),
        ),
      )
      ..picture(
        XlsxPicture(
          XlsxImage(png4x2),
          XlsxTwoCellAnchor.range(
            XlsxRange.parse('B6:D10'),
            resize: XlsxPictureResize.move,
          ),
          description: 'The PNG over B6:D10',
        ),
      );
    book.addSheet('Again')
      ..blankRow()
      ..row(<Object?>['The same PNG at A1'])
      ..picture(
        XlsxPicture(
          XlsxImage(png4x2),
          const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
        ),
      );
    return book.close();
  },
);

/// Tables on two sheets.
///
/// `Sales` has the table `Sales` over A1:C5: a header row, three data rows
/// and a totals row. The caller writes the header cells of A and B and
/// leaves C to the writer, which fills in `Note`; the sheet ends before row
/// 5, so the writer writes the totals row: `Total` under `Region`,
/// `SUBTOTAL(109,B2:B4)` under `Amount` (Decision 2) and nothing under
/// `Note`. Beside it, the table `Costs` over E1:F3 has the style
/// `TableStyleLight9` with column stripes, and its header, on the same row,
/// is filled in entirely. `Plain` has the table `Numbers` over A1:B2,
/// without a header row and without a style. A reader shows the cells; the
/// tables are pinned in `fixtures_test.dart`.
Fixture _tables() => Fixture(
  'm4_tables',
  <String, List<List<String>>>{
    'Sales': <List<String>>[
      <String>['Region', 'Amount', 'Note', '', 'Item', 'Cost'],
      <String>['North', '120', 'Checked', '', 'Paper', '15'],
      <String>['South', '80', '', '', 'Ink', '30.5'],
      <String>['East', '45.5', '', '', '', ''],
      <String>['Total', '', '', '', '', ''],
    ],
    'Plain': <List<String>>[
      <String>['1', '2'],
      <String>['3', '4'],
    ],
  },
  <String, List<List<Object?>>>{
    'Sales': <List<Object?>>[
      <Object?>['Region', 'Amount', 'Note', null, 'Item', 'Cost'],
      <Object?>['North', 120, 'Checked', null, 'Paper', 15],
      <Object?>['South', 80, null, null, 'Ink', 30.5],
      <Object?>['East', 45.5],
      <Object?>['Total', 245.5, null],
    ],
    'Plain': <List<Object?>>[
      <Object?>[1, 2],
      <Object?>[3, 4],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Sales')
      ..table(
        XlsxTable('Sales', XlsxRange.parse('A1:C5'), const <XlsxTableColumn>[
          XlsxTableColumn('Region', totalsLabel: 'Total'),
          XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
          XlsxTableColumn('Note'),
        ], totalsRow: true),
      )
      ..table(
        XlsxTable('Costs', XlsxRange.parse('E1:F3'), const <XlsxTableColumn>[
          XlsxTableColumn('Item'),
          XlsxTableColumn('Cost'),
        ], style: XlsxTableStyle.light(9, showColumnStripes: true)),
      )
      ..row(<Object?>['Region', 'Amount'])
      ..row(<Object?>['North', 120, 'Checked', null, 'Paper', 15])
      ..row(<Object?>['South', 80, null, null, 'Ink', 30.5])
      ..row(<Object?>['East', 45.5]);
    book.addSheet('Plain')
      ..table(
        XlsxTable(
          'Numbers',
          XlsxRange.parse('A1:B2'),
          const <XlsxTableColumn>[XlsxTableColumn('X'), XlsxTableColumn('Y')],
          headerRow: false,
          style: null,
        ),
      )
      ..row(<Object?>[1, 2])
      ..row(<Object?>[3, 4]);
    return book.close();
  },
);

/// One sheet with every kind of object (Review Focus 5 of the M4 plan),
/// and a second sheet with a note.
///
/// `All` has links to two addresses in A1 and B1, a note on C1, the PNG
/// of [png4x2] at G2, and the tables `Stock` over A3:B5 and `Prices` over
/// D3:E5, whose header row the writer fills in from a row of `null`s. Its
/// relationships are `rId1` and `rId2` for the links, `rId3` for the
/// drawing, `rId4` for the VML drawing, `rId5` for the comments and `rId6`
/// and `rId7` for the tables. `More` has one note on A1, whose VML drawing
/// takes the next id block. The ids are pinned in `fixtures_test.dart`.
Fixture _objects() => Fixture(
  'm4_objects',
  <String, List<List<String>>>{
    'All': <List<String>>[
      <String>['Site A', 'Site B', 'Noted', '', ''],
      <String>['', '', '', '', ''],
      <String>['Item', 'Qty', '', 'Code', 'Price'],
      <String>['Bolt', '10', '', 'B-1', '0.25'],
      <String>['Nut', '25', '', 'N-1', '0.1'],
    ],
    'More': <List<String>>[
      <String>['One note'],
    ],
  },
  <String, List<List<Object?>>>{
    'All': <List<Object?>>[
      <Object?>['Site A', 'Site B', 'Noted'],
      <Object?>[],
      <Object?>['Item', 'Qty', null, 'Code', 'Price'],
      <Object?>['Bolt', 10, null, 'B-1', 0.25],
      <Object?>['Nut', 25, null, 'N-1', 0.1],
    ],
    'More': <List<Object?>>[
      <Object?>['One note'],
    ],
  },
  () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('All')
      ..table(
        XlsxTable('Stock', XlsxRange.parse('A3:B5'), const <XlsxTableColumn>[
          XlsxTableColumn('Item'),
          XlsxTableColumn('Qty'),
        ]),
      )
      ..table(
        XlsxTable('Prices', XlsxRange.parse('D3:E5'), const <XlsxTableColumn>[
          XlsxTableColumn('Code'),
          XlsxTableColumn('Price'),
        ]),
      )
      ..row(<Object?>[
        XlsxHyperlink.url('https://example.com/a', text: 'Site A'),
        XlsxHyperlink.url('https://example.com/b', text: 'Site B'),
        'Noted',
      ])
      ..note(0, 2, XlsxNote.plain('Check C1', author: 'Ahmet'))
      ..blankRow()
      ..row(<Object?>[null, null, null, null, null])
      ..row(<Object?>['Bolt', 10, null, 'B-1', 0.25])
      ..row(<Object?>['Nut', 25, null, 'N-1', 0.1])
      ..picture(
        XlsxPicture(
          XlsxImage(png4x2),
          const XlsxOneCellAnchor(XlsxAnchorPoint(1, 6)),
        ),
      );
    book.addSheet('More')
      ..row(<Object?>['One note'])
      ..note(0, 0, XlsxNote.plain('The second sheet', author: 'Ahmet'));
    return book.close();
  },
);
