import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../read/support/zip_builder.dart';
import 'support/feature_fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 100;

/// Adler-32 of the first [_cases] cases of each of [_seeds]: their
/// descriptions and bytes' lengths, computed once on the VM. The Chrome leg
/// compares it, which proves a seed gives the same cases in a browser. A
/// changed `m3_*`, `m4_*` or `c1_kinds` fixture changes it.
const int _casesDigest = 1795111468;

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
      ]),
    );
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

  test('removing a table whose users name a column it lacks is a refusal', () {
    // Seed 7 case 328 of the long run: a mutated tableColumn name leaves
    // `Stock[[#This Row],[Qty]]` naming no column, so removeTable refuses.
    final FuzzCase c = featureFuzzCases(7, 329).last;
    expect(c.mutation, contains('xl/tables/table1.xml'));
    expect(() => exerciseFeatureCase(c), returnsNormally);
  });

  test('a comments author XML forbids does not crash a table removal', () {
    // Seed 39 case 267 of the long run (and seed 30 case 354).
    for (final (int seed, int index) in <(int, int)>[(39, 267), (30, 354)]) {
      final FuzzCase c = featureFuzzCases(seed, index + 1).last;
      expect(
        () => exerciseFeatureCase(c),
        anyOf(returnsNormally, throwsA(isA<XlsxReadException>())),
        reason: c.mutation,
      );
    }
  });

  test('a part name whose case a mutation flipped compares as the same', () {
    // Seed 36 case 204 of the long run: `xl/worksheets/Sheet1.xml` beside
    // `xl/worksheets/_rels/sheet1.xml.rels`; undo writes the relationships
    // part after the source's spelling, which OPC takes as the same name.
    final FuzzCase c = featureFuzzCases(36, 205).last;
    expect(c.mutation, contains('(archive)'));
    expect(() => exerciseFeatureCase(c), returnsNormally);
  });

  test('mutated files raise only XlsxReadException', () {
    final List<String> failures = <String>[];
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
        if (watch.elapsed > const Duration(seconds: 5)) {
          failures.add(
            'seed ${c.seed} case ${c.index} (${c.mutation}): hang, '
            '${watch.elapsedMilliseconds} ms',
          );
        }
      }
    }
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
