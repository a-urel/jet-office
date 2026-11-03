import 'dart:typed_data';

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

/// The styles of the column tests: plain (0), bold (1), italic (2) and a
/// bold one with `quotePrefix`, which the value types cannot hold (3).
const String _columnStyles =
    '<styleSheet xmlns="$mainNs">'
    '<fonts><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '<font><i/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders><border><left/><right/><top/><bottom/><diagonal/></border>'
    '</borders>'
    '<cellXfs><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyFont="1" '
    'quotePrefix="1"/>'
    '</cellXfs></styleSheet>';

const XlsxStyle _bold = XlsxStyle(font: XlsxFont(bold: true));
const XlsxStyle _italic = XlsxStyle(font: XlsxFont(italic: true));

const String _x14ac =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';

String _worksheet(String rows, {String sheetFormat = '', String cols = ''}) =>
    '<worksheet xmlns="$mainNs" xmlns:x14ac="$_x14ac">$sheetFormat$cols'
    '<sheetData>$rows</sheetData></worksheet>';

XlsxWorkbook _open(
  String rows, {
  String sheetFormat = '',
  String cols = '',
  String styles = _styles,
}) => XlsxWorkbook.open(
  buildWorkbook(<String, String>{
    'S': _worksheet(rows, sheetFormat: sheetFormat, cols: cols),
  }, styles: styles),
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

    test('an unchanged file with outlined rows gets no sheetFormatPr', () {
      final XlsxWorkbook book = _open(
        '<row r="1" outlineLevel="2"><c r="A1"><v>1</v></c></row>',
      );
      book.sheets.single.rows.toList();
      expect(_sheetXml(book), isNot(contains('sheetFormatPr')));
    });

    test('sheetFormatPr is made only when an edit goes deeper', () {
      final XlsxWorkbook book = _open('<row r="1" outlineLevel="2"/>');
      final XlsxSheet sheet = book.sheets.single;
      // A level the file has, and a lower one: nothing is needed.
      sheet.setRowFormat(1, const XlsxRowFormat(outlineLevel: 2));
      sheet.setRowFormat(2, const XlsxRowFormat(outlineLevel: 1));
      expect(_sheetXml(book), isNot(contains('sheetFormatPr')));
      final ChangeLog log = changeLogOf(book);
      final ChangeSet deeper = log.transaction(() {
        sheet.setRowFormat(3, const XlsxRowFormat(outlineLevel: 3));
      });
      expect(
        _sheetXml(book),
        contains('<sheetFormatPr defaultRowHeight="15" outlineLevelRow="3"/>'),
      );
      // Undone, the sheet is back at the file's level.
      log.revertSet(deeper);
      expect(_sheetXml(book), isNot(contains('sheetFormatPr')));
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
      // An end-tag element without children is typed: unchanged it stays
      // as it was, and an edit that goes deeper is bookkept.
      final XlsxWorkbook book = _open(
        '<row r="1" outlineLevel="2"/>',
        sheetFormat: '<sheetFormatPr defaultRowHeight="15"></sheetFormatPr>',
      );
      book.sheets.single.rowFormat(0);
      expect(_sheetXml(book), isNot(contains('outlineLevelRow')));
      book.sheets.single.setRowFormat(1, const XlsxRowFormat(outlineLevel: 3));
      expect(_sheetXml(book), contains('outlineLevelRow="3"'));
    });

    test('a kept value below the rows stays until an edit goes deeper', () {
      final XlsxWorkbook book = _open(
        '<row r="1" outlineLevel="3"/>',
        sheetFormat:
            '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="1"/>',
      );
      final XlsxSheet sheet = book.sheets.single..rowFormat(0);
      expect(_sheetXml(book), contains('outlineLevelRow="1"'));
      // No deeper than the file's rows: the value stays.
      sheet.setRowFormat(1, const XlsxRowFormat(outlineLevel: 3));
      expect(_sheetXml(book), contains('outlineLevelRow="1"'));
      final ChangeLog log = changeLogOf(book);
      final ChangeSet deeper = log.transaction(() {
        sheet.setRowFormat(2, const XlsxRowFormat(outlineLevel: 4));
      });
      expect(_sheetXml(book), contains('outlineLevelRow="4"'));
      log.revertSet(deeper);
      expect(_sheetXml(book), contains('outlineLevelRow="1"'));
    });

    test('a kept column value below the columns stays likewise', () {
      final XlsxWorkbook book = _open(
        '',
        sheetFormat:
            '<sheetFormatPr defaultRowHeight="15" outlineLevelCol="1"/>',
        cols: '<cols><col min="1" max="1" width="9" outlineLevel="3"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single..column(0);
      expect(_sheetXml(book), contains('outlineLevelCol="1"'));
      sheet.setColumn(1, const XlsxColumn(outlineLevel: 3));
      expect(_sheetXml(book), contains('outlineLevelCol="1"'));
      sheet.setColumn(1, const XlsxColumn(outlineLevel: 4));
      expect(_sheetXml(book), contains('outlineLevelCol="4"'));
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

  group('columns', () {
    String formatOf(String xml) =>
        RegExp('<sheetFormatPr[^>]*>').firstMatch(xml)?.group(0) ?? '';

    String colsOf(String xml) =>
        RegExp('<cols(/>|>.*?</cols>)').firstMatch(xml)?.group(0) ?? '';

    XlsxWorkbook openColumns(String cols, {String rows = ''}) =>
        _open(rows, cols: cols, styles: _columnStyles);

    XlsxWorkbook fixture(String name) => XlsxWorkbook.open(
      allFixtures().firstWhere((Fixture f) => f.name == name).build(),
    );

    test('column reads widths, styles, hidden and outline', () {
      final XlsxWorkbook book = fixture('m2_columns_rows');
      final XlsxSheet sheet = book.sheets.first;
      expect(sheet.column(0), const XlsxColumn(width: 5));
      expect(sheet.column(1), const XlsxColumn(width: 12));
      expect(sheet.column(2), const XlsxColumn(width: 40));
      expect(sheet.column(3), const XlsxColumn(width: 255));
      // The width is read whenever it parses, customWidth or not: the
      // writer writes the default width for a column without its own.
      expect(sheet.column(4), const XlsxColumn(width: 9.140625, hidden: true));
      expect(
        sheet.column(5),
        const XlsxColumn(width: 9.140625, outlineLevel: 1),
      );
      expect(
        sheet.column(6),
        const XlsxColumn(width: 9.140625, outlineLevel: 2),
      );
      expect(
        sheet.column(7),
        const XlsxColumn(width: 9.140625, outlineLevel: 2),
      );
      expect(sheet.column(8), isNull);
      expect(() => sheet.column(-1), throwsRangeError);
      expect(() => sheet.column(16384), throwsRangeError);
      expect(book.warnings, isEmpty);

      final XlsxSheet styled = fixture('m2_style_precedence').sheets.first;
      expect(styled.column(0), isNull);
      expect(styled.column(1)?.width, 14);
      expect(styled.column(1)?.style?.numFmt, isNotNull);
      expect(styled.column(2)?.width, 12);

      final XlsxWorkbook book2 = openColumns(
        '<cols><col min="1" max="2" width="9" style="1" collapsed="1" '
        'hidden="true" customWidth="1"/>'
        '<col min="3" max="3" width="9.140625" style="9"/></cols>',
      );
      final XlsxColumn? read = book2.sheets.single.column(1);
      expect(
        read,
        XlsxColumn(
          width: 9,
          style: stylesPartOf(book2)!.styleOf(1),
          hidden: true,
          collapsed: true,
        ),
      );
      expect(read?.style?.font?.bold, isTrue);
      // A style index with no cell format reads as no style.
      expect(book2.sheets.single.column(2), const XlsxColumn(width: 9.140625));
    });

    test('an unreadable column attribute reads as default and warns once', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="1" width="abc" customWidth="1" hidden="2" '
        'outlineLevel="9" collapsed="x" style="y"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.column(0), isNull);
      expect(sheet.column(0), isNull);
      expect(_layoutWarnings(book), hasLength(5));
      final String before = _sheetXml(book);
      expect(before, contains('width="abc"'));
      sheet.setColumn(0, const XlsxColumn(width: 7));
      final String after = colsOf(_sheetXml(book));
      expect(after, contains('width="7"'));
      expect(after, contains('hidden="2"'));
    });

    test('setting one column of a range splits it', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="2" max="10" width="20" customWidth="1" '
        'bestFit="1"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.column(4), const XlsxColumn(width: 20));
      sheet.setColumn(4, const XlsxColumn(width: 20, hidden: true));
      expect(
        colsOf(_sheetXml(book)),
        '<cols><col min="2" max="4" width="20" customWidth="1" '
        'bestFit="1"/>'
        '<col min="5" max="5" width="20" customWidth="1" bestFit="1" '
        'hidden="1"/>'
        '<col min="6" max="10" width="20" customWidth="1" bestFit="1"/>'
        '</cols>',
      );
      expect(sheet.column(3), const XlsxColumn(width: 20));
      expect(sheet.column(4), const XlsxColumn(width: 20, hidden: true));
      expect(sheet.column(5), const XlsxColumn(width: 20));
      // Putting it back joins the runs again.
      sheet.setColumn(4, const XlsxColumn(width: 20));
      expect(
        colsOf(_sheetXml(book)),
        '<cols><col min="2" max="10" width="20" customWidth="1" '
        'bestFit="1"/></cols>',
      );
    });

    test('the second column of a range splits off a single column', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="2" max="10" width="20" customWidth="1" '
        'bestFit="1"/></cols>',
      );
      book.sheets.single.setColumn(2, const XlsxColumn(width: 21));
      expect(
        colsOf(_sheetXml(book)),
        '<cols><col min="2" max="2" width="20" customWidth="1" bestFit="1"/>'
        '<col min="3" max="3" width="21" customWidth="1" bestFit="1"/>'
        '<col min="4" max="10" width="20" customWidth="1" bestFit="1"/>'
        '</cols>',
      );
    });

    test('the edge columns of a range split into two runs', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="3" width="10" customWidth="1"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single
        ..setColumn(0, const XlsxColumn(width: 11))
        ..setColumn(2, null);
      expect(
        colsOf(_sheetXml(book)),
        '<cols><col min="1" max="1" width="11" customWidth="1"/>'
        '<col min="2" max="2" width="10" customWidth="1"/></cols>',
      );
      expect(sheet.column(2), isNull);
    });

    test('resetting the last column removes cols', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="2" max="2" width="10" customWidth="1"/></cols>',
      );
      book.sheets.single.setColumn(1, null);
      expect(_sheetXml(book), isNot(contains('<cols')));
      book.sheets.single.setColumn(1, const XlsxColumn(hidden: true));
      expect(
        colsOf(_sheetXml(book)),
        '<cols><col min="2" max="2" width="9.140625" hidden="1"/></cols>',
      );
    });

    test('a width reset to the default writes the default, not custom', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="1" width="30" customWidth="1" '
        'hidden="1"/></cols>',
      );
      book.sheets.single.setColumn(0, const XlsxColumn(hidden: true));
      expect(
        colsOf(_sheetXml(book)),
        '<cols><col min="1" max="1" width="9.140625" hidden="1"/></cols>',
      );
    });

    test('setColumn on a sheet without cols creates it in schema order', () {
      for (final (String before, String order) in <(String, String)>[
        ('<sheetFormatPr defaultRowHeight="15"/>', 'sheetFormatPr'),
        ('', 'sheetViews'),
      ]) {
        final XlsxWorkbook book = XlsxWorkbook.open(
          buildWorkbook(<String, String>{
            'S':
                '<worksheet xmlns="$mainNs"><sheetViews><sheetView '
                'workbookViewId="0"/></sheetViews>$before'
                '<sheetData/><pageMargins left="1" right="1" top="1" '
                'bottom="1" header="0" footer="0"/></worksheet>',
          }, styles: _columnStyles),
        );
        book.sheets.single.setColumn(2, const XlsxColumn(width: 18));
        final String xml = _sheetXml(book);
        expect(xml, contains('<cols><col min="3" max="3" width="18" '));
        expect(xml.indexOf('<$order'), lessThan(xml.indexOf('<cols>')));
        expect(xml.indexOf('<cols>'), lessThan(xml.indexOf('<sheetData')));
        expect(
          xml.indexOf('<sheetData'),
          lessThan(xml.indexOf('<pageMargins')),
        );
      }
    });

    test('new columns write what the writer writes', () {
      const List<XlsxColumn?> columns = <XlsxColumn?>[
        XlsxColumn(width: 12),
        null,
        XlsxColumn(hidden: true),
        XlsxColumn(hidden: true),
        XlsxColumn(width: 30, outlineLevel: 2, collapsed: true),
        XlsxColumn(style: _bold),
        XlsxColumn(width: 255, style: _bold, hidden: true, outlineLevel: 7),
      ];
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('S').columns(columns);
      final Uint8List written = writer.close().bytes;
      final String expected = partText(written, 'xl/worksheets/sheet1.xml');
      final XlsxSheet other = XlsxWorkbook.open(written).sheets.single;

      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      for (int i = 0; i < columns.length; i++) {
        sheet.setColumn(i, columns[i]);
      }
      final String xml = _sheetXml(book);
      expect(colsOf(xml), colsOf(expected));
      expect(colsOf(xml), isNotEmpty);
      expect(
        RegExp('<sheetFormatPr[^>]*>').firstMatch(xml)?.group(0),
        RegExp('<sheetFormatPr[^>]*>').firstMatch(expected)?.group(0),
      );
      final XlsxWorkbook reopened = XlsxWorkbook.open(book.save().bytes);
      for (int i = 0; i < columns.length; i++) {
        expect(
          reopened.sheets.single.column(i),
          other.column(i),
          reason: 'column $i',
        );
      }
    });

    test('outlineLevelCol is the larger of the kept and the deepest', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="1" width="9" outlineLevel="1"/></cols>',
      );
      book.sheets.single.setColumn(1, const XlsxColumn(outlineLevel: 3));
      expect(
        _sheetXml(book),
        contains('<sheetFormatPr defaultRowHeight="15" '),
      );
      expect(_sheetXml(book), contains('outlineLevelCol="3"'));
      final XlsxWorkbook kept = _open(
        '',
        sheetFormat:
            '<sheetFormatPr defaultRowHeight="15" outlineLevelCol="5"/>',
        cols: '<cols><col min="1" max="1" width="9" outlineLevel="1"/></cols>',
      );
      kept.sheets.single.setColumn(1, const XlsxColumn(outlineLevel: 2));
      expect(_sheetXml(kept), contains('outlineLevelCol="5"'));
      // A loaded sheet whose column is outlined stays without the element
      // until an edit goes deeper than the file did.
      final XlsxWorkbook loaded = openColumns(
        '<cols><col min="1" max="1" width="9" outlineLevel="1"/></cols>',
      )..sheets.single.column(0);
      expect(formatOf(_sheetXml(loaded)), isEmpty);
      loaded.sheets.single.setColumn(1, const XlsxColumn(outlineLevel: 1));
      expect(formatOf(_sheetXml(loaded)), isEmpty);
      loaded.sheets.single.setColumn(1, const XlsxColumn(outlineLevel: 2));
      expect(
        formatOf(_sheetXml(loaded)),
        '<sheetFormatPr defaultRowHeight="15" outlineLevelCol="2"/>',
      );
    });

    test('an equal setColumn records no change', () {
      final XlsxWorkbook book = openColumns('');
      final XlsxSheet sheet = book.sheets.single;
      sheet.setColumn(2, const XlsxColumn(hidden: true));
      final String before = _sheetXml(book);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        sheet.setColumn(2, const XlsxColumn(hidden: true));
      });
      expect(set.isEmpty, isTrue);
      expect(_sheetXml(book), before);
      // The middle of a run writes the same <col>s too.
      final XlsxWorkbook run = openColumns(
        '<cols><col min="2" max="4" width="20" customWidth="1"/></cols>',
      );
      final ChangeSet middle = changeLogOf(run).transaction(() {
        run.sheets.single.setColumn(2, const XlsxColumn(width: 20));
      });
      expect(middle.isEmpty, isTrue);
      // A different column still is a change.
      final ChangeSet other = log.transaction(() {
        sheet.setColumn(2, const XlsxColumn(width: 30));
      });
      expect(other.isEmpty, isFalse);
    });

    test('a cols that is not plain is kept and cannot be edited', () {
      for (final String cols in <String>[
        '<cols><col min="3" max="4" width="9"/><col min="1" max="1" '
            'width="9"/></cols>',
        '<cols><col min="1" max="3" width="9"/><col min="3" max="4" '
            'width="9"/></cols>',
        '<cols><col min="0" max="3" width="9"/></cols>',
        '<cols><col min="1" max="17000" width="9"/></cols>',
        '<cols><col min="a" max="3" width="9"/></cols>',
        '<cols><col min="1" max="3" width="9"><x/></col></cols>',
        '<cols><x:col xmlns:x="urn:x" min="1" max="3"/></cols>',
        '<cols/>',
      ]) {
        final XlsxWorkbook book = openColumns(cols);
        final XlsxSheet sheet = book.sheets.single;
        expect(sheet.column(0), isNull, reason: cols);
        expect(
          () => sheet.setColumn(5, const XlsxColumn(width: 5)),
          throwsStateError,
          reason: cols,
        );
        expect(changeLogOf(book).hasChanges, isFalse);
        expect(colsOf(_sheetXml(book)), cols);
      }
    });

    test('only the first cols is typed', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="1" width="9" customWidth="1"/></cols>'
        '<cols><col min="2" max="2" width="9" customWidth="1"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.column(0), const XlsxColumn(width: 9));
      expect(sheet.column(1), isNull);
      sheet.setColumn(0, const XlsxColumn(width: 10));
      expect(
        RegExp('<cols>.*?</cols>')
            .allMatches(_sheetXml(book))
            .map((RegExpMatch m) => m.group(0))
            .toList(),
        <String>[
          '<cols><col min="1" max="1" width="10" customWidth="1"/></cols>',
          '<cols><col min="2" max="2" width="9" customWidth="1"/></cols>',
        ],
      );
    });

    test('setting a column to what it reads changes nothing', () {
      final XlsxWorkbook layout = fixture('m2_columns_rows');
      final XlsxWorkbook inexact = openColumns(
        '<cols><col min="1" max="2" width="12" customWidth="1" style="3" '
        'bestFit="1"/><col min="4" max="4" width="abc" hidden="9"/></cols>',
      );
      for (final XlsxWorkbook book in <XlsxWorkbook>[layout, inexact]) {
        final XlsxSheet sheet = book.sheets.first..column(0);
        final String before = _sheetXml(book);
        for (int c = 0; c < 10; c++) {
          sheet.setColumn(c, sheet.column(c));
        }
        expect(changeLogOf(book).hasChanges, isFalse);
        expect(_sheetXml(book), before);
      }
      // The inexact style is read, and kept when another field changes.
      final XlsxSheet sheet = inexact.sheets.single;
      expect(sheet.column(0)?.style?.font?.bold, isTrue);
      final StylesPart styles = stylesPartOf(inexact)!;
      final StylesMark mark = styles.mark();
      sheet.setColumn(
        0,
        XlsxColumn(width: 12, style: sheet.column(0)!.style, hidden: true),
      );
      expect(styles.mark(), mark);
      expect(
        colsOf(_sheetXml(inexact)),
        startsWith(
          '<cols><col min="1" max="1" width="12" customWidth="1" style="3" '
          'bestFit="1" hidden="1"/><col min="2" max="2" width="12" '
          'customWidth="1" style="3" bestFit="1"/>',
        ),
      );
    });

    test(
      'a column style appends to the styles; an equal one keeps its index',
      () {
        final XlsxWorkbook book = openColumns(
          '<cols><col min="1" max="1" width="9" style="1"/></cols>',
        );
        final XlsxSheet sheet = book.sheets.single..column(0);
        final StylesPart styles = stylesPartOf(book)!;
        final StylesMark before = styles.mark();
        sheet.setColumn(0, sheet.column(0));
        expect(styles.mark(), before);
        sheet.setColumn(1, const XlsxColumn(style: _italic));
        expect(styles.mark(), before, reason: 'italic is cell format 2');
        sheet.setColumn(
          2,
          const XlsxColumn(
            style: XlsxStyle(font: XlsxFont(bold: true, italic: true)),
          ),
        );
        expect(styles.mark(), isNot(before));
        expect(
          colsOf(_sheetXml(book)),
          '<cols><col min="1" max="1" width="9" style="1"/>'
          '<col min="2" max="2" width="9.140625" style="2"/>'
          '<col min="3" max="3" width="9.140625" style="4"/></cols>',
        );
        // A default style writes no style attribute.
        sheet.setColumn(0, const XlsxColumn(width: 9, style: XlsxStyle()));
        expect(
          colsOf(_sheetXml(book)),
          startsWith('<cols><col min="1" max="1" width="9"/>'),
        );
      },
    );

    test('a failed setColumn changes nothing', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="3" width="9" customWidth="1"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single..column(0);
      final String before = _sheetXml(book);
      final StylesMark mark = stylesPartOf(book)!.mark();
      void fails(XlsxColumn column, String name, {int index = 1}) {
        expect(
          () => sheet.setColumn(index, column),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              name,
            ),
          ),
          reason: name,
        );
      }

      for (final double bad in <double>[-1, 256, double.nan, double.infinity]) {
        fails(XlsxColumn(width: bad), 'column.width');
      }
      fails(const XlsxColumn(outlineLevel: 8), 'column.outlineLevel');
      fails(const XlsxColumn(outlineLevel: -1), 'column.outlineLevel');
      fails(
        const XlsxColumn(width: 20, style: XlsxStyle(font: XlsxFont(size: -3))),
        'column.style.font.size',
      );
      fails(
        const XlsxColumn(
          style: XlsxStyle(font: XlsxFont(name: '')),
        ),
        'column.style.font.name',
        index: 7,
      );
      expect(() => sheet.setColumn(-1, null), throwsRangeError);
      expect(() => sheet.setColumn(16384, null), throwsRangeError);
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_sheetXml(book), before);
      expect(stylesPartOf(book)!.mark(), mark);
      expect(sheet.column(1), const XlsxColumn(width: 9));
    });

    test(
      'setColumn on a workbook without sheet data styles throws cleanly',
      () {
        final XlsxWorkbook book = XlsxWorkbook.open(
          buildWorkbook(<String, String?>{'S': null}),
        );
        expect(
          () => book.sheets.single.setColumn(0, const XlsxColumn(width: 5)),
          throwsStateError,
        );
        expect(book.sheets.single.column(0), isNull);
      },
    );

    test('styleAt falls back to the column of an empty cell', () {
      final XlsxSheet sheet = fixture('m2_style_precedence').sheets.first;
      final XlsxStyle? money = sheet.styleAt(1, 1);
      final XlsxStyle? date = sheet.styleAt(1, 2);
      expect(money?.numFmt, isNotNull);
      expect(date?.numFmt, isNotNull);
      // Beyond the data: no cell, no row, the column's style.
      expect(sheet.styleAt(20, 1), money);
      expect(sheet.styleAt(20, 2), date);
      expect(sheet.styleAt(20, 0), isNull);
      expect(sheet.styleAt(20, 3), isNull);
      expect(sheet.styleAt(4, 3), isNull);
      // Cells keep their own merged style: the bold header over money.
      expect(sheet.styleAt(0, 1)?.font?.bold, isTrue);
      expect(sheet.styleAt(0, 1)?.numFmt, money?.numFmt);
    });

    test('styleAt: cell, then row, then column', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="2" width="9" style="2"/></cols>',
        rows:
            '<row r="1" s="1" customFormat="1"><c r="B1" s="3"/></row>'
            '<row r="2" s="1"/>'
            '<row r="3" s="0" customFormat="1"/>'
            '<row r="4"><c r="B4"><v>1</v></c></row>',
      );
      final XlsxSheet sheet = book.sheets.single..cellAt(0, 0);
      final StylesPart styles = stylesPartOf(book)!;
      // The cell's own style, even when the column has one.
      expect(sheet.styleAt(0, 1)?.font?.bold, isTrue);
      // No cell: the row's style, not the column's.
      expect(sheet.styleAt(0, 0), styles.styleOf(1));
      // An s without customFormat is not a row style: the column's.
      expect(sheet.styleAt(1, 0), styles.styleOf(2));
      // An explicit default row style shows the default.
      expect(sheet.styleAt(2, 0), isNull);
      // A cell without an s is the default, whatever the column.
      expect(sheet.styleAt(3, 1), isNull);
      // No cell, no row: the column; beyond the columns: none.
      expect(sheet.styleAt(9, 0), styles.styleOf(2));
      expect(sheet.styleAt(9, 1), styles.styleOf(2));
      expect(sheet.styleAt(9, 2), isNull);
    });

    test('an XlsxCell over a column style takes the writer cell formats', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="1" width="9" style="2"/></cols>',
        rows:
            '<row r="2" s="1" customFormat="1"/>'
            '<row r="3" s="0" customFormat="1"/>',
      );
      final XlsxSheet sheet = book.sheets.single
        ..cellAt(0, 0)
        ..setCell(0, 0, const XlsxCell(5, style: _bold))
        ..setCell(0, 1, const XlsxCell(6))
        ..setCell(
          1,
          0,
          XlsxCell(7, style: XlsxStyle(numFmt: XlsxNumFmt.percent())),
        )
        ..setCell(2, 0, const XlsxCell(8))
        ..setCell(3, 0, const XlsxCell(null, style: _bold))
        ..setCell(4, 0, const XlsxCell(null));
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('S')
        ..columns(const <XlsxColumn?>[XlsxColumn(style: _italic)])
        ..row(<Object?>[const XlsxCell(5, style: _bold), const XlsxCell(6)])
        ..row(<Object?>[
          XlsxCell(7, style: XlsxStyle(numFmt: XlsxNumFmt.percent())),
        ], style: _bold)
        ..blankRow()
        ..row(<Object?>[const XlsxCell(null, style: _bold)])
        ..row(<Object?>[const XlsxCell(null)]);
      final XlsxSheet other = XlsxWorkbook.open(
        writer.close().bytes,
      ).sheets.single;
      final StylesPart styles = stylesPartOf(book)!;
      expect(sheet.styleAt(0, 0), styles.styleOf(2).merge(_bold));
      for (final (int r, int c) in <(int, int)>[
        (0, 0),
        (0, 1),
        (1, 0),
        (3, 0),
        (4, 0),
      ]) {
        expect(sheet.styleAt(r, c), other.styleAt(r, c), reason: '$r, $c');
      }
      // A row formatted with the default style shows the default, so no
      // column style goes under its cells (the writer cannot make one).
      expect(sheet.styleAt(2, 0), isNull);
      for (final (int r, int c) in <(int, int)>[(0, 0), (0, 1)]) {
        expect(sheet.cellAt(r, c)?.value, other.cellAt(r, c)?.value);
        expect(sheet.cellAt(r, c)?.value, isNotNull);
      }
      expect(sheet.cellAt(2, 0)?.value, isNotNull);
    });

    test('a plain value set keeps the cell style, not the column layers', () {
      final XlsxSheet sheet = openColumns(
        '<cols><col min="1" max="1" width="9" style="2"/></cols>',
        rows: '<row r="1"><c r="A1"><v>1</v></c></row>',
      ).sheets.single..setCell(0, 0, 4);
      expect(sheet.styleAt(0, 0), isNull);
    });

    test('layout edits of different elements revert independently', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="3" width="9" customWidth="1"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single..column(0);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet first = log.transaction(
        () => sheet.setColumn(1, const XlsxColumn(hidden: true)),
      );
      final ChangeSet second = log.transaction(
        () => sheet.setDefaultSizes(rowHeight: 20),
      );
      log.revertSet(first);
      expect(sheet.column(1), const XlsxColumn(width: 9));
      expect(sheet.defaultSizes.rowHeight, 20);
      expect(formatOf(_sheetXml(book)), contains('customHeight="1"'));
      log.reapplySet(first);
      log.revertSet(second);
      expect(sheet.defaultSizes.rowHeight, isNull);
      expect(sheet.column(1)?.hidden, isTrue);
      expect(_sheetXml(book), isNot(contains('sheetFormatPr')));
    });

    test('setColumn is undone and redone with the change log', () {
      final XlsxWorkbook book = openColumns(
        '<cols><col min="1" max="3" width="9" customWidth="1"/></cols>',
      );
      final XlsxSheet sheet = book.sheets.single..column(0);
      final String before = _sheetXml(book);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        // Inside a transaction an edit is one undoable step.
        sheet.setColumn(1, const XlsxColumn(hidden: true));
      });
      final String after = _sheetXml(book);
      expect(after, isNot(before));
      log.revertSet(set);
      expect(_sheetXml(book), before);
      expect(sheet.column(1), const XlsxColumn(width: 9));
      log.reapplySet(set);
      expect(_sheetXml(book), after);
    });
  });

  group('default sizes', () {
    String formatOf(String xml) =>
        RegExp('<sheetFormatPr[^>]*>').firstMatch(xml)?.group(0) ?? '';

    test('default sizes read and set', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        allFixtures()
            .firstWhere((Fixture f) => f.name == 'm2_columns_rows')
            .build(),
      );
      expect(book.sheets[0].defaultSizes, (rowHeight: null, columnWidth: null));
      expect(book.sheets[1].defaultSizes, (rowHeight: 18, columnWidth: 11));
      expect(book.warnings, isEmpty);

      // Set as the writer sets them.
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('S').defaultSizes(rowHeight: 18, columnWidth: 11);
      final XlsxWorkbook made = XlsxWorkbook();
      final XlsxSheet sheet = made.addSheet('S')
        ..setDefaultSizes(rowHeight: 18, columnWidth: 11);
      expect(
        formatOf(_sheetXml(made)),
        formatOf(partText(writer.close().bytes, 'xl/worksheets/sheet1.xml')),
      );
      expect(formatOf(_sheetXml(made)), contains('customHeight="1"'));
      expect(XlsxWorkbook.open(made.save().bytes).sheets.single.defaultSizes, (
        rowHeight: 18,
        columnWidth: 11,
      ));
      // The element is made before sheetData, after sheetViews.
      final String xml = _sheetXml(made);
      expect(
        xml.indexOf('<sheetViews'),
        lessThan(xml.indexOf('<sheetFormatPr')),
      );
      expect(
        xml.indexOf('<sheetFormatPr'),
        lessThan(xml.indexOf('<sheetData')),
      );
      // Only the column width, like the writer.
      sheet.setDefaultSizes(columnWidth: 12.5);
      expect(
        formatOf(_sheetXml(made)),
        '<sheetFormatPr defaultColWidth="12.5" defaultRowHeight="15"/>',
      );
    });

    test('setDefaultSizes keeps the other attributes and resets to Excel', () {
      final XlsxWorkbook book = _open(
        '<row r="1"/>',
        sheetFormat:
            '<sheetFormatPr baseColWidth="10" defaultRowHeight="15" '
            'x14ac:dyDescent="0.25"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.defaultSizes, (rowHeight: null, columnWidth: null));
      sheet.setDefaultSizes(rowHeight: 20, columnWidth: 11);
      expect(
        formatOf(_sheetXml(book)),
        '<sheetFormatPr baseColWidth="10" defaultRowHeight="20" '
        'x14ac:dyDescent="0.25" defaultColWidth="11" customHeight="1"/>',
      );
      // Reset as the writer writes no custom height: 15, no customHeight.
      sheet.setDefaultSizes();
      expect(
        formatOf(_sheetXml(book)),
        '<sheetFormatPr baseColWidth="10" defaultRowHeight="15" '
        'x14ac:dyDescent="0.25"/>',
      );
      expect(sheet.defaultSizes, (rowHeight: null, columnWidth: null));
    });

    test('equal sizes change nothing, even unreadable ones', () {
      final XlsxWorkbook book = _open(
        '',
        sheetFormat:
            '<sheetFormatPr defaultColWidth="abc" defaultRowHeight="x" '
            'customHeight="1"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.defaultSizes, (rowHeight: null, columnWidth: null));
      final String before = _sheetXml(book);
      expect(_layoutWarnings(book), hasLength(2));
      sheet.setDefaultSizes();
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_sheetXml(book), before);
      final XlsxWorkbook none = _open('');
      none.sheets.single.setDefaultSizes();
      expect(changeLogOf(none).hasChanges, isFalse);
      expect(_sheetXml(none), isNot(contains('sheetFormatPr')));
    });

    test('invalid sizes throw ArgumentError named for the field', () {
      final XlsxWorkbook book = _open('');
      final XlsxSheet sheet = book.sheets.single;
      for (final (double? row, double? column, String name)
          in <(double?, double?, String)>[
            (-1, null, 'rowHeight'),
            (410, null, 'rowHeight'),
            (double.nan, null, 'rowHeight'),
            (null, 256, 'columnWidth'),
            (null, -1, 'columnWidth'),
            (null, double.infinity, 'columnWidth'),
          ]) {
        expect(
          () => sheet.setDefaultSizes(rowHeight: row, columnWidth: column),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              name,
            ),
          ),
        );
      }
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a sheetFormatPr with children reads but cannot be set', () {
      final XlsxWorkbook book = _open(
        '',
        sheetFormat:
            '<sheetFormatPr defaultColWidth="11" defaultRowHeight="15">'
            '<x/></sheetFormatPr>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.defaultSizes, (rowHeight: null, columnWidth: 11));
      expect(() => sheet.setDefaultSizes(columnWidth: 12), throwsStateError);
      sheet.setDefaultSizes(columnWidth: 11);
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(formatOf(_sheetXml(book)), startsWith('<sheetFormatPr'));
      expect(_sheetXml(book), contains('<x/>'));
      expect(
        RegExp('<sheetFormatPr').allMatches(_sheetXml(book)),
        hasLength(1),
      );
    });

    test('setDefaultSizes is undone with the change log', () {
      final XlsxWorkbook book = _open('<row r="1"/>');
      book.sheets.single.rowFormat(0);
      final String before = _sheetXml(book);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => book.sheets.single.setDefaultSizes(rowHeight: 20),
      );
      expect(_sheetXml(book), contains('customHeight="1"'));
      log.revertSet(set);
      expect(_sheetXml(book), before);
    });

    test('a sheet without a part has no sizes and cannot set them', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String?>{'S': null}),
      );
      expect(book.sheets.single.defaultSizes, (
        rowHeight: null,
        columnWidth: null,
      ));
      expect(
        () => book.sheets.single.setDefaultSizes(rowHeight: 20),
        throwsStateError,
      );
    });
  });

  group('a plain value in a cell the file lacks', () {
    // _columnStyles, then a bold date (4) and a bold 0.00 (5).
    final String styles = _columnStyles.replaceFirst(
      '</cellXfs>',
      '<xf numFmtId="14" fontId="1" fillId="0" borderId="0" applyFont="1" '
          'applyNumberFormat="1"/>'
          '<xf numFmtId="2" fontId="1" fillId="0" borderId="0" applyFont="1" '
          'applyNumberFormat="1"/></cellXfs>',
    );
    const String boldRow = '<row r="1" s="1" customFormat="1"/>';
    const String italicRow = '<row r="1" s="2" customFormat="1"/>';
    const String boldColumn =
        '<cols><col min="1" max="3" width="9" style="1"/></cols>';
    final DateTime date = DateTime.utc(2026, 11, 4, 12);

    XlsxWorkbook open({String rows = '', String cols = ''}) =>
        _open(rows, cols: cols, styles: styles);

    String stylesXml(XlsxWorkbook book) =>
        partText(book.save().bytes, 'xl/styles.xml');

    for (final (String label, String rows, String cols, XlsxFont font)
        in <(String, String, String, XlsxFont)>[
          ('a formatted row', boldRow, '', const XlsxFont(bold: true)),
          ('a styled column', '', boldColumn, const XlsxFont(bold: true)),
          ('a row over a column', italicRow, boldColumn, _italic.font!),
        ]) {
      test('keeps the style of $label: text, number and formula', () {
        final XlsxWorkbook book = open(rows: rows, cols: cols);
        final XlsxSheet sheet = book.sheets.single;
        final List<Object> values = <Object>[
          'x',
          1.5,
          const XlsxFormula('1+1'),
        ];
        final XlsxStyle? style = sheet.styleAt(0, 0);
        final String before = stylesXml(book);
        expect(style?.font?.bold, font.bold);
        expect(style?.font?.italic, font.italic);
        for (int i = 0; i < 3; i++) {
          expect(sheet.styleAt(0, i), style);
          sheet.setCell(0, i, values[i]);
          expect(sheet.styleAt(0, i), style, reason: '${values[i]}');
        }
        final XlsxSheet reopened = XlsxWorkbook.open(
          book.save().bytes,
        ).sheets.single;
        for (int i = 0; i < 3; i++) {
          expect(reopened.styleAt(0, i), style);
        }
        // The cells took an index the file has: nothing was appended.
        expect(stylesXml(book), before);
      });

      test('keeps the style of $label under a date', () {
        final XlsxWorkbook book = open(rows: rows, cols: cols);
        final XlsxSheet sheet = book.sheets.single;
        final XlsxStyle style = sheet.styleAt(0, 0)!;
        sheet.setCell(0, 0, date);
        sheet.setCell(0, 1, const XlsxDate(2026, 11, 4));
        // A date needs a date format: all else of the style stays.
        expect(
          sheet.styleAt(0, 0),
          style.copyWith(numFmt: XlsxNumFmt.localeDateTime),
        );
        expect(
          sheet.styleAt(0, 1),
          style.copyWith(numFmt: XlsxNumFmt.localeShortDate),
        );
        final XlsxReadRow row = XlsxReader(book.save().bytes).rows('S').single;
        expect(row.cells[0].isDate, isTrue);
        expect(row.cells[1].isDate, isTrue);
      });
    }

    test('a date in a row with a date format equals the row exactly', () {
      final XlsxWorkbook book = open(
        rows: '<row r="1" s="4" customFormat="1"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      final XlsxStyle? before = sheet.styleAt(0, 0);
      expect(before?.font?.bold, isTrue);
      final String xml = stylesXml(book);
      sheet.setCell(0, 0, const XlsxDate(2026, 11, 4));
      expect(sheet.styleAt(0, 0), before);
      expect(_sheetXml(book), contains('<c r="A1" s="4">'));
      expect(stylesXml(book), xml);
    });

    test('a date in a row of a number format keeps it and warns', () {
      final XlsxWorkbook book = open(
        rows: '<row r="1" s="5" customFormat="1"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      final XlsxStyle? before = sheet.styleAt(0, 0);
      sheet.setCell(0, 0, date);
      expect(sheet.styleAt(0, 0), before);
      expect(
        book.warnings.map((XlsxWarning w) => w.code),
        contains(XlsxWarningCode.dateInNonDateFormat),
      );
    });

    test('a date takes the style setRowFormat appended', () {
      final XlsxWorkbook book = open();
      final XlsxSheet sheet = book.sheets.single;
      const XlsxStyle style = XlsxStyle(
        font: XlsxFont(bold: true, italic: true),
      );
      sheet.setRowFormat(0, const XlsxRowFormat(style: style));
      sheet.setCell(0, 0, 'x');
      sheet.setCell(0, 1, date);
      expect(sheet.styleAt(0, 0), sheet.styleAt(0, 5));
      expect(sheet.styleAt(0, 1)?.font, sheet.styleAt(0, 5)?.font);
      expect(sheet.styleAt(0, 1)?.numFmt, XlsxNumFmt.localeDateTime);
    });

    test('an undone value leaves the row\'s empty cell', () {
      final XlsxWorkbook book = open(rows: boldRow);
      final XlsxSheet sheet = book.sheets.single;
      final XlsxStyle? style = sheet.styleAt(0, 0);
      final String before = stylesXml(book);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() => sheet.setCell(0, 0, date));
      log.revertSet(set);
      expect(sheet.styleAt(0, 0), style);
      expect(_sheetXml(book), isNot(contains('<c ')));
      expect(stylesXml(book), before);
    });

    test('null on an empty cell stays a no-op', () {
      for (final (String rows, String cols) in <(String, String)>[
        (boldRow, ''),
        ('', boldColumn),
      ]) {
        final XlsxWorkbook book = open(rows: rows, cols: cols);
        book.sheets.single.rows.toList();
        final String before = _sheetXml(book);
        final ChangeSet set = changeLogOf(book).transaction(() {
          book.sheets.single.setCell(0, 0, null);
        });
        expect(set.isEmpty, isTrue);
        expect(_sheetXml(book), before);
      }
    });

    test('a cell the file has keeps its own style', () {
      final XlsxWorkbook book = open(
        rows: '<row r="1" s="1" customFormat="1"><c r="A1"><v>1</v></c></row>',
      );
      book.sheets.single.setCell(0, 0, 'x');
      expect(book.sheets.single.styleAt(0, 0), isNull);
      expect(_sheetXml(book), contains('<c r="A1" t="s">'));
    });

    test('takes nothing styleAt does not show', () {
      for (final (String label, String rows, String cols)
          in <(String, String, String)>[
            ('dangling row', '<row r="1" s="99" customFormat="1"/>', ''),
            (
              'dangling row over a column',
              '<row r="1" s="99" customFormat="1"/>',
              boldColumn,
            ),
            (
              'dangling column',
              '',
              '<cols><col min="1" max="3" width="9" style="99"/></cols>',
            ),
            (
              'row of style 0 over a column',
              '<row r="1" s="0" customFormat="1"/>',
              boldColumn,
            ),
            ('row without customFormat', '<row r="1" s="1"/>', ''),
          ]) {
        final XlsxWorkbook book = open(rows: rows, cols: cols);
        final XlsxSheet sheet = book.sheets.single;
        expect(sheet.styleAt(0, 0), isNull, reason: label);
        sheet.setCell(0, 0, 'x');
        expect(_sheetXml(book), contains('<c r="A1" t="s">'), reason: label);
        expect(sheet.styleAt(0, 0), isNull, reason: label);
        // A date copies the first cell format, as in a default cell.
        sheet.setCell(0, 1, date);
        expect(sheet.styleAt(0, 1)?.font?.bold, isNot(isTrue), reason: label);
      }
    });

    test('a broken or absent styles part behaves as for any cell', () {
      final List<String?> parts = <String?>[
        null,
        '<other xmlns="urn:x"/>',
        '<styleSheet xmlns="$mainNs"/>',
      ];
      for (final String? part in parts) {
        final XlsxWorkbook book = XlsxWorkbook.open(
          buildWorkbook(<String, String>{
            'S': _worksheet(boldRow, cols: boldColumn),
          }, styles: part),
        );
        final XlsxSheet sheet = book.sheets.single;
        sheet.setCell(0, 0, 'x');
        sheet.setCell(1, 0, 1.5);
        sheet.setCell(0, 1, date);
        final String xml = _sheetXml(book);
        expect(xml, contains('<c r="A1" t="s">'), reason: part);
        expect(xml, contains('<c r="A2">'), reason: part);
      }
    });

    test('plain values match the writer in a row and a column', () {
      final List<Object> values = <Object>[
        'x',
        1.5,
        DateTime.utc(2026, 11, 4),
        const XlsxDate(2026, 11, 4),
      ];
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('Row').row(values, style: _bold);
      writer.addSheet('Column')
        ..columns(<XlsxColumn?>[
          for (int i = 0; i < 4; i++) const XlsxColumn(style: _bold),
        ])
        ..row(values);
      final XlsxWorkbook written = XlsxWorkbook.open(writer.close().bytes);

      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet row = book.addSheet('Row');
      row.setRowFormat(0, const XlsxRowFormat(style: _bold));
      final XlsxSheet column = book.addSheet('Column');
      for (int i = 0; i < 4; i++) {
        column.setColumn(i, const XlsxColumn(style: _bold));
      }
      for (int i = 0; i < 4; i++) {
        row.setCell(0, i, values[i]);
        column.setCell(0, i, values[i]);
      }
      final XlsxWorkbook saved = XlsxWorkbook.open(book.save().bytes);
      for (final String name in <String>['Row', 'Column']) {
        final XlsxSheet a = saved.sheets.firstWhere(
          (XlsxSheet s) => s.name == name,
        );
        final XlsxSheet b = written.sheets.firstWhere(
          (XlsxSheet s) => s.name == name,
        );
        for (int i = 0; i < 4; i++) {
          expect(a.styleAt(0, i), b.styleAt(0, i), reason: '$name $i');
        }
      }
    });
  });

  group('at the cell format limit', () {
    // Exactly the writer's limit: plain, bold, a bold date (22), then plain.
    final String filler =
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>' *
        (XlsxLimits.maxCellFormats - 3);
    final String styles = _styles.replaceFirst(
      '</cellXfs>',
      '<xf numFmtId="22" fontId="1" fillId="0" borderId="0" applyFont="1" '
          'applyNumberFormat="1"/>$filler</cellXfs>',
    );
    final DateTime date = DateTime.utc(2026, 11, 4, 12);

    test('a plain date on a bold row throws to append', () {
      // No bold short date among the cell formats.
      final XlsxWorkbook book = _open(
        '<row r="1" s="1" customFormat="1"/>',
        styles: styles,
      );
      final XlsxSheet sheet = book.sheets.single;
      final XlsxStyle? before = sheet.styleAt(0, 0);
      expect(
        () => sheet.setCell(0, 0, const XlsxDate(2026, 11, 4)),
        throwsA(isA<XlsxLimitError>()),
      );
      expect(sheet.styleAt(0, 0), before);
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_sheetXml(book), isNot(contains('<c ')));
    });

    test('a plain date that reuses a cell format still works', () {
      final XlsxWorkbook book = _open(
        '<row r="1" s="1" customFormat="1"/>',
        styles: styles,
      );
      final XlsxSheet sheet = book.sheets.single..setCell(0, 0, date);
      expect(_sheetXml(book), contains('<c r="A1" s="2">'));
      expect(sheet.styleAt(0, 0)?.font?.bold, isTrue);
    });
  });

  test('an XlsxCell ignores a dangling row style, as styleAt does', () {
    // Two cell formats and a row pointing past them.
    final XlsxWorkbook book = _open(
      '<row r="1" s="99" customFormat="1"/>',
      styles: _styles.replaceFirst(
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>',
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0"/>',
      ),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.styleAt(0, 0), isNull);
    sheet.setCell(0, 0, const XlsxCell('x', style: _italic));
    // xf 0's bold font does not join the layers.
    expect(sheet.styleAt(0, 0)?.font?.italic, isTrue);
    expect(sheet.styleAt(0, 0)?.font?.bold, isNot(isTrue));
  });
}
