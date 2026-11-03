import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/styles_part.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

const String _styles =
    '<styleSheet xmlns="$mainNs">'
    '<fonts><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders><border><left/><right/><top/><bottom/><diagonal/></border>'
    '</borders>'
    '<cellXfs><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyFont="1"/>'
    '</cellXfs></styleSheet>';

const XlsxStyle _bold = XlsxStyle(font: XlsxFont(bold: true));

const String _x14ac =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';

String _worksheet(String rows, {String sheetFormat = ''}) =>
    '<worksheet xmlns="$mainNs" xmlns:x14ac="$_x14ac">$sheetFormat'
    '<sheetData>$rows</sheetData></worksheet>';

XlsxWorkbook _open(String rows, {String sheetFormat = ''}) => XlsxWorkbook.open(
  buildWorkbook(<String, String>{
    'S': _worksheet(rows, sheetFormat: sheetFormat),
  }, styles: _styles),
);

String _sheetXml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

String _rowTag(String xml, int r) =>
    RegExp('<row r="$r"[^>]*>').firstMatch(xml)!.group(0)!;

List<XlsxWarning> _layoutWarnings(XlsxWorkbook book) => <XlsxWarning>[
  for (final XlsxWarning w in book.warnings)
    if (w.code == XlsxWarningCode.layoutInvalid) w,
];

