import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

void main() {
  test('XlsxRowFormat compares by value', () {
    const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
    expect(const XlsxRowFormat(), const XlsxRowFormat());
    expect(
      const XlsxRowFormat(
        height: 24,
        hidden: true,
        outlineLevel: 2,
        collapsed: true,
        style: bold,
      ),
      const XlsxRowFormat(
        height: 24,
        hidden: true,
        outlineLevel: 2,
        collapsed: true,
        style: bold,
      ),
    );
    expect(
      const XlsxRowFormat(height: 24).hashCode,
      const XlsxRowFormat(height: 24).hashCode,
    );
    expect(const XlsxRowFormat(height: 24), isNot(const XlsxRowFormat()));
    expect(const XlsxRowFormat(hidden: true), isNot(const XlsxRowFormat()));
    expect(
      const XlsxRowFormat(outlineLevel: 1),
      isNot(const XlsxRowFormat(outlineLevel: 2)),
    );
    expect(const XlsxRowFormat(collapsed: true), isNot(const XlsxRowFormat()));
    expect(const XlsxRowFormat(style: bold), isNot(const XlsxRowFormat()));
  });

  test('XlsxRowFormat toString names the fields that are set', () {
    expect(const XlsxRowFormat().toString(), 'XlsxRowFormat()');
    expect(
      const XlsxRowFormat(
        height: 24.5,
        hidden: true,
        outlineLevel: 1,
        collapsed: true,
        style: XlsxStyle(font: XlsxFont(bold: true)),
      ).toString(),
      startsWith(
        'XlsxRowFormat(height: 24.5, hidden: true, outlineLevel: 1, '
        'collapsed: true, style: XlsxStyle(',
      ),
    );
    expect(
      const XlsxRowFormat(height: 30).toString(),
      'XlsxRowFormat(height: 30)',
    );
  });
}
