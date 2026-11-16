// Tests the template values: how a data value becomes text, the data check
// and the lookups. Pure Dart, so it runs on the web too.
import 'dart:collection';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/template/values.dart';
import 'package:test/test.dart';

void main() {
  final NumberFormatter tr = NumberFormatter(locale: FormatLocale.trTR);
  final NumberFormatter en = NumberFormatter();

  group('valueText', () {
    test('numbers, dates, durations, booleans and text', () {
      expect(
        valueText(FormatDecimal('1234.56'), '#,##0.00 ₺', tr).text,
        '1.234,56 ₺',
      );
      expect(
        valueText(FormatDecimal('1234.56'), '#,##0.00 ₺', en).text,
        '1,234.56 ₺',
      );
      expect(valueText(FormatDecimal('0.1'), null, en).text, '0.1');
      expect(valueText(DateTime(2026, 11, 14), null, tr).text, '14.11.2026');
      expect(
        valueText(DateTime(2026, 11, 14, 9, 5), 'dd.mm.yyyy hh:mm', tr).text,
        '14.11.2026 09:05',
      );
      expect(
        valueText(const Duration(hours: 26, minutes: 3), null, en).text,
        '26:03:00',
      );
      expect(valueText(true, null, tr).text, 'DOĞRU');
      expect(valueText(null, null, en).text, '');
      expect(valueText('Acme', null, en).text, 'Acme');
      expect(valueText(42, null, en).text, '42');
    });

    test('a percent literal shows as text', () {
      expect(valueText(5, '0"%"', en).text, '5%');
    });

    test('a format code reaches text through the formatter', () {
      expect(valueText('Acme', '"Sn. "@', en).text, 'Sn. Acme');
    });

    test('lists, maps and images are not text', () {
      expect(
        valueText(<Object?>[], null, en).problem,
        DocxWarningCode.templateValueNotText,
      );
      expect(valueText(<Object?>[], null, en).text, isNull);
      expect(
        valueText(<String, Object?>{}, null, en).problem,
        DocxWarningCode.templateValueNotText,
      );
      expect(
        valueText(OfficeImage(Uint8List.fromList(<int>[1])), null, en).problem,
        DocxWarningCode.templateValueNotText,
      );
    });

    test('a code the engine flags yields its warning', () {
      expect(valueText(1, '[Red', en).formatWarning, FormatWarning.invalidCode);
      expect(valueText(1, null, en).formatWarning, isNull);
    });
  });

  group('checkTemplateData', () {
    test('accepts every value type, recursively', () {
      expect(
        () => checkTemplateData(<String, Object?>{
          'a': <Object?>[
            1,
            'x',
            null,
            true,
            DateTime(2026),
            const Duration(hours: 1),
            FormatDecimal('1.5'),
            <String, Object?>{'b': 2.5},
          ],
        }),
        returnsNormally,
      );
    });

    test('throws for an unsupported type, naming the path', () {
      expect(
        () => checkTemplateData(<String, Object?>{'a': Object()}),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            contains("data['a']"),
          ),
        ),
      );
      expect(
        () => checkTemplateData(<String, Object?>{
          'a': <Object?>[1, 2, Object()],
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            contains("data['a'][2]"),
          ),
        ),
      );
    });

    test('a shared structure is checked once, not once per path', () {
      // It counts the elements the check reads instead of timing it: a 1 s
      // bound on a run of under 1 ms could fail on a busy machine. Each of
      // the 41 lists is read once, 1 + 40 * 2 elements; a check that walks
      // every path reads 2^41 and stops at the budget of [_CountingList].
      final _Reads reads = _Reads(budget: 1000);
      Object level = _CountingList(<Object?>[1], reads);
      for (int i = 0; i < 40; i++) {
        level = _CountingList(<Object?>[level, level], reads);
      }
      checkTemplateData(<String, Object?>{'a': level});
      expect(reads.count, 1 + 40 * 2);
    });

    test('throws for a non-String key', () {
      expect(
        () => checkTemplateData(<String, Object?>{
          'a': <Object?, Object?>{1: 'x'},
        }),
        throwsArgumentError,
      );
    });

    test('throws for a cycle, accepts a shared sub-map', () {
      final Map<String, Object?> cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      expect(() => checkTemplateData(cyclic), throwsArgumentError);
      final List<Object?> list = <Object?>[];
      list.add(list);
      expect(
        () => checkTemplateData(<String, Object?>{'l': list}),
        throwsArgumentError,
      );
      final Map<String, Object?> shared = <String, Object?>{'x': 1};
      expect(
        () => checkTemplateData(<String, Object?>{'a': shared, 'b': shared}),
        returnsNormally,
      );
    });
  });

  group('lookups', () {
    test('lookupPath walks maps', () {
      final Map<String, Object?> data = <String, Object?>{
        'a': <String, Object?>{'b': null},
        't': 'text',
      };
      final Lookup found = lookupPath(data, <String>['a', 'b']);
      expect(found, isA<Found>());
      expect((found as Found).value, isNull);
      expect(lookupPath(data, <String>['a', 'c']), isA<Missing>());
      expect(lookupPath(data, <String>['x']), isA<Missing>());
      expect(lookupPath(data, <String>['t', 'b']), isA<Missing>());
    });

    test('lookups read any Map with String keys checkTemplateData takes', () {
      final Map<String, Object?> data = <String, Object?>{
        'a': <dynamic, dynamic>{'b': 1},
        'o': <Object, Object?>{'k': null},
      };
      checkTemplateData(data);
      expect((lookupPath(data, <String>['a', 'b']) as Found).value, 1);
      expect(lookupPath(data, <String>['o', 'k']), isA<Found>());
      expect(lookupPath(data, <String>['o', 'z']), isA<Missing>());
      final Map<Object, Object?> root = <Object, Object?>{'x': 5};
      expect((lookupKey(root, 'x') as Found).value, 5);
      expect(lookupKey(root, 'y'), isA<Missing>());
    });

    test('lookupKey reads one key', () {
      final Map<String, Object?> data = <String, Object?>{'a.b': 1, 'n': null};
      expect((lookupKey(data, 'a.b') as Found).value, 1);
      expect(lookupKey(data, 'n'), isA<Found>());
      expect(lookupKey(data, 'z'), isA<Missing>());
    });
  });

  group('sections', () {
    void expectEffect(
      Object? value,
      SectionEffect effect,
      List<Object?> items, {
      bool inverted = false,
    }) {
      final ({SectionEffect effect, List<Object?> items}) r = sectionEffect(
        value,
        inverted: inverted,
      );
      expect(r.effect, effect, reason: '$value');
      expect(r.items, items, reason: '$value');
    }

    Object? found(Lookup lookup) {
      expect(lookup, isA<Found>());
      return (lookup as Found).value;
    }

    test('a non-empty list repeats with its items', () {
      expectEffect(<Object?>[1, 2], SectionEffect.repeat, <Object?>[1, 2]);
    });

    test('false, null, empty text and an empty list remove', () {
      for (final Object? value in <Object?>[false, null, '', <Object?>[]]) {
        expectEffect(value, SectionEffect.remove, const <Object?>[]);
      }
    });

    test('zero, true, text, a date, a duration, a decimal, an image show '
        'once', () {
      final OfficeImage image = OfficeImage(Uint8List.fromList(<int>[1]));
      for (final Object value in <Object>[
        0,
        0.0,
        true,
        'x',
        DateTime(2026),
        Duration.zero,
        FormatDecimal('0'),
        image,
      ]) {
        expectEffect(value, SectionEffect.once, <Object?>[value]);
      }
    });

    test('a map, even empty, is a scope', () {
      final Map<String, Object?> empty = <String, Object?>{};
      expectEffect(empty, SectionEffect.scope, <Object?>[empty]);
      final Map<String, Object?> map = <String, Object?>{'a': 1};
      expectEffect(map, SectionEffect.scope, <Object?>[map]);
    });

    test('inverted shows once exactly when the section would remove', () {
      for (final Object? value in <Object?>[false, null, '', <Object?>[]]) {
        expectEffect(
          value,
          SectionEffect.once,
          const <Object?>[],
          inverted: true,
        );
      }
      for (final Object? value in <Object?>[
        <Object?>[1],
        <String, Object?>{},
        true,
        0,
        'x',
      ]) {
        expectEffect(
          value,
          SectionEffect.remove,
          const <Object?>[],
          inverted: true,
        );
      }
    });

    test('lookup goes from the innermost scope outward', () {
      final List<Object?> scopes = <Object?>[
        <String, Object?>{
          'a': 1,
          'b': <String, Object?>{'c': 2},
        },
        <String, Object?>{'a': 3},
      ];
      expect(found(lookupInScopes(scopes, <String>['a'])), 3);
      expect(found(lookupInScopes(scopes, <String>['b', 'c'])), 2);
      expect(lookupInScopes(scopes, <String>['z']), isA<Missing>());
    });

    test('the first map with the segment decides, no further fallback', () {
      final List<Object?> scopes = <Object?>[
        <String, Object?>{
          'b': <String, Object?>{'c': 2},
        },
        <String, Object?>{'b': <String, Object?>{}},
      ];
      expect(lookupInScopes(scopes, <String>['b', 'c']), isA<Missing>());
    });

    test('non-map scopes are skipped', () {
      final List<Object?> scopes = <Object?>[
        <String, Object?>{'a': 1},
        'item',
        null,
        <Object?>[1],
      ];
      expect(found(lookupInScopes(scopes, <String>['a'])), 1);
      expect(found(lookupKeyInScopes(scopes, 'a')), 1);
    });

    test('a key present with null is found', () {
      final List<Object?> scopes = <Object?>[
        <String, Object?>{'a': 1},
        <String, Object?>{'a': null},
      ];
      expect(found(lookupInScopes(scopes, <String>['a'])), isNull);
      expect(found(lookupKeyInScopes(scopes, 'a')), isNull);
    });

    test('a merge field key is looked up through scopes as one key', () {
      final List<Object?> scopes = <Object?>[
        <String, Object?>{'Müşteri Adı': 'x', 'a.b': 1},
        <String, Object?>{},
      ];
      expect(found(lookupKeyInScopes(scopes, 'Müşteri Adı')), 'x');
      expect(found(lookupKeyInScopes(scopes, 'a.b')), 1);
      expect(lookupKeyInScopes(scopes, 'a'), isA<Missing>());
    });

    test('no scopes find nothing', () {
      expect(lookupInScopes(const <Object?>[], <String>['a']), isA<Missing>());
      expect(lookupKeyInScopes(const <Object?>[], 'a'), isA<Missing>());
    });
  });
}

/// The element reads of every [_CountingList] that shares it.
final class _Reads {
  _Reads({required this.budget});

  /// The most reads allowed; one more fails the test at once.
  final int budget;

  /// The reads so far.
  int count = 0;
}

/// A list that counts each element read in [_reads], and fails the test
/// once the reads pass the budget, so a walk of every path of a shared
/// structure stops at once instead of running for ever.
final class _CountingList extends ListBase<Object?> {
  _CountingList(this._elements, this._reads);

  final List<Object?> _elements;
  final _Reads _reads;

  @override
  int get length => _elements.length;

  @override
  set length(int value) => _elements.length = value;

  @override
  Object? operator [](int index) {
    if (++_reads.count > _reads.budget) {
      fail('more than ${_reads.budget} elements read');
    }
    return _elements[index];
  }

  @override
  void operator []=(int index, Object? value) => _elements[index] = value;
}