void main() {
  test('rowFormat reads m2_columns_rows', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      allFixtures()
          .firstWhere((Fixture f) => f.name == 'm2_columns_rows')
          .build(),
    );
    final XlsxSheet sheet = book.sheets.first;
    expect(sheet.rowFormat(0), const XlsxRowFormat());
    expect(sheet.rowFormat(1), const XlsxRowFormat(height: 30));
    expect(sheet.rowFormat(2), const XlsxRowFormat(height: 5));
    expect(sheet.rowFormat(3), const XlsxRowFormat(hidden: true));
    expect(
      sheet.rowFormat(4),
      const XlsxRowFormat(hidden: true, outlineLevel: 2),
    );
    expect(
      sheet.rowFormat(6),
      const XlsxRowFormat(hidden: true, outlineLevel: 1),
    );
    expect(sheet.rowFormat(7), const XlsxRowFormat(collapsed: true));
    // A row the file lacks.
    expect(sheet.rowFormat(40), const XlsxRowFormat());
    expect(() => sheet.rowFormat(-1), throwsRangeError);
    expect(book.warnings, isEmpty);
  });

  test('rowFormat reads the style of a customFormat row', () {
    final XlsxWorkbook book = _open(
      '<row r="1" s="1" customFormat="1"/>'
      '<row r="2" s="1"/>'
      '<row r="3" s="0" customFormat="1"/>'
      '<row r="4" s="9" customFormat="1"/>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.rowFormat(0).style?.font?.bold, isTrue);
    expect(sheet.rowFormat(1).style, isNull);
    expect(sheet.rowFormat(2).style, isNull);
    expect(sheet.rowFormat(3).style, isNull);
  });

  test('an ht without customHeight is no height', () {
    final XlsxSheet sheet = _open('<row r="1" ht="20"/>').sheets.single;
    expect(sheet.rowFormat(0), const XlsxRowFormat());
  });

  test('setRowFormat writes what the writer writes', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('S').blankRow(height: 24, outlineLevel: 1);
    final String expected = _rowTag(
      partText(writer.close().bytes, 'xl/worksheets/sheet1.xml'),
      1,
    );

    final XlsxWorkbook book = XlsxWorkbook();
    book
        .addSheet('S')
        .setRowFormat(0, const XlsxRowFormat(height: 24, outlineLevel: 1));
    final String xml = _sheetXml(book);
    expect(_rowTag(xml, 1), expected);
    expect(xml, contains('outlineLevelRow="1"'));
    expect(xml, contains('<sheetFormatPr defaultRowHeight="15" '));
    // sheetFormatPr comes before sheetData.
    expect(xml.indexOf('<sheetFormatPr'), lessThan(xml.indexOf('<sheetData')));
    expect(
      XlsxWorkbook.open(book.save().bytes).sheets.single.rowFormat(0),
      const XlsxRowFormat(height: 24, outlineLevel: 1),
    );
  });

  test('every field round trips, in the writer attribute order', () {
    final XlsxWorkbook book = _open('<row r="1"><c r="A1"><v>1</v></c></row>');
    final XlsxSheet sheet = book.sheets.single;
    const XlsxRowFormat format = XlsxRowFormat(
      height: 12.5,
      hidden: true,
      outlineLevel: 3,
      collapsed: true,
      style: _bold,
    );
    sheet.setRowFormat(0, format);
    void expectFormat(XlsxRowFormat read) {
      expect(read.height, 12.5);
      expect(read.hidden, isTrue);
      expect(read.outlineLevel, 3);
      expect(read.collapsed, isTrue);
      expect(read.style?.font?.bold, isTrue);
    }

    expectFormat(sheet.rowFormat(0));
    final String xml = _sheetXml(book);
    expect(
      _rowTag(xml, 1),
      '<row r="1" spans="1:1" s="1" customFormat="1" ht="12.5" hidden="1" '
      'customHeight="1" outlineLevel="3" collapsed="1">',
    );
    expectFormat(
      XlsxWorkbook.open(book.save().bytes).sheets.single.rowFormat(0),
    );
    // The cell stays.
    expect(sheet.cellAt(0, 0)?.value, XlsxDecimal('1'));
  });

  test('a styled row layers under a later setCell like the writer', () {
    final XlsxWorkbook book = _open('');
    final XlsxSheet sheet = book.sheets.single
      ..setRowFormat(0, const XlsxRowFormat(style: _bold))
      ..setCell(
        0,
        0,
        const XlsxCell(7, style: XlsxStyle(font: XlsxFont(italic: true))),
      );
    expect(sheet.styleAt(0, 0)?.font?.bold, isTrue);
    expect(sheet.styleAt(0, 0)?.font?.italic, isTrue);
  });

  test('unknown row attributes are kept', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': _worksheet(
          '<row r="1" ht="30" customHeight="1" x14ac:dyDescent="0.25" '
          'thickBot="1"><c r="A1"><v>1</v></c></row>',
        ),
      }, styles: _styles),
    );
    final XlsxSheet sheet = book.sheets.single
      ..setRowFormat(0, const XlsxRowFormat(height: 40, hidden: true));
    final String tag = _rowTag(_sheetXml(book), 1);
    expect(tag, contains('x14ac:dyDescent="0.25"'));
    expect(tag, contains('thickBot="1"'));
    expect(tag, contains('ht="40"'));
    expect(tag, contains('hidden="1"'));
    expect(tag, isNot(contains('ht="30"')));
    expect(sheet.rowFormat(0), const XlsxRowFormat(height: 40, hidden: true));
    // The height was replaced where it stood.
    expect(tag.indexOf('ht='), lessThan(tag.indexOf('x14ac:dyDescent')));
  });

  test('a row reset to the default and without cells is removed', () {
    final XlsxWorkbook book = _open(
      '<row r="1" ht="30" customHeight="1" hidden="1"/>'
      '<row r="2" ht="30" customHeight="1"><c r="A2"><v>1</v></c></row>'
      '<row r="3" ht="30" customHeight="1" thickBot="1"/>',
    );
    final XlsxSheet sheet = book.sheets.single
      ..setRowFormat(0, const XlsxRowFormat())
      ..setRowFormat(1, const XlsxRowFormat())
      ..setRowFormat(2, const XlsxRowFormat());
    final String xml = _sheetXml(book);
    expect(xml, isNot(contains('<row r="1"')));
    expect(_rowTag(xml, 2), '<row r="2" spans="1:1">');
    // Another attribute keeps the row.
    expect(_rowTag(xml, 3), '<row r="3" thickBot="1"/>');
    expect(sheet.rowFormat(0), const XlsxRowFormat());
  });

  test(
    'setRowFormat on a row that does not exist and is default does nothing',
    () {
      final XlsxWorkbook book = _open('');
      book.sheets.single.setRowFormat(4, const XlsxRowFormat());
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_sheetXml(book), isNot(contains('<row')));
    },
  );

  test('a bad ht warns layoutInvalid and stays as written', () {
    final XlsxWorkbook book = _open(
      '<row r="1" ht="abc" customHeight="1" hidden="2" outlineLevel="9" '
      'collapsed="x"><c r="A1"><v>1</v></c></row>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.rowFormat(0), const XlsxRowFormat());
    expect(sheet.rowFormat(0), const XlsxRowFormat());
    final List<XlsxWarning> warnings = _layoutWarnings(book);
    // One warning per attribute, each once however often the row is read.
    expect(warnings.map((XlsxWarning w) => w.detail), <String?>[
      'row 1: hidden "2" is not a boolean.',
      'row 1: outlineLevel "9" is not an outline level from 0 to 7.',
      'row 1: collapsed "x" is not a boolean.',
      'row 1: ht "abc" is not a row height.',
    ]);
    for (final XlsxWarning w in warnings) {
      expect(w.count, 1);
      expect(w.sheet, 'S');
    }
    // An edit of another field keeps the attributes as written.
    sheet.setRowFormat(0, const XlsxRowFormat(style: _bold));
    final String tag = _rowTag(_sheetXml(book), 1);
    expect(tag, contains('ht="abc"'));
    expect(tag, contains('hidden="2"'));
    expect(tag, contains('outlineLevel="9"'));
    expect(tag, contains('collapsed="x"'));
    expect(_layoutWarnings(book), hasLength(4));
    // Setting the field replaces it.
    sheet.setRowFormat(0, const XlsxRowFormat(height: 20, style: _bold));
    expect(_rowTag(_sheetXml(book), 1), contains('ht="20"'));
  });

  test(
    'an invalid height throws ArgumentError named height; nothing changes',
    () {
      final XlsxWorkbook book = _open('<row r="1" ht="30" customHeight="1"/>');
      final XlsxSheet sheet = book.sheets.single;
      for (final double bad in <double>[-1, 410, double.nan, double.infinity]) {
        expect(
          () => sheet.setRowFormat(0, XlsxRowFormat(height: bad)),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'height',
            ),
          ),
        );
      }
      expect(
        () => sheet.setRowFormat(0, const XlsxRowFormat(outlineLevel: 8)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'outlineLevel',
          ),
        ),
      );
      expect(
        () => sheet.setRowFormat(0, const XlsxRowFormat(outlineLevel: -1)),
        throwsArgumentError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(sheet.rowFormat(0), const XlsxRowFormat(height: 30));
      expect(cellStoreOf(sheet)!.rowAttributes(0).map((a) => a.value), <String>[
        '30',
        '1',
      ]);
      expect(
        () => sheet.setRowFormat(-1, const XlsxRowFormat()),
        throwsRangeError,
      );
    },
  );

  test('a style that fails to append changes nothing', () {
    final XlsxWorkbook book = _open('<row r="1" ht="30" customHeight="1"/>');
    final XlsxSheet sheet = book.sheets.single;
    expect(
      () => sheet.setRowFormat(
        0,
        const XlsxRowFormat(
          height: 40,
          style: XlsxStyle(font: XlsxFont(size: -3)),
        ),
      ),
      throwsArgumentError,
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(sheet.rowFormat(0), const XlsxRowFormat(height: 30));
  });

  test('a row style appends to the styles; an equal one keeps its index', () {
    final XlsxWorkbook book = _open('<row r="1" s="1" customFormat="1"/>');
    final XlsxSheet sheet = book.sheets.single..rowFormat(0);
    final StylesPart styles = stylesPartOf(book)!;
    final StylesMark before = styles.mark();
    // The style read back is the style set: nothing changes.
    sheet.setRowFormat(0, XlsxRowFormat(style: sheet.rowFormat(0).style));
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(styles.mark(), before);
    // A new style is appended after the existing ones.
    sheet.setRowFormat(
      0,
      const XlsxRowFormat(style: XlsxStyle(font: XlsxFont(italic: true))),
    );
    expect(styles.mark(), isNot(before));
    expect(cellStoreOf(sheet)!.rowAttributes(0).map((a) => a.value), <String>[
      '2',
      '1',
    ]);
    // A default style gives no s.
    sheet.setRowFormat(0, const XlsxRowFormat(style: XlsxStyle()));
    expect(cellStoreOf(sheet)!.rowAttributes(0), isEmpty);
  });

  test(
    'a workbook without styles gets the made part only when appended to',
    () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S')
        ..setRowFormat(0, const XlsxRowFormat(height: 20));
      expect(
        partText(book.save().bytes, 'xl/styles.xml'),
        isNot(contains('<b/>')),
      );
      sheet.setRowFormat(1, const XlsxRowFormat(style: _bold));
      expect(partText(book.save().bytes, 'xl/styles.xml'), contains('<b/>'));
      expect(sheet.rowFormat(1).style?.font?.bold, isTrue);
    },
  );

  test('setRowFormat is undone and redone with the change log', () {
    final XlsxWorkbook book = _open('<row r="1" ht="30" customHeight="1"/>');
    final XlsxSheet sheet = book.sheets.single;
    final ChangeLog log = changeLogOf(book);
    final ChangeSet set = log.transaction(() {
      sheet
        ..setRowFormat(0, const XlsxRowFormat(hidden: true, style: _bold))
        ..setRowFormat(5, const XlsxRowFormat(outlineLevel: 2));
    });
    expect(sheet.rowFormat(5), const XlsxRowFormat(outlineLevel: 2));
    log.revertSet(set);
    expect(sheet.rowFormat(0), const XlsxRowFormat(height: 30));
    expect(sheet.rowFormat(5), const XlsxRowFormat());
    expect(cellStoreOf(sheet)!.rowIndexes, <int>[0]);
    log.reapplySet(set);
    expect(sheet.rowFormat(5), const XlsxRowFormat(outlineLevel: 2));
    expect(sheet.rowFormat(0).hidden, isTrue);
  });

  group('outlineLevelRow', () {
    test('an edit raises the kept value; an unchanged file keeps it', () {
      final XlsxWorkbook book = _open(
        '<row r="1" outlineLevel="1"/>',
        sheetFormat:
            '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="5" '
            'outlineLevelCol="2"/>',
      );
      expect(_sheetXml(book), contains('outlineLevelRow="5"'));
      book.sheets.single.setRowFormat(0, const XlsxRowFormat(outlineLevel: 7));
      final String xml = _sheetXml(book);
      expect(
        xml,
        contains(
          '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="7" '
          'outlineLevelCol="2"/>',
        ),
      );
    });

    test('a lower level leaves the kept value', () {
      final XlsxWorkbook book = _open(
        '<row r="1"/>',
        sheetFormat:
            '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="3"/>',
      );
      book.sheets.single.setRowFormat(0, const XlsxRowFormat(outlineLevel: 2));
      expect(_sheetXml(book), contains('outlineLevelRow="3"'));
    });

    test('no sheetFormatPr is made while no row is outlined', () {
      final XlsxWorkbook book = _open('<row r="1"/>');
      book.sheets.single.setRowFormat(0, const XlsxRowFormat(height: 20));
      expect(_sheetXml(book), isNot(contains('sheetFormatPr')));
    });

    test('a sheetFormatPr with another attribute order keeps the rest', () {
      final XlsxWorkbook book = _open(
        '<row r="1"/>',
        sheetFormat:
            '<sheetFormatPr baseColWidth="10" defaultRowHeight="15" '
            'x14ac:dyDescent="0.25"/>',
      );
      book.sheets.single.setRowFormat(0, const XlsxRowFormat(outlineLevel: 1));
      final String xml = _sheetXml(book);
      expect(xml, contains('baseColWidth="10"'));
      expect(xml, contains('outlineLevelRow="1"'));
    });
    test('a sheetFormatPr with end tag or children is never duplicated', () {
      for (final String format in <String>[
        '<sheetFormatPr defaultRowHeight="15"></sheetFormatPr>',
        '<sheetFormatPr defaultRowHeight="15"><extLst/></sheetFormatPr>',
      ]) {
        final XlsxWorkbook book = _open(
          '<row r="1" outlineLevel="2"/>',
          sheetFormat: format,
        );
        book.sheets.single.rowFormat(0); // load: a loaded part is rewritten
        final String xml = _sheetXml(book);
        expect(
          RegExp('<sheetFormatPr').allMatches(xml),
          hasLength(1),
          reason: format,
        );
        book.sheets.single.setRowFormat(
          0,
          const XlsxRowFormat(outlineLevel: 3),
        );
        expect(
          RegExp('<sheetFormatPr').allMatches(_sheetXml(book)),
          hasLength(1),
          reason: format,
        );
      }
      // An end-tag element without children is typed and bookkept.
      final XlsxWorkbook book = _open(
        '<row r="1" outlineLevel="2"/>',
        sheetFormat: '<sheetFormatPr defaultRowHeight="15"></sheetFormatPr>',
      );
      book.sheets.single.rowFormat(0);
      expect(_sheetXml(book), contains('outlineLevelRow="2"'));
    });

    test('an unchanged sheetFormatPr is saved exactly', () {
      const String format =
          '<sheetFormatPr baseColWidth="10" defaultRowHeight="15" '
          'thickBottom="1" x14ac:dyDescent="0.25"/>';
      final XlsxWorkbook book = _open('<row r="1"/>', sheetFormat: format);
      book.sheets.single.rowFormat(0);
      expect(_sheetXml(book), contains(format));
    });
  });

  test('setting every row to the format it reads changes nothing', () {
    final XlsxWorkbook layout = XlsxWorkbook.open(
      allFixtures()
          .firstWhere((Fixture f) => f.name == 'm2_columns_rows')
          .build(),
    );
    final XlsxWorkbook bad = _open(
      '<row r="1" ht="abc" customHeight="1" hidden="2" outlineLevel="9" '
      'collapsed="x"><c r="A1"><v>1</v></c></row>',
    );
    for (final XlsxWorkbook book in <XlsxWorkbook>[layout, bad]) {
      final XlsxSheet sheet = book.sheets.first..rowFormat(0);
      final String before = _sheetXml(book);
      for (int r = 0; r < 10; r++) {
        sheet.setRowFormat(r, sheet.rowFormat(r));
      }
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_sheetXml(book), before);
    }
  });
}
