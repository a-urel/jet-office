/// The workload's file on the VM: written by a child process.
///
/// New in jet_office.
library;

import 'dart:io' show Platform, Process, ProcessResult;
import 'dart:typed_data';

/// Writes the workload of [rows] data rows with `XlsxWriter` in a child
/// `dart` process and returns the file's bytes.
///
/// Throws a [StateError] when the child process fails.
Uint8List workloadFile(int rows) {
  final ProcessResult result = Process.runSync(
    Platform.resolvedExecutable,
    <String>['run', 'benchmark/src/write_workload.dart', '$rows'],
    stdoutEncoding: null,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'write_workload.dart exited with ${result.exitCode}: ${result.stderr}',
    );
  }
  final Object? out = result.stdout;
  if (out is! List<int>) {
    throw StateError('write_workload.dart wrote no bytes.');
  }
  return out is Uint8List ? out : Uint8List.fromList(out);
}
