/// Test helper: seeded fuzzing of `XlsxNumberFormatter`.
///
/// New in jet_office. [formatFuzzCases] derives cases (a format code and a
/// value) from a seed, [checkFormatCase] formats one and reports what broke.
/// `test/xlsx/format/fuzz_test.dart` runs a few seeds in the quality gate;
/// `tool/fuzz_formatter.dart` runs any range by hand.
///
/// A seed gives the same cases on the VM and in a browser: the generator is
/// [Xorshift32] (32-bit arithmetic only), the corpus is built from tables and
/// fixtures that do not depend on the platform, every number is built from
/// digit strings and every `DateTime` and `Duration` from integer fields
/// below 2^32. The locale and the date system come from the generator too.
library;

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/format/builtin_formats.dart';

import '../../../fixtures/fixtures.dart';
import '../../read/support/fuzz.dart' show Xorshift32;
import 'test_codes.dart';

/// One fuzz case: case `index` of `seed`.
typedef FormatFuzzCase = ({
  int seed,
  int index,
  String code,
  Object? value,
  int generalWidth,
  XlsxFormatLocale locale,
  bool date1904,
});

/// The locales a case picks from: the three the library ships.
const List<XlsxFormatLocale> formatFuzzLocales = <XlsxFormatLocale>[
  XlsxFormatLocale.enUS,
  XlsxFormatLocale.deDE,
  XlsxFormatLocale.trTR,
];

const List<String> _localeNames = <String>['enUS', 'deDE', 'trTR'];

/// One [XlsxNumberFormatter] for each locale of [formatFuzzLocales] and
/// each date system, so a run reuses their caches.
final class FormatFuzzFormatters {
  final Map<(XlsxFormatLocale, bool), XlsxNumberFormatter> _formatters =
      <(XlsxFormatLocale, bool), XlsxNumberFormatter>{};

  /// The formatter for the locale and date system of [c].
  XlsxNumberFormatter of(FormatFuzzCase c) => _formatters.putIfAbsent((
    c.locale,
    c.date1904,
  ), () => XlsxNumberFormatter(locale: c.locale, date1904: c.date1904));
}

/// The characters mutations insert, besides letters.
const String _special = '0#?.,%E+-/@"\\_*[];\$()<>=';

const String _letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

List<String>? _corpus;

/// The format codes the fuzzer starts from, in a fixed order.
///
/// Every built-in code (ids 0 to 49), every built-in, long date and long
/// time code of the three shipped locales, every number format a fixture of
/// `allFixtures()` stores, the literals of the formatter tests, the codes of
/// the owner checklist and a 240-character `dddd` repetition. The owner
/// manifest lists no file yet, so it adds none.
List<String> formatFuzzCorpus() {
  final List<String> codes = _corpus ??= () {
    final Set<String> set = <String>{};
    for (int id = 0; id < 50; id++) {
      final String? code = builtinNumberFormatCode(id);
      if (code != null) set.add(code);
    }
    for (final XlsxFormatLocale locale in formatFuzzLocales) {
      set
        ..addAll(locale.builtinCodes.values)
        ..add(locale.longDateCode)
        ..add(locale.longTimeCode);
    }
    for (final Fixture fixture in allFixtures()) {
      final XlsxReader reader = XlsxReader(fixture.build());
      for (final XlsxReadSheet sheet in reader.sheets) {
        for (final XlsxReadRow row in reader.rows(sheet.name)) {
          for (final XlsxReadCell cell in row.cells) {
            final String? code = cell.numberFormat;
            if (code != null) set.add(code);
          }
        }
      }
    }
    set
      ..addAll(testFormatCodes)
      ..addAll(ownerCheckFormatCodes)
      ..add('dddd' * 60);
    return List<String>.unmodifiable(set);
  }();
  return codes;
}

