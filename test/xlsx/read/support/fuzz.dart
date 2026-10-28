/// Test helper: seeded mutation fuzzing of `XlsxReader`.
///
/// [fuzzCorpus] is the set of valid packages the fuzzer starts from,
/// [fuzzCases] derives mutated copies of them from a seed, and
/// [exerciseReader] drives the whole public reader surface over one file.
/// `test/xlsx/read/fuzz_test.dart` runs a fixed range of seeds in the
/// quality gate; `tool/fuzz_reader.dart` runs any range by hand.
///
/// A seed gives the same cases on the VM and in a browser: [Xorshift32]
/// stays within 32 bits, and the corpus is stored, not deflated, so its
/// bytes do not depend on the platform's deflater. Two deflated corpus
/// entries fuzz inflation; their cases may differ by platform (decision
/// 0006).
///
/// The 5 s hang bound is checked after a case returns, so a real infinite
/// loop is not reported as a hang: the test's 4-minute timeout stops it and
/// names no case. `tool/fuzz_reader.dart --verbose` writes each case to
/// stderr before it runs, so the last line names it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../../../fixtures/fixtures.dart';
import '../../../support/read_xlsx.dart';
import 'producers.dart';
import 'zip_builder.dart';

/// A xorshift32 pseudo-random generator (Marsaglia, 2003).
///
/// Every step is a 32-bit shift, xor or mask, which the VM and dart2js
/// compute exactly alike, so a seed gives the same sequence everywhere.
final class Xorshift32 {
  /// A generator started from [seed]; only its low 32 bits count, and a
  /// seed of 0, which xorshift cannot leave, is replaced by a fixed one.
  ///
  /// The first outputs of a small seed are small, so the generator steps
  /// past them before it is used.
  Xorshift32(int seed) : _state = seed & _mask {
    if (_state == 0) _state = 0x9E3779B9;
    for (int i = 0; i < 16; i++) {
      _next();
    }
  }

  static const int _mask = 0xFFFFFFFF;

  int _state;

  int _next() {
    int x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >>> 17;
    x ^= (x << 5) & _mask;
    return _state = x & _mask;
  }

  /// A value from 0 inclusive to [max] exclusive.
  ///
  /// Throws a [RangeError] when [max] is not between 1 and 2^32.
  int nextInt(int max) {
    RangeError.checkValueInInterval(max, 1, 0x100000000, 'max');
    return _next() % max;
  }
}

/// One mutated file: case `index` of `seed`, described by `mutation`.
///
/// `mutation` reads `<corpus> <part>: <operation>` for a change inside one
/// part and `<corpus> (archive): <operation>` for a change to the archive's
/// bytes; [mutatedPart] extracts the part.
typedef FuzzCase = ({int seed, int index, String mutation, Uint8List bytes});

/// The fixtures of `allFixtures()` in the corpus: `m1_values`, the smallest
/// fixture with a formula and the smallest with a date format.
const List<String> _corpusFixtures = <String>[
  'm1_values',
  'm1_formulas',
  'm1_dates',
];

/// The corpus entries also added deflated, to fuzz inflation.
const List<String> _deflated = <String>['m1_values', 'libreoffice'];

/// The valid packages the fuzzer mutates, in a fixed order.
///
/// The fixtures named in `_corpusFixtures` and every `producerFiles()`
/// entry, each rebuilt with stored entries and a fixed timestamp, so the
/// bytes are equal on every platform; then `m1_values` and `libreoffice`
/// deflated, named with a `_deflated` suffix.
List<({String name, Uint8List bytes})> fuzzCorpus() {
  final Map<String, Uint8List> sources = <String, Uint8List>{
    for (final Fixture f in allFixtures())
      if (_corpusFixtures.contains(f.name)) f.name: f.build(),
    for (final ProducerFile p in producerFiles()) p.name: p.bytes,
  };
  return <({String name, Uint8List bytes})>[
    for (final MapEntry<String, Uint8List> source in sources.entries)
      (name: source.key, bytes: _rebuild(source.value, store: true)),
    for (final String name in _deflated)
      (name: '${name}_deflated', bytes: _rebuild(sources[name]!, store: false)),
  ];
}

