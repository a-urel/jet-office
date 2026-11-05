// Tests tool/write_model_sample.dart: the generated workbooks of the W1, W2
// and W3 Excel checks. It writes files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_model_sample.dart';

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
      expect(paths, hasLength(3));
      expect(paths.last, endsWith('w3_generated.xlsx'));
      book = XlsxWorkbook.open(File(paths.last).readAsBytesSync());
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
      'has a cell-value rule, a colour scale, a data bar and an icon set',
      () {
        final List<XlsxConditionalRule> rules = <XlsxConditionalRule>[
          for (final XlsxConditionalFormat f in report.conditionalFormats)
            ...f.rules,
        ];
        expect(rules.map((XlsxConditionalRule r) => r.runtimeType), <Type>[
          XlsxCellValueRule,
          XlsxColorScale,
          XlsxDataBar,
          XlsxIconSet,
        ]);
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
}
