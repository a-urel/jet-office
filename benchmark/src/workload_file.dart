/// The workload's file and the worst case's, as the read benchmarks read
/// them.
///
/// New in jet_office. On the VM each file is written by a child process
/// (`write_workload.dart`, `write_worst_case.dart`), so writing it does not
/// lift the memory the reader's process already holds: the VM keeps the
/// writer's freed heap mapped, and the reader would reuse it without its RSS
/// rising. In the browser it is written in the page, where the collector
/// frees the writer's heap when it runs; until then a baseline taken after
/// it includes that garbage. The VM's version imports `dart:io`, so it sits
/// behind a conditional export that the Chrome compile never follows.
library;

export 'workload_file_vm.dart'
    if (dart.library.js_interop) 'workload_file_web.dart';
