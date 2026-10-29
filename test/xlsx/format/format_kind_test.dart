import 'package:jet_office/src/xlsx/format/builtin_formats.dart';
import 'package:jet_office/src/xlsx/format/format_kind.dart';
import 'package:test/test.dart';

void main() {
  test('classifies codes', () {
    const Map<String, FormatKind> table = <String, FormatKind>{
      'General': FormatKind.number,
      '0.00': FormatKind.number,
      '@': FormatKind.number,
      '0.00E+00': FormatKind.number,
      '#,##0 "m"': FormatKind.number,
      '0_m': FormatKind.number,
      'AM/PM': FormatKind.number,
      'yyyy-mm-dd': FormatKind.date,
      'dd/mm/yyyy;@': FormatKind.date,
      '[\$-409]m/d/yyyy;@': FormatKind.date,
      '[\$-F800]dddd, mmmm dd, yyyy': FormatKind.date,
      '[Red]dd.mm.yyyy': FormatKind.date,
      'mm-dd-yy': FormatKind.date,
      'm/d/yy h:mm': FormatKind.date,
      'mmm-yy': FormatKind.date,
      'mmmmm': FormatKind.date,
      'h:mm': FormatKind.time,
      'h:mm AM/PM': FormatKind.time,
      'hh:mm:ss': FormatKind.time,
      'mm:ss': FormatKind.time,
      'mmss.0': FormatKind.time,
      '[h]:mm:ss': FormatKind.time,
      '[mm]:ss': FormatKind.time,
      '[ss]': FormatKind.time,
      '[m]': FormatKind.time,
      'm': FormatKind.date,
      'yyyy-mm-dd;;': FormatKind.date,
      '0.00;0.00;h:mm': FormatKind.number,
      'yyyy-mm-dd;h:mm': FormatKind.number,
      '[>=1]yyyy-mm-dd;h:mm': FormatKind.number,
      '"Date: "yyyy': FormatKind.date,
      '"d"0': FormatKind.number,
      r'\d0': FormatKind.number,
      'yyyy-mm-dd;-0;0;@': FormatKind.number,
      'yyyy-mm-dd;"-"': FormatKind.date,
      'dd.mm.yyyy;;"-"': FormatKind.date,
      '"abc"': FormatKind.number,
      '0;"-"': FormatKind.number,
      '"abc': FormatKind.number,
      '[Red': FormatKind.number,
      'yyyy-mm-dd;-0;0;h:mm': FormatKind.number,
      'General;yyyy': FormatKind.date,
      'B2yyyy-mm-dd': FormatKind.date,
      '[\$-F800]dddd': FormatKind.date,
      'h:mm:ss.00': FormatKind.time,
      '[DBNum1]0': FormatKind.number,
    };
    for (final MapEntry<String, FormatKind> e in table.entries) {
      expect(classifyFormatCode(e.key), e.value, reason: e.key);
    }
  });

  test('every invariant built-in classifies as the spec says', () {
    for (var id = 0; id <= 163; id++) {
      final String? code = builtinNumberFormatCode(id);
      if (code == null) continue;
      final FormatKind expected = switch (id) {
        14 || 15 || 16 || 17 || 22 => FormatKind.date,
        18 || 19 || 20 || 21 || 45 || 46 || 47 => FormatKind.time,
        _ => FormatKind.number,
      };
      expect(classifyFormatCode(code), expected, reason: 'id $id: $code');
    }
  });
}
