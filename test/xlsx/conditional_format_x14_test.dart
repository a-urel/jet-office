import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _x14 =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';
const String _xm = 'http://schemas.microsoft.com/office/excel/2006/main';
const String _cfRuleExt = '{B025F937-C7B1-47D3-B67F-A62EFF666E3E}';
const String _sheetExt = '{78C0D931-6437-407d-A8EE-F0AAD7539E65}';

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

/// The worksheet part of sheet `S` after [setup].
String _sheet(void Function(XlsxSheetWriter sheet) setup) =>
    _book(setup)['xl/worksheets/sheet1.xml']!;

/// Adds one format of [rules] on [range] to [sheet].
void _add(
  XlsxSheetWriter sheet,
  List<XlsxConditionalRule> rules, {
  String range = 'A1',
}) {
  sheet.conditionalFormat(
    XlsxConditionalFormat(<XlsxRange>[XlsxRange.parse(range)], rules),
  );
}

/// The worksheet `extLst` of [xml], or '' when there is none.
String _extLst(String xml) =>
    RegExp(
      '<extLst><ext uri="${RegExp.escape(_sheetExt)}".*</extLst>',
    ).firstMatch(xml)?.group(0) ??
    '';

/// The worksheet `extLst` of a sheet with one format on [range] whose one
/// Excel 2010 rule is [cfRule], wrapped as Excel writes it.
String _wrapped(String cfRule, {String range = 'A1'}) =>
    '<extLst><ext uri="$_sheetExt" xmlns:x14="$_x14">'
    '<x14:conditionalFormattings>'
    '<x14:conditionalFormatting xmlns:xm="$_xm">$cfRule'
    '<xm:sqref>$range</xm:sqref></x14:conditionalFormatting>'
    '</x14:conditionalFormattings></ext></extLst>';

/// The `x14:id` reference a 2007 `cfRule` carries for the rule [id].
String _reference(String id) =>
    '<extLst><ext uri="$_cfRuleExt" xmlns:x14="$_x14">'
    '<x14:id>$id</x14:id></ext></extLst>';

/// The x14 GUID of rule [index] (0-based) on sheet [sheet].
String _guid(String sheet, String index) => '{$sheet-0000-4000-8000-$index}';

final XlsxColor _blue = XlsxColor.hex('638EC6');

/// Expects registering [rule] on `A1` to throw an [ArgumentError] named
/// [field] and to record nothing.
void _rejects(XlsxConditionalRule rule, String field) {
  final String xml = _sheet((XlsxSheetWriter s) {
    expect(
      () => _add(s, <XlsxConditionalRule>[rule]),
      throwsA(
        isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', field),
      ),
    );
  });
  expect(xml, isNot(contains('conditionalFormatting')));
  expect(xml, isNot(contains('<extLst>')));
}

