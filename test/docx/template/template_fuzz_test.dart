// Fuzzes DocxTemplate (decision 0024, T1): seeded mutations of templates
// whose tags are split as Word splits them, of merge fields and of the
// template fill's hard cases, with tags and switches inserted into their
// text. Only DocxReadException may come out of opening a template or filling
// it; the filled file must read back, and data that names nothing must give
// the template back. The same cases run on the VM and in Chrome.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../support/event_loop.dart';
import '../../support/timing.dart';
import '../support/template_fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 300;

/// Adler-32 of every case's mutation and bytes, computed once on the VM. The
/// Chrome leg compares it, which proves both get the same cases. A change to
/// the corpus (the `t1_*` templates, `template_documents.dart`), to the
/// mutations or to the `package:archive` version resolved changes it.
const int _casesDigest = 3812990126;

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
  test('the corpus is the four templates, and each opens and fills', () {
    final List<({String name, Uint8List bytes})> corpus = templateFuzzCorpus();
    expect(
      <String>[for (final c in corpus) c.name],
      <String>[
        't1_template',
        't1_merge_fields',
        'word_split_header',
        'word_split_kinds',
      ],
    );
    for (final ({String name, Uint8List bytes}) entry in corpus) {
      expect(DocxTemplate(entry.bytes).tags, isNotEmpty, reason: entry.name);
      exerciseTemplate(entry.bytes, exact: true);
    }
  });

  test('the cases are the pinned ones, the same on every platform', () {
    final StringBuffer all = StringBuffer();
    for (final int seed in _seeds) {
      for (final FuzzCase c in templateFuzzCases(seed, _cases)) {
        all.writeln('${c.mutation} ${_adler32(c.bytes)}');
      }
    }
    expect(_adler32(utf8.encode(all.toString())), _casesDigest);
  });

  test('the cases insert tags and switches into the story parts', () {
    final List<String> mutations = <String>[
      for (final int seed in _seeds)
        for (final FuzzCase c in templateFuzzCases(seed, _cases)) c.mutation,
    ];
    expect(
      mutations.where((String m) => m.contains(' in w:t at ')),
      isNotEmpty,
    );
    expect(
      mutations.where((String m) => m.contains(' in w:instrText at ')),
      isNotEmpty,
    );
    expect(
      mutations.where((String m) => m.contains('word/header1.xml: insert')),
      isNotEmpty,
    );
    expect(
      mutations.where((String m) => m.contains('word/footer1.xml: insert')),
      isNotEmpty,
    );
  });

  test('mutated templates raise only DocxReadException', () async {
    final List<String> failures = <String>[];
    final EventLoopBreather breather = EventLoopBreather();
    int refused = 0;
    for (final int seed in _seeds) {
      for (final FuzzCase c in templateFuzzCases(seed, _cases)) {
        final Stopwatch watch = Stopwatch()..start();
        try {
          exerciseTemplate(c.bytes);
        } on DocxReadException {
          // A file problem, reported as the template promises.
          refused++;
        } on Object catch (e) {
          failures.add('seed ${c.seed} case ${c.index} (${c.mutation}): $e');
        }
        // A case over the bound runs again, as a busy machine can slow one
        // run; only a case slow in every run is a hang.
        final Duration? hang = confirmedHang(watch.elapsed, () {
          try {
            exerciseTemplate(c.bytes);
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
    printOnFailure('$refused of ${_seeds.length * _cases} refused');
    expect(failures, isEmpty);
    // Most cases must reach the fill, not stop at a refused file.
    expect(refused, lessThan(_seeds.length * _cases ~/ 2));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
