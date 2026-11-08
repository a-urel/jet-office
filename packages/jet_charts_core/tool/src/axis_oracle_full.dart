part of 'axis_oracle.dart';

// The full axis oracle: case list version 2 (test/fixtures/owner/axis_full/,
// README there), its workbook, its CSV and its analysis.

/// The first line of a version 2 results CSV.
const String axisFullCsvHeader =
    'case,width,height,font,min,max,major,'
    'plotLeft,plotTop,plotWidth,plotHeight,labelSpacing';

/// The full oracle's workbook file name.
const String axisFullWorkbookName = 'axis_oracle_full.xlsx';

/// The stem of the full oracle's CSV names, `axis_oracle_full.<region>.csv`.
const String axisFullCsvStem = 'axis_oracle_full';

/// The chart kinds of version 2.
const List<String> axisFullKinds = <String>['column', 'bar', 'line', 'area'];

/// The groupings of version 2.
const List<String> axisFullGroupings = <String>[
  'clustered',
  'stacked',
  'percentStacked',
];

/// The groups of version 2 by letter, with the name of the sheet that holds
/// their charts.
const Map<String, String> axisFullGroupSheets = <String, String>{
  'L': 'length',
  'W': 'width',
  'B': 'bar',
  'M': 'minmax',
  'G': 'grouping',
  'F': 'fixed',
  'C': 'labels',
};

/// How far, in points, a plot box may reach outside the chart.
const double _plotTolerance = 1;

/// The series fills and lines, in order.
const List<String> _seriesColors = <String>['156082', 'E97132'];

final RegExp _fullId = RegExp(r'^([LWBMGFC])(\d\d)-w(\d+)-h(\d+)-f(\d+)$');
final RegExp _count = RegExp(r'^\d+$');

const Set<String> _caseKeys = <String>{
  'id',
  'kind',
  'grouping',
  'series',
  'categories',
  'width',
  'height',
  'font',
  'fixedMin',
  'fixedMax',
  'fixedMajor',
};

/// One chart of the full oracle.
final class AxisFullCase {
  /// Creates a case.
  const AxisFullCase({
    required this.id,
    required this.kind,
    required this.grouping,
    required this.series,
    required this.categories,
    required this.width,
    required this.height,
    required this.font,
    this.fixedMin,
    this.fixedMax,
    this.fixedMajor,
  });

  /// The case id and the chart's name, such as `L05-w360-h60-f10`.
  final String id;

  /// One of [axisFullKinds].
  final String kind;

  /// One of [axisFullGroupings].
  final String grouping;

  /// The series' values as text, written unchanged to the sheet and the
  /// chart's cache; an empty text is a blank.
  final List<List<String>> series;

  /// The category labels, or `null` for none.
  final List<String>? categories;

  /// The chart's width in points.
  final int width;

  /// The chart's height in points.
  final int height;

  /// The chart's font size in points.
  final int font;

  /// The value axis' fixed minimum, or `null` for automatic.
  final double? fixedMin;

  /// The value axis' fixed maximum, or `null` for automatic.
  final double? fixedMax;

  /// The value axis' fixed major unit, or `null` for automatic.
  final double? fixedMajor;

  /// The group's letter, the first of [id].
  String get group => id.substring(0, 1);

  /// The number within the group, such as `05`.
  String get number => id.substring(1, 3);

  /// Whether the value axis runs across, as a bar chart's does, so that its
  /// length is the plot area's width; else it is the height.
  bool get valueAxisIsHorizontal => kind == 'bar';
}

/// The parsed version 2 case list.
final class AxisFullCases {
  /// Creates a case list.
  const AxisFullCases(this.cases);

  /// The cases in file order.
  final List<AxisFullCase> cases;
}

