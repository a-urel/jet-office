/// Writes the worst case's package to standard output, for the worst-case
/// read benchmark.
///
/// New in jet_office. `workload_file_vm.dart` runs it as a child process:
/// `dart <package root>/benchmark/src/write_worst_case.dart`.
library;

import 'dart:io' show stdout;

import 'worst_case.dart';

/// Builds the worst case's package and sends its bytes to standard output.
Future<void> main() async {
  stdout.add(buildWorstCase());
  await stdout.flush();
}
