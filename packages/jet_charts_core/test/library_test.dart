// The library loads on every platform. It exports nothing yet; this test
// keeps the Chrome leg of the gate from running no test at all (`dart test`
// exits 79 then), until the model's tests arrive.
// ignore: unused_import
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

void main() {
  test('the library imports', () {
    expect(true, isTrue);
  });
}
