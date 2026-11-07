/// The axis oracle's case list, for tests that run in a browser as well, where
/// no file can be read. `test/axis_oracle_test.dart` requires the committed
/// `cases.json` to hold exactly this.
library;

/// The twelve data sets by id, as decimal text.
const Map<String, List<String>> axisCaseSets = <String, List<String>>{
  'd01': <String>['1', '2', '3'],
  'd02': <String>['0.001', '0.002'],
  'd03': <String>['97', '98', '99'],
  'd04': <String>['1000', '1000', '1000'],
  'd05': <String>['0', '0', '0'],
  'd06': <String>['-5', '3'],
  'd07': <String>['-100', '-90'],
  'd08': <String>['1234567', '2345678'],
  'd09': <String>['0.5', '120'],
  'd10': <String>['95', '100'],
  'd11': <String>['1E-7', '3E-7'],
  'd12': <String>['1000000000', '5000000000'],
};

/// The five chart sizes, as height and font in points.
const List<(int, int)> axisCaseSizes = <(int, int)>[
  (150, 10),
  (300, 10),
  (600, 10),
  (300, 8),
  (300, 18),
];

/// The case list as `cases.json` holds it, decoded.
Map<String, Object?> axisCasesDocument() => <String, Object?>{
  'version': 1,
  'chartWidth': 360,
  'sets': <Object?>[
    for (final MapEntry<String, List<String>> set in axisCaseSets.entries)
      <String, Object?>{'id': set.key, 'values': set.value},
  ],
  'sizes': <Object?>[
    for (final (int height, int font) in axisCaseSizes)
      <String, Object?>{'height': height, 'font': font},
  ],
};
