// ignore_for_file: avoid_dynamic_calls
// Pins what the exported run and paragraph properties, styles and document
// defaults offer: only the typed members (and clear), none of the untyped
// property set behind them or of the styles part's internals. It
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

  test('DocxStyle exposes no member of the internal property set', () {
    final dynamic s = DocxStyle(
      type: DocxStyleType.paragraph,
      id: 'Note',
      name: 'Note',
    );
    _internalCalls(s, 'uiPriority').forEach((String n, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: n);
    });
    expect((s as DocxStyle).uiPriority, isNull);
  });

  test('DocxDocumentDefaults and DocxStyles expose no internals', () {
    final DocxStyles styles = DocxDocument().styles;
    final dynamic d = styles.defaults;
    _internalCalls(d, 'rPrDefault').forEach((String n, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: n);
    });
    final dynamic st = styles;
    for (final MapEntry<String, void Function()> e in <String, void Function()>{
      'root': () => st.root,
      'children': () => st.children,
      'encode': () => st.encode(),
      'writeTo': () => st.writeTo(null, 'styles'),
      'resolveLink': () => st.resolveLink('Normal'),
    }.entries) {
      expect(e.value, throwsA(isA<NoSuchMethodError>()), reason: e.key);
    }
    expect(styles.byId('Normal'), isNotNull);
  });

  test('the properties of a style and of the defaults have no setter', () {
    final dynamic style = DocxStyle(
      type: DocxStyleType.paragraph,
      id: 'Note',
      name: 'Note',
    );
    final dynamic defaults = DocxDocument().styles.defaults;
    for (final dynamic o in <dynamic>[style, defaults]) {
      expect(
        () => o.runProperties = DocxRun('a').properties,
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(
        () => o.paragraphProperties = DocxParagraph().properties,
        throwsA(isA<NoSuchMethodError>()),
      );
    }
  });
}
