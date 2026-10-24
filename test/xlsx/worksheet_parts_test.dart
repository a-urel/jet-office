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
    const WorksheetSettings none = WorksheetSettings();

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
        _between(WorksheetSettings(columns: <WorksheetColumn?>[_col(), null])),
        '',
      );
    });

    test('columns that differ in one attribute are not joined', () {
      expect(
        _between(
          WorksheetSettings(
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
          const WorksheetSettings(defaultRowHeight: 18, defaultColumnWidth: 10),
        ),
        '<sheetFormatPr defaultColWidth="10" defaultRowHeight="18" '
        'customHeight="1"/>',
      );
    });

    test('row outline levels alone', () {
      expect(
        _between(const WorksheetSettings(outlineLevelRow: 2)),
        '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="2"/>',
      );
    });

    test('a fractional default height', () {
      expect(
        _between(const WorksheetSettings(defaultRowHeight: 12.75)),
        '<sheetFormatPr defaultRowHeight="12.75" customHeight="1"/>',
      );
    });

    test('the deepest column level is written', () {
      expect(
        _between(
          WorksheetSettings(
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
}
