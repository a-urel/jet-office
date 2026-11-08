/// The Excel oracle for axis scaling: its case list, the workbook
/// `tool/write_axis_oracle.dart` writes from it, the checks on what Excel
/// reported and the analysis `tool/analyze_axis_oracle.dart` prints.
///
/// The case list is `test/fixtures/owner/axis/cases.json`; the README beside
/// it describes its format, the CSV and the manifest. A case is one chart: a
/// data set at a height and a font size. The question is whether Excel's
/// automatic minimum, maximum and major unit depend on the last two; Excel
/// is the oracle (decision 0014).
///
/// [buildAxisWorkbook] writes the file itself, with a small writer of its own
/// (`archive`, a dev dependency): this package knows no file format and may
/// not depend on `jet_office`. It writes one chart shape and nothing else.
/// No `dart:io` here: the tests run in a browser as well.
///
/// The full oracle (case list version 2, `test/fixtures/owner/axis_full/`)
/// is in the part `axis_oracle_full.dart`: charts of four kinds and three
/// groupings at chosen widths and heights, with the plot area's box and the
/// category labels' spacing read as well.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show excelMaxIntervals;

part 'axis_oracle_full.dart';

/// The regions an owner's run may come from, as jet_core's oracle has them.
const List<String> axisOracleRegions = <String>['en-US', 'de-DE', 'tr-TR'];

/// The first line of a results CSV.
const String axisCsvHeader = 'case,height,font,min,max,major';

/// The workbook's file name.
const String axisWorkbookName = 'axis_oracle.xlsx';

/// How far, in points, the height Excel reports may be from the case's.
const double _heightTolerance = 1;

/// The font of the cases compared across height.
const int _baseFont = 10;

/// The height of the cases compared across font.
const int _baseHeight = 300;

/// EMU per point.
const int _emu = 12700;

/// Where the charts start, in points: beyond columns A and B.
const int _chartLeft = 200;

/// The space above each chart, in points.
const int _chartGap = 20;

final RegExp _number = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');
final RegExp _setId = RegExp(r'^d\d\d$');

/// One data set: a sheet of the workbook.
final class AxisDataSet {
  /// Creates a data set.
  const AxisDataSet(this.id, this.values);

  /// The id and sheet name, such as `d01`.
  final String id;

  /// The values, as the text written to the sheet and the chart's cache.
  final List<String> values;
}

/// One chart of the workbook.
final class AxisCase {
  /// Creates a case.
  const AxisCase(this.set, this.height, this.font);

  /// The data set it charts.
  final AxisDataSet set;

  /// The chart's height in points.
  final int height;

  /// The chart's font size in points.
  final int font;

  /// The case id and the chart's name, such as `d01-h150-f10`.
  String get id => '${set.id}-h$height-f$font';
}

/// The parsed case list.
final class AxisOracleCases {
  /// Creates a case list.
  const AxisOracleCases(this.chartWidth, this.sets, this.cases);

  /// Every chart's width in points.
  final int chartWidth;

  /// The data sets in file order.
  final List<AxisDataSet> sets;

  /// Every data set at every size, set by set.
  final List<AxisCase> cases;
}

/// Parses the case list [text]. Throws a [FormatException] on anything but
/// the format of the README.
AxisOracleCases parseAxisCases(String text) {
  final Object? root = jsonDecode(text);
  if (root is! Map<String, Object?> || root['version'] != 1) {
    throw const FormatException('expected an object of version 1');
  }
  final Object? width = root['chartWidth'];
  final Object? rawSets = root['sets'];
  final Object? rawSizes = root['sizes'];
  if (width is! int ||
      rawSets is! List<Object?> ||
      rawSizes is! List<Object?>) {
    throw const FormatException('expected chartWidth, sets and sizes');
  }
  final List<AxisDataSet> sets = <AxisDataSet>[];
  for (final Object? raw in rawSets) {
    if (raw is! Map<String, Object?>) {
      throw const FormatException('sets: expected objects');
    }
    final Object? id = raw['id'];
    final Object? values = raw['values'];
    if (id is! String || !_setId.hasMatch(id) || values is! List<Object?>) {
      throw FormatException('sets: bad set $id');
    }
    if (sets.any((AxisDataSet set) => set.id == id)) {
      throw FormatException('sets: duplicate id $id');
    }
    if (values.isEmpty ||
        values.any((Object? v) => v is! String || !_number.hasMatch(v))) {
      throw FormatException('$id: expected numbers as text');
    }
    sets.add(AxisDataSet(id, values.cast<String>()));
  }
  final List<(int, int)> sizes = <(int, int)>[
    for (final Object? raw in rawSizes)
      switch (raw) {
        {'height': final int height, 'font': final int font} => (height, font),
        _ => throw const FormatException('sizes: expected height and font'),
      },
  ];
  return AxisOracleCases(width, sets, <AxisCase>[
    for (final AxisDataSet set in sets)
      for (final (int height, int font) in sizes) AxisCase(set, height, font),
  ]);
}

