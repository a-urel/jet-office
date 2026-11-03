/// Message copy for [DocxWarning]s in English, German and Turkish.
///
/// New in jet_office; not ported from Quds. [formatDocxWarning] switches
/// exhaustively over the warning code and the locale, so adding a code or a
/// locale does not compile until every combination has text.
library;

import '../common/locale.dart';
import 'warnings.dart';

/// The location list of [w] as a message suffix: its paths joined with `, `
/// in parentheses, with a leading space, followed by `, …` when [w] affects
/// more places than it names. Empty when [w] names no location.
String _locationList(DocxWarning w) {
  if (w.locations.isEmpty) return '';
  final String joined = w.locations.join(', ');
  return w.count > w.locations.length ? ' ($joined, …)' : ' ($joined)';
}

/// The message for [w] in [locale].
///
/// Placeholders: the count, the part name (absolute, such as
/// `/word/document.xml`), the location list (up to ten paths, then `, …`,
/// left out when the warning names none) and the detail.
String formatDocxWarning(DocxWarning w, OfficeLocale locale) {
  final int count = w.count;
  final String part = w.part;
  final String locations = _locationList(w);
  final String detail = w.detail ?? '';
  return switch ((w.code, locale)) {
    (DocxWarningCode.invalidCharactersRemoved, OfficeLocale.en) =>
      '$count characters that XML does not allow were removed from text in '
          '$part$locations.',
    (DocxWarningCode.invalidCharactersRemoved, OfficeLocale.de) =>
      '$count Zeichen, die XML nicht erlaubt, wurden aus dem Text in $part '
          'entfernt$locations.',
    (DocxWarningCode.invalidCharactersRemoved, OfficeLocale.tr) =>
      "$part içindeki metinden XML'in izin vermediği $count karakter "
          'çıkarıldı$locations.',
    (DocxWarningCode.contentTypeMissing, OfficeLocale.en) =>
      '$part had no content type; it was read as $detail.',
    (DocxWarningCode.contentTypeMissing, OfficeLocale.de) =>
      'Für $part fehlte der Inhaltstyp; der Teil wurde als $detail gelesen.',
    (DocxWarningCode.contentTypeMissing, OfficeLocale.tr) =>
      '$part için içerik türü yoktu; $detail olarak okundu.',
    (DocxWarningCode.mainPartContentTypeUnexpected, OfficeLocale.en) =>
      'The main document $part has the content type $detail, which is not a '
          'Word document type; it was read as one.',
    (DocxWarningCode.mainPartContentTypeUnexpected, OfficeLocale.de) =>
      'Das Hauptdokument $part hat den Inhaltstyp $detail, der kein '
          'Word-Dokumenttyp ist; es wurde als Word-Dokument gelesen.',
    (DocxWarningCode.mainPartContentTypeUnexpected, OfficeLocale.tr) =>
      'Ana belge $part, Word belge türü olmayan $detail içerik türüne '
          'sahip; Word belgesi olarak okundu.',
  };
}
