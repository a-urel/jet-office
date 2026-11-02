import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// The first element named [localName] of [xml], captured as opaque XML.
OpaqueXml _capture(String xml, String localName) {
  final XmlPullReader r = XmlPullReader(xml);
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.localName == localName) {
      return OpaqueXml.capture(r);
    }
  }
  throw StateError('No <$localName> in $xml');
}

/// Expects every field of [actual] to equal [expected]'s.
void _expectSameCell(RawCell? actual, RawCell expected) {
  expect(actual, isNotNull);
  final RawCell a = actual!;
  expect(a.kind, expected.kind, reason: 'kind');
  expect(a.style, expected.style, reason: 'style');
  expect(a.value, expected.value, reason: 'value');
  expect(a.typeText, expected.typeText, reason: 'typeText');
  expect(a.attributes, expected.attributes, reason: 'attributes');
  expect(a.inline?.xml, expected.inline?.xml, reason: 'inline');
  expect(
    a.extraChildren.map((OpaqueXml x) => x.xml).toList(),
    expected.extraChildren.map((OpaqueXml x) => x.xml).toList(),
    reason: 'extraChildren',
  );
  final RawFormula? f = a.formula;
  final RawFormula? g = expected.formula;
  expect(f == null, g == null, reason: 'formula presence');
  if (f != null && g != null) {
    expect(f.type, g.type, reason: 'formula type');
    expect(f.text, g.text, reason: 'formula text');
    expect(f.ref, g.ref, reason: 'formula ref');
    expect(f.si, g.si, reason: 'formula si');
    expect(f.attributes, g.attributes, reason: 'formula attributes');
  }
}

/// The columns [store] holds in [row], in the order it visits them.
List<int> _columns(CellStore store, int row) {
  final List<int> columns = <int>[];
  store.forEachInRow(row, (int column, RawCell cell) => columns.add(column));
  return columns;
}

