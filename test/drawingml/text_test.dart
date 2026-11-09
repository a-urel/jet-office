import 'dart:convert';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/drawingml/text.dart';
import 'package:jet_office/src/xml/xml_equivalence.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import 'chart/support/excel_charts.dart';

const String _c = 'http://schemas.openxmlformats.org/drawingml/2006/chart';
const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

/// [xml] inside a root that declares `c:` and `a:`.
String _wrap(String xml) => '<root xmlns:c="$_c" xmlns:a="$_a">$xml</root>';

/// Every `c:txPr` block of [part], in document order.
List<String> _txPrBlocks(String part) => <String>[
  for (final Match m in RegExp('<c:txPr>.*?</c:txPr>').allMatches(part))
    m.group(0)!,
];

String _body(ChartTextStyle style, DrawingTextUse use, ChartExportColors mode) {
  final StringBuffer out = StringBuffer();
  writeDrawingTextBody(
    XmlWriter(out),
    style,
    mode: mode,
    language: 'tr-TR',
    use: use,
  );
  return out.toString();
}

String _rich(String text, ChartTextStyle style, ChartExportColors mode) {
  final StringBuffer out = StringBuffer();
  writeDrawingRichText(
    XmlWriter(out),
    text,
    style,
    mode: mode,
    language: 'tr-TR',
  );
  return out.toString();
}

String? _difference(String a, String b) =>
    xmlDifference(utf8.encode(_wrap(a)), utf8.encode(_wrap(b)));

