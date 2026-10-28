/// Writes the workload's file to standard output, for the read benchmark.
///
/// New in jet_office. `workload_file_vm.dart` runs it as a child process:
/// `dart run benchmark/src/write_workload.dart <rows>`.
library;

import 'dart:io' show stdout;

import 'package:jet_office/jet_office.dart';

import 'workload.dart';

/// Writes the workload of `args[0]` data rows with [XlsxWriter] and sends
/// the file's bytes to standard output.
Future<void> main(List<String> args) async {
  final XlsxWriter book = XlsxWriter();
  writeWorkload(book.addSheet('Data'), int.parse(args.single), (int _) {});
  stdout.add(book.close().bytes);
  await stdout.flush();
}
