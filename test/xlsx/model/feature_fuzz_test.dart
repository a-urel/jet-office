import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../support/event_loop.dart';
import '../../support/read_xlsx.dart';
import '../../support/timing.dart';
import '../read/support/zip_builder.dart';
import 'support/feature_fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 100;

/// Adler-32 of the first [_cases] cases of each of [_seeds]: their
/// descriptions and bytes' lengths, computed once on the VM. The Chrome leg
/// compares it, which proves a seed gives the same cases in a browser. A
/// changed `m3_*`, `m4_*`, `c1_kinds` or `c2_kinds` fixture changes it, and
/// so did C2's adding `c2_kinds` and aiming the mutations at chart parts.
const int _casesDigest = 213320251;

/// Adler-32 of [data], in arithmetic that stays exact in a browser.
int _adler32(List<int> data) {
  int a = 1;
  int b = 0;
  for (final int byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return b * 65536 + a;
}

void main() {
  test('a seed gives the same cases everywhere', () {
    final StringBuffer all = StringBuffer();
    for (final int seed in _seeds) {
      for (final FuzzCase c in featureFuzzCases(seed, _cases)) {
        all.writeln('${c.mutation} ${c.bytes.length}');
      }
    }
    expect(_adler32(utf8.encode(all.toString())), _casesDigest);
  });

  test('the cases reach every feature part of the corpus', () {
    final Set<String> mutated = <String>{
      for (final int seed in _seeds)
        for (final FuzzCase c in featureFuzzCases(seed, _cases))
          ?mutatedPart(c.mutation),
    };
    expect(
      mutated,
      containsAll(<String>[
        'xl/workbook.xml',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
        'xl/worksheets/_rels/sheet1.xml.rels',
        'docProps/core.xml',
        'docProps/app.xml',
        'docProps/custom.xml',
        'xl/sharedStrings.xml',
        'xl/comments1.xml',
        'xl/drawings/drawing1.xml',
        'xl/drawings/vmlDrawing1.vml',
        'xl/drawings/_rels/drawing1.xml.rels',
        'xl/tables/table1.xml',
        'xl/charts/chart1.xml',
      ]),
    );
  });

  test('the corpus holds the C1 and C2 chart fixtures', () {
    expect(<String>[
      for (final ({String name, Uint8List bytes}) e in featureCorpus()) e.name,
    ], containsAll(<String>['c1_kinds', 'c2_kinds']));
  });

  test('every corpus entry exercises cleanly', () {
    for (final ({String name, Uint8List bytes}) entry in featureCorpus()) {
      expect(() => exerciseFeatures(entry.bytes), returnsNormally);
    }
  });

  test('undo restores every corpus entry', () {
    for (final ({String name, Uint8List bytes}) entry in featureCorpus()) {
      expect(
        () => exerciseFeatures(entry.bytes, proveUndo: true),
        returnsNormally,
        reason: entry.name,
      );
    }
  });

  group('undoDifferences leaves out only what the mutated part may lose', () {
    const String sheet = 'xl/worksheets/sheet1.xml';
    const String rels = 'xl/worksheets/_rels/sheet1.xml.rels';
    const String styles = 'xl/styles.xml';
    final Uint8List clean = featureCorpus()
        .firstWhere(
          (({String name, Uint8List bytes}) e) => e.name == 'excel_features',
        )
        .bytes;

    /// [clean] with [edit] applied to the text of [part].
    Uint8List changed(String part, String Function(String text) edit) {
      final Map<String, Uint8List> parts = readXlsxBytes(clean);
      return buildZipOrdered(<(String, List<int>)>[
        for (final MapEntry<String, Uint8List> e in parts.entries)
          (
            e.key,
            e.key == part ? utf8.encode(edit(utf8.decode(e.value))) : e.value,
          ),
      ], store: true);
    }

    void expectOnlyFor(String part, Uint8List lossy) {
      expect(undoDifferences(lossy, clean, mutated: part), isEmpty);
      expect(
        undoDifferences(lossy, clean, mutated: 'xl/workbook.xml'),
        isNot(isEmpty),
      );
      expect(undoDifferences(lossy, clean), isNot(isEmpty));
    }

    test('stray text', () {
      expectOnlyFor(
        sheet,
        changed(
          sheet,
          (String t) => t.replaceFirst('</sheetData>', '</sheetData>stray'),
        ),
      );
    });

    test('text in a styles part', () {
      expectOnlyFor(
        styles,
        changed(
          styles,
          (String t) => t.replaceFirst('<dxfs count="1">', '<dxfs count="1">x'),
        ),
      );
    });

    test('a relationship the parse skips', () {
      expectOnlyFor(
        rels,
        changed(
          rels,
          (String t) =>
              t.replaceFirst('</Relationships>', '<Other/></Relationships>'),
        ),
      );
    });

    test('a value of a part no ignore names is reported', () {
      final Uint8List other = changed(
        sheet,
        (String t) => t.replaceFirst('<v>1</v>', '<v>7</v>'),
      );
      expect(undoDifferences(other, clean, mutated: sheet), isNot(isEmpty));
      expect(
        undoDifferences(other, clean, mutated: 'xl/sharedStrings.xml'),
        isNot(isEmpty),
      );
      expect(
        undoDifferences(other, clean, mutated: archiveMutated),
        isNot(isEmpty),
      );
    });
  });

  /// The case of [seed] and [index] that mutated [part] of the corpus entry
  /// [entry] by [edit] of its text, described as [what], built here: the
  /// cases of a seed change whenever the corpus does (C2 added `c2_kinds`).
  FuzzCase rebuilt(
    int seed,
    int index,
    String entry,
    String part,
    String what,
    String Function(String text) edit,
  ) {
    final Map<String, Uint8List> parts = readXlsxBytes(
      featureCorpus()
          .firstWhere((({String name, Uint8List bytes}) e) => e.name == entry)
          .bytes,
    );
    final String before = utf8.decode(parts[part]!);
    final String after = edit(before);
    expect(after, isNot(before), reason: what);
    return (
      seed: seed,
      index: index,
      mutation: '$entry $part: $what',
      bytes: buildZipOrdered(<(String, List<int>)>[
        for (final MapEntry<String, Uint8List> e in parts.entries)
          (e.key, e.key == part ? utf8.encode(after) : e.value),
      ], store: true),
    );
  }

  test('removing a table whose users name a column it lacks is a refusal', () {
    // Seed 7 case 328 of the long run: a mutated tableColumn name leaves
    // `Stock[[#This Row],[Qty]]` naming no column, so removeTable refuses.
    final FuzzCase c = rebuilt(
      7,
      328,
      'excel_objects',
      'xl/tables/table1.xml',
      'set name to "NaN"',
      (String t) => t.replaceFirst('name="Qty"', 'name="NaN"'),
    );
    expect(() => exerciseFeatureCase(c), returnsNormally);
  });

  test('a comments author XML forbids does not crash a table removal', () {
    // Seed 39 case 267 of the long run (and seed 30 case 354).
    for (final FuzzCase c in <FuzzCase>[
      rebuilt(
        39,
        267,
        'm4_notes',
        'xl/comments1.xml',
        'insert "&#1;" at 151',
        (String t) => t.replaceFirst(
          '<author>Ahmet</author>',
          '<author>Ahm&#1;et</author>',
        ),
      ),
      rebuilt(
        30,
        354,
        'excel_objects',
        'xl/comments1.xml',
        r'insert " xmlns:o=\"urn:&#1;o\"" at 338',
        (String t) =>
            t.replaceFirst('<author>tc={', '<author>tc xmlns:o="urn:&#1;o"={'),
      ),
    ]) {
      expect(
        () => exerciseFeatureCase(c),
        anyOf(returnsNormally, throwsA(isA<XlsxReadException>())),
        reason: c.mutation,
      );
    }
  });

  test('a TargetMode spoilt by a character reference XML forbids is a loss '
      'of the mutated relationships part', () {
    // Seed 3 case 299 of the long run (C2): `Exte&#1;rnal` reads as no
    // mode, so undo writes the relationship internal; only the text
    // compared drops the reference and reads `External`.
    final FuzzCase c = rebuilt(
      3,
      299,
      'm3_hyperlinks',
      'xl/worksheets/_rels/sheet1.xml.rels',
      'insert "&#1;" at 488',
      (String t) => t.replaceFirst(
        '%C3%A7" TargetMode="External"',
        '%C3%A7" TargetMode="Exte&#1;rnal"',
      ),
    );
    expect(() => exerciseFeatureCase(c), returnsNormally);
  });

  test('a picture read with a size the writer refuses may be refused when '
      'added back', () {
    // Seed 10 case 425 of the long run (C2): a one-cell anchor of height 0.
    final FuzzCase c = rebuilt(
      10,
      425,
      'm4_images',
      'xl/drawings/drawing1.xml',
      'set cy to "0"',
      (String t) => t.replaceFirst('cy="19050"', 'cy="0"'),
    );
    expect(() => exerciseFeatureCase(c), returnsNormally);
  });

  test('a part name whose case a mutation flipped compares as the same', () {
    // Seed 36 case 204 of the long run: `xl/worksheets/Sheet1.xml` beside
    // `xl/worksheets/_rels/sheet1.xml.rels`; undo writes the relationships
    // part after the source's spelling, which OPC takes as the same name.
    // Built here, as C2's rebuilt `c1_kinds` changed the seed's cases.
    const int bit = 55077;
    final Uint8List bytes = Uint8List.fromList(
      featureCorpus()
          .firstWhere(
            (({String name, Uint8List bytes}) e) => e.name == 'excel_features',
          )
          .bytes,
    );
    bytes[bit >> 3] ^= 1 << (bit & 7);
    expect(latin1.decode(bytes), contains('xl/worksheets/Sheet1.xml'));
    final FuzzCase c = (
      seed: 36,
      index: 204,
      mutation: 'excel_features (archive): flip bits [$bit]',
      bytes: bytes,
    );
    expect(() => exerciseFeatureCase(c), returnsNormally);
  });

  test('mutated files raise only XlsxReadException', () async {
    final List<String> failures = <String>[];
    final EventLoopBreather breather = EventLoopBreather();
    for (final int seed in _seeds) {
      for (final FuzzCase c in featureFuzzCases(seed, _cases)) {
        final Stopwatch watch = Stopwatch()..start();
        try {
          exerciseFeatureCase(c);
        } on XlsxReadException {
          // A file problem, reported as the model promises.
        } on Object catch (e) {
          failures.add('seed ${c.seed} case ${c.index} (${c.mutation}): $e');
        }
        // A case over the bound runs again, as a busy machine can slow one
        // run; only a case slow in every run is a hang.
        final Duration? hang = confirmedHang(watch.elapsed, () {
          try {
            exerciseFeatureCase(c);
          } on Object {
            // Reported by the first run.
          }
        });
        if (hang != null) {
          failures.add(
            'seed ${c.seed} case ${c.index} (${c.mutation}): hang, '
            '${hang.inMilliseconds} ms',
          );
        }
        // Chrome runs every suite on this thread: give the others a turn.
        await breather.breathe();
      }
    }
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
