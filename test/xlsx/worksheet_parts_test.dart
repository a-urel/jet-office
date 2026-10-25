import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/worksheet_parts.dart';
import 'package:test/test.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

const String _preamble =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="$_main" xmlns:r="$_rel">'
    '<sheetViews><sheetView workbookViewId="0"/></sheetViews>';

/// A column with the given attributes and defaults for the rest.
WorksheetColumn _col({
  double? width,
  int style = 0,
  bool hidden = false,
  int outlineLevel = 0,
  bool collapsed = false,
}) => (
  width: width,
  style: style,
  hidden: hidden,
  outlineLevel: outlineLevel,
  collapsed: collapsed,
);

/// The header of a sheet with rows, without the declaration, the
/// `<worksheet>` start tag and the views, and without `<sheetData>`.
String _between(WorksheetSettings settings) {
  final String header = worksheetHeader(settings, hasRows: true);
  expect(header, startsWith(_preamble));
  expect(header, endsWith('<sheetData>'));
  return header.substring(
    _preamble.length,
    header.length - '<sheetData>'.length,
  );
}

void main() {
  group('default settings', () {
    const WorksheetSettings none = WorksheetSettings(sheetNumber: 1);

    test('a sheet with rows gets the M1 frame', () {
      expect(worksheetHeader(none, hasRows: true), '$_preamble<sheetData>');
      expect(worksheetTrailer(none, hasRows: true), '</sheetData></worksheet>');
    });

    test('a sheet without rows gets an empty sheetData', () {
      expect(worksheetHeader(none, hasRows: false), '$_preamble<sheetData/>');
      expect(worksheetTrailer(none, hasRows: false), '</worksheet>');
    });
  });

  group('cols', () {
    test('equal adjacent columns are joined, null keeps the default', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[
              _col(width: 12),
              _col(width: 12),
              null,
              _col(hidden: true),
            ],
          ),
        ),
        '<cols><col min="1" max="2" width="12" customWidth="1"/>'
        '<col min="4" max="4" width="9.140625" hidden="1"/></cols>',
      );
    });

    test('a column with only a style gets the standard width', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[null, null, _col(style: 1)],
          ),
        ),
        '<cols><col min="3" max="3" width="9.140625" style="1"/></cols>',
      );
    });

    test('a null width takes the default column width', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[_col(style: 1)],
            defaultColumnWidth: 10,
          ),
        ),
        '<sheetFormatPr defaultColWidth="10" defaultRowHeight="15"/>'
        '<cols><col min="1" max="1" width="10" style="1"/></cols>',
      );
    });

    test('attributes come in CT_Col order', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[
              _col(
                width: 7.5,
                style: 3,
                hidden: true,
                outlineLevel: 2,
                collapsed: true,
              ),
            ],
          ),
        ),
        '<sheetFormatPr defaultRowHeight="15" outlineLevelCol="2"/>'
        '<cols><col min="1" max="1" width="7.5" style="3" hidden="1" '
        'customWidth="1" outlineLevel="2" collapsed="1"/></cols>',
      );
    });

    test('a column that sets nothing writes nothing', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[_col(), null],
          ),
        ),
        '',
      );
    });

    test('columns that differ in one attribute are not joined', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[
              _col(width: 12),
              _col(width: 12, style: 1),
              _col(width: 12, style: 1),
              _col(width: 13, style: 1),
            ],
          ),
        ),
        '<cols><col min="1" max="1" width="12" customWidth="1"/>'
        '<col min="2" max="3" width="12" style="1" customWidth="1"/>'
        '<col min="4" max="4" width="13" style="1" customWidth="1"/></cols>',
      );
    });

    test('equal columns around a gap are not joined', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[_col(width: 5), null, _col(width: 5)],
          ),
        ),
        '<cols><col min="1" max="1" width="5" customWidth="1"/>'
        '<col min="3" max="3" width="5" customWidth="1"/></cols>',
      );
    });
  });

  group('sheetFormatPr', () {
    test('default sizes', () {
      expect(
        _between(
          const WorksheetSettings(
            sheetNumber: 1,
            defaultRowHeight: 18,
            defaultColumnWidth: 10,
          ),
        ),
        '<sheetFormatPr defaultColWidth="10" defaultRowHeight="18" '
        'customHeight="1"/>',
      );
    });

    test('row outline levels alone', () {
      expect(
        _between(const WorksheetSettings(sheetNumber: 1, outlineLevelRow: 2)),
        '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="2"/>',
      );
    });

    test('a fractional default height', () {
      expect(
        _between(
          const WorksheetSettings(sheetNumber: 1, defaultRowHeight: 12.75),
        ),
        '<sheetFormatPr defaultRowHeight="12.75" customHeight="1"/>',
      );
    });

    test('the deepest column level is written', () {
      expect(
        _between(
          WorksheetSettings(
            sheetNumber: 1,
            columns: <WorksheetColumn?>[
              _col(outlineLevel: 1),
              _col(outlineLevel: 3),
              _col(outlineLevel: 2),
            ],
            outlineLevelRow: 1,
          ),
        ),
        '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="1" '
        'outlineLevelCol="3"/>'
        '<cols><col min="1" max="1" width="9.140625" outlineLevel="1"/>'
        '<col min="2" max="2" width="9.140625" outlineLevel="3"/>'
        '<col min="3" max="3" width="9.140625" outlineLevel="2"/></cols>',
      );
    });
  });

  group('checks', () {
    test('column widths are 0 to 255', () {
      checkColumnWidth(0, 'width');
      checkColumnWidth(255, 'width');
      for (final double bad in <double>[-1, 256, double.nan]) {
        expect(
          () => checkColumnWidth(bad, 'columns[2].width'),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'columns[2].width',
            ),
          ),
        );
      }
    });

    test('row heights are 0 to 409', () {
      checkRowHeight(0, 'height');
      checkRowHeight(409, 'height');
      for (final double bad in <double>[-1, 410, double.infinity]) {
        expect(() => checkRowHeight(bad, 'height'), throwsArgumentError);
      }
    });

    test('outline levels are 0 to 7', () {
      checkOutlineLevel(0, 'outlineLevel');
      checkOutlineLevel(7, 'outlineLevel');
      for (final int bad in <int>[-1, 8]) {
        expect(
          () => checkOutlineLevel(bad, 'outlineLevel'),
          throwsArgumentError,
        );
      }
    });
  });

  group('sheetPr', () {
    const String declared =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="$_main" xmlns:r="$_rel">';
    const String defaultViews =
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>';

    String header(WorksheetSettings s) => worksheetHeader(s, hasRows: true);

    test('a tab color and a summary position', () {
      expect(
        header(
          const WorksheetSettings(
            sheetNumber: 1,
            tabColor: XlsxColor.rgb(0xFF0000),
            summaryBelow: false,
          ),
        ),
        '$declared<sheetPr><tabColor rgb="FFFF0000"/>'
        '<outlinePr summaryBelow="0"/></sheetPr>$defaultViews<sheetData>',
      );
    });

    test('a tab color alone', () {
      expect(
        header(
          const WorksheetSettings(sheetNumber: 1, tabColor: XlsxColor.theme(4)),
        ),
        '$declared<sheetPr><tabColor theme="4"/></sheetPr>'
        '$defaultViews<sheetData>',
      );
    });

    test('summaryRight alone, and both', () {
      expect(
        header(const WorksheetSettings(sheetNumber: 1, summaryRight: false)),
        '$declared<sheetPr><outlinePr summaryRight="0"/></sheetPr>'
        '$defaultViews<sheetData>',
      );
      expect(
        header(
          const WorksheetSettings(
            sheetNumber: 1,
            summaryBelow: false,
            summaryRight: false,
          ),
        ),
        '$declared<sheetPr><outlinePr summaryBelow="0" summaryRight="0"/>'
        '</sheetPr>$defaultViews<sheetData>',
      );
    });
  });

  group('sheetView', () {
    String views(XlsxSheetView view) {
      final String header = worksheetHeader(
        WorksheetSettings(sheetNumber: 1, view: view),
        hasRows: true,
      );
      final int start = header.indexOf('<sheetViews>');
      return header.substring(start, header.indexOf('<sheetData>'));
    }

    test('every option', () {
      expect(
        views(
          const XlsxSheetView(
            zoom: 85,
            showGridLines: false,
            showHeadings: false,
            rightToLeft: true,
            showZeros: false,
            showFormulas: true,
          ),
        ),
        '<sheetViews><sheetView showFormulas="1" showGridLines="0" '
        'showRowColHeaders="0" showZeros="0" rightToLeft="1" '
        'zoomScale="85" workbookViewId="0"/></sheetViews>',
      );
    });

    test('a frozen row', () {
      expect(
        views(const XlsxSheetView(pane: XlsxPane.frozen(rows: 1))),
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
        'topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft"/></sheetView></sheetViews>',
      );
    });

    test('frozen columns', () {
      expect(
        views(const XlsxSheetView(pane: XlsxPane.frozen(columns: 2))),
        contains(
          '<pane xSplit="2" topLeftCell="C1" activePane="topRight" '
          'state="frozen"/><selection pane="topRight"/>',
        ),
      );
    });

    test('a frozen row and column', () {
      expect(
        views(const XlsxSheetView(pane: XlsxPane.frozen(rows: 1, columns: 1))),
        contains(
          '<pane xSplit="1" ySplit="1" topLeftCell="B2" '
          'activePane="bottomRight" state="frozen"/>'
          '<selection pane="bottomRight"/>',
        ),
      );
    });

    test('a split pane is in twips and has no topLeftCell', () {
      expect(
        views(const XlsxSheetView(pane: XlsxPane.split(x: 100, y: 50))),
        contains(
          '<pane xSplit="2000" ySplit="1000" activePane="bottomRight"/>'
          '<selection pane="bottomRight"/>',
        ),
      );
    });

    test('a split on one axis', () {
      expect(
        views(const XlsxSheetView(pane: XlsxPane.split(x: 12.5))),
        contains(
          '<pane xSplit="250" activePane="topRight"/>'
          '<selection pane="topRight"/>',
        ),
      );
      expect(
        views(const XlsxSheetView(pane: XlsxPane.split(y: 60))),
        contains(
          '<pane ySplit="1200" activePane="bottomLeft"/>'
          '<selection pane="bottomLeft"/>',
        ),
      );
    });

    test('split offsets are rounded to whole twips', () {
      expect(
        views(const XlsxSheetView(pane: XlsxPane.split(x: 100.04))),
        contains('<pane xSplit="2001" activePane="topRight"/>'),
      );
    });

    test('an axis that rounds to 0 twips is no split on that axis', () {
      expect(
        views(const XlsxSheetView(pane: XlsxPane.split(x: 0.01))),
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>',
      );
      expect(
        views(const XlsxSheetView(pane: XlsxPane.split(x: 0.01, y: 50))),
        contains(
          '<pane ySplit="1000" activePane="bottomLeft"/>'
          '<selection pane="bottomLeft"/>',
        ),
      );
    });

    test('a pane of zeros writes no pane and no selection', () {
      for (final XlsxPane pane in const <XlsxPane>[
        XlsxPane.frozen(),
        XlsxPane.split(),
      ]) {
        expect(
          views(XlsxSheetView(pane: pane)),
          '<sheetViews><sheetView workbookViewId="0"/></sheetViews>',
        );
      }
    });

    test('the pane comes with the other options', () {
      expect(
        views(const XlsxSheetView(zoom: 150, pane: XlsxPane.frozen(rows: 2))),
        '<sheetViews><sheetView zoomScale="150" workbookViewId="0">'
        '<pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" '
        'state="frozen"/><selection pane="bottomLeft"/></sheetView>'
        '</sheetViews>',
      );
    });
  });

  group('autoFilter and mergeCells', () {
    final XlsxRange filter = XlsxRange.parse('A6:D20');
    final List<XlsxRange> merges = <XlsxRange>[
      XlsxRange.parse('A1:D1'),
      XlsxRange.parse('B3:C4'),
    ];

    test('the trailer writes autoFilter before mergeCells', () {
      expect(
        worksheetTrailer(
          WorksheetSettings(sheetNumber: 1, autoFilter: filter, merges: merges),
          hasRows: true,
        ),
        '</sheetData><autoFilter ref="A6:D20"/><mergeCells count="2">'
        '<mergeCell ref="A1:D1"/><mergeCell ref="B3:C4"/></mergeCells>'
        '</worksheet>',
      );
    });

    test('each alone, and with no rows', () {
      expect(
        worksheetTrailer(
          WorksheetSettings(sheetNumber: 1, autoFilter: filter),
          hasRows: true,
        ),
        '</sheetData><autoFilter ref="A6:D20"/></worksheet>',
      );
      expect(
        worksheetTrailer(
          WorksheetSettings(sheetNumber: 1, merges: merges),
          hasRows: false,
        ),
        '<mergeCells count="2"><mergeCell ref="A1:D1"/>'
        '<mergeCell ref="B3:C4"/></mergeCells></worksheet>',
      );
    });

    test('a single-cell filter writes its one reference', () {
      expect(
        worksheetTrailer(
          const WorksheetSettings(sheetNumber: 1, autoFilter: XlsxRange(0, 0)),
          hasRows: false,
        ),
        '<autoFilter ref="A1"/></worksheet>',
      );
    });
  });
}
