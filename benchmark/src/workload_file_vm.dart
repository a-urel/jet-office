/// The workload's file and the worst case's on the VM: written by a child
/// process.
///
/// New in jet_office.
library;

import 'dart:io' show Platform, Process, ProcessResult;
import 'dart:isolate' show Isolate;
import 'dart:typed_data';

/// Writes the workload of [rows] data rows with `XlsxWriter` in a child
/// `dart` process and returns the file's bytes.
///
/// The child runs `benchmark/src/write_workload.dart` of this package.
/// Throws a [StateError] when the package cannot be found or the child
/// process fails.
Uint8List workloadFile(int rows) =>
    _childOutput('write_workload.dart', <String>['$rows']);

/// Builds the worst case (`worst_case.dart`) in a child `dart` process and
/// returns the package's bytes.
///
/// The child runs `benchmark/src/write_worst_case.dart` of this package.
/// Throws a [StateError] when the package cannot be found or the child
/// process fails.
Uint8List worstCaseFile() => _childOutput('write_worst_case.dart', <String>[]);

/// Runs `benchmark/src/<script>` of this package with [args] in a child
/// `dart` process and returns what it wrote to standard output.
///
/// The script is found from the package's own `lib/`, so the working
/// directory does not matter.
Uint8List _childOutput(String script, List<String> args) {
  final Uri? library = Isolate.resolvePackageUriSync(
    Uri.parse('package:jet_office/jet_office.dart'),
  );
  if (library == null) {
    throw StateError('package:jet_office cannot be resolved.');
  }
  final Uri root = library.resolve('..');
  final String path = root.resolve('benchmark/src/$script').toFilePath();
  final ProcessResult result = Process.runSync(
    Platform.resolvedExecutable,
    <String>[path, ...args],
    workingDirectory: root.toFilePath(),
    stdoutEncoding: null,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$script exited with ${result.exitCode}: ${result.stderr}',
    );
  }
  final Object? out = result.stdout;
  if (out is! List<int> || out.isEmpty) {
    throw StateError('$script wrote no bytes.');
  }
  return out is Uint8List ? out : Uint8List.fromList(out);
}
