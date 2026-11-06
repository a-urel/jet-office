/// Value equality for the model's data, shared by every model class.
///
/// The model carries chart data as it was read, so a list of values may hold
/// `null`, `NaN` or an infinity. Plain `==` makes `NaN` unequal to itself,
/// which would make two copies of the same data unequal; here `NaN` equals
/// `NaN`, and [valueHash] agrees with that.
library;

/// The hash code of every `NaN`.
const int _nanHash = 0x7ff80000;

/// Whether [a] and [b] are the same value, with `NaN` equal to `NaN`.
bool valueEquals(Object? a, Object? b) {
  if (a is double && b is double && a.isNaN && b.isNaN) {
    return true;
  }
  return a == b;
}

/// A hash code consistent with [valueEquals].
int valueHash(Object? value) {
  if (value is double) {
    if (value.isNaN) {
      return _nanHash;
    }
    // 0.0 == -0.0, so they must hash alike.
    if (value == 0) {
      return 0;
    }
  }
  return value.hashCode;
}

/// Whether [a] and [b] hold [valueEquals] elements in the same order.
bool listValueEquals(List<Object?> a, List<Object?> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (!valueEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

/// A hash code of [list] consistent with [listValueEquals].
int listValueHash(List<Object?> list) {
  int hash = list.length;
  for (final Object? element in list) {
    hash = Object.hash(hash, valueHash(element));
  }
  return hash;
}
