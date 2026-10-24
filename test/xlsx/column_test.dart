import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

void main() {
  const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));

  test('defaults', () {
    const XlsxColumn c = XlsxColumn();
    expect(c.width, isNull);
    expect(c.style, isNull);
    expect(c.hidden, isFalse);
    expect(c.outlineLevel, 0);
    expect(c.collapsed, isFalse);
  });

  test('compares by value', () {
    const XlsxColumn a = XlsxColumn(width: 12, style: bold, outlineLevel: 1);
    // Built at run time, so it is a different instance from `a`.
    final XlsxColumn b = XlsxColumn(
      width: double.parse('12'),
      style: XlsxStyle(font: XlsxFont(bold: bool.parse('true'))),
      outlineLevel: 1,
    );
    expect(identical(a, b), isFalse);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const XlsxColumn(width: 12, style: bold)));
    expect(a, isNot(const XlsxColumn(width: 13, style: bold, outlineLevel: 1)));
    expect(const XlsxColumn(hidden: true), isNot(const XlsxColumn()));
    expect(const XlsxColumn(collapsed: true), isNot(const XlsxColumn()));
  });

  test('toString names the fields that are set', () {
    expect(const XlsxColumn().toString(), 'XlsxColumn()');
    expect(
      const XlsxColumn(
        width: 12.5,
        hidden: true,
        outlineLevel: 2,
        collapsed: true,
      ).toString(),
      'XlsxColumn(width: 12.5, hidden: true, outlineLevel: 2, '
      'collapsed: true)',
    );
    expect(
      const XlsxColumn(style: bold).toString(),
      'XlsxColumn(style: $bold)',
    );
  });

  test('toString prints the width like the file does, on every platform', () {
    // `formatXmlDouble`, as XlsxPane does: `12`, not the VM's `12.0`.
    expect(const XlsxColumn(width: 12).toString(), 'XlsxColumn(width: 12)');
    expect(const XlsxColumn(width: 1e-7).toString(), 'XlsxColumn(width: 1e-7)');
    // Not yet validated, so toString must not throw on it.
    expect(
      const XlsxColumn(width: double.nan).toString(),
      'XlsxColumn(width: NaN)',
    );
  });
}
