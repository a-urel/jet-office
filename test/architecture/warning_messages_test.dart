// Architecture guard: every warning code has a message in every locale.
library;

import 'package:jet_office/src/xlsx/warning_messages.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

XlsxWarning sampleWarning(XlsxWarningCode code) =>
    (WarningCollector()..add(code, sheet: 'S', cell: 'A1', originalName: 'O'))
        .warnings
        .single;

void main() {
  test('every warning code has a message in every locale', () {
    for (final XlsxWarningCode code in XlsxWarningCode.values) {
      for (final XlsxLocale locale in XlsxLocale.values) {
        final String m = formatWarning(sampleWarning(code), locale);
        expect(m, isNotEmpty, reason: '$code/$locale');
        expect(
          m,
          isNot(contains('{')),
          reason: 'unfilled placeholder in $code/$locale',
        );
      }
    }
  });
}
