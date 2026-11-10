// Tests tool/write_model_sample.dart: the generated workbooks of the W1, W2
// W3, W4 and W5 Excel checks. It writes files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_model_sample.dart';
import '../fixtures/m4_fixtures.dart' show jpeg3x5, png4x2;

void main() {
  test('writes a workbook the reader reads back, with the values listed', () {
    final Directory temp = Directory.systemTemp.createTempSync('model_sample');
    addTearDown(() => temp.deleteSync(recursive: true));
    final String path = writeModelSample('${temp.path}/out').first;
    expect(path, endsWith('w1_generated.xlsx'));
    final XlsxReader reader = XlsxReader(File(path).readAsBytesSync());
    expect(reader.sheets.map((XlsxReadSheet s) => s.name), <String>[
      'Values',
      'Second',
    ]);
    final List<XlsxReadRow> rows = reader.rows('Values').toList();
    expect(rows.first.cells.first.value, 'jet_office');
    expect(rows[1].cells.first.value, 'jet_office');
    // Each row's formula sums its own row.
    expect(rows[0].cells.last.formula, 'SUM(B1:C1)');
    expect(rows[1].cells.last.formula, 'SUM(B2:C2)');
    expect(reader.warnings, isEmpty);
  });
  group('w2_generated.xlsx', () {
    late XlsxWorkbook book;
    late XlsxReader reader;
    late XlsxSheet report;

    setUpAll(() {
      final Directory temp = Directory.systemTemp.createTempSync(
        'model_sample',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final String path = writeModelSample('${temp.path}/out')[1];
      expect(path, endsWith('w2_generated.xlsx'));
      final Uint8List bytes = File(path).readAsBytesSync();
      book = XlsxWorkbook.open(bytes);
      reader = XlsxReader(bytes);
      report = book.sheets.first;
    });

    test('has a merged title and a frozen header', () {
      expect(report.name, 'Report');
      expect(report.cellAt(0, 0)?.value, 'Sales report');
      expect(report.merges, <XlsxRange>[const XlsxRange(0, 0, 0, 3)]);
      expect(report.view.pane, const XlsxPane.frozen(rows: 2));
    });

    test('has a header of bold, fill and bottom border', () {
      for (int column = 0; column < 4; column++) {
        final XlsxStyle? style = report.styleAt(1, column);
        expect(style?.font?.bold, isTrue);
        expect(style?.fill, isNotNull);
        expect(style?.border?.bottom?.style, isNotNull);
      }
    });

    test('has money and date columns with widths', () {
      expect(report.column(0)?.width, 24);
      expect(report.column(1)?.width, 14);
      expect(report.column(2)?.width, 16);
      expect(report.column(1)?.style?.numFmt, isNotNull);
      expect(report.column(2)?.style?.numFmt, isNotNull);
      final List<XlsxReadCell> cells = reader
          .rowsAt(0)
          .firstWhere((XlsxReadRow r) => r.index == 2)
          .cells;
      expect(cells[1].isDate, isTrue);
      expect(cells[1].value, DateTime.utc(2026, 1, 15));
      expect(cells[2].numberFormat, report.column(2)?.style?.numFmt?.code);
    });

    test('has a hidden and a grouped row', () {
      expect(report.rowFormat(3).hidden, isTrue);
      expect(report.rowFormat(4).outlineLevel, 1);
      expect(report.rowFormat(2), const XlsxRowFormat());
    });

    test('has a tab colour, a hidden sheet and the first sheet active', () {
      expect(report.tabColor, isNotNull);
      expect(book.sheets, hasLength(2));
      expect(book.sheets.last.visibility, XlsxSheetVisibility.hidden);
      expect(book.activeSheet.name, 'Report');
    });

    test('opens with no warning', () {
      expect(reader.rowsAt(0).toList(), isNotEmpty);
      expect(reader.warnings, isEmpty);
      expect(book.warnings, isEmpty);
    });
  });

  group('w3_generated.xlsx', () {
    late XlsxWorkbook book;
    late XlsxSheet report;

    setUpAll(() {
      final Directory temp = Directory.systemTemp.createTempSync(
        'model_sample',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final List<String> paths = writeModelSample('${temp.path}/out');
      expect(paths, hasLength(5));
      expect(paths[2], endsWith('w3_generated.xlsx'));
      book = XlsxWorkbook.open(File(paths[2]).readAsBytesSync());
      report = book.sheet('Report');
    });

    test('has a Report and a Locked sheet and opens with no warning', () {
      expect(book.sheets.map((XlsxSheet s) => s.name), <String>[
        'Report',
        'Locked',
      ]);
      expect(book.warnings, isEmpty);
    });

    test('has a header, a filter and a list validation', () {
      expect(report.cellAt(0, 0)?.value, 'Product');
      expect(report.styleAt(0, 0)?.font?.bold, isTrue);
      expect(report.autoFilter, XlsxRange.parse('A1:G7'));
      final XlsxDataValidation list = report.dataValidations.single;
      expect(list.type, XlsxValidationType.list);
      expect(list.ranges, <XlsxRange>[XlsxRange.parse('B2:B7')]);
    });

    test(
      'has a cell-value rule, a colour scale, two data bars and an icon set',
      () {
        final List<XlsxConditionalRule> rules = <XlsxConditionalRule>[
          for (final XlsxConditionalFormat f in report.conditionalFormats)
            ...f.rules,
        ];
        expect(rules.map((XlsxConditionalRule r) => r.runtimeType), <Type>[
          XlsxCellValueRule,
          XlsxColorScale,
          XlsxDataBar,
          XlsxDataBar,
          XlsxIconSet,
        ]);
        expect(
          <bool>[
            for (final XlsxDataBar bar in rules.whereType<XlsxDataBar>())
              bar.showValue,
          ],
          <bool>[true, false],
        );
      },
    );

    test('has a link to a web page and one to the second sheet', () {
      expect(report.hyperlinks, hasLength(2));
      expect(report.hyperlinkAt(8, 0)?.address, startsWith('https://'));
      expect(report.hyperlinkAt(9, 0)?.location, startsWith("'Locked'!"));
    });

    test('has print settings, a name used by a formula and properties', () {
      expect(report.printArea, <XlsxRange>[XlsxRange.parse('A1:G7')]);
      expect(report.pageSetup?.orientation, XlsxOrientation.landscape);
      expect(report.pageSetup?.fitToWidth, 1);
      expect(report.headerFooter?.oddHeader, isNotNull);
      expect(report.headerFooter?.oddFooter, isNotNull);
      expect(
        book.definedNames.map((XlsxDefinedName n) => n.name),
        contains('TaxRate'),
      );
      expect(report.cellAt(1, 6)?.formula, contains('TaxRate'));
      expect(book.properties.title, isNotNull);
      expect(book.properties.custom, isNotEmpty);
    });

    test('protects the Locked sheet with a password', () {
      final XlsxSheet locked = book.sheet('Locked');
      expect(locked.protection, isNotNull);
      expect(locked.hasStoredPassword, isTrue);
      expect(report.protection, isNull);
    });
  });
  group('w4_generated.xlsx', () {
    late Uint8List bytes;
    late XlsxWorkbook book;
    late XlsxSheet objects;

    setUpAll(() {
      final Directory temp = Directory.systemTemp.createTempSync(
        'model_sample',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final List<String> paths = writeModelSample('${temp.path}/out');
      expect(paths[3], endsWith('w4_generated.xlsx'));
      bytes = File(paths[3]).readAsBytesSync();
      book = XlsxWorkbook.open(bytes);
      objects = book.sheet('Objects');
    });

    test('has an Objects and a Removed sheet and opens with no warning', () {
      expect(book.sheets.map((XlsxSheet s) => s.name), <String>[
        'Objects',
        'Removed',
      ]);
      expect(book.warnings, isEmpty);
    });

    test('has a rich text with a bold run and a red italic one', () {
      final XlsxRichText? rich = objects.richTextAt(0, 0);
      expect(rich?.text, 'Bold, plain and red italic');
      expect(rich?.runs.first.font?.bold, isTrue);
      expect(rich?.runs.last.font?.italic, isTrue);
      expect(rich?.runs.last.font?.color, const XlsxColor.rgb(0xC00000));
    });

    test('has a hidden and a visible note', () {
      expect(objects.notes, hasLength(2));
      final XlsxNote hidden = objects.noteAt(2, 1)!;
      final XlsxNote shown = objects.noteAt(2, 2)!;
      expect(hidden.visible, isFalse);
      expect(shown.visible, isTrue);
      expect(hidden.author, 'jet_office');
      expect(shown.text.text, isNotEmpty);
    });

    test('has a PNG and a JPEG, one-cell and two-cell', () {
      final List<XlsxPicture> pictures = objects.pictures;
      Iterable<XlsxPicture> of(OfficeImageFormat f) =>
          pictures.where((XlsxPicture p) => p.image.format == f);
      expect(of(OfficeImageFormat.png), hasLength(3));
      expect(of(OfficeImageFormat.jpeg), hasLength(2));
      expect(
        pictures.where((XlsxPicture p) => p.anchor is XlsxOneCellAnchor),
        hasLength(3),
      );
      expect(
        pictures.where((XlsxPicture p) => p.anchor is XlsxTwoCellAnchor),
        hasLength(2),
      );
      expect(of(OfficeImageFormat.png).first.image, OfficeImage(png4x2));
      expect(of(OfficeImageFormat.jpeg).first.image, OfficeImage(jpeg3x5));
    });

    test('shows a PNG used twice from one media part', () {
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final List<String> media = <String>[
        for (final ArchiveFile f in archive)
          if (f.name.startsWith('xl/media/')) f.name,
      ];
      expect(media, hasLength(2));
    });

    test('has a picture moved to a new size', () {
      final XlsxPicture moved = objects.pictures.firstWhere(
        (XlsxPicture p) => p.name == 'Moved picture',
      );
      final XlsxOneCellAnchor anchor = moved.anchor as XlsxOneCellAnchor;
      expect(anchor.width, 200);
      expect(anchor.height, 100);
    });

    test('has a table with totals and one without a style', () {
      final XlsxTable sales = objects.tables.firstWhere(
        (XlsxTable t) => t.name == 'Sales',
      );
      expect(sales.totalsRow, isTrue);
      expect(sales.columns.last.totalsFunction, XlsxTotalsFunction.sum);
      expect(sales.style, isNotNull);
      final XlsxTable plain = objects.tables.firstWhere(
        (XlsxTable t) => t.name == 'Plain',
      );
      expect(plain.style, isNull);
      expect(objects.tables, hasLength(2));
    });

    test('has a sheet where a table and a picture were removed again', () {
      final XlsxSheet removed = book.sheet('Removed');
      expect(removed.tables, isEmpty);
      expect(removed.pictures, isEmpty);
      expect(removed.cellAt(0, 0)?.value, isNotNull);
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final List<String> parts = <String>[
        for (final ArchiveFile f in archive) f.name,
      ];
      // One drawing and two tables, all of the sheet Objects.
      expect(
        parts.where(
          (String n) => RegExp(r'^xl/drawings/drawing\d+\.xml$').hasMatch(n),
        ),
        hasLength(1),
      );
      expect(
        parts.where(
          (String n) => RegExp(r'^xl/tables/table\d+\.xml$').hasMatch(n),
        ),
        hasLength(2),
      );
    });
  });

  group('w5_generated.xlsx', () {
    late Uint8List bytes;
    late XlsxWorkbook book;
    late XlsxSheet data;
    late XlsxSheet summary;

    setUpAll(() {
      final Directory temp = Directory.systemTemp.createTempSync(
        'model_sample',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final List<String> paths = writeModelSample('${temp.path}/out');
      expect(paths.last, endsWith('w5_generated.xlsx'));
      bytes = File(paths.last).readAsBytesSync();
      book = XlsxWorkbook.open(bytes);
      data = book.sheet('Veri 2026');
      summary = book.sheet('Summary');
    });

    String text(String part) {
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      return String.fromCharCodes(archive.findFile(part)!.content);
    }

    test('has Data renamed Veri 2026 and moved last, with no warning', () {
      expect(book.sheets.map((XlsxSheet s) => s.name), <String>[
        'Summary',
        'Veri 2026',
      ]);
      expect(book.warnings, isEmpty);
    });

    test('grew the table by the two rows inserted inside it', () {
      final XlsxTable sales = data.tables.single;
      expect(sales.name, 'Sales');
      expect(sales.range, XlsxRange.parse('A1:C8'));
      expect(data.cellAt(2, 0)?.value, 'Feb');
      expect(data.cellAt(3, 0), isNull);
      expect(data.cellAt(5, 0)?.value, 'Mar');
    });

    test('kept the Tax column one shared group over the new rows', () {
      final String sheet = text('xl/worksheets/sheet1.xml');
      expect(sheet, contains('<f t="shared" ref="C2:C8" si="0">B2*Rate</f>'));
      expect(data.cellAt(7, 2)?.formulaGroup?.range, XlsxRange.parse('C2:C8'));
    });

    test('moved the rate left with the deleted column, and the names', () {
      expect(data.cellAt(0, 8)?.value, XlsxDecimal('0.2'));
      expect(
        <String, String>{
          for (final XlsxDefinedName n in book.definedNames) n.name: n.formula,
        },
        <String, String>{
          'Rate': r"'Veri 2026'!$I$1",
          'Amounts': r"'Veri 2026'!$B$2:$B$8",
        },
      );
    });

    test('points the chart, the validation and the rule at the new cells', () {
      expect(
        text('xl/charts/chart1.xml'),
        contains(r"<c:f>'Veri 2026'!$B$2:$B$8</c:f>"),
      );
      expect(data.dataValidations.single.ranges, <XlsxRange>[
        XlsxRange.parse('B2:B8'),
      ]);
      expect(data.conditionalFormats.single.ranges, <XlsxRange>[
        XlsxRange.parse('B2:B8'),
      ]);
      expect(data.noteAt(0, 0), isNotNull);
      expect(data.pictures.single.anchor.from, const XlsxAnchorPoint(0, 10));
    });

    test("rewrote Summary's formulas and turned Extra's uses into ranges", () {
      expect(
        <String?>[for (int r = 0; r < 5; r++) summary.cellAt(r, 1)?.formula],
        <String>[
          'SUM(Sales[Amount])',
          "'Veri 2026'!B3",
          'SUM(Amounts)*Rate',
          "SUM('Summary:Veri 2026'!B2)",
          r"SUM('Veri 2026'!$F$2:$F$3)",
        ],
      );
    });

    test('asks Excel to recalculate and keeps no calculation chain', () {
      expect(text('xl/workbook.xml'), contains('fullCalcOnLoad="1"'));
      expect(
        ZipDecoder().decodeBytes(bytes).findFile('xl/calcChain.xml'),
        isNull,
      );
    });
  });
}
