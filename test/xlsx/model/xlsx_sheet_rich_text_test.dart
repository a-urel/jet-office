import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

const XlsxFont _bold = XlsxFont(bold: true);

/// [font] as the writer stores a run's font: the name and size filled in
/// (Calibri 11), which the file spells out in each `<rPr>`.
XlsxFont _stored(XlsxFont font) =>
    font.copyWith(name: font.name ?? 'Calibri', size: font.size ?? 11);

/// [text] with each run's font stored as [_stored] does.
XlsxRichText _storedRuns(XlsxRichText text) => XlsxRichText(<XlsxTextRun>[
  for (final XlsxTextRun run in text.runs)
    XlsxTextRun(run.text, font: run.font == null ? null : _stored(run.font!)),
]);

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

/// A one-sheet workbook with [cells] in row 1 and the shared strings [si]
/// (raw `<si>` items).
Uint8List _book(String cells, {String si = ''}) => buildWorkbook(
  <String, String>{'S': worksheet('<row r="1">$cells</row>')},
  sharedStrings: si.isEmpty
      ? '<sst xmlns="$mainNs"/>'
      : '<sst xmlns="$mainNs" count="1" uniqueCount="1">$si</sst>',
);

int _invalid(XlsxWorkbook book) => book.warnings
    .where((XlsxWarning w) => w.code == XlsxWarningCode.featureEntryInvalid)
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

const String _phonetic =
    '<si><r><rPr><b/></rPr><t>Tokyo</t></r><r><t> city</t></r>'
    '<rPh sb="0" eb="5"><t>toukyou</t></rPh><phoneticPr fontId="1"/></si>';

