import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xlsx/note.dart';
import 'package:jet_office/src/xlsx/sheet_writer.dart';
import 'package:jet_office/src/xlsx/workbook_context.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const String _comments1 = 'xl/comments1.xml';
const String _vml1 = 'xl/drawings/vmlDrawing1.vml';

/// The parts of a workbook whose one sheet, `S`, [script] fills; the file
/// must pass the checker.
Map<String, String> _parts(void Function(XlsxSheetWriter sheet) script) {
  final XlsxWriter book = XlsxWriter();
  script(book.addSheet('S'));
  final XlsxResult result = book.close();
  expect(checkXlsx(result.bytes), isEmpty);
  return readXlsx(result.bytes);
}

/// A comments part holding [authors] and [comments].
String _commentsPart(String authors, String comments) =>
    '$_decl<comments xmlns="${Ns.main}"><authors>$authors</authors>'
    '<commentList>$comments</commentList></comments>';

/// A VML drawing with the id [blocks] and the [shapes], in Excel's markup.
String _vmlPart(String blocks, String shapes) =>
    '$_decl<xml xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:x="urn:schemas-microsoft-com:office:excel">'
    '<o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="$blocks"/>'
    '</o:shapelayout>'
    '<v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" '
    'path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/>'
    '<v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>'
    '$shapes</xml>';

/// The note shape [id] at z-index [z] on the zero-based cell ([row],
/// [column]) with [anchor].
String _shape(
  int id,
  int z,
  String anchor,
  int row,
  int column, {
  bool visible = false,
}) =>
    '<v:shape id="_x0000_s$id" type="#_x0000_t202" '
    'style="position:absolute;margin-left:59.25pt;margin-top:1.5pt;'
    'width:108pt;height:59.25pt;z-index:$z;'
    'visibility:${visible ? 'visible' : 'hidden'}" '
    'fillcolor="#ffffe1" o:insetmode="auto"><v:fill color2="#ffffe1"/>'
    '<v:shadow on="t" color="black" obscured="t"/>'
    '<v:path o:connecttype="none"/>'
    '<v:textbox style="mso-direction-alt:auto">'
    '<div style="text-align:left"></div></v:textbox>'
    '<x:ClientData ObjectType="Note"><x:MoveWithCells/><x:SizeWithCells/>'
    '<x:Anchor>$anchor</x:Anchor><x:AutoFill>False</x:AutoFill>'
    '<x:Row>$row</x:Row><x:Column>$column</x:Column>'
    '${visible ? '<x:Visible/>' : ''}</x:ClientData></v:shape>';

