import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xlsx/model/conditional_elements.dart';
import 'package:jet_office/src/xlsx/model/conditional_x14.dart';
import 'package:jet_office/src/xlsx/model/element_node.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

const String _part = 'xl/worksheets/sheet1.xml';
const String _extUri = '{78C0D931-6437-407d-A8EE-F0AAD7539E65}';
const String _ruleExtUri = '{B025F937-C7B1-47D3-B67F-A62EFF666E3E}';
const String _sparklineUri = '{05C60535-1F16-4fd2-B633-F4F36F0B64E0}';
const String _id1 = '{00000001-0000-4000-8000-000000000000}';
const String _id2 = '{00000001-0000-4000-8000-000000000001}';

final XlsxColor _blue = XlsxColor.hex('638EC6');
final XlsxColor _green = XlsxColor.hex('63C384');

XlsxRange _r(String ref) => XlsxRange.parse(ref);

XlsxConditionalFormat _format(String ref, XlsxConditionalRule rule) =>
    XlsxConditionalFormat(<XlsxRange>[_r(ref)], <XlsxConditionalRule>[rule]);

String _sheet(String body, {String root = ''}) =>
    '<worksheet xmlns="$mainNs"$root><sheetData/>$body</worksheet>';

Uint8List _file(String body, {String root = '', String? styles}) =>
    buildWorkbook(<String, String>{
      'S': _sheet(body, root: root),
    }, styles: styles);

XlsxWorkbook _open(String body, {String root = '', String? styles}) =>
    XlsxWorkbook.open(_file(body, root: root, styles: styles));

String _xml(XlsxWorkbook book) => partText(book.save().bytes, _part);

int _invalid(XlsxWorkbook book, String detail) => book.warnings
    .where(
      (XlsxWarning w) =>
          w.code == XlsxWarningCode.featureEntryInvalid && w.detail == detail,
    )
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

/// A 2007 data bar on [sqref] naming the Excel 2010 rule [id].
String _bar2007(String sqref, String id, {int priority = 1}) =>
    '<conditionalFormatting sqref="$sqref">'
    '<cfRule type="dataBar" priority="$priority"><dataBar><cfvo type="min"/>'
    '<cfvo type="max"/><color rgb="FF638EC6"/></dataBar>'
    '<extLst><ext uri="$_ruleExtUri" xmlns:x14="${Ns.x14}">'
    '<x14:id>$id</x14:id></ext></extLst></cfRule></conditionalFormatting>';

/// The Excel 2010 half of a bar, [body] inside `x14:dataBar`.
String _barRule(
  String id, {
  String attributes = 'minLength="0" maxLength="100"',
  String body =
      '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
      '<x14:negativeFillColor rgb="FFFF0000"/>'
      '<x14:axisColor rgb="FF000000"/>',
}) =>
    '<x14:cfRule type="dataBar" id="$id">'
    '<x14:dataBar $attributes>$body</x14:dataBar></x14:cfRule>';

/// An Excel 2010 icon set rule of [priority].
String _iconRule(String id, int priority, {String set = '3Stars'}) =>
    '<x14:cfRule type="iconSet" priority="$priority" id="$id">'
    '<x14:iconSet iconSet="$set">'
    '<x14:cfvo type="percent"><xm:f>0</xm:f></x14:cfvo>'
    '<x14:cfvo type="percent"><xm:f>33</xm:f></x14:cfvo>'
    '<x14:cfvo type="percent"><xm:f>67</xm:f></x14:cfvo>'
    '</x14:iconSet></x14:cfRule>';

/// One `x14:conditionalFormatting` of [rules] on [sqref].
String _element(String sqref, String rules) =>
    '<x14:conditionalFormatting xmlns:xm="${Ns.xm}">$rules'
    '<xm:sqref>$sqref</xm:sqref></x14:conditionalFormatting>';

/// The ext of [elements].
String _ext(String elements) =>
    '<ext uri="$_extUri" xmlns:x14="${Ns.x14}">'
    '<x14:conditionalFormattings>$elements</x14:conditionalFormattings>'
    '</ext>';

const String _sparklines =
    '<ext uri="$_sparklineUri" xmlns:x14="${Ns.x14}">'
    '<x14:sparklineGroups xmlns:xm="${Ns.xm}"><x14:sparklineGroup>'
    '<x14:sparklines><x14:sparkline><xm:f>S!A1:C1</xm:f>'
    '<xm:sqref>D1</xm:sqref></x14:sparkline></x14:sparklines>'
    '</x14:sparklineGroup></x14:sparklineGroups></ext>';

