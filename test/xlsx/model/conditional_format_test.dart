import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/conditional_format.dart'
    show defaultIconSetThresholds;
import 'package:jet_office/src/xlsx/model/conditional_elements.dart';
import 'package:jet_office/src/xlsx/model/item_group.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

XlsxRange _r(String ref) => XlsxRange.parse(ref);

String _sheet(String body) =>
    '<worksheet xmlns="$mainNs"><sheetData/>$body</worksheet>';

Uint8List _file(String body, {String? styles}) =>
    buildWorkbook(<String, String>{'S': _sheet(body)}, styles: styles);

XlsxWorkbook _open(String body, {String? styles}) =>
    XlsxWorkbook.open(_file(body, styles: styles));

String _xml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

/// The `<conditionalFormatting>` elements of [xml], in order.
List<String> _elements(String xml) => RegExp(
  '<conditionalFormatting[^>]*/>|<conditionalFormatting[ >].*?'
  '</conditionalFormatting>',
).allMatches(xml).map((RegExpMatch m) => m.group(0)!).toList();

/// The `<dxf>`s of a `styles.xml`.
List<String> _dxfs(String xml) => RegExp(
  '<dxf/>|<dxf>.*?</dxf>',
).allMatches(xml).map((RegExpMatch m) => m.group(0)!).toList();

/// A styles part with the `<dxf>`s [dxfs] (raw XML).
String _styles(String dxfs) =>
    '<styleSheet xmlns="$mainNs"><cellXfs count="1"><xf/></cellXfs>'
    '<dxfs>$dxfs</dxfs></styleSheet>';

const String _bold = '<dxf><font><b/></font></dxf>';
const String _italic = '<dxf><font><i/></font></dxf>';

const XlsxStyle _boldStyle = XlsxStyle(font: XlsxFont(bold: true));
const XlsxStyle _italicStyle = XlsxStyle(font: XlsxFont(italic: true));

int _invalid(XlsxWorkbook book) => book.warnings
    .where((XlsxWarning w) => w.code == XlsxWarningCode.featureEntryInvalid)
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

XlsxConditionalFormat _format(String ref, XlsxConditionalRule rule) =>
    XlsxConditionalFormat(<XlsxRange>[_r(ref)], <XlsxConditionalRule>[rule]);

/// The formats the fixture `m3_conditional` was written with, in order.
List<XlsxConditionalFormat> _fixtureFormats() {
  final XlsxStyle red = XlsxStyle(
    font: XlsxFont(color: XlsxColor.hex('9C0006')),
    fill: XlsxFill.solid(XlsxColor.hex('FFC7CE')),
  );
  final XlsxStyle green = XlsxStyle(
    font: XlsxFont(color: XlsxColor.hex('006100')),
    fill: XlsxFill.solid(XlsxColor.hex('C6EFCE')),
  );
  XlsxConditionalFormat column(int c, XlsxConditionalRule rule) =>
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange(1, c, 20, c)],
        <XlsxConditionalRule>[rule],
      );
  return <XlsxConditionalFormat>[
    column(0, XlsxTextRule(XlsxTextOperator.contains, 'an', style: red)),
    column(
      1,
      XlsxCellValueRule(XlsxComparison.greaterThanOrEqual, '70', style: green),
    ),
    column(2, XlsxExpressionRule(r'C2>AVERAGE($C$2:$C$21)', style: green)),
    column(3, XlsxTopBottomRule(rank: 3, style: red)),
    column(4, XlsxAverageRule(above: false, orEqual: true, style: green)),
    column(5, XlsxDuplicateRule(style: red)),
    column(
      6,
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
    column(7, XlsxDataBar(color: XlsxColor.hex('638EC6'))),
    column(8, XlsxIconSet(XlsxIconSetType.threeArrows)),
    _format(
      'B2:C21',
      const XlsxCellValueRule(XlsxComparison.lessThan, '40', style: _boldStyle),
    ),
  ];
}

/// One format of every kind the Excel 2007 elements hold alone, the first
/// with more than one rule and range.
List<XlsxConditionalFormat> _addable() => <XlsxConditionalFormat>[
  XlsxConditionalFormat(
    <XlsxRange>[_r('A1:A9'), _r('C1')],
    <XlsxConditionalRule>[
      const XlsxCellValueRule(
        XlsxComparison.between,
        '1',
        formula2: '=2',
        style: _boldStyle,
        stopIfTrue: true,
      ),
      const XlsxExpressionRule('A1>0'),
      const XlsxCellValueRule(XlsxComparison.equal, '"x"', style: _italicStyle),
    ],
  ),
  _format(
    'B2:B9',
    const XlsxTextRule(
      XlsxTextOperator.notContains,
      'a"b&c',
      style: _boldStyle,
    ),
  ),
  _format('D1', const XlsxTextRule(XlsxTextOperator.beginsWith, 'x')),
  _format('D2', const XlsxTextRule(XlsxTextOperator.endsWith, 'y')),
  _format('E1', const XlsxTopBottomRule(rank: 5, percent: true, bottom: true)),
  _format('E2', const XlsxAverageRule(standardDeviations: 2)),
  _format('E3', const XlsxDuplicateRule(unique: true)),
  _format(
    'F1:F9',
    XlsxColorScale(
      <XlsxCfValue>[
        XlsxCfValue.number(1.5),
        const XlsxCfValue.formula(r'$A$1'),
      ],
      <XlsxColor>[const XlsxColor.theme(4, tint: 0.5), XlsxColor.hex('FF0000')],
    ),
  ),
  _format(
    'G1:G9',
    XlsxIconSet(
      XlsxIconSetType.fourRating,
      thresholds: <XlsxCfValue>[
        XlsxCfValue.percent(0),
        XlsxCfValue.percent(10),
        XlsxCfValue.percent(20, greaterOrEqual: false),
        XlsxCfValue.percentile(30),
      ],
      reverse: true,
      showValue: false,
    ),
  ),
];

