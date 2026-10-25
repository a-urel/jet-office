import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _sheet1 = 'xl/worksheets/sheet1.xml';
const String _styles = 'xl/styles.xml';

/// The parts of a workbook in which [setup] adds conditional formats to the
/// sheet `S`, which holds one row.
Map<String, String> _book(void Function(XlsxSheetWriter sheet) setup) {
  final XlsxWriter book = XlsxWriter();
  final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>['x']);
  setup(sheet);
  final XlsxResult result = book.close();
  expect(checkXlsx(result.bytes), isEmpty);
  return readXlsx(result.bytes);
}

/// Every `conditionalFormatting` element of sheet 1, joined, or '' when
/// there is none.
String _formats(void Function(XlsxSheetWriter sheet) setup) {
  final String xml = _book(setup)[_sheet1]!;
  final RegExpMatch? m = RegExp(
    '<conditionalFormatting.*</conditionalFormatting>',
  ).firstMatch(xml);
  return m?.group(0) ?? '';
}

/// The `dxfs` element of `styles.xml` after [setup].
String _dxfs(void Function(XlsxSheetWriter sheet) setup) {
  final String xml = _book(setup)[_styles]!;
  return RegExp('<dxfs count="0"/>|<dxfs.*?</dxfs>').firstMatch(xml)!.group(0)!;
}

/// The one `cfRule` of a format on [range] holding [rule].
String _rule(XlsxConditionalRule rule, {String range = 'A1'}) {
  final String xml = _formats(
    (XlsxSheetWriter s) => s.conditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse(range)],
        <XlsxConditionalRule>[rule],
      ),
    ),
  );
  final String start = '<conditionalFormatting sqref="$range">';
  expect(xml, startsWith(start));
  return xml.substring(
    start.length,
    xml.length - '</conditionalFormatting>'.length,
  );
}

/// Expects registering [rule] on `A1` to throw an [ArgumentError] named
/// [field] and to record nothing.
void _rejects(XlsxConditionalRule rule, String field) {
  _rejectsFormat(
    XlsxConditionalFormat(<XlsxRange>[_a1], <XlsxConditionalRule>[rule]),
    field,
  );
}

void _rejectsFormat(XlsxConditionalFormat format, String field) {
  final String xml = _formats((XlsxSheetWriter s) {
    expect(
      () => s.conditionalFormat(format),
      throwsA(
        isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', field),
      ),
    );
  });
  expect(xml, '');
}

final XlsxRange _a1 = XlsxRange.parse('A1');
final XlsxStyle _red = XlsxStyle(
  font: XlsxFont(color: XlsxColor.hex('9C0006')),
  fill: XlsxFill.solid(XlsxColor.hex('FFC7CE')),
);
final XlsxStyle _green = XlsxStyle(
  fill: XlsxFill.solid(XlsxColor.hex('C6EFCE')),
);

