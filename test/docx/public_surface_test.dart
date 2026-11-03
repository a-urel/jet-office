// ignore_for_file: avoid_dynamic_calls
// Pins what the exported run and paragraph properties offer: only the typed
// members and clear, none of the untyped property set behind them. It
// imports the public library only, so it runs on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

/// The members of the internal property set, as calls on [p].
Map<String, void Function()> _internalCalls(dynamic p, String child) =>
    <String, void Function()>{
      'setValue': () => p.setValue(child, 1e9),
      'valueOf': () => p.valueOf(child),
      'isSet': () => p.isSet(child),
      'stateOf': () => p.stateOf(child),
      'restore': () => p.restore(child, null),
      'clearChild': () => p.clearChild(child),
      'writeTo': () => p.writeTo(null, 'rPr'),
      'source': () => p.source,
      'schema': () => p.schema,
      'writesNothing': () => p.writesNothing,
    };

void main() {
  test('DocxRunProperties exposes no member of the internal property set', () {
    final dynamic p = DocxRun('a').properties;
    _internalCalls(p, 'sz').forEach((String name, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: name);
    });
    expect((p as DocxRunProperties).sizePt, isNull);
  });

  test(
    'DocxParagraphProperties exposes no member of the internal property set',
    () {
      final dynamic p = DocxParagraph().properties;
      _internalCalls(p, 'ind').forEach((String name, void Function() call) {
        expect(call, throwsA(isA<NoSuchMethodError>()), reason: name);
      });
      expect((p as DocxParagraphProperties).indentation, isNull);
    },
  );
}