/// Writes `axis_oracle.xlsx` for [cases]: a sheet per data set, its labels in
/// column A and values in column B, and a chart per case on it, named by the
/// case id. Nothing in a chart fixes the scale. The same [cases] give the same
/// bytes.
Uint8List buildAxisWorkbook(AxisOracleCases cases) {
  final Archive archive = Archive();
  void add(String name, String text) =>
      archive.add(ArchiveFile.bytes(name, utf8.encode(text)));

  add('[Content_Types].xml', _contentTypes(cases));
  add(
    '_rels/.rels',
    _rels(<String>[_rel(1, 'officeDocument', 'xl/workbook.xml')]),
  );
  add('xl/workbook.xml', _workbookXml(cases));
  add(
    'xl/_rels/workbook.xml.rels',
    _rels(<String>[
      for (int i = 1; i <= cases.sets.length; i++)
        _rel(i, 'worksheet', 'worksheets/sheet$i.xml'),
    ]),
  );
  int chart = 0;
  for (int i = 1; i <= cases.sets.length; i++) {
    final AxisDataSet set = cases.sets[i - 1];
    final List<AxisCase> charts = <AxisCase>[
      for (final AxisCase kase in cases.cases)
        if (identical(kase.set, set)) kase,
    ];
    add('xl/worksheets/sheet$i.xml', _sheetXml(set));
    add(
      'xl/worksheets/_rels/sheet$i.xml.rels',
      _rels(<String>[_rel(1, 'drawing', '../drawings/drawing$i.xml')]),
    );
    add('xl/drawings/drawing$i.xml', _drawingXml(charts, cases.chartWidth));
    add(
      'xl/drawings/_rels/drawing$i.xml.rels',
      _rels(<String>[
        for (int n = 1; n <= charts.length; n++)
          _rel(n, 'chart', '../charts/chart${chart + n}.xml'),
      ]),
    );
    for (final AxisCase kase in charts) {
      add('xl/charts/chart${++chart}.xml', _chartXml(kase));
    }
  }
  return Uint8List.fromList(
    ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2020)),
  );
}

const String _xmlDecl =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _mainNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _chartNs =
    'http://schemas.openxmlformats.org/drawingml/2006/chart';
const String _drawingNs =
    'http://schemas.openxmlformats.org/drawingml/2006/main';

String _contentTypes(AxisOracleCases cases) =>
    _contentTypesFor(cases.sets.length, cases.cases.length);

String _contentTypesFor(int sheets, int charts) {
  const String office = 'application/vnd.openxmlformats-officedocument';
  return '$_xmlDecl<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="$office.spreadsheetml.sheet.main+xml"/>'
      '${<String>[
        for (int i = 1; i <= sheets; i++) ...<String>['<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="$office.spreadsheetml.worksheet+xml"/>', '<Override PartName="/xl/drawings/drawing$i.xml" ContentType="$office.drawing+xml"/>'],
        for (int i = 1; i <= charts; i++) '<Override PartName="/xl/charts/chart$i.xml" ContentType="$office.drawingml.chart+xml"/>',
      ].join()}'
      '</Types>';
}

String _rels(List<String> relationships) =>
    '$_xmlDecl<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${relationships.join()}</Relationships>';

String _rel(int id, String type, String target) =>
    '<Relationship Id="rId$id" Type="$_relNs/$type" Target="$target"/>';

String _workbookXml(AxisOracleCases cases) =>
    _workbookXmlFor(<String>[for (final AxisDataSet set in cases.sets) set.id]);

String _workbookXmlFor(List<String> sheets) =>
    '$_xmlDecl<workbook xmlns="$_mainNs" xmlns:r="$_relNs"><sheets>'
    '${<String>[for (int i = 1; i <= sheets.length; i++) '<sheet name="${sheets[i - 1]}" sheetId="$i" r:id="rId$i"/>'].join()}'
    '</sheets></workbook>';

String _label(int index) => 'c${index + 1}';

String _sheetXml(AxisDataSet set) =>
    '$_xmlDecl<worksheet xmlns="$_mainNs" xmlns:r="$_relNs"><sheetData>'
    '${<String>[for (int i = 0; i < set.values.length; i++) '<row r="${i + 1}">'
          '<c r="A${i + 1}" t="inlineStr"><is><t>${_label(i)}</t></is></c>'
          '<c r="B${i + 1}"><v>${set.values[i]}</v></c></row>'].join()}'
    '</sheetData><drawing r:id="rId1"/></worksheet>';