void main() {
  group('CellStore', () {
    test('put and cellAt round-trip every kind', () {
      final OpaqueXml inline = _capture(
        '<c xmlns="$_main"><is><t>hi</t></is></c>',
        'is',
      );
      final OpaqueXml ext = _capture(
        '<c xmlns="$_main"><extLst><ext uri="x"/></extLst></c>',
        'extLst',
      );
      const KeptAttribute cm = (
        qualifiedName: 'cm',
        namespaceUri: '',
        value: '1',
      );
      const KeptAttribute x14 = (
        qualifiedName: 'x14ac:foo',
        namespaceUri: 'http://example.com/x14ac',
        value: 'bar',
      );
      final List<RawCell> cells = <RawCell>[
        const RawCell(kind: RawCellKind.number, value: '42'),
        const RawCell(kind: RawCellKind.number, value: '1.50'),
        const RawCell(kind: RawCellKind.number, value: '0.1'),
        const RawCell(kind: RawCellKind.number, value: '-0'),
        const RawCell(kind: RawCellKind.number, value: '1e5'),
        const RawCell(kind: RawCellKind.number, value: ' 7'),
        const RawCell(kind: RawCellKind.number, value: 'NaN'),
        const RawCell(kind: RawCellKind.number, value: 'Infinity'),
        const RawCell(kind: RawCellKind.number, value: '0.30000000000000004'),
        const RawCell(kind: RawCellKind.number, value: '123456789012345680000'),
        const RawCell(kind: RawCellKind.number, value: '12345678901234567890'),
        const RawCell(kind: RawCellKind.number, value: 'abc', style: 3),
        const RawCell(kind: RawCellKind.sharedString, value: '17', style: 0),
        const RawCell(kind: RawCellKind.boolean, value: '1'),
        const RawCell(kind: RawCellKind.error, value: '#N/A'),
        const RawCell(kind: RawCellKind.string, value: 'text result'),
        RawCell(kind: RawCellKind.inlineString, inline: inline, style: 5),
        const RawCell(kind: RawCellKind.isoDate, value: '2024-01-02T03:04:05'),
        const RawCell(kind: RawCellKind.unknown, value: 'x', typeText: 'zz'),
        const RawCell(kind: RawCellKind.number, style: 9),
        const RawCell(kind: RawCellKind.number),
        const RawCell(
          kind: RawCellKind.number,
          value: '3',
          style: 999999999,
          formula: RawFormula(
            type: FormulaType.shared,
            text: 'A1+B1',
            ref: 'C1:C9',
            si: '0',
            attributes: <KeptAttribute>[
              (qualifiedName: 'ca', namespaceUri: '', value: '1'),
            ],
          ),
        ),
        const RawCell(
          kind: RawCellKind.number,
          formula: RawFormula(type: FormulaType.shared, si: '0'),
        ),
        RawCell(
          kind: RawCellKind.string,
          value: '',
          attributes: const <KeptAttribute>[cm, x14],
          extraChildren: <OpaqueXml>[ext],
        ),
      ];
      final CellStore store = CellStore();
      for (int i = 0; i < cells.length; i++) {
        store.put(i ~/ 5, i % 5, cells[i]);
      }
      for (int i = 0; i < cells.length; i++) {
        _expectSameCell(store.cellAt(i ~/ 5, i % 5), cells[i]);
      }
      expect(store.cellAt(0, 7), isNull);
      expect(store.cellAt(99, 0), isNull);
      expect(store.cellCount, cells.length);
    });

    test('a replaced cell takes every field of the new one', () {
      final CellStore store = CellStore()
        ..put(
          2,
          2,
          const RawCell(
            kind: RawCellKind.string,
            value: 'old',
            style: 4,
            formula: RawFormula(type: FormulaType.normal, text: 'X1'),
            attributes: <KeptAttribute>[
              (qualifiedName: 'vm', namespaceUri: '', value: '1'),
            ],
          ),
        );
      expect(store.hasFormulas, isTrue);
      const RawCell replacement = RawCell(kind: RawCellKind.number, value: '1');
      store.put(2, 2, replacement);
      _expectSameCell(store.cellAt(2, 2), replacement);
      expect(store.cellCount, 1);
      expect(store.hasFormulas, isFalse);
    });

    test('rows and columns iterate ascending', () {
      final CellStore store = CellStore();
      const RawCell cell = RawCell(kind: RawCellKind.number, value: '1');
      for (final (int, int) at in <(int, int)>[
        (5, 3),
        (1, 7),
        (5, 0),
        (3, 2),
        (1, 1),
        (5, 9),
        (0, 4),
        (5, 5),
        (1, 4),
      ]) {
        store.put(at.$1, at.$2, cell);
      }
      expect(store.rowIndexes.toList(), <int>[0, 1, 3, 5]);
      expect(_columns(store, 1), <int>[1, 4, 7]);
      expect(_columns(store, 5), <int>[0, 3, 5, 9]);
      expect(_columns(store, 4), isEmpty);
    });

    test('out-of-order puts across many rows stay sorted', () {
      // Enough cells to fill several internal blocks, put in a scrambled
      // order, then compared with a plain map.
      final CellStore store = CellStore();
      final Map<int, String> expected = <int, String>{};
      int seed = 12345;
      int next() => seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      for (int i = 0; i < 40000; i++) {
        final int row = next() % 3000;
        final int column = next() % 40;
        final String value = '${next() % 1000}.5';
        store.put(row, column, RawCell(kind: RawCellKind.number, value: value));
        expected[row * 40 + column] = value;
      }
      // And remove a share of them again.
      for (int i = 0; i < 10000; i++) {
        final int row = next() % 3000;
        final int column = next() % 40;
        expect(
          store.remove(row, column),
          expected.remove(row * 40 + column) != null,
        );
      }
      expect(store.cellCount, expected.length);
      final List<int> keys = expected.keys.toList()..sort();
      final List<int> rows = keys.map((int k) => k ~/ 40).toSet().toList();
      expect(store.rowIndexes.toList(), rows);
      final List<int> seen = <int>[];
      for (final int row in store.rowIndexes) {
        store.forEachInRow(row, (int column, RawCell cell) {
          seen.add(row * 40 + column);
          expect(cell.value, expected[row * 40 + column]);
        });
      }
      expect(seen, keys);
    });

    test('remove, bounds, cellCount and hasFormulas', () {
      final CellStore store = CellStore();
      expect(store.bounds, isNull);
      expect(store.cellCount, 0);
      expect(store.hasFormulas, isFalse);
      expect(store.remove(0, 0), isFalse);

      store
        ..put(4, 2, const RawCell(kind: RawCellKind.number, value: '1'))
        ..put(
          7,
          9,
          const RawCell(
            kind: RawCellKind.number,
            formula: RawFormula(type: FormulaType.normal, text: 'A1'),
          ),
        )
        ..put(2, 5, const RawCell(kind: RawCellKind.number, style: 1));
      expect(store.cellCount, 3);
      expect(store.hasFormulas, isTrue);
      expect(store.bounds, (
        firstRow: 2,
        lastRow: 7,
        firstColumn: 2,
        lastColumn: 9,
      ));

      expect(store.remove(7, 9), isTrue);
      expect(store.remove(7, 9), isFalse);
      expect(store.cellAt(7, 9), isNull);
      expect(store.hasFormulas, isFalse);
      expect(store.cellCount, 2);
      expect(store.rowIndexes.toList(), <int>[2, 4]);
      expect(store.bounds, (
        firstRow: 2,
        lastRow: 4,
        firstColumn: 2,
        lastColumn: 5,
      ));

      expect(store.remove(2, 5), isTrue);
      expect(store.remove(4, 2), isTrue);
      expect(store.cellCount, 0);
      expect(store.bounds, isNull);
      expect(store.rowIndexes, isEmpty);
    });

    test('indexes outside the sheet throw', () {
      final CellStore store = CellStore();
      const RawCell cell = RawCell(kind: RawCellKind.number, value: '1');
      expect(() => store.put(-1, 0, cell), throwsRangeError);
      expect(() => store.put(0, 16384, cell), throwsRangeError);
      expect(() => store.put(1048576, 0, cell), throwsRangeError);
      expect(() => store.cellAt(0, -1), throwsRangeError);
      expect(
        () =>
            store.put(0, 0, const RawCell(kind: RawCellKind.number, style: -1)),
        throwsRangeError,
      );
    });

    test('row attributes survive a row without cells', () {
      const List<KeptAttribute> hidden = <KeptAttribute>[
        (qualifiedName: 'hidden', namespaceUri: '', value: '1'),
        (qualifiedName: 'ht', namespaceUri: '', value: '30'),
      ];
      final CellStore store = CellStore()
        ..put(1, 0, const RawCell(kind: RawCellKind.number, value: '1'))
        ..setRowAttributes(3, hidden)
        ..put(5, 0, const RawCell(kind: RawCellKind.number, value: '2'));
      expect(store.rowIndexes.toList(), <int>[1, 3, 5]);
      expect(store.rowAttributes(3), hidden);
      expect(store.rowAttributes(1), isEmpty);
      expect(_columns(store, 3), isEmpty);
      expect(store.cellCount, 2);
      expect(store.bounds, (
        firstRow: 1,
        lastRow: 5,
        firstColumn: 0,
        lastColumn: 0,
      ));

      // A row whose last cell goes keeps its attributes and its place.
      store
        ..setRowAttributes(5, hidden)
        ..remove(5, 0);
      expect(store.rowIndexes.toList(), <int>[1, 3, 5]);

      // Clearing the attributes of a row without cells drops the row.
      store.setRowAttributes(3, const <KeptAttribute>[]);
      expect(store.rowIndexes.toList(), <int>[1, 5]);
      expect(store.rowAttributes(3), isEmpty);

      // A row without attributes whose last cell goes is dropped.
      store.remove(1, 0);
      expect(store.rowIndexes.toList(), <int>[5]);
    });

    test('100,000 × 12 numbers load in order', () {
      final CellStore store = CellStore();
      for (int row = 0; row < 100000; row++) {
        for (int column = 0; column < 12; column++) {
          store.put(
            row,
            column,
            RawCell(kind: RawCellKind.number, value: '${row * 12 + column}.25'),
          );
        }
      }
      expect(store.cellCount, 1200000);
      expect(store.rowIndexes.length, 100000);
      expect(store.cellAt(99999, 11)?.value, '${99999 * 12 + 11}.25');
      expect(store.cellAt(54321, 6)?.value, '${54321 * 12 + 6}.25');
      expect(store.bounds, (
        firstRow: 0,
        lastRow: 99999,
        firstColumn: 0,
        lastColumn: 11,
      ));
    });
  });
}
