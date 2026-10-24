import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

void main() {
  test('100,000 warnings on one column aggregate into one', () {
    final WarningCollector c = WarningCollector();
    for (var r = 0; r < 100000; r++) {
      c.add(
        XlsxWarningCode.invalidCharactersRemoved,
        sheet: 'Data',
        cell: 'B${r + 1}',
      );
    }
    expect(c.warnings, hasLength(1));
    expect(c.warnings.single.count, 100000);
    expect(c.warnings.single.cells, <String>[
      'B1',
      'B2',
      'B3',
      'B4',
      'B5',
      'B6',
      'B7',
      'B8',
      'B9',
      'B10',
    ]);
  });

  test('different sheets and codes stay apart, in first-occurrence order', () {
    final WarningCollector c = WarningCollector()
      ..add(XlsxWarningCode.textTruncated, sheet: 'A', cell: 'A1')
      ..add(XlsxWarningCode.invalidCharactersRemoved, sheet: 'B', cell: 'A1')
      ..add(XlsxWarningCode.invalidCharactersRemoved, sheet: 'A', cell: 'A2')
      ..add(XlsxWarningCode.textTruncated, sheet: 'A', cell: 'A3');
    expect(
      c.warnings.map((XlsxWarning w) => (w.code, w.sheet, w.count)).toList(),
      <(XlsxWarningCode, String, int)>[
        (XlsxWarningCode.textTruncated, 'A', 2),
        (XlsxWarningCode.invalidCharactersRemoved, 'B', 1),
        (XlsxWarningCode.invalidCharactersRemoved, 'A', 1),
      ],
    );
  });

  test('sheet-name warnings carry the original name, one per call', () {
    final WarningCollector c = WarningCollector()
      ..add(XlsxWarningCode.sheetNameChanged, sheet: 'a_b', originalName: 'a/b')
      ..add(
        XlsxWarningCode.sheetNameChanged,
        sheet: 'a_b (2)',
        originalName: 'a:b',
      );
    expect(c.warnings, hasLength(2));
    expect(c.warnings.first.originalName, 'a/b');
    expect(c.warnings.first.cells, isEmpty);
    expect(c.warnings.first.count, 1);
  });

  test('the warnings list cannot be modified', () {
    final WarningCollector c = WarningCollector()
      ..add(XlsxWarningCode.textTruncated, sheet: 'A', cell: 'A1');
    expect(() => c.warnings.clear(), throwsUnsupportedError);
    expect(() => c.warnings.single.cells.add('Z9'), throwsUnsupportedError);
  });

  test('cells and warnings return the same view on every call', () {
    final WarningCollector c = WarningCollector()
      ..add(XlsxWarningCode.textTruncated, sheet: 'A', cell: 'A1');
    expect(identical(c.warnings, c.warnings), isTrue);
    expect(identical(c.warnings.single.cells, c.warnings.single.cells), isTrue);
  });

  test('the views follow later additions', () {
    final WarningCollector c = WarningCollector()
      ..add(XlsxWarningCode.textTruncated, sheet: 'A', cell: 'A1');
    final List<XlsxWarning> warnings = c.warnings;
    final List<String> cells = warnings.single.cells;
    c.add(XlsxWarningCode.textTruncated, sheet: 'A', cell: 'A2');
    c.add(XlsxWarningCode.invalidCharactersRemoved, sheet: 'A', cell: 'A3');
    expect(cells, <String>['A1', 'A2']);
    expect(warnings, hasLength(2));
  });
}
