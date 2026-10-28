import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';

String _sheet(String merges, {String rows = ''}) =>
    '<worksheet xmlns="$mainNs"><sheetData>$rows</sheetData>$merges'
    '</worksheet>';

XlsxReader _reader(String xml) =>
    XlsxReader(buildWorkbook(<String, String?>{'S': xml}));

int _count(XlsxReader r, XlsxWarningCode code) =>
    r.warnings.where((XlsxWarning w) => w.code == code).length;

void main() {
  test('reads merges after sheetData', () {
    final XlsxReader r = _reader(
      _sheet(
        '<mergeCells count="2"><mergeCell ref="A1:B2"/>'
        '<mergeCell ref="C3:C5"/></mergeCells>',
        rows: '<row r="1"><c r="A1"><v>1</v></c></row>',
      ),
    );
    expect(r.mergesAt(0), <XlsxRange>[
      XlsxRange.parse('A1:B2'),
      XlsxRange.parse('C3:C5'),
    ]);
    expect(r.warnings, isEmpty);
  });

  test('prefixed and foreign elements', () {
    final XlsxReader r = _reader(
      '<x:worksheet xmlns:x="$mainNs" xmlns:o="urn:other">'
      '<x:sheetData><x:row r="1"/></x:sheetData>'
      '<x:mergeCells><o:mergeCell ref="Z9:Z10"/>'
      '<x:mergeCell ref="B1:C1"/></x:mergeCells>'
      '<o:mergeCells><x:mergeCell ref="D1:E1"/></o:mergeCells>'
      '</x:worksheet>',
    );
    expect(r.mergesAt(0), <XlsxRange>[XlsxRange.parse('B1:C1')]);
  });

  test('an invalid ref is skipped and warned', () {
    final XlsxReader r = _reader(
      _sheet(
        '<mergeCells><mergeCell ref="A1:"/><mergeCell ref="ZZZZ1"/>'
        '<mergeCell/><mergeCell ref="B2"/></mergeCells>',
      ),
    );
    expect(r.mergesAt(0), <XlsxRange>[XlsxRange.parse('B2')]);
    expect(_count(r, XlsxWarningCode.mergeRangeInvalid), 1);
    final XlsxWarning w = r.warnings.single;
    expect(w.sheet, 'S');
    expect(w.cells, isEmpty);
    expect(w.count, 3);
  });

  test('writer merges round trip', () {
    final XlsxWriter w = XlsxWriter();
    w.addSheet('M')
      ..row(<Object?>['a', 'b'])
      ..merge(XlsxRange.parse('A1:B1'))
      ..merge(XlsxRange.parse('D4:E6'));
    final XlsxReader r = XlsxReader(w.close().bytes);
    expect(r.merges('M'), <XlsxRange>[
      XlsxRange.parse('A1:B1'),
      XlsxRange.parse('D4:E6'),
    ]);
  });

  test('merges are cached and unmodifiable', () {
    final XlsxReader r = _reader(
      _sheet('<mergeCells><mergeCell ref="A1:B2"/></mergeCells>'),
    );
    final List<XlsxRange> first = r.mergesAt(0);
    expect(r.mergesAt(0), same(first));
    expect(() => first.add(XlsxRange.parse('A1')), throwsUnsupportedError);
  });

  test('merges before rows, warnings kept', () {
    final XlsxReader r = _reader(
      _sheet(
        '<mergeCells><mergeCell ref="bad"/></mergeCells>',
        rows: '<row r="1"><c r="A1"><v>1</v></c></row>',
      ),
    );
    r.mergesAt(0);
    expect(_count(r, XlsxWarningCode.mergeRangeInvalid), 1);
    r.rowsAt(0).toList();
    expect(_count(r, XlsxWarningCode.mergeRangeInvalid), 1);
    r.rowsAt(0).toList();
    expect(_count(r, XlsxWarningCode.mergeRangeInvalid), 1);
    r.mergesAt(0);
    expect(_count(r, XlsxWarningCode.mergeRangeInvalid), 1);
  });

  test('a sheet without a part has no merges', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{'Gone': null}),
    );
    expect(r.mergesAt(0), isEmpty);
  });

  test('a non-worksheet root and an empty sheet have none', () {
    for (final String xml in <String>[
      '<chartsheet xmlns="$mainNs"><mergeCells><mergeCell ref="A1:B2"/>'
          '</mergeCells></chartsheet>',
      '<worksheet xmlns="urn:other"><mergeCells><mergeCell ref="A1:B2"/>'
          '</mergeCells></worksheet>',
      '<worksheet xmlns="$mainNs"/>',
    ]) {
      expect(_reader(xml).mergesAt(0), isEmpty, reason: xml);
    }
  });

  test('a Strict worksheet is unsupportedFormat', () {
    final XlsxReader r = _reader(
      '<worksheet xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main"/>',
    );
    expect(
      () => r.mergesAt(0),
      throwsA(
        isA<XlsxReadException>()
            .having(
              (XlsxReadException e) => e.reason,
              'reason',
              XlsxReadFailure.unsupportedFormat,
            )
            .having((XlsxReadException e) => e.part, 'part', sheetEntry(0)),
      ),
    );
  });

  test('malformed XML is malformedXml naming the part', () {
    final XlsxReader r = _reader(
      '<worksheet xmlns="$mainNs"><mergeCells><mergeCell ref="A1:B2">',
    );
    expect(
      () => r.mergesAt(0),
      throwsA(
        isA<XlsxReadException>()
            .having(
              (XlsxReadException e) => e.reason,
              'reason',
              XlsxReadFailure.malformedXml,
            )
            .having((XlsxReadException e) => e.part, 'part', sheetEntry(0)),
      ),
    );
  });

  test('unknown name throws ArgumentError, bad index RangeError', () {
    final XlsxReader r = _reader(_sheet(''));
    expect(() => r.merges('Nope'), throwsArgumentError);
    expect(() => r.mergesAt(1), throwsRangeError);
    expect(() => r.mergesAt(-1), throwsRangeError);
  });
}
