import 'package:jet_office/src/xlsx/limits.dart';
import 'package:jet_office/src/xlsx/number_format.dart';
import 'package:jet_office/src/xlsx/style.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  test('registry deduplicates by value', () {
    final StyleRegistry r = StyleRegistry();
    expect(r.idFor(null), 0);
    expect(r.idFor(const XlsxStyle()), 0);
    final int a = r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')));
    expect(r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000'))), a);
    expect(
      r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.localeShortDate)),
      isNot(a),
    );
  });
  test('styles.xml golden', () {
    final StyleRegistry r = StyleRegistry()
      ..idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')))
      ..idFor(const XlsxStyle(numFmt: XlsxNumFmt.localeShortDate));
    final StringBuffer out = StringBuffer();
    r.writeStylesXml(XmlWriter(out));
    expect(out.toString(), _stylesGolden);
  });
  test('an empty registry writes no numFmts', () {
    final StringBuffer out = StringBuffer();
    StyleRegistry().writeStylesXml(XmlWriter(out));
    expect(out.toString(), isNot(contains('<numFmts')));
    expect(out.toString(), contains('<cellXfs count="1">'));
  });
  test('custom ids start at 164 and codes are shared', () {
    final StyleRegistry r = StyleRegistry()
      ..idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('a"b&<')));
    final StringBuffer out = StringBuffer();
    r.writeStylesXml(XmlWriter(out));
    expect(
      out.toString(),
      contains('numFmtId="164" formatCode="a&quot;b&amp;&lt;"'),
    );
  });
  test('invalid built-in id is an ArgumentError', () {
    expect(
      () => StyleRegistry().idFor(
        const XlsxStyle(numFmt: XlsxNumFmt.builtin(200)),
      ),
      throwsArgumentError,
    );
    expect(
      () => StyleRegistry().idFor(
        const XlsxStyle(numFmt: XlsxNumFmt.builtin(-1)),
      ),
      throwsArgumentError,
    );
  });
  test('empty or unscrubbable custom code is an ArgumentError', () {
    expect(
      () =>
          StyleRegistry().idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom(''))),
      throwsArgumentError,
    );
    expect(
      () => StyleRegistry().idFor(
        const XlsxStyle(numFmt: XlsxNumFmt.custom('0\u0001')),
      ),
      throwsArgumentError,
    );
  });
  test('copyWith and equality', () {
    const XlsxStyle s = XlsxStyle();
    final XlsxStyle t = s.copyWith(numFmt: XlsxNumFmt.localeShortDate);
    expect(t.numFmt, XlsxNumFmt.localeShortDate);
    expect(t, const XlsxStyle(numFmt: XlsxNumFmt.localeShortDate));
    expect(
      t.hashCode,
      const XlsxStyle(numFmt: XlsxNumFmt.localeShortDate).hashCode,
    );
    expect(t.copyWith().numFmt, XlsxNumFmt.localeShortDate);
    expect(s, isNot(t));
  });
  test('too many cell formats', () {
    final StyleRegistry r = StyleRegistry();
    expect(() {
      for (int i = 0; i < 65490; i++) {
        r.idFor(
          XlsxStyle(numFmt: XlsxNumFmt.custom('0.${'0' * (i % 30)}"$i"')),
        );
      }
    }, throwsA(isA<XlsxLimitError>()));
  });
}

/// The `styles.xml` for one custom format (`0.000`) and one built-in date
/// format (id 14). Embedded rather than read from a file, so the test runs on
/// the web as well as the VM.
const String _stylesGolden =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="0.000"/></numFmts>'
    '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '<dxfs count="0"/>'
    '<tableStyles count="0"/>'
    '</styleSheet>';
