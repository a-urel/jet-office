/// The full axis oracle's case list (version 2), for tests that run in a
/// browser as well, where no file can be read. `test/axis_oracle_test.dart`
/// requires the committed `test/fixtures/owner/axis_full/cases.json` to hold
/// exactly this.
library;

import 'axis_cases.dart';

/// The six data sets of groups L and B, by number. Each has, by the rule of
/// `autoValueScale` at `maxIntervals` 10, as many intervals as its number
/// (`test/tool/axis_oracle_test.dart` pins that).
const Map<String, List<String>> axisFullLengthSets = <String, List<String>>{
  '05': <String>['12', '23'],
  '06': <String>['14', '27'],
  '07': <String>['16', '32'],
  '08': <String>['19', '37'],
  '09': <String>['21', '42'],
  '10': <String>['23', '46'],
};

/// The heights of group L at font 10, in points.
const List<int> axisFullLengthHeights = <int>[
  60,
  80,
  100,
  120,
  140,
  150,
  160,
  180,
  200,
  225,
  250,
  275,
];

/// The widths of group B at font 10, in points.
const List<int> axisFullBarWidths = <int>[
  80,
  100,
  120,
  150,
  180,
  220,
  260,
  300,
  400,
  600,
];

/// The twelve values of group C.
const List<String> axisFullLabelValues = <String>[
  '3',
  '7',
  '4',
  '9',
  '6',
  '8',
  '5',
  '10',
  '7',
  '11',
  '6',
  '12',
];

/// The category labels of group C: twelve of 3, of 12 and of 30 characters.
final List<List<String>> axisFullLabels = <List<String>>[
  <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ],
  <String>[for (int i = 1; i <= 12; i++) 'Product A-${'$i'.padLeft(2, '0')}'],
  <String>[
    for (int i = 1; i <= 12; i++)
      'Product line of the regions ${'$i'.padLeft(2, '0')}',
  ],
];

Map<String, Object?> _case(
  String group,
  int number,
  String kind,
  String grouping,
  List<List<String>> series, {
  List<String>? categories,
  int width = 360,
  int height = 300,
  int font = 10,
  num? fixedMin,
  num? fixedMax,
  num? fixedMajor,
}) => <String, Object?>{
  'id': '$group${'$number'.padLeft(2, '0')}-w$width-h$height-f$font',
  'kind': kind,
  'grouping': grouping,
  'series': series,
  'categories': ?categories,
  'width': width,
  'height': height,
  'font': font,
  'fixedMin': ?fixedMin,
  'fixedMax': ?fixedMax,
  'fixedMajor': ?fixedMajor,
};

List<Map<String, Object?>> _lengthGroup() => <Map<String, Object?>>[
  for (final MapEntry<String, List<String>> set in axisFullLengthSets.entries)
    for (final int height in <int>[
      ...axisFullLengthHeights,
      if (set.key == '10') ...<int>[400, 800],
    ])
      _case('L', int.parse(set.key), 'column', 'clustered', <List<String>>[
        set.value,
      ], height: height),
  for (final MapEntry<String, List<String>> set in axisFullLengthSets.entries)
    if (set.key != '05')
      for (final int height in <int>[100, 150])
        for (final int font in <int>[8, 18])
          _case(
            'L',
            int.parse(set.key),
            'column',
            'clustered',
            <List<String>>[set.value],
            height: height,
            font: font,
          ),
];

List<Map<String, Object?>> _widthGroup() => <Map<String, Object?>>[
  for (final String set in <String>['05', '06'])
    for (final int height in <int>[150, 300])
      for (final int width in <int>[120, 180, 240, 480, 720])
        _case(
          'W',
          int.parse(set),
          'column',
          'clustered',
          <List<String>>[axisCaseSets['d$set']!],
          width: width,
          height: height,
        ),
];