/// [count] cases of [seed], the same on every platform.
List<FormatFuzzCase> formatFuzzCases(int seed, int count) {
  final Xorshift32 random = Xorshift32(seed);
  final List<String> corpus = formatFuzzCorpus();
  return <FormatFuzzCase>[
    for (int i = 0; i < count; i++)
      (
        seed: seed,
        index: i,
        code: _code(random, corpus),
        value: _value(random),
        generalWidth: random.nextInt(8) == 0 ? 1 + random.nextInt(30) : 11,
        locale: formatFuzzLocales[random.nextInt(formatFuzzLocales.length)],
        date1904: random.nextInt(4) == 0,
      ),
  ];
}

String _code(Xorshift32 r, List<String> corpus) {
  String code = corpus[r.nextInt(corpus.length)];
  if (r.nextInt(4) == 0) {
    final String other = corpus[r.nextInt(corpus.length)];
    code =
        code.substring(0, r.nextInt(code.length + 1)) +
        other.substring(r.nextInt(other.length + 1));
  }
  final int mutations = r.nextInt(4);
  for (int m = 0; m < mutations; m++) {
    final int at = r.nextInt(code.length + 1);
    switch (r.nextInt(4)) {
      case 0:
        code = code.substring(0, at) + _char(r) + code.substring(at);
      case 1:
        if (at < code.length) {
          code = code.substring(0, at) + code.substring(at + 1);
        }
      case 2:
        if (at < code.length) {
          code = code.substring(0, at + 1) + code.substring(at);
        }
      case 3:
        if (code.isNotEmpty) {
          final int from = r.nextInt(code.length);
          final int to = from + 1 + r.nextInt(code.length - from);
          code =
              code.substring(0, at) +
              code.substring(from, to) +
              code.substring(at);
        }
    }
  }
  // Now and then a code near the 255 character limit.
  if (r.nextInt(100) == 0) {
    code = code.padRight(250 + r.nextInt(12), '#');
  }
  return code;
}

String _char(Xorshift32 r) => r.nextInt(3) == 0
    ? _letters[r.nextInt(_letters.length)]
    : _special[r.nextInt(_special.length)];

Object? _value(Xorshift32 r) {
  switch (r.nextInt(16)) {
    case 0:
      return null;
    case 1:
      return r.nextInt(2) == 0;
    case 2:
      return XlsxErrorValue.classic[r.nextInt(XlsxErrorValue.classic.length)];
    case 3:
      return _string(r);
    case 4:
      return <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0.0,
        -0.0,
      ][r.nextInt(5)];
    case 5:
      return r.nextInt(1000000) - 500000;
    case 6:
      return DateTime.utc(
        1900 + r.nextInt(300),
        1 + r.nextInt(12),
        1 + r.nextInt(28),
        r.nextInt(24),
        r.nextInt(60),
        r.nextInt(60),
      );
    case 7:
      return Duration(seconds: r.nextInt(2000000) - 500000);
    case 8:
    case 9:
    case 10:
      return double.parse(_digits(r));
    case 11:
    case 12:
      final String serial = _serial(r);
      return r.nextInt(2) == 0 ? XlsxDecimal(serial) : double.parse(serial);
    case 13:
      return DateTime.utc(
        1 + r.nextInt(10000),
        1 + r.nextInt(12),
        1 + r.nextInt(31),
        r.nextInt(24),
        r.nextInt(60),
        r.nextInt(60),
        r.nextInt(1000),
      );
    case 14:
      final Duration duration = Duration(
        days: r.nextInt(100000001),
        hours: r.nextInt(24),
        microseconds: r.nextInt(3600000000),
      );
      return r.nextInt(2) == 0 ? duration : -duration;
    default:
      return XlsxDecimal(_digits(r));
  }
}

/// A date serial: a whole part from 0 to 3,000,000 (past 9999-12-31), often
/// below 100 (serial 0 and the phantom leap day), and a fraction of up to 15
/// digits, often all nines (a time that rounds up); now and then negative.
String _serial(Xorshift32 r) {
  final StringBuffer out = StringBuffer();
  if (r.nextInt(8) == 0) out.write('-');
  out.write(r.nextInt(4) == 0 ? r.nextInt(100) : r.nextInt(3000001));
  final int digits = r.nextInt(16);
  if (digits > 0) {
    out.write('.');
    final bool nines = r.nextInt(4) == 0;
    for (int i = 0; i < digits; i++) {
      out.write(nines ? 9 : r.nextInt(10));
    }
  }
  return out.toString();
}