String _drawingXml(List<AxisCase> charts, int width) =>
    _anchorsXml(<(String, int, int)>[
      for (final AxisCase kase in charts) (kase.id, width, kase.height),
    ]);

/// A drawing of one chart per (name, width, height), stacked downwards.
String _anchorsXml(List<(String, int, int)> charts) {
  final StringBuffer out = StringBuffer(
    '$_xmlDecl<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
    'xmlns:a="$_drawingNs">',
  );
  int top = _chartGap;
  for (int i = 0; i < charts.length; i++) {
    final (String name, int width, int height) = charts[i];
    out.write(
      '<xdr:absoluteAnchor>'
      '<xdr:pos x="${_chartLeft * _emu}" y="${top * _emu}"/>'
      '<xdr:ext cx="${width * _emu}" cy="${height * _emu}"/>'
      '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
      '<xdr:cNvPr id="${i + 2}" name="$name"/><xdr:cNvGraphicFramePr/>'
      '</xdr:nvGraphicFramePr>'
      '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
      '<a:graphic><a:graphicData uri="$_chartNs">'
      '<c:chart xmlns:c="$_chartNs" xmlns:r="$_relNs" r:id="rId${i + 1}"/>'
      '</a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/>'
      '</xdr:absoluteAnchor>',
    );
    top += height + _chartGap;
  }
  out.write('</xdr:wsDr>');
  return out.toString();
}

String _chartXml(AxisCase kase) {
  final List<String> values = kase.set.values;
  final int n = values.length;
  // A name such as d01 reads as a cell, so a reference must quote it.
  final String sheet = "'${kase.set.id}'";
  String points(String Function(int) text) => <String>[
    '<c:ptCount val="$n"/>',
    for (int i = 0; i < n; i++) '<c:pt idx="$i"><c:v>${text(i)}</c:v></c:pt>',
  ].join();
  return '$_xmlDecl<c:chartSpace xmlns:c="$_chartNs" xmlns:a="$_drawingNs" xmlns:r="$_relNs">'
      '<c:roundedCorners val="0"/>'
      '<c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:layout/>'
      '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>'
      '<c:varyColors val="0"/>'
      '<c:ser><c:idx val="0"/><c:order val="0"/>'
      '<c:spPr><a:solidFill><a:srgbClr val="156082"/></a:solidFill></c:spPr>'
      '<c:invertIfNegative val="0"/>'
      '<c:cat><c:strRef><c:f>$sheet!\$A\$1:\$A\$$n</c:f>'
      '<c:strCache>${points(_label)}</c:strCache></c:strRef></c:cat>'
      '<c:val><c:numRef><c:f>$sheet!\$B\$1:\$B\$$n</c:f>'
      '<c:numCache><c:formatCode>General</c:formatCode>'
      '${points((int i) => values[i])}</c:numCache></c:numRef></c:val>'
      '</c:ser><c:axId val="111111111"/><c:axId val="222222222"/></c:barChart>'
      '<c:catAx><c:axId val="111111111"/>'
      '<c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
      '<c:axPos val="b"/><c:numFmt formatCode="General" sourceLinked="1"/>'
      '<c:majorTickMark val="out"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/><c:crossAx val="222222222"/>'
      '<c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/>'
      '<c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
      '<c:valAx><c:axId val="222222222"/>'
      '<c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
      '<c:axPos val="l"/><c:majorGridlines/>'
      '<c:numFmt formatCode="General" sourceLinked="1"/>'
      '<c:majorTickMark val="out"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/><c:crossAx val="111111111"/>'
      '<c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>'
      '</c:plotArea><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>'
      '<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr>'
      '<a:defRPr sz="${kase.font * 100}"><a:latin typeface="Aptos Narrow"/></a:defRPr>'
      '</a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr>'
      '</c:chartSpace>';
}

/// One row of a results CSV: what Excel reported for a chart.
final class AxisRow {
  /// Creates a row.
  const AxisRow({
    required this.id,
    required this.height,
    required this.font,
    required this.min,
    required this.max,
    required this.major,
  });

  /// The case id.
  final String id;

  /// The chart object's height in points.
  final double height;

  /// The font size of the value axis' tick labels.
  final double font;

  /// The value axis' automatic minimum.
  final double min;

  /// The value axis' automatic maximum.
  final double max;

  /// The value axis' automatic major unit.
  final double major;
}