/// [zip] with the same entries in the same order, written again.
Uint8List _rebuild(Uint8List zip, {required bool store}) =>
    buildZipOrdered(<(String, List<int>)>[
      for (final MapEntry<String, Uint8List> e in readXlsxBytes(zip).entries)
        (e.key, e.value),
    ], store: store);

/// The entry names of the corpus package [zip], in archive order.
List<String> corpusPartNames(Uint8List zip) => readXlsxBytes(zip).keys.toList();

/// The part that [mutation], a `FuzzCase.mutation`, changed, or `null` for
/// a change to the archive's bytes.
String? mutatedPart(String mutation) {
  final RegExpMatch? match = RegExp(r'^\S+ (\S+): ').firstMatch(mutation);
  final String? part = match?.group(1);
  return part == '(archive)' ? null : part;
}

/// The tokens the insert mutation puts into a part: markup, references,
/// escapes and numbers that the reader's parsers treat specially.
final List<String> _tokens = <String>[
  '<',
  '>',
  '&',
  '"',
  '</c>',
  '<c r="A1">',
  '<v>',
  ' t="s"',
  ' t="d"',
  ' t="e"',
  ' r="XFD1048577"',
  '<f t="shared" si="0"/>',
  '<f t="array" ref="A1:B2">1</f>',
  '<!DOCTYPE a>',
  '_x0000_',
  '&#0;',
  'E999999999',
  '-',
  '99999999999999999999',
  '<a>' * 300,
];

/// The first [count] cases of [seed], each one mutation of one corpus
/// entry.
///
/// The entry is chosen uniformly, then one of eight operations. On the
/// archive's bytes: truncate; flip 1 to 8 bits; overwrite 4 bytes with
/// `FF FF FF FF` or `00 00 00 00`. On one part, chosen uniformly among the
/// entry's parts, after which the archive is rebuilt stored with correct
/// CRCs: truncate; delete a span of 1 to 16 bytes; duplicate such a span;
/// insert a token of `_tokens`; replace a digit with another (a part
/// without digits gets a token instead).
///
/// Lazy, and the same for the same arguments every time.
Iterable<FuzzCase> fuzzCases(int seed, int count) sync* {
  final List<({String name, Uint8List bytes})> corpus = fuzzCorpus();
  final List<List<(String, Uint8List)>> parts = <List<(String, Uint8List)>>[
    for (final ({String name, Uint8List bytes}) entry in corpus)
      <(String, Uint8List)>[
        for (final MapEntry<String, Uint8List> e in readXlsxBytes(
          entry.bytes,
        ).entries)
          (e.key, e.value),
      ],
  ];
  final Xorshift32 random = Xorshift32(seed);
  for (int index = 0; index < count; index++) {
    final int pick = random.nextInt(corpus.length);
    final ({String name, Uint8List bytes}) entry = corpus[pick];
    final int operation = random.nextInt(8);
    final (String, Uint8List) mutated = operation < 3
        ? _mutateArchive(entry.bytes, operation, random)
        : _mutatePart(parts[pick], operation - 3, random);
    yield (
      seed: seed,
      index: index,
      mutation: '${entry.name} ${mutated.$1}',
      bytes: mutated.$2,
    );
  }
}

/// Applies archive operation [operation] (0 to 2) to [zip].
(String, Uint8List) _mutateArchive(
  Uint8List zip,
  int operation,
  Xorshift32 random,
) {
  switch (operation) {
    case 0:
      final int length = random.nextInt(zip.length);
      return (
        '(archive): truncate to $length of ${zip.length}',
        Uint8List.sublistView(zip, 0, length),
      );
    case 1:
      final Uint8List out = Uint8List.fromList(zip);
      final int flips = 1 + random.nextInt(8);
      final List<int> bits = <int>[];
      for (int i = 0; i < flips; i++) {
        final int bit = random.nextInt(out.length * 8);
        out[bit >> 3] ^= 1 << (bit & 7);
        bits.add(bit);
      }
      return ('(archive): flip bits $bits', out);
    default:
      final Uint8List out = Uint8List.fromList(zip);
      final int at = random.nextInt(out.length - 3);
      final int byte = random.nextInt(2) == 0 ? 0xFF : 0x00;
      out.fillRange(at, at + 4, byte);
      final String hex = byte.toRadixString(16).padLeft(2, '0');
      return ('(archive): overwrite 4 bytes at $at with $hex', out);
  }
}

