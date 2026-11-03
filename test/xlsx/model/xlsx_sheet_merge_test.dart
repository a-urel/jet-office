import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../read/support/producers.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

String _sheet(String body, {String after = ''}) =>
    '<worksheet xmlns="$mainNs"><sheetData/>$body$after</worksheet>';

XlsxWorkbook _open(String body, {String after = '', XlsxReadLimits? limits}) =>
    XlsxWorkbook.open(
      buildWorkbook(<String, String>{'S': _sheet(body, after: after)}),
      limits: limits ?? const XlsxReadLimits(),
    );

String _xml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

String _mergeCells(String xml) =>
    RegExp(
      '<mergeCells[^>]*/>|<mergeCells[ >].*?</mergeCells>',
    ).firstMatch(xml)?.group(0) ??
    '';

XlsxRange _r(String ref) => XlsxRange.parse(ref);

List<XlsxWarning> _invalid(XlsxWorkbook book) => <XlsxWarning>[
  for (final XlsxWarning w in book.warnings)
    if (w.code == XlsxWarningCode.mergeRangeInvalid) w,
];

void main() {
  test('merges read like XlsxReader.merges', () {
    final List<(String, Uint8List)> files = <(String, Uint8List)>[
      for (final Fixture f in allFixtures()) (f.name, f.build()),
      for (final ProducerFile p in producerFiles()) (p.name, p.bytes),
    ];
    int withMerges = 0;
    for (final (String name, Uint8List bytes) in files) {
      final XlsxReader reader = XlsxReader(bytes);
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      for (int i = 0; i < reader.sheets.length; i++) {
        final List<XlsxRange> expected = reader.mergesAt(i);
        if (expected.isNotEmpty) withMerges++;
        expect(book.sheets[i].merges, expected, reason: '$name sheet $i');
      }
      expect(
        _invalid(book).fold<int>(0, (int s, XlsxWarning w) => s + w.count),
        reader.warnings
            .where((w) => w.code == XlsxWarningCode.mergeRangeInvalid)
            .fold<int>(0, (int s, XlsxWarning w) => s + w.count),
        reason: name,
      );
    }
    expect(withMerges, greaterThan(0));
  });

  test('merges are unmodifiable and empty without a mergeCells', () {
    final XlsxWorkbook book = _open('');
    expect(book.sheets.single.merges, isEmpty);
    expect(() => book.sheets.single.merges.add(_r('A1:B1')), throwsA(anything));
  });

  test('merge and unmerge write what the writer writes', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('S')
      ..merge(_r('A1:B2'))
      ..merge(_r('D4:E4'));
    final String expected = _mergeCells(
      partText(writer.close().bytes, 'xl/worksheets/sheet1.xml'),
    );

    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S')
      ..merge(_r('A1:B2'))
      ..merge(_r('D4:E4'));
    expect(_mergeCells(_xml(book)), expected);
    expect(sheet.merges, <XlsxRange>[_r('A1:B2'), _r('D4:E4')]);
    final String xml = _xml(book);
    expect(
      xml.indexOf('<mergeCells'),
      greaterThan(xml.indexOf('</sheetData>')),
    );

    sheet.unmerge(_r('A1:B2'));
    expect(
      _mergeCells(_xml(book)),
      '<mergeCells count="1">'
      '<mergeCell ref="D4:E4"/></mergeCells>',
    );
    sheet.unmerge(_r('D4:E4'));
    expect(_xml(book), isNot(contains('mergeCells')));
    expect(sheet.merges, isEmpty);
    final XlsxWorkbook reopened = XlsxWorkbook.open(book.save().bytes);
    expect(reopened.sheets.single.merges, isEmpty);
  });

  test('a merge is written in schema position and kept in file order', () {
    final XlsxWorkbook book = _open(
      '',
      after:
          '<pageMargins left="1" right="1" top="1" bottom="1" '
          'header="0" footer="0"/>',
    );
    book.sheets.single.merge(_r('A1:B1'));
    final String xml = _xml(book);
    expect(xml.indexOf('<mergeCells'), lessThan(xml.indexOf('<pageMargins')));
    expect(xml.indexOf('<mergeCells'), greaterThan(xml.indexOf('</sheetData')));
  });

  test('an existing group keeps its own markup and recomputes count', () {
    final XlsxWorkbook book = _open(
      '<mergeCells count="9" x="1"><mergeCell ref="A1:B2" extra="e"/>'
      '</mergeCells>',
    );
    // Untouched: as written.
    expect(
      _mergeCells(_xml(book)),
      '<mergeCells count="9" x="1"><mergeCell ref="A1:B2" extra="e"/>'
      '</mergeCells>',
    );
    book.sheets.single.merge(_r('C1:D1'));
    expect(
      _mergeCells(_xml(book)),
      '<mergeCells count="2" x="1"><mergeCell ref="A1:B2" extra="e"/>'
      '<mergeCell ref="C1:D1"/></mergeCells>',
    );
  });

  test('an overlap throws naming both ranges; nothing changes', () {
    final XlsxWorkbook book = _open(
      '<mergeCells count="1"><mergeCell ref="B2:C3"/></mergeCells>',
    );
    final XlsxSheet sheet = book.sheets.single..merges;
    final String before = _xml(book);
    expect(
      () => sheet.merge(_r('C3:D4')),
      throwsA(
        isA<ArgumentError>()
            .having((ArgumentError e) => e.name, 'name', 'range')
            .having(
              (ArgumentError e) => e.message,
              'message',
              allOf(contains('C3:D4'), contains('B2:C3')),
            ),
      ),
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_xml(book), before);
    expect(sheet.merges, <XlsxRange>[_r('B2:C3')]);
  });

  test('merge refuses a single cell, outside the sheet and reversed', () {
    final XlsxSheet sheet = _open('').sheets.single;
    expect(() => sheet.merge(_r('A1')), throwsArgumentError);
    expect(
      () => sheet.merge(const XlsxRange(0, 0, 0, 16384)),
      throwsArgumentError,
    );
    expect(() => sheet.merge(const XlsxRange(2, 2, 1, 1)), throwsArgumentError);
    expect(sheet.merges, isEmpty);
  });

  test('merge refuses an overlap with a typed table', () {
    final XlsxWriter writer = XlsxWriter();
    final XlsxSheetWriter s = writer.addSheet('S')
      ..table(
        XlsxTable('Sales', _r('A1:B3'), const <XlsxTableColumn>[
          XlsxTableColumn('Region'),
          XlsxTableColumn('Amount'),
        ]),
      )
      ..row(<Object?>['Region', 'Amount'])
      ..row(<Object?>['N', 1])
      ..row(<Object?>['S', 2]);
    expect(s, isNotNull);
    final XlsxWorkbook book = XlsxWorkbook.open(writer.close().bytes);
    final XlsxSheet sheet = book.sheets.single;
    expect(
      () => sheet.merge(_r('B3:C4')),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message,
          'message',
          allOf(contains('B3:C4'), contains('Sales'), contains('A1:B3')),
        ),
      ),
    );
    sheet.merge(_r('D1:E2'));
    expect(sheet.merges, <XlsxRange>[_r('D1:E2')]);
  });

  test('unmerge of a range that is not merged throws', () {
    final XlsxWorkbook book = _open(
      '<mergeCells count="1"><mergeCell ref="B2:C3"/></mergeCells>',
    );
    final XlsxSheet sheet = book.sheets.single..merges;
    final String before = _xml(book);
    expect(() => sheet.unmerge(_r('B2:C4')), throwsArgumentError);
    expect(() => sheet.unmerge(_r('A1:B1')), throwsArgumentError);
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_xml(book), before);
  });

  test('unmerge keeps the cell values', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S')
      ..setCell(0, 0, 'a')
      ..setCell(0, 1, 'b')
      ..merge(_r('A1:B1'))
      ..unmerge(_r('A1:B1'));
    expect(sheet.cellAt(0, 0)?.value, 'a');
    expect(sheet.cellAt(0, 1)?.value, 'b');
  });

  test('an unreadable mergeCell is kept and warned', () {
    final XlsxWorkbook book = _open(
      '<mergeCells count="3"><mergeCell ref="A1:"/>'
      '<mergeCell ref="B2:C3"/><mergeCell/></mergeCells>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.merges, <XlsxRange>[_r('B2:C3')]);
    expect(_invalid(book).single.count, 2);
    // Unedited: as written.
    expect(
      _mergeCells(_xml(book)),
      '<mergeCells count="3"><mergeCell ref="A1:"/>'
      '<mergeCell ref="B2:C3"/><mergeCell/></mergeCells>',
    );
    sheet.merge(_r('E1:F1'));
    expect(
      _mergeCells(_xml(book)),
      '<mergeCells count="4"><mergeCell ref="A1:"/>'
      '<mergeCell ref="B2:C3"/><mergeCell/><mergeCell ref="E1:F1"/>'
      '</mergeCells>',
    );
    sheet.unmerge(_r('B2:C3'));
    sheet.unmerge(_r('E1:F1'));
    // The unreadable ones keep the group.
    expect(
      _mergeCells(_xml(book)),
      '<mergeCells count="2"><mergeCell ref="A1:"/><mergeCell/>'
      '</mergeCells>',
    );
    expect(_invalid(book).single.count, 2);
  });

  test('an empty group is removed once edited, not before', () {
    final XlsxWorkbook book = _open('<mergeCells count="0"/>');
    expect(_mergeCells(_xml(book)), '<mergeCells count="0"/>');
    final XlsxSheet sheet = book.sheets.single
      ..merge(_r('A1:B1'))
      ..unmerge(_r('A1:B1'));
    expect(_xml(book), isNot(contains('mergeCells')));
    expect(sheet.merges, isEmpty);
  });

  test('prefixed and foreign elements', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S':
            '<x:worksheet xmlns:x="$mainNs" xmlns:o="urn:other">'
            '<x:sheetData/>'
            '<x:mergeCells><o:mergeCell ref="Z9:Z10"/>'
            '<x:mergeCell ref="B1:C1"/></x:mergeCells>'
            '<o:mergeCells><x:mergeCell ref="D1:E1"/></o:mergeCells>'
            '</x:worksheet>',
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.merges, <XlsxRange>[_r('B1:C1')]);
    sheet.merge(_r('F1:G1'));
    final String xml = _xml(book);
    expect(xml, contains('<x:mergeCell ref="F1:G1"/>'));
    expect(xml, contains('<o:mergeCell ref="Z9:Z10"/>'));
    expect(xml, contains('<o:mergeCells>'));
  });

  test('merge and unmerge undo and redo independently of other edits', () {
    final XlsxWorkbook book = _open(
      '<mergeCells count="1"><mergeCell ref="B2:C3"/></mergeCells>',
    );
    final XlsxSheet sheet = book.sheets.single..merges;
    final ChangeLog log = changeLogOf(book);
    final String before = _xml(book);
    final ChangeSet add = log.transaction(() => sheet.merge(_r('E1:F1')));
    final String added = _xml(book);
    final ChangeSet cols = log.transaction(
      () => sheet.setColumn(0, const XlsxColumn(width: 20)),
    );
    final ChangeSet remove = log.transaction(() => sheet.unmerge(_r('B2:C3')));
    log.revertSet(remove);
    expect(sheet.merges, <XlsxRange>[_r('B2:C3'), _r('E1:F1')]);
    // Reverting the first merge leaves the column edit.
    log.revertSet(cols);
    log.revertSet(add);
    expect(_xml(book), before);
    log.reapplySet(add);
    expect(_xml(book), added);
    log.reapplySet(cols);
    log.reapplySet(remove);
    expect(sheet.merges, <XlsxRange>[_r('E1:F1')]);
  });

  test('merging into a sheet without a group undoes to none', () {
    final XlsxWorkbook book = _open('');
    final XlsxSheet sheet = book.sheets.single..merges;
    final ChangeLog log = changeLogOf(book);
    final String before = _xml(book);
    final ChangeSet set = log.transaction(() => sheet.merge(_r('A1:B1')));
    log.revertSet(set);
    expect(_xml(book), before);
    expect(sheet.merges, isEmpty);
    log.reapplySet(set);
    expect(sheet.merges, <XlsxRange>[_r('A1:B1')]);
  });

  test('a sheet that is not a worksheet cannot be merged', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String?>{'S': '<chartsheet xmlns="$mainNs"/>'}),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.merges, isEmpty);
    expect(() => sheet.merge(_r('A1:B1')), throwsStateError);
  });

  test('maxMerges applies on load', () {
    final String many =
        '<mergeCells>${'<mergeCell ref="A1:B2"/>' * 6}</mergeCells>';
    final XlsxWorkbook book = _open(
      many,
      limits: const XlsxReadLimits(maxMerges: 5),
    );
    final XlsxSheet sheet = book.sheets.single;
    for (int attempt = 0; attempt < 2; attempt++) {
      expect(
        () => sheet.merges,
        throwsA(
          isA<XlsxReadException>()
              .having(
                (XlsxReadException e) => e.reason,
                'reason',
                XlsxReadFailure.limitExceeded,
              )
              .having(
                (XlsxReadException e) => e.message,
                'message',
                allOf(contains('maxMerges'), contains('(5)')),
              ),
        ),
      );
    }
    // Up to the limit loads.
    final XlsxWorkbook ok = _open(
      '<mergeCells>${'<mergeCell ref="A1:B2"/>' * 5}</mergeCells>',
      limits: const XlsxReadLimits(maxMerges: 5),
    );
    expect(ok.sheets.single.merges, hasLength(5));
  });
}
