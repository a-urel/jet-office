/// Test helper: the seeded mutations that fuzz the XLSX reader and the DOCX
/// model.
///
/// Moved out of `test/xlsx/read/support/fuzz.dart` in phase 4 (D1) so that
/// `test/docx/support/docx_fuzz.dart` shares them; a seed gives the same
/// cases as before the move. [mutationCases] derives mutated copies of a
/// corpus of ZIP packages from a seed: it chooses an entry, then one of
/// eight operations, drawing from [Xorshift32] in a fixed order. The
/// callers supply the corpus and the tokens their parsers treat specially.
///
/// A seed gives the same cases on the VM and in a browser: [Xorshift32]
/// stays within 32 bits, and a stored corpus does not depend on the
/// platform's deflater (decision 0006).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../xlsx/read/support/zip_builder.dart';

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

/// The part that [mutation], a `FuzzCase.mutation`, changed, or `null` for
/// a change to the archive's bytes.
String? mutatedPart(String mutation) {
  final RegExpMatch? match = RegExp(r'^\S+ (\S+): ').firstMatch(mutation);
  final String? part = match?.group(1);
  return part == '(archive)' ? null : part;
}

/// A mutation of the bytes of one part that a caller adds to the eight
/// operations of [mutationCases]: given the part's name and bytes, it
/// returns what it did, as shown in the case's description, and the new
/// bytes.
typedef PartMutation =
    (String, List<int>) Function(
      String name,
      Uint8List part,
      Xorshift32 random,
    );

/// The first [count] cases of [seed], each one mutation of one entry of
/// [corpus]; [parts] holds the parts of each entry, in the same order.
///
/// [extra] adds operations on one part, chosen uniformly like the others,
/// after the eight, on a part chosen among those [extraParts] accepts (all
/// of them when it is null or accepts none); with none the cases are the
/// ones the eight give, so the XLSX seeds do not move.
///
/// The entry is chosen uniformly, then one of eight operations. On the
/// archive's bytes: truncate; flip 1 to 8 bits; overwrite 4 bytes with
/// `FF FF FF FF` or `00 00 00 00`. On one part, chosen uniformly among the
/// entry's parts, after which the archive is rebuilt stored with correct
/// CRCs: truncate; delete a span of 1 to 16 bytes; duplicate such a span;
/// insert a token of [tokens]; replace a digit with another (a part
/// without digits gets a token instead).
///
/// Lazy, and the same for the same arguments every time.
Iterable<FuzzCase> mutationCases({
  required int seed,
  required int count,
  required List<({String name, Uint8List bytes})> corpus,
  required List<List<(String, Uint8List)>> parts,
  required List<String> tokens,
  List<PartMutation> extra = const <PartMutation>[],
  bool Function(String name)? extraParts,
}) sync* {
  final Xorshift32 random = Xorshift32(seed);
  for (int index = 0; index < count; index++) {
    final int pick = random.nextInt(corpus.length);
    final ({String name, Uint8List bytes}) entry = corpus[pick];
    final int operation = random.nextInt(8 + extra.length);
    final (String, Uint8List) mutated = operation < 3
        ? mutateArchive(entry.bytes, operation, random)
        : mutatePart(
            parts[pick],
            operation - 3,
            random,
            tokens,
            extra: extra,
            extraParts: extraParts,
          );
    yield (
      seed: seed,
      index: index,
      mutation: '${entry.name} ${mutated.$1}',
      bytes: mutated.$2,
    );
  }
}

/// Applies archive operation [operation] (0 to 2) to [zip].
(String, Uint8List) mutateArchive(
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

/// Applies part operation [operation] (0 to 4, and from 5 on the entries
/// of [extra]) to one part of [parts], chosen uniformly (an [extra] one
/// among those [extraParts] accepts), and rebuilds the archive stored.
(String, Uint8List) mutatePart(
  List<(String, Uint8List)> parts,
  int operation,
  Xorshift32 random,
  List<String> tokens, {
  List<PartMutation> extra = const <PartMutation>[],
  bool Function(String name)? extraParts,
}) {
  final List<int> choices = <int>[
    for (int i = 0; i < parts.length; i++)
      if (operation < 5 || extraParts == null || extraParts(parts[i].$1)) i,
  ];
  final int which = choices.isEmpty
      ? random.nextInt(parts.length)
      : choices[random.nextInt(choices.length)];
  final (String name, Uint8List part) = parts[which];
  final (String what, List<int> bytes) = operation < 5
      ? mutateBytes(part, operation, random, tokens)
      : extra[operation - 5](name, part, random);
  return (
    '$name: $what',
    buildZipOrdered(<(String, List<int>)>[
      for (int i = 0; i < parts.length; i++)
        i == which ? (name, bytes) : parts[i],
    ], store: true),
  );
}

/// Applies part operation [operation] (0 to 4) to the bytes of one part.
(String, List<int>) mutateBytes(
  Uint8List part,
  int operation,
  Xorshift32 random,
  List<String> tokens,
) {
  final int n = part.length;
  switch (operation) {
    case 0:
      final int length = n == 0 ? 0 : random.nextInt(n);
      return ('truncate to $length of $n', part.sublist(0, length));
    case 1 || 2:
      if (n == 0) return _insertToken(part, random, tokens);
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
      return _insertToken(part, random, tokens);
    default:
      final List<int> digits = <int>[
        for (int i = 0; i < n; i++)
          if (part[i] >= 0x30 && part[i] <= 0x39) i,
      ];
      if (digits.isEmpty) return _insertToken(part, random, tokens);
      final int at = digits[random.nextInt(digits.length)];
      final int digit = 0x30 + (part[at] - 0x30 + 1 + random.nextInt(9)) % 10;
      final Uint8List out = Uint8List.fromList(part)..[at] = digit;
      return ('replace digit at $at with ${String.fromCharCode(digit)}', out);
  }
}

/// [part] with one of [tokens] inserted at a random offset.
(String, List<int>) _insertToken(
  Uint8List part,
  Xorshift32 random,
  List<String> tokens,
) {
  final String token = tokens[random.nextInt(tokens.length)];
  final int at = random.nextInt(part.length + 1);
  final String shown = token.length > 20
      ? '${token.substring(0, 9)}... (${token.length} chars)'
      : token;
  return (
    'insert ${jsonEncode(shown)} at $at',
    <int>[...part.sublist(0, at), ...utf8.encode(token), ...part.sublist(at)],
  );
}