/// Applies part operation [operation] (0 to 4) to one part of [parts],
/// chosen uniformly, and rebuilds the archive stored.
(String, Uint8List) _mutatePart(
  List<(String, Uint8List)> parts,
  int operation,
  Xorshift32 random,
) {
  final int which = random.nextInt(parts.length);
  final (String name, Uint8List part) = parts[which];
  final (String what, List<int> bytes) = _mutateBytes(part, operation, random);
  return (
    '$name: $what',
    buildZipOrdered(<(String, List<int>)>[
      for (int i = 0; i < parts.length; i++)
        i == which ? (name, bytes) : parts[i],
    ], store: true),
  );
}

/// Applies part operation [operation] (0 to 4) to the bytes of one part.
(String, List<int>) _mutateBytes(
  Uint8List part,
  int operation,
  Xorshift32 random,
) {
  final int n = part.length;
  switch (operation) {
    case 0:
      final int length = n == 0 ? 0 : random.nextInt(n);
      return ('truncate to $length of $n', part.sublist(0, length));
    case 1 || 2:
      if (n == 0) return _insertToken(part, random);
      final int at = random.nextInt(n);
      final int end = at + 1 + random.nextInt(16);
      final int stop = end > n ? n : end;
      if (operation == 1) {
        return (
          'delete $at..$stop',
          <int>[...part.sublist(0, at), ...part.sublist(stop)],
        );
      }
      return (
        'duplicate $at..$stop',
        <int>[...part.sublist(0, stop), ...part.sublist(at)],
      );
    case 3:
      return _insertToken(part, random);
    default:
      final List<int> digits = <int>[
        for (int i = 0; i < n; i++)
          if (part[i] >= 0x30 && part[i] <= 0x39) i,
      ];
      if (digits.isEmpty) return _insertToken(part, random);
      final int at = digits[random.nextInt(digits.length)];
      final int digit = 0x30 + (part[at] - 0x30 + 1 + random.nextInt(9)) % 10;
      final Uint8List out = Uint8List.fromList(part)..[at] = digit;
      return ('replace digit at $at with ${String.fromCharCode(digit)}', out);
  }
}

/// [part] with one token of `_tokens` inserted at a random offset.
(String, List<int>) _insertToken(Uint8List part, Xorshift32 random) {
  final String token = _tokens[random.nextInt(_tokens.length)];
  final int at = random.nextInt(part.length + 1);
  final String shown = token.length > 20
      ? '${token.substring(0, 9)}... (${token.length} chars)'
      : token;
  return (
    'insert ${jsonEncode(shown)} at $at',
    <int>[...part.sublist(0, at), ...utf8.encode(token), ...part.sublist(at)],
  );
}

/// Opens [bytes], reads every sheet's rows and merges, and renders every
/// row, every warning in English, German and Turkish, and the exception.
///
/// Returns normally or throws [XlsxReadException]. A sheet whose rows or
/// merges throw one does not stop the others: the first exception is
/// rethrown after every sheet has been read and every warning rendered.
/// Anything else thrown is a reader defect and propagates at once.
void exerciseReader(Uint8List bytes) {
  try {
    _exercise(bytes);
  } on XlsxReadException catch (e) {
    e.toString();
    rethrow;
  }
}

void _exercise(Uint8List bytes) {
  final XlsxReader reader = XlsxReader(bytes);
  XlsxReadException? first;
  for (final XlsxReadSheet sheet in reader.sheets) {
    sheet.toString();
    try {
      for (final XlsxReadRow row in reader.rowsAt(sheet.index)) {
        row.toString();
      }
    } on XlsxReadException catch (e) {
      first ??= e;
    }
    try {
      reader.mergesAt(sheet.index).toString();
    } on XlsxReadException catch (e) {
      first ??= e;
    }
  }
  for (final XlsxWarning warning in reader.warnings) {
    for (final XlsxLocale locale in XlsxLocale.values) {
      warning.message(locale);
    }
  }
  if (first != null) throw first;
}
