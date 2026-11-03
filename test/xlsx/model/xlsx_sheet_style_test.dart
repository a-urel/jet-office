import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/styles_part.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

/// A styles part with a regular and a bold font, the two required fills,
/// one border and the cell formats [xfs] (raw XML).
String _styles(String xfs, {String fonts = ''}) =>
    '<styleSheet xmlns="$mainNs">'
    '<fonts><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>$fonts</fonts>'
    '<fills><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders><border><left/><right/><top/><bottom/><diagonal/></border>'
    '</borders>'
    '<cellXfs>$xfs</cellXfs></styleSheet>';

/// Plain (0), 0.00 (1), bold (2) and 0.00% (3).
const String _xfs =
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
    '<xf numFmtId="2" fontId="0" fillId="0" borderId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyFont="1"/>'
    '<xf numFmtId="10" fontId="0" fillId="0" borderId="0" '
    'applyNumberFormat="1"/>';

const XlsxStyle _bold = XlsxStyle(font: XlsxFont(bold: true));

String _encode(PartContent part) =>
    utf8.decode(<int>[for (final Uint8List c in part.encode()) ...c]);

XlsxWorkbook _open(String rows, {String xfs = _xfs, String fonts = ''}) =>
    XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(rows),
      }, styles: _styles(xfs, fonts: fonts)),
    );