List<Map<String, Object?>> _barGroup() => <Map<String, Object?>>[
  for (final MapEntry<String, List<String>> set in axisFullLengthSets.entries)
    for (final int width in axisFullBarWidths)
      _case('B', int.parse(set.key), 'bar', 'clustered', <List<String>>[
        set.value,
      ], width: width),
  for (final MapEntry<String, List<String>> set in axisFullLengthSets.entries)
    if (set.key != '05')
      for (final int width in <int>[150, 300])
        for (final int font in <int>[8, 18])
          _case(
            'B',
            int.parse(set.key),
            'bar',
            'clustered',
            <List<String>>[set.value],
            width: width,
            font: font,
          ),
];

List<Map<String, Object?>> _minMaxGroup() {
  final List<(String, List<List<String>>)> charts =
      <(String, List<List<String>>)>[
        for (final List<String> values in <List<String>>[
          <String>['83', '100'],
          <String>['83.3', '100'],
          <String>['83.4', '100'],
          <String>['84', '100'],
          <String>['-100', '-84'],
          <String>['-100', '-83'],
          <String>['5'],
          <String>['-3'],
          <String>['7', '7'],
          <String>['-7', '-7'],
          <String>['1', '', '3'],
          <String>['0.0001', '1000000'],
          <String>['-1', '1'],
          <String>['-1000', '1'],
        ])
          ('column', <List<String>>[values]),
        (
          'column',
          <List<String>>[
            <String>['1', '2'],
            <String>['10', '20'],
          ],
        ),
        for (final List<String> values in <List<String>>[
          <String>['97', '98', '99'],
          <String>['-5', '3'],
        ])
          for (final String kind in <String>['line', 'area'])
            (kind, <List<String>>[values]),
      ];
  return <Map<String, Object?>>[
    for (int i = 0; i < charts.length; i++)
      _case('M', i + 1, charts[i].$1, 'clustered', charts[i].$2),
  ];
}

List<Map<String, Object?>> _groupingGroup() {
  const List<List<String>> plain = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
  ];
  const List<List<String>> negative = <List<String>>[
    <String>['3', '-2', '4'],
    <String>['-1', '-3', '2'],
  ];
  final List<(String, List<List<String>>)> sets =
      <(String, List<List<String>>)>[
        ('stacked', plain),
        ('stacked', negative),
        ('percentStacked', plain),
        ('percentStacked', negative),
      ];
  int n = 0;
  return <Map<String, Object?>>[
    for (final (String grouping, List<List<String>> series) in sets)
      for (final String kind in <String>['column', 'bar', 'area'])
        _case('G', ++n, kind, grouping, series),
  ];
}

List<Map<String, Object?>> _fixedGroup() {
  const List<String> high = <String>['97', '98', '99'];
  const List<String> low = <String>['1', '2', '3'];
  return <Map<String, Object?>>[
    _case('F', 1, 'column', 'clustered', <List<String>>[high], fixedMin: 0),
    _case('F', 2, 'column', 'clustered', <List<String>>[high], fixedMax: 200),
    _case('F', 3, 'column', 'clustered', <List<String>>[low], fixedMajor: 0.25),
    _case('F', 4, 'column', 'clustered', <List<String>>[low], fixedMax: 2),
    _case(
      'F',
      5,
      'column',
      'clustered',
      <List<String>>[low],
      fixedMin: 5,
      fixedMax: 5,
    ),
  ];
}

List<Map<String, Object?>> _labelGroup() => <Map<String, Object?>>[
  for (int i = 0; i < axisFullLabels.length; i++)
    for (final int width in <int>[180, 360, 720])
      _case(
        'C',
        i + 1,
        'column',
        'clustered',
        <List<String>>[axisFullLabelValues],
        categories: axisFullLabels[i],
        width: width,
      ),
];

/// The case list as `axis_full/cases.json` holds it, decoded.
Map<String, Object?> axisFullCasesDocument() => <String, Object?>{
  'version': 2,
  'cases': <Object?>[
    ..._lengthGroup(),
    ..._widthGroup(),
    ..._barGroup(),
    ..._minMaxGroup(),
    ..._groupingGroup(),
    ..._fixedGroup(),
    ..._labelGroup(),
  ],
};
