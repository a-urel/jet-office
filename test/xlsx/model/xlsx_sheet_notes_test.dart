import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

const String _vmlHead =
    '<xml xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:x="urn:schemas-microsoft-com:office:excel">';

String _vmlShape(int row, int column, {bool visible = false}) =>
    '<v:shape id="_x0000_s1025" type="#_x0000_t202">'
    '<x:ClientData ObjectType="Note"><x:Row>$row</x:Row>'
    '<x:Column>$column</x:Column>${visible ? '<x:Visible/>' : ''}'
    '</x:ClientData></v:shape>';

/// A one-sheet package whose sheet has [comments] (raw part text) and, when
/// given, [vml], with the sheet's `legacyDrawing` naming the VML part.
Uint8List _package({String? comments, String? vml}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    buildWorkbook(<String, String>{
      'S':
          '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>'
          '${vml != null ? '<legacyDrawing r:id="rId1"/>' : ''}'
          '</worksheet>',
    }),
  );
  parts['xl/worksheets/_rels/sheet1.xml.rels'] = Uint8List.fromList(
    utf8.encode(
      '<Relationships xmlns="$pkgRelNs">'
      '${vml == null ? '' : '<Relationship Id="rId1" Type="$relNs/vmlDrawing" '
                'Target="../drawings/vmlDrawing1.vml"/>'}'
      '${comments == null ? '' : '<Relationship Id="rId2" Type="$relNs/comments" '
                'Target="../comments1.xml"/>'}'
      '</Relationships>',
    ),
  );
  if (comments != null) {
    parts['xl/comments1.xml'] = Uint8List.fromList(utf8.encode(comments));
  }
  if (vml != null) {
    parts['xl/drawings/vmlDrawing1.vml'] = Uint8List.fromList(utf8.encode(vml));
  }
  return buildZip(<String, List<int>>{...parts});
}

String _comments(String list, {String authors = '<author>A</author>'}) =>
    '<comments xmlns="$mainNs"><authors>$authors</authors>'
    '<commentList>$list</commentList></comments>';

String _comment(String ref, String text, {int author = 0}) =>
    '<comment ref="$ref" authorId="$author"><text>$text</text></comment>';

String _vml(Uint8List bytes) => readXlsx(bytes)['xl/drawings/vmlDrawing1.vml']!;

int _invalid(XlsxWorkbook book, String detail) => book.warnings
    .where(
      (XlsxWarning w) =>
          w.code == XlsxWarningCode.featureEntryInvalid && w.detail == detail,
    )
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

