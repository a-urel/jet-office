import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';
import 'package:jet_office/src/xlsx/chart.dart' show xlsxChartIds;
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../drawingml/chart/support/excel_charts.dart';
import '../../fixtures/c1_fixtures.dart';
import '../../fixtures/fixtures.dart';
import '../../fixtures/m4_fixtures.dart';
import '../../support/read_xlsx.dart';
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
  return buildZip(<String, List<int>>{...parts});
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
}
