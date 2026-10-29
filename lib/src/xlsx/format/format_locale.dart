/// The regional data the number format engine renders with.
///
/// New in jet_office; Quds has no number format engine. A file's format
/// codes are written in an invariant syntax (`.` for the decimal point,
/// `,` for grouping, English words); what a cell shows depends on the
/// region of the Excel that opens it. [XlsxFormatLocale] holds that region's
/// separators, names and built-in codes (spec §5.5, §6.1).
library;

import '../warnings.dart';

/// Formatting data for one region: separators, month and day names, the
/// built-in codes that follow the region, and the words for booleans and
/// errors.
///
/// It is not [XlsxLocale], which names the language of warning messages;
/// [messageLocale] gives the matching one. Every field but [dateSeparator]
/// is required, so a caller can define a region the library does not ship.
final class XlsxFormatLocale {
  /// Creates a locale from every field.
  ///
  /// [monthNames] and [monthAbbreviations] hold 12 entries from January;
  /// [dayNames] and [dayAbbreviations] hold 7 from Sunday. [dateSeparator]
  /// defaults to `/`, which shows a code's `/` as written.
  const XlsxFormatLocale({
    required this.decimalSeparator,
    required this.groupSeparator,
    this.dateSeparator = '/',
    required this.monthNames,
    required this.monthAbbreviations,
    required this.dayNames,
    required this.dayAbbreviations,
    required this.am,
    required this.pm,
    required this.trueText,
    required this.falseText,
    required this.errorNames,
    required this.lcid,
    required this.builtinCodes,
    required this.longDateCode,
    required this.longTimeCode,
    required this.messageLocale,
    required this.verified,
  });

  /// What the `.` of a format code shows as, such as `.` or `,`.
  final String decimalSeparator;

  /// What a grouping `,` of a format code shows as, such as `,` or `.`.
  final String groupSeparator;

  /// What a `/` in a date or time section shows as, such as `/` or `.`.
  ///
  /// Excel for Mac in tr-TR shows `dd/mm/yyyy` as `28.10.2026`.
  final String dateSeparator;

  /// The month names, January first: what `mmmm` shows.
  final List<String> monthNames;

  /// The short month names, January first: what `mmm` shows.
  final List<String> monthAbbreviations;

  /// The day names, Sunday first: what `dddd` shows.
  final List<String> dayNames;

  /// The short day names, Sunday first: what `ddd` shows.
  final List<String> dayAbbreviations;

  /// What `AM/PM` shows before noon.
  final String am;

  /// What `AM/PM` shows from noon.
  final String pm;

  /// What the boolean true shows as, whatever the code.
  final String trueText;

  /// What the boolean false shows as, whatever the code.
  final String falseText;

  /// What each error value shows as, by its English code such as
  /// `#VALUE!`. A code not in the map shows as written.
  final Map<String, String> errorNames;

  /// The Windows locale id that a `[$-xxx]` tag selects this locale with,
  /// such as `0x409` for en-US.
  final int lcid;

  /// The region's code for each built-in id that follows the region (5–8,
  /// 14–22 and 37–44), in the invariant syntax of a file.
  final Map<int, String> builtinCodes;

  /// The region's long date, which `[$-F800]` shows.
  ///
  /// It must be a valid format code. Its first section is used; tags and
  /// brackets in it are neither applied nor reported.
  final String longDateCode;

  /// The region's long time, which `[$-F400]` shows.
  ///
  /// It must be a valid format code. Its first section is used; tags and
  /// brackets in it are neither applied nor reported.
  final String longTimeCode;

  /// The language of warning messages that matches this region.
  final XlsxLocale messageLocale;

  /// Whether the owner checked this locale's output against Excel for Mac.
  ///
  /// The three shipped locales are checked (`docs/number-format.md`,
  /// "Excel as the oracle"); each one's dartdoc lists what the check could
  /// not show. A language tag no shipped locale serves (`[$-40C]`, French)
  /// shows the renderer locale's names, where Excel shows that language's.
  /// An unchecked locale is built from CLDR's region data and
  /// LibreOffice's import tables and may differ from Excel in details.
  final bool verified;

