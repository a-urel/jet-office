import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/chart.dart'
    show xlsxChartIds, xlsxChartWithIds;
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart'
    show openedChartPartCount;
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:jet_office/src/xml/xml_equivalence.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../drawingml/chart/support/excel_charts.dart';
import '../../fixtures/c1_fixtures.dart';
import '../../fixtures/fixtures.dart';
import '../../fixtures/m4_fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/producers.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

const String _xdr =
    'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="$relNs"';

String _marker(
  String name,
  int col,
  int row, {
  int colOff = 0,
  int rowOff = 0,
}) =>
    '<xdr:$name><xdr:col>$col</xdr:col><xdr:colOff>$colOff</xdr:colOff>'
    '<xdr:row>$row</xdr:row><xdr:rowOff>$rowOff</xdr:rowOff></xdr:$name>';

/// A graphic frame showing the chart of relationship [rel], `cNvPr` [id].
String _frame(int id, String rel, {String name = 'Chart 1', String? descr}) =>
    '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
    '<xdr:cNvPr id="$id" name="$name"'
    '${descr == null ? '' : ' descr="$descr"'}/>'
    '<xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
    '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
    '<a:graphic><a:graphicData '
    'uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
    '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
    'r:id="$rel"/></a:graphicData></a:graphic></xdr:graphicFrame>';

/// A two-cell anchor from B3 (offsets 9525 and 190500 EMU) to H18 holding
/// [content].
String _twoCell(String content) =>
    '<xdr:twoCellAnchor>'
    '${_marker('from', 1, 2, colOff: 9525, rowOff: 190500)}'
    '${_marker('to', 7, 17)}$content<xdr:clientData/></xdr:twoCellAnchor>';

String _pic(int id) =>
    '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="$id" name="Picture 1"/>'
    '<xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rIdP"/>'
    '</xdr:blipFill><xdr:spPr/></xdr:pic>';

String _oneCellPic(int id) =>
    '<xdr:oneCellAnchor>${_marker('from', 9, 0)}'
    '<xdr:ext cx="38100" cy="19050"/>${_pic(id)}<xdr:clientData/>'
    '</xdr:oneCellAnchor>';

/// A one-sheet package (`S`) whose drawing holds [anchors]; [charts] are the
/// chart parts by relationship id (`xl/charts/chart{n}.xml`, n from 1 in
/// order), and [extraRels] more relationships of the drawing.
Uint8List _package(
  String anchors, {
  Map<String, List<int>> charts = const <String, List<int>>{},
  String extraRels = '',
  bool picture = false,
  bool date1904 = false,
  String? theme,
  Map<String, List<int>> extraParts = const <String, List<int>>{},
}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    buildWorkbook(
      <String, String>{
        'S':
            '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>'
            '<drawing r:id="rId1"/></worksheet>',
      },
      date1904: date1904,
      theme: theme,
    ),
  );
  parts['xl/worksheets/_rels/sheet1.xml.rels'] = Uint8List.fromList(
    utf8.encode(
      '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
      'Type="$relNs/drawing" Target="../drawings/drawing1.xml"/>'
      '</Relationships>',
    ),
  );
  parts['xl/drawings/drawing1.xml'] = Uint8List.fromList(
    utf8.encode('<xdr:wsDr $_xdr>$anchors</xdr:wsDr>'),
  );
  final StringBuffer rels = StringBuffer();
  int n = 0;
  for (final MapEntry<String, List<int>> e in charts.entries) {
    n++;
    rels.write(
      '<Relationship Id="${e.key}" Type="$relNs/chart" '
      'Target="../charts/chart$n.xml"/>',
    );
    parts['xl/charts/chart$n.xml'] = Uint8List.fromList(e.value);
  }
  if (picture) {
    rels.write(
      '<Relationship Id="rIdP" Type="$relNs/image" '
      'Target="../media/image1.png"/>',
    );
    parts['xl/media/image1.png'] = Uint8List.fromList(png4x2);
  }
  parts['xl/drawings/_rels/drawing1.xml.rels'] = Uint8List.fromList(
    utf8.encode(
      '<Relationships xmlns="$pkgRelNs">$rels$extraRels</Relationships>',
    ),
  );
  return buildZip(<String, List<int>>{...parts, ...extraParts});
}

int _invalid(XlsxWorkbook book, String detail) => book.warnings
    .where(
      (XlsxWarning w) =>
          w.code == XlsxWarningCode.featureEntryInvalid && w.detail == detail,
    )
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

void _unchanged(Uint8List input, XlsxWorkbook book) => expect(
  comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
  isEmpty,
);

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

final List<int> _column = utf8.encode(excelColumnChart);

/// The anchor [_twoCell] gives.
const XlsxAnchor _anchor = XlsxTwoCellAnchor(
  XlsxAnchorPoint(2, 1, offsetX: 1, offsetY: 20),
  XlsxAnchorPoint(17, 7),
);

/// The deterministic ids of chart part n with [series] series (Global
/// Constraints of C2).
DrawingChartIds _ids(int n, int series) => DrawingChartIds(
  categoryAxis: 100000 + 2 * n,
  valueAxis: 100001 + 2 * n,
  secondaryCategoryAxis: 200000 + 2 * n,
  secondaryValueAxis: 200001 + 2 * n,
  series: <String>[
    for (int i = 0; i < series; i++)
      '{00000000-00C1-0000-${n.toString().padLeft(4, '0')}-'
          '${i.toString().padLeft(12, '0')}}',
  ],
);

/// A column chart of two series over three categories.
Chart _columns({String? title}) => Chart(
  kind: ChartKind.column,
  title: title == null ? null : ChartTitle(text: title),
  series: <ChartSeries>[
    for (final String name in <String>['North', 'South'])
      ChartSeries(
        name: ChartData<String>(values: <String?>[name]),
        categories: ChartData<Object>(values: const <Object?>['a', 'b', 'c']),
        values: ChartData<double>(values: const <double?>[1, 2, 3]),
      ),
  ],
);

/// A pie chart of one series whose values are [values].
Chart _pie(List<double?> values) => Chart(
  kind: ChartKind.pie,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: const <String?>['Share']),
      categories: ChartData<Object>(
        values: <Object?>[for (int i = 0; i < values.length; i++) 'c$i'],
      ),
      values: ChartData<double>(values: values),
    ),
  ],
);

String _text(Uint8List xlsx, String part) =>
    utf8.decode(readXlsxBytes(xlsx)[part]!);

/// What a drawing's root holds: its text between the root's start tag and
/// its end tag.
String _drawingBody(String xml) {
  final int root = xml.indexOf('wsDr');
  final int start = xml.indexOf('>', root) + 1;
  return xml.substring(start, xml.lastIndexOf('</'));
}

