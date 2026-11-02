import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart' show Fixture;
import '../../fixtures/m1_fixtures.dart';

/// Rows of cell values for each sheet, in tab order, as the writer fixture
/// writes them.
typedef _Sheets = List<(String, List<List<Object?>>)>;

/// The M1 fixtures that use only W1 value types, rebuilt with the model.
///
/// The others wait for their milestone: `m1_values` and `m1_dates` style a
/// cell with `XlsxCell` (W2), `m1_sheets` places tabs and picks the active
/// one (W5 sheet moves; the active tab is a W2 view setting), and
/// `m1_properties` sets document properties (W3).
final Map<String, _Sheets> _rebuilt = <String, _Sheets>{
  'm1_dirty_text': <(String, List<List<Object?>>)>[
    (
      'Text',
      <List<Object?>>[
        <Object?>['a\u0000b\u0008c\u000Bd'],
        <Object?>['x\uD800y'],
        <Object?>['p\uDC00q'],
        <Object?>['a' * 40000],
        <Object?>['${'a' * 32766}\u{1F600}'],
        <Object?>['  padded  '],
        <Object?>['Şube Müdürü'],
        <Object?>['Straße'],
        <Object?>['\u{1F600} emoji \u{1F468}‍\u{1F469}'],
        <Object?>['_x0041_'],
        <Object?>['a_x00e9_b'],
      ],
    ),
  ],
  'm1_formulas': <(String, List<List<Object?>>)>[
    (
      'Formulas',
      <List<Object?>>[
        <Object?>[
          const XlsxFormula('SUM(1,1)', cached: 2),
          const XlsxFormula('CONCATENATE("hel","lo")', cached: 'hello'),
          const XlsxFormula('AND(TRUE,TRUE)', cached: true),
          const XlsxFormula('1+2'),
        ],
      ],
    ),
  ],
  'm1_empty': <(String, List<List<Object?>>)>[
    ('Empty', <List<Object?>>[]),
    (
      'Nulls',
      <List<Object?>>[
        <Object?>[null, null],
        <Object?>['x'],
      ],
    ),
    (
      'Blank',
      <List<Object?>>[
        <Object?>['a'],
        <Object?>[],
        <Object?>[null, 'b'],
      ],
    ),
    (
      'EmptyString',
      <List<Object?>>[
        <Object?>[''],
      ],
    ),
  ],
};

/// Differences the model may have from the writer, each with its reason.
/// Empty: for these fixtures the two write paths agree part by part.
const Set<String> _allowedParts = <String>{};

/// Builds [sheets] with the model.
XlsxResult _build(_Sheets sheets) {
  final XlsxWorkbook book = XlsxWorkbook();
  for (final (String name, List<List<Object?>> rows) in sheets) {
    final XlsxSheet sheet = book.addSheet(name);
    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        sheet.setCell(r, c, rows[r][c]);
      }
    }
  }
  return book.save();
}

Map<XlsxWarningCode, int> _totals(
  List<XlsxWarning> warnings,
) => <XlsxWarningCode, int>{
  for (final XlsxWarningCode code in warnings.map((XlsxWarning w) => w.code))
    code: warnings
        .where((XlsxWarning w) => w.code == code)
        .fold(0, (int sum, XlsxWarning w) => sum + w.count),
};

void main() {
  group('value fixtures built with the model equal the writer\'s', () {
    for (final Fixture f in m1Fixtures()) {
      final _Sheets? sheets = _rebuilt[f.name];
      if (sheets == null) continue;
      test(f.name, () {
        final Uint8List writer = f.build();
        final XlsxResult model = _build(sheets);
        expect(
          comparePackages(
            writer,
            model.bytes,
            ignoreParts: _allowedParts,
            // The model writes each row's spans; the writer writes none.
            ignoreBookkeeping: true,
          ),
          isEmpty,
        );
        expect(_totals(model.warnings), f.expectedWarnings);
      });
    }
  });

  test('every rebuilt fixture exists', () {
    final Set<String> names = <String>{
      for (final Fixture f in m1Fixtures()) f.name,
    };
    expect(names, containsAll(_rebuilt.keys));
  });
}
