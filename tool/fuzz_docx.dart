/// Fuzzes `DocxDocument` with seeded mutations, for runs longer than the
/// quality gate's.
///
/// ```bash
/// dart run tool/fuzz_docx.dart [--template] [--seeds 1-20] [--cases 500]
///     [--verbose]
/// ```
///
/// For every seed of the inclusive range `--seeds` (default `1-20`, or a
/// single seed such as `7`) it mutates `--cases` (default 500) corpus files
/// as `test/docx/support/docx_fuzz.dart` describes and opens each one with
/// `exerciseDocx`. Anything thrown other than a `DocxReadException`, and
/// any case taking more than 5 s in each of three runs, is a failure and
/// printed as `seed <s> case <i> (<mutation>): <error>`, which
/// `docxFuzzCases(s, i + 1)` reproduces. A summary line follows; the exit code is
/// 1 on any failure and 64 on bad arguments.
///
/// A hang is measured after a case returns, so a real infinite loop is not
/// reported by this tool; it stops only when killed. With `--verbose` each
/// case is written to stderr as `seed <s> case <i> (<mutation>)` before it
/// runs, so the last line names the case that never came back.
///
/// The quality gate runs seeds 1 to 4 with 900 cases each
/// (`test/docx/fuzz_test.dart`).
///
/// With `--template` it fuzzes `DocxTemplate` instead (decision 0024, T1): the
/// cases of `templateFuzzCases` (`test/docx/support/template_fuzz.dart`, the
/// T1 templates and Word's split tags, with tags and switches inserted into
/// their text), each run through `exerciseTemplate`, which `templateFuzzCases(s,
/// i + 1)` reproduces. The quality gate runs seeds 1 to 4 with 300 cases each
/// (`test/docx/template/template_fuzz_test.dart`).
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';

import '../test/docx/support/docx_fuzz.dart';
import '../test/docx/support/template_fuzz.dart'
    show exerciseTemplate, templateFuzzCases;
import 'src/fuzz_run.dart';

void main(List<String> args) {
  final ({int first, int last, int cases, bool verbose, bool template})?
  options = _parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/fuzz_docx.dart [--template] [--seeds 1-20] '
      '[--cases 500] [--verbose]',
    );
    exitCode = 64;
    return;
  }
  final Stopwatch total = Stopwatch()..start();
  final FuzzRunResult result = runFuzz(
    first: options.first,
    last: options.last,
    cases: options.cases,
    verbose: options.verbose,
    exercise: options.template ? exerciseTemplate : exerciseDocx,
    generate: options.template ? templateFuzzCases : docxFuzzCases,
    isRefusal: (Object e) => e is DocxReadException,
    out: stdout,
    err: stderr,
  );
  stdout.writeln(
    'seeds ${options.first}-${options.last}: ${result.cases} cases, '
    '${result.refused} refused with DocxReadException, '
    '${result.failures} failures, '
    '${total.elapsed.inMilliseconds} ms',
  );
  if (result.failures > 0) exitCode = 1;
}

/// The seed range and case count of [args], or `null` when they are not
/// understood.
({int first, int last, int cases, bool verbose, bool template})? _parse(
  List<String> args,
) {
  int first = 1;
  int last = 20;
  int cases = 500;
  bool verbose = false;
  bool template = false;
  for (int i = 0; i < args.length; i += 2) {
    if (args[i] == '--verbose' || args[i] == '--template') {
      if (args[i] == '--verbose') verbose = true;
      if (args[i] == '--template') template = true;
      i--;
      continue;
    }
    if (i + 1 >= args.length) return null;
    final String value = args[i + 1];
    switch (args[i]) {
      case '--seeds':
        final List<String> ends = value.split('-');
        if (ends.length > 2) return null;
        final int? from = int.tryParse(ends.first);
        final int? to = int.tryParse(ends.last);
        if (from == null || to == null || from < 0 || to < from) return null;
        first = from;
        last = to;
      case '--cases':
        final int? n = int.tryParse(value);
        if (n == null || n < 1) return null;
        cases = n;
      default:
        return null;
    }
  }
  return (
    first: first,
    last: last,
    cases: cases,
    verbose: verbose,
    template: template,
  );
}
