import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

void main() {
  const XlsxNumFmt money = XlsxNumFmt.custom('#,##0.00" ₺"');
  const XlsxStyle moneyColumn = XlsxStyle(
    numFmt: money,
    font: XlsxFont(color: XlsxColor.rgb(0x1F4E79)),
    fill: XlsxFill.solid(XlsxColor.rgb(0xEEEEEE)),
    border: XlsxBorder(left: XlsxBorderSide(style: XlsxBorderStyle.thin)),
    alignment: XlsxAlignment(horizontal: XlsxHorizontalAlignment.right),
    protection: XlsxProtection(locked: false),
  );
  const XlsxStyle boldRow = XlsxStyle(font: XlsxFont(bold: true));

  test('money column merged with a bold row carries both', () {
    final XlsxStyle merged = moneyColumn.merge(boldRow);
    expect(merged.numFmt, money);
    expect(
      merged.font,
      const XlsxFont(color: XlsxColor.rgb(0x1F4E79), bold: true),
    );
    expect(merged.fill, moneyColumn.fill);
    expect(merged.border, moneyColumn.border);
    expect(merged.alignment, moneyColumn.alignment);
    expect(merged.protection, moneyColumn.protection);
  });

  test('a null part never erases an inherited one', () {
    expect(moneyColumn.merge(const XlsxStyle()), moneyColumn);
    expect(moneyColumn.merge(null), moneyColumn);
    expect(const XlsxStyle().merge(moneyColumn), moneyColumn);
  });

  test('font, border, alignment and protection merge field by field', () {
    final XlsxStyle merged = moneyColumn.merge(
      const XlsxStyle(
        border: XlsxBorder(top: XlsxBorderSide(style: XlsxBorderStyle.thick)),
        alignment: XlsxAlignment(wrapText: true),
        protection: XlsxProtection(hidden: true),
      ),
    );
    expect(
      merged.border,
      const XlsxBorder(
        left: XlsxBorderSide(style: XlsxBorderStyle.thin),
        top: XlsxBorderSide(style: XlsxBorderStyle.thick),
      ),
    );
    expect(
      merged.alignment,
      const XlsxAlignment(
        horizontal: XlsxHorizontalAlignment.right,
        wrapText: true,
      ),
    );
    expect(
      merged.protection,
      const XlsxProtection(locked: false, hidden: true),
    );
  });

  test('a number format and a fill are replaced whole', () {
    final XlsxStyle merged = moneyColumn.merge(
      const XlsxStyle(
        numFmt: XlsxNumFmt.general,
        fill: XlsxFill.pattern(
          XlsxPatternType.lightGrid,
          background: XlsxColor.rgb(0xFF0000),
        ),
      ),
    );
    expect(merged.numFmt, XlsxNumFmt.general);
    expect(
      merged.fill,
      const XlsxFill.pattern(
        XlsxPatternType.lightGrid,
        background: XlsxColor.rgb(0xFF0000),
      ),
    );
  });

  test('a field set back to its default wins', () {
    final XlsxStyle merged = const XlsxStyle(
      font: XlsxFont(bold: true),
    ).merge(const XlsxStyle(font: XlsxFont(bold: false)));
    expect(merged.font, const XlsxFont(bold: false));
  });

  test('copyWith replaces the given fields and keeps the rest', () {
    final XlsxStyle copy = moneyColumn.copyWith(
      numFmt: XlsxNumFmt.general,
      font: const XlsxFont(italic: true),
    );
    expect(copy.numFmt, XlsxNumFmt.general);
    expect(copy.font, const XlsxFont(italic: true));
    expect(copy.fill, moneyColumn.fill);
    expect(copy.border, moneyColumn.border);
    expect(copy.alignment, moneyColumn.alignment);
    expect(copy.protection, moneyColumn.protection);
    expect(moneyColumn.copyWith(), moneyColumn);
    final XlsxStyle all = const XlsxStyle().copyWith(
      numFmt: money,
      font: moneyColumn.font,
      fill: moneyColumn.fill,
      border: moneyColumn.border,
      alignment: moneyColumn.alignment,
      protection: moneyColumn.protection,
    );
    expect(all, moneyColumn);
  });

  test('value equality, hashCode and toString', () {
    const XlsxStyle same = XlsxStyle(
      numFmt: money,
      font: XlsxFont(color: XlsxColor.rgb(0x1F4E79)),
      fill: XlsxFill.solid(XlsxColor.rgb(0xEEEEEE)),
      border: XlsxBorder(left: XlsxBorderSide(style: XlsxBorderStyle.thin)),
      alignment: XlsxAlignment(horizontal: XlsxHorizontalAlignment.right),
      protection: XlsxProtection(locked: false),
    );
    expect(same, moneyColumn);
    expect(same.hashCode, moneyColumn.hashCode);
    for (final XlsxStyle other in <XlsxStyle>[
      moneyColumn.copyWith(numFmt: XlsxNumFmt.general),
      moneyColumn.copyWith(font: const XlsxFont()),
      moneyColumn.copyWith(fill: const XlsxFill.solid(XlsxColor.rgb(0))),
      moneyColumn.copyWith(border: const XlsxBorder()),
      moneyColumn.copyWith(alignment: const XlsxAlignment()),
      moneyColumn.copyWith(protection: const XlsxProtection()),
    ]) {
      expect(other, isNot(moneyColumn));
    }
    expect(const XlsxStyle().toString(), 'XlsxStyle()');
    expect(boldRow.toString(), 'XlsxStyle(font: XlsxFont(bold: true))');
    expect(
      const XlsxStyle(numFmt: XlsxNumFmt.general).toString(),
      'XlsxStyle(numFmt: XlsxNumFmt.builtin(0))',
    );
  });
}