/// The chart part names of [xlsx].
Set<String> _chartParts(Uint8List xlsx) => <String>{
  for (final String name in readXlsxBytes(xlsx).keys)
    if (name.startsWith('xl/charts/')) name,
};

/// [_column] with relationships to a style and a colour-style part, beside a
/// picture.
Uint8List _styledColumn({bool picture = false}) => _package(
  '${_twoCell(_frame(2, 'rIdC'))}${picture ? _oneCellPic(3) : ''}',
  charts: <String, List<int>>{'rIdC': _column},
  picture: picture,
  extraParts: <String, List<int>>{
    'xl/charts/_rels/chart1.xml.rels': utf8.encode(
      '<Relationships xmlns="$pkgRelNs">'
      '<Relationship Id="rId2" Type="$_chartColorStyle" '
      'Target="colors1.xml"/>'
      '<Relationship Id="rId1" Type="$_chartStyle" Target="style1.xml"/>'
      '</Relationships>',
    ),
    'xl/charts/style1.xml': utf8.encode(
      '<cs:chartStyle xmlns:cs="http://schemas.microsoft.com/office/drawing/'
      '2012/chartStyle" id="201"/>',
    ),
    'xl/charts/colors1.xml': utf8.encode(
      '<cs:colorStyle xmlns:cs="http://schemas.microsoft.com/office/drawing/'
      '2012/chartStyle" meth="cycle" id="10"/>',
    ),
  },
);

const String _chartStyle =
    'http://schemas.microsoft.com/office/2011/relationships/chartStyle';
const String _chartColorStyle =
    'http://schemas.microsoft.com/office/2011/relationships/chartColorStyle';

/// Expects [read], the ids a part read back with, to be [written]'s, the
/// secondary axes aside: a part without a secondary axis does not hold them.
void _sameIds(DrawingChartIds read, DrawingChartIds written) {
  expect(read.categoryAxis, written.categoryAxis);
  expect(read.valueAxis, written.valueAxis);
  expect(read.series, written.series);
}

/// Expects [edit] to throw [matcher] and leave [book] saving as before.
void _refused(XlsxWorkbook book, void Function() edit, Matcher matcher) {
  final Uint8List before = book.save().bytes;
  final int warnings = book.warnings.length;
  expect(edit, matcher);
  expect(comparePackages(before, book.save().bytes), isEmpty);
  expect(book.warnings, hasLength(warnings));
}

int _warned(XlsxWorkbook book, XlsxWarningCode code) => book.warnings
    .where((XlsxWarning w) => w.code == code)
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

