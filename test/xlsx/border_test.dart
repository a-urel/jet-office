import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/border.dart' as impl;
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String xml(XlsxBorder border) {
  final StringBuffer out = StringBuffer();
  impl.writeBorderXml(XmlWriter(out), border);
  return out.toString();
}

void main() {
  const XlsxBorderSide thinBlack = XlsxBorderSide(
    style: XlsxBorderStyle.thin,
    color: XlsxColor.rgb(0),
  );

  test('an empty border is the M1 default', () {
    expect(
      xml(const XlsxBorder()),
      '<border><left/><right/><top/><bottom/><diagonal/></border>',
    );
  });

  test('XlsxBorder.all sets the four outer sides', () {
    expect(
      xml(const XlsxBorder.all(thinBlack)),
      '<border><left style="thin"><color rgb="FF000000"/></left>'
      '<right style="thin"><color rgb="FF000000"/></right>'
      '<top style="thin"><color rgb="FF000000"/></top>'
      '<bottom style="thin"><color rgb="FF000000"/></bottom>'
      '<diagonal/></border>',
    );
  });

  test('a diagonal border writes its flag and a double style', () {
    expect(
      xml(
        const XlsxBorder(
          diagonalUp: true,
          diagonal: XlsxBorderSide(style: XlsxBorderStyle.doubleLine),
        ),
      ),
      '<border diagonalUp="1"><left/><right/><top/><bottom/>'
      '<diagonal style="double"/></border>',
    );
  });

  test('a diagonal side without a direction writes an empty diagonal', () {
    const String empty =
        '<border><left/><right/><top/><bottom/><diagonal/></border>';
    expect(xml(const XlsxBorder(diagonal: thinBlack)), empty);
    expect(
      xml(
        const XlsxBorder(
          diagonalUp: false,
          diagonalDown: false,
          diagonal: thinBlack,
        ),
      ),
      empty,
    );
    expect(
      xml(const XlsxBorder(diagonalDown: true, diagonal: thinBlack)),
      '<border diagonalDown="1"><left/><right/><top/><bottom/>'
      '<diagonal style="thin"><color rgb="FF000000"/></diagonal></border>',
    );
  });

  test('diagonalDown, outline and vertical and horizontal sides', () {
    expect(
      xml(
        const XlsxBorder(
          diagonalDown: true,
          outline: false,
          vertical: XlsxBorderSide(style: XlsxBorderStyle.hair),
          horizontal: XlsxBorderSide(style: XlsxBorderStyle.slantDashDot),
        ),
      ),
      '<border diagonalDown="1" outline="0"><left/><right/><top/><bottom/>'
      '<diagonal/><vertical style="hair"/>'
      '<horizontal style="slantDashDot"/></border>',
    );
  });

  test('a none style is the default and writes no attribute', () {
    expect(
      xml(const XlsxBorder(left: XlsxBorderSide(style: XlsxBorderStyle.none))),
      '<border><left/><right/><top/><bottom/><diagonal/></border>',
    );
  });

  test('a side that draws no line writes like an unset side', () {
    const String empty =
        '<border><left/><right/><top/><bottom/><diagonal/></border>';
    const XlsxColor red = XlsxColor.rgb(0xFF0000);
    for (final XlsxBorder border in <XlsxBorder>[
      const XlsxBorder(
        left: XlsxBorderSide(style: XlsxBorderStyle.none, color: red),
      ),
      const XlsxBorder(top: XlsxBorderSide(color: red)),
      const XlsxBorder(vertical: XlsxBorderSide()),
      const XlsxBorder(
        horizontal: XlsxBorderSide(style: XlsxBorderStyle.none, color: red),
      ),
      const XlsxBorder(diagonalUp: false, diagonalDown: false, outline: true),
    ]) {
      expect(xml(border), empty, reason: '$border');
    }
  });

  test('every style name is the ST_BorderStyle value', () {
    final Map<XlsxBorderStyle, String> expected = <XlsxBorderStyle, String>{
      XlsxBorderStyle.thin: 'thin',
      XlsxBorderStyle.medium: 'medium',
      XlsxBorderStyle.dashed: 'dashed',
      XlsxBorderStyle.dotted: 'dotted',
      XlsxBorderStyle.thick: 'thick',
      XlsxBorderStyle.doubleLine: 'double',
      XlsxBorderStyle.hair: 'hair',
      XlsxBorderStyle.mediumDashed: 'mediumDashed',
      XlsxBorderStyle.dashDot: 'dashDot',
      XlsxBorderStyle.mediumDashDot: 'mediumDashDot',
      XlsxBorderStyle.dashDotDot: 'dashDotDot',
      XlsxBorderStyle.mediumDashDotDot: 'mediumDashDotDot',
      XlsxBorderStyle.slantDashDot: 'slantDashDot',
    };
    expected.forEach((XlsxBorderStyle style, String name) {
      expect(
        xml(XlsxBorder(top: XlsxBorderSide(style: style))),
        contains('<top style="$name"/>'),
      );
    });
  });

  test('merge replaces a side whole and keeps the rest', () {
    const XlsxBorder base = XlsxBorder(
      left: thinBlack,
      top: XlsxBorderSide(style: XlsxBorderStyle.thick),
      diagonalUp: true,
    );
    final XlsxBorder merged = base.merge(
      const XlsxBorder(
        top: XlsxBorderSide(style: XlsxBorderStyle.hair),
        diagonalDown: true,
      ),
    );
    expect(merged.left, thinBlack);
    expect(merged.top, const XlsxBorderSide(style: XlsxBorderStyle.hair));
    expect(merged.diagonalUp, true);
    expect(merged.diagonalDown, true);
    expect(base.merge(null), same(base));
  });

  test('value equality, hashCode and toString', () {
    expect(const XlsxBorder.all(thinBlack), const XlsxBorder.all(thinBlack));
    expect(
      const XlsxBorder.all(thinBlack).hashCode,
      const XlsxBorder.all(thinBlack).hashCode,
    );
    expect(const XlsxBorder.all(thinBlack), isNot(const XlsxBorder()));
    expect(
      thinBlack,
      const XlsxBorderSide(
        style: XlsxBorderStyle.thin,
        color: XlsxColor.rgb(0),
      ),
    );
    expect(thinBlack.toString(), contains('thin'));
    expect(const XlsxBorder(outline: false).toString(), contains('outline'));
  });

  test('validateBorder rejects an invalid side color, naming the field', () {
    expect(
      () => impl.validateBorder(
        const XlsxBorder(left: XlsxBorderSide(color: XlsxColor.rgb(0x1000000))),
      ),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'left')),
    );
    expect(
      () => impl.validateBorder(const XlsxBorder.all(thinBlack)),
      returnsNormally,
    );
  });
}
