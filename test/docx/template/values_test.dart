// Tests the template values: how a data value becomes text, the data check
// and the lookups. Pure Dart, so it runs on the web too.
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

    test('lookupKey reads one key', () {
      final Map<String, Object?> data = <String, Object?>{'a.b': 1, 'n': null};
      expect((lookupKey(data, 'a.b') as Found).value, 1);
      expect(lookupKey(data, 'n'), isA<Found>());
      expect(lookupKey(data, 'z'), isA<Missing>());
    });
  });
}
