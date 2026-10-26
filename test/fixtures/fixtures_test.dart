import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/src/csv_compare.dart' show decodeXstring;
import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';
import 'fixtures.dart';
import 'm1_fixtures.dart';
import 'm2_fixtures.dart';
import 'm3_fixtures.dart';
import 'm4_fixtures.dart';

/// What a sheet stores: its rectangle of cell text and the cells that hold a
/// formula, as (row, column) pairs counted from 1.
typedef _Sheet = ({List<List<String>> rows, Set<(int, int)> formulas});

/// Every sheet in [bytes], as stored, keyed by decoded sheet name. Empty
/// cells are `''`.
Map<String, _Sheet> _readSheets(Uint8List bytes) {
  final Map<String, String> parts = readXlsx(bytes);
  final List<String> strings = <String>[
    for (final XmlElement si in XmlDocument.parse(
      parts['xl/sharedStrings.xml']!,
    ).findAllElements('si'))
      si.findAllElements('t').map((XmlElement t) => t.innerText).join(),
  ];
  final Map<String, String> targets = <String, String>{
    for (final XmlElement r in XmlDocument.parse(
      parts['xl/_rels/workbook.xml.rels']!,
    ).findAllElements('Relationship'))
      r.getAttribute('Id')!: 'xl/${r.getAttribute('Target')!}',
  };
  final Map<String, _Sheet> result = <String, _Sheet>{};
  for (final XmlElement sheet in XmlDocument.parse(
    parts['xl/workbook.xml']!,
  ).findAllElements('sheet')) {
    final XmlDocument doc = XmlDocument.parse(
      parts[targets[sheet.getAttribute('r:id')!]]!,
    );
    final Map<(int, int), String> cells = <(int, int), String>{};
    final Set<(int, int)> formulas = <(int, int)>{};
    int rows = 0;
    int columns = 0;
    for (final XmlElement row in doc.findAllElements('row')) {
      final int r = int.parse(row.getAttribute('r')!);
      for (final XmlElement c in row.findElements('c')) {
        final String letters = c
            .getAttribute('r')!
            .replaceAll(RegExp(r'\d'), '');
        int column = 0;
        for (final int unit in letters.codeUnits) {
          column = column * 26 + unit - 0x40;
        }
        final String v = c.getElement('v')?.innerText ?? '';
        cells[(r, column)] = c.getAttribute('t') == 's'
            ? strings[int.parse(v)]
            : v;
        if (c.getElement('f') != null) formulas.add((r, column));
        if (r > rows) rows = r;
        if (column > columns) columns = column;
      }
    }
    // A reader decodes `_xHHHH_` in sheet names too (ruling R22).
    result[decodeXstring(sheet.getAttribute('name')!)] = (
      rows: <List<String>>[
        for (int r = 1; r <= rows; r++)
          <String>[for (int c = 1; c <= columns; c++) cells[(r, c)] ?? ''],
      ],
      formulas: formulas,
    );
  }
  return result;
}

