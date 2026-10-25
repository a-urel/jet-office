import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/cell_ref.dart';
import 'package:jet_office/src/xlsx/range.dart' as impl;
import 'package:test/test.dart';

void main() {
  test('parse normalizes case and reversed corners', () {
    expect(XlsxRange.parse('d10:b2'), const XlsxRange(1, 1, 9, 3));
    expect(XlsxRange.parse(r'$B$2:$D$10'), const XlsxRange(1, 1, 9, 3));
    expect(XlsxRange.parse('B2'), const XlsxRange(1, 1));
    expect(XlsxRange.parse('XFD1048576').firstColumn, 16383);
  });

  test('parse rejects what is not a cell range', () {
    for (final String bad in <String>[
      'A:A',
      '1:3',
      'XFE1',
      'A1048577',
      'A0',
      '',
      'B2:',
      'B2:D10:F1',
      'hello',
    ]) {
      expect(() => XlsxRange.parse(bad), throwsArgumentError, reason: bad);
    }
  });

  test('shape getters', () {
    expect(XlsxRange.parse('A1').isSingleCell, isTrue);
    final XlsxRange r = XlsxRange.parse('B2:D10');
    expect(r.isSingleCell, isFalse);
    expect(r.rowCount, 9);
    expect(r.columnCount, 3);
    expect(r.ref, 'B2:D10');
    expect(r.absoluteRef, r'$B$2:$D$10');
    expect(XlsxRange.parse('B2').ref, 'B2');
    expect(XlsxRange.parse('B2').absoluteRef, r'$B$2');
  });

  test(
    'ref and absoluteRef throw RangeError for a corner outside the sheet',
    () {
      for (final XlsxRange bad in <XlsxRange>[
        const XlsxRange(1048576, 0),
        const XlsxRange(0, 0, 1048576, 0),
        const XlsxRange(0, 16384),
        const XlsxRange(0, 0, 0, 16384),
        const XlsxRange(-1, 0),
      ]) {
        expect(() => bad.ref, throwsRangeError, reason: '$bad');
        expect(() => bad.absoluteRef, throwsRangeError, reason: '$bad');
      }
      expect(const XlsxRange(1048575, 16383).ref, 'XFD1048576');
    },
  );

  test('a hand-built reversed range formats its corners as given', () {
    const XlsxRange reversed = XlsxRange(9, 3, 1, 1);
    expect(reversed.ref, 'D10:B2');
    expect(reversed.absoluteRef, r'$D$10:$B$2');
    expect(reversed.toString(), 'XlsxRange(D10:B2)');
    expect(reversed, isNot(XlsxRange.parse('D10:B2')));
  });

  test('value equality and toString', () {
    expect(const XlsxRange(0, 0, 1, 1), XlsxRange.parse('A1:B2'));
    expect(
      const XlsxRange(0, 0, 1, 1).hashCode,
      XlsxRange.parse('A1:B2').hashCode,
    );
    expect(const XlsxRange(0, 0), isNot(const XlsxRange(0, 1)));
    expect(const XlsxRange(0, 0, 1, 1).toString(), contains('A1:B2'));
  });

  test('overlaps', () {
    const XlsxRange a = XlsxRange(0, 0, 1, 1);
    expect(a.overlaps(const XlsxRange(1, 1, 2, 2)), isTrue);
    expect(a.overlaps(const XlsxRange(2, 2, 3, 3)), isFalse);
    expect(a.overlaps(const XlsxRange(0, 2, 1, 3)), isFalse);
    expect(a.overlaps(a), isTrue);
  });

  test('validateRange checks the corners', () {
    impl.validateRange(const XlsxRange(0, 0, 1048575, 16383), 'range');
    for (final XlsxRange bad in <XlsxRange>[
      const XlsxRange(-1, 0),
      const XlsxRange(0, -1),
      const XlsxRange(1048576, 0),
      const XlsxRange(0, 16384),
      const XlsxRange(0, 0, 1048576, 0),
      const XlsxRange(5, 0, 4, 0),
      const XlsxRange(0, 5, 0, 4),
    ]) {
      expect(
        () => impl.validateRange(bad, 'range'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'range',
          ),
        ),
        reason: '$bad',
      );
    }
  });

  group('parseCellRef', () {
    test('accepts dollars and either case', () {
      expect(parseCellRef('B2'), (row: 1, column: 1));
      expect(parseCellRef(r'$b$2'), (row: 1, column: 1));
      expect(parseCellRef(r'$XFD1'), (row: 0, column: 16383));
      expect(parseCellRef('AA10'), (row: 9, column: 26));
    });
    test('throws ArgumentError', () {
      for (final String bad in <String>['A', '1', 'A0', 'XFE1', 'A-1', 'A 1']) {
        expect(() => parseCellRef(bad), throwsArgumentError, reason: bad);
      }
    });
    test('rejects a row with leading zeros', () {
      for (final String bad in <String>[
        'A01',
        'A0000001',
        r'$A$01',
        'B010',
        'A00',
      ]) {
        expect(() => parseCellRef(bad), throwsArgumentError, reason: bad);
      }
      expect(parseCellRef('A10'), (row: 9, column: 0));
      expect(parseCellRef('A1048576'), (row: 1048575, column: 0));
      expect(() => XlsxRange.parse('A01:B2'), throwsArgumentError);
    });
  });
}