/// A read results CSV.
final class AxisCsv {
  /// Creates a read CSV.
  const AxisCsv(this.rows, this.problems);

  /// The rows that read as numbers, in file order.
  final List<AxisRow> rows;

  /// What is wrong, one line each; empty for a usable CSV.
  final List<String> problems;
}

/// Reads the results CSV [text] of [cases].
///
/// A problem is a wrong header, a line that is not six fields, a field that
/// is no number, a case unknown, repeated or missing, a maximum not above the
/// minimum, a major unit not above zero, a height more than a point from the
/// case's, and a font not the case's: a result is valid only if Excel took
/// the size. A leading BOM and CR or CRLF line ends are accepted.
AxisCsv readAxisCsv(AxisOracleCases cases, String text) {
  final List<String> lines = <String>[
    for (final String line
        in text.replaceFirst('\uFEFF', '').split(RegExp(r'\r\n|\r|\n')))
      if (line.isNotEmpty) line,
  ];
  if (lines.isEmpty || lines.first != axisCsvHeader) {
    return const AxisCsv(<AxisRow>[], <String>[
      'the header is not $axisCsvHeader',
    ]);
  }
  final Map<String, AxisCase> byId = <String, AxisCase>{
    for (final AxisCase kase in cases.cases) kase.id: kase,
  };
  final Set<String> seen = <String>{};
  final List<AxisRow> rows = <AxisRow>[];
  final List<String> problems = <String>[];
  for (final String line in lines.skip(1)) {
    final List<String> fields = line.split(',');
    final String id = fields.first;
    final AxisCase? kase = byId[id];
    if (kase == null) {
      problems.add('$id: unknown case');
    } else if (!seen.add(id)) {
      problems.add('$id: duplicate');
    } else if (fields.length != 6) {
      problems.add('$id: expected 6 fields');
    } else if (!fields.skip(1).every(_number.hasMatch)) {
      problems.add('$id: not a number: $line');
    } else {
      final List<double> n = fields.skip(1).map(double.parse).toList();
      final AxisRow row = AxisRow(
        id: id,
        height: n[0],
        font: n[1],
        min: n[2],
        max: n[3],
        major: n[4],
      );
      rows.add(row);
      if (row.max <= row.min) problems.add('$id: max is not above min');
      if (row.major <= 0) problems.add('$id: major is not above zero');
      if ((row.height - kase.height).abs() > _heightTolerance) {
        problems.add('$id: height ${row.height} is not ${kase.height}');
      }
      if (row.font != kase.font) {
        problems.add('$id: font ${row.font} is not ${kase.font}');
      }
    }
  }
  for (final AxisCase kase in cases.cases) {
    if (!seen.contains(kase.id)) problems.add('${kase.id}: missing');
  }
  return AxisCsv(rows, problems);
}

/// One region's run, as `manifest.json` records it (format in the README).
final class AxisManifestEntry {
  /// Creates an entry.
  const AxisManifestEntry({
    required this.region,
    required this.appleLocale,
    required this.excelLanguage,
    required this.excel,
    required this.macos,
    required this.confirmedBy,
    required this.csv,
    required this.notes,
  });

  /// One of [axisOracleRegions].
  final String region;

  /// What `defaults read -g AppleLocale` printed, such as `tr_TR`.
  final String appleLocale;

  /// Excel's language in the run.
  final String excelLanguage;

  /// Excel's name, version and build.
  final String excel;

  /// The macOS version.
  final String macos;

  /// Always `owner`.
  final String confirmedBy;

  /// The CSV file, `axis_oracle.<region>.csv` (`axis_oracle_full.<region>.csv`
  /// for the full oracle).
  final String csv;

  /// What Excel said or did, or empty.
  final String notes;
}

const Set<String> _manifestKeys = <String>{
  'region',
  'appleLocale',
  'excelLanguage',
  'excel',
  'macos',
  'confirmedBy',
  'csv',
  'notes',
};