String _string(Xorshift32 r) {
  final int length = r.nextInt(5) == 0 ? r.nextInt(300) : r.nextInt(12);
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < length; i++) {
    out.write(r.nextInt(6) == 0 ? _special[r.nextInt(_special.length)] : 'x');
  }
  return out.toString();
}

/// A decimal string: sign, 1 to 30 integer digits (now and then up to 309,
/// or a tiny number with up to 320 zeros after the point) and a fraction of
/// up to 30 digits.
String _digits(Xorshift32 r) {
  final StringBuffer out = StringBuffer();
  if (r.nextInt(2) == 0) out.write('-');
  final int kind = r.nextInt(10);
  if (kind == 0) {
    out.write('0.');
    out.write('0' * r.nextInt(321));
    for (int i = 1 + r.nextInt(16); i > 0; i--) {
      out.write(r.nextInt(10));
    }
    return out.toString();
  }
  final int length = kind == 1 ? 1 + r.nextInt(309) : 1 + r.nextInt(30);
  for (int i = 0; i < length; i++) {
    // No leading zero unless the number is a single digit.
    out.write(i == 0 && length > 1 ? 1 + r.nextInt(9) : r.nextInt(10));
  }
  if (r.nextInt(2) == 0) {
    out.write('.');
    for (int i = 1 + r.nextInt(30); i > 0; i--) {
      out.write(r.nextInt(10));
    }
  }
  return out.toString();
}

/// What [value] looks like in a failure line.
String describeFuzzValue(Object? value) => switch (value) {
  String() => 'String(${_quote(value)})',
  XlsxErrorValue() => 'XlsxErrorValue(${value.code})',
  _ => '${value.runtimeType}($value)',
};

String _quote(String s) =>
    '"${s.length > 80 ? '${s.substring(0, 80)}...' : s}"';

/// Formats [c] with the formatter of its locale and date system in
/// [formatters]; null when every property holds, else a
/// description of the first one broken.
///
/// The properties: nothing is thrown, `text` has at most 1,000 characters
/// more than a text value it may show unchanged, and the parts joined
/// (each padding as one space, each fill left out) equal `text`.
String? checkFormatCase(FormatFuzzFormatters formatters, FormatFuzzCase c) {
  try {
    final XlsxFormattedValue result = formatters
        .of(c)
        .format(c.value, numberFormat: c.code, generalWidth: c.generalWidth);
    final Object? value = c.value;
    final int shown = value is String ? value.length : 0;
    if (result.text.length > 1000 + shown) {
      return 'text has ${result.text.length} characters';
    }
    final StringBuffer joined = StringBuffer();
    for (final XlsxFormatPart part in result.parts) {
      switch (part) {
        case XlsxFormatText(:final String text):
          joined.write(text);
        case XlsxFormatPadding():
          joined.write(' ');
        case XlsxFormatFill():
          break;
      }
    }
    if (joined.toString() != result.text) {
      return 'parts joined are "$joined", text is "${result.text}"';
    }
    return null;
  } on Object catch (e, s) {
    return 'threw $e\n$s';
  }
}

/// The failure line of [c] with [problem], as the test and the tool print it.
String describeFormatFailure(FormatFuzzCase c, String problem) =>
    'seed ${c.seed} case ${c.index}: ${_quote(c.code)} '
    '${describeFuzzValue(c.value)} width ${c.generalWidth} '
    '${describeFuzzSettings(c)}: $problem';

/// The locale and date system of [c], such as `deDE 1904`.
String describeFuzzSettings(FormatFuzzCase c) =>
    '${_localeNames[formatFuzzLocales.indexOf(c.locale)]} '
    '${c.date1904 ? '1904' : '1900'}';