/// A value of every field an Excel 2010 rule holds, for the add and reopen
/// tests.
List<XlsxConditionalFormat> _x14Formats() => <XlsxConditionalFormat>[
  _format('A1:A5', XlsxDataBar(color: _blue)),
  _format(
    'B1:B5',
    XlsxDataBar(
      min: XlsxCfValue.number(1),
      max: const XlsxCfValue.formula(r'=$Z$1'),
      color: _green,
      showValue: false,
      minLength: 5,
      maxLength: 95,
      gradient: false,
      border: true,
      borderColor: _green,
      negativeFillColor: XlsxColor.hex('FF0000'),
      negativeBorderColor: _blue,
      axis: XlsxDataBarAxis.none,
      axisColor: XlsxColor.hex('000000'),
      stopIfTrue: true,
    ),
  ),
  _format(
    'C1:C5',
    XlsxDataBar(
      color: _blue,
      minLength: 0,
      maxLength: 100,
      borderColor: _green,
      negativeBorderColor: _green,
    ),
  ),
  _format(
    'D1:D5',
    XlsxDataBar(
      min: const XlsxCfValue(XlsxCfValueType.min, value: '3'),
      max: const XlsxCfValue.max(greaterOrEqual: false),
      color: _blue,
      border: true,
      borderColor: _blue,
      negativeFillColor: _green,
      axis: XlsxDataBarAxis.middle,
      axisColor: _green,
    ),
  ),
  _format('E1:E5', XlsxIconSet(XlsxIconSetType.threeStars)),
  _format(
    'F1:F5',
    XlsxIconSet(
      XlsxIconSetType.fiveBoxes,
      thresholds: <XlsxCfValue>[
        XlsxCfValue.percent(0),
        XlsxCfValue.percent(10),
        XlsxCfValue.number(20),
        const XlsxCfValue.formula(r'=$A$1'),
        XlsxCfValue.percentile(90, greaterOrEqual: false),
      ],
      reverse: true,
      showValue: false,
      stopIfTrue: true,
    ),
  ),
  XlsxConditionalFormat(
    <XlsxRange>[_r('G1:G5'), _r('I1')],
    <XlsxConditionalRule>[
      XlsxIconSet(XlsxIconSetType.threeTriangles),
      const XlsxExpressionRule('G1>0'),
      XlsxDataBar(color: _blue),
      XlsxIconSet(XlsxIconSetType.threeStars),
    ],
  ),
];