/// Parses `manifest.json` [text]: a list of [AxisManifestEntry].
///
/// Every field must be present, and no other; all but `notes` filled in, with
/// no `<placeholder>` left. `region` must be one of [axisOracleRegions], at
/// most once in the list, `confirmedBy` exactly `owner`, and `csv`
/// `<csvStem>.<region>.csv`: `axis_oracle.<region>.csv` by default, and
/// [axisFullCsvStem] for the full oracle. Throws a [FormatException]
/// otherwise.
List<AxisManifestEntry> parseAxisManifest(
  String text, {
  String csvStem = 'axis_oracle',
}) {
  final Object? root = jsonDecode(text);
  if (root is! List<Object?>) throw const FormatException('expected a list');
  final Set<String> regions = <String>{};
  final List<AxisManifestEntry> entries = <AxisManifestEntry>[];
  for (int i = 0; i < root.length; i++) {
    final Object? raw = root[i];
    if (raw is! Map<String, Object?> ||
        raw.length != _manifestKeys.length ||
        !raw.keys.toSet().containsAll(_manifestKeys)) {
      throw FormatException('[$i]: expected exactly $_manifestKeys');
    }
    String field(String key) {
      final Object? value = raw[key];
      if (value is! String ||
          value.startsWith('<') ||
          (value.isEmpty && key != 'notes')) {
        throw FormatException('[$i].$key: fill it in');
      }
      return value;
    }

    final String region = field('region');
    if (!axisOracleRegions.contains(region) || !regions.add(region)) {
      throw FormatException('[$i].region: unknown or repeated $region');
    }
    if (field('confirmedBy') != 'owner') {
      throw FormatException('[$i].confirmedBy: expected owner');
    }
    if (field('csv') != '$csvStem.$region.csv') {
      throw FormatException('[$i].csv: expected $csvStem.$region.csv');
    }
    entries.add(
      AxisManifestEntry(
        region: region,
        appleLocale: field('appleLocale'),
        excelLanguage: field('excelLanguage'),
        excel: field('excel'),
        macos: field('macos'),
        confirmedBy: 'owner',
        csv: field('csv'),
        notes: field('notes'),
      ),
    );
  }
  return entries;
}

/// What differed in one data set of a region's run.
final class AxisSetFinding {
  /// Creates a finding.
  const AxisSetFinding(this.set, this.acrossHeight, this.acrossFont);

  /// The data set's id.
  final String set;

  /// Which of `min`, `max` and `major` differ across height, at font 10.
  final List<String> acrossHeight;

  /// Which of `min`, `max` and `major` differ across font, at height 300.
  final List<String> acrossFont;
}

/// Compares [rows], which must have no problems ([readAxisCsv]), within each
/// data set of [cases].
List<AxisSetFinding> analyzeAxisRows(
  AxisOracleCases cases,
  List<AxisRow> rows,
) {
  final Map<String, AxisRow> byId = <String, AxisRow>{
    for (final AxisRow row in rows) row.id: row,
  };
  List<String> differing(Iterable<AxisCase> group) {
    final List<AxisRow> of = <AxisRow>[
      for (final AxisCase kase in group) byId[kase.id]!,
    ];
    return <String>[
      if (of.map((AxisRow r) => r.min).toSet().length > 1) 'min',
      if (of.map((AxisRow r) => r.max).toSet().length > 1) 'max',
      if (of.map((AxisRow r) => r.major).toSet().length > 1) 'major',
    ];
  }

  return <AxisSetFinding>[
    for (final AxisDataSet set in cases.sets)
      AxisSetFinding(
        set.id,
        differing(
          cases.cases.where(
            (AxisCase c) => identical(c.set, set) && c.font == _baseFont,
          ),
        ),
        differing(
          cases.cases.where(
            (AxisCase c) => identical(c.set, set) && c.height == _baseHeight,
          ),
        ),
      ),
  ];
}

/// The plain text report of [byRegion]: a line per data set of each region,
/// then the answer, or `no results`.
String axisOracleReport(Map<String, List<AxisSetFinding>> byRegion) {
  if (byRegion.isEmpty) return 'no results\n';
  String list(List<String> fields) =>
      fields.isEmpty ? 'same' : fields.join(', ');
  String answer(List<String> Function(AxisSetFinding) fields) {
    final List<String> hits = <String>[
      for (final MapEntry<String, List<AxisSetFinding>> region
          in byRegion.entries)
        if (region.value.any((AxisSetFinding f) => fields(f).isNotEmpty))
          '${region.key} ${<String>[for (final AxisSetFinding f in region.value)
            if (fields(f).isNotEmpty) f.set].join(', ')}',
    ];
    return hits.isEmpty ? 'no' : 'yes (${hits.join('; ')})';
  }

  final StringBuffer out = StringBuffer();
  byRegion.forEach((String region, List<AxisSetFinding> findings) {
    out.writeln(region);
    for (final AxisSetFinding f in findings) {
      out.writeln(
        '${f.set}: across height: ${list(f.acrossHeight)}; '
        'across font: ${list(f.acrossFont)}',
      );
    }
  });
  out.writeln(
    'answer: across height: '
    '${answer((AxisSetFinding f) => f.acrossHeight)}; '
    'across font: ${answer((AxisSetFinding f) => f.acrossFont)}',
  );
  return out.toString();
}
