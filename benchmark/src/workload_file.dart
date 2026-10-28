/// The workload's file, as the read benchmark reads it.
///
/// New in jet_office. On the VM the file is written by a child process
/// (`write_workload.dart`), so writing it does not lift the memory the
/// reader's process already holds: the VM keeps the writer's freed heap
/// mapped, and the reader would reuse it without its RSS rising. In the
/// browser it is written in the page, where the collector frees the writer's
/// heap. The VM's version imports `dart:io`, so it sits behind a conditional
/// export that the Chrome compile never follows.
library;

export 'workload_file_vm.dart'
    if (dart.library.js_interop) 'workload_file_web.dart';
