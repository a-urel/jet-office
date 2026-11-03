import 'package:jet_office/src/common/warning_aggregator.dart';
import 'package:test/test.dart';

enum _Code { a, b }

void main() {
  test('aggregates per scope and code with count and first ten locations', () {
    final WarningAggregator<_Code> w = WarningAggregator<_Code>();
    for (int i = 1; i <= 25; i++) {
      w.add(_Code.a, scope: 'Data', location: 'B$i');
    }
    w.add(_Code.b, scope: 'Data', location: 'C1');
    w.add(_Code.a, scope: 0, location: 'D1');
    expect(w.all, hasLength(3));
    final AggregatedWarning<_Code> first = w.all.first;
    expect(first.code, _Code.a);
    expect(first.scope, 'Data');
    expect(first.detail, isNull);
    expect(first.count, 25);
    expect(first.locations, <String>[for (int i = 1; i <= 10; i++) 'B$i']);
    expect(
      w.all
          .map((AggregatedWarning<_Code> e) => (e.code, e.scope, e.count))
          .toList(),
      <(_Code, Object, int)>[
        (_Code.a, 'Data', 25),
        (_Code.b, 'Data', 1),
        (_Code.a, 0, 1),
      ],
    );
  });

  test('add with a count adds that many occurrences and one location', () {
    final WarningAggregator<_Code> w = WarningAggregator<_Code>()
      ..add(_Code.a, scope: 'S', location: 'A1', count: 3)
      ..add(_Code.a, scope: 'S');
    expect(w.all.single.count, 4);
    expect(w.all.single.locations, <String>['A1']);
  });

  test('eleventh distinct detail joins a null-detail entry', () {
    final WarningAggregator<_Code> w = WarningAggregator<_Code>();
    for (int i = 0; i < 12; i++) {
      w.add(_Code.a, scope: 'S', detail: '$i', location: 'A${i + 1}');
    }
    // A detail already kept still has its own entry.
    w.add(_Code.a, scope: 'S', detail: '3', location: 'A99');
    // Another scope has its own ten.
    w.add(_Code.a, scope: 'T', detail: '11');
    expect(
      w.all.map((AggregatedWarning<_Code> e) => e.detail).toList(),
      <String?>['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', null, '11'],
    );
    expect(w.all[3].count, 2);
    expect(w.all[3].locations, <String>['A4', 'A99']);
    expect(w.all[10].count, 2);
    expect(w.all[10].locations, <String>['A11', 'A12']);
  });

  test('addUnaggregated gives one entry per call', () {
    final WarningAggregator<_Code> w = WarningAggregator<_Code>()
      ..add(_Code.a, scope: 'S', location: 'A1')
      ..addUnaggregated(_Code.b, scope: 'S')
      ..addUnaggregated(_Code.b, scope: 'S', detail: 'x', location: 'B2')
      ..add(_Code.a, scope: 'S', location: 'A2');
    expect(
      w.all
          .map(
            (AggregatedWarning<_Code> e) =>
                (e.code, e.detail, e.count, e.locations.length),
          )
          .toList(),
      <(_Code, String?, int, int)>[
        (_Code.a, null, 2, 2),
        (_Code.b, null, 1, 0),
        (_Code.b, 'x', 1, 1),
      ],
    );
  });

  test('removeScope drops only that scope', () {
    final WarningAggregator<_Code> w = WarningAggregator<_Code>()
      ..add(_Code.a, scope: 'S', location: 'A1')
      ..add(_Code.a, scope: 'T', location: 'A1')
      ..add(_Code.b, scope: 'S', location: 'B1')
      ..addUnaggregated(_Code.a, scope: 'S');
    w.removeScope('S');
    expect(
      w.all.map((AggregatedWarning<_Code> e) => (e.code, e.scope)).toList(),
      <(_Code, Object)>[(_Code.a, 'T')],
    );
    // A later add starts a fresh entry.
    w.add(_Code.a, scope: 'S', location: 'A5');
    expect(w.all.last.scope, 'S');
    expect(w.all.last.count, 1);
    expect(w.all.last.locations, <String>['A5']);
  });

  test('removeScope keeps the codes in keep, with their details', () {
    final WarningAggregator<_Code> w = WarningAggregator<_Code>();
    for (int i = 0; i < 10; i++) {
      w.add(_Code.a, scope: 'S', detail: '$i');
      w.add(_Code.b, scope: 'S', detail: '$i');
    }
    w.removeScope('S', keep: <_Code>{_Code.b});
    expect(w.all.map((AggregatedWarning<_Code> e) => e.code).toSet(), <_Code>{
      _Code.b,
    });
    // The kept code still has its ten details: a new one joins null.
    w.add(_Code.b, scope: 'S', detail: 'new');
    expect(w.all.last.detail, isNull);
    // The dropped code starts over with fresh details.
    w.add(_Code.a, scope: 'S', detail: 'new');
    expect(w.all.last.detail, 'new');
  });

  test('locations view is the same object and shows later adds', () {
    final WarningAggregator<_Code> w = WarningAggregator<_Code>()
      ..add(_Code.a, scope: 'S', location: 'A1');
    final AggregatedWarning<_Code> entry = w.all.single;
    final List<String> view = entry.locations;
    w.add(_Code.a, scope: 'S', location: 'A2');
    expect(identical(entry.locations, view), isTrue);
    expect(view, <String>['A1', 'A2']);
    expect(() => view.add('A3'), throwsUnsupportedError);
    expect(identical(w.all, w.all), isTrue);
    expect(() => w.all.add(entry), throwsUnsupportedError);
  });
}
