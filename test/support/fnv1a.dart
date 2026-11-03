/// Test helper: the FNV-1a hash the part-contents golden tests compare.
///
/// Not ported from Quds; written for jet_office.
library;

/// FNV-1a (32 bit) over [bytes].
///
/// Exact on the web as well as on the VM, so a constant computed on one leg
/// matches the other.
int fnv1a(List<int> bytes) {
  int hash = 0x811c9dc5;
  for (final int b in bytes) {
    // hash * 0x01000193 = hash * 0x193 + (hash << 24), kept below 2^53 so the
    // web computes it exactly.
    final int x = hash ^ b;
    hash = (x * 0x193 + ((x << 24) & 0xffffffff)) & 0xffffffff;
  }
  return hash;
}
