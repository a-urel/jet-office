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
/// [messageLocale] gives the matching one. Every field is required, so a
/// caller can define a region the library does not ship.
final class XlsxFormatLocale {
  /// Creates a locale from every field.
  ///
  /// [monthNames] and [monthAbbreviations] hold 12 entries from January;
  /// [dayNames] and [dayAbbreviations] hold 7 from Sunday.
  const XlsxFormatLocale({
    required this.decimalSeparator,
    required this.groupSeparator,
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
  final String longDateCode;

  /// The region's long time, which `[$-F400]` shows.
  final String longTimeCode;

  /// The language of warning messages that matches this region.
  final XlsxLocale messageLocale;

  /// Whether the owner checked this locale's output against Excel for Mac.
  ///
  /// An unchecked locale is built from CLDR's region data and
  /// LibreOffice's import tables and may differ from Excel in details.
  final bool verified;

  /// United States English.
  ///
  /// Names and AM/PM are Excel's English ones; the built-in codes come from
  /// LibreOffice's import table for en-US. Not yet checked against Excel
  /// for Mac ([verified] is false).
  static const XlsxFormatLocale enUS = XlsxFormatLocale(
    decimalSeparator: '.',
    groupSeparator: ',',
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
      14: 'm/d/yyyy',
      15: 'd-mmm-yy',
      16: 'd-mmm',
      17: 'mmm-yy',
      18: 'h:mm AM/PM',
      19: 'h:mm:ss AM/PM',
      20: 'h:mm',
      21: 'h:mm:ss',
      22: 'm/d/yyyy h:mm',
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
    verified: false,
  );

  /// German (Germany).
  ///
  /// Month and day names come from CLDR, the abbreviations from CLDR's
  /// stand-alone abbreviated forms without dots; the built-in codes come
  /// from LibreOffice's import table for de-DE. Not yet checked against
  /// Excel for Mac ([verified] is false).
  static const XlsxFormatLocale deDE = XlsxFormatLocale(
    decimalSeparator: ',',
    groupSeparator: '.',
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
    },
    lcid: 0x407,
    builtinCodes: <int, String>{
      5: '#,##0 "€";-#,##0 "€"',
      6: '#,##0 "€";[Red]-#,##0 "€"',
      7: '#,##0.00 "€";-#,##0.00 "€"',
      8: '#,##0.00 "€";[Red]-#,##0.00 "€"',
      14: 'dd.mm.yyyy',
      15: 'dd. mmm yy',
      16: 'dd. mmm',
      17: 'mmm yy',
      18: 'h:mm AM/PM',
      19: 'h:mm:ss AM/PM',
      20: 'hh:mm',
      21: 'hh:mm:ss',
      22: 'dd.mm.yyyy hh:mm',
      37: '#,##0 ;-#,##0 ',
      38: '#,##0 ;[Red]-#,##0 ',
      39: '#,##0.00 ;-#,##0.00 ',
      40: '#,##0.00 ;[Red]-#,##0.00 ',
      41: '_-* #,##0 _€_-;-* #,##0 _€_-;_-* "-" _€_-;_-@_-',
      42: '_-* #,##0 "€"_-;-* #,##0 "€"_-;_-* "-" "€"_-;_-@_-',
      43: '_-* #,##0.00 _€_-;-* #,##0.00 _€_-;_-* "-"?? _€_-;_-@_-',
      44: '_-* #,##0.00 "€"_-;-* #,##0.00 "€"_-;_-* "-"?? "€"_-;_-@_-',
    },
    longDateCode: 'dddd, d. mmmm yyyy',
    longTimeCode: 'hh:mm:ss',
    messageLocale: XlsxLocale.de,
    verified: false,
  );

  /// Turkish (Turkey).
  ///
  /// Month and day names come from CLDR, the abbreviations from CLDR's
  /// stand-alone abbreviated forms without dots; the built-in codes come
  /// from LibreOffice's import table for tr-TR. Not yet checked against
  /// Excel for Mac ([verified] is false).
  static const XlsxFormatLocale trTR = XlsxFormatLocale(
    decimalSeparator: ',',
    groupSeparator: '.',
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
    },
    lcid: 0x41F,
    builtinCodes: <int, String>{
      5: '#,##0 "₺";-#,##0 "₺"',
      6: '#,##0 "₺";[Red]-#,##0 "₺"',
      7: '#,##0.00 "₺";-#,##0.00 "₺"',
      8: '#,##0.00 "₺";[Red]-#,##0.00 "₺"',
      14: 'dd.mm.yyyy',
      15: 'dd.mmm.yy',
      16: 'dd.mmm',
      17: 'mmm.yy',
      18: 'h:mm AM/PM',
      19: 'h:mm:ss AM/PM',
      20: 'hh:mm',
      21: 'hh:mm:ss',
      22: 'dd.mm.yyyy hh:mm',
      37: '#,##0 ;-#,##0 ',
      38: '#,##0 ;[Red]-#,##0 ',
      39: '#,##0.00 ;-#,##0.00 ',
      40: '#,##0.00 ;[Red]-#,##0.00 ',
      41: '_-* #,##0 _₺_-;-* #,##0 _₺_-;_-* "-" _₺_-;_-@_-',
      42: '_-* #,##0 "₺"_-;-* #,##0 "₺"_-;_-* "-" "₺"_-;_-@_-',
      43: '_-* #,##0.00 _₺_-;-* #,##0.00 _₺_-;_-* "-"?? _₺_-;_-@_-',
      44: '_-* #,##0.00 "₺"_-;-* #,##0.00 "₺"_-;_-* "-"?? "₺"_-;_-@_-',
    },
    longDateCode: 'd mmmm yyyy dddd',
    longTimeCode: 'hh:mm:ss',
    messageLocale: XlsxLocale.tr,
    verified: false,
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
