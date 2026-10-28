import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

void main() {
  group('XlsxErrorValue', () {
    test('the classic constants carry their codes', () {
      expect(XlsxErrorValue.nullError.code, '#NULL!');
      expect(XlsxErrorValue.div0.code, '#DIV/0!');
      expect(XlsxErrorValue.value.code, '#VALUE!');
      expect(XlsxErrorValue.ref.code, '#REF!');
      expect(XlsxErrorValue.name.code, '#NAME?');
      expect(XlsxErrorValue.num.code, '#NUM!');
      expect(XlsxErrorValue.na.code, '#N/A');
      expect(XlsxErrorValue.classic, <XlsxErrorValue>[
        XlsxErrorValue.nullError,
        XlsxErrorValue.div0,
        XlsxErrorValue.value,
        XlsxErrorValue.ref,
        XlsxErrorValue.name,
        XlsxErrorValue.num,
        XlsxErrorValue.na,
      ]);
    });

    test('isClassic', () {
      for (final XlsxErrorValue e in XlsxErrorValue.classic) {
        expect(e.isClassic, isTrue, reason: e.code);
      }
      expect(const XlsxErrorValue('#SPILL!').isClassic, isFalse);
      expect(const XlsxErrorValue('#n/a').isClassic, isFalse);
    });

    test('equality is by code', () {
      expect(const XlsxErrorValue('#N/A'), XlsxErrorValue.na);
      expect(const XlsxErrorValue('#N/A').hashCode, XlsxErrorValue.na.hashCode);
      expect(XlsxErrorValue.na, isNot(XlsxErrorValue.ref));
      expect(XlsxErrorValue.na, isNot('#N/A'));
    });

    test('toString', () {
      expect(XlsxErrorValue.div0.toString(), 'XlsxErrorValue(#DIV/0!)');
    });
  });

  group('XlsxFormulaGroup', () {
    final XlsxRange range = XlsxRange.parse('B2:B4');

    test('holds kind, range and isMaster', () {
      final XlsxFormulaGroup group = XlsxFormulaGroup(
        XlsxFormulaGroupKind.shared,
        range,
        isMaster: true,
      );
      expect(group.kind, XlsxFormulaGroupKind.shared);
      expect(group.range, range);
      expect(group.isMaster, isTrue);
      expect(XlsxFormulaGroupKind.values, <XlsxFormulaGroupKind>[
        XlsxFormulaGroupKind.shared,
        XlsxFormulaGroupKind.array,
        XlsxFormulaGroupKind.dataTable,
      ]);
    });

    test('equality covers every field', () {
      XlsxFormulaGroup g(
        XlsxFormulaGroupKind kind,
        String ref, {
        bool isMaster = false,
      }) => XlsxFormulaGroup(kind, XlsxRange.parse(ref), isMaster: isMaster);

      final XlsxFormulaGroup a = g(XlsxFormulaGroupKind.array, 'C1:C3');
      expect(a, g(XlsxFormulaGroupKind.array, 'C1:C3'));
      expect(a.hashCode, g(XlsxFormulaGroupKind.array, 'C1:C3').hashCode);
      expect(a, isNot(g(XlsxFormulaGroupKind.shared, 'C1:C3')));
      expect(a, isNot(g(XlsxFormulaGroupKind.array, 'C1:C4')));
      expect(a, isNot(g(XlsxFormulaGroupKind.array, 'C1:C3', isMaster: true)));
    });

    test('toString', () {
      expect(
        XlsxFormulaGroup(
          XlsxFormulaGroupKind.shared,
          range,
          isMaster: true,
        ).toString(),
        'XlsxFormulaGroup(shared, XlsxRange(B2:B4), master)',
      );
      expect(
        XlsxFormulaGroup(
          XlsxFormulaGroupKind.dataTable,
          range,
          isMaster: false,
        ).toString(),
        'XlsxFormulaGroup(dataTable, XlsxRange(B2:B4))',
      );
    });
  });

  group('XlsxReadCell', () {
    test('defaults', () {
      const XlsxReadCell cell = XlsxReadCell(2, 'a');
      expect(cell.column, 2);
      expect(cell.value, 'a');
      expect(cell.formula, isNull);
      expect(cell.formulaGroup, isNull);
      expect(cell.numberFormatId, 0);
      expect(cell.numberFormat, 'General');
      expect(cell.isDate, isFalse);
    });

    test('equality covers every field', () {
      final XlsxFormulaGroup group = XlsxFormulaGroup(
        XlsxFormulaGroupKind.array,
        XlsxRange.parse('A1:A2'),
        isMaster: true,
      );
      final XlsxReadCell full = XlsxReadCell(
        0,
        DateTime.utc(2026, 10, 28),
        formula: 'TODAY()',
        formulaGroup: group,
        numberFormatId: 14,
        numberFormat: 'm/d/yyyy',
        isDate: true,
      );
      final XlsxReadCell same = XlsxReadCell(
        0,
        DateTime.utc(2026, 10, 28),
        formula: 'TODAY()',
        formulaGroup: group,
        numberFormatId: 14,
        numberFormat: 'm/d/yyyy',
        isDate: true,
      );
      expect(full, same);
      expect(full.hashCode, same.hashCode);
      for (final XlsxReadCell other in <XlsxReadCell>[
        XlsxReadCell(
          1,
          DateTime.utc(2026, 10, 28),
          formula: 'TODAY()',
          formulaGroup: group,
          numberFormatId: 14,
          numberFormat: 'm/d/yyyy',
          isDate: true,
        ),
        XlsxReadCell(
          0,
          DateTime.utc(2026, 10, 29),
          formula: 'TODAY()',
          formulaGroup: group,
          numberFormatId: 14,
          numberFormat: 'm/d/yyyy',
          isDate: true,
        ),
        XlsxReadCell(
          0,
          DateTime.utc(2026, 10, 28),
          formulaGroup: group,
          numberFormatId: 14,
          numberFormat: 'm/d/yyyy',
          isDate: true,
        ),
        XlsxReadCell(
          0,
          DateTime.utc(2026, 10, 28),
          formula: 'TODAY()',
          numberFormatId: 14,
          numberFormat: 'm/d/yyyy',
          isDate: true,
        ),
        XlsxReadCell(
          0,
          DateTime.utc(2026, 10, 28),
          formula: 'TODAY()',
          formulaGroup: group,
          numberFormatId: 15,
          numberFormat: 'm/d/yyyy',
          isDate: true,
        ),
        XlsxReadCell(
          0,
          DateTime.utc(2026, 10, 28),
          formula: 'TODAY()',
          formulaGroup: group,
          numberFormatId: 14,
          numberFormat: null,
          isDate: true,
        ),
        XlsxReadCell(
          0,
          DateTime.utc(2026, 10, 28),
          formula: 'TODAY()',
          formulaGroup: group,
          numberFormatId: 14,
          numberFormat: 'm/d/yyyy',
        ),
      ]) {
        expect(full, isNot(other), reason: '$other');
      }
    });

    test('toString shows only what differs from the defaults', () {
      expect(const XlsxReadCell(0, 'a').toString(), 'XlsxReadCell(0, a)');
      expect(
        const XlsxReadCell(1, null, formula: 'A1').toString(),
        'XlsxReadCell(1, null, formula: A1)',
      );
      expect(
        XlsxReadCell(
          2,
          DateTime.utc(2026, 10, 28),
          formulaGroup: XlsxFormulaGroup(
            XlsxFormulaGroupKind.shared,
            XlsxRange.parse('C1:C2'),
            isMaster: false,
          ),
          numberFormatId: 14,
          numberFormat: 'm/d/yyyy',
          isDate: true,
        ).toString(),
        'XlsxReadCell(2, 2026-10-28 00:00:00.000Z, '
        'group: XlsxFormulaGroup(shared, XlsxRange(C1:C2)), '
        'format: 14 m/d/yyyy, date)',
      );
      expect(
        const XlsxReadCell(
          0,
          1,
          numberFormatId: 27,
          numberFormat: null,
        ).toString(),
        'XlsxReadCell(0, 1, format: 27 null)',
      );
    });
  });

  test('XlsxReadRow is exported unchanged', () {
    final XlsxReadRow row = XlsxReadRow(3, <XlsxReadCell>[
      const XlsxReadCell(0, 'a'),
    ], hidden: true);
    expect(row.index, 3);
    expect(row.hidden, isTrue);
    expect(row.cells, <XlsxReadCell>[const XlsxReadCell(0, 'a')]);
    expect(row.toString(), 'XlsxReadRow(3, hidden, [XlsxReadCell(0, a)])');
  });
}
