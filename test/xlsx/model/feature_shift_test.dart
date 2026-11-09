import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

const String _sheetRels = 'xl/worksheets/_rels/sheet1.xml.rels';
const String _x14 =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';
const String _xm = 'http://schemas.microsoft.com/office/excel/2006/main';

/// A package of the sheet `S` whose worksheet holds [body] after an empty
/// `<sheetData>`, with [names] (raw `<definedName>`s) in the workbook,
/// [rels] (raw `<Relationship>`s) for the sheet and [styles] when given.
Uint8List _package(
  String body, {
  String names = '',
  String? rels,
  String? styles,
}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    buildWorkbook(<String, String>{
      'S':
          '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>$body'
          '</worksheet>',
    }, styles: styles),
  );
  if (names.isNotEmpty) {
    final String workbook = utf8
        .decode(parts['xl/workbook.xml']!)
        .replaceFirst(
          '</sheets>',
          '</sheets><definedNames>$names</definedNames>',
        );
    parts['xl/workbook.xml'] = Uint8List.fromList(utf8.encode(workbook));
  }
  if (rels != null) {
    parts[_sheetRels] = Uint8List.fromList(
      utf8.encode('<Relationships xmlns="$pkgRelNs">$rels</Relationships>'),
    );
  }
  return buildZip(<String, List<int>>{...parts});
}

ChangeSet _edit(XlsxWorkbook book, ReferenceShift edit) => changeLogOf(
  book,
).transaction(() => referenceRegistryOf(book).apply(edit, edit));

ReferenceShift _deleteRows(int index, int count) =>
    ReferenceShift.delete('S', ShiftAxis.rows, index, count);

ReferenceShift _insertRows(int index, int count) =>
    ReferenceShift.insert('S', ShiftAxis.rows, index, count);

ReferenceShift _deleteColumns(int index, int count) =>
    ReferenceShift.delete('S', ShiftAxis.columns, index, count);

String _part(XlsxWorkbook book, String name) =>
    readXlsx(book.save().bytes)[name] ?? '';

String _sheet(XlsxWorkbook book) => _part(book, 'xl/worksheets/sheet1.xml');

