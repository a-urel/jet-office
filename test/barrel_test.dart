// Runs on the VM and in Chrome: the barrel library loads on both, so the
// Chrome leg of the quality gate has a test to run until the engine arrives.
// ignore: unused_import
import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

void main() {
  test('the barrel library can be imported', () {
    expect(true, isTrue);
  });
}
