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
  // A repaired bookmark name's detail, after a colon; none when the
  // warning aggregated more names than it keeps.
  final String named = w.detail == null ? '' : ': $detail';
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
    (DocxWarningCode.propertyValueInvalid, OfficeLocale.en) =>
      'Document property $detail in $part could not be read; it was kept as '
          'it is.',
    (DocxWarningCode.propertyValueInvalid, OfficeLocale.de) =>
      'Die Dokumenteigenschaft $detail in $part konnte nicht gelesen '
          'werden; sie wurde unverändert beibehalten.',
    (DocxWarningCode.propertyValueInvalid, OfficeLocale.tr) =>
      '$part içindeki $detail belge özelliği okunamadı; olduğu gibi '
          'korundu.',
    (DocxWarningCode.bookmarkNameRepaired, OfficeLocale.en) =>
      count == 1
          ? "A bookmark name in $part did not follow Word's rules and was "
                'repaired$named.'
          : "$count bookmark names in $part did not follow Word's rules and "
                'were repaired$named.',
    (DocxWarningCode.bookmarkNameRepaired, OfficeLocale.de) =>
      count == 1
          ? 'Ein Textmarkenname in $part entsprach nicht den Regeln von Word '
                'und wurde korrigiert$named.'
          : '$count Textmarkennamen in $part entsprachen nicht den Regeln '
                'von Word und wurden korrigiert$named.',
    // Turkish keeps the noun singular after a numeral: "2 yer işareti adı".
    (DocxWarningCode.bookmarkNameRepaired, OfficeLocale.tr) =>
      count == 1
          ? '$part içindeki bir yer işareti adı Word kurallarına uymuyordu ve '
                'düzeltildi$named.'
          : '$part içindeki $count yer işareti adı Word kurallarına '
                'uymuyordu ve düzeltildi$named.',
    (DocxWarningCode.templateValueMissing, OfficeLocale.en) =>
      'The data has no value for $detail in $part$locations; the tag was left as written.',
    (DocxWarningCode.templateValueMissing, OfficeLocale.de) =>
      'Die Daten enthalten keinen Wert für $detail in $part$locations; das Tag blieb unverändert.',
    (DocxWarningCode.templateValueMissing, OfficeLocale.tr) =>
      '$part$locations içindeki $detail için veride değer yok; etiket olduğu gibi bırakıldı.',
    (DocxWarningCode.templateTagMalformed, OfficeLocale.en) =>
      '$detail in $part$locations is not a valid tag; it was left as text.',
    (DocxWarningCode.templateTagMalformed, OfficeLocale.de) =>
      '$detail in $part$locations ist kein gültiges Tag; es blieb als Text stehen.',
    (DocxWarningCode.templateTagMalformed, OfficeLocale.tr) =>
      '$part$locations içindeki $detail geçerli bir etiket değil; metin olarak bırakıldı.',
    (DocxWarningCode.templateSectionMalformed, OfficeLocale.en) =>
      'A section tag in $part$locations was left as written: sections are not filled yet ($detail).',
    (DocxWarningCode.templateSectionMalformed, OfficeLocale.de) =>
      'Ein Abschnitts-Tag in $part$locations blieb unverändert: Abschnitte werden noch nicht gefüllt ($detail).',
    (DocxWarningCode.templateSectionMalformed, OfficeLocale.tr) =>
      '$part$locations içindeki bir bölüm etiketi olduğu gibi bırakıldı: bölümler henüz doldurulmuyor ($detail).',
    (DocxWarningCode.templateValueNotText, OfficeLocale.en) =>
      'The value for $detail in $part$locations is a list or a map, not text; the tag was left as written.',
    (DocxWarningCode.templateValueNotText, OfficeLocale.de) =>
      'Der Wert für $detail in $part$locations ist eine Liste oder Zuordnung, kein Text; das Tag blieb unverändert.',
    (DocxWarningCode.templateValueNotText, OfficeLocale.tr) =>
      '$part$locations içindeki $detail için değer metin değil, liste veya harita; etiket olduğu gibi bırakıldı.',
    (DocxWarningCode.templateValueNotPicture, OfficeLocale.en) =>
      'The value for $detail in $part$locations is not a picture; the placeholder picture was kept.',
    (DocxWarningCode.templateValueNotPicture, OfficeLocale.de) =>
      'Der Wert für $detail in $part$locations ist kein Bild; das Platzhalterbild blieb erhalten.',
    (DocxWarningCode.templateValueNotPicture, OfficeLocale.tr) =>
      '$part$locations içindeki $detail için değer bir resim değil; yer tutucu resim korundu.',
    (DocxWarningCode.templateFormatWarning, OfficeLocale.en) =>
      'The format code of $detail in $part$locations raised a warning from the number format engine.',
    (DocxWarningCode.templateFormatWarning, OfficeLocale.de) =>
      'Der Formatcode von $detail in $part$locations löste eine Warnung der Zahlenformat-Engine aus.',
    (DocxWarningCode.templateFormatWarning, OfficeLocale.tr) =>
      '$part$locations içindeki $detail biçim kodu, sayı biçimi motorundan bir uyarı verdi.',
    (DocxWarningCode.templateSwitchUnsupported, OfficeLocale.en) =>
      'A switch of $detail in $part$locations is not supported; the default format was used.',
    (DocxWarningCode.templateSwitchUnsupported, OfficeLocale.de) =>
      'Ein Schalter von $detail in $part$locations wird nicht unterstützt; das Standardformat wurde verwendet.',
    (DocxWarningCode.templateSwitchUnsupported, OfficeLocale.tr) =>
      '$part$locations içindeki $detail alanının bir anahtarı desteklenmiyor; varsayılan biçim kullanıldı.',
    (DocxWarningCode.templateFieldNotTyped, OfficeLocale.en) =>
      'The merge field $detail in $part$locations is kept as loose runs, not as a field, and was left as it is.',
    (DocxWarningCode.templateFieldNotTyped, OfficeLocale.de) =>
      'Das Seriendruckfeld $detail in $part$locations liegt als lose Abschnitte vor, nicht als Feld, und blieb unverändert.',
    (DocxWarningCode.templateFieldNotTyped, OfficeLocale.tr) =>
      '$part$locations içindeki $detail birleştirme alanı alan olarak değil, ayrı parçalar olarak tutuluyor ve olduğu gibi bırakıldı.',
    (DocxWarningCode.templatePlaceholderInRevision, OfficeLocale.en) =>
      '$detail in $part$locations lies inside a tracked change; it was left as written.',
    (DocxWarningCode.templatePlaceholderInRevision, OfficeLocale.de) =>
      '$detail in $part$locations liegt in einer Änderungsnachverfolgung; es blieb unverändert.',
    (DocxWarningCode.templatePlaceholderInRevision, OfficeLocale.tr) =>
      '$part$locations içindeki $detail izlenen bir değişikliğin içinde; olduğu gibi bırakıldı.',
    (DocxWarningCode.templatePlaceholderInContentControl, OfficeLocale.en) =>
      '$detail in $part$locations lies inside a content control; it was left as written.',
    (DocxWarningCode.templatePlaceholderInContentControl, OfficeLocale.de) =>
      '$detail in $part$locations liegt in einem Inhaltssteuerelement; es blieb unverändert.',
    (DocxWarningCode.templatePlaceholderInContentControl, OfficeLocale.tr) =>
      '$part$locations içindeki $detail bir içerik denetiminin içinde; olduğu gibi bırakıldı.',
    (DocxWarningCode.templatePlaceholderNotTyped, OfficeLocale.en) =>
      '$detail in $part$locations lies where the model keeps content opaque; it was left as written.',
    (DocxWarningCode.templatePlaceholderNotTyped, OfficeLocale.de) =>
      '$detail in $part$locations liegt in einem Bereich, den das Modell nicht auswertet; es blieb unverändert.',
    (DocxWarningCode.templatePlaceholderNotTyped, OfficeLocale.tr) =>
      '$part$locations içindeki $detail, modelin içeriği opak tuttuğu bir yerde; olduğu gibi bırakıldı.',
    (DocxWarningCode.templateRepeatDroppedAnnotation, OfficeLocale.en) =>
      'A comment, note reference or bookmark in the section $detail of $part$locations was kept in the first copy only.',
    (DocxWarningCode.templateRepeatDroppedAnnotation, OfficeLocale.de) =>
      'Ein Kommentar, Notizverweis oder eine Textmarke im Abschnitt $detail von $part$locations blieb nur in der ersten Kopie erhalten.',
    (DocxWarningCode.templateRepeatDroppedAnnotation, OfficeLocale.tr) =>
      '$part$locations içindeki $detail bölümündeki bir açıklama, not başvurusu veya yer işareti yalnızca ilk kopyada korundu.',
    (DocxWarningCode.templateRemovalDroppedAnnotation, OfficeLocale.en) =>
      'Half of a comment, note reference or bookmark was removed with the section $detail in $part$locations.',
    (DocxWarningCode.templateRemovalDroppedAnnotation, OfficeLocale.de) =>
      'Die Hälfte eines Kommentars, Notizverweises oder einer Textmarke wurde mit dem Abschnitt $detail in $part$locations entfernt.',
    (DocxWarningCode.templateRemovalDroppedAnnotation, OfficeLocale.tr) =>
      '$part$locations içindeki $detail bölümüyle birlikte bir açıklamanın, not başvurusunun veya yer işaretinin yarısı kaldırıldı.',
  };
}