/// Parses the version 2 case list [text]. Throws a [FormatException] on
/// anything but the format of the README in `axis_full/`.
AxisFullCases parseAxisFullCases(String text) {
  final Object? root = jsonDecode(text);
  if (root is! Map<String, Object?> || root['version'] != 2) {
    throw const FormatException('expected an object of version 2');
  }
  final Object? rawCases = root['cases'];
  if (rawCases is! List<Object?> || root.length != 2) {
    throw const FormatException('expected version and cases');
  }
  final Set<String> ids = <String>{};
  final List<AxisFullCase> cases = <AxisFullCase>[];
  for (final Object? raw in rawCases) {
    if (raw is! Map<String, Object?> || !_caseKeys.containsAll(raw.keys)) {
      throw const FormatException('cases: expected objects of known keys');
    }
    final Object? id = raw['id'];
    final RegExpMatch? match = id is String ? _fullId.firstMatch(id) : null;
    if (id is! String || match == null || !ids.add(id)) {
      throw FormatException('cases: bad or repeated id $id');
    }
    int size(String key, int group) {
      final Object? value = raw[key];
      if (value is! int || value <= 0 || '$value' != match.group(group)) {
        throw FormatException('$id: $key does not match the id');
      }
      return value;
    }

    final Object? kind = raw['kind'];
    final Object? grouping = raw['grouping'];
    if (!axisFullKinds.contains(kind) ||
        !axisFullGroupings.contains(grouping)) {
      throw FormatException('$id: unknown kind or grouping');
    }
    final Object? rawSeries = raw['series'];
    if (rawSeries is! List<Object?> ||
        rawSeries.isEmpty ||
        rawSeries.length > _seriesColors.length) {
      throw FormatException('$id: expected one or two series');
    }
    final List<List<String>> series = <List<String>>[];
    for (final Object? values in rawSeries) {
      if (values is! List<Object?> ||
          values.isEmpty ||
          values.any(
            (Object? v) =>
                v is! String || (v.isNotEmpty && !_number.hasMatch(v)),
          )) {
        throw FormatException('$id: expected numbers as text, or ""');
      }
      series.add(values.cast<String>());
    }
    final int n = series.first.length;
    if (series.any((List<String> s) => s.length != n) ||
        series.every((List<String> s) => s.every((String v) => v.isEmpty))) {
      throw FormatException('$id: series of one length with a number');
    }
    final Object? rawCategories = raw['categories'];
    if (rawCategories != null &&
        (rawCategories is! List<Object?> ||
            rawCategories.length != n ||
            rawCategories.any((Object? c) => c is! String))) {
      throw FormatException('$id: expected a label per value');
    }
    double? fixed(String key) {
      final Object? value = raw[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite) {
        throw FormatException('$id: $key is not a number');
      }
      return value.toDouble();
    }

    cases.add(
      AxisFullCase(
        id: id,
        kind: kind! as String,
        grouping: grouping! as String,
        series: series,
        categories: (rawCategories as List<Object?>?)?.cast<String>(),
        width: size('width', 3),
        height: size('height', 4),
        font: size('font', 5),
        fixedMin: fixed('fixedMin'),
        fixedMax: fixed('fixedMax'),
        fixedMajor: fixed('fixedMajor'),
      ),
    );
  }
  return AxisFullCases(cases);
}