void main() {
  final List<Fixture> fixtures = allFixtures();

  test('the milestone lists name their fixtures', () {
    List<String> names(List<Fixture> list) => <String>[
      for (final Fixture f in list) f.name,
    ];
    expect(names(m1Fixtures()), <String>[
      'm1_values',
      'm1_dirty_text',
      'm1_sheets',
      'm1_formulas',
      'm1_empty',
      'm1_properties',
      'm1_dates',
    ]);
    expect(names(m2Fixtures()), <String>[
      'm2_styles',
      'm2_columns_rows',
      'm2_style_precedence',
      'm2_views',
      'm2_merges_filter',
      'm2_formula_xstring',
    ]);
    expect(names(m3Fixtures()), <String>[
      'm3_names',
      'm3_hyperlinks',
      'm3_validation',
      'm3_conditional',
      'm3_conditional_x14',
      'm3_page_setup',
      'm3_header_footer',
      'm3_protection',
      'm3_properties',
    ]);
    expect(names(m4Fixtures()), <String>['m4_rich_text', 'm4_notes']);
    expect(names(allFixtures()), <String>[
      ...names(m1Fixtures()),
      ...names(m2Fixtures()),
      ...names(m3Fixtures()),
      ...names(m4Fixtures()),
    ]);
  });

  test('fixture names are unique', () {
    final List<String> names = <String>[
      for (final Fixture f in fixtures) f.name,
    ];
    expect(names.toSet(), hasLength(names.length));
  });

  for (final Fixture f in fixtures) {
    group(f.name, () {
      test('passes the consistency checker', () {
        expect(checkXlsx(f.build()), isEmpty);
      });

      test('is deterministic', () {
        expect(f.build(), f.build());
      });

      test('storedValues describe what the file stores', () {
        final Map<String, _Sheet> sheets = _readSheets(f.build());
        expect(<String, List<List<String>>>{
          for (final MapEntry<String, _Sheet> e in sheets.entries)
            e.key: e.value.rows,
        }, f.storedValues);
      });

      test('expectedValues agree with storedValues', () {
        final Map<String, _Sheet> sheets = _readSheets(f.build());
        expect(
          f.expectedValues.keys.toSet(),
          f.storedValues.keys.toSet(),
          reason: 'same sheets',
        );
        f.expectedValues.forEach((String sheet, List<List<Object?>> rows) {
          final List<List<String>> stored = f.storedValues[sheet]!;
          final int height = rows.length > stored.length
              ? rows.length
              : stored.length;
          for (int r = 0; r < height; r++) {
            final List<Object?> want = r < rows.length ? rows[r] : <Object?>[];
            final List<String> raw = r < stored.length ? stored[r] : <String>[];
            final int width = want.length > raw.length
                ? want.length
                : raw.length;
            for (int c = 0; c < width; c++) {
              // A formula cell holds the value a reader computes, which the
              // file may not store, so only its cell is exempt.
              if (sheets[sheet]!.formulas.contains((r + 1, c + 1))) continue;
              final Object? e = c < want.length ? want[c] : null;
              final String s = c < raw.length ? raw[c] : '';
              final String at = '$sheet r${r + 1} c${c + 1}';
              switch (e) {
                case null:
                  expect(s, '', reason: at);
                case bool():
                  expect(s, e ? '1' : '0', reason: at);
                case num():
                  final double got = double.parse(s);
                  final double scale = e.abs() > got.abs()
                      ? e.abs().toDouble()
                      : got.abs();
                  expect(
                    (got - e).abs(),
                    lessThanOrEqualTo(1e-12 * scale),
                    reason: at,
                  );
                case String():
                  // A reader decodes the `_xHHHH_` escapes of stored text.
                  expect(decodeXstring(s), e, reason: at);
                default:
                  fail('$at: unsupported expected type ${e.runtimeType}');
              }
            }
          }
        });
      });

      test('produces the expected warnings', () {
        final Map<XlsxWarningCode, int> counts = <XlsxWarningCode, int>{};
        for (final XlsxWarning w in f.warnings()) {
          counts.update(
            w.code,
            (int n) => n + w.count,
            ifAbsent: () => w.count,
          );
        }
        expect(counts, f.expectedWarnings);
      });
    });
  }

  Fixture named(String name) =>
      fixtures.firstWhere((Fixture f) => f.name == name);

  test('m1_sheets orders the tabs and picks the active one', () {
    final Map<String, String> parts = readXlsx(named('m1_sheets').build());
    final XmlDocument book = XmlDocument.parse(parts['xl/workbook.xml']!);
    final List<String> names = <String>[
      for (final XmlElement s in book.findAllElements('sheet'))
        s.getAttribute('name')!,
    ];
    expect(names.first, 'Başlangıç');
    expect(names.last, '_x005F_x0041_'); // the sheet `_x0041_`, escaped
    expect(
      names[int.parse(
        book.findAllElements('workbookView').single.getAttribute('activeTab')!,
      )],
      'şube (2)',
    );
  });

  test('m1_properties writes the title and creator', () {
    final Map<String, String> parts = readXlsx(named('m1_properties').build());
    final XmlDocument core = XmlDocument.parse(parts['docProps/core.xml']!);
    expect(
      core.findAllElements('dc:title').single.innerText,
      'Quarterly report',
    );
    expect(core.findAllElements('dc:creator').single.innerText, 'Ahmet Urel');
  });

  test('m2_styles writes the pattern none fill as fill 0', () {
    final Map<String, String> parts = readXlsx(named('m2_styles').build());
    final XmlDocument sheet = XmlDocument.parse(
      parts['xl/worksheets/sheet1.xml']!,
    );
    final XmlDocument styles = XmlDocument.parse(parts['xl/styles.xml']!);
    final List<XmlElement> xfs = styles
        .findAllElements('cellXfs')
        .single
        .findElements('xf')
        .toList();
    final List<String> labels = <String>[
      for (final XmlElement si in XmlDocument.parse(
        parts['xl/sharedStrings.xml']!,
      ).findAllElements('si'))
        si.findAllElements('t').map((XmlElement t) => t.innerText).join(),
    ];
    final XmlElement row = sheet.findAllElements('row').firstWhere((
      XmlElement r,
    ) {
      final XmlElement label = r.findElements('c').elementAt(1);
      return labels[int.parse(label.getElement('v')!.innerText)] ==
          'pattern none';
    });
    final XmlElement cell = row.findElements('c').first;
    expect(
      xfs[int.parse(cell.getAttribute('s') ?? '0')].getAttribute('fillId'),
      '0',
    );
  });

  test('m2_columns_rows writes its columns, rows and default sizes', () {
    final Map<String, String> parts = readXlsx(
      named('m2_columns_rows').build(),
    );
    final String layout = parts['xl/worksheets/sheet1.xml']!;
    expect(
      layout,
      contains(
        '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="2" '
        'outlineLevelCol="2"/>'
        '<cols><col min="1" max="1" width="5" customWidth="1"/>'
        '<col min="2" max="2" width="12" customWidth="1"/>'
        '<col min="3" max="3" width="40" customWidth="1"/>'
        '<col min="4" max="4" width="255" customWidth="1"/>'
        '<col min="5" max="5" width="9.140625" hidden="1"/>'
        '<col min="6" max="6" width="9.140625" outlineLevel="1"/>'
        '<col min="7" max="8" width="9.140625" outlineLevel="2"/></cols>',
      ),
    );
    for (final String row in <String>[
      '<row r="2" ht="30" customHeight="1">',
      '<row r="3" ht="5" customHeight="1">',
      '<row r="4" hidden="1">',
      '<row r="5" hidden="1" outlineLevel="2">',
      '<row r="7" hidden="1" outlineLevel="1">',
      '<row r="8" collapsed="1">',
    ]) {
      expect(layout, contains(row));
    }
    expect(
      parts['xl/worksheets/sheet2.xml'],
      contains(
        '<sheetFormatPr defaultColWidth="11" defaultRowHeight="18" '
        'customHeight="1"/>',
      ),
    );
  });

  test('m2_style_precedence merges column, row and cell styles', () {
    final Map<String, String> parts = readXlsx(
      named('m2_style_precedence').build(),
    );
    final XmlDocument sheet = XmlDocument.parse(
      parts['xl/worksheets/sheet1.xml']!,
    );
    final XmlDocument styles = XmlDocument.parse(parts['xl/styles.xml']!);
    final List<XmlElement> xfs = styles
        .findAllElements('cellXfs')
        .single
        .findElements('xf')
        .toList();
    XmlElement xfOf(String ref) =>
        xfs[int.parse(
          sheet
                  .findAllElements('c')
                  .firstWhere((XmlElement c) => c.getAttribute('r') == ref)
                  .getAttribute('s') ??
              '0',
        )];
    String fontOf(XmlElement xf) => styles
        .findAllElements('fonts')
        .single
        .findElements('font')
        .elementAt(int.parse(xf.getAttribute('fontId')!))
        .toXmlString();
    final String money = xfOf('B2').getAttribute('numFmtId')!;
    expect(int.parse(money), greaterThanOrEqualTo(164));
    // Header: bold over money.
    expect(xfOf('B1').getAttribute('numFmtId'), money);
    expect(fontOf(xfOf('B1')), contains('<b/>'));
    // A date in the money column keeps the money format.
    expect(xfOf('B4').getAttribute('numFmtId'), money);
    // Totals: italic cell over the bordered row over the money column.
    final XmlElement total = xfOf('B5');
    expect(total.getAttribute('numFmtId'), money);
    expect(total.getAttribute('borderId'), isNot('0'));
    expect(fontOf(total), contains('<i/>'));
    expect(xfOf('A5').getAttribute('borderId'), total.getAttribute('borderId'));
    expect(xfOf('A5').getAttribute('numFmtId'), '0');
    // C5 is a styled empty cell (R11), so the border spans A5:C5; it keeps
    // the date column's format.
    expect(sheet.toXmlString(), contains(RegExp(r'<c r="C5" s="\d+"/>')));
    final XmlElement emptyTotal = xfOf('C5');
    expect(emptyTotal.getAttribute('borderId'), total.getAttribute('borderId'));
    expect(
      emptyTotal.getAttribute('numFmtId'),
      xfOf('C2').getAttribute('numFmtId'),
    );
  });

  test('m2_views writes its views, panes, tab color and visibility', () {
    final Map<String, String> parts = readXlsx(named('m2_views').build());
    final String workbook = parts['xl/workbook.xml']!;
    expect(workbook, contains('<workbookView activeTab="2"/>'));
    expect(
      workbook,
      contains('<sheet name="Hidden" sheetId="6" state="hidden"'),
    );
    expect(
      workbook,
      contains('<sheet name="VeryHidden" sheetId="7" state="veryHidden"'),
    );
    expect(
      parts['xl/worksheets/sheet1.xml'],
      contains(
        '<pane xSplit="1" ySplit="1" topLeftCell="B2" '
        'activePane="bottomRight" state="frozen"/>',
      ),
    );
    expect(
      parts['xl/worksheets/sheet2.xml'],
      contains('<pane xSplit="2400" ySplit="1200" activePane="bottomRight"/>'),
    );
    expect(
      parts['xl/worksheets/sheet3.xml'],
      contains(
        '<sheetPr><tabColor rgb="FFFF0000"/></sheetPr><sheetViews>'
        '<sheetView showGridLines="0" showRowColHeaders="0" showZeros="0" '
        'zoomScale="85" workbookViewId="0"/>',
      ),
    );
    expect(parts['xl/worksheets/sheet4.xml'], contains('rightToLeft="1"'));
    expect(
      parts['xl/worksheets/sheet5.xml'],
      contains('<sheetPr><outlinePr summaryBelow="0"/></sheetPr>'),
    );
  });

  test('m2_merges_filter writes its merges, filter and defined name', () {
    final Map<String, String> parts = readXlsx(
      named('m2_merges_filter').build(),
    );
    expect(
      parts['xl/worksheets/sheet1.xml'],
      endsWith(
        '</sheetData><autoFilter ref="A6:D20"/><mergeCells count="2">'
        '<mergeCell ref="A1:D1"/><mergeCell ref="B3:C4"/></mergeCells>'
        '</worksheet>',
      ),
    );
    expect(
      parts['xl/worksheets/sheet2.xml'],
      isNot(anyOf(contains('autoFilter'), contains('mergeCell'))),
    );
    expect(
      parts['xl/workbook.xml'],
      contains(
        '</sheets><definedNames><definedName name="_xlnm._FilterDatabase" '
        'localSheetId="0" hidden="1">\'Bob\'\'s Data\'!\$A\$6:\$D\$20'
        '</definedName></definedNames>',
      ),
    );
  });

  test('m3_names writes its names, print area and print titles', () {
    final Map<String, String> parts = readXlsx(named('m3_names').build());
    expect(
      parts['xl/workbook.xml'],
      contains(
        '<definedNames><definedName name="TaxRate">0.18</definedName>'
        '<definedName name="Local" localSheetId="0">Data!\$B\$2'
        '</definedName>'
        '<definedName name="_xlnm.Print_Area" localSheetId="1">'
        "'O''Brien'!\$A\$1:\$B\$4,'O''Brien'!\$D\$1:\$D\$3</definedName>"
        '<definedName name="_xlnm.Print_Titles" localSheetId="1">'
        "'O''Brien'!\$A:\$A,'O''Brien'!\$1:\$1</definedName>"
        '</definedNames>',
      ),
    );
    expect(parts['xl/worksheets/sheet1.xml'], contains('<f>TaxRate*100</f>'));
  });

  test('m3_validation writes a validation of every kind', () {
    final String sheet = readXlsx(
      named('m3_validation').build(),
    )['xl/worksheets/sheet1.xml']!;
    expect(sheet, contains('<dataValidations count="9">'));
    expect(sheet, contains('<formula1>"Fish,say ""hi"",R&amp;D"</formula1>'));
    expect(sheet, contains(r'<formula1>$D$2:$D$4</formula1>'));
    expect(sheet, contains('<formula1>46319</formula1>'));
    expect(sheet, contains('<formula1>0.5</formula1>'));
    expect(sheet, contains('<formula1>ISEVEN(B9)</formula1>'));
    expect(sheet, contains('errorStyle="warning"'));
    expect(sheet.indexOf('</sheetData>'), lessThan(sheet.indexOf('<dataV')));
  });

  test('m3_conditional writes a format of every kind', () {
    final Map<String, String> parts = readXlsx(named('m3_conditional').build());
    final String sheet = parts['xl/worksheets/sheet1.xml']!;
    for (final String type in <String>[
      'cellIs',
      'expression',
      'top10',
      'aboveAverage',
      'duplicateValues',
      'containsText',
      'colorScale',
      'dataBar',
      'iconSet',
    ]) {
      expect(sheet, contains('<cfRule type="$type"'));
    }
    // Ten rules, priorities 1 to 10 in order; the second format on column B
    // overlaps the first.
    expect(
      RegExp(
        r'priority="(\d+)"',
      ).allMatches(sheet).map((Match m) => int.parse(m.group(1)!)),
      <int>[for (int i = 1; i <= 10; i++) i],
    );
    expect(sheet, contains('<conditionalFormatting sqref="B2:B21">'));
    expect(sheet, contains('<conditionalFormatting sqref="B2:C21">'));
    expect(parts['xl/styles.xml'], contains('<dxfs count="3">'));
    expect(sheet.indexOf('</sheetData>'), lessThan(sheet.indexOf('<condit')));
  });

  test('m3_conditional_x14 writes the Excel 2010 bars and icon sets', () {
    final String sheet = readXlsx(
      named('m3_conditional_x14').build(),
    )['xl/worksheets/sheet1.xml']!;
    // Two data bars keep their 2007 rules; the x14-only icon sets have none.
    expect(RegExp('<cfRule type="dataBar"').allMatches(sheet), hasLength(2));
    expect(sheet, isNot(contains('<cfRule type="iconSet"')));
    // Both bars write a negative fill and an axis color, Excel's defaults
    // where the rule has none (A's axis, both of B's), which the M3 Excel
    // check found missing.
    expect(
      sheet,
      contains(
        '<x14:dataBar minLength="0" maxLength="100" axisPosition="middle">'
        '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
        '<x14:negativeFillColor rgb="FFFF0000"/>'
        '<x14:axisColor rgb="FF000000"/></x14:dataBar>',
      ),
    );
    expect(
      sheet,
      contains(
        '<x14:dataBar minLength="0" maxLength="100" border="1" '
        'gradient="0">'
        '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
        '<x14:borderColor rgb="FF63C384"/>'
        '<x14:negativeFillColor rgb="FFFF0000"/>'
        '<x14:axisColor rgb="FF000000"/></x14:dataBar>',
      ),
    );
    for (final String set in <String>['3Stars', '3Triangles', '5Boxes']) {
      expect(sheet, contains('<x14:iconSet iconSet="$set">'));
    }
    // The icon sets take priorities 3 to 5 after the bars' 1 and 2.
    expect(
      RegExp(
        r'priority="(\d+)"',
      ).allMatches(sheet).map((Match m) => int.parse(m.group(1)!)),
      <int>[1, 2, 3, 4, 5],
    );
    expect(sheet, endsWith('</extLst></worksheet>'));
  });

  test('m2_formula_xstring probes _xHHHH_ inside a formula and in text', () {
    final Map<String, String> parts = readXlsx(
      named('m2_formula_xstring').build(),
    );
    final String sheet = parts['xl/worksheets/sheet1.xml']!;
    // Excel decodes `_xHHHH_` inside `<f>`, so the formula is escaped like
    // cell text, as Excel writes it itself (decision 0005).
    expect(sheet, contains('<f>"_x005F_x0041_"</f>'));
    expect(sheet, contains('<c r="A2" t="s">'));
    expect(parts['xl/sharedStrings.xml'], contains('_x005F_x0041_'));
    // The sheet `_x0041_` is named escaped (R22), and its filter's defined
    // name spells it escaped the same way (decision 0005).
    final String workbook = parts['xl/workbook.xml']!;
    expect(workbook, contains('<sheet name="_x005F_x0041_" sheetId="2"'));
    expect(
      workbook,
      contains(
        '<definedNames><definedName name="_xlnm._FilterDatabase" '
        'localSheetId="1" hidden="1">\'_x005F_x0041_\'!\$A\$1:\$B\$3'
        '</definedName></definedNames>',
      ),
    );
    expect(
      parts['xl/worksheets/sheet2.xml'],
      contains('<autoFilter ref="A1:B3"/>'),
    );
  });

  test('m3_page_setup writes landscape fit-to-width and a scaled sheet', () {
    final Map<String, String> parts = readXlsx(named('m3_page_setup').build());
    final String landscape = parts['xl/worksheets/sheet1.xml']!;
    expect(landscape, contains('<pageSetUpPr fitToPage="1"/>'));
    expect(
      landscape,
      contains(
        '<printOptions horizontalCentered="1" gridLines="1"/>'
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/><pageSetup paperSize="9" fitToWidth="1" '
        'fitToHeight="0" orientation="landscape"/>',
      ),
    );
    final String scaled = parts['xl/worksheets/sheet2.xml']!;
    expect(scaled, isNot(contains('pageSetUpPr')));
    expect(
      scaled,
      contains(
        '<pageMargins left="0.25" right="0.25" top="0.5" bottom="0.5" '
        'header="0.2" footer="0.2"/><pageSetup scale="85" '
        'firstPageNumber="3" pageOrder="overThenDown" '
        'useFirstPageNumber="1"/>',
      ),
    );
  });

  test('m3_header_footer writes the texts after pageSetup order', () {
    final Map<String, String> parts = readXlsx(
      named('m3_header_footer').build(),
    );
    expect(
      parts['xl/worksheets/sheet1.xml'],
      contains(
        '<headerFooter differentOddEven="1" differentFirst="1">'
        '<oddHeader>&amp;LR&amp;&amp;D&amp;R&amp;D</oddHeader>'
        '<oddFooter>Page &amp;P of &amp;N</oddFooter>'
        '<evenFooter>&amp;A</evenFooter>'
        '<firstHeader>Cover</firstHeader></headerFooter>',
      ),
    );
  });

  test('m3_protection writes both protections and the cell flags', () {
    final Map<String, String> parts = readXlsx(named('m3_protection').build());
    expect(
      parts['xl/worksheets/sheet1.xml'],
      contains(
        '</sheetData><sheetProtection password="83AF" sheet="1" '
        'objects="1" scenarios="1" formatColumns="0"/>',
      ),
    );
    expect(
      parts['xl/workbook.xml'],
      contains(
        '<workbookProtection workbookPassword="CBEB" lockStructure="1"/>'
        '<bookViews>',
      ),
    );
    expect(parts['xl/styles.xml'], contains('<protection locked="0"/>'));
    expect(parts['xl/styles.xml'], contains('<protection hidden="1"/>'));
  });

  test('m3_properties writes every field and the five custom properties', () {
    final Map<String, String> parts = readXlsx(named('m3_properties').build());
    expect(parts['docProps/core.xml'], contains('<dc:title>Quarterly report'));
    expect(
      parts['docProps/core.xml'],
      contains('<cp:category>Finance</cp:category><cp:contentStatus>Final'),
    );
    expect(
      parts['docProps/app.xml'],
      contains('<Company>Jetronik</Company><Manager>Ayse Yilmaz</Manager>'),
    );
    final String custom = parts['docProps/custom.xml']!;
    for (final String type in <String>[
      'vt:lpwstr',
      'vt:i4',
      'vt:r8',
      'vt:bool',
      'vt:filetime',
    ]) {
      expect(custom, contains('<$type>'));
    }
    expect(custom, contains('<vt:filetime>2026-10-24T00:00:00Z'));
  });

  test('m4_rich_text writes its runs and shares A5 with A6', () {
    final Map<String, String> parts = readXlsx(named('m4_rich_text').build());
    final String sheet = parts['xl/worksheets/sheet1.xml']!;
    final List<String> items = <String>[
      for (final XmlElement si in XmlDocument.parse(
        parts['xl/sharedStrings.xml']!,
      ).findAllElements('si'))
        si.toXmlString(),
    ];
    String itemOf(String ref) =>
        items[int.parse(
          RegExp(
            '<c r="$ref"[^>]* t="s"><v>(\\d+)</v>',
          ).firstMatch(sheet)!.group(1)!,
        )];
    expect(
      itemOf('A1'),
      '<si><r><rPr><b/><sz val="11"/><rFont val="Calibri"/></rPr>'
      '<t xml:space="preserve">Total: </t></r><r><t>42</t></r></si>',
    );
    expect(
      itemOf('A2'),
      '<si><r><rPr><i/><sz val="11"/><color rgb="FFFF0000"/>'
      '<rFont val="Calibri"/></rPr><t>Red italic</t></r>'
      '<r><rPr><u/><sz val="11"/><rFont val="Calibri"/></rPr>'
      '<t xml:space="preserve"> and underlined</t></r></si>',
    );
    expect(
      itemOf('A3'),
      '<si><r><t>x</t></r><r><rPr><vertAlign val="superscript"/>'
      '<sz val="11"/><rFont val="Calibri"/></rPr><t>2</t></r></si>',
    );
    // Decision 3: the bold run carries the cell's Arial 14.
    expect(
      itemOf('A4'),
      '<si><r><rPr><b/><sz val="14"/><rFont val="Arial"/></rPr>'
      '<t>Bold</t></r><r><t xml:space="preserve"> in Arial 14</t></r></si>',
    );
    expect(sheet, contains(RegExp('<c r="A4" s="[1-9][0-9]*" t="s">')));
    expect(itemOf('A5'), '<si><t>Same text</t></si>');
    expect(
      RegExp('<c r="A5" t="s"><v>(\\d+)</v>').firstMatch(sheet)!.group(1),
      RegExp('<c r="A6" t="s"><v>(\\d+)</v>').firstMatch(sheet)!.group(1),
    );
  });

  test('m4_notes writes its notes and their boxes', () {
    final Map<String, String> parts = readXlsx(named('m4_notes').build());
    final String comments1 = parts['xl/comments1.xml']!;
    expect(
      comments1,
      contains(
        '<authors><author>Ahmet</author><author>Ayse Yilmaz</author>'
        '</authors><commentList>'
        '<comment ref="B2" authorId="0"><text><t>Check this</t></text>'
        '</comment>'
        '<comment ref="C3" authorId="0"><text>'
        '<r><rPr><b/></rPr><t>Ahmet:</t></r>'
        '<r><t xml:space="preserve">\nThe total is checked.</t></r>'
        '</text></comment>'
        '<comment ref="D4" authorId="1"><text><t>Always shown</t></text>'
        '</comment></commentList>',
      ),
    );
    final String vml1 = parts['xl/drawings/vmlDrawing1.vml']!;
    expect(vml1, contains('<o:idmap v:ext="edit" data="1"/>'));
    for (final (int id, String anchor, int row, int column)
        in <(int, String, int, int)>[
          (1025, '2, 15, 0, 10, 4, 15, 4, 4', 1, 1),
          (1026, '3, 15, 1, 10, 5, 15, 5, 4', 2, 2),
          (1027, '4, 15, 2, 10, 6, 15, 6, 4', 3, 3),
        ]) {
      expect(
        vml1,
        matches(
          '<v:shape id="_x0000_s$id" [^>]*>.*?<x:Anchor>$anchor</x:Anchor>'
          '<x:AutoFill>False</x:AutoFill><x:Row>$row</x:Row>'
          '<x:Column>$column</x:Column>',
        ),
      );
    }
    expect('visibility:visible'.allMatches(vml1), hasLength(1));
    expect(vml1, contains('<x:Column>3</x:Column><x:Visible/>'));

    final String comments2 = parts['xl/comments2.xml']!;
    expect(
      RegExp(
        '<comment ref="([A-Z]+[0-9]+)"',
      ).allMatches(comments2).map((RegExpMatch m) => m.group(1)),
      <String>['XFD1', 'A1048576'],
    );
    final String vml2 = parts['xl/drawings/vmlDrawing2.vml']!;
    expect(vml2, contains('<o:idmap v:ext="edit" data="2"/>'));
    expect(
      vml2,
      contains(
        '<x:Anchor>16380, 15, 0, 2, 16382, 15, 4, 16</x:Anchor>'
        '<x:AutoFill>False</x:AutoFill><x:Row>0</x:Row>'
        '<x:Column>16383</x:Column>',
      ),
    );
    expect(
      vml2,
      contains(
        '<x:Anchor>1, 15, 1048571, 10, 3, 15, 1048575, 4</x:Anchor>'
        '<x:AutoFill>False</x:AutoFill><x:Row>1048575</x:Row>'
        '<x:Column>0</x:Column>',
      ),
    );
    for (final int n in <int>[1, 2]) {
      expect(
        parts['xl/worksheets/sheet$n.xml'],
        endsWith('<legacyDrawing r:id="rId1"/></worksheet>'),
      );
    }
  });
}