void main() {
  test('styleAt reads cell and row styles', () {
    // Row 1 is formatted 0.00 (customFormat), row 2 has an s without
    // customFormat, which Excel ignores.
    final XlsxWorkbook book = _open(
      '<row r="1" s="1" customFormat="1"><c r="A1" s="2"><v>1</v></c>'
      '<c r="B1"><v>2</v></c></row>'
      '<row r="2" s="3"><c r="A2"><v>3</v></c></row>'
      '<row r="3" s="0" customFormat="1"/>',
    );
    final XlsxSheet sheet = book.sheets.single..cellAt(0, 0);
    final StylesPart styles = stylesPartOf(book) ?? _fail();
    expect(sheet.styleAt(0, 0), styles.styleOf(2));
    expect(sheet.styleAt(0, 0)?.font?.bold, isTrue);
    // B1 exists without s: its own style is the default.
    expect(sheet.styleAt(0, 1), isNull);
    // C1 does not exist: the row's style shows.
    expect(sheet.styleAt(0, 2), styles.styleOf(1));
    expect(sheet.styleAt(0, 2)?.numFmt, XlsxNumFmt.decimal2);
    expect(sheet.styleAt(1, 1), isNull);
    expect(sheet.styleAt(2, 0), isNull);
    expect(sheet.styleAt(9, 9), isNull);
    expect(() => sheet.styleAt(-1, 0), throwsRangeError);
  });

  test('setStyle appends and reads back', () {
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1"><v>1.5</v></c></row>',
    );
    final XlsxSheet sheet = book.sheets.single;
    const XlsxStyle money = XlsxStyle(
      numFmt: XlsxNumFmt.custom('#,##0.000'),
      font: XlsxFont(bold: true),
    );
    sheet
      ..setStyle(0, 0, money)
      ..setStyle(4, 2, money);
    expect(sheet.styleAt(0, 0)?.numFmt, money.numFmt);
    expect(sheet.styleAt(0, 0)?.font?.bold, isTrue);
    expect(sheet.cellAt(0, 0)?.numberFormat, '#,##0.000');
    // An empty styled cell was made at C5.
    expect(sheet.cellAt(4, 2), isNull);
    expect(sheet.styleAt(4, 2), sheet.styleAt(0, 0));
    final Uint8List output = book.save().bytes;
    final XlsxReadCell cell = XlsxReader(output).rowsAt(0).single.cells.single;
    expect(cell.value, XlsxDecimal('1.5'));
    expect(cell.numberFormat, '#,##0.000');
    final String part = partText(output, 'xl/worksheets/sheet1.xml');
    expect(part, contains('<c r="A1" s="4">'));
    expect(part, contains('<c r="C5" s="4"/>'));
  });

  test('setStyle keeps the index of an equal style', () {
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1" s="1"><v>1</v></c></row>',
    );
    final XlsxSheet sheet = book.sheets.single..cellAt(0, 0);
    final StylesPart styles = stylesPartOf(book) ?? _fail();
    final StylesMark before = styles.mark();
    sheet.setStyle(0, 0, styles.styleOf(1));
    expect(styles.mark(), before);
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(cellStoreOf(sheet)!.cellAt(0, 0)?.style, 1);
  });

  test('setStyle(null) on an empty styled cell removes it', () {
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1" s="2"/><c r="B1" s="2"><v>4</v></c>'
      '<c r="C1" s="x"/></row>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet
      ..setStyle(0, 0, null)
      ..setStyle(0, 1, null)
      ..setStyle(0, 2, null)
      ..setStyle(0, 3, null);
    final CellStore store = cellStoreOf(sheet)!;
    expect(store.cellAt(0, 0), isNull);
    expect(store.cellAt(0, 1)?.style, isNull);
    expect(store.cellAt(0, 1)?.value, '4');
    // An invalid s counts as a style and goes with null.
    expect(store.cellAt(0, 2), isNull);
    expect(store.cellAt(0, 3), isNull);
    final String part = partText(book.save().bytes, 'xl/worksheets/sheet1.xml');
    expect(part, contains('<c r="B1"><v>4</v></c>'));
    expect(part, isNot(contains('r="A1"')));
    expect(part, isNot(contains('r="C1"')));
  });

  test('setStyle(null) on a cell at index 0 changes nothing', () {
    // LibreOffice writes s="0" on plain cells.
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1" s="0"><v>1</v></c><c r="B1" s="0"/>'
      '<c r="C1"><v>2</v></c></row>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet
      ..setStyle(0, 0, null)
      ..setStyle(0, 1, null)
      ..setStyle(0, 2, null);
    expect(changeLogOf(book).hasChanges, isFalse);
    final String part = partText(book.save().bytes, 'xl/worksheets/sheet1.xml');
    expect(part, contains('<c r="A1" s="0"><v>1</v></c>'));
    expect(part, contains('<c r="B1" s="0"/>'));
  });

  test('XlsxCell layers like the writer', () {
    // Row 1 is formatted 0.00 with customFormat; row 2 is not formatted.
    final XlsxWorkbook book = _open(
      '<row r="1" s="1" customFormat="1"><c r="A1" s="3"><v>1</v></c></row>'
      '<row r="2"><c r="A2" s="3"><v>2</v></c></row>',
    );
    final XlsxSheet sheet = book.sheets.single..cellAt(0, 0);
    final StylesPart styles = stylesPartOf(book) ?? _fail();
    final XlsxStyle row = styles.styleOf(1);
    sheet
      ..setCell(0, 0, const XlsxCell(5, style: _bold))
      ..setCell(0, 1, const XlsxCell('x'))
      ..setCell(1, 0, const XlsxCell(6, style: _bold))
      ..setCell(1, 1, const XlsxCell(7));
    // The cell's old style (0.00%) is replaced by the layers.
    expect(sheet.styleAt(0, 0), row.merge(_bold));
    expect(sheet.cellAt(0, 0)?.numberFormatId, 2);
    expect(sheet.styleAt(0, 1), row);
    expect(sheet.styleAt(1, 0), styles.styleOf(2));
    expect(sheet.cellAt(1, 0)?.numberFormatId, 0);
    expect(cellStoreOf(sheet)!.cellAt(1, 1)?.style, isNull);
    // The writer, given the same row style, writes the same cell formats.
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('S')
      ..row(<Object?>[
        const XlsxCell(5, style: _bold),
        const XlsxCell('x'),
      ], style: row)
      ..row(<Object?>[const XlsxCell(6, style: _bold), const XlsxCell(7)]);
    final XlsxWorkbook written = XlsxWorkbook.open(writer.close().bytes);
    final XlsxSheet other = written.sheets.single;
    for (final (int r, int c) in <(int, int)>[(0, 0), (0, 1), (1, 0)]) {
      expect(sheet.styleAt(r, c), other.styleAt(r, c), reason: '$r, $c');
    }
    expect(other.styleAt(1, 1), isNull);
  });

  test('XlsxCell dates take the writer format rule', () {
    final XlsxWorkbook book = _open('');
    final XlsxSheet sheet = book.sheets.single;
    sheet
      ..setCell(0, 0, XlsxCell(DateTime.utc(2026, 11, 3, 12), style: _bold))
      ..setCell(0, 1, const XlsxCell(XlsxDate(2026, 11, 3)))
      ..setCell(
        0,
        2,
        const XlsxCell(
          XlsxDate(2026, 11, 3),
          style: XlsxStyle(numFmt: XlsxNumFmt.general),
        ),
      )
      ..setCell(0, 3, const XlsxCell(XlsxDate(1800, 1, 1), style: _bold));
    expect(sheet.styleAt(0, 0)?.numFmt, XlsxNumFmt.localeDateTime);
    expect(sheet.styleAt(0, 0)?.font?.bold, isTrue);
    expect(sheet.styleAt(0, 1)?.numFmt, XlsxNumFmt.localeShortDate);
    expect(sheet.cellAt(0, 1)?.value, DateTime.utc(2026, 11, 3));
    // An explicit General stays, with the writer's warning.
    expect(sheet.cellAt(0, 2)?.numberFormatId, 0);
    // A date outside Excel's range is text, in the cell's own style.
    expect(sheet.cellAt(0, 3)?.value, '1800-01-01');
    expect(sheet.styleAt(0, 3)?.numFmt, isNot(XlsxNumFmt.localeShortDate));
    expect(sheet.styleAt(0, 3)?.font?.bold, isTrue);
    expect(
      book.warnings.map((XlsxWarning w) => w.code),
      unorderedEquals(<XlsxWarningCode>[
        XlsxWarningCode.dateInNonDateFormat,
        XlsxWarningCode.dateOutsideExcelRange,
      ]),
    );
  });

  test('an XlsxCell of null writes what the writer writes', () {
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1" s="1"><v>1</v></c><c r="B1" s="1"/>'
      '<c r="C1" s="1"/></row>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet
      ..setCell(0, 0, const XlsxCell(null, style: _bold))
      ..setCell(0, 1, const XlsxCell(null))
      ..setCell(0, 2, const XlsxCell(null, style: XlsxStyle()));
    final CellStore store = cellStoreOf(sheet)!;
    expect(store.cellAt(0, 0)?.style, 2);
    expect(store.cellAt(0, 0)?.value, isNull);
    expect(store.cellAt(0, 1), isNull);
    expect(store.cellAt(0, 2), isNull);
  });

  test('an unloaded sheet keeps its styles', () {
    final Uint8List input = buildWorkbook(<String, String>{
      'One': worksheet('<row r="1"><c r="A1" s="3"><v>0.5</v></c></row>'),
      'Two': worksheet(
        '<row r="1"><c r="A1" s="3"><v>0.25</v></c>'
        '<c r="B1" s="1"><v>2</v></c></row>',
      ),
    }, styles: _styles(_xfs));
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    book.sheets[0]
      ..setStyle(0, 0, _bold)
      ..setStyle(0, 1, const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0')));
    final Uint8List output = book.save().bytes;
    final XlsxReader before = XlsxReader(input);
    final XlsxReader after = XlsxReader(output);
    final List<XlsxReadCell> was = before.rowsAt(1).single.cells;
    final List<XlsxReadCell> now = after.rowsAt(1).single.cells;
    for (int i = 0; i < was.length; i++) {
      expect(now[i].numberFormat, was[i].numberFormat);
      expect(now[i].numberFormatId, was[i].numberFormatId);
    }
    expect(
      partText(output, 'xl/worksheets/sheet2.xml'),
      partText(input, 'xl/worksheets/sheet2.xml'),
    );
    expect(after.rowsAt(0).single.cells.single.numberFormatId, 0);
  });

  test('a failed setStyle changes nothing', () {
    final XlsxWorkbook book = _open('<row r="1"><c r="A1"><v>1</v></c></row>');
    final XlsxSheet sheet = book.sheets.single;
    sheet.cellAt(0, 0);
    final StylesPart styles = stylesPartOf(book) ?? _fail();
    final String part = _encode(styles);
    final List<Object?> cells = cellsOf(cellStoreOf(sheet)!);
    const XlsxStyle bad = XlsxStyle(font: XlsxFont(name: ''));
    expect(
      () => sheet.setStyle(0, 0, bad),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'font.name',
        ),
      ),
    );
    expect(
      () => sheet.setCell(0, 1, const XlsxCell(1, style: bad)),
      throwsArgumentError,
    );
    expect(_encode(styles), part);
    expect(cellsOf(cellStoreOf(sheet)!), cells);
    expect(book.warnings, isEmpty);
    expect(changeLogOf(book).hasChanges, isFalse);
  });

  test('a failed XlsxCell rolls back the styles it appended', () {
    final XlsxWorkbook book = _open('<row r="1"><c r="A1"><v>1</v></c></row>');
    final XlsxSheet sheet = book.sheets.single;
    sheet.cellAt(0, 0);
    final StylesPart styles = stylesPartOf(book) ?? _fail();
    final String part = _encode(styles);
    final StylesMark mark = styles.mark();
    final List<Object?> cells = cellsOf(cellStoreOf(sheet)!);
    // The style is appended before the value is refused.
    expect(
      () => sheet.setCell(
        0,
        0,
        const XlsxCell(double.nan, style: XlsxStyle(font: XlsxFont(size: 30))),
      ),
      throwsArgumentError,
    );
    expect(styles.mark(), mark);
    expect(_encode(styles), part);
    expect(cellsOf(cellStoreOf(sheet)!), cells);
    expect(changeLogOf(book).hasChanges, isFalse);
  });

  group('a workbook without styles', () {
    Uint8List input() => buildWorkbook(<String, String>{
      'S': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
    });

    bool hasStyles(Uint8List bytes) =>
        readXlsxBytes(bytes).containsKey('xl/styles.xml');

    test('gets the part on save once a style is appended', () {
      final XlsxWorkbook book = XlsxWorkbook.open(input());
      final XlsxSheet sheet = book.sheets.single;
      expect(
        () => sheet.setStyle(0, 0, const XlsxStyle(font: XlsxFont(name: ''))),
        throwsArgumentError,
      );
      expect(hasStyles(book.save().bytes), isFalse);
      sheet.setStyle(0, 0, _bold);
      expect(sheet.styleAt(0, 0)?.font?.bold, isTrue);
      final Uint8List output = book.save().bytes;
      expect(hasStyles(output), isTrue);
      final XlsxReadCell cell = XlsxReader(
        output,
      ).rowsAt(0).single.cells.single;
      expect(cell.value, XlsxDecimal('1'));
    });

    test('a failed XlsxCell adds no part', () {
      final XlsxWorkbook book = XlsxWorkbook.open(input());
      final XlsxSheet sheet = book.sheets.single;
      expect(
        () => sheet.setCell(0, 1, const XlsxCell(double.nan, style: _bold)),
        throwsArgumentError,
      );
      expect(packageOf(book).partNames, isNot(contains('/xl/styles.xml')));
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(hasStyles(book.save().bytes), isFalse);
    });

    test('an undone setStyle leaves no part', () {
      final XlsxWorkbook book = XlsxWorkbook.open(input());
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() => sheet.setStyle(0, 0, _bold));
      log.revertSet(set);
      expect(sheet.styleAt(0, 0), isNull);
      expect(hasStyles(book.save().bytes), isFalse);
    });

    test('an undone date leaves no part', () {
      final XlsxWorkbook book = XlsxWorkbook.open(input());
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => sheet.setCell(0, 1, const XlsxDate(2026, 11, 3)),
      );
      log.revertSet(set);
      expect(sheet.cellAt(0, 1), isNull);
      expect(hasStyles(book.save().bytes), isFalse);
    });
  });

  test('setStyle undoes and redoes through the change log', () {
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1" s="1"><v>1</v></c></row>',
    );
    final XlsxSheet sheet = book.sheets.single..cellAt(0, 0);
    final StylesPart styles = stylesPartOf(book) ?? _fail();
    final StylesMark before = styles.mark();
    final ChangeLog log = changeLogOf(book);
    final ChangeSet set = log.transaction(() => sheet.setStyle(0, 0, _bold));
    final XlsxStyle? set1 = sheet.styleAt(0, 0);
    final StylesMark after = styles.mark();
    log.revertSet(set);
    expect(sheet.styleAt(0, 0), styles.styleOf(1));
    expect(styles.mark(), before);
    log.reapplySet(set);
    expect(sheet.styleAt(0, 0), set1);
    expect(styles.mark(), after);
  });

  test('an index outside cellXfs reads and is replaced as no style', () {
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1" s="9"><v>1</v></c></row>'
      '<row r="2" s="9" customFormat="1"/>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.styleAt(0, 0), isNull);
    expect(sheet.styleAt(1, 0), isNull);
    // styleOf(9) gives index 0's style, but 9 is not kept.
    final StylesPart styles = stylesPartOf(book) ?? _fail();
    sheet.setStyle(0, 0, styles.styleOf(0));
    expect(changeLogOf(book).hasChanges, isTrue);
    expect(cellStoreOf(sheet)!.cellAt(0, 0)?.style, isNull);
    expect(sheet.cellAt(0, 0)?.value, XlsxDecimal('1'));
  });

  test('XlsxCell without a style needs no styles part', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      }, styles: '<other xmlns="urn:x"/>'),
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet
      ..setCell(0, 0, const XlsxCell(2))
      ..setCell(0, 1, const XlsxCell(null));
    expect(sheet.cellAt(0, 0)?.value, XlsxDecimal('2'));
    expect(cellStoreOf(sheet)!.cellAt(0, 1), isNull);
  });

  test('XlsxCell of null in a formatted row writes what the writer writes', () {
    final XlsxWorkbook book = _open(
      '<row r="1" s="1" customFormat="1"><c r="A1" s="3"><v>1</v></c>'
      '<c r="B1" s="3"/></row>',
    );
    final XlsxSheet sheet = book.sheets.single..cellAt(0, 0);
    final XlsxStyle row = (stylesPartOf(book) ?? _fail()).styleOf(1);
    sheet
      ..setCell(0, 0, const XlsxCell(null))
      ..setCell(0, 1, const XlsxCell(null, style: _bold));
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('S').row(<Object?>[
      const XlsxCell(null),
      const XlsxCell(null, style: _bold),
    ], style: row);
    final XlsxWorkbook written = XlsxWorkbook.open(writer.close().bytes);
    final CellStore ours = cellStoreOf(sheet)!;
    final XlsxSheet other = written.sheets.single..cellAt(0, 0);
    final CellStore theirs = cellStoreOf(other)!;
    expect(ours.cellAt(0, 0), isNull);
    expect(theirs.cellAt(0, 0), isNull);
    expect(sheet.styleAt(0, 1), row.merge(_bold));
    expect(sheet.styleAt(0, 1), other.styleAt(0, 1));
    expect(ours.cellAt(0, 1)?.isEmpty, isTrue);
    expect(theirs.cellAt(0, 1)?.isEmpty, isTrue);
  });

  test('setStyle throws StateError on an untyped styles part', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      }, styles: '<other xmlns="urn:x"/>'),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(() => sheet.setStyle(0, 0, _bold), throwsStateError);
    expect(() => sheet.setStyle(0, 0, null), throwsStateError);
    expect(
      () => sheet.setCell(0, 0, const XlsxCell(1, style: _bold)),
      throwsStateError,
    );
    expect(changeLogOf(book).hasChanges, isFalse);
  });

  test('setStyle on a sheet that is not a worksheet throws StateError', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{'Chart': '<chartsheet xmlns="$mainNs"/>'}),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(() => sheet.setStyle(0, 0, _bold), throwsStateError);
    expect(sheet.styleAt(0, 0), isNull);
  });

  test('a style entry that cannot be read warns on the workbook', () {
    final XlsxWorkbook book = _open(
      '<row r="1"><c r="A1" s="4"><v>1</v></c></row>',
      fonts: '<font><sz val="abc"/><name val="Calibri"/></font>',
      xfs: '$_xfs<xf numFmtId="0" fontId="2" fillId="0" borderId="0"/>',
    );
    book.sheets.single.styleAt(0, 0);
    final XlsxWarning warning = book.warnings.single;
    expect(warning.code, XlsxWarningCode.styleEntryInvalid);
    expect(warning.sheet, '');
    expect(
      warning.detail,
      'font 2: The font size "abc" is not a finite number.',
    );
  });
}

Never _fail() => throw StateError('The styles part did not load.');
