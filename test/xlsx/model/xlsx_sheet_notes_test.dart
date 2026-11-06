import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
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
Uint8List _package({String? comments, String? vml, bool legacy = true}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    buildWorkbook(<String, String>{
      'S':
          '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>'
          '${vml != null && legacy ? '<legacyDrawing r:id="rId1"/>' : ''}'
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
}