  /// United States English.
  ///
  /// Names and AM/PM are Excel's English ones. Checked against Excel for
  /// Mac 16.114.1, oracle run 2026-10-30: names, booleans, built-in codes
  /// 5–8, 14–22 and 37–44 (14 and 22 have a two-digit year), the long date
  /// and time, `#SPILL!` and `#CALC!` show as Excel shows them.
  ///
  /// Assumptions that remain, which a CSV cannot show: the `[Red]` of 6,
  /// 8, 38 and 40; the fill, zero and text sections of 41–44; the error
  /// names other than `#SPILL!` and `#CALC!`, never shown by the run.
  static const XlsxFormatLocale enUS = XlsxFormatLocale(
    decimalSeparator: '.',
    groupSeparator: ',',
    dateSeparator: '/',
    monthNames: <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ],
    monthAbbreviations: <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ],
    dayNames: <String>[
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ],
    dayAbbreviations: <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    am: 'AM',
    pm: 'PM',
    trueText: 'TRUE',
    falseText: 'FALSE',
    errorNames: <String, String>{
      '#NULL!': '#NULL!',
      '#DIV/0!': '#DIV/0!',
      '#VALUE!': '#VALUE!',
      '#REF!': '#REF!',
      '#NAME?': '#NAME?',
      '#NUM!': '#NUM!',
      '#N/A': '#N/A',
    },
    lcid: 0x409,
    builtinCodes: <int, String>{
      5: r'$#,##0_);($#,##0)',
      6: r'$#,##0_);[Red]($#,##0)',
      7: r'$#,##0.00_);($#,##0.00)',
      8: r'$#,##0.00_);[Red]($#,##0.00)',
      14: 'm/d/yy',
      15: 'd-mmm-yy',
      16: 'd-mmm',
      17: 'mmm-yy',
      18: 'h:mm AM/PM',
      19: 'h:mm:ss AM/PM',
      20: 'h:mm',
      21: 'h:mm:ss',
      22: 'm/d/yy h:mm',
      37: '#,##0_);(#,##0)',
      38: '#,##0_);[Red](#,##0)',
      39: '#,##0.00_);(#,##0.00)',
      40: '#,##0.00_);[Red](#,##0.00)',
      41: '_(* #,##0_);_(* (#,##0);_(* "-"_);_(@_)',
      42: r'_($* #,##0_);_($* (#,##0);_($* "-"_);_(@_)',
      43: '_(* #,##0.00_);_(* (#,##0.00);_(* "-"??_);_(@_)',
      44: r'_($* #,##0.00_);_($* (#,##0.00);_($* "-"??_);_(@_)',
    },
    longDateCode: 'dddd, mmmm d, yyyy',
    longTimeCode: 'h:mm:ss AM/PM',
    messageLocale: XlsxLocale.en,
    verified: true,
  );

  /// German (Germany).
  ///
  /// Month and day names come from CLDR, the abbreviations from CLDR's
  /// stand-alone abbreviated forms without dots. Checked against Excel for
  /// Mac 16.114.1, oracle run 2026-10-30: names, booleans, built-in codes
  /// 5–8, 14–22 and 37–44 (14 and 22 have a two-digit year, 37–40 no
  /// padding, 41 and 43 Excel's accounting style), [dateSeparator], the
  /// long date and time, `#SPILL!` (`#ÜBERLAUF!`) and `#CALC!` (German
  /// Excel leaves it untranslated) show as Excel shows them.
  ///
  /// Assumptions that remain, which a CSV cannot show: the `[Red]` of 6,
  /// 8, 38 and 40; the fill, zero (`"-"`) and text sections of 41–44;
  /// whether 18 and 19 show `AM`/`PM` as German words by a tag or as the
  /// English words of an untagged `AM/PM` (both are `AM`/`PM`); the error
  /// names other than `#SPILL!` and `#CALC!`, never shown by the run.
  static const XlsxFormatLocale deDE = XlsxFormatLocale(
    decimalSeparator: ',',
    groupSeparator: '.',
    dateSeparator: '.',
    monthNames: <String>[
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ],
    monthAbbreviations: <String>[
      'Jan',
      'Feb',
      'Mär',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez',
    ],
    dayNames: <String>[
      'Sonntag',
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
    ],
    dayAbbreviations: <String>['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'],
    am: 'AM',
    pm: 'PM',
    trueText: 'WAHR',
    falseText: 'FALSCH',
    errorNames: <String, String>{
      '#NULL!': '#NULL!',
      '#DIV/0!': '#DIV/0!',
      '#VALUE!': '#WERT!',
      '#REF!': '#BEZUG!',
      '#NAME?': '#NAME?',
      '#NUM!': '#ZAHL!',
      '#N/A': '#NV',
      '#SPILL!': '#ÜBERLAUF!',
      '#CALC!': '#CALC!',
    },
    lcid: 0x407,
    builtinCodes: <int, String>{
      5: '#,##0 "€";-#,##0 "€"',
      6: '#,##0 "€";[Red]-#,##0 "€"',
      7: '#,##0.00 "€";-#,##0.00 "€"',
      8: '#,##0.00 "€";[Red]-#,##0.00 "€"',
      14: 'dd.mm.yy',
      15: 'dd. mmm yy',
      16: 'dd. mmm',
      17: 'mmm yy',
      18: 'h:mm AM/PM',
      19: 'h:mm:ss AM/PM',
      20: 'hh:mm',
      21: 'hh:mm:ss',
      22: 'dd.mm.yy hh:mm',
      37: '#,##0;-#,##0',
      38: '#,##0;[Red]-#,##0',
      39: '#,##0.00;-#,##0.00',
      40: '#,##0.00;[Red]-#,##0.00',
      41: '_-* #,##0_-;-* #,##0_-;_-* "-"_-;_-@_-',
      42: '_-* #,##0 "€"_-;-* #,##0 "€"_-;_-* "-" "€"_-;_-@_-',
      43: '_-* #,##0.00_-;-* #,##0.00_-;_-* "-"??_-;_-@_-',
      44: '_-* #,##0.00 "€"_-;-* #,##0.00 "€"_-;_-* "-"?? "€"_-;_-@_-',
    },
    longDateCode: 'dddd, d. mmmm yyyy',
    longTimeCode: 'hh:mm:ss',
    messageLocale: XlsxLocale.de,
    verified: true,
  );

  /// Turkish (Turkey).
  ///
  /// Month and day names come from CLDR, the abbreviations from CLDR's
  /// stand-alone abbreviated forms without dots. Checked against Excel for
  /// Mac 16.114.1, oracle run 2026-10-30: names, booleans, built-in codes
  /// 5–8 (`₺` first, minus first), 14–22 and 37–44 (37–40 no symbol and
  /// no padding), [dateSeparator], the long date and time, `#SPILL!`
  /// (`#TAŞMA!`) and `#CALC!` (`#HESAPLA!`) show as Excel shows them. Ids
  /// 18 and 19 carry the tr-TR tag `[$-41F]` because Excel shows `ÖÖ`/`ÖS`
  /// for them but English words for an untagged `AM/PM`.
  ///
  /// Assumptions that remain, which a CSV cannot show: the `[Red]` of 6,
  /// 8, 38 and 40; the fill, zero (`"-"`) and text sections of 41–44; the
  /// error names other than `#SPILL!` and `#CALC!`, never shown by the run.
  static const XlsxFormatLocale trTR = XlsxFormatLocale(
    decimalSeparator: ',',
    groupSeparator: '.',
    dateSeparator: '.',
    monthNames: <String>[
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ],
    monthAbbreviations: <String>[
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ],
    dayNames: <String>[
      'Pazar',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
    ],
    dayAbbreviations: <String>['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'],
    am: 'ÖÖ',
    pm: 'ÖS',
    trueText: 'DOĞRU',
    falseText: 'YANLIŞ',
    errorNames: <String, String>{
      '#NULL!': '#BOŞ!',
      '#DIV/0!': '#SAYI/0!',
      '#VALUE!': '#DEĞER!',
      '#REF!': '#BAŞV!',
      '#NAME?': '#AD?',
      '#NUM!': '#SAYI!',
      '#N/A': '#YOK',
      '#SPILL!': '#TAŞMA!',
      '#CALC!': '#HESAPLA!',
    },
    lcid: 0x41F,
    builtinCodes: <int, String>{
      5: '"₺"#,##0;-"₺"#,##0',
      6: '"₺"#,##0;[Red]-"₺"#,##0',
      7: '"₺"#,##0.00;-"₺"#,##0.00',
      8: '"₺"#,##0.00;[Red]-"₺"#,##0.00',
      14: 'dd.mm.yyyy',
      15: 'dd.mmm.yy',
      16: 'dd.mmm',
      17: 'mmm.yy',
      18: r'[$-41F]h:mm AM/PM',
      19: r'[$-41F]h:mm:ss AM/PM',
      20: 'hh:mm',
      21: 'hh:mm:ss',
      22: 'dd.mm.yyyy hh:mm',
      37: '#,##0;-#,##0',
      38: '#,##0;[Red]-#,##0',
      39: '#,##0.00;-#,##0.00',
      40: '#,##0.00;[Red]-#,##0.00',
      41: '_-* #,##0_-;-* #,##0_-;_-* "-"_-;_-@_-',
      42: '_-"₺"* #,##0_-;-"₺"* #,##0_-;_-"₺"* "-"_-;_-@_-',
      43: '_-* #,##0.00_-;-* #,##0.00_-;_-* "-"??_-;_-@_-',
      44: '_-"₺"* #,##0.00_-;-"₺"* #,##0.00_-;_-"₺"* "-"??_-;_-@_-',
    },
    longDateCode: 'd mmmm yyyy dddd',
    longTimeCode: 'hh:mm:ss',
    messageLocale: XlsxLocale.tr,
    verified: true,
  );
}

/// The shipped locale whose [XlsxFormatLocale.lcid] equals [language], or
/// null when the library ships none for it.
XlsxFormatLocale? shippedFormatLocale(int language) {
  for (final XlsxFormatLocale locale in _shipped) {
    if (locale.lcid == language) {
      return locale;
    }
  }
  return null;
}

const List<XlsxFormatLocale> _shipped = <XlsxFormatLocale>[
  XlsxFormatLocale.enUS,
  XlsxFormatLocale.deDE,
  XlsxFormatLocale.trTR,
];
