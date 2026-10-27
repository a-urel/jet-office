/// The VM memory probe: the process's peak resident set size.
///
/// New in jet_office.
library;

import 'dart:io' show ProcessInfo;

import 'memory_probe.dart' show MemoryProbe;

/// Creates the probe of this platform.
MemoryProbe probe() => _VmProbe();

final class _VmProbe implements MemoryProbe {
  @override
  int? sample() => ProcessInfo.maxRss;

  @override
  String get unit => 'peak RSS';
}
