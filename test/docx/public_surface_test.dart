// Pins what the exported run properties offer: only the typed members and
// ignore_for_file: avoid_dynamic_calls
// clear, none of the untyped property set behind them. It imports the
// public library only, so it runs on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

void main() {
  test('DocxRunProperties exposes no member of the internal property set', () {
    final dynamic p = DocxRun('a').properties;
    final Map<String, void Function()> calls = <String, void Function()>{
      'setValue': () => p.setValue('sz', 1e9),
      'valueOf': () => p.valueOf('sz'),
      'isSet': () => p.isSet('sz'),
      'stateOf': () => p.stateOf('sz'),
      'restore': () => p.restore('sz', null),
      'clearChild': () => p.clearChild('sz'),
      'writeTo': () => p.writeTo(null, 'rPr'),
      'source': () => p.source,
      'schema': () => p.schema,
      'writesNothing': () => p.writesNothing,
    };
    calls.forEach((String name, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: name);
    });
    expect((p as DocxRunProperties).sizePt, isNull);
  });
}