void main() {
  group('noteAnchor', () {
    test('puts the box right of the cell and from the row above', () {
      expect(noteAnchor(1, 1), '2, 15, 0, 10, 4, 15, 4, 4');
      expect(noteAnchor(9, 4), '5, 15, 8, 10, 7, 15, 12, 4');
    });
    test('starts the box at the top in the first row', () {
      expect(noteAnchor(0, 0), '1, 15, 0, 2, 3, 15, 4, 16');
    });
    test('puts the box left of the cell near the last column', () {
      expect(noteAnchor(0, 16383), '16380, 15, 0, 2, 16382, 15, 4, 16');
      expect(noteAnchor(5, 16381), '16378, 15, 4, 10, 16380, 15, 8, 4');
      expect(noteAnchor(5, 16380), '16381, 15, 4, 10, 16383, 15, 8, 4');
    });
    test('moves the box up near the last row', () {
      expect(noteAnchor(1048575, 0), '1, 15, 1048571, 10, 3, 15, 1048575, 4');
      expect(noteAnchor(1048572, 2), '3, 15, 1048571, 10, 5, 15, 1048575, 4');
      expect(noteAnchor(1048571, 2), '3, 15, 1048570, 10, 5, 15, 1048574, 4');
    });
  });

  group('vmlBlockCount', () {
    // Shape ids run from 1024 × b + 1 to 1024 × b + n, so the last one
    // lies in block b + n ~/ 1024.
    test('covers the blocks the shape ids reach', () {
      expect(vmlBlockCount(1), 1);
      expect(vmlBlockCount(1023), 1);
      expect(vmlBlockCount(1024), 2);
      expect(vmlBlockCount(1025), 2);
      expect(vmlBlockCount(2047), 2);
      expect(vmlBlockCount(2048), 3);
      expect(vmlBlockCount(2049), 3);
    });
  });

  group('WorkbookContext.takeVmlBlocks', () {
    test('hands out consecutive blocks from 1', () {
      final WorkbookContext context = WorkbookContext(ZipWriter());
      expect(context.takeVmlBlocks(2), 1);
      expect(context.takeVmlBlocks(1), 3);
      expect(context.takeVmlBlocks(3), 4);
      expect(context.takeVmlBlocks(1), 7);
    });
    test('refuses a count below 1', () {
      final WorkbookContext context = WorkbookContext(ZipWriter());
      expect(() => context.takeVmlBlocks(0), throwsArgumentError);
      expect(context.takeVmlBlocks(1), 1);
    });
  });

  group('XlsxNote', () {
    test('takes the text, the author and the visibility', () {
      final XlsxRichText text = XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('Hi', font: XlsxFont(bold: true)),
      ]);
      final XlsxNote note = XlsxNote(text, author: 'Ahmet', visible: true);
      expect(note.text, text);
      expect(note.author, 'Ahmet');
      expect(note.visible, isTrue);
    });

    test('has no author and is hidden by default', () {
      final XlsxNote note = XlsxNote(
        XlsxRichText(const <XlsxTextRun>[XlsxTextRun('Hi')]),
      );
      expect(note.author, '');
      expect(note.visible, isFalse);
    });

    test('plain is one run without a font', () {
      final XlsxNote note = XlsxNote.plain(
        'Check this',
        author: 'Ahmet',
        visible: true,
      );
      expect(
        note.text,
        XlsxRichText(const <XlsxTextRun>[XlsxTextRun('Check this')]),
      );
      expect(note.author, 'Ahmet');
      expect(note.visible, isTrue);
      expect(XlsxNote.plain('x').author, '');
      expect(XlsxNote.plain('x').visible, isFalse);
    });

    test('== compares the text, the author and the visibility', () {
      expect(XlsxNote.plain('a'), XlsxNote.plain('a'));
      expect(XlsxNote.plain('a').hashCode, XlsxNote.plain('a').hashCode);
      expect(XlsxNote.plain('a'), isNot(XlsxNote.plain('b')));
      expect(XlsxNote.plain('a'), isNot(XlsxNote.plain('a', author: 'X')));
      expect(XlsxNote.plain('a'), isNot(XlsxNote.plain('a', visible: true)));
    });

    test('toString names every field', () {
      expect(
        XlsxNote.plain('a', author: 'X', visible: true).toString(),
        'XlsxNote(XlsxRichText([XlsxTextRun(a, font: null)]), author: X, '
        'visible: true)',
      );
    });
  });

  group('the comments part', () {
    test('holds a plain note as one t', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) =>
            s.note(1, 1, XlsxNote.plain('Check this', author: 'Ahmet')),
      );
      expect(
        parts[_comments1],
        _commentsPart(
          '<author>Ahmet</author>',
          '<comment ref="B2" authorId="0"><text><t>Check this</t></text>'
              '</comment>',
        ),
      );
    });

    test('holds a rich note as runs, their fonts as given', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.note(
          0,
          0,
          XlsxNote(
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun('Ahmet:', font: XlsxFont(bold: true)),
              XlsxTextRun('\nCheck'),
            ]),
          ),
        ),
      );
      expect(
        parts[_comments1],
        contains(
          '<comment ref="A1" authorId="0"><text>'
          '<r><rPr><b/></rPr><t>Ahmet:</t></r>'
          '<r><t xml:space="preserve">\nCheck</t></r></text></comment>',
        ),
      );
    });

    test('holds several runs without fonts as <r> runs', () {
      // Ruling R1: only one fontless run is a plain string.
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.note(
          0,
          0,
          XlsxNote(
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun('a'),
              XlsxTextRun('b'),
            ]),
          ),
        ),
      );
      expect(
        parts[_comments1],
        contains('<text><r><t>a</t></r><r><t>b</t></r></text>'),
      );
    });

    test('holds one run with a font as a run', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.note(
          0,
          0,
          XlsxNote(
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun('x', font: XlsxFont(italic: true)),
            ]),
          ),
        ),
      );
      expect(
        parts[_comments1],
        contains('<text><r><rPr><i/></rPr><t>x</t></r></text>'),
      );
    });

    test('escapes the text and the author', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) =>
            s.note(0, 0, XlsxNote.plain(' _x0041_ & <', author: 'R&D _x0042_')),
      );
      expect(
        parts[_comments1],
        _commentsPart(
          '<author>R&amp;D _x005F_x0042_</author>',
          '<comment ref="A1" authorId="0"><text>'
              '<t xml:space="preserve"> _x005F_x0041_ &amp; &lt;</t></text>'
              '</comment>',
        ),
      );
    });

    test('holds an empty note as an empty t', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..note(0, 0, XlsxNote.plain(''))
          ..note(
            1,
            0,
            XlsxNote(
              XlsxRichText(const <XlsxTextRun>[
                XlsxTextRun('', font: XlsxFont(bold: true)),
              ]),
            ),
          ),
      );
      expect(
        parts[_comments1],
        _commentsPart(
          '<author></author>',
          '<comment ref="A1" authorId="0"><text><t></t></text></comment>'
              '<comment ref="A2" authorId="0"><text><t></t></text></comment>',
        ),
      );
    });

    test('lists each author once, in first use, the default as empty', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..note(0, 0, XlsxNote.plain('a', author: 'Ahmet'))
          ..note(1, 0, XlsxNote.plain('b'))
          ..note(2, 0, XlsxNote.plain('c', author: 'Ahmet'))
          ..note(3, 0, XlsxNote.plain('d', author: 'Ayse')),
      );
      expect(
        parts[_comments1],
        _commentsPart(
          '<author>Ahmet</author><author></author><author>Ayse</author>',
          '<comment ref="A1" authorId="0"><text><t>a</t></text></comment>'
              '<comment ref="A2" authorId="1"><text><t>b</t></text></comment>'
              '<comment ref="A3" authorId="0"><text><t>c</t></text></comment>'
              '<comment ref="A4" authorId="2"><text><t>d</t></text></comment>',
        ),
      );
    });

    test('writes comments by row, then column, and authors in that order', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..row(<Object?>['x'])
          ..note(2, 2, XlsxNote.plain('C3', author: 'Late'))
          ..note(0, 1, XlsxNote.plain('B1', author: 'Early'))
          ..note(2, 0, XlsxNote.plain('A3', author: 'Late'))
          ..note(0, 0, XlsxNote.plain('A1', author: 'Early')),
      );
      expect(
        parts[_comments1],
        _commentsPart(
          '<author>Early</author><author>Late</author>',
          '<comment ref="A1" authorId="0"><text><t>A1</t></text></comment>'
              '<comment ref="B1" authorId="0"><text><t>B1</t></text></comment>'
              '<comment ref="A3" authorId="1"><text><t>A3</t></text></comment>'
              '<comment ref="C3" authorId="1"><text><t>C3</t></text>'
              '</comment>',
        ),
      );
      expect(
        parts[_vml1],
        _vmlPart(
          '1',
          _shape(1025, 1, '1, 15, 0, 2, 3, 15, 4, 16', 0, 0) +
              _shape(1026, 2, '2, 15, 0, 2, 4, 15, 4, 16', 0, 1) +
              _shape(1027, 3, '1, 15, 1, 10, 3, 15, 5, 4', 2, 0) +
              _shape(1028, 4, '3, 15, 1, 10, 5, 15, 5, 4', 2, 2),
        ),
      );
    });
  });

  group('the VML drawing', () {
    test('holds one hidden note shape in Excel\'s markup', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) =>
            s.note(1, 1, XlsxNote.plain('Check this', author: 'Ahmet')),
      );
      expect(
        parts[_vml1],
        _vmlPart('1', _shape(1025, 1, '2, 15, 0, 10, 4, 15, 4, 4', 1, 1)),
      );
    });

    test('shows a visible note', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) =>
            s.note(1, 1, XlsxNote.plain('Shown', visible: true)),
      );
      expect(
        parts[_vml1],
        _vmlPart(
          '1',
          _shape(1025, 1, '2, 15, 0, 10, 4, 15, 4, 4', 1, 1, visible: true),
        ),
      );
    });

    test('keeps the boxes of notes at the edges inside the sheet', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..note(0, 0, XlsxNote.plain('A1'))
          ..note(0, 16383, XlsxNote.plain('XFD1'))
          ..note(1048575, 0, XlsxNote.plain('A1048576')),
      );
      expect(
        parts[_vml1],
        _vmlPart(
          '1',
          _shape(1025, 1, '1, 15, 0, 2, 3, 15, 4, 16', 0, 0) +
              _shape(1026, 2, '16380, 15, 0, 2, 16382, 15, 4, 16', 0, 16383) +
              _shape(
                1027,
                3,
                '1, 15, 1048571, 10, 3, 15, 1048575, 4',
                1048575,
                0,
              ),
        ),
      );
    });

    test('takes id blocks across the sheets in the order they finish', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('First');
      for (int i = 0; i < 1025; i++) {
        first.note(i, 0, XlsxNote.plain('n$i'));
      }
      book.addSheet('Plain').row(<Object?>[1]);
      book.addSheet('Last').note(0, 0, XlsxNote.plain('last'));
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, String> parts = readXlsx(result.bytes);

      final String vml1 = parts[_vml1]!;
      expect(vml1, contains('<o:idmap v:ext="edit" data="1,2"/>'));
      final List<String> ids = <String>[
        for (final RegExpMatch m in RegExp(
          r'<v:shape id="_x0000_s(\d+)"',
        ).allMatches(vml1))
          m.group(1)!,
      ];
      expect(ids, <String>[for (int i = 1025; i <= 2049; i++) '$i']);
      expect(vml1, contains('z-index:1025;'));

      expect(parts.containsKey('xl/drawings/vmlDrawing2.vml'), isFalse);
      expect(parts.containsKey('xl/comments2.xml'), isFalse);
      expect(
        parts['xl/drawings/vmlDrawing3.vml'],
        _vmlPart('3', _shape(3073, 1, '1, 15, 0, 2, 3, 15, 4, 16', 0, 0)),
      );
    });

    test('gives 1,024 notes two blocks, as their last id lies in the '
        'second', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('First');
      for (int i = 0; i < 1024; i++) {
        first.note(i, 0, XlsxNote.plain('n$i'));
      }
      book.addSheet('Next').note(0, 0, XlsxNote.plain('next'));
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, String> parts = readXlsx(result.bytes);

      final String vml1 = parts[_vml1]!;
      expect(vml1, contains('<o:idmap v:ext="edit" data="1,2"/>'));
      final List<String> ids = <String>[
        for (final RegExpMatch m in RegExp(
          r'<v:shape id="_x0000_s(\d+)"',
        ).allMatches(vml1))
          m.group(1)!,
      ];
      expect(ids, <String>[for (int i = 1025; i <= 2048; i++) '$i']);
      expect(
        parts['xl/drawings/vmlDrawing2.vml'],
        _vmlPart('3', _shape(3073, 1, '1, 15, 0, 2, 3, 15, 4, 16', 0, 0)),
      );
    });
  });

  group('the sheet', () {
    test('refers to the VML drawing after its links', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..row(<Object?>[XlsxHyperlink.url('https://example.com')])
          ..note(0, 1, XlsxNote.plain('n')),
      );
      expect(
        parts['xl/worksheets/sheet1.xml'],
        endsWith('<legacyDrawing r:id="rId2"/></worksheet>'),
      );
      expect(
        parts['xl/worksheets/_rels/sheet1.xml.rels'],
        allOf(
          contains('Id="rId1" Type="${RelType.hyperlink}"'),
          contains(
            '<Relationship Id="rId2" Type="${RelType.vmlDrawing}" '
            'Target="../drawings/vmlDrawing1.vml"/>'
            '<Relationship Id="rId3" Type="${RelType.comments}" '
            'Target="../comments1.xml"/>',
          ),
        ),
      );
    });

    test('with only notes gets a relationships part for them', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.note(0, 0, XlsxNote.plain('n')),
      );
      expect(
        parts['xl/worksheets/sheet1.xml'],
        endsWith('<sheetData/><legacyDrawing r:id="rId1"/></worksheet>'),
      );
      expect(
        parts['xl/worksheets/_rels/sheet1.xml.rels'],
        '$_decl<Relationships xmlns="${Ns.packageRel}">'
        '<Relationship Id="rId1" Type="${RelType.vmlDrawing}" '
        'Target="../drawings/vmlDrawing1.vml"/>'
        '<Relationship Id="rId2" Type="${RelType.comments}" '
        'Target="../comments1.xml"/>'
        '</Relationships>',
      );
    });

    test('without notes writes no note part', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.row(<Object?>['x']),
      );
      expect(parts.keys, isNot(contains(_comments1)));
      expect(parts.keys, isNot(contains(_vml1)));
      expect(parts['xl/worksheets/sheet1.xml'], isNot(contains('legacy')));
      expect(parts['[Content_Types].xml'], isNot(contains('vml')));
    });

    test('writes the worksheet, its rels, the comments and the VML', () {
      final List<String> names = _parts(
        (XlsxSheetWriter s) => s.note(0, 0, XlsxNote.plain('n')),
      ).keys.toList();
      final int sheet = names.indexOf('xl/worksheets/sheet1.xml');
      expect(sheet, isNonNegative);
      expect(names.sublist(sheet, sheet + 4), <String>[
        'xl/worksheets/sheet1.xml',
        'xl/worksheets/_rels/sheet1.xml.rels',
        _comments1,
        _vml1,
      ]);
    });

    test('registers the vml default once and each comments part', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('A').note(0, 0, XlsxNote.plain('a'));
      book.addSheet('B').row(<Object?>[1]);
      book.addSheet('C').note(0, 0, XlsxNote.plain('c'));
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final String types = readXlsx(result.bytes)['[Content_Types].xml']!;
      const String vml =
          '<Default Extension="vml" ContentType="${ContentType.vmlDrawing}"/>';
      expect(vml.allMatches(types), hasLength(1));
      for (final int n in <int>[1, 3]) {
        expect(
          types,
          contains(
            '<Override PartName="/xl/comments$n.xml" '
            'ContentType="${ContentType.comments}"/>',
          ),
        );
      }
      expect(types, isNot(contains('/xl/comments2.xml')));
    });
  });

  group('XlsxSheetWriter.note', () {
    Matcher argumentError(String name) =>
        isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name);

    test('removes characters XML forbids, with a warning at the cell', () {
      final XlsxWriter book = XlsxWriter();
      book
          .addSheet('S')
          .note(
            1,
            1,
            XlsxNote(
              XlsxRichText(const <XlsxTextRun>[
                XlsxTextRun('a\u0001b'),
                XlsxTextRun('\u0002', font: XlsxFont(bold: true)),
              ]),
            ),
          );
      final XlsxResult result = book.close();
      expect(result.warnings, hasLength(1));
      final XlsxWarning warning = result.warnings.single;
      expect(warning.code, XlsxWarningCode.invalidCharactersRemoved);
      expect(warning.sheet, 'S');
      expect(warning.cells, <String>['B2']);
      expect(warning.count, 1);
      expect(
        readXlsx(result.bytes)[_comments1],
        contains('<text><t>ab</t></text>'),
      );
    });

    test('cuts text past 32,767 units, with a warning at the cell', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').note(2, 0, XlsxNote.plain('a' * 32768));
      final XlsxResult result = book.close();
      final XlsxWarning warning = result.warnings.single;
      expect(warning.code, XlsxWarningCode.textTruncated);
      expect(warning.sheet, 'S');
      expect(warning.cells, <String>['A3']);
      expect(
        readXlsx(result.bytes)[_comments1],
        contains('<text><t>${'a' * 32767}</t></text>'),
      );
    });

    test('refuses an author with a character XML forbids', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      expect(
        () => sheet.note(0, 0, XlsxNote.plain('n', author: 'A\u0001')),
        throwsA(argumentError('author')),
      );
    });

    test('refuses an author longer than 255 units', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      expect(
        () => sheet.note(0, 0, XlsxNote.plain('n', author: 'a' * 256)),
        throwsA(argumentError('author')),
      );
      sheet.note(0, 0, XlsxNote.plain('n', author: 'a' * 255));
      expect(
        readXlsx(book.close().bytes)[_comments1],
        contains('<author>${'a' * 255}</author>'),
      );
    });

    test('refuses a cell outside the sheet', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      final XlsxNote note = XlsxNote.plain('n');
      expect(() => sheet.note(-1, 0, note), throwsA(argumentError('row')));
      expect(() => sheet.note(1048576, 0, note), throwsA(argumentError('row')));
      expect(() => sheet.note(0, -1, note), throwsA(argumentError('column')));
      expect(
        () => sheet.note(0, 16384, note),
        throwsA(argumentError('column')),
      );
    });

    test('refuses a second note on a cell, naming it', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      sheet.note(1, 1, XlsxNote.plain('first'));
      expect(
        () => sheet.note(1, 1, XlsxNote.plain('second\u0001')),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('B2'),
          ),
        ),
      );
      final XlsxResult result = book.close();
      expect(result.warnings, isEmpty);
      final String comments = readXlsx(result.bytes)[_comments1]!;
      expect(comments, contains('<t>first</t>'));
      expect(comments, isNot(contains('second')));
    });

    test('refuses a text without runs', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      expect(
        () => sheet.note(0, 0, XlsxNote(XlsxRichText(const <XlsxTextRun>[]))),
        throwsA(argumentError('runs')),
      );
    });

    test('refuses a run with an invalid font, naming the run', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      expect(
        () => sheet.note(
          0,
          0,
          XlsxNote(
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun('a'),
              XlsxTextRun('b', font: XlsxFont(size: 0)),
            ]),
          ),
        ),
        throwsA(argumentError('runs[1].font.size')),
      );
    });

    test('records nothing when it throws', () {
      final XlsxWriter book = XlsxWriter();
      final WorksheetWriter sheet = book.addSheet('S') as WorksheetWriter;
      final XlsxNote dirty = XlsxNote(
        XlsxRichText(<XlsxTextRun>[
          XlsxTextRun('a\u0001${'b' * 32768}'),
          const XlsxTextRun('c', font: XlsxFont(size: 0)),
        ]),
      );
      expect(() => sheet.note(0, 0, dirty), throwsArgumentError);
      expect(
        () => sheet.note(0, 0, XlsxNote(dirty.text, author: '\u0001')),
        throwsArgumentError,
      );
      expect(sheet.holdsTrailerData, isFalse);
      final XlsxResult result = book.close();
      expect(result.warnings, isEmpty);
      final Map<String, String> parts = readXlsx(result.bytes);
      expect(parts.keys, isNot(contains(_comments1)));
      expect(parts.keys, isNot(contains(_vml1)));
    });

    test('throws StateError once the sheet is finished', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('First');
      book.addSheet('Second');
      expect(() => first.note(0, 0, XlsxNote.plain('n')), throwsStateError);
    });

    test('holds its notes until the sheet finishes', () {
      final XlsxWriter book = XlsxWriter();
      final WorksheetWriter sheet = book.addSheet('S') as WorksheetWriter;
      expect(sheet.holdsTrailerData, isFalse);
      sheet.note(0, 0, XlsxNote.plain('n'));
      expect(sheet.holdsTrailerData, isTrue);
      book.addSheet('T');
      expect(sheet.holdsTrailerData, isFalse);
      expect(readXlsx(book.close().bytes), contains(_comments1));
    });
  });
}
