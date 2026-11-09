import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/reference_holders.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';

XlsxWorkbook _open(String name) => XlsxWorkbook.open(
  allFixtures().firstWhere((Fixture f) => f.name == name).build(),
);

const List<String> _sheet = <String>[
  'cells',
  'merges',
  'conditionalFormats',
  'dataValidations',
  'hyperlinks',
  'autoFilter',
  'tables',
  'drawings',
  'notes',
  'views',
];

void main() {
  test('the registry lists every holder of a sheet with every feature', () {
    for (final String name in <String>['m4_objects', 'c1_kinds']) {
      final XlsxWorkbook book = _open(name);
      final List<String> names = <String>[
        for (final ReferenceHolder h in referenceRegistryOf(book).holders())
          h.holderName,
      ];
      expect(names, <String>[
        for (final XlsxSheet _ in book.sheets) ..._sheet,
        'definedNames',
      ], reason: name);
      expect(book.sheets.every(isLoadedSheet), isTrue, reason: name);
    }
  });

  test('a sheet keeps its holders', () {
    final XlsxWorkbook book = _open('m4_objects');
    final XlsxSheet sheet = book.sheets.first;
    expect(sheetReferenceHolders(sheet), same(sheetReferenceHolders(sheet)));
  });

  test('apply passes the mapper and edit to every holder once', () {
    final XlsxWorkbook book = _open('c1_kinds');
    final ReferenceRegistry registry = referenceRegistryOf(book);
    final ReferenceShift edit = ReferenceShift.insert(
      book.sheets.first.name,
      ShiftAxis.rows,
      2,
      1,
    );
    registry.apply(edit, edit);
    for (final ReferenceHolder h in registry.holders()) {
      final PendingReferenceHolder p = h as PendingReferenceHolder;
      expect(p.calls, hasLength(1), reason: h.holderName);
      expect(p.calls.single.mapper, same(edit));
      expect(p.calls.single.edit, same(edit));
    }
  });
}
