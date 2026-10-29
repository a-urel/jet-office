/// Memory probes of the benchmark, one per platform.
///
/// New in jet_office. `probe()` reads the peak the writers report;
/// `currentProbe()` reads the memory in use now, which the read
/// benchmark samples against a baseline. The VM probe imports `dart:io`,
/// so it sits behind a conditional export that the Chrome compile never
/// follows.
library;

export 'memory_probe_vm.dart'
    if (dart.library.js_interop) 'memory_probe_web.dart';

/// Reads how much memory the process uses right now.
abstract interface class MemoryProbe {
  /// The current reading in [unit], or `null` when the platform gives none.
  int? sample();

  /// What [sample] measures, for example `peak RSS`.
  String get unit;
}
