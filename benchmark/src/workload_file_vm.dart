/// The workload's file on the VM: written by a child process.
///
/// New in jet_office.
library;

import 'dart:io' show Platform, Process, ProcessResult;
import 'dart:isolate' show Isolate;
import 'dart:typed_data';

/// Writes the workload of [rows] data rows with `XlsxWriter` in a child
/// `dart` process and returns the file's bytes.
///
/// The child runs `benchmark/src/write_workload.dart` of this package, found
/// from the package's own `lib/` (so the working directory does not matter),
/// and sends the file on standard output. Throws a [StateError] when the
/// package cannot be found or the child process fails.
Uint8List workloadFile(int rows) {
  final Uri? library = Isolate.resolvePackageUriSync(
    Uri.parse('package:jet_office/jet_office.dart'),
  );
  if (library == null) {
    throw StateError('package:jet_office cannot be resolved.');
  }
  final Uri root = library.resolve('..');
  final String script = root
      .resolve('benchmark/src/write_workload.dart')
      .toFilePath();
  final ProcessResult result = Process.runSync(
    Platform.resolvedExecutable,
    <String>[script, '$rows'],
    workingDirectory: root.toFilePath(),
    stdoutEncoding: null,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'write_workload.dart exited with ${result.exitCode}: ${result.stderr}',
    );
  }
  final Object? out = result.stdout;
  if (out is! List<int> || out.isEmpty) {
    throw StateError('write_workload.dart wrote no bytes.');
  }
  return out is Uint8List ? out : Uint8List.fromList(out);
}
