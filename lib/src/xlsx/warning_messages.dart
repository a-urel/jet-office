/// Message copy for [XlsxWarning]s in English, German and Turkish.
///
/// New in jet_office. [formatWarning] switches exhaustively over the warning
/// code and the locale, so adding a code or a locale does not compile until
/// every combination has text.
library;

import '../common/locale.dart';
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
String formatWarning(XlsxWarning w, OfficeLocale locale) {
  final int count = w.count;
  final String sheet = w.sheet;
  final String original = w.originalName ?? w.sheet;
  final String cells = _cellList(w);
  final String id = w.detail ?? '';
  // A feature of the workbook has no sheet.
  final bool book = sheet.isEmpty;
  return switch ((w.code, locale)) {
    (XlsxWarningCode.invalidCharactersRemoved, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' had characters removed that XML does "
          'not allow$cells.',
    (XlsxWarningCode.invalidCharactersRemoved, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthielten Zeichen, die XML nicht '
          'erlaubt; sie wurden entfernt$cells.',
    (XlsxWarningCode.invalidCharactersRemoved, OfficeLocale.tr) =>
      "“$sheet” sayfasındaki $count hücreden XML'in izin vermediği karakterler "
          'çıkarıldı$cells.',
    (XlsxWarningCode.textTruncated, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' were cut to 32,767 characters, Excel's "
          'limit$cells.',
    (XlsxWarningCode.textTruncated, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ wurden auf 32.767 Zeichen gekürzt, '
          'die Obergrenze von Excel$cells.',
    (XlsxWarningCode.textTruncated, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, Excel sınırı olan 32.767 karaktere '
          'kısaltıldı$cells.',
    (XlsxWarningCode.sheetNameChanged, OfficeLocale.en) =>
      "Sheet name '$original' is not allowed in Excel and was changed to "
          "'$sheet'.",
    (XlsxWarningCode.sheetNameChanged, OfficeLocale.de) =>
      'Der Blattname „$original“ ist in Excel nicht zulässig und wurde in '
          '„$sheet“ geändert.',
    (XlsxWarningCode.sheetNameChanged, OfficeLocale.tr) =>
      "“$original” sayfa adına Excel'de izin verilmiyor; ad “$sheet” olarak "
          'değiştirildi.',
    (XlsxWarningCode.sheetNameDuplicated, OfficeLocale.en) =>
      "Sheet name '$original' was already used and was changed to '$sheet'.",
    (XlsxWarningCode.sheetNameDuplicated, OfficeLocale.de) =>
      'Der Blattname „$original“ war bereits vergeben und wurde in „$sheet“ '
          'geändert.',
    (XlsxWarningCode.sheetNameDuplicated, OfficeLocale.tr) =>
      '“$original” sayfa adı zaten kullanılıyordu; ad “$sheet” olarak '
          'değiştirildi.',
    (XlsxWarningCode.intPrecisionLost, OfficeLocale.en) =>
      "$count whole number(s) on sheet '$sheet' are larger than Excel can "
          'store exactly and may be rounded$cells.',
    (XlsxWarningCode.intPrecisionLost, OfficeLocale.de) =>
      '$count ganze Zahl(en) im Blatt „$sheet“ sind größer, als Excel exakt '
          'speichern kann, und werden möglicherweise gerundet$cells.',
    (XlsxWarningCode.intPrecisionLost, OfficeLocale.tr) =>
      "“$sheet” sayfasındaki $count tam sayı, Excel'in tam olarak "
          'saklayabileceğinden büyük; yuvarlanabilir$cells.',
    (XlsxWarningCode.dateOutsideExcelRange, OfficeLocale.en) =>
      "$count date(s) on sheet '$sheet' are outside the range Excel can store "
          'as dates (1900–9999) and were written as text$cells.',
    (XlsxWarningCode.dateOutsideExcelRange, OfficeLocale.de) =>
      '$count Datumswert(e) im Blatt „$sheet“ liegen außerhalb des Bereichs, '
          'den Excel als Datum speichern kann (1900–9999); sie wurden als Text '
          'geschrieben$cells.',
    (XlsxWarningCode.dateOutsideExcelRange, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count tarih, Excel\'in tarih olarak '
          'saklayabildiği aralığın (1900–9999) dışında olduğu için metin '
          'olarak yazıldı$cells.',
    (XlsxWarningCode.dateInNonDateFormat, OfficeLocale.en) =>
      "$count date(s) on sheet '$sheet' use a number format that does not show "
          'dates$cells.',
    (XlsxWarningCode.dateInNonDateFormat, OfficeLocale.de) =>
      '$count Datumswert(e) im Blatt „$sheet“ haben ein Zahlenformat, das kein '
          'Datum anzeigt$cells.',
    (XlsxWarningCode.dateInNonDateFormat, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count tarih, tarih göstermeyen bir sayı biçimi '
          'kullanıyor$cells.',
    (XlsxWarningCode.tableColumnRenamed, OfficeLocale.en) =>
      "$count table header cell(s) on sheet '$sheet' were set, so their "
          'columns were renamed to match; formulas that refer to a column by '
          'its old name are not updated$cells.',
    (XlsxWarningCode.tableColumnRenamed, OfficeLocale.de) =>
      '$count Tabellenkopfzelle(n) im Blatt „$sheet“ wurden gesetzt, daher '
          'wurden ihre Spalten passend umbenannt; Formeln, die eine Spalte '
          'mit ihrem alten Namen ansprechen, werden nicht angepasst$cells.',
    (XlsxWarningCode.tableColumnRenamed, OfficeLocale.tr) =>
      '“$sheet” sayfasında $count tablo başlık hücresi değiştirildi; '
          'sütunları da bu metinle yeniden adlandırıldı. Bir sütuna eski '
          'adıyla başvuran formüller güncellenmedi$cells.',
    (XlsxWarningCode.tableHeaderAdjusted, OfficeLocale.en) =>
      "$count table header cell(s) on sheet '$sheet' were given a different "
          "text, because a table's column names must be unique and not "
          'empty$cells.',
    (XlsxWarningCode.tableHeaderAdjusted, OfficeLocale.de) =>
      '$count Tabellenkopfzelle(n) im Blatt „$sheet“ erhielten einen '
          'anderen Text, weil die Spaltennamen einer Tabelle eindeutig und '
          'nicht leer sein müssen$cells.',
    (XlsxWarningCode.tableHeaderAdjusted, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count tablo başlık hücresine farklı bir metin '
          'yazıldı, çünkü bir tablonun sütun adları benzersiz olmalı ve boş '
          'olamaz$cells.',
    (XlsxWarningCode.sheetPartMissing, OfficeLocale.en) =>
      "Sheet '$sheet' is listed in the workbook but its part is "
          'missing; it reads as empty.',
    (XlsxWarningCode.sheetPartMissing, OfficeLocale.de) =>
      'Das Blatt „$sheet“ ist in der Arbeitsmappe aufgeführt, '
          'aber sein Teil fehlt in der Datei; es wird als leer '
          'gelesen.',
    (XlsxWarningCode.sheetPartMissing, OfficeLocale.tr) =>
      '“$sheet” sayfası çalışma kitabında listeleniyor ancak '
          'sayfa parçası dosyada yok; boş okunuyor.',
    (XlsxWarningCode.sharedStringInvalid, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' point to a shared "
          'string that does not exist; they read as empty$cells.',
    (XlsxWarningCode.sharedStringInvalid, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ verweisen auf eine '
          'gemeinsame Zeichenfolge, die nicht existiert; sie werden '
          'als leer gelesen$cells.',
    (XlsxWarningCode.sharedStringInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, var olmayan bir '
          'paylaşılan dizeye başvuruyor; boş okunuyor$cells.',
    (XlsxWarningCode.numberInvalid, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' hold a number that "
          'cannot be read; they read as empty$cells.',
    (XlsxWarningCode.numberInvalid, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthalten eine Zahl, '
          'die nicht gelesen werden kann; sie werden als leer '
          'gelesen$cells.',
    (XlsxWarningCode.numberInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre okunamayan bir sayı '
          'içeriyor; boş okunuyor$cells.',
    (XlsxWarningCode.booleanInvalid, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' hold a boolean other "
          'than 0 or 1; they read as empty$cells.',
    (XlsxWarningCode.booleanInvalid, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthalten einen '
          'Wahrheitswert, der weder 0 noch 1 ist; sie werden als '
          'leer gelesen$cells.',
    (XlsxWarningCode.booleanInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre 0 veya 1 dışında bir '
          'mantıksal değer içeriyor; boş okunuyor$cells.',
    (XlsxWarningCode.cellTypeUnsupported, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' have a type or content the "
          'reader does not support; their value may be empty or read from '
          'the stored value$cells.',
    (XlsxWarningCode.cellTypeUnsupported, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben einen Typ oder Inhalt, '
          'den der Reader nicht unterstützt; ihr Wert ist möglicherweise '
          'leer oder stammt aus dem gespeicherten Wert$cells.',
    (XlsxWarningCode.cellTypeUnsupported, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, okuyucunun '
          'desteklemediği bir tür veya içerik taşıyor; değeri boş olabilir '
          'ya da kayıtlı değerden okunur$cells.',
    (XlsxWarningCode.formulaWithoutValue, OfficeLocale.en) =>
      "$count formula cell(s) on sheet '$sheet' have no saved "
          'result; they read as empty$cells.',
    (XlsxWarningCode.formulaWithoutValue, OfficeLocale.de) =>
      '$count Formelzelle(n) im Blatt „$sheet“ haben kein '
          'gespeichertes Ergebnis; sie werden als leer '
          'gelesen$cells.',
    (XlsxWarningCode.formulaWithoutValue, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count formül hücresinin kayıtlı '
          'sonucu yok; boş okunuyor$cells.',
    (XlsxWarningCode.cellReferenceInvalid, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' have an invalid "
          'reference; they were placed after the previous '
          'cell$cells.',
    (XlsxWarningCode.cellReferenceInvalid, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben einen ungültigen '
          'Zellbezug; sie wurden hinter der vorherigen Zelle '
          'eingefügt$cells.',
    (XlsxWarningCode.cellReferenceInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücrenin başvurusu '
          'geçersiz; hücre, önceki hücrenin ardına '
          'yerleştirildi$cells.',
    (XlsxWarningCode.cellDuplicated, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' appear more than once; "
          'the last one was kept$cells.',
    (XlsxWarningCode.cellDuplicated, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ kommen mehrfach vor; '
          'die letzte wurde beibehalten$cells.',
    (XlsxWarningCode.cellDuplicated, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre birden fazla kez '
          'geçiyor; sonuncusu korundu$cells.',
    (XlsxWarningCode.rowOutOfOrder, OfficeLocale.en) =>
      "$count row(s) on sheet '$sheet' are out of order; they "
          'were read in file order$cells.',
    (XlsxWarningCode.rowOutOfOrder, OfficeLocale.de) =>
      '$count Zeile(n) im Blatt „$sheet“ stehen nicht in der '
          'richtigen Reihenfolge; sie wurden in der Reihenfolge der '
          'Datei gelesen$cells.',
    (XlsxWarningCode.rowOutOfOrder, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count satır sıralı değil; dosyadaki '
          'sırayla okundu$cells.',
    (XlsxWarningCode.cellOutsideSheet, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' lie outside Excel's "
          'grid and were skipped$cells.',
    (XlsxWarningCode.cellOutsideSheet, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ liegen außerhalb des '
          'Excel-Rasters und wurden übersprungen$cells.',
    (XlsxWarningCode.cellOutsideSheet, OfficeLocale.tr) =>
      "“$sheet” sayfasındaki $count hücre, Excel'in sayfa sınırları "
          'dışında kaldığı için atlandı$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, OfficeLocale.en)
        when w.detail == null =>
      "$count number cell(s) on sheet '$sheet' use number formats whose code "
          'depends on the locale or is missing from the file; they read as '
          'plain numbers, even if they show dates$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, OfficeLocale.de)
        when w.detail == null =>
      '$count Zahlenzelle(n) im Blatt „$sheet“ verwenden Zahlenformate, '
          'deren Code vom Gebietsschema abhängt oder in der Datei fehlt; sie '
          'werden als einfache Zahlen gelesen, auch wenn sie ein Datum '
          'anzeigen$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, OfficeLocale.tr)
        when w.detail == null =>
      '“$sheet” sayfasındaki $count sayı hücresi, kodu yerel ayara bağlı '
          'olan ya da dosyada bulunmayan sayı biçimleri kullanıyor; tarih '
          'gösterseler bile düz sayı olarak okunuyor$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, OfficeLocale.en) =>
      "$count number cell(s) on sheet '$sheet' use built-in number "
          'format $id, whose code depends on the locale and is not in the '
          'file; they read as plain numbers, even if they show '
          'dates$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, OfficeLocale.de) =>
      '$count Zahlenzelle(n) im Blatt „$sheet“ verwenden das '
          'integrierte Zahlenformat $id, dessen Code vom Gebietsschema '
          'abhängt und nicht in der Datei steht; sie werden als einfache '
          'Zahlen gelesen, auch wenn sie ein Datum anzeigen$cells.',
    (XlsxWarningCode.unresolvedNumberFormat, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count sayı hücresi, kodu yerel ayara '
          'bağlı olan ve dosyada bulunmayan $id numaralı yerleşik sayı '
          'biçimini kullanıyor; tarih gösterseler bile düz sayı olarak '
          'okunuyor$cells.',
    (XlsxWarningCode.styleInvalid, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' point to a cell format that "
          'does not exist or cannot be read; they read with the General '
          'format$cells.',
    (XlsxWarningCode.styleInvalid, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ verweisen auf ein Zellformat, '
          'das nicht existiert oder nicht gelesen werden kann; sie werden '
          'mit dem Format „Standard“ gelesen$cells.',
    (XlsxWarningCode.styleInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, var olmayan veya okunamayan '
          'bir hücre biçimine başvuruyor; Genel biçimle okunuyor$cells.',
    (XlsxWarningCode.serialOutOfRange, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' are formatted as a date or "
          'time but hold a number no date or time can have; they read as '
          'numbers$cells.',
    (XlsxWarningCode.serialOutOfRange, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ sind als Datum oder Uhrzeit '
          'formatiert, enthalten aber eine Zahl, die kein Datum und keine '
          'Uhrzeit sein kann; sie werden als Zahlen gelesen$cells.',
    (XlsxWarningCode.serialOutOfRange, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre tarih veya saat olarak '
          'biçimlendirilmiş, ancak hiçbir tarih ya da saatin alamayacağı '
          'bir sayı içeriyor; sayı olarak okunuyor$cells.',
    (XlsxWarningCode.phantomLeapDay, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' hold 29 February 1900, a day "
          'that did not exist (Excel counts it for compatibility); they '
          'read as numbers$cells.',
    (XlsxWarningCode.phantomLeapDay, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthalten den 29. Februar '
          '1900, einen Tag, den es nicht gab (Excel zählt ihn aus '
          'Kompatibilitätsgründen); sie werden als Zahlen gelesen$cells.',
    (XlsxWarningCode.phantomLeapDay, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, hiç var olmamış bir gün '
          "olan 29 Şubat 1900'ü içeriyor (Excel bu günü uyumluluk için "
          'sayar); sayı olarak okunuyor$cells.',
    (XlsxWarningCode.dateTextInvalid, OfficeLocale.en) =>
      "$count date cell(s) on sheet '$sheet' hold text that is not a "
          'valid date; they read as empty$cells.',
    (XlsxWarningCode.dateTextInvalid, OfficeLocale.de) =>
      '$count Datumszelle(n) im Blatt „$sheet“ enthalten Text, der '
          'kein gültiges Datum ist; sie werden als leer gelesen$cells.',
    (XlsxWarningCode.dateTextInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count tarih hücresi geçerli bir tarih '
          'olmayan metin içeriyor; boş okunuyor$cells.',
    (XlsxWarningCode.errorValueInvalid, OfficeLocale.en) =>
      "$count error cell(s) on sheet '$sheet' hold no error code; they "
          'read as empty$cells.',
    (XlsxWarningCode.errorValueInvalid, OfficeLocale.de) =>
      '$count Fehlerzelle(n) im Blatt „$sheet“ enthalten keinen '
          'Fehlercode; sie werden als leer gelesen$cells.',
    (XlsxWarningCode.errorValueInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hata hücresi hata kodu içermiyor; '
          'boş okunuyor$cells.',
    (XlsxWarningCode.formulaGroupInvalid, OfficeLocale.en) =>
      "$count formula cell(s) on sheet '$sheet' belong to a shared, "
          'array or data-table formula the file does not define correctly; '
          'their values were kept without the formula group$cells.',
    (XlsxWarningCode.formulaGroupInvalid, OfficeLocale.de) =>
      '$count Formelzelle(n) im Blatt „$sheet“ gehören zu einer '
          'gemeinsamen, Matrix- oder Datentabellenformel, die die Datei '
          'nicht korrekt definiert; ihre Werte wurden ohne die '
          'Formelgruppe beibehalten$cells.',
    (XlsxWarningCode.formulaGroupInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count formül hücresi, dosyada doğru '
          'tanımlanmamış bir paylaşılan, dizi veya veri tablosu formülüne '
          'ait; kayıtlı değerleri korundu, formül grubu yok sayıldı$cells.',
    (XlsxWarningCode.mergeRangeInvalid, OfficeLocale.en) =>
      "$count merged range(s) on sheet '$sheet' have an invalid "
          'reference and were skipped$cells.',
    (XlsxWarningCode.mergeRangeInvalid, OfficeLocale.de) =>
      '$count verbundene(r) Bereich(e) im Blatt „$sheet“ haben einen '
          'ungültigen Bezug und wurden übersprungen$cells.',
    (XlsxWarningCode.mergeRangeInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count birleştirilmiş aralığın başvurusu '
          'geçersiz; atlandı$cells.',
    (XlsxWarningCode.numberFormatInvalid, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' have a number format code that "
          'cannot be read; they show with the General format$cells.',
    (XlsxWarningCode.numberFormatInvalid, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben einen Zahlenformatcode, '
          'der nicht gelesen werden kann; sie werden mit dem Format '
          '„Standard“ angezeigt$cells.',
    (XlsxWarningCode.numberFormatInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücrenin sayı biçimi kodu '
          'okunamıyor; Genel biçimle gösteriliyor$cells.',
    (XlsxWarningCode.numberFormatUnsupported, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' have a number format that uses a "
          'calendar, numeral system or language this library does not '
          'render; they show with Gregorian dates, Western digits and the '
          'default language$cells.',
    (XlsxWarningCode.numberFormatUnsupported, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ haben ein Zahlenformat mit einem '
          'Kalender, Zahlensystem oder einer Sprache, die diese Bibliothek '
          'nicht darstellt; sie werden mit gregorianischem Datum, westlichen '
          'Ziffern und der Standardsprache angezeigt$cells.',
    (XlsxWarningCode.numberFormatUnsupported, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücrenin sayı biçimi bu kitaplığın '
          'göstermediği bir takvim, rakam sistemi veya dil kullanıyor; '
          'Miladi tarih, Batı rakamları ve varsayılan dille gösteriliyor$cells.',
    (XlsxWarningCode.numberFormatLocaleDependent, OfficeLocale.en) =>
      "$count cell(s) on sheet '$sheet' use a built-in number format whose "
          'code depends on the locale and is not in the file; they show with '
          'the closest built-in format$cells.',
    (XlsxWarningCode.numberFormatLocaleDependent, OfficeLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ verwenden ein integriertes '
          'Zahlenformat, dessen Code vom Gebietsschema abhängt und in der '
          'Datei fehlt; sie werden mit dem nächstliegenden integrierten '
          'Format angezeigt$cells.',
    (XlsxWarningCode.numberFormatLocaleDependent, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, kodu yerel ayara bağlı olan ve '
          'dosyada bulunmayan yerleşik bir sayı biçimi kullanıyor; en yakın '
          'yerleşik biçimle gösteriliyor$cells.',
    (XlsxWarningCode.styleEntryInvalid, OfficeLocale.en)
        when w.detail == null =>
      '$count style entries of the workbook cannot be read exactly; what '
          'cannot be read takes its default, and the entries are saved as '
          'written.',
    (XlsxWarningCode.styleEntryInvalid, OfficeLocale.de)
        when w.detail == null =>
      '$count Formatierungseinträge der Arbeitsmappe können nicht exakt '
          'gelesen werden; was nicht gelesen werden kann, erhält den '
          'Standardwert, und die Einträge werden unverändert gespeichert.',
    (XlsxWarningCode.styleEntryInvalid, OfficeLocale.tr)
        when w.detail == null =>
      'Çalışma kitabındaki $count biçim girdisi tam olarak okunamıyor; '
          'okunamayan kısımlar varsayılan değeri alıyor ve girdiler olduğu '
          'gibi kaydediliyor.',
    (XlsxWarningCode.styleEntryInvalid, OfficeLocale.en) =>
      'A style entry of the workbook cannot be read exactly ($id); what '
          'cannot be read takes its default, and the entry is saved as '
          'written.',
    (XlsxWarningCode.styleEntryInvalid, OfficeLocale.de) =>
      'Ein Formatierungseintrag der Arbeitsmappe kann nicht exakt gelesen '
          'werden ($id); was nicht gelesen werden kann, erhält den '
          'Standardwert, und der Eintrag wird unverändert gespeichert.',
    (XlsxWarningCode.styleEntryInvalid, OfficeLocale.tr) =>
      'Çalışma kitabındaki bir biçim girdisi tam olarak okunamıyor ($id); '
          'okunamayan kısımlar varsayılan değeri alıyor ve girdi olduğu gibi '
          'kaydediliyor.',
    (XlsxWarningCode.layoutInvalid, OfficeLocale.en) when w.detail == null =>
      "$count layout settings of sheet '$sheet' cannot be read exactly; "
          'what cannot be read takes its default, and the settings are saved '
          'as written.',
    (XlsxWarningCode.layoutInvalid, OfficeLocale.de) when w.detail == null =>
      '$count Layouteinstellungen im Blatt „$sheet“ können nicht exakt '
          'gelesen werden; was nicht gelesen werden kann, erhält den '
          'Standardwert, und die Einstellungen werden unverändert '
          'gespeichert.',
    (XlsxWarningCode.layoutInvalid, OfficeLocale.tr) when w.detail == null =>
      '“$sheet” sayfasındaki $count düzen ayarı tam olarak okunamıyor; '
          'okunamayan kısımlar varsayılan değeri alıyor ve ayarlar olduğu '
          'gibi kaydediliyor.',
    (XlsxWarningCode.layoutInvalid, OfficeLocale.en) =>
      "A layout setting of sheet '$sheet' cannot be read exactly ($id); what "
          'cannot be read takes its default, and the setting is saved as '
          'written.',
    (XlsxWarningCode.layoutInvalid, OfficeLocale.de) =>
      'Eine Layouteinstellung im Blatt „$sheet“ kann nicht exakt gelesen '
          'werden ($id); was nicht gelesen werden kann, erhält den '
          'Standardwert, und die Einstellung wird unverändert gespeichert.',
    (XlsxWarningCode.layoutInvalid, OfficeLocale.tr) =>
      '“$sheet” sayfasındaki bir düzen ayarı tam olarak okunamıyor ($id); '
          'okunamayan kısımlar varsayılan değeri alıyor ve ayar olduğu gibi '
          'kaydediliyor.',
    (XlsxWarningCode.featureEntryInvalid, OfficeLocale.en)
        when w.detail == null =>
      "$count feature entries of ${book ? 'the workbook' : "sheet '$sheet'"} "
          'cannot be read; they are kept as written and left out of the typed '
          'lists.',
    (XlsxWarningCode.featureEntryInvalid, OfficeLocale.de)
        when w.detail == null =>
      '$count Funktionseinträge ${book ? 'der Arbeitsmappe' : 'im Blatt „$sheet“'} '
          'können nicht gelesen werden; sie werden unverändert gespeichert '
          'und in den Listen ausgelassen.',
    (XlsxWarningCode.featureEntryInvalid, OfficeLocale.tr)
        when w.detail == null =>
      '${book ? 'Çalışma kitabındaki' : '“$sheet” sayfasındaki'} $count '
          'özellik girdisi okunamıyor; olduğu gibi korunuyor ve '
          'listelere alınmıyor.',
    (XlsxWarningCode.featureEntryInvalid, OfficeLocale.en) =>
      "A feature entry of ${book ? 'the workbook' : "sheet '$sheet'"} cannot "
          'be read ($id); it is kept as written and left out of the typed '
          'list.',
    (XlsxWarningCode.featureEntryInvalid, OfficeLocale.de) =>
      'Ein Funktionseintrag ${book ? 'der Arbeitsmappe' : 'im Blatt „$sheet“'} '
          'kann nicht gelesen werden ($id); er wird unverändert gespeichert '
          'und in der Liste ausgelassen.',
    (XlsxWarningCode.featureEntryInvalid, OfficeLocale.tr) =>
      '${book ? 'Çalışma kitabındaki' : '“$sheet” sayfasındaki'} bir özellik '
          'girdisi okunamıyor ($id); olduğu gibi korunuyor ve listeye '
          'alınmıyor.',
  };
}
