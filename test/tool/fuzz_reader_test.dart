// Tests the case loop behind tool/fuzz_reader.dart: with `verbose`, each
// case is written to the error sink before the reader runs on it, so the
// last line names a case that never came back.
//
// It reads no files, so it runs on the web as well as the VM.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/fuzz_run.dart';

void main() {
  group('runFuzz', () {
    test('verbose writes each case line before that case runs', () {
      final List<String> events = <String>[];
      final _Log err = _Log(events, 'line');
      final FuzzRunResult r = runFuzz(
        first: 1,
        last: 1,
        cases: 2,
        verbose: true,
        out: StringBuffer(),
        err: err,
        exercise: (Uint8List bytes) => events.add('run'),
      );
      expect(r.cases, 2);
      expect(r.failures, 0);
      expect(events, <String>['line', 'run', 'line', 'run']);
      expect(err.lines.first, matches(RegExp(r'^seed 1 case 0 \(.+\)$')));
      expect(err.lines.last, matches(RegExp(r'^seed 1 case 1 \(.+\)$')));
    });

    test('without verbose nothing is written to the error sink', () {
      final StringBuffer err = StringBuffer();
      final FuzzRunResult r = runFuzz(
        first: 1,
        last: 1,
        cases: 2,
        verbose: false,
        out: StringBuffer(),
        err: err,
        exercise: (Uint8List bytes) {},
      );
      expect(r.cases, 2);
      expect(err.toString(), isEmpty);
    });

    test('a refusal is counted and anything else is a failure', () {
      int n = 0;
      final StringBuffer out = StringBuffer();
      final FuzzRunResult r = runFuzz(
        first: 1,
        last: 1,
        cases: 2,
        verbose: false,
        out: out,
        err: StringBuffer(),
        exercise: (Uint8List bytes) {
          n++;
          if (n == 1) {
            throw XlsxReadException(XlsxReadFailure.notZip, 'no');
          }
          throw StateError('boom');
        },
      );
      expect(r.refused, 1);
      expect(r.failures, 1);
      expect(out.toString(), matches(RegExp(r'^seed 1 case 1 \(.+\): .*boom')));
    });
  });
}

/// A sink that records each line it receives in [events] as [tag].
final class _Log implements StringSink {
  _Log(this.events, this.tag);

  final List<String> events;
  final String tag;
  final List<String> lines = <String>[];

  @override
  void writeln([Object? object = '']) {
    lines.add('$object');
    events.add(tag);
  }

  @override
  void write(Object? object) => throw UnimplementedError();

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      throw UnimplementedError();

  @override
  void writeCharCode(int charCode) => throw UnimplementedError();
}
