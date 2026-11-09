/// Test helper: seeded mutation fuzzing of the chart reader
/// (`readDrawingChartSpace`) and the chart part handle (`DrawingChart`).
///
/// [chartFuzzCorpus] is the set of valid chart parts the fuzzer starts from,
/// [chartFuzzCases] derives mutated copies of them from a seed, and
/// [exerciseChartCase] checks one. `test/drawingml/chart/chart_fuzz_test.dart`
/// runs a fixed range of seeds in the quality gate; `tool/fuzz_chart.dart`
/// runs any range by hand.
///
/// A seed gives the same cases on the VM and in a browser: [Xorshift32]
/// stays within 32 bits, and the corpus is text (the Excel parts as
/// committed, the C1 parts as the writer writes them), never a ZIP, so no
/// deflater is involved (decision 0006).
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/drawingml/chart/chart_part.dart';
import 'package:jet_office/src/drawingml/chart/chart_reader.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';

import '../../../fixtures/c1_fixtures.dart';
import '../../../support/fuzz_mutations.dart';
import 'excel_charts.dart';

export '../../../support/fuzz_mutations.dart' show FuzzCase, Xorshift32;

/// One corpus entry: its name, its bytes and the theme it is read in.
typedef _Entry = ({String name, Uint8List bytes, ChartTheme theme});

/// The C1 fixtures whose charts join the corpus.
const List<String> _fixtures = <String>['c1_kinds', 'c1_options'];

/// The corpus with the themes, built once: the corpus is the same every
/// time, and the C1 charts take a moment to write.
final List<_Entry> _corpus = <_Entry>[
  (
    name: 'excel_column',
    bytes: utf8.encode(excelColumnChart),
    theme: ChartTheme.office,
  ),
  (
    name: 'excel_line',
    bytes: utf8.encode(excelLineChart),
    theme: ChartTheme.office,
  ),
  for (final String fixture in _fixtures)
    for (final (int i, C1Chart chart) in c1Charts(fixture).indexed)
      (
        name: '${fixture}_chart${i + 1}',
        bytes: writeDrawingChartSpace(chart.space, chart.theme).bytes,
        theme: chart.theme,
      ),
];

/// The valid chart parts the fuzzer mutates, in a fixed order.
///
/// The two parts of the owner's `chart_defaults.xlsx` as `excel_column` and
/// `excel_line` (`excel_charts.dart`), then every chart of `c1_kinds` and of
/// `c1_options`, written by `writeDrawingChartSpace` in its own theme, as
/// `<fixture>_chart<n>` (`n` from 1, in part order). Each reads typed in the
/// theme [chartFuzzTheme] gives it.
List<({String name, Uint8List bytes})> chartFuzzCorpus() =>
    <({String name, Uint8List bytes})>[
      for (final _Entry e in _corpus) (name: e.name, bytes: e.bytes),
    ];

/// The theme the corpus entry [name] is written and read in: the Office
/// theme for the Excel parts, the fixture's theme for a C1 chart.
///
/// Throws an [ArgumentError] when [name] is not a corpus entry.
ChartTheme chartFuzzTheme(String name) {
  for (final _Entry e in _corpus) {
    if (e.name == name) return e.theme;
  }
  throw ArgumentError.value(name, 'name', 'is not a chart corpus entry');
}

/// The tokens the insert mutation puts into a part: markup, numbers and
/// escapes the reader treats specially.
final List<String> _tokens = <String>[
  '<',
  '>',
  '&',
  '"',
  '<c:v>',
  '</c:v>',
  '<c:v>NaN</c:v>',
  '<c:pt idx="1048577"><c:v>1</c:v></c:pt>',
  '<c:ptCount val="1048576"/>',
  '<c:ser>',
  '</c:ser>',
  '<c:lineChart/>',
  '<c:valAx/>',
  '<c:axId val="0"/>',
  '<a:schemeClr val="dk1"/>',
  '<!DOCTYPE a>',
  '&#0;',
  '&#x1F600;',
  '-',
  '1e999',
  '99999999999999999999',
  '<a>' * 300,
];

/// The values the attribute and text mutations write: text where a number
/// is read, a number past every range, a bare sign, not a number and an
/// infinite one.
const List<String> _values = <String>[
  'abc',
  '99999999999999999999',
  '-',
  'NaN',
  '1e999',
];

final RegExp _attribute = RegExp(r'([\w:.-]+)="([^"]*)"');
final RegExp _text = RegExp(r'>([^<]+)<');

/// Replaces the value of one attribute of [part], chosen uniformly, by one
/// of [_values]; the description reads
/// `replace <attribute> at <offset> with "<value>"`. A part without an
/// attribute gets `abc` inserted instead.
(String, List<int>) _replaceAttribute(Uint8List part, Xorshift32 random) {
  final String text = latin1.decode(part);
  final List<RegExpMatch> found = _attribute.allMatches(text).toList();
  if (found.isEmpty) return _insertAbc(part, random);
  final RegExpMatch match = found[random.nextInt(found.length)];
  final String value = _values[random.nextInt(_values.length)];
  final int from = match.start + match.group(1)!.length + 2;
  return (
    'replace ${match.group(1)} at $from with "$value"',
    <int>[
      ...part.sublist(0, from),
      ...latin1.encode(value),
      ...part.sublist(match.end - 1),
    ],
  );
}