/// Writes `axis_oracle_full.xlsx` for [cases]: a sheet per group
/// ([axisFullGroupSheets]), each case's data in a block of rows (labels in
/// column A when it has them, a series per column from B, a blank as an
/// empty cell), and a chart per case on it, named by the case id. Only a
/// case's fixed values fix the scale. The same [cases] give the same bytes.
Uint8List buildAxisFullWorkbook(AxisFullCases cases) {
  final List<String> groups = <String>[
    for (final String group in axisFullGroupSheets.keys)
      if (cases.cases.any((AxisFullCase c) => c.group == group)) group,
  ];
  final Archive archive = Archive();
  void add(String name, String text) =>
      archive.add(ArchiveFile.bytes(name, utf8.encode(text)));

  add(
    '[Content_Types].xml',
    _contentTypesFor(groups.length, cases.cases.length),
  );
  add(
    '_rels/.rels',
    _rels(<String>[_rel(1, 'officeDocument', 'xl/workbook.xml')]),
  );
  add(
    'xl/workbook.xml',
    _workbookXmlFor(<String>[
      for (final String g in groups) axisFullGroupSheets[g]!,
    ]),
  );
  add(
    'xl/_rels/workbook.xml.rels',
    _rels(<String>[
      for (int i = 1; i <= groups.length; i++)
        _rel(i, 'worksheet', 'worksheets/sheet$i.xml'),
    ]),
  );
  int chart = 0;
  for (int i = 1; i <= groups.length; i++) {
    final String sheet = axisFullGroupSheets[groups[i - 1]]!;
    final List<AxisFullCase> charts = <AxisFullCase>[
      for (final AxisFullCase kase in cases.cases)
        if (kase.group == groups[i - 1]) kase,
    ];
    final List<int> firstRows = <int>[];
    int row = 1;
    for (final AxisFullCase kase in charts) {
      firstRows.add(row);
      row += kase.series.first.length;
    }
    add('xl/worksheets/sheet$i.xml', _fullSheetXml(charts, firstRows));
    add(
      'xl/worksheets/_rels/sheet$i.xml.rels',
      _rels(<String>[_rel(1, 'drawing', '../drawings/drawing$i.xml')]),
    );
    add(
      'xl/drawings/drawing$i.xml',
      _anchorsXml(<(String, int, int)>[
        for (final AxisFullCase kase in charts)
          (kase.id, kase.width, kase.height),
      ]),
    );
    add(
      'xl/drawings/_rels/drawing$i.xml.rels',
      _rels(<String>[
        for (int n = 1; n <= charts.length; n++)
          _rel(n, 'chart', '../charts/chart${chart + n}.xml'),
      ]),
    );
    for (int k = 0; k < charts.length; k++) {
      add(
        'xl/charts/chart${++chart}.xml',
        _fullChartXml(charts[k], sheet, firstRows[k]),
      );
    }
  }
  return Uint8List.fromList(
    ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2020)),
  );
}

