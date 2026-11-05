import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/validation_elements.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

XlsxRange _r(String ref) => XlsxRange.parse(ref);

String _sheet(String body) =>
    '<worksheet xmlns="$mainNs"><sheetData/>$body</worksheet>';

XlsxWorkbook _open(String body) =>
    XlsxWorkbook.open(buildWorkbook(<String, String>{'S': _sheet(body)}));

String _xml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

String _group(String xml) =>
    RegExp(
      '<dataValidations[^>]*/>|<dataValidations[ >].*?</dataValidations>',
    ).firstMatch(xml)?.group(0) ??
    '';

int _invalid(XlsxWorkbook book) => book.warnings
    .where((XlsxWarning w) => w.code == XlsxWarningCode.featureEntryInvalid)
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

/// The validations the fixture `m3_validation` was written with.
List<XlsxDataValidation> _fixtureValidations() {
  XlsxRange input(int row) => XlsxRange(row, 1);
  return <XlsxDataValidation>[
    XlsxDataValidation.list(
      <XlsxRange>[input(1)],
      <String>['Fish', 'say "hi"', 'R&D'],
    ),
    XlsxDataValidation.listFrom(<XlsxRange>[input(2)], r'$D$2:$D$4'),
    XlsxDataValidation.whole(
      <XlsxRange>[input(3)],
      XlsxComparison.between,
      1,
      b: 10,
      promptTitle: 'Count',
      prompt: 'Enter a whole number from 1 to 10.',
      errorTitle: 'Not allowed',
      error: 'Use 1 to 10.',
    ),
    XlsxDataValidation.decimal(
      <XlsxRange>[input(4)],
      XlsxComparison.greaterThan,
      0,
    ),
    XlsxDataValidation.date(
      <XlsxRange>[input(5)],
      XlsxComparison.greaterThan,
      const XlsxDate(2026, 10, 24),
    ),
    XlsxDataValidation.time(
      <XlsxRange>[input(6)],
      XlsxComparison.lessThan,
      const Duration(hours: 12),
    ),
    XlsxDataValidation.textLength(
      <XlsxRange>[input(7)],
      XlsxComparison.lessThanOrEqual,
      5,
    ),
    XlsxDataValidation.custom(
      <XlsxRange>[input(8)],
      'ISEVEN(B9)',
      errorStyle: XlsxValidationErrorStyle.warning,
      errorTitle: 'Odd',
      error: 'The number is not even.',
    ),
    XlsxDataValidation.any(
      <XlsxRange>[input(9)],
      promptTitle: 'Note',
      prompt: 'Anything goes here.',
    ),
  ];
}

XlsxWorkbook _fixtureBook() => XlsxWorkbook.open(
  allFixtures().firstWhere((Fixture f) => f.name == 'm3_validation').build(),
);