void main() {
  group('reading', () {
    test('reads m3_conditional_x14', () {
      final Fixture fixture = allFixtures().firstWhere(
        (Fixture f) => f.name == 'm3_conditional_x14',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(fixture.build());
      XlsxConditionalFormat column(int c, XlsxConditionalRule rule) =>
          XlsxConditionalFormat(
            <XlsxRange>[XlsxRange(1, c, 21, c)],
            <XlsxConditionalRule>[rule],
          );
      final List<XlsxConditionalFormat> written = <XlsxConditionalFormat>[
        column(
          0,
          XlsxDataBar(
            color: _blue,
            negativeFillColor: XlsxColor.hex('FF0000'),
            axis: XlsxDataBarAxis.middle,
          ),
        ),
        column(1, XlsxDataBar(color: _green, gradient: false, border: true)),
        column(2, XlsxIconSet(XlsxIconSetType.threeStars)),
        column(3, XlsxIconSet(XlsxIconSetType.threeTriangles)),
        column(4, XlsxIconSet(XlsxIconSetType.fiveBoxes)),
      ];
      // The first bar's red is what the writer fills for none, so the file
      // cannot tell the two apart: it reads as none.
      expect(
        book.sheets.single.conditionalFormats,
        written.map(normalizedConditionalFormat),
      );
      expect(
        book.sheets.single.conditionalFormats.first.rules.single,
        XlsxDataBar(color: _blue, axis: XlsxDataBarAxis.middle),
      );
      expect(book.warnings, isEmpty);
    });

    test('the Excel 2010 fields lie over the Excel 2007 rule', () {
      final XlsxWorkbook book = _open(
        '${_bar2007('A1:A5', _id1)}<extLst>'
        '${_ext(_element('A1:A5', _barRule(_id1, attributes: 'minLength="20" maxLength="80" border="1" gradient="0" negativeBarBorderColorSameAsPositive="0" axisPosition="middle"', body: '<x14:cfvo type="num"><xm:f>2</xm:f></x14:cfvo><x14:cfvo type="autoMax"/><x14:borderColor rgb="FF00FF00"/><x14:negativeFillColor rgb="FF0000FF"/><x14:negativeBorderColor rgb="FF111111"/><x14:axisColor theme="4"/>')))}'
        '</extLst>',
      );
      expect(
        book.sheets.single.conditionalFormats.single.rules.single,
        XlsxDataBar(
          min: XlsxCfValue.number(2),
          color: _blue,
          minLength: 20,
          maxLength: 80,
          gradient: false,
          border: true,
          borderColor: XlsxColor.hex('00FF00'),
          negativeFillColor: XlsxColor.hex('0000FF'),
          negativeBorderColor: XlsxColor.hex('111111'),
          axis: XlsxDataBarAxis.middle,
          axisColor: const XlsxColor.theme(4),
        ),
      );
    });

    test('a negative border color counts only when Excel uses it', () {
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', _id1)}<extLst>'
        '${_ext(_element('A1', _barRule(_id1, attributes: 'minLength="0" maxLength="100" border="1"', body: '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/><x14:borderColor rgb="FF638EC6"/><x14:negativeBorderColor rgb="FF111111"/>')))}'
        '</extLst>',
      );
      expect(
        book.sheets.single.conditionalFormats.single.rules.single,
        XlsxDataBar(color: _blue, border: true),
      );
    });

    test('an id naming nothing keeps the 2007 fields, unreported', () {
      final XlsxWorkbook book = _open(_bar2007('A1', _id1));
      expect(
        book.sheets.single.conditionalFormats.single.rules.single,
        XlsxDataBar(color: _blue),
      );
      expect(book.warnings, isEmpty);
    });

    test('an unlinked rule joins the format with an equal sqref', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1:A5 C1">'
        '<cfRule type="expression" priority="1"><formula>A1</formula></cfRule>'
        '<cfRule type="expression" priority="3"><formula>A2</formula></cfRule>'
        '</conditionalFormatting><extLst>'
        '${_ext(_element('A1:A5 C1', _iconRule(_id1, 2)) + _element('B1', _iconRule(_id2, 4)))}'
        '</extLst>',
      );
      final XlsxIconSet stars = XlsxIconSet(XlsxIconSetType.threeStars);
      expect(book.sheets.single.conditionalFormats, <XlsxConditionalFormat>[
        XlsxConditionalFormat(
          <XlsxRange>[_r('A1:A5'), _r('C1')],
          <XlsxConditionalRule>[
            const XlsxExpressionRule('A1'),
            stars,
            const XlsxExpressionRule('A2'),
          ],
        ),
        _format('B1', stars),
      ]);
    });

    test('an expression with a cross-sheet reference reads', () {
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1:A5', '<x14:cfRule type="expression" priority="1" stopIfTrue="1" id="$_id1"><xm:f>Other!\$A\$1&gt;0</xm:f><x14:dxf><font><b/></font></x14:dxf></x14:cfRule>'))}</extLst>',
      );
      expect(book.sheets.single.conditionalFormats, <XlsxConditionalFormat>[
        _format(
          'A1:A5',
          const XlsxExpressionRule(
            r'Other!$A$1>0',
            style: XlsxStyle(font: XlsxFont(bold: true)),
            stopIfTrue: true,
          ),
        ),
      ]);
      expect(book.warnings, isEmpty);
    });

    test('a cell value rule reads from xm:f', () {
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1', '<x14:cfRule type="cellIs" priority="1" operator="between" id="$_id1"><xm:f>Other!\$A\$1</xm:f><xm:f>Other!\$A\$2</xm:f><x14:dxf><font><i/></font></x14:dxf></x14:cfRule>'))}</extLst>',
      );
      expect(
        book.sheets.single.conditionalFormats.single.rules.single,
        const XlsxCellValueRule(
          XlsxComparison.between,
          r'Other!$A$1',
          formula2: r'Other!$A$2',
          style: XlsxStyle(font: XlsxFont(italic: true)),
        ),
      );
    });

    test('elements match by namespace, not by prefix', () {
      final XlsxWorkbook book = _open(
        '<extLst><ext uri="$_extUri" xmlns:y="${Ns.x14}" xmlns:f="${Ns.xm}">'
        '<y:conditionalFormattings><y:conditionalFormatting>'
        '<y:cfRule type="iconSet" priority="1" id="$_id1">'
        '<y:iconSet iconSet="3Stars"><y:cfvo type="percent"><f:f>0</f:f>'
        '</y:cfvo><y:cfvo type="percent"><f:f>33</f:f></y:cfvo>'
        '<y:cfvo type="percent"><f:f>67</f:f></y:cfvo></y:iconSet></y:cfRule>'
        '<f:sqref>A1</f:sqref></y:conditionalFormatting>'
        '</y:conditionalFormattings></ext></extLst>',
      );
      expect(book.sheets.single.conditionalFormats, <XlsxConditionalFormat>[
        _format('A1', XlsxIconSet(XlsxIconSetType.threeStars)),
      ]);
    });

    test('a custom icon set stays kept and unlisted', () {
      const String custom =
          '<x14:cfRule type="iconSet" priority="1" id="$_id1">'
          '<x14:iconSet iconSet="3Stars" custom="1">'
          '<x14:cfvo type="percent"><xm:f>0</xm:f></x14:cfvo>'
          '<x14:cfvo type="percent"><xm:f>33</xm:f></x14:cfvo>'
          '<x14:cfvo type="percent"><xm:f>67</xm:f></x14:cfvo>'
          '<x14:cfIcon iconSet="3Flags" iconId="0"/>'
          '<x14:cfIcon iconSet="3Flags" iconId="1"/>'
          '<x14:cfIcon iconSet="3Flags" iconId="2"/>'
          '</x14:iconSet></x14:cfRule>';
      final Uint8List input = _file(
        '<extLst>${_ext(_element('A1', custom))}</extLst>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(book.sheets.single.conditionalFormats, isEmpty);
      expect(book.warnings, isEmpty);
      expect(comparePackages(input, book.save().bytes), isEmpty);
    });

    test('another kind of rule stays kept and unlisted, unreported', () {
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1', '<x14:cfRule type="containsText" priority="1" id="$_id1"><xm:f>A1</xm:f></x14:cfRule>'))}</extLst>',
      );
      expect(book.sheets.single.conditionalFormats, isEmpty);
      expect(book.warnings, isEmpty);
    });

    test('an opened file saves unchanged', () {
      final Uint8List input = _file(
        '${_bar2007('A1', _id1)}<extLst>'
        '${_ext(_element('A1', _barRule(_id1)))}$_sparklines</extLst>',
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
      _x14Formats().forEach(written.conditionalFormat);
      final Uint8List expected = writer.close().bytes;

      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      _x14Formats().forEach(sheet.addConditionalFormat);
      expect(
        compareXml(
          _part,
          partText(expected, _part),
          partText(book.save().bytes, _part),
        ),
        isEmpty,
      );
    });

    test('the getter after an add is the getter after a reopen', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      _x14Formats().forEach(sheet.addConditionalFormat);
      final XlsxWorkbook reopened = XlsxWorkbook.open(book.save().bytes);
      expect(
        sheet.conditionalFormats,
        reopened.sheets.single.conditionalFormats,
      );
      expect(reopened.warnings, isEmpty);
    });

    test('what is added reads back as normalizedConditionalFormat says', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      _x14Formats().forEach(sheet.addConditionalFormat);
      final List<XlsxConditionalFormat> read = sheet.conditionalFormats;
      // A format of the ext alone comes after those with a 2007 element.
      expect(
        read,
        unorderedEquals(_x14Formats().map(normalizedConditionalFormat)),
      );
    });

    test('a format of Excel 2010 icon sets alone makes no 2007 element', () {
      final XlsxWorkbook book = _open('');
      book.sheets.single.addConditionalFormat(
        _format('A1', XlsxIconSet(XlsxIconSetType.threeStars)),
      );
      final String xml = _xml(book);
      expect(xml, isNot(contains('<conditionalFormatting')));
      expect(xml, contains('<x14:conditionalFormatting'));
    });

    test('a new rule joins the file\'s ext and element list', () {
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', _id1)}<extLst>'
        '${_ext(_element('A1', _barRule(_id1)))}$_sparklines</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.addConditionalFormat(_format('B1', XlsxDataBar(color: _green)));
      final String xml = _xml(book);
      // Two for the 2007 rules, one for the sheet.
      expect('<extLst>'.allMatches(xml), hasLength(3));
      expect('<x14:conditionalFormattings'.allMatches(xml), hasLength(1));
      expect('<x14:conditionalFormatting '.allMatches(xml), hasLength(2));
      expect(xml.indexOf(_sparklineUri), greaterThan(xml.indexOf('B1</xm')));
      expect(sheet.conditionalFormats, hasLength(2));
    });

    test('priorities continue past the Excel 2010 rules', () {
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1', _iconRule(_id1, 7)))}</extLst>',
      );
      book.sheets.single.addConditionalFormat(
        _format('B1', const XlsxExpressionRule('B1')),
      );
      expect(_xml(book), contains('priority="8"'));
    });

    test('ids do not collide', () {
      // Priority 2 is next, and with sheet 1 that is the id `_id2`: a rule of
      // the file, which the Excel 2007 rule of priority 1 does not name.
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', _id2)}<extLst>'
        '${_ext(_element('A1', _barRule(_id2)))}</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      final XlsxDataBar added = XlsxDataBar(color: _green, gradient: false);
      sheet.addConditionalFormat(_format('B1', added));
      final String xml = _xml(book);
      expect(RegExp(RegExp.escape(_id2)).allMatches(xml), hasLength(2));
      expect(
        sheet.conditionalFormats.last,
        normalizedConditionalFormat(_format('B1', added)),
      );
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.conditionalFormats,
        sheet.conditionalFormats,
      );
    });

    test('an id only an unlisted element uses does not collide', () {
      const String unread =
          '<conditionalFormatting sqref="A1">'
          '<cfRule type="nonsense" priority="1"><extLst>'
          '<ext uri="$_ruleExtUri" xmlns:x14="${Ns.x14}">'
          '<x14:id>$_id2</x14:id></ext></extLst></cfRule>'
          '</conditionalFormatting>';
      final XlsxWorkbook book = _open(unread);
      book.sheets.single.addConditionalFormat(
        _format('B1', XlsxDataBar(color: _green)),
      );
      expect(RegExp(RegExp.escape(_id2)).allMatches(_xml(book)), hasLength(1));
    });

    test('a prefixed worksheet keeps extLst in SpreadsheetML', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String>{
          'S': '<x:worksheet xmlns:x="$mainNs"><x:sheetData/></x:worksheet>',
        }),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.addConditionalFormat(_format('A1', XlsxDataBar(color: _blue)));
      final Uint8List saved = book.save().bytes;
      expect(partText(saved, _part), contains('<x:extLst>'));
      expect(
        XlsxWorkbook.open(saved).sheets.single.conditionalFormats,
        sheet.conditionalFormats,
      );
      expect(
        (sheet.conditionalFormats.single.rules.single as XlsxDataBar).color,
        _blue,
      );
    });

    test('a bad rule throws; nothing changes', () {
      final XlsxWorkbook book = _open('');
      final XlsxSheet sheet = book.sheets.single;
      expect(
        () => sheet.addConditionalFormat(
          _format('A1', XlsxDataBar(color: _blue, minLength: 200)),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'rules[0].minLength',
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(sheet.conditionalFormats, isEmpty);
    });

    test('an add undoes and redoes, both halves', () {
      final XlsxWorkbook book = _open('');
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      final XlsxConditionalFormat format = _format(
        'A1',
        XlsxDataBar(color: _blue),
      );
      sheet.conditionalFormats;
      final String before = _xml(book);
      final ChangeSet set = log.transaction(
        () => sheet.addConditionalFormat(format),
      );
      final String after = _xml(book);
      expect(after, contains('x14:cfRule'));
      log.revertSet(set);
      expect(sheet.conditionalFormats, isEmpty);
      expect(_xml(book), before);
      log.reapplySet(set);
      expect(sheet.conditionalFormats, <XlsxConditionalFormat>[format]);
      expect(_xml(book), after);
    });
  });

  group('removing', () {
    String twoBars() =>
        '${_bar2007('A1', _id1)}${_bar2007('B1', _id2, priority: 2)}';

    test('a data bar\'s halves leave together; undo restores both', () {
      final Uint8List input = _file(
        '${twoBars()}<extLst>'
        '${_ext(_element('A1', _barRule(_id1)) + _element('B1', _barRule(_id2)))}'
        '</extLst>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      sheet.conditionalFormats;
      final String before = _xml(book);
      final ChangeSet set = log.transaction(
        () => sheet.removeConditionalFormat(sheet.conditionalFormats.first),
      );
      final String xml = _xml(book);
      expect(xml, isNot(contains(_id1)));
      expect(RegExp(RegExp.escape(_id2)).allMatches(xml), hasLength(2));
      expect(sheet.conditionalFormats.single.ranges, <XlsxRange>[_r('B1')]);
      log.revertSet(set);
      expect(_xml(book), before);
      expect(sheet.conditionalFormats, hasLength(2));
      log.reapplySet(set);
      expect(_xml(book), xml);
    });

    test('the last format takes the element, the ext and extLst with it', () {
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', _id1)}<extLst>'
        '${_ext(_element('A1', _barRule(_id1)))}</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      sheet.conditionalFormats;
      final String before = _xml(book);
      final ChangeSet set = log.transaction(
        () => sheet.removeConditionalFormat(sheet.conditionalFormats.single),
      );
      expect(_xml(book), isNot(contains('extLst')));
      expect(_xml(book), isNot(contains('conditionalFormatting')));
      log.revertSet(set);
      expect(_xml(book), before);
    });

    test('other exts survive', () {
      final XlsxWorkbook book = _open('<extLst>$_sparklines</extLst>');
      final XlsxSheet sheet = book.sheets.single;
      sheet.conditionalFormats;
      final String before = _xml(book);
      sheet.addConditionalFormat(_format('A1', XlsxDataBar(color: _blue)));
      expect(_xml(book), contains(_sparklineUri));
      expect(_xml(book), contains(_extUri));
      sheet.removeConditionalFormat(sheet.conditionalFormats.single);
      expect(_xml(book), before);
    });

    test('other children of the ext survive', () {
      const String other = '<o:keep xmlns:o="urn:o"/>';
      final XlsxWorkbook book = _open(
        '<extLst><ext uri="$_extUri" xmlns:x14="${Ns.x14}">'
        '<x14:conditionalFormattings>'
        '${_element('A1', _iconRule(_id1, 1))}'
        '</x14:conditionalFormattings>$other</ext></extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.removeConditionalFormat(sheet.conditionalFormats.single);
      final String xml = _xml(book);
      expect(xml, contains(other));
      expect(xml, isNot(contains('conditionalFormattings')));
      expect(xml, contains(_extUri));
    });

    test('one x14 element shared by two formats keeps the other\'s rule', () {
      final String shared = _element(
        'A1 B1',
        '${_barRule(_id1)}'
            '${_barRule(_id2, attributes: 'minLength="0" maxLength="100" gradient="0"')}',
      );
      final XlsxWorkbook book = _open(
        '${twoBars()}<extLst>${_ext(shared)}</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, hasLength(2));
      sheet.removeConditionalFormat(sheet.conditionalFormats.first);
      final String xml = _xml(book);
      expect(xml, isNot(contains(_id1)));
      expect(xml, contains('<xm:sqref>A1 B1</xm:sqref>'));
      expect(
        sheet.conditionalFormats.single.rules.single,
        XlsxDataBar(color: _blue, gradient: false),
      );
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.conditionalFormats,
        sheet.conditionalFormats,
      );
    });

    test('a kept rule keeps its element', () {
      const String kept =
          '<x14:cfRule type="containsText" priority="2" id="$_id2">'
          '<xm:f>A1</xm:f></x14:cfRule>';
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1', _iconRule(_id1, 1) + kept))}</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.removeConditionalFormat(sheet.conditionalFormats.single);
      final String xml = _xml(book);
      expect(xml, contains(kept));
      expect(xml, contains('<xm:sqref>A1</xm:sqref>'));
      expect(xml, isNot(contains(_id1)));
    });

    test('what was added can be removed as it was given', () {
      final XlsxWorkbook book = _open('');
      final XlsxSheet sheet = book.sheets.single;
      sheet.conditionalFormats;
      final String before = _xml(book);
      final List<XlsxConditionalFormat> formats = _x14Formats();
      formats.forEach(sheet.addConditionalFormat);
      formats.forEach(sheet.removeConditionalFormat);
      expect(sheet.conditionalFormats, isEmpty);
      expect(_xml(book), before);
    });

    test('add, reopen, remove with the original value', () {
      final XlsxWorkbook first = _open('');
      _x14Formats().forEach(first.sheets.single.addConditionalFormat);
      final XlsxWorkbook book = XlsxWorkbook.open(first.save().bytes);
      final XlsxSheet sheet = book.sheets.single;
      _x14Formats().forEach(sheet.removeConditionalFormat);
      expect(sheet.conditionalFormats, isEmpty);
      expect(_xml(book), isNot(contains('extLst')));
    });

    test('a format of rules in the ext alone is removed', () {
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1', _iconRule(_id1, 1)) + _element('B1', _iconRule(_id2, 2)))}</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.removeConditionalFormat(
        _format('A1', XlsxIconSet(XlsxIconSetType.threeStars)),
      );
      expect(sheet.conditionalFormats.single.ranges, <XlsxRange>[_r('B1')]);
      expect(_xml(book), isNot(contains(_id1)));
    });

    test('a rule another 2007 rule still names stays', () {
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', _id1)}${_bar2007('B1', _id1, priority: 2)}<extLst>'
        '${_ext(_element('A1', _barRule(_id1, attributes: 'gradient="0"')))}'
        '</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.removeConditionalFormat(sheet.conditionalFormats.first);
      expect(
        sheet.conditionalFormats.single.rules.single,
        XlsxDataBar(color: _blue, gradient: false),
      );
    });
  });

  group('normalizedConditionalFormat', () {
    XlsxDataBar normalized(XlsxDataBar bar) =>
        normalizedConditionalFormat(_format('A1', bar)).rules.single
            as XlsxDataBar;

    test('what the writer fills reads as none', () {
      expect(
        normalized(
          XlsxDataBar(
            color: _blue,
            border: true,
            borderColor: _blue,
            negativeFillColor: XlsxColor.hex('FF0000'),
            axisColor: XlsxColor.hex('000000'),
          ),
        ),
        XlsxDataBar(color: _blue, border: true),
      );
    });

    test('a border color goes without a border', () {
      expect(
        normalized(
          XlsxDataBar(
            color: _blue,
            borderColor: _green,
            negativeBorderColor: _green,
          ),
        ),
        XlsxDataBar(color: _blue),
      );
    });

    test('other colors stay', () {
      final XlsxDataBar bar = XlsxDataBar(
        color: _blue,
        border: true,
        borderColor: _green,
        negativeFillColor: _green,
        negativeBorderColor: _green,
        axisColor: _green,
      );
      expect(normalized(bar), bar);
    });
  });

  group('kept as written', () {
    test('bad values are kept and reported', () {
      const String noId =
          '<x14:cfRule type="iconSet" priority="1">'
          '<x14:iconSet iconSet="3Stars"/></x14:cfRule>';
      const String badBar =
          '<x14:cfRule type="dataBar" id="{bad}">'
          '<x14:dataBar minLength="500"/></x14:cfRule>';
      const String badIcons =
          '<x14:cfRule type="iconSet" priority="3" id="{icons}">'
          '<x14:iconSet iconSet="nonsense"/></x14:cfRule>';
      const String badCell =
          '<x14:cfRule type="cellIs" priority="4" operator="nope" id="{cell}">'
          '<xm:f>1</xm:f></x14:cfRule>';
      // The defaults of the unlinked bar put this past the longest bar.
      const String longBar =
          '<x14:cfRule type="dataBar" priority="6" id="{long}">'
          '<x14:dataBar minLength="95"><x14:cfvo type="autoMin"/>'
          '<x14:cfvo type="autoMax"/><x14:fillColor rgb="FF638EC6"/>'
          '</x14:dataBar></x14:cfRule>';
      final String badSqref = _element('not a range', _iconRule(_id1, 2));
      final String noSqref =
          '<x14:conditionalFormatting xmlns:xm="${Ns.xm}">'
          '${_iconRule(_id2, 5)}</x14:conditionalFormatting>';
      final Uint8List input = _file(
        '<extLst>${_ext(_element('A1', noId + badBar + badIcons + badCell + longBar) + badSqref + noSqref)}</extLst>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, isEmpty);
      expect(_invalid(book, 'x14:cfRule'), 5);
      expect(_invalid(book, 'x14:conditionalFormatting'), 2);
      expect(comparePackages(input, book.save().bytes), isEmpty);
      sheet.addConditionalFormat(_format('B1', XlsxDataBar(color: _green)));
      final String xml = _xml(book);
      for (final String kept in <String>[
        noId,
        badBar,
        longBar,
        badSqref,
        noSqref,
      ]) {
        expect(xml, contains(kept));
      }
    });

    test('several rules with one id: the first gives the fields', () {
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', _id1)}<extLst>'
        '${_ext(_element('A1', _barRule(_id1, attributes: 'gradient="0"') + _barRule(_id1, attributes: 'border="1"')))}'
        '</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(
        sheet.conditionalFormats.single.rules.single,
        XlsxDataBar(color: _blue, gradient: false),
      );
      sheet.removeConditionalFormat(sheet.conditionalFormats.single);
      expect(_xml(book), isNot(contains('extLst')));
    });

    test('prefixes the root declares survive an edit of a shared element', () {
      final String noDeclarations =
          '<ext uri="$_extUri"><x14:conditionalFormattings>'
          '<x14:conditionalFormatting>'
          '${_iconRule(_id1, 1)}'
          '${_iconRule(_id2, 2, set: '3Triangles')}'
          '<xm:sqref>A1</xm:sqref></x14:conditionalFormatting>'
          '<x14:conditionalFormatting>${_iconRule('{3}', 3)}'
          '<xm:sqref>B1</xm:sqref></x14:conditionalFormatting>'
          '</x14:conditionalFormattings></ext>';
      final XlsxWorkbook book = _open(
        '<extLst>$noDeclarations</extLst>',
        root: ' xmlns:x14="${Ns.x14}" xmlns:xm="${Ns.xm}"',
      );
      final XlsxSheet sheet = book.sheets.single;
      final XlsxConditionalFormat second = sheet.conditionalFormats.last;
      sheet.addConditionalFormat(_format('C1', XlsxDataBar(color: _blue)));
      sheet.removeConditionalFormat(second);
      final List<XlsxConditionalFormat> left = sheet.conditionalFormats;
      expect(left, hasLength(2));
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.conditionalFormats,
        left,
      );
      expect(_xml(book), isNot(contains('xmlns:x14="${Ns.x14}" xmlns:x14')));
    });

    test('a style the types cannot hold whole reads, and is not exact', () {
      String rule(String dxf) =>
          '<x14:cfRule type="expression" priority="1" id="$_id1">'
          '<xm:f>A1</xm:f><x14:dxf>$dxf</x14:dxf></x14:cfRule>';
      X14Rule read(String dxf) {
        final XmlPullReader r = XmlPullReader(
          '<extLst xmlns="$mainNs">${_ext(_element('A1', rule(dxf)))}</extLst>',
        )..next();
        final XmlNode node = XmlNode.read(r, const <String, Set<String>>{
          'extLst': <String>{'ext'},
        });
        return readX14Block(node)!.elements.single.rules.single;
      }

      expect(read('<font><b/></font>').exact, isTrue);
      final X14Rule inexact = read('<font><b/></font><alignment/>');
      expect(inexact.exact, isFalse);
      expect(inexact.rule, isA<XlsxExpressionRule>());
    });

    test('a bad half keeps the 2007 fields and is reported', () {
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', _id1)}<extLst>'
        '${_ext(_element('A1', _barRule(_id1, attributes: 'minLength="500"')))}'
        '</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(
        sheet.conditionalFormats.single.rules.single,
        XlsxDataBar(color: _blue),
      );
      expect(_invalid(book, 'x14:cfRule'), 1);
      sheet.removeConditionalFormat(sheet.conditionalFormats.single);
      expect(_xml(book), isNot(contains('extLst')));
    });

    test('a bar whose lengths cross the 2007 ones keeps the 2007 ones', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1">'
        '<cfRule type="dataBar" priority="1"><dataBar maxLength="40">'
        '<cfvo type="min"/><cfvo type="max"/><color rgb="FF638EC6"/></dataBar>'
        '<extLst><ext uri="$_ruleExtUri" xmlns:x14="${Ns.x14}">'
        '<x14:id>$_id1</x14:id></ext></extLst></cfRule>'
        '</conditionalFormatting><extLst>'
        '${_ext(_element('A1', _barRule(_id1, attributes: 'minLength="50"')))}'
        '</extLst>',
      );
      expect(
        book.sheets.single.conditionalFormats.single.rules.single,
        XlsxDataBar(color: _blue, maxLength: 40),
      );
    });

    test('the half of an unreadable 2007 element stays unlisted', () {
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1">'
        '<cfRule type="dataBar" priority="1"><dataBar/><extLst>'
        '<ext uri="$_ruleExtUri" xmlns:x14="${Ns.x14}">'
        '<x14:id>$_id1</x14:id></ext></extLst></cfRule>'
        '</conditionalFormatting><extLst>'
        '${_ext(_element('A1', _barRule(_id1, body: '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/><x14:fillColor rgb="FF638EC6"/>')))}'
        '</extLst>',
      );
      expect(book.sheets.single.conditionalFormats, isEmpty);
    });

    test('an unlinked bar with a fill reads, one without stays kept', () {
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1', _barRule(_id1, body: '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/><x14:fillColor rgb="FF638EC6"/>')) + _element('B1', _barRule(_id2)))}</extLst>',
      );
      expect(book.sheets.single.conditionalFormats, <XlsxConditionalFormat>[
        _format('A1', XlsxDataBar(color: _blue, minLength: 0, maxLength: 100)),
      ]);
      expect(book.warnings, isEmpty);
    });

    test('ids match in any case, as a GUID does', () {
      const String lower = '{0000000a-0000-4000-8000-00000000000b}';
      const String upper = '{0000000A-0000-4000-8000-00000000000B}';
      final XlsxWorkbook book = _open(
        '${_bar2007('A1', lower)}<extLst>'
        '${_ext(_element('A1', _barRule(upper, attributes: 'gradient="0"')))}'
        '</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, <XlsxConditionalFormat>[
        _format('A1', XlsxDataBar(color: _blue, gradient: false)),
      ]);
      sheet.removeConditionalFormat(sheet.conditionalFormats.single);
      expect(_xml(book), isNot(contains('extLst')));
    });

    test('the half of an unlisted element matches in any case too', () {
      const String lower = '{0000000a-0000-4000-8000-00000000000b}';
      const String upper = '{0000000A-0000-4000-8000-00000000000B}';
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1">'
        '<cfRule type="dataBar" priority="1"><dataBar/><extLst>'
        '<ext uri="$_ruleExtUri" xmlns:x14="${Ns.x14}">'
        '<x14:id>$lower</x14:id></ext></extLst></cfRule>'
        '</conditionalFormatting><extLst>'
        '${_ext(_element('A1', _iconRule(upper, 2)))}</extLst>',
      );
      expect(book.sheets.single.conditionalFormats, isEmpty);
    });

    test('rules on equal priorities keep file order; none goes last', () {
      final XlsxIconSet stars = XlsxIconSet(XlsxIconSetType.threeStars);
      final XlsxIconSet triangles = XlsxIconSet(XlsxIconSetType.threeTriangles);
      final String noPriority = _iconRule(
        '{n}',
        0,
      ).replaceFirst(' priority="0"', '');
      final XlsxWorkbook book = _open(
        '<conditionalFormatting sqref="A1">'
        '<cfRule type="expression" priority="5"><formula>A1</formula></cfRule>'
        '<cfRule type="expression" priority="2"><formula>A2</formula></cfRule>'
        '</conditionalFormatting><extLst>'
        '${_ext(_element('A1', noPriority + _iconRule('{a}', 9) + _iconRule('{b}', 3, set: '3Triangles') + _iconRule('{c}', 3) + _iconRule('{d}', 1)))}'
        '</extLst>',
      );
      expect(
        book.sheets.single.conditionalFormats.single.rules,
        <XlsxConditionalRule>[
          stars,
          triangles,
          stars,
          const XlsxExpressionRule('A1'),
          const XlsxExpressionRule('A2'),
          stars,
          stars,
        ],
      );
    });

    group('a file of very many rules joins in linear time', () {
      const int count = 150000;
      void joins(String name, String Function(int i) sqref, int formats) {
        test(name, testOn: 'vm', () {
          final StringBuffer elements = StringBuffer();
          for (int i = 0; i < count; i++) {
            elements.write(_element(sqref(i), _iconRule('{$i}', i + 1)));
          }
          final XlsxSheet sheet = _open(
            '<extLst>${_ext(elements.toString())}</extLst>',
          ).sheets.single;
          // Loads the sheet, so that only the join is timed. A test's timeout
          // cannot stop code that never yields, so the bound is checked after:
          // a fraction of a second here, minutes when quadratic.
          sheet.dataValidations;
          final Stopwatch watch = Stopwatch()..start();
          final List<XlsxConditionalFormat> read = sheet.conditionalFormats;
          expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
          expect(read, hasLength(formats));
          expect(
            read.fold<int>(
              0,
              (int n, XlsxConditionalFormat f) => n + f.rules.length,
            ),
            count,
          );
        });
      }

      joins('on as many ranges', (int i) => 'A${i + 1}', count);
      joins('on one range', (int i) => 'A1', 1);
    });

    test('a repeated ext stays as written; its ids and priorities count', () {
      final XlsxWorkbook book = _open(
        '<extLst>${_ext(_element('A1', _iconRule(_id1, 1)))}'
        '${_ext(_element('B1', _iconRule(_id2, 9)))}</extLst>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.conditionalFormats, hasLength(1));
      sheet.addConditionalFormat(_format('C1', XlsxDataBar(color: _blue)));
      expect(_xml(book), contains('priority="10"'));
      expect(_xml(book), contains('<xm:sqref>B1</xm:sqref>'));
    });

    test('an empty extLst and a foreign ext read as none', () {
      for (final String body in <String>[
        '<extLst/>',
        '<extLst><ext/></extLst>',
        '<extLst><ext uri="$_extUri"/></extLst>',
        '<extLst><ext uri="$_extUri" xmlns:x14="${Ns.x14}">'
            '<x14:conditionalFormattings/></ext></extLst>',
        '<extLst><ext uri="$_extUri" xmlns:x14="${Ns.x14}">'
            '<x14:conditionalFormattings><x14:conditionalFormatting/>'
            '</x14:conditionalFormattings></ext></extLst>',
      ]) {
        final Uint8List input = _file(body);
        final XlsxWorkbook book = XlsxWorkbook.open(input);
        final XlsxSheet sheet = book.sheets.single;
        expect(sheet.conditionalFormats, isEmpty, reason: body);
        expect(comparePackages(input, book.save().bytes), isEmpty);
        sheet.addConditionalFormat(_format('C1', XlsxDataBar(color: _blue)));
        expect(sheet.conditionalFormats, hasLength(1), reason: body);
        expect(
          XlsxWorkbook.open(book.save().bytes).sheets.single.conditionalFormats,
          sheet.conditionalFormats,
          reason: body,
        );
      }
    });
  });
}
