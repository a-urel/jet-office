import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/model/columns.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

KeptAttribute _attr(String name, String value) =>
    (qualifiedName: name, namespaceUri: '', value: value);

ColRun _run(int min, int max, [List<KeptAttribute>? attributes]) => ColRun(
  min,
  max,
  'col',
  attributes ?? <KeptAttribute>[_attr('width', '10')],
);

String _show(List<ColRun> runs) => runs
    .map(
      (ColRun r) =>
          '${r.min}-${r.max}[${r.attributes.map((KeptAttribute a) => '${a.qualifiedName}=${a.value}').join(',')}]',
    )
    .join(' ');

CapturedCols _capture(String xml) {
  final XmlPullReader r = XmlPullReader(
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '$xml</worksheet>',
  );
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.localName == 'cols') {
      return captureCols(r);
    }
  }
  throw StateError('no cols');
}

void main() {
  group('replaceAttributes', () {
    test('replaces where it stood, adds after, removes on null', () {
      final List<KeptAttribute> old = <KeptAttribute>[
        _attr('width', '9'),
        _attr('bestFit', '1'),
        _attr('width', '8'),
        (qualifiedName: 'x:width', namespaceUri: 'urn:x', value: 'keep'),
      ];
      expect(
        replaceAttributes(old, <String, String?>{
          'width': '20',
          'hidden': '1',
          'bestFit': null,
        }).map((KeptAttribute a) => '${a.qualifiedName}=${a.value}'),
        <String>['width=20', 'x:width=keep', 'hidden=1'],
      );
      expect(replaceAttributes(old, <String, String?>{}), old);
    });
  });

  group('setColumnInRuns', () {
    List<KeptAttribute>? replaceWith(String value, List<KeptAttribute>? old) =>
        <KeptAttribute>[_attr('width', value), ...?old?.skip(1)];

    test('splits a run into three; the outer runs are the same objects', () {
      final ColRun whole = _run(2, 10);
      final List<ColRun> runs = setColumnInRuns(
        <ColRun>[whole],
        5,
        'col',
        (List<KeptAttribute>? old) => replaceWith('99', old),
      );
      expect(_show(runs), '2-4[width=10] 5-5[width=99] 6-10[width=10]');
      expect(runs.first.attributes, same(whole.attributes));
      expect(runs.last.attributes, same(whole.attributes));
    });

    test('an edge column leaves two runs, a single column one', () {
      expect(
        _show(
          setColumnInRuns(
            <ColRun>[_run(1, 3)],
            1,
            'col',
            (List<KeptAttribute>? old) => replaceWith('1', old),
          ),
        ),
        '1-1[width=1] 2-3[width=10]',
      );
      expect(
        _show(
          setColumnInRuns(
            <ColRun>[_run(1, 3)],
            3,
            'col',
            (List<KeptAttribute>? old) => replaceWith('1', old),
          ),
        ),
        '1-2[width=10] 3-3[width=1]',
      );
      expect(
        _show(
          setColumnInRuns(
            <ColRun>[_run(4, 4)],
            4,
            'col',
            (List<KeptAttribute>? old) => replaceWith('1', old),
          ),
        ),
        '4-4[width=1]',
      );
    });

    test('null takes the column out of its run', () {
      List<ColRun> remove(List<ColRun> runs, int column) =>
          setColumnInRuns(runs, column, 'col', (_) => null);
      expect(
        _show(remove(<ColRun>[_run(1, 3)], 2)),
        '1-1[width=10] 3-3[width=10]',
      );
      expect(_show(remove(<ColRun>[_run(2, 2)], 2)), '');
      // A column no run holds is left alone.
      final List<ColRun> runs = <ColRun>[_run(2, 2)];
      expect(_show(remove(runs, 5)), '2-2[width=10]');
    });

    test('a new column goes in order and joins an equal neighbour', () {
      final List<ColRun> runs = <ColRun>[_run(1, 1), _run(5, 6)];
      List<KeptAttribute>? ten(List<KeptAttribute>? old) {
        expect(old, isNull);
        return <KeptAttribute>[_attr('width', '10')];
      }

      expect(
        _show(setColumnInRuns(runs, 3, 'x:col', ten)),
        '1-1[width=10] 3-3[width=10] 5-6[width=10]',
      );
      expect(
        _show(setColumnInRuns(runs, 2, 'col', ten)),
        '1-2[width=10] 5-6[width=10]',
      );
      expect(
        _show(setColumnInRuns(runs, 4, 'col', ten)),
        '1-1[width=10] 4-6[width=10]',
      );
      expect(
        _show(setColumnInRuns(<ColRun>[_run(1, 1), _run(3, 3)], 2, 'col', ten)),
        '1-3[width=10]',
      );
      expect(setColumnInRuns(runs, 3, 'x:col', ten)[1].qualifiedName, 'x:col');
      expect(setColumnInRuns(runs, 9, 'col', ten).last.min, 9);
      expect(setColumnInRuns(const <ColRun>[], 1, 'col', ten), hasLength(1));
    });

    test('does not change its input and runs the edit once', () {
      final List<ColRun> runs = <ColRun>[_run(1, 3)];
      int calls = 0;
      setColumnInRuns(runs, 2, 'col', (List<KeptAttribute>? old) {
        calls++;
        return old;
      });
      expect(calls, 1);
      expect(_show(runs), '1-3[width=10]');
    });
  });

  group('ColsGroup', () {
    test('runAt finds the run by binary search', () {
      final ColsGroup group = ColsGroup(
        'cols',
        const <String, String>{},
        const <KeptAttribute>[],
        <ColRun>[_run(2, 4), _run(7, 7), _run(9, 12), _run(20, 30)],
      );
      expect(group.runAt(1), isNull);
      expect(group.runAt(2)?.min, 2);
      expect(group.runAt(4)?.min, 2);
      expect(group.runAt(5), isNull);
      expect(group.runAt(7)?.min, 7);
      expect(group.runAt(12)?.min, 9);
      expect(group.runAt(13), isNull);
      expect(group.runAt(30)?.min, 20);
      expect(group.runAt(31), isNull);
    });

    test('deepestOutline reads valid levels only', () {
      final ColsGroup group = ColsGroup(
        'cols',
        const <String, String>{},
        const <KeptAttribute>[],
        <ColRun>[
          _run(1, 1, <KeptAttribute>[_attr('outlineLevel', '2')]),
          _run(2, 2, <KeptAttribute>[_attr('outlineLevel', '9')]),
          _run(3, 3, <KeptAttribute>[_attr('outlineLevel', 'x')]),
          _run(4, 4, <KeptAttribute>[_attr('outlineLevel', '5')]),
        ],
      );
      expect(group.deepestOutline, 5);
    });
  });

  group('captureCols', () {
    test('types a plain cols and keeps every attribute', () {
      final CapturedCols cols = _capture(
        '<cols><col min="2" max="10" width="20" customWidth="1" bestFit="1"/>'
        '<col width="3" max="12" min="11"/></cols>',
      );
      final ColsGroup group = cols.typed!;
      expect(
        _show(group.runs),
        '2-10[width=20,customWidth=1,bestFit=1] 11-12[width=3]',
      );
      expect(cols.whole.localName, 'cols');
    });

    test('anything not plain stays opaque', () {
      for (final String xml in <String>[
        '<cols/>',
        '<cols></cols>',
        '<cols><col min="1"/></cols>',
        '<cols><col max="1"/></cols>',
        '<cols><col min="2" max="1"/></cols>',
        '<cols><col min="1" max="1"/><col min="1" max="2"/></cols>',
        '<cols><col min="3" max="3"/><col min="1" max="1"/></cols>',
        '<cols><col min="0" max="1"/></cols>',
        '<cols><col min="1" max="16385"/></cols>',
        '<cols><col min="1" max="99999"/></cols>',
        '<cols><col min="1.5" max="2"/></cols>',
        '<cols><col min="1" max="1"><x/></col></cols>',
        '<cols><other min="1" max="1"/></cols>',
        '<cols><c:col xmlns:c="urn:c" min="1" max="1"/></cols>',
        '<cols><col xmlns:q="urn:q" min="1" max="1"/></cols>',
      ]) {
        expect(_capture(xml).typed, isNull, reason: xml);
      }
    });

    test('the last column is allowed', () {
      expect(
        _capture('<cols><col min="16384" max="16384"/></cols>').typed,
        isNotNull,
      );
    });
  });

  group('parseOutlineLevel', () {
    test('accepts 0 to 7 only', () {
      expect(parseOutlineLevel('0'), 0);
      expect(parseOutlineLevel('7'), 7);
      expect(parseOutlineLevel('+3'), 3);
      for (final String? bad in <String?>[
        null,
        '',
        '8',
        '-1',
        'x',
        '1.5',
        '0007x',
      ]) {
        expect(parseOutlineLevel(bad), isNull, reason: '$bad');
      }
    });
  });
}
