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

  test('dateOutsideExcelRange messages name the 1900-9999 range', () {
    final XlsxWarning w =
        (WarningCollector()..add(
              XlsxWarningCode.dateOutsideExcelRange,
              sheet: 'S',
              cell: 'A1',
            ))
            .warnings
            .single;
    expect(
      w.message(),
      "1 date(s) on sheet 'S' are outside the range Excel can store as dates "
      '(1900\u20139999) and were written as text (A1).',
    );
    expect(
      w.message(XlsxLocale.de),
      '1 Datumswert(e) im Blatt \u201eS\u201c liegen au\u00dferhalb des '
      'Bereichs, den Excel als Datum speichern kann (1900\u20139999); sie '
      'wurden als Text geschrieben (A1).',
    );
    expect(
      w.message(XlsxLocale.tr),
      '\u201cS\u201d sayfas\u0131ndaki 1 tarih, Excel\'in tarih olarak '
      'saklayabildi\u011fi aral\u0131\u011f\u0131n (1900\u20139999) '
      'd\u0131\u015f\u0131nda oldu\u011fu i\u00e7in metin olarak yaz\u0131ld\u0131 (A1).',
    );
  });
}
