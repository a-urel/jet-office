// Every Dart block of README.md appears here verbatim, inside a function, so
// the README compiles and runs. Keep the two in step.
import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

List<String> formatting() {
  final List<String> lines = <String>[];
  void print(Object? text) => lines.add('$text');

  final NumberFormatter formatter = NumberFormatter();
  final FormattedValue shown = formatter.format(
    FormatDecimal('-1234.5'),
    numberFormat: '#,##0.00;(#,##0.00)',
  );
  print(shown.text); // (1,234.50)

  final NumberFormatter german = NumberFormatter(locale: FormatLocale.deDE);
  print(german.format(46323, numberFormat: 'dddd, d. mmmm yyyy').text);
  // Mittwoch, 28. Oktober 2026
  return lines;
}

void main() {
  test('README example prints what its comments say', () {
    expect(formatting(), <String>['(1,234.50)', 'Mittwoch, 28. Oktober 2026']);
  });

  test('README says an unreadable code shows General with a warning', () {
    final FormattedValue shown = NumberFormatter().format(
      5,
      numberFormat: '0;0;0;0;0',
    );
    expect(shown.text, '5');
    expect(shown.warning, FormatWarning.invalidCode);
  });
}
