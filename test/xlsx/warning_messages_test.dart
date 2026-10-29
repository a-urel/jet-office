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
  (
    XlsxWarningCode.sheetPartMissing,
    XlsxLocale.en,
  ): "Sheet 'S' is listed in the workbook but its part is missing; it reads as empty.",
  (
    XlsxWarningCode.sheetPartMissing,
    XlsxLocale.de,
  ): 'Das Blatt „S“ ist in der Arbeitsmappe aufgeführt, aber sein Teil fehlt in der Datei; es wird als leer gelesen.',
  (
    XlsxWarningCode.sheetPartMissing,
    XlsxLocale.tr,
  ): '“S” sayfası çalışma kitabında listeleniyor ancak sayfa parçası dosyada yok; boş okunuyor.',
  (
    XlsxWarningCode.sharedStringInvalid,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' point to a shared string that does not exist; they read as empty (A1).",
  (
    XlsxWarningCode.sharedStringInvalid,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ verweisen auf eine gemeinsame Zeichenfolge, die nicht existiert; sie werden als leer gelesen (A1).',
  (
    XlsxWarningCode.sharedStringInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre, var olmayan bir paylaşılan dizeye başvuruyor; boş okunuyor (A1).',
  (
    XlsxWarningCode.numberInvalid,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' hold a number that cannot be read; they read as empty (A1).",
  (
    XlsxWarningCode.numberInvalid,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ enthalten eine Zahl, die nicht gelesen werden kann; sie werden als leer gelesen (A1).',
  (
    XlsxWarningCode.numberInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre okunamayan bir sayı içeriyor; boş okunuyor (A1).',
  (
    XlsxWarningCode.booleanInvalid,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' hold a boolean other than 0 or 1; they read as empty (A1).",
  (
    XlsxWarningCode.booleanInvalid,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ enthalten einen Wahrheitswert, der weder 0 noch 1 ist; sie werden als leer gelesen (A1).',
  (
    XlsxWarningCode.booleanInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre 0 veya 1 dışında bir mantıksal değer içeriyor; boş okunuyor (A1).',
  (
    XlsxWarningCode.cellTypeUnsupported,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' have a type the reader does not support; they read as empty (A1).",
  (
    XlsxWarningCode.cellTypeUnsupported,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ haben einen Typ, den der Reader nicht unterstützt; sie werden als leer gelesen (A1).',
  (
    XlsxWarningCode.cellTypeUnsupported,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre, okuyucunun desteklemediği bir türde; boş okunuyor (A1).',
  (
    XlsxWarningCode.formulaWithoutValue,
    XlsxLocale.en,
  ): "1 formula cell(s) on sheet 'S' have no saved result; they read as empty (A1).",
  (
    XlsxWarningCode.formulaWithoutValue,
    XlsxLocale.de,
  ): '1 Formelzelle(n) im Blatt „S“ haben kein gespeichertes Ergebnis; sie werden als leer gelesen (A1).',
  (
    XlsxWarningCode.formulaWithoutValue,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 formül hücresinin kayıtlı sonucu yok; boş okunuyor (A1).',
  (
    XlsxWarningCode.cellReferenceInvalid,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' have an invalid reference; they were placed after the previous cell (A1).",
  (
    XlsxWarningCode.cellReferenceInvalid,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ haben einen ungültigen Zellbezug; sie wurden hinter der vorherigen Zelle eingefügt (A1).',
  (
    XlsxWarningCode.cellReferenceInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücrenin başvurusu geçersiz; hücre, önceki hücrenin ardına yerleştirildi (A1).',
  (
    XlsxWarningCode.cellDuplicated,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' appear more than once; the last one was kept (A1).",
  (
    XlsxWarningCode.cellDuplicated,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ kommen mehrfach vor; die letzte wurde beibehalten (A1).',
  (
    XlsxWarningCode.cellDuplicated,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre birden fazla kez geçiyor; sonuncusu korundu (A1).',
  (
    XlsxWarningCode.rowOutOfOrder,
    XlsxLocale.en,
  ): "1 row(s) on sheet 'S' are out of order; they were read in file order (A1).",
  (
    XlsxWarningCode.rowOutOfOrder,
    XlsxLocale.de,
  ): '1 Zeile(n) im Blatt „S“ stehen nicht in der richtigen Reihenfolge; sie wurden in der Reihenfolge der Datei gelesen (A1).',
  (XlsxWarningCode.rowOutOfOrder, XlsxLocale.tr):
      '“S” sayfasındaki 1 satır sırasız; dosyadaki sırayla okundu (A1).',
  (XlsxWarningCode.cellOutsideSheet, XlsxLocale.en):
      "1 cell(s) on sheet 'S' lie outside Excel's grid and were skipped (A1).",
  (
    XlsxWarningCode.cellOutsideSheet,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ liegen außerhalb des Excel-Rasters und wurden übersprungen (A1).',
  (
    XlsxWarningCode.cellOutsideSheet,
    XlsxLocale.tr,
  ): "“S” sayfasındaki 1 hücre, Excel'in ızgarasının dışında kaldığı için atlandı (A1).",
  (
    XlsxWarningCode.unresolvedNumberFormat,
    XlsxLocale.en,
  ): "1 number cell(s) on sheet 'S' use built-in number format 27, whose code depends on the locale and is not in the file; they read as plain numbers, even if they show dates (A1).",
  (
    XlsxWarningCode.unresolvedNumberFormat,
    XlsxLocale.de,
  ): '1 Zahlenzelle(n) im Blatt „S“ verwenden das integrierte Zahlenformat 27, dessen Code vom Gebietsschema abhängt und nicht in der Datei steht; sie werden als einfache Zahlen gelesen, auch wenn sie ein Datum anzeigen (A1).',
  (
    XlsxWarningCode.unresolvedNumberFormat,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 sayı hücresi, kodu yerel ayara bağlı olan ve dosyada bulunmayan 27 numaralı yerleşik sayı biçimini kullanıyor; tarih gösterseler bile düz sayı olarak okunuyor (A1).',
  (
    XlsxWarningCode.styleInvalid,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' point to a cell format that does not exist or cannot be read; they read with the General format (A1).",
  (
    XlsxWarningCode.styleInvalid,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ verweisen auf ein Zellformat, das nicht existiert oder nicht gelesen werden kann; sie werden mit dem Format „Standard“ gelesen (A1).',
  (
    XlsxWarningCode.styleInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre, var olmayan veya okunamayan bir hücre biçimine başvuruyor; Genel biçimle okunuyor (A1).',
  (
    XlsxWarningCode.serialOutOfRange,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' are formatted as a date or time but hold a number no date or time can have; they read as numbers (A1).",
  (
    XlsxWarningCode.serialOutOfRange,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ sind als Datum oder Uhrzeit formatiert, enthalten aber eine Zahl, die kein Datum und keine Uhrzeit sein kann; sie werden als Zahlen gelesen (A1).',
  (
    XlsxWarningCode.serialOutOfRange,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre tarih veya saat olarak biçimlendirilmiş, ancak hiçbir tarih ya da saatin alamayacağı bir sayı içeriyor; sayı olarak okunuyor (A1).',
  (
    XlsxWarningCode.phantomLeapDay,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' hold 29 February 1900, a day that did not exist (Excel counts it for compatibility); they read as numbers (A1).",
  (
    XlsxWarningCode.phantomLeapDay,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ enthalten den 29. Februar 1900, einen Tag, den es nicht gab (Excel zählt ihn aus Kompatibilitätsgründen); sie werden als Zahlen gelesen (A1).',
  (
    XlsxWarningCode.phantomLeapDay,
    XlsxLocale.tr,
  ): "“S” sayfasındaki 1 hücre, hiç var olmamış bir gün olan 29 Şubat 1900'ü içeriyor (Excel bu günü uyumluluk için sayar); sayı olarak okunuyor (A1).",
  (
    XlsxWarningCode.dateTextInvalid,
    XlsxLocale.en,
  ): "1 date cell(s) on sheet 'S' hold text that is not a valid date; they read as empty (A1).",
  (
    XlsxWarningCode.dateTextInvalid,
    XlsxLocale.de,
  ): '1 Datumszelle(n) im Blatt „S“ enthalten Text, der kein gültiges Datum ist; sie werden als leer gelesen (A1).',
  (
    XlsxWarningCode.dateTextInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 tarih hücresi geçerli bir tarih olmayan metin içeriyor; boş okunuyor (A1).',
  (
    XlsxWarningCode.errorValueInvalid,
    XlsxLocale.en,
  ): "1 error cell(s) on sheet 'S' hold no error code; they read as empty (A1).",
  (
    XlsxWarningCode.errorValueInvalid,
    XlsxLocale.de,
  ): '1 Fehlerzelle(n) im Blatt „S“ enthalten keinen Fehlercode; sie werden als leer gelesen (A1).',
  (XlsxWarningCode.errorValueInvalid, XlsxLocale.tr):
      '“S” sayfasındaki 1 hata hücresi hata kodu içermiyor; boş okunuyor (A1).',
  (
    XlsxWarningCode.formulaGroupInvalid,
    XlsxLocale.en,
  ): "1 formula cell(s) on sheet 'S' belong to a shared, array or data-table formula the file does not define correctly; their values were kept without the formula group (A1).",
  (
    XlsxWarningCode.formulaGroupInvalid,
    XlsxLocale.de,
  ): '1 Formelzelle(n) im Blatt „S“ gehören zu einer gemeinsamen, Matrix- oder Datentabellenformel, die die Datei nicht korrekt definiert; ihre Werte wurden ohne die Formelgruppe beibehalten (A1).',
  (
    XlsxWarningCode.formulaGroupInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 formül hücresi, dosyada doğru tanımlanmamış bir paylaşılan, dizi veya veri tablosu formülüne ait; değerleri formül grubu olmadan korundu (A1).',
  (
    XlsxWarningCode.mergeRangeInvalid,
    XlsxLocale.en,
  ): "1 merged range(s) on sheet 'S' have an invalid reference and were skipped (A1).",
  (
    XlsxWarningCode.mergeRangeInvalid,
    XlsxLocale.de,
  ): '1 verbundene(r) Bereich(e) im Blatt „S“ haben einen ungültigen Bezug und wurden übersprungen (A1).',
  (
    XlsxWarningCode.mergeRangeInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 birleştirilmiş aralığın başvurusu geçersiz; atlandı (A1).',
  (
    XlsxWarningCode.numberFormatInvalid,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' have a number format code that cannot be read; they show with the General format (A1).",
  (
    XlsxWarningCode.numberFormatInvalid,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ haben einen Zahlenformatcode, der nicht gelesen werden kann; sie werden mit dem Format „Standard“ angezeigt (A1).',
  (
    XlsxWarningCode.numberFormatInvalid,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücrenin sayı biçimi kodu okunamıyor; Genel biçimle gösteriliyor (A1).',
  (
    XlsxWarningCode.numberFormatUnsupported,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' have a number format that uses a calendar, numeral system or language this library does not render; they show with Gregorian dates and the default language (A1).",
  (
    XlsxWarningCode.numberFormatUnsupported,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ haben ein Zahlenformat mit einem Kalender, Zahlensystem oder einer Sprache, die diese Bibliothek nicht darstellt; sie werden mit gregorianischem Datum und der Standardsprache angezeigt (A1).',
  (
    XlsxWarningCode.numberFormatUnsupported,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücrenin sayı biçimi bu kitaplığın göstermediği bir takvim, rakam sistemi veya dil kullanıyor; Miladi tarih ve varsayılan dille gösteriliyor (A1).',
  (
    XlsxWarningCode.numberFormatLocaleDependent,
    XlsxLocale.en,
  ): "1 cell(s) on sheet 'S' use a built-in number format whose code depends on the locale and is not in the file; they show with the closest built-in format (A1).",
  (
    XlsxWarningCode.numberFormatLocaleDependent,
    XlsxLocale.de,
  ): '1 Zelle(n) im Blatt „S“ verwenden ein integriertes Zahlenformat, dessen Code vom Gebietsschema abhängt und in der Datei fehlt; sie werden mit dem nächstliegenden integrierten Format angezeigt (A1).',
  (
    XlsxWarningCode.numberFormatLocaleDependent,
    XlsxLocale.tr,
  ): '“S” sayfasındaki 1 hücre, kodu yerel ayara bağlı olan ve dosyada bulunmayan yerleşik bir sayı biçimi kullanıyor; en yakın yerleşik biçimle gösteriliyor (A1).',
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

  test('all 84 messages are worded exactly as specified', () {
    final List<(XlsxWarningCode, XlsxLocale)> keys =
        <(XlsxWarningCode, XlsxLocale)>[
          for (final XlsxWarningCode code in XlsxWarningCode.values)
            for (final XlsxLocale locale in XlsxLocale.values) (code, locale),
        ];
    expect(keys, hasLength(84));
    expect(_expected.keys, unorderedEquals(keys));
    for (final (XlsxWarningCode, XlsxLocale) key in keys) {
      final XlsxWarning w =
          (WarningCollector()..add(
                key.$1,
                sheet: 'S',
                cell: 'A1',
                originalName: 'O',
                detail: '27',
              ))
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

  test('unresolvedNumberFormat names the id', () {
    final XlsxWarning w =
        (WarningCollector()..add(
              XlsxWarningCode.unresolvedNumberFormat,
              sheet: 'S',
              cell: 'A1',
              detail: '27',
            ))
            .warnings
            .single;
    expect(w.message(XlsxLocale.en), contains('format 27'));
    expect(w.message(XlsxLocale.de), contains('Zahlenformat 27'));
    expect(w.message(XlsxLocale.tr), contains('27 numaralı'));
  });

  test('unresolvedNumberFormat without an id is worded exactly', () {
    final XlsxWarning w =
        (WarningCollector()..add(
              XlsxWarningCode.unresolvedNumberFormat,
              sheet: 'S',
              cell: 'A1',
            ))
            .warnings
            .single;
    expect(
      w.message(XlsxLocale.en),
      "1 number cell(s) on sheet 'S' use number formats whose code depends "
      'on the locale or is missing from the file; they read as plain '
      'numbers, even if they show dates (A1).',
    );
    expect(
      w.message(XlsxLocale.de),
      '1 Zahlenzelle(n) im Blatt „S“ verwenden Zahlenformate, deren Code '
      'vom Gebietsschema abhängt oder in der Datei fehlt; sie werden als '
      'einfache Zahlen gelesen, auch wenn sie ein Datum anzeigen (A1).',
    );
    expect(
      w.message(XlsxLocale.tr),
      '“S” sayfasındaki 1 sayı hücresi, kodu yerel ayara bağlı olan veya '
      'dosyada bulunmayan sayı biçimleri kullanıyor; tarih gösterseler bile '
      'düz sayı olarak okunuyor (A1).',
    );
  });

  test('the R2 messages are exact', () {
    XlsxWarning one(XlsxWarningCode code, {String? detail}) =>
        (WarningCollector()..add(code, sheet: 'S', cell: 'A1', detail: detail))
            .warnings
            .single;
    expect(
      one(XlsxWarningCode.mergeRangeInvalid).message(XlsxLocale.tr),
      '“S” sayfasındaki 1 birleştirilmiş aralığın başvurusu geçersiz; '
      'atlandı (A1).',
    );
    expect(
      one(XlsxWarningCode.phantomLeapDay).message(XlsxLocale.en),
      "1 cell(s) on sheet 'S' hold 29 February 1900, a day that did not "
      'exist (Excel counts it for compatibility); they read as numbers (A1).',
    );
  });
}