/// Edits the first sheet of [input] with [edit] as one transaction, then
/// checks undo gives the input back byte for byte (bookkeeping aside), redo
/// the edited file, and undo the input again.
void _undone(Uint8List input, void Function(XlsxSheet sheet) edit) {
  final XlsxWorkbook book = XlsxWorkbook.open(input);
  final XlsxSheet sheet = book.sheets.first;
  final ChangeLog log = changeLogOf(book);
  final List<XlsxSheetChart> before = sheet.charts;
  final List<XlsxPicture> pictures = sheet.pictures;
  final ChangeSet set = log.transaction(() => edit(sheet));
  final List<XlsxSheetChart> after = sheet.charts;
  final Uint8List edited = book.save().bytes;
  log.revertSet(set);
  expect(sheet.charts, before);
  expect(sheet.pictures, pictures);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  log.reapplySet(set);
  expect(sheet.charts, after);
  expect(
    comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  log.revertSet(set);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
}

void main() {
  group('XlsxChart', () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        ChartSeries(
          name: ChartData<String>(values: const <String?>['A']),
          categories: ChartData<Object>(values: const <Object?>['x']),
          values: ChartData<double>(values: const <double?>[1]),
        ),
      ],
    );

    test('takes the Office theme, en-US and no automatic title by '
        'default', () {
      final XlsxChart c = XlsxChart(chart, _anchor);
      expect(c.theme, ChartTheme.office);
      expect(c.language, 'en-US');
      expect(c.autoTitle, isFalse);
      expect(c.name, isNull);
      expect(c.description, isNull);
      expect(xlsxChartIds(c), isNull);
    });

    test('has value equality', () {
      expect(
        XlsxChart(chart, _anchor, name: 'n', description: 'd'),
        XlsxChart(chart, _anchor, name: 'n', description: 'd'),
      );
      expect(
        XlsxChart(chart, _anchor).hashCode,
        XlsxChart(chart, _anchor).hashCode,
      );
      expect(
        XlsxChart(chart, _anchor),
        isNot(XlsxChart(chart, _anchor, name: 'n')),
      );
      expect(
        XlsxChart(chart, _anchor),
        isNot(XlsxChart(chart, _anchor, language: 'tr-TR')),
      );
      expect(
        XlsxChart(chart, _anchor),
        isNot(XlsxChart(chart, _anchor, autoTitle: true)),
      );
    });
  });

  group('charts', () {
    test("lists c1_kinds' twelve charts, typed, with their ids", () {
      final Uint8List input = _fixture('c1_kinds');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final List<XlsxSheetChart> charts = book.sheet('Data').charts;
      final List<C1Chart> expected = c1Charts('c1_kinds');
      expect(charts, hasLength(12));
      for (int i = 0; i < 12; i++) {
        final XlsxSheetChart c = charts[i];
        final DrawingChartSpace space = expected[i].space;
        expect(c.name, 'Chart ${i + 1}');
        expect(c.description, isNull);
        final int column = (i % 3) * 8;
        // The test host starts the grid on row 2.
        final int row = 1 + (i ~/ 3) * 15;
        expect(
          c.anchor,
          XlsxTwoCellAnchor(
            XlsxAnchorPoint(row, column),
            XlsxAnchorPoint(row + 15, column + 8),
            resize: XlsxPictureResize.move,
          ),
          reason: 'chart ${i + 1}',
        );
        expect(c.view, space.chart);
        final XlsxChart typed = c.typed!;
        expect(typed.chart, space.chart);
        expect(typed.anchor, c.anchor);
        expect(typed.name, c.name);
        expect(typed.language, space.language);
        expect(typed.autoTitle, space.autoTitle);
        expect(typed.theme, ChartTheme.office);
        expect(xlsxChartIds(typed), space.ids);
      }
      expect(() => charts.add(charts.first), throwsUnsupportedError);
      expect(book.warnings, isEmpty);
      _unchanged(input, book);
    });

    test('a listed chart has value equality, its typed ids excluded', () {
      final XlsxWorkbook a = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxWorkbook b = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheetChart first = a.sheet('Data').charts.first;
      expect(first, b.sheet('Data').charts.first);
      expect(first.hashCode, b.sheet('Data').charts.first.hashCode);
      expect(first, isNot(a.sheet('Data').charts[1]));
      final XlsxChart typed = first.typed!;
      final XlsxChart fresh = XlsxChart(
        typed.chart,
        typed.anchor,
        name: typed.name,
        description: typed.description,
        language: typed.language,
        autoTitle: typed.autoTitle,
      );
      expect(xlsxChartIds(fresh), isNull);
      expect(fresh, typed);
      expect(fresh.hashCode, typed.hashCode);
    });

    test('a sheet without a drawing has no charts', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_notes'));
      expect(book.sheets.first.charts, isEmpty);
    });

    test('a chart beside a picture: each list holds only its own', () {
      final Uint8List input = _package(
        '${_twoCell(_frame(2, 'rIdC', name: 'Grafik 1', descr: 'Sales'))}'
        '${_oneCellPic(3)}',
        charts: <String, List<int>>{'rIdC': _column},
        picture: true,
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.pictures, hasLength(1));
      expect(sheet.pictures.single.name, 'Picture 1');
      final List<XlsxSheetChart> charts = sheet.charts;
      expect(charts, hasLength(1));
      expect(charts.single.anchor, _anchor);
      expect(charts.single.name, 'Grafik 1');
      expect(charts.single.description, 'Sales');
      expect(charts.single.view!.kind, ChartKind.column);
      expect(charts.single.typed!.language, 'tr-TR');
      expect(charts.single.typed!.autoTitle, isTrue);
      expect(charts.single.typed!.description, 'Sales');
      expect(book.warnings, isEmpty);
      _unchanged(input, book);
    });

    test('a one-cell anchor lists with its size', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          '<xdr:oneCellAnchor>${_marker('from', 1, 2)}'
          '<xdr:ext cx="952500" cy="476250"/>${_frame(2, 'rIdC')}'
          '<xdr:clientData/></xdr:oneCellAnchor>',
          charts: <String, List<int>>{'rIdC': _column},
        ),
      );
      expect(
        book.sheets.single.charts.single.anchor,
        const XlsxOneCellAnchor(XlsxAnchorPoint(2, 1), width: 100, height: 50),
      );
    });

    test('a chart in a group, an absolute anchor or AlternateContent is '
        'kept and unlisted without a warning', () {
      final Uint8List input = _package(
        '<xdr:absoluteAnchor><xdr:pos x="0" y="0"/><xdr:ext cx="1" cy="1"/>'
        '${_frame(2, 'rIdC')}<xdr:clientData/></xdr:absoluteAnchor>'
        '${_twoCell('<xdr:grpSp><xdr:nvGrpSpPr><xdr:cNvPr id="3" name="G"/>'
        '<xdr:cNvGrpSpPr/></xdr:nvGrpSpPr><xdr:grpSpPr/>'
        '${_frame(4, 'rIdC')}</xdr:grpSp>')}'
        '<mc:AlternateContent '
        'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
        '<mc:Choice Requires="a">${_twoCell(_frame(5, 'rIdC'))}</mc:Choice>'
        '</mc:AlternateContent>',
        charts: <String, List<int>>{'rIdC': _column},
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheets.single.charts, isEmpty);
      expect(book.warnings, isEmpty);
      _unchanged(input, book);
    });

    test('a frame of another graphic is no chart and warns nothing', () {
      final Uint8List input = _package(
        _twoCell(
          _frame(
            2,
            'rIdC',
          ).replaceFirst('drawingml/2006/chart">', 'drawingml/2006/table">'),
        ),
        charts: <String, List<int>>{'rIdC': _column},
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheets.single.charts, isEmpty);
      expect(book.warnings, isEmpty);
    });

    test('a dangling r:id is kept, unlisted and warned about once', () {
      final Uint8List input = _package(
        '${_twoCell(_frame(2, 'rIdX'))}${_twoCell(_frame(3, 'rIdC'))}'
        '${_twoCell(_frame(4, 'rIdY'))}',
        charts: <String, List<int>>{'rIdC': _column},
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.charts, hasLength(1));
      expect(sheet.charts.single.name, 'Chart 1');
      expect(_invalid(book, 'chart'), 1);
      expect(book.warnings, hasLength(1));
      _unchanged(input, book);
    });

    test('an r:id of another relationship type is unlisted and warned '
        'about', () {
      final Uint8List input = _package(
        _twoCell(_frame(2, 'rIdP')),
        picture: true,
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheets.single.charts, isEmpty);
      expect(_invalid(book, 'chart'), 1);
      _unchanged(input, book);
    });

    test('a frame without a cNvPr id or an r:id is unlisted and warned '
        'about', () {
      final Uint8List input = _package(
        '${_twoCell(_frame(2, 'rIdC').replaceFirst('id="2" ', ''))}'
        '${_twoCell(_frame(3, 'rIdC').replaceFirst(' r:id="rIdC"', ''))}',
        charts: <String, List<int>>{'rIdC': _column},
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheets.single.charts, isEmpty);
      expect(_invalid(book, 'chart'), 1);
      _unchanged(input, book);
    });

    test('a part over maxChartPartBytes lists without a view, warns and '
        'saves unchanged', () {
      final Uint8List input = _package(
        _twoCell(_frame(2, 'rIdC')),
        charts: <String, List<int>>{'rIdC': _column},
      );
      final XlsxWorkbook book = XlsxWorkbook.open(
        input,
        limits: const XlsxReadLimits(maxChartPartBytes: 100),
      );
      final XlsxSheetChart chart = book.sheets.single.charts.single;
      expect(chart.anchor, _anchor);
      expect(chart.view, isNull);
      expect(chart.typed, isNull);
      expect(book.sheets.single.charts, hasLength(1));
      expect(_invalid(book, 'chart'), 1);
      final Uint8List saved = book.save().bytes;
      expect(readXlsxBytes(saved)['xl/charts/chart1.xml'], _column);
      expect(comparePackages(input, saved, ignoreBookkeeping: true), isEmpty);
    });

    test('a part that is not a chart lists without a view and warns '
        'once', () {
      final Uint8List input = _package(
        '${_twoCell(_frame(2, 'rIdC'))}${_twoCell(_frame(3, 'rIdD'))}',
        charts: <String, List<int>>{
          'rIdC': utf8.encode('<other/>'),
          'rIdD': utf8.encode('<c:chartSpace'),
        },
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final List<XlsxSheetChart> charts = book.sheets.single.charts;
      expect(charts, hasLength(2));
      expect(charts.every((XlsxSheetChart c) => c.view == null), isTrue);
      expect(charts.every((XlsxSheetChart c) => c.typed == null), isTrue);
      expect(book.sheets.single.charts, hasLength(2));
      expect(_invalid(book, 'chart'), 1);
      final Map<String, Uint8List> saved = readXlsxBytes(book.save().bytes);
      expect(saved['xl/charts/chart1.xml'], utf8.encode('<other/>'));
      expect(saved['xl/charts/chart2.xml'], utf8.encode('<c:chartSpace'));
    });

    test('a number that cannot be read warns; the chart lists', () {
      final Uint8List input = _package(
        _twoCell(_frame(2, 'rIdC')),
        charts: <String, List<int>>{
          'rIdC': utf8.encode(
            excelColumnChart.replaceFirst('<c:v>1</c:v>', '<c:v>abc</c:v>'),
          ),
        },
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheetChart chart = book.sheets.single.charts.single;
      expect(chart.view, isNotNull);
      expect(_invalid(book, 'chart'), 1);
      _unchanged(input, book);
    });

    test('a kind the model does not draw lists as a view, without a '
        'warning', () {
      final Uint8List input = _package(
        _twoCell(_frame(2, 'rIdC')),
        charts: <String, List<int>>{
          'rIdC': utf8.encode(
            excelColumnChart
                .replaceFirst('<c:barChart>', '<c:bar3DChart>')
                .replaceFirst('</c:barChart>', '</c:bar3DChart>'),
          ),
        },
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheetChart chart = book.sheets.single.charts.single;
      expect(chart.view!.kind, ChartKind.unsupported);
      expect(chart.typed, isNull);
      expect(book.warnings, isEmpty);
    });

    test("reads in the workbook's date system", () {
      final DrawingChartSpace dated = DrawingChartSpace(
        chart: Chart(
          kind: ChartKind.column,
          series: <ChartSeries>[
            ChartSeries(
              name: ChartData<String>(values: const <String?>[]),
              categories: ChartData<Object>(
                values: <Object?>[DateTime(2026, 1, 1)],
              ),
              values: ChartData<double>(values: const <double?>[1]),
            ),
          ],
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _twoCell(_frame(2, 'rIdC')),
          charts: <String, List<int>>{
            'rIdC': writeDrawingChartSpace(
              dated,
              ChartTheme.office,
              date1904: true,
            ).bytes,
          },
          date1904: true,
        ),
      );
      final XlsxSheetChart chart = book.sheets.single.charts.single;
      expect(chart.view!.series.single.categories.values, <Object?>[
        DateTime(2026, 1, 1),
      ]);
      expect(chart.typed!.chart, dated.chart);
    });

    test("reads scheme colours in the workbook theme's colours", () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _twoCell(_frame(2, 'rIdC')),
          charts: <String, List<int>>{
            'rIdC': utf8.encode(
              excelColumnChart.replaceFirst(
                '<c:spPr><a:solidFill><a:schemeClr val="accent1"/>',
                '<c:spPr><a:solidFill><a:schemeClr val="accent2"/>',
              ),
            ),
          },
          theme:
              '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/'
              '2006/main"><a:themeElements><a:clrScheme name="x">'
              '<a:accent2><a:srgbClr val="FF0000"/></a:accent2>'
              '</a:clrScheme></a:themeElements></a:theme>',
        ),
      );
      final XlsxSheetChart chart = book.sheets.single.charts.single;
      expect(chart.view!.series.single.color!.rgb, 0xFF0000);
    });

    group('after an edit rewrites a chart part', () {
      String values(XlsxSheet sheet) =>
          sheet.charts.first.view!.series.first.values.reference!;
      String typedValues(XlsxSheet sheet) =>
          sheet.charts.first.typed!.chart.series.first.values.reference!;

      test('insertRows on its sheet, its undo and redo', () {
        final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
        final XlsxSheet sheet = book.sheet('Data');
        expect(values(sheet), r'Data!$B$2:$B$5');
        final XlsxChangeSet set = book.transaction(
          () => sheet.insertRows(0, 1),
        );
        expect(values(sheet), r'Data!$B$3:$B$6');
        expect(typedValues(sheet), r'Data!$B$3:$B$6');
        book.undo(set);
        expect(values(sheet), r'Data!$B$2:$B$5');
        book.redo(set);
        expect(values(sheet), r'Data!$B$3:$B$6');
      });

      test('a rewritten part over the cap still lists without a view', () {
        final XlsxWorkbook book = XlsxWorkbook.open(
          _fixture('c1_kinds'),
          limits: const XlsxReadLimits(maxChartPartBytes: 100),
        );
        final XlsxSheet sheet = book.sheet('Data');
        expect(sheet.charts.first.view, isNull);
        sheet.insertRows(0, 1);
        expect(sheet.charts, hasLength(12));
        expect(
          sheet.charts.every((XlsxSheetChart c) => c.view == null),
          isTrue,
        );
      });

      test('renameSheet', () {
        final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
        final XlsxSheet sheet = book.sheet('Data');
        expect(values(sheet), r'Data!$B$2:$B$5');
        book.renameSheet(sheet, 'Veri 2026');
        expect(values(sheet), r"'Veri 2026'!$B$2:$B$5");
      });

      test("another sheet's edit and rename, where the chart's data is", () {
        final DrawingChartSpace space = DrawingChartSpace(
          chart: Chart(
            kind: ChartKind.column,
            series: <ChartSeries>[
              ChartSeries(
                name: ChartData<String>(values: const <String?>[]),
                categories: ChartData<Object>(
                  values: const <Object?>['a', 'b'],
                  reference: r'T!$A$2:$A$3',
                ),
                values: ChartData<double>(
                  values: const <double?>[1, 2],
                  reference: r'T!$B$2:$B$3',
                ),
              ),
            ],
          ),
        );
        final Map<String, Uint8List> parts = readXlsxBytes(
          _package(
            _twoCell(_frame(2, 'rIdC')),
            charts: <String, List<int>>{
              'rIdC': writeDrawingChartSpace(space, ChartTheme.office).bytes,
            },
          ),
        );
        // A second sheet T, the chart's data.
        parts['xl/worksheets/sheet2.xml'] = Uint8List.fromList(
          utf8.encode('<worksheet xmlns="$mainNs"><sheetData/></worksheet>'),
        );
        parts['xl/workbook.xml'] = Uint8List.fromList(
          utf8.encode(
            utf8
                .decode(parts['xl/workbook.xml']!)
                .replaceFirst(
                  '</sheets>',
                  '<sheet name="T" sheetId="2" r:id="rIdT2"/></sheets>',
                ),
          ),
        );
        parts['xl/_rels/workbook.xml.rels'] = Uint8List.fromList(
          utf8.encode(
            utf8
                .decode(parts['xl/_rels/workbook.xml.rels']!)
                .replaceFirst(
                  '</Relationships>',
                  '<Relationship Id="rIdT2" Type="$relNs/worksheet" '
                      'Target="worksheets/sheet2.xml"/></Relationships>',
                ),
          ),
        );
        final XlsxWorkbook book = XlsxWorkbook.open(
          buildZip(<String, List<int>>{...parts}),
        );
        final XlsxSheet host = book.sheet('S');
        expect(values(host), r'T!$B$2:$B$3');
        book.sheet('T').insertRows(0, 2);
        expect(values(host), r'T!$B$4:$B$5');
        book.renameSheet(book.sheet('T'), 'Q1 Sales');
        expect(values(host), r"'Q1 Sales'!$B$4:$B$5");
      });
    });

    test('reading the charts of c1_options and saving changes no chart '
        'part', () {
      final Uint8List input = _fixture('c1_options');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheet("O'Brien").charts, hasLength(6));
      final Uint8List saved = book.save().bytes;
      final Map<String, Uint8List> before = readXlsxBytes(input);
      final Map<String, Uint8List> after = readXlsxBytes(saved);
      for (final String name in before.keys) {
        if (name.startsWith('xl/charts/')) {
          expect(after[name], before[name], reason: name);
        }
      }
    });
  });

  group('addChart', () {
    const XlsxAnchor at = XlsxTwoCellAnchor(
      XlsxAnchorPoint(1, 1),
      XlsxAnchorPoint(16, 9),
    );

    test('adds a part, its relationship and frame to a new workbook', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      final Chart chart = _columns(title: 'Sales');
      sheet.addChart(XlsxChart(chart, at));
      final Uint8List saved = book.save().bytes;
      final Map<String, Uint8List> parts = readXlsxBytes(saved);
      expect(
        xmlDifference(
          parts['xl/charts/chart1.xml']!,
          writeDrawingChartSpace(
            DrawingChartSpace(chart: chart, ids: _ids(1, 2)),
            ChartTheme.office,
          ).bytes,
        ),
        isNull,
      );
      expect(
        _drawingBody(utf8.decode(parts['xl/drawings/drawing1.xml']!)),
        '<xdr:twoCellAnchor>${_marker('from', 1, 1)}${_marker('to', 9, 16)}'
        '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
        '<xdr:cNvPr id="2" name="Chart 1"/><xdr:cNvGraphicFramePr/>'
        '</xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData '
        'uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
        '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/'
        'chart" xmlns:r="$relNs" r:id="rId1"/></a:graphicData></a:graphic>'
        '</xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>',
      );
      final String rels = utf8.decode(
        parts['xl/drawings/_rels/drawing1.xml.rels']!,
      );
      expect(rels, contains('Id="rId1"'));
      expect(rels, contains('Type="$relNs/chart"'));
      expect(rels, contains('Target="../charts/chart1.xml"'));
      expect(
        utf8.decode(parts['[Content_Types].xml']!),
        contains(
          '<Override PartName="/xl/charts/chart1.xml" '
          'ContentType="$drawingChartContentType"/>',
        ),
      );
      final XlsxSheetChart listed = XlsxWorkbook.open(
        saved,
      ).sheet('S').charts.single;
      expect(listed.typed, XlsxChart(chart, at, name: 'Chart 1'));
      _sameIds(xlsxChartIds(listed.typed!)!, _ids(1, 2));
      expect(book.warnings, isEmpty);
    });

    test('a chart given ids keeps them and its theme in its part', () {
      const DrawingChartIds ids = DrawingChartIds(
        categoryAxis: 7,
        valueAxis: 8,
        series: <String>[
          '{00000000-0000-0000-0000-000000000001}',
          '{00000000-0000-0000-0000-000000000002}',
        ],
      );
      final ChartTheme app = ChartTheme.office.copyWith(
        exportColors: ChartExportColors.fixed,
      );
      final Chart chart = _columns(title: 'Ids');
      final XlsxChart given = xlsxChartWithIds(
        XlsxChart(chart, at, theme: app, language: 'tr-TR', autoTitle: true),
        ids,
      );
      expect(xlsxChartIds(given), ids);
      expect(
        given,
        XlsxChart(chart, at, theme: app, language: 'tr-TR', autoTitle: true),
      );
      final XlsxWorkbook book = XlsxWorkbook();
      book.addSheet('S').addChart(given);
      expect(
        readXlsxBytes(book.save().bytes)['xl/charts/chart1.xml'],
        writeDrawingChartSpace(
          DrawingChartSpace(
            chart: chart,
            ids: ids,
            language: 'tr-TR',
            autoTitle: true,
          ),
          app,
        ).bytes,
      );
    });

    test('a one-cell anchor gives its size; without one it throws', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      const XlsxAnchor one = XlsxOneCellAnchor(
        XlsxAnchorPoint(2, 1),
        width: 100,
        height: 50,
      );
      _refused(
        book,
        () => sheet.addChart(
          XlsxChart(
            _columns(),
            const XlsxOneCellAnchor(XlsxAnchorPoint(2, 1), width: 100),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'anchor',
          ),
        ),
      );
      sheet.addChart(XlsxChart(_columns(), one, description: 'Two & one'));
      final String drawing = _text(
        book.save().bytes,
        'xl/drawings/drawing1.xml',
      );
      expect(
        drawing,
        contains(
          '<xdr:oneCellAnchor>${_marker('from', 1, 2)}'
          '<xdr:ext cx="952500" cy="476250"/><xdr:graphicFrame macro="">'
          '<xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="Chart 1" '
          'descr="Two &amp; one"/>',
        ),
      );
      final XlsxSheetChart listed = XlsxWorkbook.open(
        book.save().bytes,
      ).sheet('S').charts.single;
      expect(listed.anchor, one);
      expect(listed.description, 'Two & one');
    });

    test('the editAs of a two-cell anchor follows its resize', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet
        ..addChart(
          XlsxChart(
            _columns(),
            const XlsxTwoCellAnchor(
              XlsxAnchorPoint(0, 0),
              XlsxAnchorPoint(5, 5),
              resize: XlsxPictureResize.move,
            ),
          ),
        )
        ..addChart(
          XlsxChart(
            _columns(),
            const XlsxTwoCellAnchor(
              XlsxAnchorPoint(0, 0),
              XlsxAnchorPoint(5, 5),
              resize: XlsxPictureResize.none,
            ),
          ),
        );
      final String drawing = _text(
        book.save().bytes,
        'xl/drawings/drawing1.xml',
      );
      expect(drawing, contains('<xdr:twoCellAnchor editAs="oneCell">'));
      expect(drawing, contains('<xdr:twoCellAnchor editAs="absolute">'));
    });

    test(
      'a default name is the lowest Chart k no frame of the drawing has',
      () {
        final XlsxWorkbook book = XlsxWorkbook();
        final XlsxSheet sheet = book.addSheet('S');
        sheet
          ..addChart(XlsxChart(_columns(), at))
          ..addChart(XlsxChart(_columns(), at))
          ..removeChartAt(0)
          ..addChart(XlsxChart(_columns(), at));
        expect(sheet.charts.map((XlsxSheetChart c) => c.name), <String>[
          'Chart 2',
          'Chart 1',
        ]);
        sheet.addChart(XlsxChart(_columns(), at, name: 'Chart 3'));
        sheet.addChart(XlsxChart(_columns(), at));
        expect(sheet.charts.map((XlsxSheetChart c) => c.name), <String>[
          'Chart 2',
          'Chart 1',
          'Chart 3',
          'Chart 4',
        ]);
      },
    );

    test('a second chart takes the next part, id and name', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet
        ..addChart(XlsxChart(_columns(), at))
        ..addChart(XlsxChart(_pie(const <double?>[1, 2]), at));
      expect(sheet.charts.map((XlsxSheetChart c) => c.name), <String>[
        'Chart 1',
        'Chart 2',
      ]);
      final Uint8List saved = book.save().bytes;
      expect(_chartParts(saved), <String>{
        'xl/charts/chart1.xml',
        'xl/charts/chart2.xml',
      });
      final String drawing = _text(saved, 'xl/drawings/drawing1.xml');
      expect(drawing, contains('<xdr:cNvPr id="3" name="Chart 2"/>'));
      expect(drawing, contains('r:id="rId2"'));
      expect(
        xlsxChartIds(
          XlsxWorkbook.open(saved).sheet('S').charts[1].typed!,
        )!.series,
        _ids(2, 1).series,
      );
    });

    test('a chart takes no number a content type override of no part names, '
        'so undo keeps that override', () {
      // Seed 11 case 949 of the feature fuzz's long run (C2): an archive
      // mutation renamed `xl/charts/chart1.xml`, leaving its override; the
      // added chart took that name, and undo removed the override with it.
      final XlsxWorkbook source = XlsxWorkbook();
      source.addSheet('S').setCell(0, 0, 1);
      final Map<String, Uint8List> parts = readXlsxBytes(source.save().bytes);
      parts['[Content_Types].xml'] = utf8.encode(
        utf8
            .decode(parts['[Content_Types].xml']!)
            .replaceFirst(
              '</Types>',
              '<Override PartName="/xl/charts/chart1.xml" ContentType="'
                  'application/vnd.openxmlformats-officedocument.'
                  'drawingml.chart+xml"/></Types>',
            ),
      );
      final Uint8List input = buildZipOrdered(<(String, List<int>)>[
        for (final MapEntry<String, Uint8List> e in parts.entries)
          (e.key, e.value),
      ], store: true);
      _undone(input, (XlsxSheet sheet) {
        sheet.addChart(XlsxChart(_columns(), at));
      });
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.first.addChart(XlsxChart(_columns(), at));
      expect(_chartParts(book.save().bytes), <String>{'xl/charts/chart2.xml'});
    });

    test('a listed typed chart added again keeps its ids, as a copy', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheet sheet = book.sheet('Data');
      final XlsxChart first = sheet.charts.first.typed!;
      sheet.addChart(first);
      expect(sheet.charts, hasLength(13));
      final XlsxSheetChart copy = XlsxWorkbook.open(
        book.save().bytes,
      ).sheet('Data').charts.last;
      expect(copy.typed, first);
      expect(xlsxChartIds(copy.typed!), xlsxChartIds(first));
      expect(_chartParts(book.save().bytes), contains('xl/charts/chart13.xml'));
    });

    test('a value that is not finite warns chartValueOmitted once', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.addChart(
        XlsxChart(_pie(const <double?>[1, double.nan, double.infinity]), at),
      );
      expect(_warned(book, XlsxWarningCode.chartValueOmitted), 1);
      final XlsxWarning w = book.warnings.single;
      expect(w.sheet, 'S');
      expect(w.detail, 'Chart 1');
      expect(w.message(), contains('Chart 1'));
    });

    test('characters XML forbids in the text warn '
        'invalidCharactersRemoved', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.addChart(XlsxChart(_columns(title: 'A\u0001B'), at, name: 'K'));
      expect(_warned(book, XlsxWarningCode.invalidCharactersRemoved), 1);
      expect(book.warnings.single.detail, 'K');
      expect(book.warnings.single.message(), contains('K'));
    });

    test('a kind the writer refuses throws and nothing changes', () {
      final Uint8List input = _fixture('c1_kinds');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheet('Data');
      final Chart spark = Chart(
        kind: ChartKind.sparkline,
        series: _columns().series,
      );
      expect(() => sheet.addChart(XlsxChart(spark, at)), throwsArgumentError);
      expect(sheet.charts, hasLength(12));
      expect(changeLogOf(book).hasChanges, isFalse);
      _unchanged(input, book);
    });

    test('a bad anchor or name throws and nothing changes', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      _refused(
        book,
        () => sheet.addChart(
          XlsxChart(
            _columns(),
            const XlsxTwoCellAnchor(
              XlsxAnchorPoint(5, 5),
              XlsxAnchorPoint(1, 1),
            ),
          ),
        ),
        throwsArgumentError,
      );
      _refused(
        book,
        () => sheet.addChart(XlsxChart(_columns(), at, name: 'a\u0000')),
        throwsArgumentError,
      );
      expect(sheet.charts, isEmpty);
    });

    test('beside pictures, shapes and a chart (excel_objects): pictures and '
        'every entry stay', () {
      final ProducerFile file = producerFiles().firstWhere(
        (ProducerFile f) => f.name == 'excel_objects',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(file.bytes);
      final XlsxSheet sheet = book.sheets.first;
      final List<XlsxPicture> pictures = sheet.pictures;
      final List<XlsxSheetChart> charts = sheet.charts;
      final String drawingName = readXlsxBytes(
        file.bytes,
      ).keys.firstWhere((String n) => n.startsWith('xl/drawings/drawing'));
      final String before = _drawingBody(_text(file.bytes, drawingName));
      sheet.addChart(XlsxChart(_columns(), at));
      expect(sheet.pictures, pictures);
      expect(sheet.charts.take(charts.length), charts);
      final Uint8List saved = book.save().bytes;
      final String after = _drawingBody(_text(saved, drawingName));
      expect(after.startsWith(before), isTrue, reason: after);
      for (final String part in readXlsxBytes(file.bytes).keys) {
        if (part.startsWith('xl/charts/') || part.startsWith('xl/media/')) {
          expect(readXlsxBytes(saved)[part], readXlsxBytes(file.bytes)[part]);
        }
      }
      sheet.removeChartAt(sheet.charts.length - 1);
      expect(sheet.pictures, pictures);
      expect(sheet.charts, charts);
      _unchanged(file.bytes, book);
    });
  });

  group('replaceChartAt', () {
    test('an equal chart records nothing', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheet sheet = book.sheet('Data');
      sheet.replaceChartAt(0, sheet.charts.first.typed!.chart);
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('keeps the frame, language, ids and automatic title', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheet sheet = book.sheet('Data');
      final XlsxSheetChart old = sheet.charts.first;
      final Chart chart = old.typed!.chart.copyWith(kind: ChartKind.line);
      sheet.replaceChartAt(0, chart);
      final XlsxSheetChart now = XlsxWorkbook.open(
        book.save().bytes,
      ).sheet('Data').charts.first;
      expect(now.anchor, old.anchor);
      expect(now.name, old.name);
      expect(now.typed!.chart, chart);
      expect(now.typed!.language, old.typed!.language);
      expect(now.typed!.autoTitle, old.typed!.autoTitle);
      expect(xlsxChartIds(now.typed!), xlsxChartIds(old.typed!));
      expect(sheet.charts.first.typed!.chart, chart);
    });

    test("a pie for Excel's column chart drops its style parts", () {
      final Uint8List input = _styledColumn();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      final XlsxSheetChart old = sheet.charts.single;
      final Chart pie = _pie(const <double?>[1, 2, 3]);
      sheet.replaceChartAt(0, pie);
      final Uint8List saved = book.save().bytes;
      // The chart's relationships part stays, empty.
      expect(_chartParts(saved), <String>{
        'xl/charts/chart1.xml',
        'xl/charts/_rels/chart1.xml.rels',
      });
      expect(
        _text(saved, 'xl/charts/_rels/chart1.xml.rels'),
        isNot(contains('<Relationship ')),
      );
      final XlsxSheetChart now = XlsxWorkbook.open(
        saved,
      ).sheets.single.charts.single;
      expect(now.anchor, old.anchor);
      expect(now.typed!.chart, pie);
      expect(now.typed!.language, 'tr-TR');
      expect(
        xlsxChartIds(now.typed!)!.series,
        xlsxChartIds(old.typed!)!.series.take(1),
      );
      expect(_text(saved, 'xl/drawings/drawing1.xml'), contains('rIdC'));
    });

    test('more series take the ids of their positions; a part that showed '
        'a pie takes the axis ids of its number', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_styledColumn());
      final XlsxSheet sheet = book.sheets.single;
      final DrawingChartIds old = xlsxChartIds(sheet.charts.single.typed!)!;
      final int m = old.series.length;
      final Chart more = Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          for (int i = 0; i < m + 2; i++) _columns().series.first,
        ],
      );
      sheet.replaceChartAt(0, more);
      final DrawingChartIds grown = xlsxChartIds(sheet.charts.single.typed!)!;
      expect(grown.categoryAxis, old.categoryAxis);
      expect(grown.valueAxis, old.valueAxis);
      expect(grown.series, <String>[
        ...old.series,
        ..._ids(1, m + 2).series.skip(m),
      ]);
      sheet
        ..replaceChartAt(0, _pie(const <double?>[1]))
        ..replaceChartAt(0, _columns());
      final DrawingChartIds back = xlsxChartIds(sheet.charts.single.typed!)!;
      expect(back.categoryAxis, _ids(1, 2).categoryAxis);
      expect(back.valueAxis, _ids(1, 2).valueAxis);
      expect(back.series, <String>[old.series.first, _ids(1, 2).series[1]]);
    });

    test('the same kind keeps the style parts', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_styledColumn());
      final XlsxSheet sheet = book.sheets.single;
      sheet.replaceChartAt(0, _columns(title: 'New'));
      expect(_chartParts(book.save().bytes), <String>{
        'xl/charts/chart1.xml',
        'xl/charts/_rels/chart1.xml.rels',
        'xl/charts/style1.xml',
        'xl/charts/colors1.xml',
      });
    });

    test('a style part another chart targets stays', () {
      final Map<String, Uint8List> parts = readXlsxBytes(_styledColumn());
      parts['xl/charts/chart2.xml'] = Uint8List.fromList(_column);
      parts['xl/charts/_rels/chart2.xml.rels'] =
          parts['xl/charts/_rels/chart1.xml.rels']!;
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildZip(<String, List<int>>{...parts}),
      );
      book.sheets.single.replaceChartAt(0, _pie(const <double?>[1]));
      final Set<String> left = _chartParts(book.save().bytes);
      expect(left, contains('xl/charts/style1.xml'));
      expect(left, contains('xl/charts/colors1.xml'));
      expect(
        _text(book.save().bytes, 'xl/charts/_rels/chart1.xml.rels'),
        isNot(contains('<Relationship ')),
      );
    });

    test('a part that is not a chart is rebuilt with deterministic ids', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _twoCell(_frame(2, 'rIdC')),
          charts: <String, List<int>>{'rIdC': utf8.encode('<other/>')},
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.charts.single.view, isNull);
      final Chart chart = _columns();
      sheet.replaceChartAt(0, chart, theme: ChartTheme.office);
      final XlsxChart typed = sheet.charts.single.typed!;
      expect(typed.chart, chart);
      expect(typed.language, 'en-US');
      _sameIds(xlsxChartIds(typed)!, _ids(1, 2));
    });

    test('warns about what the writer leaves out', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      book.sheet('Data').replaceChartAt(0, _pie(const <double?>[double.nan]));
      expect(_warned(book, XlsxWarningCode.chartValueOmitted), 1);
      expect(book.warnings.single.detail, 'Chart 1');
    });

    test('a bad index or chart throws and nothing changes', () {
      final Uint8List input = _fixture('c1_kinds');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheet('Data');
      expect(() => sheet.replaceChartAt(12, _columns()), throwsRangeError);
      expect(() => sheet.replaceChartAt(-1, _columns()), throwsRangeError);
      expect(
        () => sheet.replaceChartAt(
          0,
          Chart(kind: ChartKind.sparkline, series: _columns().series),
        ),
        throwsArgumentError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      _unchanged(input, book);
    });
  });

  group('moveChartAt', () {
    test('moves, keeping the frame; an equal anchor records nothing', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheet sheet = book.sheet('Data');
      sheet.moveChartAt(1, sheet.charts[1].anchor);
      expect(changeLogOf(book).hasChanges, isFalse);
      const XlsxAnchor one = XlsxOneCellAnchor(
        XlsxAnchorPoint(40, 2),
        width: 300,
        height: 200,
      );
      final XlsxSheetChart old = sheet.charts[1];
      sheet.moveChartAt(1, one);
      final XlsxSheetChart moved = XlsxWorkbook.open(
        book.save().bytes,
      ).sheet('Data').charts[1];
      expect(moved.anchor, one);
      expect(moved.name, old.name);
      expect(moved.view, old.view);
    });

    test('a one-cell anchor without a size, a bad anchor or index throws '
        'and nothing changes', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheet sheet = book.sheet('Data');
      expect(
        () => sheet.moveChartAt(
          0,
          const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), height: 3),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'anchor',
          ),
        ),
      );
      expect(
        () => sheet.moveChartAt(
          0,
          const XlsxOneCellAnchor(XlsxAnchorPoint(-1, 1), width: 1, height: 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => sheet.moveChartAt(
          12,
          const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 1, height: 1),
        ),
        throwsRangeError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
    });
  });

  group('removeChartAt', () {
    test('removes the frame, the part and the parts only it targets', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_styledColumn(picture: true));
      final XlsxSheet sheet = book.sheets.single;
      final List<XlsxPicture> pictures = sheet.pictures;
      sheet.removeChartAt(0);
      expect(sheet.charts, isEmpty);
      expect(sheet.pictures, pictures);
      final Uint8List saved = book.save().bytes;
      expect(_chartParts(saved), isEmpty);
      final String drawing = _text(saved, 'xl/drawings/drawing1.xml');
      expect(drawing, isNot(contains('graphicFrame')));
      expect(
        _text(saved, 'xl/drawings/_rels/drawing1.xml.rels'),
        isNot(contains('rIdC')),
      );
      expect(
        _text(saved, '[Content_Types].xml'),
        isNot(contains('/xl/charts/')),
      );
      expect(XlsxWorkbook.open(saved).sheets.single.pictures, pictures);
    });

    test('a drawing that goes takes a chart part no frame uses, and its '
        'own parts', () {
      final Uint8List styled = _styledColumn(picture: true);
      final Map<String, Uint8List> parts = readXlsxBytes(styled);
      // The frame goes: the chart relationship stays, used by no entry.
      parts['xl/drawings/drawing1.xml'] = Uint8List.fromList(
        utf8.encode('<xdr:wsDr $_xdr>${_oneCellPic(3)}</xdr:wsDr>'),
      );
      final Uint8List input = buildZip(<String, List<int>>{...parts});
      expect(_chartParts(input), hasLength(4));
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheets.single.charts, isEmpty);
      book.sheets.single.removePictureAt(0);
      final Uint8List saved = book.save().bytes;
      expect(readXlsxBytes(saved).keys, isNot(contains(startsWith('xl/dr'))));
      expect(_chartParts(saved), isEmpty);
      expect(
        _text(saved, '[Content_Types].xml'),
        isNot(contains('/xl/charts/')),
      );
      _undone(input, (XlsxSheet s) => s.removePictureAt(0));
    });

    test('the last entry takes the drawing and <drawing> with it', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_styledColumn());
      final XlsxSheet sheet = book.sheets.single;
      sheet.removeChartAt(0);
      final Uint8List saved = book.save().bytes;
      expect(readXlsxBytes(saved).keys, isNot(contains(startsWith('xl/dr'))));
      expect(
        _text(saved, 'xl/worksheets/sheet1.xml'),
        isNot(contains('<drawing')),
      );
      expect(XlsxWorkbook.open(saved).sheets.single.charts, isEmpty);
    });

    test('removing every chart of c1_kinds removes every chart part', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheet sheet = book.sheet('Data');
      for (int i = 11; i >= 0; i--) {
        sheet.removeChartAt(i);
      }
      final Uint8List saved = book.save().bytes;
      expect(_chartParts(saved), isEmpty);
      expect(readXlsxBytes(saved).keys, isNot(contains(startsWith('xl/dr'))));
    });

    test('a removed chart part leaves the cache of opened parts', () {
      final XlsxSheet sheet = XlsxWorkbook.open(
        _fixture('c1_kinds'),
      ).sheet('Data');
      expect(sheet.charts, hasLength(12));
      expect(openedChartPartCount(sheet), 12);
      sheet.removeChartAt(0);
      expect(openedChartPartCount(sheet), 11);
      while (sheet.charts.isNotEmpty) {
        sheet.removeChartAt(0);
      }
      expect(openedChartPartCount(sheet), 0);
    });

    test('a bad index throws and nothing changes', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      expect(() => book.sheet('Data').removeChartAt(12), throwsRangeError);
      expect(changeLogOf(book).hasChanges, isFalse);
    });
  });

  group('undo of add, replace, move and remove restores the file', () {
    test('add', () {
      _undone(
        buildWorkbook(<String, String>{
          'S': '<worksheet xmlns="$mainNs"><sheetData/></worksheet>',
        }),
        (XlsxSheet s) => s.addChart(XlsxChart(_columns(), _anchor)),
      );
      _undone(_fixture('c1_kinds'), (XlsxSheet s) {
        s
          ..addChart(XlsxChart(_columns(), _anchor))
          ..addChart(s.charts.first.typed!);
      });
      _undone(_styledColumn(picture: true), (XlsxSheet s) {
        s.addChart(XlsxChart(_pie(const <double?>[1]), _anchor));
      });
    });

    test('replace', () {
      _undone(_fixture('c1_kinds'), (XlsxSheet s) {
        s.replaceChartAt(0, _columns(title: 'X'));
      });
      _undone(_styledColumn(), (XlsxSheet s) {
        s.replaceChartAt(0, _pie(const <double?>[1, 2]));
      });
    });

    test('move', () {
      _undone(_fixture('c1_kinds'), (XlsxSheet s) {
        s
          ..moveChartAt(
            0,
            const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 9, height: 9),
          )
          ..moveChartAt(3, _anchor);
      });
    });

    test('remove', () {
      _undone(_fixture('c1_kinds'), (XlsxSheet s) => s.removeChartAt(4));
      _undone(_styledColumn(), (XlsxSheet s) => s.removeChartAt(0));
      _undone(_styledColumn(picture: true), (XlsxSheet s) {
        s.removeChartAt(0);
      });
    });

    test('an add removed in the same breath', () {
      _undone(_styledColumn(), (XlsxSheet s) {
        s
          ..addChart(XlsxChart(_columns(), _anchor))
          ..removeChartAt(1)
          ..removeChartAt(0);
      });
    });

    test('a structural edit after a replace undoes to the replaced chart', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('c1_kinds'));
      final XlsxSheet sheet = book.sheet('Data');
      sheet.insertRows(0, 1);
      final Chart chart = sheet.charts.first.typed!.chart.copyWith(
        title: const ChartTitle(text: 'Replaced'),
      );
      sheet.replaceChartAt(0, chart);
      final XlsxChangeSet insert = book.transaction(
        () => sheet.insertRows(0, 1),
      );
      expect(
        sheet.charts.first.typed!.chart.series.first.values.reference,
        r'Data!$B$4:$B$7',
      );
      book.undo(insert);
      expect(sheet.charts.first.typed!.chart, chart);
    });
  });
}
