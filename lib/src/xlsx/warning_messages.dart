/// Message copy for [XlsxWarning]s in English, German and Turkish.
///
/// New in jet_office. [formatWarning] switches exhaustively over the warning
/// code and the locale, so adding a code or a locale does not compile until
/// every combination has text.
library;

import 'warnings.dart';

/// The references of [w] joined with `, `, followed by `, …` when [w] affects
/// more cells than it names.
String _cellList(XlsxWarning w) {
  final String joined = w.cells.join(', ');
  return w.count > w.cells.length ? '$joined, …' : joined;
}

/// The message for [w] in [locale].
///
/// Placeholders: the count, the sheet and the cell list (up to ten references,
/// then `, …`); sheet-name codes use the requested name instead.
String formatWarning(XlsxWarning w, XlsxLocale locale) {
  final int count = w.count;
  final String sheet = w.sheet;
  final String original = w.originalName ?? w.sheet;
  final String cells = _cellList(w);
  return switch ((w.code, locale)) {
    (XlsxWarningCode.invalidCharactersRemoved, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' had characters removed that XML does not allow ($cells).",
    (XlsxWarningCode.invalidCharactersRemoved, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ enthielten Zeichen, die XML nicht erlaubt; sie wurden entfernt ($cells).',
    (XlsxWarningCode.invalidCharactersRemoved, XlsxLocale.tr) =>
      "“$sheet” sayfasındaki $count hücreden XML'in izin vermediği karakterler çıkarıldı ($cells).",
    (XlsxWarningCode.textTruncated, XlsxLocale.en) =>
      "$count cell(s) on sheet '$sheet' were cut to 32,767 characters, Excel's limit ($cells).",
    (XlsxWarningCode.textTruncated, XlsxLocale.de) =>
      '$count Zelle(n) im Blatt „$sheet“ wurden auf 32.767 Zeichen gekürzt, die Obergrenze von Excel ($cells).',
    (XlsxWarningCode.textTruncated, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count hücre, Excel sınırı olan 32.767 karaktere kısaltıldı ($cells).',
    (XlsxWarningCode.sheetNameChanged, XlsxLocale.en) =>
      "Sheet name '$original' is not allowed in Excel and was changed to '$sheet'.",
    (XlsxWarningCode.sheetNameChanged, XlsxLocale.de) =>
      'Der Blattname „$original“ ist in Excel nicht zulässig und wurde in „$sheet“ geändert.',
    (XlsxWarningCode.sheetNameChanged, XlsxLocale.tr) =>
      "“$original” sayfa adına Excel'de izin verilmiyor; ad “$sheet” olarak değiştirildi.",
    (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.en) =>
      "Sheet name '$original' was already used and was changed to '$sheet'.",
    (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.de) =>
      'Der Blattname „$original“ war bereits vergeben und wurde in „$sheet“ geändert.',
    (XlsxWarningCode.sheetNameDuplicated, XlsxLocale.tr) =>
      '“$original” sayfa adı zaten kullanılıyordu; ad “$sheet” olarak değiştirildi.',
    (XlsxWarningCode.intPrecisionLost, XlsxLocale.en) =>
      "$count whole number(s) on sheet '$sheet' are larger than Excel can store exactly and may be rounded ($cells).",
    (XlsxWarningCode.intPrecisionLost, XlsxLocale.de) =>
      '$count ganze Zahl(en) im Blatt „$sheet“ sind größer, als Excel exakt speichern kann, und werden möglicherweise gerundet ($cells).',
    (XlsxWarningCode.intPrecisionLost, XlsxLocale.tr) =>
      "“$sheet” sayfasındaki $count tam sayı, Excel'in tam olarak saklayabileceğinden büyük; yuvarlanabilir ($cells).",
    (XlsxWarningCode.dateBefore1900, XlsxLocale.en) =>
      "$count date(s) on sheet '$sheet' are before 1900, which Excel cannot store as dates, and were written as text ($cells).",
    (XlsxWarningCode.dateBefore1900, XlsxLocale.de) =>
      '$count Datumswert(e) im Blatt „$sheet“ liegen vor 1900; Excel kann sie nicht als Datum speichern, sie wurden als Text geschrieben ($cells).',
    (XlsxWarningCode.dateBefore1900, XlsxLocale.tr) =>
      "“$sheet” sayfasındaki $count tarih 1900'den önce olduğu için Excel'de tarih olarak saklanamaz; metin olarak yazıldı ($cells).",
    (XlsxWarningCode.dateInNonDateFormat, XlsxLocale.en) =>
      "$count date(s) on sheet '$sheet' use a number format that does not show dates ($cells).",
    (XlsxWarningCode.dateInNonDateFormat, XlsxLocale.de) =>
      '$count Datumswert(e) im Blatt „$sheet“ haben ein Zahlenformat, das kein Datum anzeigt ($cells).',
    (XlsxWarningCode.dateInNonDateFormat, XlsxLocale.tr) =>
      '“$sheet” sayfasındaki $count tarih, tarih göstermeyen bir sayı biçimi kullanıyor ($cells).',
  };
}
