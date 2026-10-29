/// Message copy for [XlsxWarning]s in English, German and Turkish.
///
/// New in jet_office. [formatWarning] switches exhaustively over the warning
/// code and the locale, so adding a code or a locale does not compile until
/// every combination has text.
library;

import 'warnings.dart';

/// The cell list of [w] as a message suffix: its references joined with `, `
/// in parentheses, with a leading space, followed by `, …` when [w] affects
/// more cells than it names. Empty when [w] names no cell.
String _cellList(XlsxWarning w) {
  if (w.cells.isEmpty) return '';
  final String joined = w.cells.join(', ');
  return w.count > w.cells.length ? ' ($joined, …)' : ' ($joined)';
}

/// The message for [w] in [locale].
///
/// Placeholders: the count, the sheet and the cell list (up to ten references,
/// then `, …`, left out when the warning names no cell). Sheet-name codes use
/// the requested name instead: [XlsxWarning.originalName], or
/// [XlsxWarning.sheet] when the warning has none.
String formatWarning(XlsxWarning w, XlsxLocale locale) {
  final int count = w.count;
  final String sheet = w.sheet;
  final String original = w.originalName ?? w.sheet;
  final String cells = _cellList(w);
  final String id = w.detail ?? '';
  return switch ((w.code, locale)) {
    (XlsxWarningCode.invalidCharactersRemoved, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' had characters removed that XML does "
          'not allow$cells.',
    (XlsxWarningCode.invalidCharactersRemoved, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthielten Zeichen, die XML nicht '
          'erlaubt; sie wurden entfernt$cells.',
    (XlsxWarningCode.invalidCharactersRemoved, XlsxLocale.tr) =>
      "“$sheet” sayfasındaki $count hücreden XML'in izin vermediği karakterler "
          'çıkarıldı$cells.',
    (XlsxWarningCode.textTruncated, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' were cut to 32,767 characters, Excel's "
          'limit$cells.',
    (XlsxWarningCode.textTruncated, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ wurden auf 32.767 Zeichen gekürzt, '
          'die Obergrenze von Excel$cells.',
    (XlsxWarningCode.textTruncated, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, Excel sınırı olan 32.767 karaktere '
          'kısaltıldı$cells.',
    (XlsxWarningCode.sheetNameChanged, XlsxLocale.en) =>
      "Sheet name '$original' is not allowed in Excel and was changed to "
          "'$sheet'.",
    (XlsxWarningCode.sheetNameChanged, XlsxLocale.de) =>
      'Der Blattname „$original“ ist in Excel nicht zulässig und wurde in '
          '„$sheet“ geändert.',
    (XlsxWarningCode.sheetNameChanged, XlsxLocale.tr) =>
      "“$original” sayfa adına Excel'de izin verilmiyor; ad “$sheet” olarak "
          'değiştirildi.',
    (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.en) =>
      "Sheet name '$original' was already used and was changed to '$sheet'.",
    (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.de) =>
      'Der Blattname „$original“ war bereits vergeben und wurde in „$sheet“ '
          'geändert.',
    (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.tr) =>
      '“$original” sayfa adı zaten kullanılıyordu; ad “$sheet” olarak '
          'değiştirildi.',
    (XlsxWarningCode.intPrecisionLost, XlsxLocale.en) =>
      "$count whole number(s) on sheet '$sheet' are larger than Excel can "
          'store exactly and may be rounded$cells.',
    (XlsxWarningCode.intPrecisionLost, XlsxLocale.de) =>
      '$count ganze Zahl(en) im Blatt „$sheet“ sind größer, als Excel exakt '
          'speichern kann, und werden möglicherweise gerundet$cells.',
    (XlsxWarningCode.intPrecisionLost, XlsxLocale.tr) =>
      "“$sheet” sayfasındaki $count tam sayı, Excel'in tam olarak "
          'saklayabileceğinden büyük; yuvarlanabilir$cells.',
    (XlsxWarningCode.dateOutsideExcelRange, XlsxLocale.en) =>
      "$count date(s) on sheet '$sheet' are outside the range Excel can store "
          'as dates (1900–9999) and were written as text$cells.',
    (XlsxWarningCode.dateOutsideExcelRange, XlsxLocale.de) =>
      '$count Datumswert(e) im Blatt „$sheet“ liegen außerhalb des Bereichs, '
          'den Excel als Datum speichern kann (1900–9999); sie wurden als Text '
          'geschrieben$cells.',
    (XlsxWarningCode.dateOutsideExcelRange, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count tarih, Excel\'in tarih olarak '
          'saklayabildiği aralığın (1900–9999) dışında olduğu için metin '
          'olarak yazıldı$cells.',
    (XlsxWarningCode.dateInNonDateFormat, XlsxLocale.en) =>
      "$count date(s) on sheet '$sheet' use a number format that does not show "
          'dates$cells.',
    (XlsxWarningCode.dateInNonDateFormat, XlsxLocale.de) =>
      '$count Datumswert(e) im Blatt „$sheet“ haben ein Zahlenformat, das kein '
          'Datum anzeigt$cells.',
    (XlsxWarningCode.dateInNonDateFormat, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count tarih, tarih göstermeyen bir sayı biçimi '
          'kullanıyor$cells.',
    (XlsxWarningCode.sheetPartMissing, XlsxLocale.en) =>
      "Sheet '$sheet' is listed in the workbook but its part is "
          'missing; it reads as empty.',
    (XlsxWarningCode.sheetPartMissing, XlsxLocale.de) =>
      'Das Blatt „$sheet“ ist in der Arbeitsmappe aufgeführt, '
          'aber sein Teil fehlt in der Datei; es wird als leer '
          'gelesen.',
    (XlsxWarningCode.sheetPartMissing, XlsxLocale.tr) =>
      '“$sheet” sayfası çalışma kitabında listeleniyor ancak '
          'sayfa parçası dosyada yok; boş okunuyor.',
    (XlsxWarningCode.sharedStringInvalid, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' point to a shared "
          'string that does not exist; they read as empty$cells.',
    (XlsxWarningCode.sharedStringInvalid, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ verweisen auf eine '
          'gemeinsame Zeichenfolge, die nicht existiert; sie werden '
          'als leer gelesen$cells.',
    (XlsxWarningCode.sharedStringInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, var olmayan bir '
          'paylaşılan dizeye başvuruyor; boş okunuyor$cells.',
    (XlsxWarningCode.numberInvalid, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' hold a number that "
          'cannot be read; they read as empty$cells.',
    (XlsxWarningCode.numberInvalid, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthalten eine Zahl, '
          'die nicht gelesen werden kann; sie werden als leer '
          'gelesen$cells.',
    (XlsxWarningCode.numberInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre okunamayan bir sayı '
          'içeriyor; boş okunuyor$cells.',
    (XlsxWarningCode.booleanInvalid, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' hold a boolean other "
          'than 0 or 1; they read as empty$cells.',
    (XlsxWarningCode.booleanInvalid, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthalten einen '
          'Wahrheitswert, der weder 0 noch 1 ist; sie werden als '
          'leer gelesen$cells.',
    (XlsxWarningCode.booleanInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre 0 veya 1 dışında bir '
          'mantıksal değer içeriyor; boş okunuyor$cells.',
    (XlsxWarningCode.cellTypeUnsupported, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' have a type the reader "
          'does not support; they read as empty$cells.',
    (XlsxWarningCode.cellTypeUnsupported, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben einen Typ, den '
          'der Reader nicht unterstützt; sie werden als leer '
          'gelesen$cells.',
    (XlsxWarningCode.cellTypeUnsupported, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, okuyucunun '
          'desteklemediği bir türde; boş okunuyor$cells.',
    (XlsxWarningCode.formulaWithoutValue, XlsxLocale.en) =>
      "$count formula cell(s) on sheet '$sheet' have no saved "
          'result; they read as empty$cells.',
    (XlsxWarningCode.formulaWithoutValue, XlsxLocale.de) =>
      '$count Formelzelle(n) im Blatt „$sheet“ haben kein '
          'gespeichertes Ergebnis; sie werden als leer '
          'gelesen$cells.',
    (XlsxWarningCode.formulaWithoutValue, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count formül hücresinin kayıtlı '
          'sonucu yok; boş okunuyor$cells.',
    (XlsxWarningCode.cellReferenceInvalid, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' have an invalid "
          'reference; they were placed after the previous '
          'cell$cells.',
    (XlsxWarningCode.cellReferenceInvalid, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben einen ungültigen '
          'Zellbezug; sie wurden hinter der vorherigen Zelle '
          'eingefügt$cells.',
    (XlsxWarningCode.cellReferenceInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücrenin başvurusu '
          'geçersiz; hücre, önceki hücrenin ardına '
          'yerleştirildi$cells.',
    (XlsxWarningCode.cellDuplicated, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' appear more than once; "
          'the last one was kept$cells.',
    (XlsxWarningCode.cellDuplicated, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ kommen mehrfach vor; '
          'die letzte wurde beibehalten$cells.',
    (XlsxWarningCode.cellDuplicated, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre birden fazla kez '
          'geçiyor; sonuncusu korundu$cells.',
    (XlsxWarningCode.rowOutOfOrder, XlsxLocale.en) =>
      "$count row(s) on sheet '$sheet' are out of order; they "
          'were read in file order$cells.',
    (XlsxWarningCode.rowOutOfOrder, XlsxLocale.de) =>
      '$count Zeile(n) im Blatt „$sheet“ stehen nicht in der '
          'richtigen Reihenfolge; sie wurden in der Reihenfolge der '
          'Datei gelesen$cells.',
    (XlsxWarningCode.rowOutOfOrder, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count satır sırasız; dosyadaki '
          'sırayla okundu$cells.',
    (XlsxWarningCode.cellOutsideSheet, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' lie outside Excel's "
          'grid and were skipped$cells.',
    (XlsxWarningCode.cellOutsideSheet, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ liegen außerhalb des '
          'Excel-Rasters und wurden übersprungen$cells.',
    (XlsxWarningCode.cellOutsideSheet, XlsxLocale.tr) =>
      "“$sheet” sayfasındaki $count hücre, Excel'in ızgarasının "
          'dışında kaldığı için atlandı$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, XlsxLocale.en)
        when w.detail == null =>
      "$count number cell(s) on sheet '$sheet' use number formats whose code "
          'depends on the locale or is missing from the file; they read as '
          'plain numbers, even if they show dates$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, XlsxLocale.de)
        when w.detail == null =>
      '$count Zahlenzelle(n) im Blatt „$sheet“ verwenden Zahlenformate, '
          'deren Code vom Gebietsschema abhängt oder in der Datei fehlt; sie '
          'werden als einfache Zahlen gelesen, auch wenn sie ein Datum '
          'anzeigen$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, XlsxLocale.tr)
        when w.detail == null =>
      '“$sheet” sayfasındaki $count sayı hücresi, kodu yerel ayara bağlı '
          'olan veya dosyada bulunmayan sayı biçimleri kullanıyor; tarih '
          'gösterseler bile düz sayı olarak okunuyor$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, XlsxLocale.en) =>
      "$count number cell(s) on sheet '$sheet' use built-in number "
          'format $id, whose code depends on the locale and is not in the '
          'file; they read as plain numbers, even if they show '
          'dates$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, XlsxLocale.de) =>
      '$count Zahlenzelle(n) im Blatt „$sheet“ verwenden das '
          'integrierte Zahlenformat $id, dessen Code vom Gebietsschema '
          'abhängt und nicht in der Datei steht; sie werden als einfache '
          'Zahlen gelesen, auch wenn sie ein Datum anzeigen$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count sayı hücresi, kodu yerel ayara '
          'bağlı olan ve dosyada bulunmayan $id numaralı yerleşik sayı '
          'biçimini kullanıyor; tarih gösterseler bile düz sayı olarak '
          'okunuyor$cells.',
    (XlsxWarningCode.styleInvalid, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' point to a cell format that "
          'does not exist or cannot be read; they read with the General '
          'format$cells.',
    (XlsxWarningCode.styleInvalid, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ verweisen auf ein Zellformat, '
          'das nicht existiert oder nicht gelesen werden kann; sie werden '
          'mit dem Format „Standard“ gelesen$cells.',
    (XlsxWarningCode.styleInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, var olmayan veya okunamayan '
          'bir hücre biçimine başvuruyor; Genel biçimle okunuyor$cells.',
    (XlsxWarningCode.serialOutOfRange, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' are formatted as a date or "
          'time but hold a number no date or time can have; they read as '
          'numbers$cells.',
    (XlsxWarningCode.serialOutOfRange, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ sind als Datum oder Uhrzeit '
          'formatiert, enthalten aber eine Zahl, die kein Datum und keine '
          'Uhrzeit sein kann; sie werden als Zahlen gelesen$cells.',
    (XlsxWarningCode.serialOutOfRange, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre tarih veya saat olarak '
          'biçimlendirilmiş, ancak hiçbir tarih ya da saatin alamayacağı '
          'bir sayı içeriyor; sayı olarak okunuyor$cells.',
    (XlsxWarningCode.phantomLeapDay, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' hold 29 February 1900, a day "
          'that did not exist (Excel counts it for compatibility); they '
          'read as numbers$cells.',
    (XlsxWarningCode.phantomLeapDay, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthalten den 29. Februar '
          '1900, einen Tag, den es nicht gab (Excel zählt ihn aus '
          'Kompatibilitätsgründen); sie werden als Zahlen gelesen$cells.',
    (XlsxWarningCode.phantomLeapDay, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, hiç var olmamış bir gün '
          "olan 29 Şubat 1900'ü içeriyor (Excel bu günü uyumluluk için "
          'sayar); sayı olarak okunuyor$cells.',
    (XlsxWarningCode.dateTextInvalid, XlsxLocale.en) =>
      "$count date cell(s) on sheet '$sheet' hold text that is not a "
          'valid date; they read as empty$cells.',
    (XlsxWarningCode.dateTextInvalid, XlsxLocale.de) =>
      '$count Datumszelle(n) im Blatt „$sheet“ enthalten Text, der '
          'kein gültiges Datum ist; sie werden als leer gelesen$cells.',
    (XlsxWarningCode.dateTextInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count tarih hücresi geçerli bir tarih '
          'olmayan metin içeriyor; boş okunuyor$cells.',
    (XlsxWarningCode.errorValueInvalid, XlsxLocale.en) =>
      "$count error cell(s) on sheet '$sheet' hold no error code; they "
          'read as empty$cells.',
    (XlsxWarningCode.errorValueInvalid, XlsxLocale.de) =>
      '$count Fehlerzelle(n) im Blatt „$sheet“ enthalten keinen '
          'Fehlercode; sie werden als leer gelesen$cells.',
    (XlsxWarningCode.errorValueInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hata hücresi hata kodu içermiyor; '
          'boş okunuyor$cells.',
    (XlsxWarningCode.formulaGroupInvalid, XlsxLocale.en) =>
      "$count formula cell(s) on sheet '$sheet' belong to a shared, "
          'array or data-table formula the file does not define correctly; '
          'their values were kept without the formula group$cells.',
    (XlsxWarningCode.formulaGroupInvalid, XlsxLocale.de) =>
      '$count Formelzelle(n) im Blatt „$sheet“ gehören zu einer '
          'gemeinsamen, Matrix- oder Datentabellenformel, die die Datei '
          'nicht korrekt definiert; ihre Werte wurden ohne die '
          'Formelgruppe beibehalten$cells.',
    (XlsxWarningCode.formulaGroupInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count formül hücresi, dosyada doğru '
          'tanımlanmamış bir paylaşılan, dizi veya veri tablosu formülüne '
          'ait; değerleri formül grubu olmadan korundu$cells.',
    (XlsxWarningCode.mergeRangeInvalid, XlsxLocale.en) =>
      "$count merged range(s) on sheet '$sheet' have an invalid "
          'reference and were skipped$cells.',
    (XlsxWarningCode.mergeRangeInvalid, XlsxLocale.de) =>
      '$count verbundene(r) Bereich(e) im Blatt „$sheet“ haben einen '
          'ungültigen Bezug und wurden übersprungen$cells.',
    (XlsxWarningCode.mergeRangeInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count birleştirilmiş aralığın başvurusu '
          'geçersiz; atlandı$cells.',
    (XlsxWarningCode.numberFormatInvalid, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' have a number format code that "
          'cannot be read; they show with the General format$cells.',
    (XlsxWarningCode.numberFormatInvalid, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben einen Zahlenformatcode, '
          'der nicht gelesen werden kann; sie werden mit dem Format '
          '„Standard“ angezeigt$cells.',
    (XlsxWarningCode.numberFormatInvalid, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücrenin sayı biçimi kodu '
          'okunamıyor; Genel biçimle gösteriliyor$cells.',
    (XlsxWarningCode.numberFormatUnsupported, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' have a number format that uses a "
          'calendar, numeral system or language this library does not '
          'render; they show with Gregorian dates and the default '
          'language$cells.',
    (XlsxWarningCode.numberFormatUnsupported, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben ein Zahlenformat mit einem '
          'Kalender, Zahlensystem oder einer Sprache, die diese Bibliothek '
          'nicht darstellt; sie werden mit gregorianischem Datum und der '
          'Standardsprache angezeigt$cells.',
    (XlsxWarningCode.numberFormatUnsupported, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücrenin sayı biçimi bu kitaplığın '
          'göstermediği bir takvim, rakam sistemi veya dil kullanıyor; '
          'Miladi tarih ve varsayılan dille gösteriliyor$cells.',
  };
}
