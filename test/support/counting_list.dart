/// Test helper: a growable list that counts the writes of its elements.
library;

import 'dart:collection';

import 'package:test/test.dart';

/// A growable list that counts the writes of its elements: each element
/// added, set or moved (an insert moves the elements after it).
///
/// With a [budget], the write that passes it fails the test at once, so a
/// quadratic or unbounded run fails instead of running for minutes.
final class CountingList<E> extends ListBase<E> {
  /// An empty list, failing the test past [budget] writes when given.
  CountingList({this.budget});

  /// The most writes allowed, or `null` for no limit.
  final int? budget;

  final List<E> _elements = <E>[];

  /// The elements written so far.
  int writes = 0;

  void _write() {
    writes++;
    final int? most = budget;
    if (most != null && writes > most) {
      fail('more than $most elements written');
    }
  }

  @override
  int get length => _elements.length;

  @override
  set length(int value) {
    if (value > _elements.length) {
      throw UnsupportedError('Grows only by add.');
    }
    _elements.length = value;
  }

  @override
  E operator [](int index) => _elements[index];

  @override
  void operator []=(int index, E value) {
    _write();
    _elements[index] = value;
  }

  @override
  void add(E element) {
    _write();
    _elements.add(element);
  }
}