/// Formats whose value differs from what a reading of the file gives.
List<XlsxConditionalFormat> _asWrittenDiffers() => <XlsxConditionalFormat>[
  _format('A1', const XlsxExpressionRule('=A1>0')),
  _format(
    'A1:A9',
    XlsxColorScale(
      const <XlsxCfValue>[XlsxCfValue.min(), XlsxCfValue.formula(r'=$A$1')],
      <XlsxColor>[XlsxColor.hex('FF0000'), XlsxColor.hex('00FF00')],
    ),
  ),
  _format(
    'A1:A9',
    XlsxIconSet(
      XlsxIconSetType.threeArrows,
      thresholds: defaultIconSetThresholds(3),
    ),
  ),
];

void main() {
  group('reading', () {
    test('reads m3_conditional', () {
      final Fixture fixture = allFixtures().firstWhere(
        (Fixture f) => f.name == 'm3_conditional',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(fixture.build());
      expect(book.sheets.single.conditionalFormats, _fixtureFormats());
      expect(_invalid(book), 0);
    });

    test('what is added reads back equal after a save', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      _addable().forEach(sheet.addConditionalFormat);
      final List<XlsxConditionalFormat> listed = sheet.conditionalFormats;
      // The first has a formula with a leading `=`, which is not written.
      expect((listed.first.rules.first as XlsxCellValueRule).formula2, '2');
      expect(listed, _addable().map(normalizedConditionalFormat));
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.sheets.single.conditionalFormats, listed);
      expect(_invalid(again), 0);
    });

    test('the getter gives what the file says, before and after a save', () {
      for (final XlsxConditionalFormat format in _asWrittenDiffers()) {
        final XlsxWorkbook book = XlsxWorkbook();
        final XlsxSheet sheet = book.addSheet('S');
        sheet.addConditionalFormat(format);
        final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
        expect(
          again.sheets.single.conditionalFormats,
          sheet.conditionalFormats,
        );
        expect(sheet.conditionalFormats.single, isNot(format));
      }
    });

    test('rule order is the file\'s, not the priorities\'', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1 B2:B3">'
        '<cfRule type="expression" priority="7"><formula>A1</formula></cfRule>'
        '<cfRule type="expression" priority="2"><formula>B1</formula></cfRule>'
        '</conditionalFormatting>',
      );
      expect(book.sheets.single.conditionalFormats, <XlsxConditionalFormat>[
        XlsxConditionalFormat(
          <XlsxRange>[_r('A1'), _r('B2:B3')],
          const <XlsxConditionalRule>[
            XlsxExpressionRule('A1'),
            XlsxExpressionRule('B1'),
          ],
        ),
      ]);
    });

    test('attributes read through the schema defaults', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1">'
        '<cfRule type="aboveAverage" priority="1" stopIfTrue="true"/>'
        '<cfRule type="aboveAverage" priority="2" aboveAverage="false" '
        'equalAverage="true" stdDev="3"/>'
        '<cfRule type="top10" priority="3" rank="4" percent="true" '
        'bottom="1"/>'
        '<cfRule type="uniqueValues" priority="4"/>'
        '<cfRule type="iconSet" priority="5"><iconSet>'
        '<cfvo type="percent" val="0"/><cfvo type="percent" val="33"/>'
        '<cfvo type="percent" val="67"/></iconSet></cfRule>'
        '<cfRule type="dataBar" priority="6"><dataBar minLength="5" '
        'maxLength="95" showValue="0"><cfvo type="min" val="0"/>'
        '<cfvo type="num" val="9" gte="0"/><color theme="4"/></dataBar>'
        '</cfRule></conditionalFormatting>',
      );
      expect(book.sheets.single.conditionalFormats.single.rules, <Object>[
        const XlsxAverageRule(stopIfTrue: true),
        const XlsxAverageRule(
          above: false,
          orEqual: true,
          standardDeviations: 3,
        ),
        const XlsxTopBottomRule(rank: 4, percent: true, bottom: true),
        const XlsxDuplicateRule(unique: true),
        // The schema's default set, with Excel's default thresholds.
        XlsxIconSet(XlsxIconSetType.threeTrafficLights1),
        const XlsxDataBar(
          min: XlsxCfValue(XlsxCfValueType.min, value: '0'),
          max: XlsxCfValue(
            XlsxCfValueType.number,
            value: '9',
            greaterOrEqual: false,
          ),
          color: XlsxColor.theme(4),
          minLength: 5,
          maxLength: 95,
          showValue: false,
        ),
      ]);
      expect(_invalid(book), 0);
    });

    test('text and formulas are decoded', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="B2">'
        '<cfRule type="containsText" priority="1" operator="containsText" '
        'text="a_x0009_&amp;"><formula>anything else</formula></cfRule>'
        '<cfRule type="cellIs" priority="2" operator="notBetween">'
        '<formula>&quot;x&quot;&amp;1</formula><formula>A_x000A_</formula>'
        '</cfRule></conditionalFormatting>',
      );
      expect(book.sheets.single.conditionalFormats.single.rules, <Object>[
        const XlsxTextRule(XlsxTextOperator.contains, 'a\t&'),
        const XlsxCellValueRule(
          XlsxComparison.notBetween,
          '"x"&1',
          formula2: 'A\n',
        ),
      ]);
    });

    test('other rule types read as expressions, kept as written', () {
      const String body =
          '<conditionalFormatting sqref="A1:A9">'
          '<cfRule type="timePeriod" dxfId="0" priority="1" '
          'timePeriod="today"><formula>FLOOR(A1,1)=TODAY()</formula></cfRule>'
          '<cfRule type="containsBlanks" priority="2">'
          '<formula>LEN(TRIM(A1))=0</formula></cfRule>'
          '<cfRule type="notContainsBlanks" priority="3">'
          '<formula>LEN(TRIM(A1))&gt;0</formula></cfRule>'
          '<cfRule type="containsErrors" priority="4">'
          '<formula>ISERROR(A1)</formula></cfRule>'
          '<cfRule type="notContainsErrors" priority="5" stopIfTrue="1">'
          '<formula>NOT(ISERROR(A1))</formula></cfRule>'
          '</conditionalFormatting>';
      final XlsxWorkbook book = _open(body, styles: _styles(_bold));
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats.single.rules, <Object>[
        const XlsxExpressionRule('FLOOR(A1,1)=TODAY()', style: _boldStyle),
        const XlsxExpressionRule('LEN(TRIM(A1))=0'),
        const XlsxExpressionRule('LEN(TRIM(A1))>0'),
        const XlsxExpressionRule('ISERROR(A1)'),
        const XlsxExpressionRule('NOT(ISERROR(A1))', stopIfTrue: true),
      ]);
      expect(_elements(_xml(book)).single, body);
    });

    test('a data bar keeps the id of its Excel 2010 rule', () {
      final OpaqueXml element = renderElements(
        (XmlWriter w) => w
          ..start('conditionalFormatting')
          ..attribute('sqref', 'A1')
          ..start('cfRule')
          ..attribute('type', 'dataBar')
          ..attribute('priority', '3')
          ..start('dataBar')
          ..start('cfvo')
          ..attribute('type', 'min')
          ..end()
          ..start('cfvo')
          ..attribute('type', 'max')
          ..end()
          ..start('color')
          ..attribute('rgb', 'FF638EC6')
          ..end()
          ..end()
          ..start('extLst')
          ..start('ext')
          ..attribute('uri', '{B025F937-C7B1-47D3-B67F-A62EFF666E3E}')
          ..attribute('xmlns:x14', Ns.x14)
          ..start('x14:id')
          ..text('{00000001-0000-4000-8000-000000000002}')
          ..end()
          ..end()
          ..end()
          ..end()
          ..end(),
      ).single;
      final CfEntry entry = readConditionalFormatting(element).value!;
      expect(entry.source, same(element));
      expect(entry.rules.single.priority, 3);
      expect(entry.rules.single.dxfId, isNull);
      expect(
        entry.rules.single.x14Id,
        '{00000001-0000-4000-8000-000000000002}',
      );
      expect(entry.rules.single.rule, isA<XlsxDataBar>());
    });

    test('the block holds rules without their style', () {
      final OpaqueXml element = renderElements(
        (XmlWriter w) => w
          ..start('conditionalFormatting')
          ..attribute('sqref', 'A1')
          ..start('cfRule')
          ..attribute('type', 'expression')
          ..attribute('dxfId', '4')
          ..attribute('priority', '1')
          ..start('formula')
          ..text('A1')
          ..end()
          ..end()
          ..end(),
      ).single;
      final CfRuleEntry rule = readConditionalFormatting(
        element,
      ).value!.rules.single;
      expect(rule.rule, const XlsxExpressionRule('A1'));
      expect(rule.dxfId, 4);
      expect(rule.x14Id, isNull);
    });

    test('a prefixed worksheet reads', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String>{
          'S':
              '<x:worksheet xmlns:x="$mainNs"><x:sheetData/>'
              '<x:conditionalFormatting sqref="A1"><x:cfRule type="cellIs" '
              'priority="2" operator="equal"><x:formula>1</x:formula>'
              '</x:cfRule></x:conditionalFormatting></x:worksheet>',
        }),
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, <XlsxConditionalFormat>[
        _format('A1', const XlsxCellValueRule(XlsxComparison.equal, '1')),
      ]);
      sheet.addConditionalFormat(_format('B1', const XlsxExpressionRule('B1')));
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.sheets.single.conditionalFormats, hasLength(2));
    });

    test('an opened file saves unchanged', () {
      final Uint8List input = _file(
        '<conditionalFormatting sqref="???"/>'
        '<conditionalFormatting pivot="1" sqref="A1"><cfRule type="expression" '
        'priority="1"><formula>A1</formula></cfRule>'
        '<extLst><ext uri="{x}"/></extLst></conditionalFormatting>'
        '<dataValidations count="0"/>'
        '<conditionalFormatting sqref="B1"/>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheets.single.conditionalFormats, hasLength(1));
      expect(comparePackages(input, book.save().bytes), isEmpty);
    });
  });

  group('adding', () {
    test('add writes what the writer writes', () {
      final XlsxWriter writer = XlsxWriter();
      final XlsxSheetWriter written = writer.addSheet('S');
      _addable().forEach(written.conditionalFormat);
      final Uint8List expected = writer.close().bytes;

      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      _addable().forEach(sheet.addConditionalFormat);
      final Uint8List actual = book.save().bytes;

      const String part = 'xl/worksheets/sheet1.xml';
      expect(
        _elements(partText(actual, part)),
        _elements(partText(expected, part)),
      );
      expect(
        _dxfs(partText(actual, 'xl/styles.xml')),
        _dxfs(partText(expected, 'xl/styles.xml')),
      );
    });

    test('the element goes where the schema puts it', () {
      final XlsxWorkbook book = _open(
        '<mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells>'
        '<dataValidations count="0"/><pageMargins left="1" right="1" top="1" '
        'bottom="1" header="1" footer="1"/>',
      );
      book.sheets.single.addConditionalFormat(
        _format('C1', const XlsxExpressionRule('C1')),
      );
      final String xml = _xml(book);
      expect(
        xml.indexOf('<conditionalFormatting'),
        greaterThan(xml.indexOf('</mergeCells>')),
      );
      expect(
        xml.indexOf('</conditionalFormatting>'),
        lessThan(xml.indexOf('<dataValidations')),
      );
    });

    test('a new format follows the block, before what comes next', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1"><cfRule type="expression" '
        'priority="1"><formula>A1</formula></cfRule></conditionalFormatting>'
        '<conditionalFormatting sqref="???"/>'
        '<dataValidations count="0"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.addConditionalFormat(_format('B1', const XlsxExpressionRule('B1')));
      final List<String> elements = _elements(_xml(book));
      expect(elements, hasLength(3));
      expect(elements[0], contains('sqref="A1"'));
      expect(elements[1], contains('sqref="???"'));
      expect(elements[2], contains('sqref="B1"'));
    });

    test('priorities continue the file\'s', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1">'
        '<cfRule type="expression" priority="9"><formula>A1</formula></cfRule>'
        '<cfRule type="expression" priority="5"><formula>B1</formula></cfRule>'
        '</conditionalFormatting>',
      );
      book.sheets.single.addConditionalFormat(
        XlsxConditionalFormat(
          <XlsxRange>[_r('B1')],
          const <XlsxConditionalRule>[
            XlsxExpressionRule('B1'),
            XlsxExpressionRule('C1'),
          ],
        ),
      );
      final String added = _elements(_xml(book)).last;
      expect(added, contains('priority="10"'));
      expect(added, contains('priority="11"'));
    });

    test('priorities count what is not listed', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="???"><cfRule type="expression" '
        'priority="20"><formula>A1</formula></cfRule>'
        '</conditionalFormatting>'
        '<phoneticPr/>'
        '<conditionalFormatting sqref="B1"><cfRule type="expression" '
        'priority="30"><formula>A1</formula></cfRule>'
        '</conditionalFormatting>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.addConditionalFormat(_format('C1', const XlsxExpressionRule('C1')));
      expect(_xml(book), contains('priority="31"'));
    });

    test('a priority past the schema\'s int throws', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1"><cfRule type="expression" '
        'priority="2147483647"><formula>A1</formula></cfRule>'
        '</conditionalFormatting>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.conditionalFormats;
      final String before = _xml(book);
      expect(
        () => sheet.addConditionalFormat(
          _format('C1', const XlsxExpressionRule('C1', style: _boldStyle)),
        ),
        throwsA(isA<XlsxLimitError>()),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_xml(book), before);
    });

    test('a style the file has is reused, a new one appended', () {
      final XlsxWorkbook book = _open('', styles: _styles('$_bold$_italic'));
      final XlsxSheet sheet = book.sheets.single;
      sheet.addConditionalFormat(
        XlsxConditionalFormat(
          <XlsxRange>[_r('A1')],
          <XlsxConditionalRule>[
            const XlsxExpressionRule('A1', style: _italicStyle),
            const XlsxExpressionRule(
              'B1',
              style: XlsxStyle(font: XlsxFont(strike: true)),
            ),
          ],
        ),
      );
      final String element = _elements(_xml(book)).single;
      expect(element, contains('dxfId="1"'));
      expect(element, contains('dxfId="2"'));
      expect(_dxfs(partText(book.save().bytes, 'xl/styles.xml')), hasLength(3));
    });

    test('a bad rule throws named rules[0]...; nothing changes', () {
      final XlsxWorkbook book = _open('', styles: _styles(_bold));
      final XlsxSheet sheet = book.sheets.single;
      final Uint8List before = book.save().bytes;
      expect(
        () => sheet.addConditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[_r('A1')],
            const <XlsxConditionalRule>[
              XlsxTopBottomRule(rank: 0, style: _italicStyle),
            ],
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'rules[0].rank',
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(sheet.conditionalFormats, isEmpty);
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });

    test('a style that fails at registration drops the earlier ones', () {
      final XlsxWorkbook book = _open('', styles: _styles(_bold));
      final XlsxSheet sheet = book.sheets.single;
      final Uint8List before = book.save().bytes;
      expect(
        () => sheet.addConditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[_r('A1')],
            const <XlsxConditionalRule>[
              XlsxExpressionRule('A1', style: _italicStyle),
              XlsxExpressionRule(
                'B1',
                style: XlsxStyle(numFmt: XlsxNumFmt.builtin(30)),
              ),
            ],
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'rules[1].style.numFmt',
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(sheet.conditionalFormats, isEmpty);
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });

    test('the first append reads the file\'s dxfs and warns of a bad one', () {
      final XlsxWorkbook book = _open(
        '',
        styles: _styles('<dxf><font><color rgb="zz"/></font></dxf>'),
      );
      book.sheets.single.addConditionalFormat(
        _format('A1', const XlsxExpressionRule('A1', style: _boldStyle)),
      );
      expect(
        book.warnings.map((XlsxWarning w) => w.code),
        contains(XlsxWarningCode.styleEntryInvalid),
      );
      final List<String> dxfs = _dxfs(
        partText(book.save().bytes, 'xl/styles.xml'),
      );
      expect(dxfs, hasLength(2));
      expect(dxfs.first, contains('rgb="zz"'));
      expect(_elements(_xml(book)).single, contains('dxfId="1"'));
    });

    test('an add undoes and redoes, the dxf with it', () {
      final XlsxWorkbook book = _open('', styles: _styles(_bold));
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      final XlsxConditionalFormat format = _format(
        'A1',
        const XlsxExpressionRule('A1', style: _italicStyle),
      );
      sheet.conditionalFormats;
      final String before = _xml(book);
      final ChangeSet set = log.transaction(
        () => sheet.addConditionalFormat(format),
      );
      expect(sheet.conditionalFormats, <XlsxConditionalFormat>[format]);
      log.revertSet(set);
      expect(sheet.conditionalFormats, isEmpty);
      expect(_xml(book), before);
      expect(_dxfs(partText(book.save().bytes, 'xl/styles.xml')), hasLength(1));
      log.reapplySet(set);
      expect(sheet.conditionalFormats, <XlsxConditionalFormat>[format]);
      expect(_dxfs(partText(book.save().bytes, 'xl/styles.xml')), hasLength(2));
    });
  });

  group('removing', () {
    const String body =
        '<conditionalFormatting sqref="A1"><cfRule type="expression" '
        'dxfId="0" priority="1"><formula>A1</formula></cfRule>'
        '</conditionalFormatting>'
        '<conditionalFormatting sqref="???"><cfRule type="expression" '
        'priority="2"><formula>Q1</formula></cfRule>'
        '</conditionalFormatting>'
        '<conditionalFormatting sqref="B1"><cfRule type="expression" '
        'dxfId="1" priority="3"><formula>B1</formula></cfRule>'
        '</conditionalFormatting>'
        '<conditionalFormatting sqref="B1"><cfRule type="expression" '
        'dxfId="1" priority="4"><formula>B1</formula></cfRule>'
        '</conditionalFormatting>'
        '<conditionalFormatting sqref="C1"><cfRule type="expression" '
        'priority="5"><formula>C1</formula></cfRule>'
        '</conditionalFormatting>';

    final XlsxConditionalFormat second = _format(
      'B1',
      const XlsxExpressionRule('B1', style: _italicStyle),
    );

    test('removing keeps the others and their order; undo restores it', () {
      final XlsxWorkbook book = _open(body, styles: _styles('$_bold$_italic'));
      final XlsxSheet sheet = book.sheets.single;
      final List<String> before = _elements(_xml(book));
      final List<XlsxConditionalFormat> listed = sheet.conditionalFormats;
      expect(listed, hasLength(4));

      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => sheet.removeConditionalFormat(second),
      );
      final List<String> after = _elements(_xml(book));
      expect(after, <String>[before[0], before[1], before[3], before[4]]);
      expect(sheet.conditionalFormats, <XlsxConditionalFormat>[
        listed[0],
        listed[2],
        listed[3],
      ]);
      // Its dxfs stay: the part is append-only.
      expect(_dxfs(partText(book.save().bytes, 'xl/styles.xml')), hasLength(2));

      log.revertSet(set);
      expect(_elements(_xml(book)), before);
      expect(sheet.conditionalFormats, listed);
    });

    test('removing the last one leaves no element; undo keeps its place', () {
      const String last =
          '<dataValidations count="0"/>'
          '<conditionalFormatting sqref="A1"><cfRule type="expression" '
          'priority="1"><formula>A1</formula></cfRule>'
          '</conditionalFormatting>';
      final XlsxWorkbook book = _open(last);
      final XlsxSheet sheet = book.sheets.single;
      sheet.conditionalFormats;
      final String before = _xml(book);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => sheet.removeConditionalFormat(sheet.conditionalFormats.single),
      );
      expect(_elements(_xml(book)), isEmpty);
      expect(sheet.conditionalFormats, isEmpty);
      log.revertSet(set);
      expect(_xml(book), before);
    });

    test('a format that is not there throws; nothing changes', () {
      final XlsxWorkbook book = _open(body, styles: _styles('$_bold$_italic'));
      final XlsxSheet sheet = book.sheets.single;
      for (final XlsxConditionalFormat format in <XlsxConditionalFormat>[
        _format('B1', const XlsxExpressionRule('B1')),
        _format('Z1', const XlsxExpressionRule('Q1')),
      ]) {
        expect(
          () => sheet.removeConditionalFormat(format),
          throwsArgumentError,
        );
      }
      expect(changeLogOf(book).hasChanges, isFalse);
      final XlsxWorkbook empty = _open('');
      expect(
        () => empty.sheets.single.removeConditionalFormat(second),
        throwsArgumentError,
      );
    });

    test('what was added can be removed as it was given', () {
      final XlsxWorkbook book = _open('');
      final XlsxSheet sheet = book.sheets.single;
      for (final XlsxConditionalFormat format in _addable()) {
        sheet
          ..addConditionalFormat(format)
          ..removeConditionalFormat(format);
      }
      expect(sheet.conditionalFormats, isEmpty);
      expect(_elements(_xml(book)), isEmpty);
    });

    test('add, reopen, remove with the original value', () {
      for (final XlsxConditionalFormat format in <XlsxConditionalFormat>[
        ..._asWrittenDiffers(),
        ..._addable(),
      ]) {
        final XlsxWorkbook book = XlsxWorkbook();
        book.addSheet('S').addConditionalFormat(format);
        final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
        final XlsxSheet sheet = again.sheets.single;
        sheet.removeConditionalFormat(format);
        expect(sheet.conditionalFormats, isEmpty, reason: '$format');
      }
    });

    test('a value the getter gave removes, whatever the file wrote', () {
      for (final String formula in <String>['=A1', '==A1']) {
        final String body =
            '<conditionalFormatting sqref="A1"><cfRule type="expression" '
            'priority="1"><formula>$formula</formula></cfRule>'
            '</conditionalFormatting>';
        final XlsxSheet sheet = _open(body).sheets.single;
        final XlsxConditionalFormat listed = sheet.conditionalFormats.single;
        expect(
          listed.rules.single,
          XlsxExpressionRule(formula),
          reason: 'kept as written',
        );
        sheet.removeConditionalFormat(listed);
        expect(sheet.conditionalFormats, isEmpty);
      }
    });
  });

  group('normalizedConditionalFormat', () {
    XlsxConditionalRule normalized(XlsxConditionalRule rule) =>
        normalizedConditionalFormat(_format('A1', rule)).rules.single;

    test('one leading = goes from every formula', () {
      expect(
        normalized(
          const XlsxCellValueRule(
            XlsxComparison.between,
            '=1',
            formula2: '==2',
            style: _boldStyle,
            stopIfTrue: true,
          ),
        ),
        const XlsxCellValueRule(
          XlsxComparison.between,
          '1',
          formula2: '=2',
          style: _boldStyle,
          stopIfTrue: true,
        ),
      );
      expect(
        normalized(
          const XlsxExpressionRule('=A1', style: _boldStyle, stopIfTrue: true),
        ),
        const XlsxExpressionRule('A1', style: _boldStyle, stopIfTrue: true),
      );
    });

    test('and from every point', () {
      expect(
        normalized(
          XlsxColorScale(
            const <XlsxCfValue>[
              XlsxCfValue.formula('=A1', greaterOrEqual: false),
              XlsxCfValue.max(),
            ],
            <XlsxColor>[XlsxColor.hex('FF0000'), XlsxColor.hex('00FF00')],
            stopIfTrue: true,
          ),
        ),
        XlsxColorScale(
          const <XlsxCfValue>[
            XlsxCfValue.formula('A1', greaterOrEqual: false),
            XlsxCfValue.max(),
          ],
          <XlsxColor>[XlsxColor.hex('FF0000'), XlsxColor.hex('00FF00')],
          stopIfTrue: true,
        ),
      );
      final XlsxDataBar bar = XlsxDataBar(
        min: const XlsxCfValue.formula('=A1'),
        max: const XlsxCfValue(XlsxCfValueType.number, value: '=B1'),
        color: XlsxColor.hex('638EC6'),
        showValue: false,
        minLength: 5,
        maxLength: 95,
        gradient: false,
        border: true,
        borderColor: XlsxColor.hex('000001'),
        negativeFillColor: XlsxColor.hex('000002'),
        negativeBorderColor: XlsxColor.hex('000003'),
        axis: XlsxDataBarAxis.middle,
        axisColor: XlsxColor.hex('000004'),
        stopIfTrue: true,
      );
      expect(
        normalized(bar),
        XlsxDataBar(
          min: const XlsxCfValue.formula('A1'),
          max: const XlsxCfValue(XlsxCfValueType.number, value: 'B1'),
          color: bar.color,
          showValue: false,
          minLength: 5,
          maxLength: 95,
          gradient: false,
          border: true,
          borderColor: bar.borderColor,
          negativeFillColor: bar.negativeFillColor,
          negativeBorderColor: bar.negativeBorderColor,
          axis: XlsxDataBarAxis.middle,
          axisColor: bar.axisColor,
          stopIfTrue: true,
        ),
      );
    });

    test('default thresholds collapse, others stay', () {
      expect(
        normalized(
          XlsxIconSet(
            XlsxIconSetType.threeArrows,
            thresholds: const <XlsxCfValue>[
              XlsxCfValue(XlsxCfValueType.percent, value: '=0'),
              XlsxCfValue(XlsxCfValueType.percent, value: '33'),
              XlsxCfValue(XlsxCfValueType.percent, value: '67'),
            ],
            reverse: true,
            showValue: false,
            stopIfTrue: true,
          ),
        ),
        XlsxIconSet(
          XlsxIconSetType.threeArrows,
          reverse: true,
          showValue: false,
          stopIfTrue: true,
        ),
      );
      final XlsxIconSet other = XlsxIconSet(
        XlsxIconSetType.threeArrows,
        thresholds: <XlsxCfValue>[
          XlsxCfValue.percent(0),
          XlsxCfValue.percent(33),
          XlsxCfValue.percent(68),
        ],
      );
      expect(normalized(other), other);
      expect(
        normalized(XlsxIconSet(XlsxIconSetType.threeArrows)),
        XlsxIconSet(XlsxIconSetType.threeArrows),
      );
    });

    test('a text rule\'s text is not a formula', () {
      const XlsxTextRule rule = XlsxTextRule(
        XlsxTextOperator.contains,
        '=x',
        style: _boldStyle,
      );
      expect(normalized(rule), rule);
    });

    test('ranges stay', () {
      final XlsxConditionalFormat format = XlsxConditionalFormat(
        <XlsxRange>[_r('A1'), _r('B2:C3')],
        const <XlsxConditionalRule>[XlsxDuplicateRule(), XlsxAverageRule()],
      );
      expect(normalizedConditionalFormat(format), format);
    });
  });

  group('kept as written', () {
    test('bad values are kept and reported', () {
      const String bad =
          '<conditionalFormatting sqref="">'
          '<cfRule type="expression" priority="1"><formula>A1</formula>'
          '</cfRule></conditionalFormatting>'
          '<conditionalFormatting sqref="B1">'
          '<cfRule type="zigzag" priority="2"/></conditionalFormatting>';
      const String dangling =
          '<conditionalFormatting sqref="C1">'
          '<cfRule type="expression" dxfId="7" priority="3">'
          '<formula>C1</formula></cfRule></conditionalFormatting>';
      final XlsxWorkbook book = _open('$bad$dangling', styles: _styles(_bold));
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, <XlsxConditionalFormat>[
        _format('C1', const XlsxExpressionRule('C1')),
      ]);
      sheet.conditionalFormats;
      expect(_invalid(book), 3);
      expect(
        book.warnings.map((XlsxWarning w) => w.detail),
        everyElement('conditionalFormatting'),
      );

      sheet.addConditionalFormat(_format('D1', const XlsxExpressionRule('D1')));
      sheet.removeConditionalFormat(
        _format('C1', const XlsxExpressionRule('C1')),
      );
      final String xml = _xml(book);
      expect(xml, contains(bad));
      expect(xml, isNot(contains('dxfId="7"')));
    });

    test('a dangling id without a styles part reads with no style', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="C1">'
        '<cfRule type="expression" dxfId="0" priority="3">'
        '<formula>C1</formula></cfRule></conditionalFormatting>',
      );
      expect(
        book.sheets.single.conditionalFormats.single.rules.single,
        const XlsxExpressionRule('C1'),
      );
      expect(_invalid(book), 1);
    });

    test('a scale ignores a dxfId it cannot use', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="C1">'
        '<cfRule type="colorScale" dxfId="9" priority="3"><colorScale>'
        '<cfvo type="min"/><cfvo type="max"/><color rgb="FF000000"/>'
        '<color rgb="FFFFFFFF"/></colorScale></cfRule>'
        '</conditionalFormatting>',
      );
      expect(
        book.sheets.single.conditionalFormats.single.rules.single,
        isA<XlsxColorScale>(),
      );
      expect(_invalid(book), 0);
    });

    group('an unreadable element', () {
      final Map<String, String> cases = <String, String>{
        'no sqref':
            '<conditionalFormatting><cfRule type="expression" '
            'priority="1"><formula>A1</formula></cfRule>'
            '</conditionalFormatting>',
        'no rule': '<conditionalFormatting sqref="A1"/>',
        'a range outside the sheet':
            '<conditionalFormatting sqref="XFE1">'
            '<cfRule type="expression" priority="1"><formula>A1</formula>'
            '</cfRule></conditionalFormatting>',
        'no type': _bad('priority="1"', '<formula>A1</formula>'),
        'no priority': _bad('type="expression"', '<formula>A1</formula>'),
        'a bad priority': _bad(
          'type="expression" priority="0x10"',
          '<formula>A1</formula>',
        ),
        'a huge priority': _bad(
          'type="expression" priority="99999999999999999999"',
          '<formula>A1</formula>',
        ),
        'a priority past the int': _bad(
          'type="expression" priority="2147483648"',
          '<formula>A1</formula>',
        ),
        'a bad dxfId': _bad(
          'type="expression" priority="1" dxfId="x"',
          '<formula>A1</formula>',
        ),
        'a negative dxfId': _bad(
          'type="expression" priority="1" dxfId="-1"',
          '<formula>A1</formula>',
        ),
        'no formula': _bad('type="expression" priority="1"', ''),
        'an empty formula': _bad(
          'type="expression" priority="1"',
          '<formula></formula>',
        ),
        'a formula XML forbids': _bad(
          'type="expression" priority="1"',
          '<formula>_x0001_</formula>',
        ),
        'no operator': _bad(
          'type="cellIs" priority="1"',
          '<formula>1</formula>',
        ),
        'a text operator on cellIs': _bad(
          'type="cellIs" priority="1" operator="beginsWith"',
          '<formula>1</formula>',
        ),
        'between with one operand': _bad(
          'type="cellIs" priority="1" operator="between"',
          '<formula>1</formula>',
        ),
        'a text rule with no text': _bad(
          'type="containsText" priority="1"',
          '<formula>1</formula>',
        ),
        'no rank': _bad('type="top10" priority="1"', ''),
        'a rank of 0': _bad('type="top10" priority="1" rank="0"', ''),
        'a percent rank above 100': _bad(
          'type="top10" priority="1" rank="101" percent="1"',
          '',
        ),
        'a bad stdDev': _bad('type="aboveAverage" priority="1" stdDev="x"', ''),
        'too many deviations': _bad(
          'type="aboveAverage" priority="1" stdDev="4"',
          '',
        ),
        'a scale with no body': _bad('type="colorScale" priority="1"', ''),
        'a scale with the wrong body': _bad(
          'type="colorScale" priority="1"',
          '<dataBar><cfvo type="min"/><cfvo type="max"/>'
              '<color rgb="FF000000"/></dataBar>',
        ),
        'a scale of one point': _bad(
          'type="colorScale" priority="1"',
          '<colorScale><cfvo type="min"/><color rgb="FF000000"/></colorScale>',
        ),
        'a scale with too few colors': _bad(
          'type="colorScale" priority="1"',
          '<colorScale><cfvo type="min"/><cfvo type="max"/>'
              '<color rgb="FF000000"/></colorScale>',
        ),
        'a bad cfvo type': _bad(
          'type="colorScale" priority="1"',
          '<colorScale><cfvo type="odd"/><cfvo type="max"/>'
              '<color rgb="FF000000"/><color rgb="FF000000"/></colorScale>',
        ),
        'a cfvo with no type': _bad(
          'type="colorScale" priority="1"',
          '<colorScale><cfvo/><cfvo type="max"/>'
              '<color rgb="FF000000"/><color rgb="FF000000"/></colorScale>',
        ),
        'a cfvo with no value': _bad(
          'type="colorScale" priority="1"',
          '<colorScale><cfvo type="num"/><cfvo type="max"/>'
              '<color rgb="FF000000"/><color rgb="FF000000"/></colorScale>',
        ),
        'a bad color': _bad(
          'type="colorScale" priority="1"',
          '<colorScale><cfvo type="min"/><cfvo type="max"/>'
              '<color rgb="zz"/><color rgb="FF000000"/></colorScale>',
        ),
        'a bar with no color': _bad(
          'type="dataBar" priority="1"',
          '<dataBar><cfvo type="min"/><cfvo type="max"/></dataBar>',
        ),
        'a bar with one point': _bad(
          'type="dataBar" priority="1"',
          '<dataBar><cfvo type="min"/><color rgb="FF000000"/></dataBar>',
        ),
        'a bar with a bad length': _bad(
          'type="dataBar" priority="1"',
          '<dataBar minLength="x"><cfvo type="min"/><cfvo type="max"/>'
              '<color rgb="FF000000"/></dataBar>',
        ),
        'a bar shorter at the top': _bad(
          'type="dataBar" priority="1"',
          '<dataBar minLength="50" maxLength="40"><cfvo type="min"/>'
              '<cfvo type="max"/><color rgb="FF000000"/></dataBar>',
        ),
        'an unknown icon set': _bad(
          'type="iconSet" priority="1"',
          '<iconSet iconSet="9Moons"><cfvo type="percent" val="0"/></iconSet>',
        ),
        'an Excel 2010 icon set in a 2007 rule': _bad(
          'type="iconSet" priority="1"',
          '<iconSet iconSet="3Stars"><cfvo type="percent" val="0"/>'
              '<cfvo type="percent" val="33"/><cfvo type="percent" val="67"/>'
              '</iconSet>',
        ),
        'too few thresholds': _bad(
          'type="iconSet" priority="1"',
          '<iconSet iconSet="3Arrows"><cfvo type="percent" val="0"/></iconSet>',
        ),
      };
      cases.forEach((String name, String element) {
        test('$name is kept and reported', () {
          final Uint8List input = _file(element);
          final XlsxWorkbook book = XlsxWorkbook.open(input);
          final XlsxSheet sheet = book.sheets.single;
          expect(sheet.conditionalFormats, isEmpty);
          expect(_invalid(book), 1);
          expect(comparePackages(input, book.save().bytes), isEmpty);
          expect(_elements(_xml(book)).single, element);
        });
      });
    });

    test('one bad rule keeps the whole element out', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1">'
        '<cfRule type="expression" priority="1"><formula>A1</formula></cfRule>'
        '<cfRule type="zigzag" priority="2"/></conditionalFormatting>',
      );
      expect(book.sheets.single.conditionalFormats, isEmpty);
      expect(_invalid(book), 1);
    });

    test('only the first run of elements is listed', () {
      const String after =
          '<conditionalFormatting sqref="B1"><cfRule type="zigzag" '
          'priority="2"/></conditionalFormatting>';
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1"><cfRule type="expression" '
        'priority="1"><formula>A1</formula></cfRule>'
        '</conditionalFormatting><foreign xmlns="urn:x"/>$after',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, hasLength(1));
      expect(_invalid(book), 0);
      sheet.removeConditionalFormat(sheet.conditionalFormats.single);
      expect(_elements(_xml(book)), <String>[after]);
    });

    test('a sheet with no part lists none', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String?>{'S': null}),
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, isEmpty);
      expect(
        () => sheet.addConditionalFormat(
          _format('A1', const XlsxExpressionRule('A1')),
        ),
        throwsStateError,
      );
    });
  });
}

/// A `<conditionalFormatting>` on `A1` of one `<cfRule>` with [attributes]
/// and the children [body].
String _bad(String attributes, String body) =>
    '<conditionalFormatting sqref="A1"><cfRule $attributes'
    '${body.isEmpty ? '/>' : '>$body</cfRule>'}</conditionalFormatting>';
