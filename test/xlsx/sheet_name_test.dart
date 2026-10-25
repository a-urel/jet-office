import 'package:jet_office/src/xlsx/sheet_name.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

void main() {
  late WarningCollector w;
  late SheetNamer n;

  setUp(() {
    w = WarningCollector();
    n = SheetNamer(w);
  });

  test('a valid name is kept and raises no warning', () {
    expect(n.assign('Customers'), 'Customers');
    expect(w.warnings, isEmpty);
  });

  test('duplicates are made unique, case-insensitively (Quds did not)', () {
    expect(n.assign('Data'), 'Data');
    expect(n.assign('DATA'), 'DATA (2)');
    expect(n.assign('data'), 'data (3)');
  });

  test('Turkish and German case variants clash', () {
    expect(n.assign('Şube'), 'Şube');
    expect(n.assign('ŞUBE'), 'ŞUBE (2)');
    expect(n.assign('liste'), 'liste');
    expect(n.assign('LİSTE'), 'LİSTE (2)');
    expect(n.assign('straße'), 'straße');
    expect(n.assign('STRASSE'), 'STRASSE (2)');
  });

  test('the Kelvin sign clashes with K and k, as in Excel', () {
    // Excel for the web refuses the Kelvin sign (U+212A) as a sheet name
    // when a sheet `K` exists (M2 Excel check, 2026-10-25).
    expect(n.assign('K'), 'K');
    expect(n.assign('\u212A'), '\u212A (2)');
    expect(n.assign('k'), 'k (3)');
    expect(n.assign('\u212Aelvin'), '\u212Aelvin');
    expect(n.assign('KELVIN'), 'KELVIN (2)');
  });

  test('sheetNameKey folds case, dotted and dotless i, sharp s and Kelvin', () {
    expect(sheetNameKey('liste'), sheetNameKey('LİSTE'));
    expect(sheetNameKey('ısı'), sheetNameKey('ISI'));
    expect(sheetNameKey('straße'), sheetNameKey('STRASSE'));
    expect(sheetNameKey('\u212A'), sheetNameKey('k'));
    expect(sheetNameKey('a'), isNot(sheetNameKey('b')));
  });

  test('invalid characters, quotes, length, empty, reserved', () {
    expect(n.assign('a/b:c*d?e[f]g\\h'), 'a_b_c_d_e_f_g_h');
    expect(n.assign("'Quoted'"), 'Quoted');
    expect(n.assign('   '), 'Sheet3');
    expect(n.assign('x' * 40), 'x' * 31);
    expect(n.assign('${'y' * 30}😀'), 'y' * 30);
    expect(n.assign('History'), 'History (2)');
    expect(n.assign('z' * 31), 'z' * 31);
    expect(n.assign('Z' * 31), '${'Z' * 27} (2)');
  });

  test('truncation never leaves half of a surrogate pair', () {
    final String name = n.assign('${'y' * 30}😀');
    expect(name, 'y' * 30);
    expect(name.codeUnits.every((int u) => u < 0xD800 || u > 0xDFFF), isTrue);
  });

  test('a pair that ends exactly at the limit is kept', () {
    final String requested = '${'y' * 29}😀';
    expect(requested.length, 31);
    expect(n.assign(requested), requested);
    expect(w.warnings, isEmpty);
  });

  test('shortening the base for a suffix never splits a pair', () {
    final String requested = '${'y' * 26}😀zz';
    expect(requested.length, 30);
    expect(n.assign(requested), requested);
    expect(n.assign(requested.toUpperCase()), '${'Y' * 26} (2)');
  });

  test('apostrophes only at the ends are removed', () {
    expect(n.assign("it's"), "it's");
    expect(n.assign("''a'b''"), "a'b");
    expect(n.assign("' '"), 'Sheet3');
  });

  test('forbidden XML characters are scrubbed', () {
    expect(n.assign('a\u0001b'), 'ab');
    expect(n.assign('lone\uD800'), 'lone');
    expect(w.warnings.map((XlsxWarning x) => x.code), <XlsxWarningCode>[
      XlsxWarningCode.sheetNameChanged,
      XlsxWarningCode.sheetNameChanged,
    ]);
  });

  test('a name made only of invalid characters becomes underscores', () {
    expect(n.assign('///'), '___');
  });

  test('warnings carry original and final names', () {
    n.assign('a/b');
    expect(w.warnings, hasLength(1));
    final XlsxWarning x = w.warnings.single;
    expect(x.code, XlsxWarningCode.sheetNameChanged);
    expect(x.sheet, 'a_b');
    expect(x.originalName, 'a/b');
    expect(x.count, 1);
  });

  test('a duplicate raises sheetNameDuplicated with the final name', () {
    n.assign('Data');
    n.assign('data');
    expect(w.warnings, hasLength(1));
    expect(w.warnings.single.code, XlsxWarningCode.sheetNameDuplicated);
    expect(w.warnings.single.sheet, 'data (2)');
    expect(w.warnings.single.originalName, 'data');
  });

  test(
    'a name changed and then duplicated gets both warnings, changed first',
    () {
      n.assign('a_b');
      expect(n.assign('A/B'), 'A_B (2)');
      expect(w.warnings.map((XlsxWarning x) => x.code), <XlsxWarningCode>[
        XlsxWarningCode.sheetNameChanged,
        XlsxWarningCode.sheetNameDuplicated,
      ]);
      expect(w.warnings[0].sheet, 'A_B (2)');
      expect(w.warnings[0].originalName, 'A/B');
      expect(w.warnings[1].sheet, 'A_B (2)');
      expect(w.warnings[1].originalName, 'A/B');
    },
  );

  test('Sheet{n} counts names assigned so far', () {
    expect(n.assign(''), 'Sheet1');
    expect(n.assign('B'), 'B');
    expect(n.assign(''), 'Sheet3');
  });

  test('a suffix that would clash is skipped', () {
    expect(n.assign('Data'), 'Data');
    expect(n.assign('Data (2)'), 'Data (2)');
    expect(n.assign('data'), 'data (3)');
  });

  test('names of only apostrophes and spaces fall back to Sheet{n}', () {
    expect(n.assign("' ' '"), 'Sheet1');
    expect(n.assign("'"), 'Sheet2');
    expect(n.assign("''"), 'Sheet3');
  });

  test('apostrophes and spaces are stripped until stable', () {
    expect(n.assign("' ' x"), 'x');
  });

  test('truncation that exposes an apostrophe or space is cleaned', () {
    expect(n.assign("${'x' * 30}'y"), 'x' * 30);
    expect(SheetNamer(w).assign('${'x' * 30} y'), 'x' * 30);
    expect(w.warnings.any((XlsxWarning x) => x.sheet.isEmpty), isFalse);
  });

  test('a base cut for the suffix never leaves a double space', () {
    final String name = '${'a' * 26} x';
    expect(n.assign(name), name);
    expect(n.assign(name), '${'a' * 26} (2)');
  });

  test('a base cut for the suffix drops a trailing apostrophe too', () {
    final String name = "${'b' * 26}'x";
    expect(n.assign(name), name);
    expect(n.assign(name), '${'b' * 26} (2)');
  });
}