void main() {
  group('cell value', () {
    test('writes dxfId and priority (Quds wrote neither)', () {
      expect(
        _formats(
          (XlsxSheetWriter s) => s.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[XlsxRange.parse('B2:B20')],
              <XlsxConditionalRule>[
                XlsxCellValueRule(
                  XlsxComparison.greaterThan,
                  '10',
                  style: _red,
                ),
              ],
            ),
          ),
        ),
        '<conditionalFormatting sqref="B2:B20"><cfRule type="cellIs" '
        'dxfId="0" priority="1" operator="greaterThan"><formula>10</formula>'
        '</cfRule></conditionalFormatting>',
      );
    });
    test('the style becomes a dxf in styles.xml', () {
      expect(
        _dxfs(
          (XlsxSheetWriter s) => s.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[_a1],
              <XlsxConditionalRule>[
                XlsxCellValueRule(XlsxComparison.equal, '1', style: _red),
              ],
            ),
          ),
        ),
        '<dxfs count="1"><dxf><font><color rgb="FF9C0006"/></font>'
        '<fill><patternFill><bgColor rgb="FFFFC7CE"/></patternFill></fill>'
        '</dxf></dxfs>',
      );
    });
    test('between writes both formulas, in order', () {
      expect(
        _rule(
          const XlsxCellValueRule(XlsxComparison.between, '1', formula2: '9'),
        ),
        '<cfRule type="cellIs" priority="1" operator="between">'
        '<formula>1</formula><formula>9</formula></cfRule>',
      );
    });
    test('a rule without a style writes no dxfId; stopIfTrue is written', () {
      expect(
        _rule(
          const XlsxCellValueRule(
            XlsxComparison.lessThan,
            r'=$B$1',
            stopIfTrue: true,
          ),
        ),
        '<cfRule type="cellIs" priority="1" stopIfTrue="1" '
        r'operator="lessThan"><formula>$B$1</formula></cfRule>',
      );
    });
    test('formula text is escaped', () {
      expect(
        _rule(const XlsxCellValueRule(XlsxComparison.equal, '"a<b&_x0041_"')),
        contains('<formula>"a&lt;b&amp;_x005F_x0041_"</formula>'),
      );
    });
    test('formula2 for a one-operand comparison throws', () {
      _rejects(
        const XlsxCellValueRule(XlsxComparison.greaterThan, '1', formula2: '2'),
        'rules[0].formula2',
      );
    });
    test('between or notBetween without formula2 throws', () {
      _rejects(
        const XlsxCellValueRule(XlsxComparison.between, '1'),
        'rules[0].formula2',
      );
      _rejects(
        const XlsxCellValueRule(XlsxComparison.notBetween, '1'),
        'rules[0].formula2',
      );
    });
    test('an empty formula throws', () {
      _rejects(
        const XlsxCellValueRule(XlsxComparison.equal, '='),
        'rules[0].formula1',
      );
    });
  });

  group('priorities', () {
    test('run from 1 across several conditionalFormat calls', () {
      final String xml = _formats((XlsxSheetWriter s) {
        for (final String range in <String>['A1:A5', 'B1:B5']) {
          s.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[XlsxRange.parse(range)],
              <XlsxConditionalRule>[
                const XlsxExpressionRule('TRUE'),
                const XlsxExpressionRule('FALSE'),
              ],
            ),
          );
        }
      });
      expect(
        RegExp(
          r'priority="(\d+)"',
        ).allMatches(xml).map((Match m) => m.group(1)),
        <String>['1', '2', '3', '4'],
      );
      expect(xml, contains('</conditionalFormatting><conditionalFormatting'));
    });
    test('a rejected format takes no priority', () {
      final String xml = _formats((XlsxSheetWriter s) {
        expect(
          () => s.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[_a1],
              <XlsxConditionalRule>[
                const XlsxExpressionRule('TRUE'),
                const XlsxTopBottomRule(rank: 0),
              ],
            ),
          ),
          throwsArgumentError,
        );
        s.conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[_a1],
            <XlsxConditionalRule>[const XlsxExpressionRule('TRUE')],
          ),
        );
      });
      expect(xml, contains('priority="1"'));
      expect(xml, isNot(contains('priority="2"')));
    });
  });

  group('expression', () {
    test('writes type expression and its formula', () {
      expect(
        _rule(XlsxExpressionRule(r'=MOD(ROW(),2)=0', style: _green)),
        '<cfRule type="expression" dxfId="0" priority="1">'
        '<formula>MOD(ROW(),2)=0</formula></cfRule>',
      );
    });
    test('an empty formula throws', () {
      _rejects(const XlsxExpressionRule(''), 'rules[0].formula');
    });
  });

  group('text', () {
    test('contains doubles a quote in the formula (Review Focus 2)', () {
      expect(
        _rule(
          XlsxTextRule(XlsxTextOperator.contains, 'a"b', style: _red),
          range: 'C2:C9',
        ),
        '<cfRule type="containsText" dxfId="0" priority="1" '
        'operator="containsText" text="a&quot;b">'
        '<formula>NOT(ISERROR(SEARCH("a""b",C2)))</formula></cfRule>',
      );
    });
    test('notContains, beginsWith and endsWith', () {
      expect(
        _rule(
          const XlsxTextRule(XlsxTextOperator.notContains, 't'),
          range: 'C2:C9',
        ),
        '<cfRule type="notContainsText" priority="1" operator="notContains" '
        'text="t"><formula>ISERROR(SEARCH("t",C2))</formula></cfRule>',
      );
      expect(
        _rule(
          const XlsxTextRule(XlsxTextOperator.beginsWith, 't'),
          range: 'C2:C9',
        ),
        '<cfRule type="beginsWith" priority="1" operator="beginsWith" '
        'text="t"><formula>LEFT(C2,LEN("t"))="t"</formula></cfRule>',
      );
      expect(
        _rule(
          const XlsxTextRule(XlsxTextOperator.endsWith, 't'),
          range: 'C2:C9',
        ),
        '<cfRule type="endsWith" priority="1" operator="endsWith" '
        'text="t"><formula>RIGHT(C2,LEN("t"))="t"</formula></cfRule>',
      );
    });
    test('the reference is the top-left cell of the first range', () {
      final String xml = _formats(
        (XlsxSheetWriter s) => s.conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[XlsxRange.parse('D5:E9'), _a1],
            <XlsxConditionalRule>[
              const XlsxTextRule(XlsxTextOperator.contains, 'x'),
            ],
          ),
        ),
      );
      expect(xml, contains('sqref="D5:E9 A1"'));
      expect(xml, contains('SEARCH("x",D5)'));
    });
    test('an _xHHHH_ look-alike is escaped in text and formula', () {
      final String rule = _rule(
        const XlsxTextRule(XlsxTextOperator.contains, '_x0041_&'),
      );
      expect(rule, contains('text="_x005F_x0041_&amp;"'));
      expect(rule, contains('SEARCH("_x005F_x0041_&amp;",A1)'));
    });
    test('a character XML forbids throws', () {
      _rejects(
        const XlsxTextRule(XlsxTextOperator.contains, 'a\u0001'),
        'rules[0].text',
      );
    });
    test('text too long for the formula throws', () {
      _rejects(
        XlsxTextRule(XlsxTextOperator.contains, 'x' * 8192),
        'rules[0].text',
      );
    });
  });

  group('duplicates', () {
    test('write duplicateValues and uniqueValues (Quds wrote cellIs)', () {
      expect(
        _rule(XlsxDuplicateRule(style: _red)),
        '<cfRule type="duplicateValues" dxfId="0" priority="1"/>',
      );
      expect(
        _rule(const XlsxDuplicateRule(unique: true)),
        '<cfRule type="uniqueValues" priority="1"/>',
      );
    });
  });

  group('top and bottom', () {
    test('writes percent, bottom and rank in schema order', () {
      expect(
        _rule(
          XlsxTopBottomRule(rank: 5, percent: true, bottom: true, style: _red),
        ),
        '<cfRule type="top10" dxfId="0" priority="1" percent="1" bottom="1" '
        'rank="5"/>',
      );
    });
    test('the defaults are the top 10 items', () {
      expect(
        _rule(const XlsxTopBottomRule()),
        '<cfRule type="top10" priority="1" rank="10"/>',
      );
    });
    test('a rank of 1 to 1,000 is allowed, others throw', () {
      expect(XlsxLimits.maxTopBottomRank, 1000);
      expect(_rule(const XlsxTopBottomRule(rank: 1)), contains('rank="1"'));
      expect(
        _rule(const XlsxTopBottomRule(rank: 1000)),
        contains('rank="1000"'),
      );
      _rejects(const XlsxTopBottomRule(rank: 0), 'rules[0].rank');
      _rejects(const XlsxTopBottomRule(rank: 1001), 'rules[0].rank');
    });
    test('a percent rank of 1 to 100 is allowed, others throw', () {
      expect(
        _rule(const XlsxTopBottomRule(rank: 100, percent: true)),
        contains('rank="100"'),
      );
      _rejects(
        const XlsxTopBottomRule(rank: 101, percent: true),
        'rules[0].rank',
      );
      _rejects(
        const XlsxTopBottomRule(rank: 0, percent: true),
        'rules[0].rank',
      );
    });
  });

  group('average', () {
    test('writes aboveAverage, stdDev and equalAverage in schema order', () {
      expect(
        _rule(
          XlsxAverageRule(
            above: false,
            orEqual: true,
            standardDeviations: 1,
            style: _red,
          ),
        ),
        '<cfRule type="aboveAverage" dxfId="0" priority="1" '
        'aboveAverage="0" stdDev="1" equalAverage="1"/>',
      );
    });
    test('the defaults write the type only', () {
      expect(
        _rule(const XlsxAverageRule()),
        '<cfRule type="aboveAverage" priority="1"/>',
      );
    });
    test('standard deviations of 1 to 3 are allowed, others throw', () {
      expect(
        _rule(const XlsxAverageRule(standardDeviations: 3)),
        contains('stdDev="3"'),
      );
      _rejects(
        const XlsxAverageRule(standardDeviations: 0),
        'rules[0].standardDeviations',
      );
      _rejects(
        const XlsxAverageRule(standardDeviations: 4),
        'rules[0].standardDeviations',
      );
    });
  });

  group('color scale', () {
    test('three points write three cfvo, then three colors', () {
      expect(
        _rule(
          XlsxColorScale(
            <XlsxCfValue>[
              const XlsxCfValue.min(),
              XlsxCfValue.percentile(50),
              const XlsxCfValue.max(),
            ],
            <XlsxColor>[
              XlsxColor.hex('F8696B'),
              XlsxColor.hex('FFEB84'),
              XlsxColor.hex('63BE7B'),
            ],
          ),
        ),
        '<cfRule type="colorScale" priority="1"><colorScale>'
        '<cfvo type="min"/><cfvo type="percentile" val="50"/>'
        '<cfvo type="max"/><color rgb="FFF8696B"/><color rgb="FFFFEB84"/>'
        '<color rgb="FF63BE7B"/></colorScale></cfRule>',
      );
    });
    test('two points are allowed', () {
      expect(
        _rule(
          XlsxColorScale(
            <XlsxCfValue>[XlsxCfValue.number(0), XlsxCfValue.number(1.5)],
            <XlsxColor>[XlsxColor.hex('FFFFFF'), XlsxColor.hex('000000')],
          ),
        ),
        contains(
          '<cfvo type="num" val="0"/><cfvo type="num" val="1.5"/>'
          '<color rgb="FFFFFFFF"/><color rgb="FF000000"/>',
        ),
      );
    });
    test('other than 2 or 3 points throw', () {
      _rejects(
        XlsxColorScale(
          <XlsxCfValue>[const XlsxCfValue.min()],
          <XlsxColor>[XlsxColor.hex('FFFFFF')],
        ),
        'rules[0].points',
      );
      _rejects(
        XlsxColorScale(
          List<XlsxCfValue>.filled(4, const XlsxCfValue.min()),
          List<XlsxColor>.filled(4, XlsxColor.hex('FFFFFF')),
        ),
        'rules[0].points',
      );
    });
    test('point and color counts that differ throw', () {
      _rejects(
        XlsxColorScale(
          <XlsxCfValue>[const XlsxCfValue.min(), const XlsxCfValue.max()],
          <XlsxColor>[XlsxColor.hex('FFFFFF')],
        ),
        'rules[0].colors',
      );
    });
    test('an invalid color throws', () {
      _rejects(
        XlsxColorScale(
          <XlsxCfValue>[const XlsxCfValue.min(), const XlsxCfValue.max()],
          <XlsxColor>[XlsxColor.hex('FFFFFF'), const XlsxColor.theme(99)],
        ),
        'rules[0].colors[1]',
      );
    });
  });

  group('data bar', () {
    test('the defaults write min, max and the color only', () {
      expect(
        _rule(XlsxDataBar(color: XlsxColor.hex('638EC6'))),
        '<cfRule type="dataBar" priority="1"><dataBar><cfvo type="min"/>'
        '<cfvo type="max"/><color rgb="FF638EC6"/></dataBar></cfRule>',
      );
    });
    test('lengths and showValue are written when they differ', () {
      expect(
        _rule(
          XlsxDataBar(
            min: XlsxCfValue.number(0),
            max: XlsxCfValue.percent(80),
            color: XlsxColor.hex('638EC6'),
            showValue: false,
            minLength: 0,
            maxLength: 100,
          ),
        ),
        '<cfRule type="dataBar" priority="1">'
        '<dataBar minLength="0" maxLength="100" showValue="0">'
        '<cfvo type="num" val="0"/><cfvo type="percent" val="80"/>'
        '<color rgb="FF638EC6"/></dataBar></cfRule>',
      );
    });
    test('minLength above maxLength, or outside 0 to 100, throws', () {
      final XlsxColor c = XlsxColor.hex('638EC6');
      _rejects(
        XlsxDataBar(color: c, minLength: 50, maxLength: 40),
        'rules[0].minLength',
      );
      _rejects(XlsxDataBar(color: c, minLength: -1), 'rules[0].minLength');
      _rejects(XlsxDataBar(color: c, maxLength: 101), 'rules[0].maxLength');
    });
    test('an invalid cfvo throws', () {
      _rejects(
        XlsxDataBar(
          color: XlsxColor.hex('638EC6'),
          max: XlsxCfValue.percent(101),
        ),
        'rules[0].max',
      );
    });
  });

  group('icon set', () {
    test("three arrows write Excel's default thresholds", () {
      expect(
        _rule(XlsxIconSet(XlsxIconSetType.threeArrows)),
        '<cfRule type="iconSet" priority="1"><iconSet iconSet="3Arrows">'
        '<cfvo type="percent" val="0"/><cfvo type="percent" val="33"/>'
        '<cfvo type="percent" val="67"/></iconSet></cfRule>',
      );
    });
    test('four and five icons have their own default thresholds', () {
      String values(String rule) => RegExp(
        r'val="(\d+)"',
      ).allMatches(rule).map((Match m) => m.group(1)).join(',');
      expect(
        values(_rule(XlsxIconSet(XlsxIconSetType.fourRating))),
        '0,25,50,75',
      );
      expect(
        values(_rule(XlsxIconSet(XlsxIconSetType.fiveQuarters))),
        '0,20,40,60,80',
      );
    });
    test('given thresholds, reverse, showValue and gte are written', () {
      expect(
        _rule(
          XlsxIconSet(
            XlsxIconSetType.threeFlags,
            thresholds: <XlsxCfValue>[
              XlsxCfValue.number(0),
              XlsxCfValue.number(10, greaterOrEqual: false),
              const XlsxCfValue.formula(r'=$B$1'),
            ],
            reverse: true,
            showValue: false,
          ),
        ),
        '<cfRule type="iconSet" priority="1">'
        '<iconSet iconSet="3Flags" showValue="0" reverse="1">'
        '<cfvo type="num" val="0"/><cfvo type="num" val="10" gte="0"/>'
        r'<cfvo type="formula" val="$B$1"/></iconSet></cfRule>',
      );
    });
    test('thresholds whose count differs from the icons throw', () {
      _rejects(
        XlsxIconSet(
          XlsxIconSetType.fourArrows,
          thresholds: <XlsxCfValue>[
            XlsxCfValue.percent(0),
            XlsxCfValue.percent(50),
          ],
        ),
        'rules[0].thresholds',
      );
    });
    test('the 17 Excel 2007 sets have their XML names and icon counts', () {
      expect(
        <String>[
          for (final XlsxIconSetType t in XlsxIconSetType.values)
            '${t.xmlName}/${t.iconCount}',
        ],
        <String>[
          '3Arrows/3',
          '3ArrowsGray/3',
          '3Flags/3',
          '3TrafficLights1/3',
          '3TrafficLights2/3',
          '3Signs/3',
          '3Symbols/3',
          '3Symbols2/3',
          '4Arrows/4',
          '4ArrowsGray/4',
          '4RedToBlack/4',
          '4Rating/4',
          '4TrafficLights/4',
          '5Arrows/5',
          '5ArrowsGray/5',
          '5Rating/5',
          '5Quarters/5',
        ],
      );
    });
  });

  group('cfvo', () {
    test('non-finite numbers throw', () {
      for (final double bad in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        _rejects(
          XlsxDataBar(
            color: XlsxColor.hex('638EC6'),
            min: XlsxCfValue.number(bad),
          ),
          'rules[0].min',
        );
      }
    });
    test('percents and percentiles outside 0 to 100 throw', () {
      for (final XlsxCfValue bad in <XlsxCfValue>[
        XlsxCfValue.percent(-1),
        XlsxCfValue.percent(100.5),
        XlsxCfValue.percentile(-0.5),
        XlsxCfValue.percentile(101),
      ]) {
        _rejects(
          XlsxColorScale(
            <XlsxCfValue>[bad, const XlsxCfValue.max()],
            <XlsxColor>[XlsxColor.hex('FFFFFF'), XlsxColor.hex('000000')],
          ),
          'rules[0].points[0]',
        );
      }
    });
    test('a percent given as a reference is not range-checked', () {
      expect(
        _rule(
          XlsxDataBar(
            color: XlsxColor.hex('638EC6'),
            min: const XlsxCfValue(XlsxCfValueType.percent, value: r'$A$1'),
          ),
        ),
        contains(r'<cfvo type="percent" val="$A$1"/>'),
      );
    });
    test('a type that needs a value throws without one', () {
      _rejects(
        XlsxDataBar(
          color: XlsxColor.hex('638EC6'),
          max: const XlsxCfValue(XlsxCfValueType.number),
        ),
        'rules[0].max',
      );
    });
    test('a min or max value read from a file is written', () {
      expect(
        _rule(
          XlsxDataBar(
            color: XlsxColor.hex('638EC6'),
            min: const XlsxCfValue(XlsxCfValueType.min, value: '0'),
          ),
        ),
        contains('<cfvo type="min" val="0"/>'),
      );
    });
  });

  group('format', () {
    test('no ranges or no rules throw', () {
      _rejectsFormat(
        XlsxConditionalFormat(<XlsxRange>[], <XlsxConditionalRule>[
          const XlsxExpressionRule('TRUE'),
        ]),
        'ranges',
      );
      _rejectsFormat(
        XlsxConditionalFormat(<XlsxRange>[_a1], <XlsxConditionalRule>[]),
        'rules',
      );
    });
    test('a range outside the sheet throws', () {
      _rejectsFormat(
        XlsxConditionalFormat(
          <XlsxRange>[_a1, const XlsxRange(0, 16384)],
          <XlsxConditionalRule>[const XlsxExpressionRule('TRUE')],
        ),
        'ranges[1]',
      );
    });
    test('formats whose ranges overlap are allowed', () {
      final String xml = _formats((XlsxSheetWriter s) {
        s
          ..conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[XlsxRange.parse('A1:B5')],
              <XlsxConditionalRule>[const XlsxExpressionRule('TRUE')],
            ),
          )
          ..conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[XlsxRange.parse('B2:C9')],
              <XlsxConditionalRule>[const XlsxDuplicateRule()],
            ),
          );
      });
      expect(xml, contains('sqref="A1:B5"'));
      expect(xml, contains('sqref="B2:C9"'));
    });
    test('equal styles share one dxf', () {
      final String xml = _formats(
        (XlsxSheetWriter s) => s.conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[_a1],
            <XlsxConditionalRule>[
              XlsxDuplicateRule(style: _red),
              XlsxDuplicateRule(unique: true, style: _green),
              XlsxExpressionRule('TRUE', style: _red),
            ],
          ),
        ),
      );
      expect(
        RegExp(r'dxfId="(\d+)"').allMatches(xml).map((Match m) => m.group(1)),
        <String>['0', '1', '0'],
      );
    });
    test('after the sheet is finished it throws StateError', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('A')..row(<Object?>[1]);
      book.addSheet('B');
      expect(
        () => first.conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[_a1],
            <XlsxConditionalRule>[const XlsxExpressionRule('TRUE')],
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('atomicity (Review Focus 4)', () {
    test('an invalid third rule records nothing and registers no dxf', () {
      final Map<String, String> parts = _book((XlsxSheetWriter s) {
        expect(
          () => s.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[_a1],
              <XlsxConditionalRule>[
                XlsxDuplicateRule(style: _red),
                XlsxExpressionRule('TRUE', style: _green),
                const XlsxAverageRule(standardDeviations: 9),
              ],
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'rules[2].standardDeviations',
            ),
          ),
        );
      });
      expect(parts[_sheet1], isNot(contains('conditionalFormatting')));
      expect(parts[_styles], contains('<dxfs count="0"/>'));
    });
    test('an invalid style in the third rule registers no dxf', () {
      final Map<String, String> parts = _book((XlsxSheetWriter s) {
        expect(
          () => s.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[_a1],
              <XlsxConditionalRule>[
                XlsxDuplicateRule(style: _red),
                XlsxExpressionRule('TRUE', style: _green),
                const XlsxExpressionRule(
                  'TRUE',
                  style: XlsxStyle(font: XlsxFont(size: 12)),
                ),
              ],
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'rules[2].style.size',
            ),
          ),
        );
      });
      expect(parts[_sheet1], isNot(contains('conditionalFormatting')));
      expect(parts[_styles], contains('<dxfs count="0"/>'));
    });
    test('a number format the dxf table cannot hold registers nothing', () {
      final Map<String, String> parts = _book((XlsxSheetWriter s) {
        expect(
          () => s.conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[_a1],
              <XlsxConditionalRule>[
                const XlsxDuplicateRule(
                  style: XlsxStyle(numFmt: XlsxNumFmt.custom('0.0#')),
                ),
                const XlsxExpressionRule(
                  'TRUE',
                  style: XlsxStyle(numFmt: XlsxNumFmt.builtin(30)),
                ),
              ],
            ),
          ),
          throwsArgumentError,
        );
      });
      expect(parts[_sheet1], isNot(contains('conditionalFormatting')));
      expect(parts[_styles], contains('<dxfs count="0"/>'));
      expect(parts[_styles], isNot(contains('0.0#')));
    });
  });

  group('value semantics', () {
    test('equal formats are equal and hash alike', () {
      XlsxConditionalFormat make() => XlsxConditionalFormat(
        <XlsxRange>[_a1],
        <XlsxConditionalRule>[
          XlsxCellValueRule(
            XlsxComparison.between,
            '1',
            formula2: '2',
            style: _red,
          ),
          XlsxColorScale(
            <XlsxCfValue>[const XlsxCfValue.min(), const XlsxCfValue.max()],
            <XlsxColor>[XlsxColor.hex('FFFFFF'), XlsxColor.hex('000000')],
          ),
          XlsxIconSet(
            XlsxIconSetType.threeSigns,
            thresholds: <XlsxCfValue>[
              XlsxCfValue.percent(0),
              XlsxCfValue.percent(10),
              XlsxCfValue.percent(20),
            ],
          ),
        ],
      );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(make().toString(), startsWith('XlsxConditionalFormat('));
      expect(
        make(),
        isNot(
          XlsxConditionalFormat(
            <XlsxRange>[_a1],
            <XlsxConditionalRule>[const XlsxExpressionRule('TRUE')],
          ),
        ),
      );
    });
    test('every rule compares by value and has a toString', () {
      final List<XlsxConditionalRule Function()> makers =
          <XlsxConditionalRule Function()>[
            () => const XlsxCellValueRule(XlsxComparison.equal, '1'),
            () => const XlsxExpressionRule('TRUE'),
            () => const XlsxTopBottomRule(rank: 3),
            () => const XlsxAverageRule(above: false),
            () => const XlsxDuplicateRule(unique: true),
            () => const XlsxTextRule(XlsxTextOperator.endsWith, 'x'),
            () => XlsxColorScale(
              <XlsxCfValue>[const XlsxCfValue.min(), const XlsxCfValue.max()],
              <XlsxColor>[XlsxColor.hex('FFFFFF'), XlsxColor.hex('000000')],
            ),
            () => XlsxDataBar(color: XlsxColor.hex('638EC6')),
            () => XlsxIconSet(XlsxIconSetType.fiveArrows),
          ];
      for (final XlsxConditionalRule Function() make in makers) {
        expect(make(), make());
        expect(make().hashCode, make().hashCode);
        expect(make().toString(), startsWith('Xlsx'));
      }
      for (int i = 0; i < makers.length; i++) {
        for (int j = 0; j < i; j++) {
          expect(makers[i](), isNot(makers[j]()));
        }
      }
    });
    test('stopIfTrue and style take part in equality', () {
      expect(
        const XlsxExpressionRule('TRUE'),
        isNot(const XlsxExpressionRule('TRUE', stopIfTrue: true)),
      );
      expect(const XlsxDuplicateRule(), isNot(XlsxDuplicateRule(style: _red)));
      expect(
        XlsxCfValue.number(1),
        isNot(XlsxCfValue.number(1, greaterOrEqual: false)),
      );
    });
    test('lists are unmodifiable copies', () {
      final List<XlsxRange> ranges = <XlsxRange>[_a1];
      final List<XlsxConditionalRule> rules = <XlsxConditionalRule>[
        const XlsxExpressionRule('TRUE'),
      ];
      final List<XlsxCfValue> points = <XlsxCfValue>[
        const XlsxCfValue.min(),
        const XlsxCfValue.max(),
      ];
      final List<XlsxColor> colors = <XlsxColor>[
        XlsxColor.hex('FFFFFF'),
        XlsxColor.hex('000000'),
      ];
      final XlsxConditionalFormat f = XlsxConditionalFormat(ranges, rules);
      final XlsxColorScale scale = XlsxColorScale(points, colors);
      final XlsxIconSet icons = XlsxIconSet(
        XlsxIconSetType.threeArrows,
        thresholds: points.toList()..add(const XlsxCfValue.max()),
      );
      ranges.add(_a1);
      rules.clear();
      points.clear();
      colors.clear();
      expect(f.ranges, hasLength(1));
      expect(f.rules, hasLength(1));
      expect(scale.points, hasLength(2));
      expect(scale.colors, hasLength(2));
      expect(() => f.ranges.add(_a1), throwsUnsupportedError);
      expect(() => f.rules.clear(), throwsUnsupportedError);
      expect(() => scale.points.clear(), throwsUnsupportedError);
      expect(() => icons.thresholds!.clear(), throwsUnsupportedError);
    });
    test('the defaults are those of the schema and the brief', () {
      const XlsxTopBottomRule top = XlsxTopBottomRule();
      expect((top.rank, top.percent, top.bottom), (10, false, false));
      const XlsxAverageRule avg = XlsxAverageRule();
      expect(
        (avg.above, avg.orEqual, avg.standardDeviations),
        (true, false, null),
      );
      final XlsxDataBar bar = XlsxDataBar(color: XlsxColor.hex('638EC6'));
      expect(bar.min, const XlsxCfValue.min());
      expect(bar.max, const XlsxCfValue.max());
      expect((bar.showValue, bar.minLength, bar.maxLength), (true, 10, 90));
      final XlsxIconSet set = XlsxIconSet(XlsxIconSetType.threeArrows);
      expect((set.thresholds, set.reverse, set.showValue), (null, false, true));
      expect(const XlsxExpressionRule('TRUE').stopIfTrue, isFalse);
      expect(const XlsxCfValue.min().greaterOrEqual, isTrue);
      expect(
        XlsxCfValue.percent(33),
        const XlsxCfValue(XlsxCfValueType.percent, value: '33'),
      );
    });
  });
}