void main() {
  final ChartTheme office = ChartTheme.office;
  final List<String> excel = _txPrBlocks(excelColumnChart);

  test('chart1.xml has the title, two axis and the chart space blocks', () {
    expect(excel, hasLength(4));
    expect(excel[1], excel[2]);
    expect(_txPrBlocks(excelLineChart), excel);
  });

  group('writeDrawingTextBody with the file theme', () {
    test('writes the title block as Excel does', () {
      expect(
        _difference(
          _body(
            office.titleText,
            DrawingTextUse.title,
            ChartExportColors.fileTheme,
          ),
          excel[0],
        ),
        isNull,
      );
    });

    test('writes the axis block as Excel does', () {
      expect(
        _difference(
          _body(
            office.axisLabels,
            DrawingTextUse.axis,
            ChartExportColors.fileTheme,
          ),
          excel[1],
        ),
        isNull,
      );
    });

    test('writes the chart space block as Excel does', () {
      expect(
        _difference(
          _body(
            office.axisLabels,
            DrawingTextUse.chartSpace,
            ChartExportColors.fileTheme,
          ),
          excel[3],
        ),
        isNull,
      );
    });

    test('writes the legend block as Excel does', () {
      final String expected = excel[1].replaceFirst(
        'rot="-60000000"',
        'rot="0"',
      );
      expect(
        _difference(
          _body(
            office.legendText,
            DrawingTextUse.legend,
            ChartExportColors.fileTheme,
          ),
          expected,
        ),
        isNull,
      );
    });

    test('writes the data label block as Excel does', () {
      final String expected = excel[1]
          .replaceFirst(
            RegExp('<a:bodyPr[^>]*/>'),
            '<a:bodyPr rot="0" spcFirstLastPara="1" vertOverflow="ellipsis" '
            'vert="horz" wrap="square" lIns="38100" tIns="19050" rIns="38100" '
            'bIns="19050" anchor="ctr" anchorCtr="1"><a:spAutoFit/></a:bodyPr>',
          )
          // Excel's data labels are `tx1` 75000 and 25000 (`404040`;
          // chart_reference.xlsx, charts 20 and 21), not the axis labels' grey.
          .replaceFirst('<a:lumMod val="65000"/>', '<a:lumMod val="75000"/>')
          .replaceFirst('<a:lumOff val="35000"/>', '<a:lumOff val="25000"/>');
      expect(
        _difference(
          _body(
            office.dataLabels,
            DrawingTextUse.dataLabel,
            ChartExportColors.fileTheme,
          ),
          expected,
        ),
        isNull,
      );
    });

    test('writes an axis title block without spc, turned when vertical', () {
      // chart_reference.xlsx, chart 17: the axis titles' `a:defRPr` has no
      // `spc`, the vertical one's `a:bodyPr` has `rot="-5400000"`.
      final String flat = _body(
        office.axisLabels,
        DrawingTextUse.axisTitle,
        ChartExportColors.fileTheme,
      );
      expect(flat, isNot(contains('spc="0"')));
      expect(flat, contains('<a:bodyPr rot="0" '));
      final StringBuffer out = StringBuffer();
      writeDrawingTextBody(
        XmlWriter(out),
        office.axisLabels,
        mode: ChartExportColors.fileTheme,
        language: 'tr-TR',
        use: DrawingTextUse.axisTitle,
        vertical: true,
      );
      expect(out.toString(), contains('<a:bodyPr rot="-5400000" '));
      final StringBuffer title = StringBuffer();
      writeDrawingTextBody(
        XmlWriter(title),
        office.titleText,
        mode: ChartExportColors.fileTheme,
        language: 'tr-TR',
        use: DrawingTextUse.title,
        vertical: true,
      );
      expect(title.toString(), contains('<a:bodyPr rot="0" '));
      expect(title.toString(), contains('spc="0"'));
    });

    test('writes the size in hundredths of a point and bold as b', () {
      final String xml = _body(
        office.axisLabels.copyWith(size: 10.5, bold: true),
        DrawingTextUse.axis,
        ChartExportColors.fileTheme,
      );
      expect(xml, contains('sz="1050" b="1"'));
    });
  });

  group('writeDrawingTextBody with fixed colours', () {
    test('writes the colour as srgbClr and the font by name', () {
      final String xml = _body(
        office.axisLabels,
        DrawingTextUse.axis,
        ChartExportColors.fixed,
      );
      expect(xml, contains('<a:solidFill><a:srgbClr val="595959"/>'));
      expect(xml, contains('<a:latin typeface="Aptos Narrow"/>'));
      expect(xml, isNot(contains('+mn-')));
      expect(xml, isNot(contains('schemeClr')));
      final String expected = excel[1]
          .replaceFirst(
            '<a:schemeClr val="tx1"><a:lumMod val="65000"/>'
                '<a:lumOff val="35000"/></a:schemeClr>',
            '<a:srgbClr val="595959"/>',
          )
          .replaceFirst(
            '<a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/>'
                '<a:cs typeface="+mn-cs"/>',
            '<a:latin typeface="Aptos Narrow"/>',
          );
      expect(_difference(xml, expected), isNull);
    });

    test('escapes the font name', () {
      final String xml = _body(
        office.axisLabels.copyWith(fontFamily: 'A&B "C"'),
        DrawingTextUse.axis,
        ChartExportColors.fixed,
      );
      expect(xml, contains('typeface="A&amp;B &quot;C&quot;"'));
    });
  });

  group('writeDrawingRichText', () {
    test('writes one paragraph of a run per line', () {
      final String xml = _rich(
        'Satışlar\n2026',
        office.titleText,
        ChartExportColors.fileTheme,
      );
      final String title = excel[0];
      final String bodyPr = RegExp('<a:bodyPr[^>]*/>').firstMatch(title)![0]!;
      final String pPr = RegExp('<a:pPr>.*</a:pPr>').firstMatch(title)![0]!;
      expect(
        _difference(
          xml,
          '<c:rich>$bodyPr<a:lstStyle/>'
          '<a:p>$pPr<a:r><a:rPr lang="tr-TR"/><a:t>Satışlar</a:t></a:r></a:p>'
          '<a:p>$pPr<a:r><a:rPr lang="tr-TR"/><a:t>2026</a:t></a:r></a:p>'
          '</c:rich>',
        ),
        isNull,
      );
    });

    test('splits on CR LF, CR and LF and keeps empty lines', () {
      final String xml = _rich(
        'a\r\nb\rc\n\nd',
        office.titleText,
        ChartExportColors.fileTheme,
      );
      final List<String> paragraphs = <String>[
        for (final Match m in RegExp('<a:p>.*?</a:p>').allMatches(xml))
          m.group(0)!,
      ];
      expect(paragraphs, hasLength(5));
      expect(paragraphs[3], isNot(contains('<a:r>')));
      expect(paragraphs[3], contains('<a:endParaRPr lang="tr-TR"/>'));
      expect(paragraphs[4], contains('<a:t>d</a:t>'));
    });

    test('an axis title has no spc and turns when vertical', () {
      final StringBuffer out = StringBuffer();
      writeDrawingRichText(
        XmlWriter(out),
        'Tutar',
        office.axisLabels,
        mode: ChartExportColors.fileTheme,
        language: 'tr-TR',
        use: DrawingTextUse.axisTitle,
        vertical: true,
      );
      expect(out.toString(), isNot(contains('spc=')));
      expect(out.toString(), contains('<a:bodyPr rot="-5400000" '));
      expect(
        _rich('T', office.titleText, ChartExportColors.fileTheme),
        contains('spc="0"'),
      );
    });

    test('another use throws an ArgumentError', () {
      expect(
        () => writeDrawingRichText(
          XmlWriter(StringBuffer()),
          'T',
          office.titleText,
          mode: ChartExportColors.fileTheme,
          language: 'tr-TR',
          use: DrawingTextUse.legend,
        ),
        throwsArgumentError,
      );
    });

    test('escapes markup and is well formed', () {
      final String xml = _rich(
        '<a> & "b"',
        office.titleText,
        ChartExportColors.fixed,
      );
      expect(xml, contains('<a:t>&lt;a&gt; &amp; "b"</a:t>'));
      final XmlPullReader r = XmlPullReader(_wrap(xml));
      while (r.next()) {}
      expect(xml, contains('<a:srgbClr val="595959"/>'));
    });
  });
}