void main() {
  test("reads the fixture's notes", () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_notes'));
    final XlsxSheet notes = book.sheets.first;
    expect(notes.notes.map((XlsxCellNote n) => (n.row, n.column)), <(int, int)>[
      (1, 1),
      (2, 2),
      (3, 3),
    ]);
    expect(notes.notes[0].note, XlsxNote.plain('Check this', author: 'Ahmet'));
    final XlsxNote rich = notes.notes[1].note;
    expect(rich.author, 'Ahmet');
    expect(rich.visible, isFalse);
    expect(rich.text.runs.map((XlsxTextRun r) => r.text), <String>[
      'Ahmet:',
      '\nThe total is checked.',
    ]);
    expect(rich.text.runs[0].font?.bold, isTrue);
    expect(rich.text.runs[1].font, isNull);
    expect(
      notes.notes[2].note,
      XlsxNote.plain('Always shown', author: 'Ayse Yilmaz', visible: true),
    );
    expect(book.sheets[1].noteAt(0, 16383)!.text.text, 'The last column');
    expect(book.sheets[2].noteAt(1048575, 0)!.text.text, 'The last row');
    expect(book.warnings, isEmpty);
  });

  test('plain <t> text reads one run without a font', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(comments: _comments(_comment('A1', '<t>Plain</t>'))),
    );
    final XlsxNote note = book.sheets.single.noteAt(0, 0)!;
    expect(note.text.runs, hasLength(1));
    expect(note.text.runs.single.text, 'Plain');
    expect(note.text.runs.single.font, isNull);
    expect(note.visible, isFalse);
  });

  test('noteAt finds one and null elsewhere', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_notes'));
    final XlsxSheet sheet = book.sheets.first;
    expect(sheet.noteAt(1, 1)!.text.text, 'Check this');
    expect(sheet.noteAt(0, 0), isNull);
    expect(sheet.noteAt(1, 2), isNull);
  });

  test('a sheet without notes reads empty', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_package());
    expect(book.sheets.first.notes, isEmpty);
    expect(book.sheets.first.noteAt(0, 0), isNull);
    expect(
      () => book.sheets.first.notes.add((
        row: 0,
        column: 0,
        note: XlsxNote.plain(''),
      )),
      throwsUnsupportedError,
    );
  });

  test('a repeated ref is kept and warned', () {
    final Uint8List input = _package(
      comments: _comments(
        _comment('A1', '<t>first</t>') + _comment('A1', '<t>second</t>'),
      ),
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(book.sheets.single.notes, hasLength(1));
    expect(book.sheets.single.noteAt(0, 0)!.text.text, 'first');
    expect(_invalid(book, 'comment'), 1);
    expect(
      comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  test('a bad authorId reads an empty author', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(comments: _comments(_comment('A1', '<t>x</t>', author: 5))),
    );
    expect(book.sheets.single.noteAt(0, 0)!.author, '');
    expect(_invalid(book, 'comment'), 1);
  });

  test('VML that is not XML warns and reads visible false', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        comments: _comments(_comment('A1', '<t>x</t>')),
        vml: '$_vmlHead<v:shape><br></xml>',
      ),
    );
    expect(book.sheets.single.noteAt(0, 0)!.visible, isFalse);
    expect(book.sheets.single.notes, hasLength(1));
    expect(_invalid(book, 'legacyDrawing'), 1);
  });

  group('the colour of a run', () {
    XlsxWorkbook open(int index) => XlsxWorkbook.open(
      _package(
        comments: _comments(
          _comment(
            'A1',
            '<r><rPr><b/><color indexed="$index"/></rPr><t>x</t></r>',
          ),
        ),
      ),
    );

    test("Excel's indexed 81 reads as no colour, without a warning", () {
      final XlsxWorkbook book = open(81);
      final XlsxFont font = book.sheets.single.noteAt(0, 0)!.text.runs[0].font!;
      expect(font.bold, isTrue);
      expect(font.color, isNull);
      expect(book.warnings, isEmpty);
    });

    test('another index past the palette warns', () {
      final XlsxWorkbook book = open(82);
      final XlsxFont font = book.sheets.single.noteAt(0, 0)!.text.runs[0].font!;
      expect(font.color, isNull);
      expect(_invalid(book, 'rPr'), 1);
    });

    test('the writer still refuses indexed 81', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
      expect(
        () => sheet.setNote(
          0,
          0,
          XlsxNote(
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun('x', font: XlsxFont(color: XlsxColor.indexed(81))),
            ]),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  test('a legacyDrawing id with no relationship has no boxes', () {
    final Map<String, Uint8List> parts = readXlsxBytes(
      _package(
        comments: _comments(_comment('A1', '<t>x</t>')),
        vml: '$_vmlHead${_vmlShape(0, 0, visible: true)}</xml>',
      ),
    );
    parts['xl/worksheets/sheet1.xml'] = Uint8List.fromList(
      utf8.encode(
        utf8
            .decode(parts['xl/worksheets/sheet1.xml']!)
            .replaceFirst('r:id="rId1"', 'r:id="rId9"'),
      ),
    );
    final Uint8List input = buildZip(<String, List<int>>{...parts});
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.noteAt(0, 0)!.visible, isFalse);
    sheet.setNote(1, 1, XlsxNote.plain('y'));
    final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
    expect(again.sheets.single.notes, hasLength(2));
  });

  test('visible comes from the shape of the same row and column', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        comments: _comments(
          _comment('A1', '<t>x</t>') + _comment('B2', '<t>y</t>'),
        ),
        vml:
            '$_vmlHead${_vmlShape(0, 0)}${_vmlShape(1, 1, visible: true)}'
            '</xml>',
      ),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.noteAt(0, 0)!.visible, isFalse);
    expect(sheet.noteAt(1, 1)!.visible, isTrue);
    expect(book.warnings, isEmpty);
  });

  test('a comments part that is not SpreadsheetML reads no notes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(comments: '<comments xmlns="urn:other"/>'),
    );
    expect(book.sheets.single.notes, isEmpty);
    expect(_invalid(book, 'comment'), 1);
  });

  test('a prefixed comments root reads', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        comments:
            '<c:comments xmlns:c="$mainNs"><c:authors><c:author>Z'
            '</c:author></c:authors><c:commentList><c:comment ref="C3" '
            'authorId="0"><c:text><c:r><c:t>pre</c:t></c:r></c:text>'
            '</c:comment></c:commentList></c:comments>',
      ),
    );
    final XlsxNote note = book.sheets.single.noteAt(2, 2)!;
    expect((note.text.text, note.author), ('pre', 'Z'));
  });

  test('more comments than maxMerges throws limitExceeded', () {
    final Uint8List input = _package(
      comments: _comments(
        _comment('A1', '<t>x</t>') + _comment('A2', '<t>y</t>'),
      ),
    );
    final XlsxWorkbook book = XlsxWorkbook.open(
      input,
      limits: const XlsxReadLimits(maxMerges: 1),
    );
    expect(
      () => book.sheets.single.notes,
      throwsA(
        isA<XlsxReadException>().having(
          (XlsxReadException e) => e.reason,
          'reason',
          XlsxReadFailure.limitExceeded,
        ),
      ),
    );
  });

  test('more VML shapes than maxMerges leave the part as written', () {
    final Uint8List input = _package(
      comments: _comments(_comment('A1', '<t>x</t>')),
      vml: '$_vmlHead${_vmlShape(0, 0)}${_vmlShape(1, 1)}</xml>',
    );
    final XlsxWorkbook book = XlsxWorkbook.open(
      input,
      limits: const XlsxReadLimits(maxMerges: 1),
    );
    expect(
      () => book.sheets.single.notes,
      throwsA(
        isA<XlsxReadException>().having(
          (XlsxReadException e) => e.reason,
          'reason',
          XlsxReadFailure.limitExceeded,
        ),
      ),
    );
    expect(
      comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  test('reading saves the input unchanged', () {
    final Uint8List input = _fixture('m4_notes');
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    for (final XlsxSheet sheet in book.sheets) {
      expect(sheet.notes, isNotEmpty);
    }
    expect(
      comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  group('setNote', () {
    test('adds to a sheet without notes', () {
      final Uint8List input = buildWorkbook(<String, String>{
        'S':
            '<worksheet xmlns="$mainNs"><sheetData/><pageSetup paperSize="9"/>'
            '<tableParts count="0"/></worksheet>',
      });
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxNote note = XlsxNote.plain('New', author: 'Ayşe');
      book.sheets.single.setNote(2, 1, note);
      expect(book.sheets.single.noteAt(2, 1), note);
      final Uint8List saved = book.save().bytes;
      final Map<String, String> parts = readXlsx(saved);
      expect(parts.keys, contains('xl/comments1.xml'));
      expect(parts.keys, contains('xl/drawings/vmlDrawing1.vml'));
      final String types = parts['[Content_Types].xml']!;
      expect(types, contains('Extension="vml"'));
      expect(types, contains('PartName="/xl/comments1.xml"'));
      final String rels = parts['xl/worksheets/_rels/sheet1.xml.rels']!;
      expect(
        rels.indexOf('vmlDrawing1.vml'),
        lessThan(rels.indexOf('comments1.xml')),
      );
      expect(rels, contains('Target="../drawings/vmlDrawing1.vml"'));
      expect(rels, contains('Target="../comments1.xml"'));
      final String sheet = parts['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('legacyDrawing'));
      expect(
        sheet.indexOf('pageSetup'),
        lessThan(sheet.indexOf('legacyDrawing')),
      );
      expect(
        sheet.indexOf('legacyDrawing'),
        lessThan(sheet.indexOf('tableParts')),
      );
      final XlsxWorkbook again = XlsxWorkbook.open(saved);
      expect(again.sheets.single.notes, hasLength(1));
      expect(again.sheets.single.noteAt(2, 1), note);
      expect(again.warnings, isEmpty);
    });

    test('rich text and visible read back equal', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_package());
      final XlsxNote note = XlsxNote(
        XlsxRichText(<XlsxTextRun>[
          const XlsxTextRun('Bold', font: XlsxFont(bold: true)),
          const XlsxTextRun(' plain'),
        ]),
        author: 'A',
        visible: true,
      );
      book.sheets.single.setNote(0, 0, note);
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.sheets.single.noteAt(0, 0), note);
    });

    test('a new comment goes in row-major order', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(
            _comment('A1', '<t>a</t>') + _comment('C3', '<t>c</t>'),
          ),
          vml: '$_vmlHead${_vmlShape(0, 0)}${_vmlShape(2, 2)}</xml>',
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setNote(1, 1, XlsxNote.plain('b', author: 'A'));
      sheet.setNote(9, 9, XlsxNote.plain('z', author: 'A'));
      expect(sheet.notes.map((XlsxCellNote n) => n.note.text.text), <String>[
        'a',
        'b',
        'c',
        'z',
      ]);
    });

    test('adds beside a form control shape', () {
      const String control =
          '<v:shape id="_x0000_s1025" type="#_x0000_t201" style="z-index:7">'
          '<x:ClientData ObjectType="Button"><x:FmlaMacro>[0]!Go'
          '</x:FmlaMacro></x:ClientData></v:shape>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          vml:
              '$_vmlHead<o:shapelayout v:ext="edit"><o:idmap v:ext="edit" '
              'data="1"/></o:shapelayout>$control</xml>',
        ),
      );
      book.sheets.single.setNote(0, 0, XlsxNote.plain('n'));
      final Uint8List saved = book.save().bytes;
      final String vml = _vml(saved);
      expect(vml, contains(control));
      expect(vml, contains('id="_x0000_s1026"'));
      expect(vml, contains('z-index:8'));
      expect(vml, contains('id="_x0000_t202"'));
      expect(readXlsx(saved).keys, contains('xl/comments1.xml'));
      expect(
        readXlsx(saved).keys.where((String n) => n.endsWith('.vml')),
        hasLength(1),
      );
      expect(
        XlsxWorkbook.open(saved).sheets.single.noteAt(0, 0)!.text.text,
        'n',
      );
    });

    test('replaces text and keeps xr:uid and the shape', () {
      const String ns = 'xmlns:xr="urn:xr"';
      final String shape = _vmlShape(0, 0);
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(
            '<comment ref="A1" authorId="0" shapeId="0" xr:uid="{1}" $ns>'
            '<text><t>old</t></text></comment>',
          ),
          vml: '$_vmlHead$shape</xml>',
        ),
      );
      final XlsxNote note = XlsxNote.plain('new', author: 'B');
      book.sheets.single.setNote(0, 0, note);
      expect(book.sheets.single.noteAt(0, 0), note);
      final Uint8List saved = book.save().bytes;
      final String comments = readXlsx(saved)['xl/comments1.xml']!;
      expect(comments, contains('xr:uid="{1}"'));
      expect(comments, contains('shapeId="0"'));
      expect(comments, contains('authorId="1"'));
      expect(comments, contains('<t>new</t>'));
      expect(comments, isNot(contains('old')));
      expect(_vml(saved), contains(shape));
      expect(XlsxWorkbook.open(saved).sheets.single.noteAt(0, 0), note);
    });

    test('a prefixed comments root takes new and replaced notes', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments:
              '<c:comments xmlns:c="$mainNs"><c:authors><c:author>Z</c:author>'
              '</c:authors><c:commentList><c:comment ref="A1" authorId="0">'
              '<c:text><c:t>x</c:t></c:text></c:comment></c:commentList>'
              '</c:comments>',
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setNote(0, 0, XlsxNote.plain('r', author: 'Z'));
      sheet.setNote(1, 0, XlsxNote.plain('n', author: 'Z'));
      final XlsxSheet again = XlsxWorkbook.open(
        book.save().bytes,
      ).sheets.single;
      expect(again.noteAt(0, 0)!.text.text, 'r');
      expect(again.noteAt(1, 0)!.text.text, 'n');
    });

    test('visible toggles the shape', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(_comment('A1', '<t>x</t>')),
          vml:
              '$_vmlHead<v:shape id="_x0000_s1025" '
              'style="position:absolute;visibility:hidden">'
              '<x:ClientData ObjectType="Note"><x:Row>0</x:Row>'
              '<x:Column>0</x:Column></x:ClientData></v:shape></xml>',
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setNote(0, 0, XlsxNote.plain('x', author: 'A', visible: true));
      expect(sheet.noteAt(0, 0)!.visible, isTrue);
      String vml = _vml(book.save().bytes);
      expect(vml, contains('visibility:visible'));
      expect(vml, contains('<x:Visible/>'));
      sheet.setNote(0, 0, XlsxNote.plain('x', author: 'A'));
      expect(sheet.noteAt(0, 0)!.visible, isFalse);
      vml = _vml(book.save().bytes);
      expect(vml, contains('visibility:hidden'));
      expect(vml, isNot(contains('Visible')));
    });

    test('an author is reused and a new one appended', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(
            _comment('A1', '<t>x</t>'),
            authors: '<author>A</author><author>Unused</author>',
          ),
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setNote(1, 0, XlsxNote.plain('y', author: 'A'));
      sheet.setNote(2, 0, XlsxNote.plain('z', author: 'New'));
      final String comments = readXlsx(book.save().bytes)['xl/comments1.xml']!;
      expect(
        comments,
        contains(
          '<authors><author>A</author><author>Unused</author>'
          '<author>New</author></authors>',
        ),
      );
      expect(comments, contains('ref="A2" authorId="0"'));
      expect(comments, contains('ref="A3" authorId="2"'));
    });

    test('shape ids and blocks stay unique across sheets, unloaded ones '
        'included', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_notes'));
      final XlsxSheet added = book.addSheet('Added');
      final XlsxSheet other = book.addSheet('Other');
      added.setNote(0, 0, XlsxNote.plain('a'));
      other.setNote(0, 0, XlsxNote.plain('b'));
      final Map<String, String> parts = readXlsx(book.save().bytes);
      final List<String> blocks = <String>[];
      final List<String> ids = <String>[];
      for (final MapEntry<String, String> p in parts.entries) {
        if (!p.key.endsWith('.vml')) continue;
        blocks.addAll(
          RegExp(
            r'data="([^"]*)"',
          ).allMatches(p.value).expand((Match m) => m[1]!.split(',')),
        );
        ids.addAll(
          RegExp(
            r'<v:shape id="([^"]*)"',
          ).allMatches(p.value).map((Match m) => m[1]!),
        );
      }
      expect(blocks.length, greaterThanOrEqualTo(5));
      expect(blocks.toSet(), hasLength(blocks.length));
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('1,100 notes take a second block', () {
      final Uint8List input = _package();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        for (int i = 0; i < 1100; i++) {
          sheet.setNote(i, 0, XlsxNote.plain('n$i'));
        }
      });
      final Uint8List saved = book.save().bytes;
      final String vml = _vml(saved);
      expect(vml, contains('data="1,2"'));
      final List<int> ids = RegExp(
        r'<v:shape id="_x0000_s(\d+)"',
      ).allMatches(vml).map((Match m) => int.parse(m[1]!)).toList();
      expect(ids, hasLength(1100));
      expect(ids.toSet(), hasLength(1100));
      expect(ids.map((int id) => id ~/ 1024).toSet(), <int>{1, 2});
      expect(XlsxWorkbook.open(saved).sheets.single.notes, hasLength(1100));
      log.revertSet(set);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
      log.reapplySet(set);
      expect(_vml(book.save().bytes), vml);
    });

    test('removing the last note removes both parts and legacyDrawing', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(_comment('A1', '<t>x</t>')),
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        ),
      );
      book.sheets.single.setNote(0, 0, null);
      expect(book.sheets.single.notes, isEmpty);
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts.keys, isNot(contains('xl/comments1.xml')));
      expect(parts.keys, isNot(contains('xl/drawings/vmlDrawing1.vml')));
      expect(
        parts['xl/worksheets/sheet1.xml'],
        isNot(contains('legacyDrawing')),
      );
      expect(parts['[Content_Types].xml'], isNot(contains('comments1')));
      expect(
        parts['xl/worksheets/_rels/sheet1.xml.rels'] ?? '',
        isNot(contains('Target')),
      );
    });

    test('removing one of several keeps the text between shapes', () {
      final String source =
          '$_vmlHead${_vmlShape(0, 0)}<v:rect id="r1"/>${_vmlShape(1, 1)}'
          '<v:rect id="r2"/>${_vmlShape(2, 2)}</xml>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(
            _comment('A1', '<t>x</t>') +
                _comment('B2', '<t>y</t>') +
                _comment('C3', '<t>z</t>'),
          ),
          vml: source,
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        sheet.setNote(0, 0, null);
        sheet.setNote(1, 1, null);
      });
      final String vml = _vml(book.save().bytes);
      expect(vml, contains('<v:rect id="r1"/><v:rect id="r2"/>'));
      expect(vml, contains('<x:Row>2</x:Row>'));
      expect(vml, isNot(contains('<x:Row>0</x:Row>')));
      expect(vml, isNot(contains('<x:Row>1</x:Row>')));
      log.revertSet(set);
      expect(_vml(book.save().bytes), source);
    });

    test('notes set in order are what the writer writes', () {
      final List<XlsxNote> notes = <XlsxNote>[
        XlsxNote.plain('One', author: 'A'),
        XlsxNote(
          XlsxRichText(const <XlsxTextRun>[
            XlsxTextRun('Two', font: XlsxFont(bold: true)),
          ]),
          author: 'B',
          visible: true,
        ),
        XlsxNote.plain('Three', author: 'A'),
      ];
      final XlsxWriter writer = XlsxWriter();
      final XlsxSheetWriter written = writer.addSheet('S');
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      for (int i = 0; i < notes.length; i++) {
        written.note(i, i, notes[i]);
        sheet.setNote(i, i, notes[i]);
      }
      final Map<String, String> expected = readXlsx(writer.close().bytes);
      final Map<String, String> actual = readXlsx(book.save().bytes);
      for (final String part in <String>[
        'xl/comments1.xml',
        'xl/drawings/vmlDrawing1.vml',
        'xl/worksheets/_rels/sheet1.xml.rels',
      ]) {
        expect(actual[part], expected[part], reason: part);
      }
    });

    test('the VML of a sheet with shapes but no idmap gets one', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(_comment('A1', '<t>x</t>')),
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        ),
      );
      book.sheets.single.setNote(1, 1, XlsxNote.plain('y', author: 'A'));
      final String vml = _vml(book.save().bytes);
      expect(vml, contains('<o:shapelayout v:ext="edit"><o:idmap'));
      expect(vml, contains('id="_x0000_t202"'));
      expect(
        RegExp(r'<v:shape id="[^"]*"').allMatches(vml).map((Match m) => m[0]),
        hasLength(2),
      );
    });

    test('a replaced comment with no text and no authorId takes both', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(
            '<comment ref="A1"/><comment ref="B1"><x/></comment>',
          ),
          vml: '$_vmlHead${_vmlShape(0, 0)}${_vmlShape(0, 1)}</xml>',
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setNote(0, 0, XlsxNote.plain('a', author: 'A'));
      sheet.setNote(0, 1, XlsxNote.plain('b', author: 'A'));
      final XlsxSheet again = XlsxWorkbook.open(
        book.save().bytes,
      ).sheets.single;
      expect(again.noteAt(0, 0), XlsxNote.plain('a', author: 'A'));
      expect(again.noteAt(0, 1), XlsxNote.plain('b', author: 'A'));
    });

    test('a child of the comment list with a ref takes no cell', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(
            '<other ref="A1" authorId="0"/>${_comment('A1', '<t>real</t>')}',
          ),
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.noteAt(0, 0), XlsxNote.plain('real', author: 'A'));
      expect(sheet.notes, hasLength(1));
      sheet.setNote(0, 0, XlsxNote.plain('new', author: 'A'));
      final String comments = readXlsx(book.save().bytes)['xl/comments1.xml']!;
      expect(comments, contains('<other ref="A1" authorId="0"/>'));
      expect(comments, contains('<t>new</t>'));
      expect(comments, isNot(contains('real')));
    });

    test('a sheet in a subfolder gets relationships that resolve', () {
      final Map<String, Uint8List> parts = readXlsxBytes(
        buildWorkbook(<String, String>{
          'S': '<worksheet xmlns="$mainNs"><sheetData/></worksheet>',
        }),
      );
      String moved(String name) => utf8
          .decode(parts[name]!)
          .replaceAll('worksheets/sheet1.xml', 'worksheets/sub/sheet1.xml');
      parts['xl/worksheets/sub/sheet1.xml'] = parts.remove(
        'xl/worksheets/sheet1.xml',
      )!;
      for (final String name in <String>[
        '[Content_Types].xml',
        'xl/_rels/workbook.xml.rels',
      ]) {
        parts[name] = Uint8List.fromList(utf8.encode(moved(name)));
      }
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildZip(<String, List<int>>{...parts}),
      );
      final XlsxNote note = XlsxNote.plain('n', author: 'A', visible: true);
      book.sheets.single.setNote(0, 0, note);
      final Uint8List saved = book.save().bytes;
      final String rels = readXlsx(
        saved,
      )['xl/worksheets/sub/_rels/sheet1.xml.rels']!;
      expect(rels, contains('Target="../../comments1.xml"'));
      expect(rels, contains('Target="../../drawings/vmlDrawing1.vml"'));
      final XlsxWorkbook again = XlsxWorkbook.open(saved);
      expect(again.sheets.single.noteAt(0, 0), note);
      expect(again.warnings, isEmpty);
    });

    test('an empty VML root keeps what surrounds it', () {
      const String source =
          '<?xml version="1.0"?><!-- keep -->'
          '<xml xmlns:v="urn:schemas-microsoft-com:vml"/><!-- after -->';
      final XlsxWorkbook book = XlsxWorkbook.open(_package(vml: source));
      final ChangeSet set = changeLogOf(book).transaction(
        () => book.sheets.single.setNote(0, 0, XlsxNote.plain('n')),
      );
      final Uint8List saved = book.save().bytes;
      final String vml = _vml(saved);
      expect(vml, startsWith('<?xml version="1.0"?><!-- keep --><xml '));
      expect(vml, endsWith('</v:shape></xml><!-- after -->'));
      expect(XlsxWorkbook.open(saved).sheets.single.notes, hasLength(1));
      changeLogOf(book).revertSet(set);
      expect(_vml(book.save().bytes), source);
    });

    test('a child of the comment list that is no comment is kept', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments('${_comment('A1', '<t>x</t>')}<other a="1"/>'),
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        ),
      );
      book.sheets.single.setNote(0, 0, null);
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts['xl/comments1.xml'], contains('<other a="1"/>'));
    });

    test('removing keeps VML with a form control', () {
      const String control =
          '<v:shape id="_x0000_s1026" type="#_x0000_t201">'
          '<x:ClientData ObjectType="Button"/></v:shape>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(_comment('A1', '<t>x</t>')),
          vml: '$_vmlHead${_vmlShape(0, 0)}$control</xml>',
        ),
      );
      book.sheets.single.setNote(0, 0, null);
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts.keys, isNot(contains('xl/comments1.xml')));
      expect(parts['xl/drawings/vmlDrawing1.vml'], contains(control));
      expect(parts['xl/drawings/vmlDrawing1.vml'], isNot(contains('"Note"')));
      expect(parts['xl/worksheets/sheet1.xml'], contains('legacyDrawing'));
    });

    test('removing keeps VML that holds another kind of element', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(_comment('A1', '<t>x</t>')),
          vml: '$_vmlHead${_vmlShape(0, 0)}<v:rect id="r1"/></xml>',
        ),
      );
      book.sheets.single.setNote(0, 0, null);
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(
        parts['xl/drawings/vmlDrawing1.vml'],
        contains('<v:rect id="r1"/>'),
      );
    });

    test('a tc= note throws StateError and nothing changes', () {
      final Uint8List input = _package(
        comments: _comments(
          _comment('A1', '<t>[Threaded comment]</t>'),
          authors: '<author>tc={A1B2}</author>',
        ),
        vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(() => sheet.setNote(0, 0, null), throwsStateError);
      expect(() => sheet.setNote(0, 0, XlsxNote.plain('x')), throwsStateError);
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
    });

    group('a note set back as read is no edit', () {
      void expectNoEdit(
        String comment, {
        String authors = '<author>A</author>',
      }) {
        final Uint8List input = _package(
          comments: _comments(comment, authors: authors),
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        );
        final XlsxWorkbook book = XlsxWorkbook.open(input);
        final XlsxSheet sheet = book.sheets.single;
        final int before = book.warnings.length;
        sheet.setNote(0, 0, sheet.noteAt(0, 0));
        expect(changeLogOf(book).hasChanges, isFalse);
        expect(book.warnings, hasLength(before));
        expect(
          comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
        );
      }

      test('the note of a thread', () {
        expectNoEdit(
          _comment('A1', '<t>[Threaded comment]</t>'),
          authors: '<author>tc={A1B2}</author>',
        );
      });

      test('an author the writer refuses', () {
        expectNoEdit(
          _comment('A1', '<t>x</t>'),
          authors: '<author>${'a' * 300}</author>',
        );
      });

      test('a text the writer would cut', () {
        expectNoEdit(_comment('A1', '<t>${'a' * 40000}</t>'));
      });
    });

    test('undo of the last note gives a repeated <legacyDrawing> back', () {
      final Map<String, Uint8List> parts = readXlsxBytes(
        _package(
          comments: _comments(_comment('A1', '<t>x</t>')),
          vml: '$_vmlHead${_vmlShape(0, 0)}</xml>',
        ),
      );
      const String element = '<legacyDrawing r:id="rId1"/>';
      parts['xl/worksheets/sheet1.xml'] = Uint8List.fromList(
        utf8.encode(
          utf8
              .decode(parts['xl/worksheets/sheet1.xml']!)
              .replaceFirst(element, '$element$element'),
        ),
      );
      final Uint8List input = buildZip(<String, List<int>>{...parts});
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => book.sheets.single.setNote(0, 0, null),
      );
      log.revertSet(set);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
    });

    test('malformed VML throws StateError', () {
      final Uint8List input = _package(
        comments: _comments(_comment('A1', '<t>x</t>')),
        vml: '$_vmlHead<v:shape><br></xml>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(() => sheet.setNote(1, 1, XlsxNote.plain('y')), throwsStateError);
      expect(() => sheet.setNote(0, 0, null), throwsStateError);
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a comments part that is not SpreadsheetML throws StateError', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(comments: '<comments xmlns="urn:other"/>'),
      );
      expect(
        () => book.sheets.single.setNote(0, 0, XlsxNote.plain('y')),
        throwsStateError,
      );
    });

    test('a bad note throws and nothing changes', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_package());
      final XlsxSheet sheet = book.sheets.single;
      expect(
        () => sheet.setNote(-1, 0, XlsxNote.plain('y')),
        throwsArgumentError,
      );
      expect(
        () =>
            sheet.setNote(0, 0, XlsxNote(XlsxRichText(const <XlsxTextRun>[]))),
        throwsArgumentError,
      );
      expect(() => sheet.setNote(0, 1 << 20, null), throwsRangeError);
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('text is repaired with the warnings of the writer', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_package());
      book.sheets.single.setNote(0, 0, XlsxNote.plain('a\u0001b'));
      expect(book.sheets.single.noteAt(0, 0)!.text.text, 'ab');
      expect(
        book.warnings.map((XlsxWarning w) => (w.code, w.cells.single)),
        contains((XlsxWarningCode.invalidCharactersRemoved, 'A1')),
      );
    });

    test('comments without VML get one with every note', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          comments: _comments(
            _comment('A1', '<t>x</t>') + _comment('B2', '<t>y</t>'),
          ),
        ),
      );
      book.sheets.single.setNote(2, 2, XlsxNote.plain('z', author: 'A'));
      final Uint8List saved = book.save().bytes;
      final String vml = _vml(saved);
      expect('<v:shape '.allMatches(vml), hasLength(3));
      expect(vml, contains('<x:Row>0</x:Row>'));
      expect(vml, contains('<x:Row>1</x:Row>'));
      expect(vml, contains('<x:Row>2</x:Row>'));
      expect(
        readXlsx(saved)['xl/worksheets/sheet1.xml'],
        contains('legacyDrawing'),
      );
      expect(XlsxWorkbook.open(saved).sheets.single.notes, hasLength(3));
    });

    test('a legacyDrawing naming no part gets a new VML', () {
      final Uint8List input = buildWorkbook(<String, String>{
        'S':
            '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>'
            '<legacyDrawing r:id="rId9"/></worksheet>',
      });
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single.setNote(0, 0, XlsxNote.plain('z'));
      final Uint8List saved = book.save().bytes;
      expect(
        'legacyDrawing r:id'.allMatches(
          readXlsx(saved)['xl/worksheets/sheet1.xml']!,
        ),
        hasLength(1),
      );
      expect(_vml(saved), contains('<x:Row>0</x:Row>'));
    });

    test(
      'a root that binds other prefixes gets a shape that declares them',
      () {
        final XlsxWorkbook book = XlsxWorkbook.open(
          _package(vml: '<xml xmlns:vv="urn:schemas-microsoft-com:vml"></xml>'),
        );
        final XlsxSheet sheet = book.sheets.single;
        sheet.setNote(0, 0, XlsxNote.plain('n', visible: true));
        final Uint8List saved = book.save().bytes;
        final String vml = _vml(saved);
        expect(vml, contains('<v:shape xmlns:v='));
        expect(vml, contains('data="1"'));
        expect(
          XlsxWorkbook.open(saved).sheets.single.noteAt(0, 0)!.visible,
          isTrue,
        );
      },
    );

    test('an empty VML root opens to take a shape', () {
      final Uint8List input = _package(vml: '<xml/>');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeSet set = changeLogOf(book).transaction(
        () => book.sheets.single.setNote(0, 0, XlsxNote.plain('n')),
      );
      expect(_vml(book.save().bytes), endsWith('</v:shape></xml>'));
      changeLogOf(book).revertSet(set);
      expect(_vml(book.save().bytes), '<xml/>');
    });

    test('equal set is no edit', () {
      final Uint8List input = _fixture('m4_notes');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      for (final XlsxCellNote n in sheet.notes) {
        sheet.setNote(n.row, n.column, n.note);
      }
      sheet.setNote(0, 0, null);
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
    });

    group('undo of add, replace and remove restores the file', () {
      void undone(Uint8List input, void Function(XlsxSheet sheet) edit) {
        final XlsxWorkbook book = XlsxWorkbook.open(input);
        final XlsxSheet sheet = book.sheets.first;
        final ChangeLog log = changeLogOf(book);
        final List<XlsxCellNote> before = sheet.notes;
        final ChangeSet set = log.transaction(() => edit(sheet));
        final List<XlsxCellNote> after = sheet.notes;
        final Uint8List edited = book.save().bytes;
        log.revertSet(set);
        expect(sheet.notes, before);
        expect(
          comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
        );
        log.reapplySet(set);
        expect(sheet.notes, after);
        expect(
          comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
        );
      }

      test('add on a sheet without notes', () {
        undone(_package(), (XlsxSheet s) {
          s.setNote(0, 0, XlsxNote.plain('a', author: 'A', visible: true));
          s.setNote(1, 0, XlsxNote.plain('b', author: 'B'));
        });
      });

      test('add on the fixture, a new author and block included', () {
        undone(_fixture('m4_notes'), (XlsxSheet s) {
          s.setNote(0, 0, XlsxNote.plain('a', author: 'New'));
        });
      });

      test('replace and visible', () {
        undone(_fixture('m4_notes'), (XlsxSheet s) {
          s.setNote(1, 1, XlsxNote.plain('r', author: 'Ahmet', visible: true));
          s.setNote(3, 3, XlsxNote.plain('r', author: 'Ayse Yilmaz'));
        });
      });

      test('remove one and all', () {
        undone(_fixture('m4_notes'), (XlsxSheet s) => s.setNote(1, 1, null));
        undone(_fixture('m4_notes'), (XlsxSheet s) {
          for (final XlsxCellNote n in s.notes) {
            s.setNote(n.row, n.column, null);
          }
        });
      });

      test('comments without VML', () {
        undone(
          _package(comments: _comments(_comment('A1', '<t>x</t>'))),
          (XlsxSheet s) => s.setNote(1, 1, XlsxNote.plain('y', author: 'A')),
        );
      });

      test('a failed transaction leaves nothing', () {
        final Uint8List input = _package();
        final XlsxWorkbook book = XlsxWorkbook.open(input);
        final XlsxSheet sheet = book.sheets.single;
        expect(
          () => changeLogOf(book).transaction(() {
            sheet.setNote(0, 0, XlsxNote.plain('a'));
            throw StateError('later');
          }),
          throwsStateError,
        );
        expect(sheet.notes, isEmpty);
        expect(
          comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
        );
      });
    });

    test('generates 10,000 notes in under 5 s', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_package());
      final XlsxSheet sheet = book.sheets.single;
      final Stopwatch watch = Stopwatch()..start();
      for (int i = 0; i < 10000; i++) {
        sheet.setNote(i, i % 10, XlsxNote.plain('Note $i', author: 'A'));
      }
      final Uint8List saved = book.save().bytes;
      watch.stop();
      printOnFailure('${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(XlsxWorkbook.open(saved).sheets.single.notes, hasLength(10000));
    });
  });

  group('the bytes of the note parts', () {
    final String comments =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<!-- after the declaration -->\n'
        '${_comments('\n  <!-- between -->\n  ${_comment('A1', '<t>x</t>')}\n')}';
    final String vml = '$_vmlHead\n<!-- kept -->\n${_vmlShape(0, 0)}\n</xml>\n';
    Uint8List input() => _package(comments: comments, vml: vml);
    void same(Uint8List a, Uint8List b) {
      for (final String part in <String>[
        'xl/comments1.xml',
        'xl/drawings/vmlDrawing1.vml',
      ]) {
        expect(readXlsxBytes(b)[part], readXlsxBytes(a)[part], reason: part);
      }
    }

    test('stay after a failed edit', () {
      final Uint8List bytes = input();
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      expect(
        () => changeLogOf(book).transaction(() {
          book.sheets.single.setNote(0, 0, XlsxNote.plain('new', author: 'A'));
          throw StateError('later');
        }),
        throwsStateError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      same(bytes, book.save().bytes);
    });

    test('come back on undo, of a removal too', () {
      for (final XlsxNote? note in <XlsxNote?>[
        XlsxNote.plain('new', author: 'A'),
        null,
      ]) {
        final Uint8List bytes = input();
        final XlsxWorkbook book = XlsxWorkbook.open(bytes);
        final ChangeLog log = changeLogOf(book);
        final XlsxSheet sheet = book.sheets.single;
        final ChangeSet set = log.transaction(() => sheet.setNote(0, 0, note));
        final Uint8List edited = book.save().bytes;
        log.revertSet(set);
        same(bytes, book.save().bytes);
        log.reapplySet(set);
        expect(
          comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
        );
      }
    });
  });

  test('a part name used again after a removal keeps later edits', () {
    final XlsxWorkbook made = XlsxWorkbook();
    made.addSheet('S').setNote(0, 0, XlsxNote.plain('First'));
    final XlsxWorkbook book = XlsxWorkbook.open(made.save().bytes);
    final XlsxSheet sheet = book.sheets.single;
    final ChangeLog log = changeLogOf(book);
    final ChangeSet removed = log.transaction(() => sheet.setNote(0, 0, null));
    final ChangeSet added = log.transaction(
      () => sheet.setNote(2, 2, XlsxNote.plain('Other')),
    );
    log.revertSet(added);
    log.revertSet(removed);
    sheet.setNote(1, 1, XlsxNote.plain('Later'));
    final XlsxSheet saved = XlsxWorkbook.open(book.save().bytes).sheets.single;
    expect(saved.notes.map((XlsxCellNote n) => n.note.text.text), <String>[
      'First',
      'Later',
    ]);
  });
}