void main() {
  test('reads m3_validation to the fixture values, in order', () {
    final XlsxWorkbook book = _fixtureBook();
    expect(book.sheets.single.dataValidations, _fixtureValidations());
    expect(_invalid(book), 0);
  });

  test('parseSqref reads ranges and returns null for bad text', () {
    expect(parseSqref('A1 C3:D4'), <XlsxRange>[_r('A1'), _r('C3:D4')]);
    expect(parseSqref(' A1\tB2 \n'), <XlsxRange>[_r('A1'), _r('B2')]);
    expect(parseSqref(''), isNull);
    expect(parseSqref('   '), isNull);
    expect(parseSqref('???'), isNull);
    expect(parseSqref('A1 ???'), isNull);
    expect(parseSqref('A:A'), isNull);
    expect(parseSqref('XFE1'), isNull);
  });

  test('a file element maps through the schema defaults', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="2">'
      '<dataValidation sqref="A1"/>'
      '<dataValidation type="whole" operator="equal" showDropDown="1" '
      'allowBlank="true" showErrorMessage="1" errorTitle="a_x0042_c" '
      'sqref="B2 D4:E5"><formula1>_x0031_0</formula1></dataValidation>'
      '</dataValidations>',
    );
    expect(book.sheets.single.dataValidations, <XlsxDataValidation>[
      XlsxDataValidation.any(
        <XlsxRange>[_r('A1')],
        allowBlank: false,
        showInputMessage: false,
        showErrorMessage: false,
      ),
      XlsxDataValidation(
        <XlsxRange>[_r('B2'), _r('D4:E5')],
        XlsxValidationType.whole,
        comparison: XlsxComparison.equal,
        formula1: '10',
        showDropDownArrow: false,
        showInputMessage: false,
        errorTitle: 'aBc',
      ),
    ]);
  });

  test('add writes what the writer writes', () {
    final XlsxWorkbook book = _open('');
    final XlsxSheet sheet = book.sheets.single;
    final List<XlsxDataValidation> all = _fixtureValidations();
    for (final XlsxDataValidation v in all) {
      sheet.addDataValidation(v);
    }
    expect(sheet.dataValidations, all);
    final XlsxWriter writer = XlsxWriter();
    final XlsxSheetWriter w = writer.addSheet('S');
    all.forEach(w.dataValidation);
    final String written = _group(
      partText(writer.close().bytes, 'xl/worksheets/sheet1.xml'),
    );
    expect(_group(_xml(book)), written);
    expect(_xml(book).indexOf('</sheetData>'), lessThan(written.length));
    // Reading the saved file gives the same values.
    expect(
      XlsxWorkbook.open(book.save().bytes).sheets.single.dataValidations,
      all,
    );
  });

  test('add joins an existing group and recomputes count', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="5" disablePrompts="1" xWindow="3" '
      'yWindow="4"><dataValidation type="list" imeMode="on" sqref="A1">'
      '<formula1>"a,b"</formula1></dataValidation></dataValidations>',
    );
    book.sheets.single.addDataValidation(
      XlsxDataValidation.any(<XlsxRange>[_r('C3')]),
    );
    final String group = _group(_xml(book));
    expect(group, contains('count="2"'));
    expect(group, contains('disablePrompts="1"'));
    expect(group, contains('xWindow="3"'));
    expect(group, contains('yWindow="4"'));
    expect(group, contains('imeMode="on"'));
    expect(group, contains('<dataValidation allowBlank="1"'));
  });

  test('an overlapping range throws; nothing changes', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="1"><dataValidation type="whole" '
      'sqref="A1:B2"><formula1>1</formula1></dataValidation>'
      '</dataValidations>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.dataValidations;
    final String before = _xml(book);
    expect(
      () => sheet.addDataValidation(
        XlsxDataValidation.any(<XlsxRange>[_r('B2:C3')]),
      ),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'ranges[0]')),
    );
    expect(
      () => sheet.addDataValidation(XlsxDataValidation.any(<XlsxRange>[])),
      throwsArgumentError,
    );
    expect(_xml(book), before);
    expect(sheet.dataValidations, hasLength(1));
  });

  test('removing keeps the others as written', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="3">'
      '<dataValidation type="whole" imeMode="on" sqref="A1">'
      '<formula1>1</formula1></dataValidation>'
      '<dataValidation type="list" sqref="B1"><formula1>"x,y"</formula1>'
      '</dataValidation>'
      '<dataValidation type="whole"   sqref="C1"><formula1>2</formula1>'
      '</dataValidation></dataValidations>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.removeDataValidation(
      XlsxDataValidation.list(
        <XlsxRange>[_r('B1')],
        <String>['x', 'y'],
        allowBlank: false,
        showInputMessage: false,
        showErrorMessage: false,
      ),
    );
    expect(
      _group(_xml(book)),
      '<dataValidations count="2">'
      '<dataValidation type="whole" imeMode="on" sqref="A1">'
      '<formula1>1</formula1></dataValidation>'
      '<dataValidation type="whole"   sqref="C1"><formula1>2</formula1>'
      '</dataValidation></dataValidations>',
    );
    expect(sheet.dataValidations, hasLength(2));
  });

  test('removing the last one removes the group; none equal throws', () {
    final XlsxWorkbook book = _open('');
    final XlsxSheet sheet = book.sheets.single;
    final XlsxDataValidation v = XlsxDataValidation.custom(<XlsxRange>[
      _r('A1'),
    ], '=ISEVEN(A1)');
    expect(() => sheet.removeDataValidation(v), throwsArgumentError);
    sheet.addDataValidation(v);
    expect(
      () => sheet.removeDataValidation(
        XlsxDataValidation.custom(<XlsxRange>[_r('A2')], 'ISEVEN(A1)'),
      ),
      throwsArgumentError,
    );
    final String added = _xml(book);
    sheet.removeDataValidation(
      XlsxDataValidation.custom(<XlsxRange>[_r('A1')], 'ISEVEN(A1)'),
    );
    expect(_xml(book), isNot(contains('dataValidations')));
    expect(sheet.dataValidations, isEmpty);
    expect(added, contains('<formula1>ISEVEN(A1)</formula1>'));
  });

  test('a value read from a formula with a leading = removes', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="2">'
      '<dataValidation type="custom" sqref="A1"><formula1>=A1&gt;0</formula1>'
      '</dataValidation>'
      '<dataValidation type="whole" operator="greaterThan" sqref="A2">'
      '<formula1>=B1</formula1></dataValidation></dataValidations>',
    );
    final XlsxSheet sheet = book.sheets.single;
    for (final XlsxDataValidation read in sheet.dataValidations.toList()) {
      sheet.removeDataValidation(read);
    }
    expect(sheet.dataValidations, isEmpty);
    expect(_xml(book), isNot(contains('dataValidation')));
  });

  test('a hand-built value removes an entry that has a leading =', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="1">'
      '<dataValidation type="custom" allowBlank="1" showInputMessage="1" '
      'showErrorMessage="1" sqref="A1"><formula1>=A1&gt;0</formula1>'
      '</dataValidation></dataValidations>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.removeDataValidation(
      XlsxDataValidation.custom(<XlsxRange>[_r('A1')], 'A1>0'),
    );
    expect(sheet.dataValidations, isEmpty);
  });

  test('a validation added under a prefixed worksheet stays '
      'SpreadsheetML', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': '<x:worksheet xmlns:x="$mainNs"><x:sheetData/></x:worksheet>',
      }),
    );
    final XlsxDataValidation validation = XlsxDataValidation.custom(<XlsxRange>[
      _r('A1'),
    ], 'A1>0');
    book.sheets.single.addDataValidation(validation);
    final Uint8List saved = book.save().bytes;
    final String xml = partText(saved, 'xl/worksheets/sheet1.xml');
    expect(xml, contains('<x:dataValidations count="1">'));
    expect(xml, contains(' xmlns="$mainNs"'));
    expect(xml, isNot(contains('xmlns=""')));
    expect(
      XlsxWorkbook.open(saved).sheets.single.dataValidations,
      <XlsxDataValidation>[normalizedValidation(validation)],
    );
  });

  test('type="none" reads as any, and an equal add is refused', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="2">'
      '<dataValidation type="none" allowBlank="1" showInputMessage="1" '
      'promptTitle="T" prompt="P" sqref="A1"/>'
      '<dataValidation allowBlank="1" sqref="A2"/></dataValidations>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(_invalid(book), 0);
    final List<XlsxDataValidation> read = sheet.dataValidations.toList();
    expect(read, hasLength(2));
    expect(read.first.type, XlsxValidationType.any);
    expect(read.first.prompt, 'P');
    expect(read.last.type, XlsxValidationType.any);
    expect(
      () => sheet.addDataValidation(read.first),
      throwsArgumentError,
      reason: 'it overlaps itself',
    );
    sheet.removeDataValidation(read.first);
    final String group = _group(_xml(book));
    expect(group, isNot(contains('type="none"')));
    expect(group, contains('sqref="A2"'));
    sheet.addDataValidation(read.first);
    expect(sheet.dataValidations.last, read.first);
  });

  test('kept attributes stay', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="1" disablePrompts="1"><dataValidation '
      'type="whole" imeMode="hiragana" sqref="A1"><formula1>1</formula1>'
      '</dataValidation></dataValidations>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.addDataValidation(XlsxDataValidation.any(<XlsxRange>[_r('C1')]));
    sheet.removeDataValidation(XlsxDataValidation.any(<XlsxRange>[_r('C1')]));
    expect(
      _group(_xml(book)),
      '<dataValidations count="1" disablePrompts="1"><dataValidation '
      'type="whole" imeMode="hiragana" sqref="A1"><formula1>1</formula1>'
      '</dataValidation></dataValidations>',
    );
  });

  test('bad values are kept and reported', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="3">'
      '<dataValidation type="whole" sqref="???"><formula1>1</formula1>'
      '</dataValidation>'
      '<dataValidation type="zigzag" sqref="B1"/>'
      '<dataValidation type="whole" sqref="C1"><formula1>3</formula1>'
      '</dataValidation></dataValidations>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.dataValidations, hasLength(1));
    expect(sheet.dataValidations.single.ranges, <XlsxRange>[_r('C1')]);
    sheet.dataValidations;
    expect(_invalid(book), 2);
    expect(
      book.warnings.map((XlsxWarning w) => w.detail),
      everyElement('dataValidation'),
    );
    sheet.addDataValidation(XlsxDataValidation.any(<XlsxRange>[_r('E1')]));
    final String group = _group(_xml(book));
    expect(group, contains('count="4"'));
    expect(group, contains('sqref="???"'));
    expect(group, contains('type="zigzag"'));
    sheet.removeDataValidation(
      XlsxDataValidation.whole(
        <XlsxRange>[_r('C1')],
        XlsxComparison.between,
        3,
        allowBlank: false,
        showInputMessage: false,
        showErrorMessage: false,
      ),
    );
    final String after = _group(_xml(book));
    expect(after, contains('count="3"'));
    expect(after, contains('sqref="???"'));
  });

  test('an edit undoes and redoes', () {
    final XlsxWorkbook book = _open('');
    final XlsxSheet sheet = book.sheets.single;
    final ChangeLog log = changeLogOf(book);
    sheet.dataValidations;
    final String before = _xml(book);
    final ChangeSet add = log.transaction(
      () => sheet.addDataValidation(
        XlsxDataValidation.any(<XlsxRange>[_r('A1')]),
      ),
    );
    final String added = _xml(book);
    log.revertSet(add);
    expect(_xml(book), before);
    expect(sheet.dataValidations, isEmpty);
    log.reapplySet(add);
    expect(_xml(book), added);
    expect(sheet.dataValidations, hasLength(1));
  });

  test('a second dataValidations stays opaque', () {
    final XlsxWorkbook book = _open(
      '<dataValidations count="1"><dataValidation sqref="A1"/>'
      '</dataValidations><dataValidations count="1">'
      '<dataValidation sqref="B1"/></dataValidations>',
    );
    expect(book.sheets.single.dataValidations, hasLength(1));
    expect(book.sheets.single.dataValidations.single.ranges, [_r('A1')]);
  });
}
