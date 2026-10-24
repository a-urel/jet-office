import 'dart:io';

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
    final String golden = File(
      'test/golden/m1/styles_custom_and_builtin.xml',
    ).readAsStringSync();
    expect(out.toString(), golden);
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
