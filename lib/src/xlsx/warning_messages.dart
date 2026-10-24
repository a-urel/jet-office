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
  };
}
