import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

/// Every message of every code and locale, verbatim, for a warning on sheet
/// `S`, cell `A1`, requested name `O`.
const Map<(XlsxWarningCode, XlsxLocale), String>
_expected = <(XlsxWarningCode, XlsxLocale), String>{
  (
    XlsxWarningCode.invalidCharactersRemoved,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' had characters removed that XML does not allow (A1).",
  (
    XlsxWarningCode.invalidCharactersRemoved,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ enthielten Zeichen, die XML nicht erlaubt; sie wurden entfernt (A1).',
  (
    XlsxWarningCode.invalidCharactersRemoved,
    XlsxLocale.tr,
  ): "“S” sayfasındaki 1 hücreden XML'in izin vermediği karakterler çıkarıldı (A1).",
  (
    XlsxWarningCode.textTruncated,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' were cut to 32,767 characters, Excel's limit (A1).",
  (
    XlsxWarningCode.textTruncated,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ wurden auf 32.767 Zeichen gekürzt, die Obergrenze von Excel (A1).',
  (
    XlsxWarningCode.textTruncated,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre, Excel sınırı olan 32.767 karaktere kısaltıldı (A1).',
  (XlsxWarningCode.sheetNameChanged, XlsxLocale.en):
      "Sheet name 'O' is not allowed in Excel and was changed to 'S'.",
  (
    XlsxWarningCode.sheetNameChanged,
    XlsxLocale.de,
  ): 'Der Blattname „O“ ist in Excel nicht zulässig und wurde in „S“ geändert.',
  (XlsxWarningCode.sheetNameChanged, XlsxLocale.tr):
      "“O” sayfa adına Excel'de izin verilmiyor; ad “S” olarak değiştirildi.",
  (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.en):
      "Sheet name 'O' was already used and was changed to 'S'.",
  (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.de):
      'Der Blattname „O“ war bereits vergeben und wurde in „S“ geändert.',
  (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.tr):
      '“O” sayfa adı zaten kullanılıyordu; ad “S” olarak değiştirildi.',
  (
    XlsxWarningCode.intPrecisionLost,
    XlsxLocale.en,
  ): "1 whole number(s) on sheet 'S' are larger than Excel can store exactly and may be rounded (A1).",
  (
    XlsxWarningCode.intPrecisionLost,
    XlsxLocale.de,
  ): '1 ganze Zahl(en) im Blatt „S“ sind größer, als Excel exakt speichern kann, und werden möglicherweise gerundet (A1).',
  (
    XlsxWarningCode.intPrecisionLost,
    XlsxLocale.tr,
  ): "“S” sayfasındaki 1 tam sayı, Excel'in tam olarak saklayabileceğinden büyük; yuvarlanabilir (A1).",
  (
    XlsxWarningCode.dateOutsideExcelRange,
    XlsxLocale.en,
  ): "1 date(s) on sheet 'S' are outside the range Excel can store as dates (1900–9999) and were written as text (A1).",
  (
    XlsxWarningCode.dateOutsideExcelRange,
    XlsxLocale.de,
  ): '1 Datumswert(e) im Blatt „S“ liegen außerhalb des Bereichs, den Excel als Datum speichern kann (1900–9999); sie wurden als Text geschrieben (A1).',
  (
    XlsxWarningCode.dateOutsideExcelRange,
    XlsxLocale.tr,
  ): "“S” sayfasındaki 1 tarih, Excel'in tarih olarak saklayabildiği aralığın (1900–9999) dışında olduğu için metin olarak yazıldı (A1).",
  (
    XlsxWarningCode.dateInNonDateFormat,
    XlsxLocale.en,
  ): "1 date(s) on sheet 'S' use a number format that does not show dates (A1).",
  (
    XlsxWarningCode.dateInNonDateFormat,
    XlsxLocale.de,
  ): '1 Datumswert(e) im Blatt „S“ haben ein Zahlenformat, das kein Datum anzeigt (A1).',
  (
    XlsxWarningCode.dateInNonDateFormat,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 tarih, tarih göstermeyen bir sayı biçimi kullanıyor (A1).',
};

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

  test('all 21 messages are worded exactly as specified', () {
    final List<(XlsxWarningCode, XlsxLocale)> keys =
        <(XlsxWarningCode, XlsxLocale)>[
          for (final XlsxWarningCode code in XlsxWarningCode.values)
            for (final XlsxLocale locale in XlsxLocale.values) (code, locale),
        ];
    expect(keys, hasLength(21));
    expect(_expected.keys, unorderedEquals(keys));
    for (final (XlsxWarningCode, XlsxLocale) key in keys) {
      final XlsxWarning w =
          (WarningCollector()
                ..add(key.$1, sheet: 'S', cell: 'A1', originalName: 'O'))
              .warnings
              .single;
      expect(w.message(key.$2), _expected[key], reason: '${key.$1}/${key.$2}');
    }
  });

  test('exactly ten cells are listed without an ellipsis', () {
    final WarningCollector c = WarningCollector();
    for (var r = 1; r <= 10; r++) {
      c.add(XlsxWarningCode.textTruncated, sheet: 'S', cell: 'A$r');
    }
    expect(c.warnings.single.cells, hasLength(10));
    expect(c.warnings.single.message(), isNot(contains('…')));
    expect(
      c.warnings.single.message(),
      endsWith('(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10).'),
    );
  });

  test('more than ten cells end with an ellipsis in every locale', () {
    final WarningCollector c = WarningCollector();
    for (var r = 1; r <= 11; r++) {
      c.add(XlsxWarningCode.textTruncated, sheet: 'S', cell: 'A$r');
    }
    final XlsxWarning w = c.warnings.single;
    expect(w.cells, hasLength(10));
    expect(w.count, 11);
    for (final XlsxLocale locale in XlsxLocale.values) {
      expect(
        w.message(locale),
        contains('(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, …)'),
        reason: '$locale',
      );
    }
    expect(w.message(XlsxLocale.de), startsWith('11 Zelle(n)'));
    expect(w.message(XlsxLocale.tr), contains('11 hücre'));
  });

  test('a cell-level warning without a cell has no cell list', () {
    final XlsxWarning w =
        (WarningCollector()..add(XlsxWarningCode.textTruncated, sheet: 'S'))
            .warnings
            .single;
    expect(w.cells, isEmpty);
    expect(w.count, 1);
    expect(
      w.message(),
      "1 cell(s) on sheet 'S' were cut to 32,767 characters, Excel's limit.",
    );
  });

  test('a sheet-name message falls back to the sheet without an original', () {
    final XlsxWarning w =
        (WarningCollector()
              ..add(XlsxWarningCode.sheetNameChanged, sheet: 'Final'))
            .warnings
            .single;
    expect(
      w.message(),
      "Sheet name 'Final' is not allowed in Excel and was changed to 'Final'.",
    );
  });
}
