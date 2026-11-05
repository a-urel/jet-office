/// Message copy for [DocxWarning]s in English, German and Turkish.
///
/// New in jet_office; not ported from Quds. [formatDocxWarning] switches
/// exhaustively over the warning code and the locale, so adding a code or a
/// locale does not compile until every combination has text.
library;

import '../common/locale.dart';
import 'warnings.dart';

/// The location list of [w] as a message suffix: its paths joined with `, `
/// in parentheses, with a leading space, followed by `, …` when [w] was
/// given more locations than it keeps. Empty when [w] names no location.
String _locationList(DocxWarning w) {
  if (w.locations.isEmpty) return '';
  final String joined = w.locations.join(', ');
  return locationsTruncated(w) ? ' ($joined, …)' : ' ($joined)';
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
      count == 1
          ? '1 character that XML does not allow was removed from text in '
                '$part$locations.'
          : '$count characters that XML does not allow were removed from '
                'text in $part$locations.',
    (DocxWarningCode.invalidCharactersRemoved, OfficeLocale.de) =>
      count == 1
          ? '1 Zeichen, das XML nicht erlaubt, wurde aus dem Text in $part '
                'entfernt$locations.'
          : '$count Zeichen, die XML nicht erlaubt, wurden aus dem Text in '
                '$part entfernt$locations.',
    // Turkish keeps the noun singular after a numeral: "1 karakter",
    // "2 karakter".
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
    (DocxWarningCode.numberingNotFound, OfficeLocale.en) =>
      count == 1
          ? '1 paragraph in $part$locations belongs to the list $detail, '
                'which the document does not define; Word shows it without a '
                'number.'
          : '$count paragraphs in $part$locations belong to the list '
                '$detail, which the document does not define; Word shows them '
                'without a number.',
    (DocxWarningCode.numberingNotFound, OfficeLocale.de) =>
      count == 1
          ? '1 Absatz in $part$locations gehört zur Liste $detail, die das '
                'Dokument nicht definiert; Word zeigt ihn ohne Nummer.'
          : '$count Absätze in $part$locations gehören zur Liste $detail, '
                'die das Dokument nicht definiert; Word zeigt sie ohne Nummer.',
    // Turkish keeps the noun singular after a numeral: "2 paragraf".
    (DocxWarningCode.numberingNotFound, OfficeLocale.tr) =>
      count == 1
          ? '$part$locations içindeki 1 paragraf, belgenin tanımlamadığı '
                '$detail listesine ait; Word onu numarasız gösterir.'
          : '$part$locations içindeki $count paragraf, belgenin '
                'tanımlamadığı $detail listesine ait; Word bunları numarasız '
                'gösterir.',
    (DocxWarningCode.styleNotFound, OfficeLocale.en) =>
      count == 1
          ? '1 reference in $part$locations names the style $detail, which '
                'the document does not define; Word shows it in the default '
                'style.'
          : '$count references in $part$locations name the style $detail, '
                'which the document does not define; Word shows them in the '
                'default style.',
    (DocxWarningCode.styleNotFound, OfficeLocale.de) =>
      count == 1
          ? '1 Verweis in $part$locations nennt die Formatvorlage $detail, '
                'die das Dokument nicht definiert; Word zeigt ihn in der '
                'Standardformatvorlage.'
          : '$count Verweise in $part$locations nennen die Formatvorlage '
                '$detail, die das Dokument nicht definiert; Word zeigt sie in '
                'der Standardformatvorlage.',
    // Turkish keeps the noun singular after a numeral: "2 başvuru".
    (DocxWarningCode.styleNotFound, OfficeLocale.tr) =>
      count == 1
          ? '$part$locations içindeki 1 başvuru, belgenin tanımlamadığı '
                '$detail stilini adlandırıyor; Word onu varsayılan stilde '
                'gösterir.'
          : '$part$locations içindeki $count başvuru, belgenin '
                'tanımlamadığı $detail stilini adlandırıyor; Word bunları '
                'varsayılan stilde gösterir.',
  };
}
