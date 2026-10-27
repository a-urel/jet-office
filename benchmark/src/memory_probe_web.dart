/// The Chrome memory probe: the used JavaScript heap.
///
/// New in jet_office. `performance.memory` is a Chrome extension. It holds
/// exact figures only when Chrome starts with `--enable-precise-memory-info`
/// (see `dart_test.yaml`); where it is missing the probe reads `null`.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'memory_probe.dart' show MemoryProbe;

/// Creates the probe of this platform.
MemoryProbe probe() => _WebProbe();

final class _WebProbe implements MemoryProbe {
  @override
  int? sample() {
    final JSAny? performance = globalContext['performance'];
    if (performance == null || !performance.isA<JSObject>()) return null;
    final JSAny? memory = (performance as JSObject)['memory'];
    if (memory == null || !memory.isA<JSObject>()) return null;
    final JSAny? used = (memory as JSObject)['usedJSHeapSize'];
    if (used == null || !used.isA<JSNumber>()) return null;
    return (used as JSNumber).toDartInt;
  }

  @override
  String get unit => 'peak JS heap';
}