String _column(int index) => String.fromCharCode('A'.codeUnitAt(0) + index);

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// [value] as the shortest text: whole numbers without a decimal point.
String _numText(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? '${value.toInt()}'
    : '$value';

String _fullSheetXml(List<AxisFullCase> charts, List<int> firstRows) {
  final StringBuffer out = StringBuffer(
    '$_xmlDecl<worksheet xmlns="$_mainNs" xmlns:r="$_relNs"><sheetData>',
  );
  for (int k = 0; k < charts.length; k++) {
    final AxisFullCase kase = charts[k];
    for (int i = 0; i < kase.series.first.length; i++) {
      final int r = firstRows[k] + i;
      final List<String> cells = <String>[
        if (kase.categories != null)
          '<c r="A$r" t="inlineStr"><is><t>${_escape(kase.categories![i])}</t></is></c>',
        for (int s = 0; s < kase.series.length; s++)
          if (kase.series[s][i].isNotEmpty)
            '<c r="${_column(s + 1)}$r"><v>${kase.series[s][i]}</v></c>',
      ];
      if (cells.isNotEmpty) out.write('<row r="$r">${cells.join()}</row>');
    }
  }
  out.write('</sheetData><drawing r:id="rId1"/></worksheet>');
  return out.toString();
}

String _fullChartXml(AxisFullCase kase, String sheetName, int firstRow) {
  final int n = kase.series.first.length;
  final int lastRow = firstRow + n - 1;
  final String sheet = "'$sheetName'";
  final bool bar = kase.kind == 'column' || kase.kind == 'bar';
  final bool horizontal = kase.kind == 'bar';
  final String grouping = !bar && kase.grouping == 'clustered'
      ? 'standard'
      : kase.grouping;
  String cache(List<String> values) => <String>[
    '<c:ptCount val="$n"/>',
    for (int i = 0; i < n; i++)
      if (values[i].isNotEmpty)
        '<c:pt idx="$i"><c:v>${_escape(values[i])}</c:v></c:pt>',
  ].join();
  final String cat = kase.categories == null
      ? ''
      : '<c:cat><c:strRef><c:f>$sheet!\$A\$$firstRow:\$A\$$lastRow</c:f>'
            '<c:strCache>${cache(kase.categories!)}</c:strCache></c:strRef></c:cat>';
  final StringBuffer sers = StringBuffer();
  for (int s = 0; s < kase.series.length; s++) {
    final String color = _seriesColors[s];
    final String column = _column(s + 1);
    final String val =
        '<c:val><c:numRef><c:f>$sheet!\$$column\$$firstRow:\$$column\$$lastRow</c:f>'
        '<c:numCache><c:formatCode>General</c:formatCode>'
        '${cache(kase.series[s])}</c:numCache></c:numRef></c:val>';
    final String fill =
        '<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill></c:spPr>';
    sers.write('<c:ser><c:idx val="$s"/><c:order val="$s"/>');
    sers.write(switch (kase.kind) {
      'line' =>
        '<c:spPr><a:ln w="28575" cap="rnd"><a:solidFill>'
            '<a:srgbClr val="$color"/></a:solidFill><a:round/></a:ln></c:spPr>'
            '<c:marker><c:symbol val="none"/></c:marker>$cat$val'
            '<c:smooth val="0"/>',
      'area' => '$fill$cat$val',
      _ => '$fill<c:invertIfNegative val="0"/>$cat$val',
    });
    sers.write('</c:ser>');
  }
  const String axIds = '<c:axId val="111111111"/><c:axId val="222222222"/>';
  final String plot = switch (kase.kind) {
    'line' =>
      '<c:lineChart><c:grouping val="$grouping"/><c:varyColors val="0"/>'
          '$sers<c:marker val="1"/>$axIds</c:lineChart>',
    'area' =>
      '<c:areaChart><c:grouping val="$grouping"/><c:varyColors val="0"/>'
          '$sers$axIds</c:areaChart>',
    _ =>
      '<c:barChart><c:barDir val="${horizontal ? 'bar' : 'col'}"/>'
          '<c:grouping val="$grouping"/><c:varyColors val="0"/>$sers'
          '${kase.grouping == 'clustered' ? '' : '<c:overlap val="100"/>'}'
          '$axIds</c:barChart>',
  };
  final String fixedMax = kase.fixedMax == null
      ? ''
      : '<c:max val="${_numText(kase.fixedMax!)}"/>';
  final String fixedMin = kase.fixedMin == null
      ? ''
      : '<c:min val="${_numText(kase.fixedMin!)}"/>';
  final String fixedMajor = kase.fixedMajor == null
      ? ''
      : '<c:majorUnit val="${_numText(kase.fixedMajor!)}"/>';
  final String valueFormat = kase.grouping == 'percentStacked'
      ? '<c:numFmt formatCode="0%" sourceLinked="0"/>'
      : '<c:numFmt formatCode="General" sourceLinked="1"/>';
  return '$_xmlDecl<c:chartSpace xmlns:c="$_chartNs" xmlns:a="$_drawingNs" xmlns:r="$_relNs">'
      '<c:roundedCorners val="0"/>'
      '<c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:layout/>$plot'
      '<c:catAx><c:axId val="111111111"/>'
      '<c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
      '<c:axPos val="${horizontal ? 'l' : 'b'}"/>'
      '<c:numFmt formatCode="General" sourceLinked="1"/>'
      '<c:majorTickMark val="out"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/><c:crossAx val="222222222"/>'
      '<c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/>'
      '<c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
      '<c:valAx><c:axId val="222222222"/>'
      '<c:scaling><c:orientation val="minMax"/>$fixedMax$fixedMin</c:scaling>'
      '<c:delete val="0"/><c:axPos val="${horizontal ? 'b' : 'l'}"/>'
      '<c:majorGridlines/>$valueFormat'
      '<c:majorTickMark val="out"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/><c:crossAx val="111111111"/>'
      '<c:crosses val="autoZero"/>'
      '<c:crossBetween val="${kase.kind == 'area' ? 'midCat' : 'between'}"/>'
      '$fixedMajor</c:valAx>'
      '</c:plotArea><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>'
      '<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr>'
      '<a:defRPr sz="${kase.font * 100}"><a:latin typeface="Aptos Narrow"/></a:defRPr>'
      '</a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr>'
      '</c:chartSpace>';
}

/// One row of a version 2 results CSV: what Excel reported for a chart.
final class AxisFullRow {
  /// Creates a row.
  const AxisFullRow({
    required this.id,
    required this.width,
    required this.height,
    required this.font,
    required this.min,
    required this.max,
    required this.major,
    required this.plotLeft,
    required this.plotTop,
    required this.plotWidth,
    required this.plotHeight,
    required this.labelSpacing,
  });

  /// The case id.
  final String id;

  /// The chart object's width in points.
  final double width;

  /// The chart object's height in points.
  final double height;

  /// The font size of the value axis' tick labels.
  final double font;

  /// The value axis' minimum.
  final double min;

  /// The value axis' maximum.
  final double max;

  /// The value axis' major unit.
  final double major;

  /// The plot area's inside left, from the chart's edge, in points.
  final double plotLeft;

  /// The plot area's inside top, from the chart's edge, in points.
  final double plotTop;

  /// The plot area's inside width in points.
  final double plotWidth;

  /// The plot area's inside height in points.
  final double plotHeight;

  /// The category axis' tick label spacing, or `null` where Excel gave none.
  final int? labelSpacing;
}

/// A read version 2 results CSV.
final class AxisFullCsv {
  /// Creates a read CSV.
  const AxisFullCsv(this.rows, this.problems);

  /// The rows that read, in file order.
  final List<AxisFullRow> rows;

  /// What is wrong, one line each; empty for a usable CSV.
  final List<String> problems;
}

/// Reads the version 2 results CSV [text] of [cases].
///
/// A problem is what [readAxisCsv] finds (a wrong header, a case unknown,
/// repeated or missing, a field that is no number, a maximum not above the
/// minimum, a major unit not above zero, a height more than a point from the
/// case's, a font not the case's), and also a line that is not twelve fields,
/// a width more than a point from the case's, a plot field that is no number,
/// a plot box of negative size or reaching more than a point outside the
/// chart Excel reports, and a `labelSpacing` that is neither empty nor a
/// positive whole number, or is empty on a case with category labels. A
/// maximum equal to the minimum is accepted only where the case fixes both
/// to one value. A row has at most one problem.
AxisFullCsv readAxisFullCsv(AxisFullCases cases, String text) {
  final List<String> lines = <String>[
    for (final String line
        in text.replaceFirst('﻿', '').split(RegExp(r'\r\n|\r|\n')))
      if (line.isNotEmpty) line,
  ];
  if (lines.isEmpty || lines.first != axisFullCsvHeader) {
    return const AxisFullCsv(<AxisFullRow>[], <String>[
      'the header is not $axisFullCsvHeader',
    ]);
  }
  final Map<String, AxisFullCase> byId = <String, AxisFullCase>{
    for (final AxisFullCase kase in cases.cases) kase.id: kase,
  };
  final Set<String> seen = <String>{};
  final List<AxisFullRow> rows = <AxisFullRow>[];
  final List<String> problems = <String>[];
  for (final String line in lines.skip(1)) {
    final List<String> fields = line.split(',');
    final String id = fields.first;
    final AxisFullCase? kase = byId[id];
    if (kase == null) {
      problems.add('$id: unknown case');
      continue;
    }
    if (!seen.add(id)) {
      problems.add('$id: duplicate');
      continue;
    }
    if (fields.length != 12) {
      problems.add('$id: expected 12 fields');
      continue;
    }
    if (!fields.sublist(1, 11).every(_number.hasMatch)) {
      problems.add('$id: not a number: $line');
      continue;
    }
    final String spacing = fields[11];
    if (spacing.isEmpty && kase.categories != null) {
      problems.add('$id: labelSpacing is empty on a chart with labels');
      continue;
    }
    if (spacing.isNotEmpty &&
        (!_count.hasMatch(spacing) || int.parse(spacing) == 0)) {
      problems.add('$id: labelSpacing $spacing is not a positive whole number');
      continue;
    }
    final List<double> n = fields.sublist(1, 11).map(double.parse).toList();
    final AxisFullRow row = AxisFullRow(
      id: id,
      width: n[0],
      height: n[1],
      font: n[2],
      min: n[3],
      max: n[4],
      major: n[5],
      plotLeft: n[6],
      plotTop: n[7],
      plotWidth: n[8],
      plotHeight: n[9],
      labelSpacing: spacing.isEmpty ? null : int.parse(spacing),
    );
    rows.add(row);
    const double slack = _plotTolerance + 1e-9;
    // A case that fixes both bounds to one value may get them back equal.
    final bool fixedEqual =
        kase.fixedMin != null && kase.fixedMin == kase.fixedMax;
    if (row.max < row.min || (row.max == row.min && !fixedEqual)) {
      problems.add('$id: max is not above min');
    } else if (row.major <= 0) {
      problems.add('$id: major is not above zero');
    } else if ((row.width - kase.width).abs() > _heightTolerance) {
      problems.add('$id: width ${row.width} is not ${kase.width}');
    } else if ((row.height - kase.height).abs() > _heightTolerance) {
      problems.add('$id: height ${row.height} is not ${kase.height}');
    } else if (row.font != kase.font) {
      problems.add('$id: font ${row.font} is not ${kase.font}');
    } else if (row.plotWidth < 0 ||
        row.plotHeight < 0 ||
        row.plotLeft < -slack ||
        row.plotTop < -slack ||
        row.plotLeft + row.plotWidth > row.width + slack ||
        row.plotTop + row.plotHeight > row.height + slack) {
      problems.add(
        '$id: plot box ${row.plotLeft},${row.plotTop},${row.plotWidth},'
        '${row.plotHeight} is outside the chart',
      );
    }
  }
  for (final AxisFullCase kase in cases.cases) {
    if (!seen.contains(kase.id)) problems.add('${kase.id}: missing');
  }
  return AxisFullCsv(rows, problems);
}

/// [value] rounded to hundredths, as the shortest text.
String _length(double value) => _numText((value * 100).round() / 100);

String _range(Iterable<double> values) {
  final double lo = values.reduce(math.min);
  final double hi = values.reduce(math.max);
  return lo == hi ? _length(lo) : '${_length(lo)}-${_length(hi)}';
}

String _scaleText(double min, double max, double major) =>
    '${_numText(min)} to ${_numText(max)} by ${_numText(major)}';

bool _close(double a, double b) =>
    (a - b).abs() <= 1e-9 * math.max(1, math.max(a.abs(), b.abs()));

double _plotLength(AxisFullCase kase, AxisFullRow row) =>
    kase.valueAxisIsHorizontal ? row.plotWidth : row.plotHeight;

/// The plain text report of [byRegion], whose rows must have no problems
/// ([readAxisFullCsv]): per region, what each group shows, or `no results`.
///
/// - L and B: per data set and font, the value axis' scale at each run of
///   plot lengths (the plot height of a column chart, the width of a bar
///   chart) that shares it, from short to long, so the length at which the
///   unit coarsens is where one run ends and the next begins.
/// - W: per data set and height, which of `min`, `max` and `major` differ
///   across width, or `same`.
/// - M, G and F: Excel's scale beside `autoValueScale`'s at Excel's own plot
///   length through `provisionalMaxIntervals`, labelled provisional: that
///   rule is not Excel's yet.
/// - C: per label set, the label spacing at each width (`-` for none).
String axisFullReport(
  AxisFullCases cases,
  Map<String, List<AxisFullRow>> byRegion,
) {
  if (byRegion.isEmpty) return 'no results\n';
  final StringBuffer out = StringBuffer();
  byRegion.forEach((String region, List<AxisFullRow> rows) {
    final Map<String, AxisFullRow> byId = <String, AxisFullRow>{
      for (final AxisFullRow row in rows) row.id: row,
    };
    Map<String, List<AxisFullCase>> keyed(
      String group,
      String Function(AxisFullCase) key,
    ) {
      final Map<String, List<AxisFullCase>> map =
          <String, List<AxisFullCase>>{};
      for (final AxisFullCase kase in cases.cases) {
        if (kase.group == group) {
          (map[key(kase)] ??= <AxisFullCase>[]).add(kase);
        }
      }
      return map;
    }

    out.writeln(region);
    for (final (String group, String title) in <(String, String)>[
      ('L', 'L: the unit against the plot height (column)'),
      ('B', 'B: the unit against the plot width (bar)'),
    ]) {
      out.writeln(title);
      keyed(group, (AxisFullCase c) => '$group${c.number} f${c.font}').forEach((
        String key,
        List<AxisFullCase> of,
      ) {
        final List<(double, AxisFullRow)> sorted =
            <(double, AxisFullRow)>[
              for (final AxisFullCase kase in of)
                (_plotLength(kase, byId[kase.id]!), byId[kase.id]!),
            ]..sort(
              ((double, AxisFullRow) a, (double, AxisFullRow) b) =>
                  a.$1.compareTo(b.$1),
            );
        final List<(String, List<double>)> runs = <(String, List<double>)>[];
        for (final (double length, AxisFullRow row) in sorted) {
          final String scale = _scaleText(row.min, row.max, row.major);
          if (runs.isEmpty || runs.last.$1 != scale) {
            runs.add((scale, <double>[length]));
          } else {
            runs.last.$2.add(length);
          }
        }
        final String all = _range(
          sorted.map(((double, AxisFullRow) e) => e.$1),
        );
        out.writeln(
          runs.length == 1
              ? '$key: plot $all: ${runs.single.$1}'
              : '$key: plot $all: ${<String>[for (final (String scale, List<double> lengths) in runs) '$scale at ${_range(lengths)}'].join(', ')}',
        );
      });
    }

    out.writeln('W: across width');
    keyed('W', (AxisFullCase c) => 'W${c.number} h${c.height}').forEach((
      String key,
      List<AxisFullCase> of,
    ) {
      final List<AxisFullRow> group = <AxisFullRow>[
        for (final AxisFullCase kase in of) byId[kase.id]!,
      ];
      final List<String> differing = <String>[
        if (group.map((AxisFullRow r) => r.min).toSet().length > 1) 'min',
        if (group.map((AxisFullRow r) => r.max).toSet().length > 1) 'max',
        if (group.map((AxisFullRow r) => r.major).toSet().length > 1) 'major',
      ];
      out.writeln(
        '$key: across width: ${differing.isEmpty ? 'same' : differing.join(', ')}',
      );
    });

    out.writeln(
      'M, G, F: Excel beside the provisional rule '
      '(provisionalMaxIntervals at Excel\'s plot length)',
    );
    for (final AxisFullCase kase in cases.cases) {
      if (!const <String>{'M', 'G', 'F'}.contains(kase.group)) continue;
      final AxisFullRow row = byId[kase.id]!;
      final double length = _plotLength(kase, row);
      final ({double min, double max}) extent = dataExtent(<List<double?>>[
        for (final List<String> values in kase.series)
          <double?>[
            for (final String v in values) v.isEmpty ? null : double.parse(v),
          ],
      ], ChartGrouping.values.byName(kase.grouping));
      final ValueScale rule = autoValueScale(
        dataMin: extent.min,
        dataMax: extent.max,
        maxIntervals: provisionalMaxIntervals(length),
        fixedMin: kase.fixedMin,
        fixedMax: kase.fixedMax,
        fixedMajorUnit: kase.fixedMajor,
        percent: kase.grouping == 'percentStacked',
      );
      final bool same =
          _close(rule.min, row.min) &&
          _close(rule.max, row.max) &&
          _close(rule.majorUnit, row.major);
      out.writeln(
        '${kase.id}: Excel ${_scaleText(row.min, row.max, row.major)}; '
        'provisional ${_scaleText(rule.min, rule.max, rule.majorUnit)} '
        'at plot ${_length(length)}: ${same ? 'same' : 'differs'}',
      );
    }

    out.writeln('C: label spacing per width');
    keyed('C', (AxisFullCase c) => c.number).forEach((
      String number,
      List<AxisFullCase> of,
    ) {
      final int characters = of.first.categories?.first.length ?? 0;
      out.writeln(
        'C$number ($characters characters): ${<String>[for (final AxisFullCase kase in of) 'w${kase.width} ${byId[kase.id]!.labelSpacing ?? '-'}'].join('; ')}',
      );
    });
  });
  return out.toString();
}