void main() {
  test("defined names' text goes through the rewriter", () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        names:
            r'<definedName name="Rate" comment="c">S!$B$2:$B$9</definedName>'
            r'<definedName name="Local" localSheetId="0">$C$4+Other!$C$4'
            '</definedName>',
      ),
    );
    _edit(book, _deleteRows(3, 1));
    final String workbook = _part(book, 'xl/workbook.xml');
    expect(
      workbook,
      contains(
        r'<definedName name="Rate" comment="c">S!$B$2:$B$8</definedName>',
      ),
    );
    expect(
      workbook,
      contains(
        r'<definedName name="Local" localSheetId="0">$C$3+Other!$C$4'
        '</definedName>',
      ),
    );
  });

  test('a print area shrinks, and becomes #REF! as Excel when wholly '
      'deleted', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        names:
            '<definedName name="_xlnm.Print_Area" localSheetId="0">'
            r'S!$A$3:$D$6</definedName>'
            '<definedName name="_xlnm.Print_Titles" localSheetId="0">'
            r'S!$1:$2</definedName>',
      ),
    );
    _edit(book, _deleteRows(4, 2));
    expect(book.sheets.single.printArea, <XlsxRange>[XlsxRange.parse('A3:D4')]);
    _edit(book, _deleteRows(1, 4));
    final String workbook = _part(book, 'xl/workbook.xml');
    expect(workbook, contains(r'localSheetId="0">S!#REF!</definedName>'));
    expect(workbook, isNot(contains(r'S!$1:$2')));
  });

  test("a validation's sqref goes through rewriteSqref, the entry removed "
      'when empty', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<dataValidations count="2">'
        '<dataValidation type="whole" sqref="B2 B5:B9" xr:uid="x" '
        'xmlns:xr="urn:xr"><formula1>1</formula1></dataValidation>'
        '<dataValidation type="list" sqref="C3"><formula1>"a,b"</formula1>'
        '</dataValidation></dataValidations>',
      ),
    );
    _edit(book, _deleteRows(3, 1));
    String sheet = _sheet(book);
    expect(
      sheet,
      contains(
        '<dataValidations count="1">'
        '<dataValidation type="whole" sqref="B2 B4:B8" xr:uid="x" '
        'xmlns:xr="urn:xr"><formula1>1</formula1></dataValidation>'
        '</dataValidations>',
      ),
    );
    _edit(book, _deleteRows(1, 10));
    sheet = _sheet(book);
    expect(sheet, isNot(contains('dataValidation')));
  });

  String validation(String sqref, String formula) =>
      '<dataValidations count="1"><dataValidation type="custom" '
      'sqref="$sqref"><formula1>$formula</formula1></dataValidation>'
      '</dataValidations>';

  test("a validation's formula shifts as written, as a cell formula of the "
      'sheet does', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(validation('A1:A10', 'B5&gt;0')),
    );
    _edit(book, _insertRows(3, 1));
    expect(_sheet(book), contains(validation('A1:A11', 'B6&gt;0')));
  });

  test("a validation's formula before the insert stays", () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(validation('A5:A9', 'B2&gt;0')),
    );
    _edit(book, _insertRows(3, 1));
    expect(_sheet(book), contains(validation('A6:A10', 'B2&gt;0')));
  });

  test("a validation's formula whose row is deleted becomes #REF!", () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(validation('A1:A10', r'B5&gt;$C$5')),
    );
    _edit(book, _deleteRows(5, 1));
    expect(_sheet(book), contains(validation('A1:A9', '#REF!&gt;#REF!')));
  });

  test("a rule's sqref and formulas shift relative to its first cell", () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<conditionalFormatting sqref="C4:C8 E4">'
        '<cfRule type="expression" dxfId="0" priority="1">'
        r'<formula>C4&gt;$A$2</formula></cfRule>'
        '</conditionalFormatting>',
        styles:
            '<styleSheet xmlns="$mainNs"><dxfs count="1"><dxf><font><b/>'
            '</font></dxf></dxfs></styleSheet>',
      ),
    );
    final ChangeSet set = _edit(book, _insertRows(1, 2));
    expect(
      _sheet(book),
      contains(
        '<conditionalFormatting sqref="C6:C10 E6">'
        '<cfRule type="expression" dxfId="0" priority="1">'
        r'<formula>C6&gt;$A$4</formula></cfRule>'
        '</conditionalFormatting>',
      ),
    );
    expect(book.sheets.single.conditionalFormats.single.ranges, <XlsxRange>[
      XlsxRange.parse('C6:C10'),
      XlsxRange.parse('E6'),
    ]);
    changeLogOf(book).revertSet(set);
    expect(_sheet(book), contains('<conditionalFormatting sqref="C4:C8 E4">'));
  });

  test('a rule whose sqref is wholly deleted goes with its dxf kept', () {
    const String styles =
        '<styleSheet xmlns="$mainNs"><dxfs count="1"><dxf><font><b/>'
        '</font></dxf></dxfs></styleSheet>';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<conditionalFormatting sqref="C4:C8">'
        '<cfRule type="expression" dxfId="0" priority="1">'
        '<formula>C4&gt;1</formula></cfRule></conditionalFormatting>'
        '<conditionalFormatting sqref="D1">'
        '<cfRule type="expression" dxfId="0" priority="2">'
        '<formula>D1&gt;1</formula></cfRule></conditionalFormatting>',
        styles: styles,
      ),
    );
    _edit(book, _deleteRows(3, 6));
    final String sheet = _sheet(book);
    expect(sheet, isNot(contains('C4')));
    expect(sheet, contains('<conditionalFormatting sqref="D1">'));
    expect(_part(book, 'xl/styles.xml'), contains('<dxfs count="1">'));
  });

  test("an Excel 2010 rule's xm:sqref and xm:f shift likewise", () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<extLst><ext uri="{78C0D931-6437-407d-A8EE-F0AAD7539E65}" '
        'xmlns:x14="$_x14"><x14:conditionalFormattings>'
        '<x14:conditionalFormatting xmlns:xm="$_xm">'
        '<x14:cfRule type="expression" priority="1" id="{1}">'
        r'<xm:f>A5&gt;$C$3</xm:f></x14:cfRule><xm:sqref>A5:A9</xm:sqref>'
        '</x14:conditionalFormatting>'
        '<x14:conditionalFormatting xmlns:xm="$_xm">'
        '<x14:cfRule type="expression" priority="2" id="{2}">'
        '<xm:f>B2</xm:f></x14:cfRule><xm:sqref>B2</xm:sqref>'
        '</x14:conditionalFormatting>'
        '</x14:conditionalFormattings></ext></extLst>',
      ),
    );
    _edit(book, _deleteRows(2, 2));
    final String sheet = _sheet(book);
    expect(
      sheet,
      contains(
        '<x14:conditionalFormattings>'
        '<x14:conditionalFormatting xmlns:xm="$_xm">'
        '<x14:cfRule type="expression" priority="1" id="{1}">'
        r'<xm:f>A3&gt;#REF!</xm:f></x14:cfRule><xm:sqref>A3:A7</xm:sqref>'
        '</x14:conditionalFormatting></x14:conditionalFormattings>',
      ),
    );
  });

  test("a hyperlink's ref shifts, it goes with its relationship when "
      'deleted, and an internal location goes through the rewriter', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<hyperlinks><hyperlink ref="A2" r:id="rId1"/>'
        '<hyperlink ref="A5:B6" location="S!C7" display="d"/>'
        '<hyperlink ref="A9" location="Other!C7"/></hyperlinks>',
        rels:
            '<Relationship Id="rId1" Type="$relNs/hyperlink" '
            'Target="https://example.com" TargetMode="External"/>',
      ),
    );
    _edit(book, _deleteRows(2, 2));
    expect(
      _sheet(book),
      contains(
        '<hyperlinks><hyperlink ref="A3:B4" location="S!C5" display="d"/>'
        '<hyperlink ref="A7" location="Other!C7"/></hyperlinks>',
      ),
    );
    expect(_part(book, _sheetRels), isNot(contains('rId1')));
    expect(book.sheets.single.hyperlinkAt(2, 1)?.location, 'S!C5');
  });

  test("the auto filter's ref shifts, a filter column renumbers on column "
      'edits and one deleted goes', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<autoFilter ref="B2:E9"><filterColumn colId="1"><filters>'
        '<filter val="a"/></filters></filterColumn>'
        '<filterColumn colId="3"><filters><filter val="b"/></filters>'
        '</filterColumn></autoFilter>',
      ),
    );
    _edit(book, _insertRows(1, 1));
    expect(_sheet(book), contains('<autoFilter ref="B3:E10">'));
    _edit(book, _deleteColumns(3, 1));
    expect(
      _sheet(book),
      contains(
        '<autoFilter ref="B3:D10"><filterColumn colId="2"><filters>'
        '<filter val="b"/></filters></filterColumn></autoFilter>',
      ),
    );
    expect(book.sheets.single.autoFilter, XlsxRange.parse('B3:D10'));
  });

  test('row and column breaks shift', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<rowBreaks count="2" manualBreakCount="2">'
        '<brk id="10" max="16383" man="1"/><brk id="20" max="16383" man="1"/>'
        '</rowBreaks><colBreaks count="1" manualBreakCount="1">'
        '<brk id="4" max="1048575" man="1"/></colBreaks>',
      ),
    );
    _edit(book, _deleteRows(3, 2));
    _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 1, 2));
    expect(
      _sheet(book),
      contains(
        '<rowBreaks count="2" manualBreakCount="2">'
        '<brk id="8" max="16383" man="1"/><brk id="18" max="16383" man="1"/>'
        '</rowBreaks><colBreaks count="1" manualBreakCount="1">'
        '<brk id="6" max="1048575" man="1"/></colBreaks>',
      ),
    );
    // The rows of the first page break's next page go: the break goes.
    _edit(book, _deleteRows(9, 1));
    expect(
      _sheet(book),
      contains(
        '<rowBreaks count="1" manualBreakCount="1">'
        '<brk id="17" max="16383" man="1"/></rowBreaks>',
      ),
    );
  });

  test('an Excel 2010 validation shifts its xm:sqref and xm:f, goes when '
      'wholly deleted, and undoes', () {
    String ext(String validations) =>
        '<extLst><ext uri="{CCE6A557-97BC-4b89-ADB6-D9C93CAAB3DF}" '
        'xmlns:x14="$_x14"><x14:dataValidations count="2" '
        'xmlns:xm="$_xm">$validations</x14:dataValidations></ext></extLst>';
    String validation(String f, String sqref) =>
        '<x14:dataValidation type="list"><x14:formula1><xm:f>$f</xm:f>'
        '</x14:formula1><xm:sqref>$sqref</xm:sqref></x14:dataValidation>';
    final String before = ext(
      validation(r'Other!$A$1:$A$3', 'B2') +
          validation(r'S!$D$5:$D$9', 'C5:C9'),
    );
    final XlsxWorkbook book = XlsxWorkbook.open(_package(before));
    final ChangeSet set = _edit(book, _deleteRows(2, 2));
    expect(
      _sheet(book),
      contains(
        '<x14:dataValidations count="1" xmlns:xm="$_xm">'
        '${validation(r'S!$D$3:$D$7', 'C3:C7')}</x14:dataValidations>',
      ),
    );
    changeLogOf(book).revertSet(set);
    expect(
      _sheet(book),
      contains(
        '<x14:dataValidations count="2" xmlns:xm="$_xm">'
        '${validation(r'Other!$A$1:$A$3', 'B2')}'
        '${validation(r'S!$D$5:$D$9', 'C5:C9')}</x14:dataValidations>',
      ),
    );
    _edit(book, _deleteRows(1, 20));
    expect(_sheet(book), isNot(contains('extLst')));
  });

  test('a sort state shifts with its filter and goes with it', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<autoFilter ref="A2:C9"><sortState ref="A3:C9">'
        '<sortCondition ref="B3:B9"/></sortState></autoFilter>'
        '<sortState ref="A3:C9"><sortCondition descending="1" ref="C3:C9"/>'
        '<sortCondition ref="A3:A9"/></sortState>',
        names:
            '<definedName name="_xlnm._FilterDatabase" localSheetId="0" '
            r'hidden="1">S!$A$2:$C$9</definedName>',
      ),
    );
    _edit(book, _insertRows(1, 1));
    _edit(book, _deleteColumns(1, 1));
    expect(
      _sheet(book),
      contains(
        '<autoFilter ref="A3:B10"><sortState ref="A4:B10">'
        '<sortCondition ref="A4:A10"/></sortState></autoFilter>'
        '<sortState ref="A4:B10"><sortCondition descending="1" '
        'ref="B4:B10"/></sortState>',
      ),
    );
    final ChangeSet set = _edit(book, _deleteRows(1, 20));
    expect(_sheet(book), isNot(contains('autoFilter')));
    expect(_sheet(book), isNot(contains('sortState')));
    expect(_part(book, 'xl/workbook.xml'), isNot(contains('_FilterDatabase')));
    changeLogOf(book).revertSet(set);
    expect(_part(book, 'xl/workbook.xml'), contains('_FilterDatabase'));
  });

  test("a break's min and max shift on the other axis", () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<rowBreaks count="1" manualBreakCount="1">'
        '<brk id="10" min="2" max="6" man="1"/></rowBreaks>'
        '<colBreaks count="2" manualBreakCount="2">'
        '<brk id="4" max="1048575" man="1"/>'
        '<brk id="5" min="3" max="20" man="1"/></colBreaks>',
      ),
    );
    _edit(book, _insertRows(2, 2));
    _edit(book, _deleteColumns(1, 2));
    expect(
      _sheet(book),
      contains(
        '<rowBreaks count="1" manualBreakCount="1">'
        '<brk id="12" min="0" max="4" man="1"/></rowBreaks>'
        '<colBreaks count="2" manualBreakCount="2">'
        '<brk id="2" max="1048575" man="1"/>'
        '<brk id="3" min="5" max="22" man="1"/></colBreaks>',
      ),
    );
  });
}