void main() {
  test('text past the limit is cut and warned about, as in a string', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S')
      ..setCell(
        0,
        0,
        XlsxRichText(<XlsxTextRun>[
          XlsxTextRun('a' * 32760, font: _bold),
          XlsxTextRun('b' * 20),
        ]),
      );
    expect(sheet.richTextAt(0, 0)!.text, hasLength(32767));
    expect(
      book.warnings.map((XlsxWarning w) => w.code),
      contains(XlsxWarningCode.textTruncated),
    );
  });

  test('an inline rich string set back equal is no edit', () {
    final Uint8List input = _book(
      '<c r="A1" t="inlineStr"><is><r><rPr><b/></rPr><t>Bold</t></r>'
      '<r><t> plain</t></r></is></c><c r="B1" t="s"><v>0</v></c>',
      si: '<si><t>shared</t></si>',
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheets.single;
    final XlsxRichText read = sheet.richTextAt(0, 0)!;
    expect(read.text, 'Bold plain');
    sheet.setCell(0, 0, read);
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(
      comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  test('a rich text set drops calcChain, as any value', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      packageWith(
        rows: '<row r="1"><c r="A1"><f>1+1</f><v>2</v></c></row>',
        calcChain: true,
      ),
    );
    book.sheets.single.setCell(
      1,
      0,
      XlsxRichText(const <XlsxTextRun>[XlsxTextRun('x', font: _bold)]),
    );
    final Map<String, String> parts = readXlsx(book.save().bytes);
    expect(parts, isNot(contains('xl/calcChain.xml')));
    expect(parts['xl/workbook.xml'], contains('fullCalcOnLoad="1"'));
  });

  group('reading', () {
    test('reads runs of a shared string', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_rich_text'));
      final XlsxSheet sheet = book.sheets.first;
      expect(
        sheet.richTextAt(0, 0),
        _storedRuns(
          XlsxRichText(const <XlsxTextRun>[
            XlsxTextRun('Total: ', font: _bold),
            XlsxTextRun('42'),
          ]),
        ),
      );
      expect(
        sheet.richTextAt(1, 0),
        _storedRuns(
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
        ),
      );
      expect(
        sheet.richTextAt(2, 0),
        _storedRuns(
          XlsxRichText(const <XlsxTextRun>[
            XlsxTextRun('x'),
            XlsxTextRun(
              '2',
              font: XlsxFont(script: XlsxFontScript.superscript),
            ),
          ]),
        ),
      );
      expect(sheet.richTextAt(2, 0)!.text, 'x2');
      expect(book.warnings, isEmpty);
    });

    test('reads an inline rich string', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _book(
          '<c r="A1" t="inlineStr"><is><r><rPr><i/><rFont val="Arial"/>'
          '<sz val="9.5"/></rPr><t xml:space="preserve">a </t></r>'
          '<r><t>b_x0041_</t></r></is></c>',
        ),
      );
      expect(
        book.sheets.first.richTextAt(0, 0),
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun(
            'a ',
            font: XlsxFont(italic: true, name: 'Arial', size: 9.5),
          ),
          XlsxTextRun('bA'),
        ]),
      );
    });

    test('a plain cell reads null', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _book(
          '<c r="A1" t="s"><v>0</v></c><c r="B1"><v>1</v></c>'
          '<c r="C1" t="inlineStr"><is><t>x</t></is></c>'
          '<c r="D1" t="s"><v>9</v></c>',
          si: '<si><t>plain</t></si>',
        ),
      );
      final XlsxSheet sheet = book.sheets.first;
      for (int c = 0; c < 4; c++) {
        expect(sheet.richTextAt(0, c), isNull, reason: 'column $c');
      }
      expect(sheet.richTextAt(5, 5), isNull);
      expect(() => sheet.richTextAt(-1, 0), throwsRangeError);
    });

    test('a phonetic-only item reads null', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _book(
          '<c r="A1" t="s"><v>0</v></c>',
          si: '<si><t>abc</t><rPh sb="0" eb="1"><t>x</t></rPh></si>',
        ),
      );
      expect(book.sheets.first.richTextAt(0, 0), isNull);
      expect(book.sheets.first.cellAt(0, 0)?.value, 'abc');
    });

    test('a run with a bad size warns once', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _book(
          '<c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>0</v></c>',
          si:
              '<si><r><rPr><b/><sz val="abc"/></rPr><t>x</t></r>'
              '<r><t>y</t></r></si>',
        ),
      );
      final XlsxSheet sheet = book.sheets.first;
      final XlsxRichText? first = sheet.richTextAt(0, 0);
      expect(first!.runs.first.font, _bold);
      expect(first.runs.last.font, isNull);
      sheet.richTextAt(0, 0);
      sheet.richTextAt(0, 1);
      expect(_invalid(book), 1);
      final XlsxWarning warning = book.warnings.single;
      expect(warning.code, XlsxWarningCode.featureEntryInvalid);
      expect(warning.detail, 'rPr');
    });
  });

  group('setting', () {
    test('setCell round-trips through richTextAt', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      final XlsxRichText text = XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('Total: ', font: _bold),
        XlsxTextRun('42'),
      ]);
      sheet.setCell(2, 1, text);
      expect(sheet.richTextAt(2, 1), _storedRuns(text));
      expect(sheet.cellAt(2, 1)?.value, 'Total: 42');
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.sheets.first.richTextAt(2, 1), _storedRuns(text));
      expect(again.warnings, isEmpty);
      sheet.setCell(2, 1, 'plain');
      expect(sheet.richTextAt(2, 1), isNull);
    });

    test('an XlsxCell keeps its style', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(
        0,
        0,
        XlsxCell(
          XlsxRichText(const <XlsxTextRun>[
            XlsxTextRun('Bold', font: _bold),
            XlsxTextRun(' in Arial 14'),
          ]),
          style: const XlsxStyle(font: XlsxFont(name: 'Arial', size: 14)),
        ),
      );
      expect(sheet.styleAt(0, 0)?.font?.name, 'Arial');
      final XlsxRichText read = sheet.richTextAt(0, 0)!;
      expect(read.text, 'Bold in Arial 14');
      expect(read.runs.first.font?.bold, isTrue);
      expect(read.runs.first.font?.name, 'Arial');
      expect(read.runs.first.font?.size, 14);
      expect(read.runs.last.font?.name, 'Arial');
      expect(read.runs.last.font?.bold, isNull);
    });

    test('setting back what was read changes nothing', () {
      final Uint8List input = _book(
        '<c r="A1" t="s"><v>0</v></c>',
        si: _phonetic,
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      final XlsxRichText read = sheet.richTextAt(0, 0)!;
      expect(read.text, 'Tokyo city');
      sheet.setCell(0, 0, read);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
      expect(
        partText(book.save().bytes, 'xl/sharedStrings.xml'),
        contains('toukyou'),
      );
    });

    test('dirty text repairs as the writer', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(
        0,
        0,
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('a\u0001b', font: _bold),
          XlsxTextRun('c'),
        ]),
      );
      expect(sheet.richTextAt(0, 0)!.text, 'abc');
      final XlsxWarning warning = book.warnings.single;
      expect(warning.code, XlsxWarningCode.invalidCharactersRemoved);
      expect(warning.sheet, 'S');
      expect(warning.cells, <String>['A1']);
    });

    test('no runs throws and changes nothing', () {
      final Uint8List input = _book(
        '<c r="A1" t="s"><v>0</v></c>',
        si: '<si><t>a</t></si>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      expect(
        () => sheet.setCell(0, 0, XlsxRichText(const <XlsxTextRun>[])),
        throwsArgumentError,
      );
      expect(sheet.cellAt(0, 0)?.value, 'a');
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
    });

    test('a header cell refuses it', () {
      final XlsxWriter writer = XlsxWriter();
      final XlsxSheetWriter sheet = writer.addSheet('S');
      sheet.table(
        XlsxTable('Sales', XlsxRange.parse('A1:B2'), const <XlsxTableColumn>[
          XlsxTableColumn('Region'),
          XlsxTableColumn('Amount'),
        ]),
      );
      sheet.row(<Object?>[null, null]);
      sheet.row(<Object?>['North', 120]);
      final XlsxWorkbook book = XlsxWorkbook.open(writer.close().bytes);
      expect(
        () => book.sheets.first.setCell(
          0,
          0,
          XlsxRichText(const <XlsxTextRun>[XlsxTextRun('x', font: _bold)]),
        ),
        throwsStateError,
      );
    });

    test('undo restores the cell', () {
      final Uint8List input = _book(
        '<c r="A1" t="s"><v>0</v></c>',
        si: _phonetic,
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      final ChangeLog log = changeLogOf(book);
      final XlsxRichText before = sheet.richTextAt(0, 0)!;
      final XlsxRichText next = XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('new', font: _bold),
        XlsxTextRun(' text'),
      ]);
      final ChangeSet set = log.transaction(() => sheet.setCell(0, 0, next));
      expect(sheet.richTextAt(0, 0), _storedRuns(next));
      log.revertSet(set);
      // The string table keeps the entry the edit appended, as it does for
      // any string: the cell is what the undo restores.
      expect(sheet.richTextAt(0, 0), before);
      expect(sheet.cellAt(0, 0)?.value, 'Tokyo city');
      expect(
        comparePackages(
          input,
          book.save().bytes,
          ignoreBookkeeping: true,
        ).where((String line) => !line.startsWith('xl/sharedStrings.xml')),
        isEmpty,
      );
      log.reapplySet(set);
      expect(sheet.richTextAt(0, 0), _storedRuns(next));
    });
  });
}
