/// The VM memory probes: the process's peak and current resident set size.
///
/// New in jet_office.
library;

import 'dart:io' show ProcessInfo;

import 'memory_probe.dart' show MemoryProbe;

/// Creates the probe of this platform: the peak resident set size.
MemoryProbe probe() => _VmProbe();

/// Creates the probe of this platform that reads the memory in use now: the
/// current resident set size, which falls when memory is given back.
///
/// The read benchmark samples it against a baseline, because the peak the
/// [probe] reads is already lifted by writing the input in the same process.
MemoryProbe currentProbe() => _VmCurrentProbe();

final class _VmProbe implements MemoryProbe {
  @override
  int? sample() => ProcessInfo.maxRss;

  @override
  String get unit => 'peak RSS';
}

final class _VmCurrentProbe implements MemoryProbe {
  @override
  int? sample() => ProcessInfo.currentRss;

  @override
  String get unit => 'RSS';
}