void main() {
  group('data bar', () {
    test('keeps its 2007 rule, which gains an x14:id reference', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) =>
            _add(s, <XlsxConditionalRule>[XlsxDataBar(color: _blue)]),
      );
      expect(
        xml,
        contains(
          '<conditionalFormatting sqref="A1"><cfRule type="dataBar" '
          'priority="1"><dataBar><cfvo type="min"/><cfvo type="max"/>'
          '<color rgb="FF638EC6"/></dataBar>'
          '${_reference('{00000001-0000-4000-8000-000000000000}')}'
          '</cfRule></conditionalFormatting>',
        ),
      );
    });
    test('the worksheet extension holds the x14 rule, last', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxDataBar(color: _blue),
        ], range: 'B2:B20'),
      );
      expect(
        _extLst(xml),
        _wrapped(
          '<x14:cfRule type="dataBar" '
          'id="{00000001-0000-4000-8000-000000000000}">'
          '<x14:dataBar minLength="0" maxLength="100">'
          '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
          '</x14:dataBar></x14:cfRule>',
          range: 'B2:B20',
        ),
      );
      expect(xml, endsWith('</extLst></worksheet>'));
    });
    test('writes every x14 attribute and child in schema order', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxDataBar(
            min: XlsxCfValue.number(-10),
            max: const XlsxCfValue.formula(r'=$C$1'),
            color: _blue,
            minLength: 5,
            maxLength: 95,
            gradient: false,
            border: true,
            borderColor: XlsxColor.hex('203864'),
            negativeFillColor: XlsxColor.hex('FF0000'),
            negativeBorderColor: XlsxColor.hex('C00000'),
            axis: XlsxDataBarAxis.middle,
            axisColor: XlsxColor.hex('000000'),
          ),
        ]),
      );
      expect(
        _extLst(xml),
        contains(
          '<x14:dataBar minLength="5" maxLength="95" border="1" '
          'gradient="0" negativeBarColorSameAsPositive="0" '
          'negativeBarBorderColorSameAsPositive="0" axisPosition="middle">'
          '<x14:cfvo type="num"><xm:f>-10</xm:f></x14:cfvo>'
          r'<x14:cfvo type="formula"><xm:f>$C$1</xm:f></x14:cfvo>'
          '<x14:borderColor rgb="FF203864"/>'
          '<x14:negativeFillColor rgb="FFFF0000"/>'
          '<x14:negativeBorderColor rgb="FFC00000"/>'
          '<x14:axisColor rgb="FF000000"/></x14:dataBar>',
        ),
      );
      // The 2007 rule keeps its own lengths.
      expect(xml, contains('<dataBar minLength="5" maxLength="95">'));
    });
    test('the x14 lengths: the defaults 10 and 90 become 0 and 100', () {
      String lengths(int minLength, int maxLength) {
        final String xml = _sheet(
          (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
            XlsxDataBar(
              color: _blue,
              minLength: minLength,
              maxLength: maxLength,
            ),
          ]),
        );
        return RegExp(r'<x14:dataBar [^>]*>').firstMatch(xml)!.group(0)!;
      }

      expect(lengths(10, 90), '<x14:dataBar minLength="0" maxLength="100">');
      expect(lengths(5, 95), '<x14:dataBar minLength="5" maxLength="95">');
    });
    test('percent and percentile carry xm:f; gte="0" is written', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxDataBar(
            min: XlsxCfValue.percent(10, greaterOrEqual: false),
            max: XlsxCfValue.percentile(90),
            color: _blue,
          ),
        ]),
      );
      expect(
        _extLst(xml),
        contains(
          '<x14:cfvo type="percent" gte="0"><xm:f>10</xm:f></x14:cfvo>'
          '<x14:cfvo type="percentile"><xm:f>90</xm:f></x14:cfvo>',
        ),
      );
    });
    test('a border without its own color takes the bar color', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxDataBar(color: _blue, border: true),
        ]),
      );
      expect(
        _extLst(xml),
        contains(
          '<x14:dataBar minLength="0" maxLength="100" border="1">'
          '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
          '<x14:borderColor rgb="FF638EC6"/></x14:dataBar>',
        ),
      );
    });
    test('border colors are written only with a border', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxDataBar(
            color: _blue,
            borderColor: XlsxColor.hex('203864'),
            negativeBorderColor: XlsxColor.hex('C00000'),
          ),
        ]),
      );
      expect(
        _extLst(xml),
        contains(
          '<x14:dataBar minLength="0" maxLength="100">'
          '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
          '</x14:dataBar>',
        ),
      );
    });
    test('no axis writes axisPosition none; a negative fill alone', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxDataBar(
            color: _blue,
            axis: XlsxDataBarAxis.none,
            negativeFillColor: XlsxColor.hex('FF0000'),
          ),
        ]),
      );
      expect(
        _extLst(xml),
        contains(
          '<x14:dataBar minLength="0" maxLength="100" '
          'negativeBarColorSameAsPositive="0" axisPosition="none">'
          '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
          '<x14:negativeFillColor rgb="FFFF0000"/></x14:dataBar>',
        ),
      );
    });
    test('invalid colors throw naming the field', () {
      const XlsxColor bad = XlsxColor.theme(99);
      _rejects(
        XlsxDataBar(color: _blue, border: true, borderColor: bad),
        'rules[0].borderColor',
      );
      _rejects(
        XlsxDataBar(color: _blue, negativeFillColor: bad),
        'rules[0].negativeFillColor',
      );
      _rejects(
        XlsxDataBar(color: _blue, negativeBorderColor: bad),
        'rules[0].negativeBorderColor',
      );
      _rejects(XlsxDataBar(color: _blue, axisColor: bad), 'rules[0].axisColor');
    });
  });

  group('x14-only icon sets', () {
    test('are written only in the worksheet extension, with a priority', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxIconSet(XlsxIconSetType.threeStars),
        ]),
      );
      // No 2007 rule, so no conditionalFormatting, which needs one.
      expect(xml, isNot(contains('<conditionalFormatting')));
      expect(
        _extLst(xml),
        _wrapped(
          '<x14:cfRule type="iconSet" priority="1" '
          'id="{00000001-0000-4000-8000-000000000000}">'
          '<x14:iconSet iconSet="3Stars">'
          '<x14:cfvo type="percent"><xm:f>0</xm:f></x14:cfvo>'
          '<x14:cfvo type="percent"><xm:f>33</xm:f></x14:cfvo>'
          '<x14:cfvo type="percent"><xm:f>67</xm:f></x14:cfvo>'
          '</x14:iconSet></x14:cfRule>',
        ),
      );
    });
    test('thresholds, showValue, reverse and stopIfTrue are written', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxIconSet(
            XlsxIconSetType.fiveBoxes,
            thresholds: <XlsxCfValue>[
              const XlsxCfValue.min(),
              XlsxCfValue.number(10),
              XlsxCfValue.number(20, greaterOrEqual: false),
              const XlsxCfValue.formula(r'$B$1'),
              XlsxCfValue.percentile(90),
            ],
            reverse: true,
            showValue: false,
            stopIfTrue: true,
          ),
        ]),
      );
      expect(
        _extLst(xml),
        contains(
          '<x14:cfRule type="iconSet" priority="1" stopIfTrue="1" '
          'id="{00000001-0000-4000-8000-000000000000}">'
          '<x14:iconSet iconSet="5Boxes" showValue="0" reverse="1">'
          '<x14:cfvo type="min"/>'
          '<x14:cfvo type="num"><xm:f>10</xm:f></x14:cfvo>'
          '<x14:cfvo type="num" gte="0"><xm:f>20</xm:f></x14:cfvo>'
          r'<x14:cfvo type="formula"><xm:f>$B$1</xm:f></x14:cfvo>'
          '<x14:cfvo type="percentile"><xm:f>90</xm:f></x14:cfvo>'
          '</x14:iconSet></x14:cfRule>',
        ),
      );
    });
    test('the x14 sets have their XML names and icon counts', () {
      expect(
        <String>[
          for (final XlsxIconSetType t in XlsxIconSetType.values)
            if (t.isX14Only) '${t.name}/${t.xmlName}/${t.iconCount}',
        ],
        <String>[
          'threeStars/3Stars/3',
          'threeTriangles/3Triangles/3',
          'fiveBoxes/5Boxes/5',
        ],
      );
      expect(XlsxIconSetType.threeArrows.isX14Only, isFalse);
    });
    test('thresholds whose count differs from the icons throw', () {
      _rejects(
        XlsxIconSet(
          XlsxIconSetType.fiveBoxes,
          thresholds: <XlsxCfValue>[
            XlsxCfValue.percent(0),
            XlsxCfValue.percent(50),
          ],
        ),
        'rules[0].thresholds',
      );
    });
  });

  group('priorities and GUIDs', () {
    test('x14-only rules take priorities from the same counter', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        _add(s, <XlsxConditionalRule>[
          const XlsxExpressionRule('TRUE'),
          XlsxIconSet(XlsxIconSetType.threeStars),
          XlsxDataBar(color: _blue),
        ], range: 'A1:A5');
        _add(s, <XlsxConditionalRule>[
          XlsxIconSet(XlsxIconSetType.threeTriangles),
        ], range: 'B1:B5');
      });
      // The 2007 rules are 1 and 3; the x14-only icon sets 2 and 4.
      expect(
        xml,
        contains(
          '<conditionalFormatting sqref="A1:A5">'
          '<cfRule type="expression" priority="1"><formula>TRUE</formula>'
          '</cfRule><cfRule type="dataBar" priority="3">',
        ),
      );
      expect(xml, isNot(contains('<conditionalFormatting sqref="B1:B5">')));
      final String ext = _extLst(xml);
      expect(
        ext,
        contains(
          '<x14:conditionalFormatting xmlns:xm="$_xm">'
          '<x14:cfRule type="iconSet" priority="2" '
          'id="{00000001-0000-4000-8000-000000000001}">',
        ),
      );
      expect(
        ext,
        contains(
          '</x14:cfRule><x14:cfRule type="dataBar" '
          'id="{00000001-0000-4000-8000-000000000002}">',
        ),
      );
      expect(
        ext,
        contains(
          '<xm:sqref>A1:A5</xm:sqref></x14:conditionalFormatting>'
          '<x14:conditionalFormatting xmlns:xm="$_xm">'
          '<x14:cfRule type="iconSet" priority="4" '
          'id="{00000001-0000-4000-8000-000000000003}">',
        ),
      );
      expect(
        ext,
        endsWith(
          '<xm:sqref>B1:B5</xm:sqref>'
          '</x14:conditionalFormatting></x14:conditionalFormattings>'
          '</ext></extLst>',
        ),
      );
      expect(
        xml,
        contains(_reference('{00000001-0000-4000-8000-000000000002}')),
      );
    });
    test('a GUID holds the sheet number and the rule index in hex', () {
      final XlsxWriter book = XlsxWriter();
      for (int i = 1; i <= 10; i++) {
        final XlsxSheetWriter sheet = book.addSheet('S$i');
        _add(sheet, <XlsxConditionalRule>[
          for (int j = 0; j < 10; j++) const XlsxExpressionRule('TRUE'),
          XlsxDataBar(color: _blue),
        ]);
      }
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, String> parts = readXlsx(result.bytes);
      expect(
        parts['xl/worksheets/sheet1.xml'],
        contains(_reference(_guid('00000001', '00000000000A'))),
      );
      expect(
        parts['xl/worksheets/sheet10.xml'],
        contains(_reference(_guid('0000000A', '00000000000A'))),
      );
    });
    test('GUIDs are unique across two sheets', () {
      final XlsxWriter book = XlsxWriter();
      for (final String name in <String>['A', 'B']) {
        _add(book.addSheet(name), <XlsxConditionalRule>[
          XlsxDataBar(color: _blue),
          XlsxIconSet(XlsxIconSetType.threeStars),
        ]);
      }
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, String> parts = readXlsx(result.bytes);
      final List<String> ids = <String>[
        for (final String part in <String>[
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml',
        ])
          ...RegExp(
            r' id="(\{[^}]*\})"',
          ).allMatches(parts[part]!).map((Match m) => m.group(1)!),
      ];
      expect(ids, <String>[
        _guid('00000001', '000000000000'),
        _guid('00000001', '000000000001'),
        _guid('00000002', '000000000000'),
        _guid('00000002', '000000000001'),
      ]);
    });
  });

  group('worksheet', () {
    test('the extLst is the last child, after hyperlinks', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        s.row(<Object?>[XlsxHyperlink.url('https://example.com', text: 'x')]);
        s.merge(XlsxRange.parse('C1:D1'));
        s.dataValidation(
          XlsxDataValidation.whole(
            <XlsxRange>[XlsxRange.parse('E1')],
            XlsxComparison.greaterThan,
            0,
          ),
        );
        _add(s, <XlsxConditionalRule>[XlsxDataBar(color: _blue)]);
      });
      expect(xml, contains('</hyperlinks><extLst>'));
      expect(xml, endsWith('</extLst></worksheet>'));
    });
    test('a sheet without data bars or x14 icon sets has no extLst', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => _add(s, <XlsxConditionalRule>[
          XlsxIconSet(XlsxIconSetType.threeArrows),
        ]),
      );
      expect(xml, isNot(contains('extLst')));
      expect(xml, isNot(contains('x14')));
    });
  });

  group('value semantics', () {
    test('the new data bar fields default as the brief says', () {
      final XlsxDataBar bar = XlsxDataBar(color: _blue);
      expect((bar.gradient, bar.border, bar.borderColor), (true, false, null));
      expect((bar.negativeFillColor, bar.negativeBorderColor), (null, null));
      expect((bar.axis, bar.axisColor), (XlsxDataBarAxis.automatic, null));
      expect(
        XlsxDataBarAxis.values.map((XlsxDataBarAxis a) => a.name),
        <String>['automatic', 'middle', 'none'],
      );
    });
    test('the new fields take part in ==, hashCode and toString', () {
      XlsxDataBar full() => XlsxDataBar(
        color: _blue,
        gradient: false,
        border: true,
        borderColor: XlsxColor.hex('203864'),
        negativeFillColor: XlsxColor.hex('FF0000'),
        negativeBorderColor: XlsxColor.hex('C00000'),
        axis: XlsxDataBarAxis.middle,
        axisColor: XlsxColor.hex('000000'),
      );
      expect(full(), full());
      expect(full().hashCode, full().hashCode);
      final List<XlsxDataBar> variants = <XlsxDataBar>[
        XlsxDataBar(color: _blue),
        XlsxDataBar(color: _blue, gradient: false),
        XlsxDataBar(color: _blue, border: true),
        XlsxDataBar(color: _blue, borderColor: XlsxColor.hex('203864')),
        XlsxDataBar(color: _blue, negativeFillColor: XlsxColor.hex('FF0000')),
        XlsxDataBar(color: _blue, negativeBorderColor: XlsxColor.hex('C00000')),
        XlsxDataBar(color: _blue, axis: XlsxDataBarAxis.none),
        XlsxDataBar(color: _blue, axisColor: XlsxColor.hex('000000')),
      ];
      for (int i = 0; i < variants.length; i++) {
        for (int j = 0; j < i; j++) {
          expect(variants[i], isNot(variants[j]));
        }
      }
      final String text = full().toString();
      for (final String part in <String>[
        'gradient: false',
        'border: true',
        'borderColor:',
        'negativeFillColor:',
        'negativeBorderColor:',
        'axis: middle',
        'axisColor:',
      ]) {
        expect(text, contains(part));
      }
    });
  });
}
