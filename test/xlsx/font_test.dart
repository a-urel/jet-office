import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/font.dart' as impl;
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String xml(XlsxFont? font) {
  final StringBuffer out = StringBuffer();
  impl.writeFontXml(XmlWriter(out), impl.resolveFont(font));
  return out.toString();
}

void main() {
  const XlsxColor red = XlsxColor.rgb(0xC00000);

  test('the default font equals the M1 default font', () {
    expect(xml(null), '<font><sz val="11"/><name val="Calibri"/></font>');
    expect(
      xml(const XlsxFont()),
      '<font><sz val="11"/><name val="Calibri"/></font>',
    );
  });

  test('every property is written in CT_Font order', () {
    expect(
      xml(
        const XlsxFont(
          bold: true,
          italic: true,
          underline: XlsxUnderline.doubleLine,
          strike: true,
          script: XlsxFontScript.superscript,
          size: 14,
          color: red,
          name: 'Arial',
        ),
      ),
      '<font><b/><i/><strike/><u val="double"/><vertAlign val="superscript"/>'
      '<sz val="14"/><color rgb="FFC00000"/><name val="Arial"/></font>',
    );
    expect(
      xml(
        const XlsxFont(
          condense: true,
          extend: true,
          outline: true,
          shadow: true,
          family: 2,
          charset: 1,
          scheme: XlsxFontScheme.minor,
        ),
      ),
      '<font><condense/><extend/><outline/><shadow/><sz val="11"/>'
      '<name val="Calibri"/><family val="2"/><charset val="1"/>'
      '<scheme val="minor"/></font>',
    );
  });

  test('underline values', () {
    String u(XlsxUnderline v) => xml(XlsxFont(underline: v));
    expect(u(XlsxUnderline.single), contains('<u/>'));
    expect(
      u(XlsxUnderline.singleAccounting),
      contains('<u val="singleAccounting"/>'),
    );
    expect(
      u(XlsxUnderline.doubleAccounting),
      contains('<u val="doubleAccounting"/>'),
    );
    expect(u(XlsxUnderline.none), isNot(contains('<u')));
  });

  test('false, none and baseline are omitted', () {
    expect(
      xml(
        const XlsxFont(
          bold: false,
          italic: false,
          strike: false,
          underline: XlsxUnderline.none,
          script: XlsxFontScript.baseline,
          scheme: XlsxFontScheme.none,
        ),
      ),
      '<font><sz val="11"/><name val="Calibri"/></font>',
    );
    expect(
      xml(const XlsxFont(script: XlsxFontScript.subscript)),
      contains('<vertAlign val="subscript"/>'),
    );
  });

  test('a fractional size is written with formatXmlDouble', () {
    expect(xml(const XlsxFont(size: 10.5)), contains('<sz val="10.5"/>'));
  });

  test('merge: non-null fields of the other font win', () {
    const XlsxFont base = XlsxFont(bold: true, color: red);
    expect(
      base.merge(const XlsxFont(bold: false)),
      const XlsxFont(bold: false, color: red),
    );
    expect(base.merge(null), base);
    expect(base.merge(null).hashCode, base.hashCode);
    expect(
      base.copyWith(name: 'Arial'),
      const XlsxFont(bold: true, color: red, name: 'Arial'),
    );
    expect(const XlsxFont(bold: true), isNot(const XlsxFont(italic: true)));
    expect(base.toString(), contains('bold: true'));
  });

  test('resolveFont keeps given name and size', () {
    final XlsxFont f = impl.resolveFont(const XlsxFont(name: 'X', size: 9));
    expect(f.name, 'X');
    expect(f.size, 9);
  });

  test('validateFont accepts the limits', () {
    impl.validateFont(impl.resolveFont(null));
    impl.validateFont(XlsxFont(name: 'a' * 31, size: 1));
    impl.validateFont(const XlsxFont(name: 'a', size: 409, family: 14));
    impl.validateFont(const XlsxFont(name: 'a', size: 11, charset: 255));
  });

  test('validateFont rejects bad values naming the field', () {
    void bad(XlsxFont f, String field) => expect(
      () => impl.validateFont(f),
      throwsA(
        isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', field),
      ),
    );
    bad(const XlsxFont(name: 'a', size: 0), 'size');
    bad(const XlsxFont(name: 'a', size: 410), 'size');
    bad(const XlsxFont(name: 'a', size: double.nan), 'size');
    bad(const XlsxFont(name: 'a', size: double.infinity), 'size');
    bad(XlsxFont(name: 'a' * 32, size: 11), 'name');
    bad(const XlsxFont(name: '', size: 11), 'name');
    bad(const XlsxFont(name: 'a\u0001', size: 11), 'name');
    bad(const XlsxFont(name: 'a', size: 11, family: 15), 'family');
    bad(const XlsxFont(name: 'a', size: 11, family: -1), 'family');
    bad(const XlsxFont(name: 'a', size: 11, charset: 256), 'charset');
    bad(
      const XlsxFont(name: 'a', size: 11, color: XlsxColor.theme(12)),
      'color',
    );
  });

  group('writeRunPropertiesXml', () {
    String rPr(XlsxFont font) {
      final StringBuffer out = StringBuffer();
      impl.writeRunPropertiesXml(XmlWriter(out), font);
      return out.toString();
    }

    test('writes every property in Excel\'s order, the name as rFont', () {
      expect(
        rPr(
          const XlsxFont(
            scheme: XlsxFontScheme.minor,
            charset: 1,
            family: 2,
            name: 'Arial',
            color: red,
            size: 14,
            script: XlsxFontScript.superscript,
            underline: XlsxUnderline.doubleLine,
            shadow: true,
            outline: true,
            extend: true,
            condense: true,
            strike: true,
            italic: true,
            bold: true,
          ),
        ),
        '<rPr><b/><i/><strike/><condense/><extend/><outline/><shadow/>'
        '<u val="double"/><vertAlign val="superscript"/><sz val="14"/>'
        '<color rgb="FFC00000"/><rFont val="Arial"/><family val="2"/>'
        '<charset val="1"/><scheme val="minor"/></rPr>',
      );
    });

    test('writes only the fields the font sets', () {
      expect(rPr(const XlsxFont(bold: true)), '<rPr><b/></rPr>');
      expect(
        rPr(const XlsxFont(name: 'Arial', size: 9.5)),
        '<rPr><sz val="9.5"/><rFont val="Arial"/></rPr>',
      );
      expect(
        rPr(const XlsxFont(underline: XlsxUnderline.single)),
        '<rPr><u/></rPr>',
      );
    });

    test('false, none and baseline are omitted', () {
      expect(
        rPr(
          const XlsxFont(
            bold: false,
            italic: false,
            strike: false,
            condense: false,
            extend: false,
            outline: false,
            shadow: false,
            underline: XlsxUnderline.none,
            script: XlsxFontScript.baseline,
            scheme: XlsxFontScheme.none,
          ),
        ),
        '<rPr/>',
      );
    });
  });
}