/// Replaces the text of one element of [part] (a cached number, a formula,
/// a format code, a title), chosen uniformly, by one of [_values]; the
/// description reads `replace text at <offset> with "<value>"`. A part
/// without element text gets `abc` inserted instead.
(String, List<int>) _replaceText(Uint8List part, Xorshift32 random) {
  final String text = latin1.decode(part);
  final List<RegExpMatch> found = _text.allMatches(text).toList();
  if (found.isEmpty) return _insertAbc(part, random);
  final RegExpMatch match = found[random.nextInt(found.length)];
  final String value = _values[random.nextInt(_values.length)];
  return (
    'replace text at ${match.start + 1} with "$value"',
    <int>[
      ...part.sublist(0, match.start + 1),
      ...latin1.encode(value),
      ...part.sublist(match.end - 1),
    ],
  );
}

(String, List<int>) _insertAbc(Uint8List part, Xorshift32 random) {
  final int at = random.nextInt(part.length + 1);
  return (
    'insert "abc" at $at',
    <int>[...part.sublist(0, at), ...latin1.encode('abc'), ...part.sublist(at)],
  );
}

/// The first [count] cases of [seed], each one mutation of one corpus entry.
///
/// The entry is chosen uniformly, then one of ten operations: flip 1 to 8
/// bits, or overwrite 4 bytes with `FF FF FF FF` or `00 00 00 00` (the
/// reader fuzz's operations on an archive's bytes); truncate, delete a span
/// of 1 to 16 bytes, duplicate such a span, insert a token of `_tokens`, or
/// replace a digit with another (its operations on a part); replace an
/// attribute's value (two in ten) or an element's text (one in ten) by
/// `abc`, twenty digits, `-`, `NaN` or `1e999`. The description reads
/// `<entry>: <operation>`; the entry gives the theme ([chartFuzzTheme]).
///
/// Lazy, and the same for the same arguments every time.
Iterable<FuzzCase> chartFuzzCases(int seed, int count) sync* {
  final Xorshift32 random = Xorshift32(seed);
  for (int index = 0; index < count; index++) {
    final _Entry entry = _corpus[random.nextInt(_corpus.length)];
    final int operation = random.nextInt(10);
    final (String what, List<int> bytes) = switch (operation) {
      0 || 1 => _bytesOperation(entry.bytes, operation + 1, random),
      2 ||
      3 ||
      4 ||
      5 ||
      6 => mutateBytes(entry.bytes, operation - 2, random, _tokens),
      7 || 8 => _replaceAttribute(entry.bytes, random),
      _ => _replaceText(entry.bytes, random),
    };
    yield (
      seed: seed,
      index: index,
      mutation: '${entry.name}: $what',
      bytes: Uint8List.fromList(bytes),
    );
  }
}

/// Archive operation [operation] (1 or 2) of `mutateArchive` on the bytes of
/// a part, described without the `(archive)` prefix.
(String, List<int>) _bytesOperation(
  Uint8List part,
  int operation,
  Xorshift32 random,
) {
  final (String what, Uint8List bytes) = mutateArchive(part, operation, random);
  return (what.replaceFirst('(archive): ', ''), bytes);
}

/// Checks the case [c] with [exerciseChart], in the theme of the corpus
/// entry its description names.
///
/// Throws an [ArgumentError] when the description names no corpus entry.
void exerciseChartCase(FuzzCase c) {
  final int colon = c.mutation.indexOf(':');
  exerciseChart(
    c.bytes,
    colon < 0 ? c.mutation : c.mutation.substring(0, colon),
  );
}

/// Checks the chart part [bytes], read in the theme of the corpus entry
/// [entry] ([chartFuzzTheme]).
///
/// `readDrawingChartSpace` must not throw. When it gives a typed form,
/// `writeDrawingChartSpace` must write it without a throw, and reading what
/// it wrote must give the same typed form again. `DrawingChart.opened` of
/// [bytes] must give the reader's chart, typed form and issues without a
/// throw, and encode [bytes] unchanged.
///
/// Returns normally or throws a [StateError] naming the step that failed.
void exerciseChart(Uint8List bytes, String entry) {
  final ChartTheme theme = chartFuzzTheme(entry);
  final DrawingChartRead read;
  try {
    read = readDrawingChartSpace(bytes, theme: theme);
    read.chart?.toString();
  } on Object catch (e) {
    throw StateError('readDrawingChartSpace threw: $e');
  }
  final DrawingChartSpace? typed = read.typed;
  if (typed != null) {
    final Uint8List written;
    try {
      written = writeDrawingChartSpace(typed, theme).bytes;
    } on Object catch (e) {
      throw StateError('writing the typed form threw: $e');
    }
    final DrawingChartRead again;
    try {
      again = readDrawingChartSpace(written, theme: theme);
    } on Object catch (e) {
      throw StateError('reading the written typed form threw: $e');
    }
    if (again.typed != typed) {
      throw StateError(
        'the written typed form read back as ${again.typed}, not $typed',
      );
    }
  }
  final DrawingChart part = DrawingChart.opened(bytes, theme: theme);
  try {
    if (part.chart != read.chart ||
        part.typed != read.typed ||
        part.issues.length != read.issues.length) {
      throw StateError('DrawingChart.opened read differently from the reader');
    }
  } on StateError {
    rethrow;
  } on Object catch (e) {
    throw StateError('DrawingChart.opened threw: $e');
  }
  final List<Uint8List> encoded = part.encode();
  if (encoded.length != 1 || !_equal(encoded.single, bytes)) {
    throw StateError('DrawingChart.opened(...).encode() changed the bytes');
  }
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
