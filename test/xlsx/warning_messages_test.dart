import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

void main() {
  test('English message lists cells and an ellipsis', () {
    final WarningCollector c = WarningCollector();
    for (var r = 1; r <= 12; r++) {
      c.add(
        XlsxWarningCode.invalidCharactersRemoved,
        sheet: 'Data',
        cell: 'B$r',
      );
    }
    expect(
      c.warnings.single.message(),
      "12 cell(s) on sheet 'Data' had characters removed that XML does not "
      'allow (B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, …).',
    );
    expect(c.warnings.single.toString(), c.warnings.single.message());
  });

  test('Turkish and German messages', () {
    final XlsxWarning w =
        (WarningCollector()
              ..add(XlsxWarningCode.textTruncated, sheet: 'Şube', cell: 'C3'))
            .warnings
            .single;
    expect(
      w.message(XlsxLocale.tr),
      '“Şube” sayfasındaki 1 hücre, Excel sınırı olan 32.767 karaktere '
      'kısaltıldı (C3).',
    );
    expect(
      w.message(XlsxLocale.de),
      '1 Zelle(n) im Blatt „Şube“ wurden auf 32.767 Zeichen gekürzt, die '
      'Obergrenze von Excel (C3).',
    );
  });

  test('sheet-name messages use the original name', () {
    final XlsxWarning w =
        (WarningCollector()..add(
              XlsxWarningCode.sheetNameChanged,
              sheet: 'a_b',
              originalName: 'a/b',
            ))
            .warnings
            .single;
    expect(
      w.message(),
      "Sheet name 'a/b' is not allowed in Excel and was changed to 'a_b'.",
    );
  });
}
