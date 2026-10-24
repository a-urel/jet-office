import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' show XmlDocument, XmlElement;

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
  test('the second custom code gets id 165', () {
    final StyleRegistry r = StyleRegistry()
      ..idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')))
      ..idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0000')));
    final StringBuffer out = StringBuffer();
    r.writeStylesXml(XmlWriter(out));
    expect(out.toString(), contains('numFmtId="164" formatCode="0.000"'));
    expect(out.toString(), contains('numFmtId="165" formatCode="0.0000"'));
  });
  test('equal codes share an id', () {
    final StyleRegistry r = StyleRegistry();
    final int a = r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')));
    final int b = r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.000')));
    expect(b, a);
    final StringBuffer out = StringBuffer();
    r.writeStylesXml(XmlWriter(out));
    expect(out.toString(), contains('<numFmts count="1">'));
  });
  test('an explicit General shares cell format 0', () {
    // General is numFmtId 0, as in cell format 0, so the two `<xf>` would be
    // identical. An explicit General wins when styles are merged, before the
    // registry sees the result.
    final StyleRegistry r = StyleRegistry();
    expect(r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.general)), 0);
  });
  test('the 201st custom code throws and registers nothing', () {
    final StyleRegistry r = StyleRegistry();
    for (int i = 0; i < XlsxLimits.maxNumberFormats; i++) {
      expect(r.idFor(XlsxStyle(numFmt: XlsxNumFmt.custom('0.0"$i"'))), i + 1);
    }
    expect(
      () => r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0"x"'))),
      throwsA(
        isA<XlsxLimitError>()
            .having((e) => e.limit, 'limit', 'number formats')
            .having((e) => e.max, 'max', 200),
      ),
    );
    // Nothing was registered: a code already known still works, and a
    // built-in format takes the next cell format id.
    expect(r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0"0"'))), 1);
    expect(r.idFor(const XlsxStyle(numFmt: XlsxNumFmt.builtin(14))), 201);
    final StringBuffer out = StringBuffer();
    r.writeStylesXml(XmlWriter(out));
    expect(out.toString(), contains('<numFmts count="200">'));
    expect(out.toString(), contains('<cellXfs count="202">'));
    expect(out.toString(), isNot(contains('0.0&quot;x&quot;')));
  });

  group('equivalent styles share one cell format', () {
    const XlsxFill yellow = XlsxFill.solid(XlsxColor.rgb(0xFFFF00));
    final List<(String, XlsxStyle, XlsxStyle)> pairs =
        <(String, XlsxStyle, XlsxStyle)>[
          (
            'an empty font and Calibri 11',
            const XlsxStyle(fill: yellow, font: XlsxFont()),
            const XlsxStyle(
              fill: yellow,
              font: XlsxFont(name: 'Calibri', size: 11),
            ),
          ),
          (
            'bold false and no font',
            const XlsxStyle(fill: yellow, font: XlsxFont(bold: false)),
            const XlsxStyle(fill: yellow),
          ),
          (
            'general alignment and no alignment',
            const XlsxStyle(
              fill: yellow,
              alignment: XlsxAlignment(
                horizontal: XlsxHorizontalAlignment.general,
              ),
            ),
            const XlsxStyle(fill: yellow),
          ),
          (
            'a hex color and the same rgb color',
            XlsxStyle(font: XlsxFont(color: XlsxColor.hex('1f4e79'))),
            const XlsxStyle(font: XlsxFont(color: XlsxColor.rgb(0x1F4E79))),
          ),
          (
            'a none pattern and no fill',
            const XlsxStyle(
              font: XlsxFont(bold: true),
              fill: XlsxFill.pattern(XlsxPatternType.none),
            ),
            const XlsxStyle(font: XlsxFont(bold: true)),
          ),
          (
            'a none pattern with colors and no fill',
            const XlsxStyle(
              font: XlsxFont(bold: true),
              fill: XlsxFill.pattern(
                XlsxPatternType.none,
                foreground: XlsxColor.rgb(0xFF0000),
              ),
            ),
            const XlsxStyle(font: XlsxFont(bold: true)),
          ),
          (
            'an empty border and no border',
            const XlsxStyle(fill: yellow, border: XlsxBorder()),
            const XlsxStyle(fill: yellow),
          ),
          (
            'an empty vertical side and no vertical side',
            const XlsxStyle(
              fill: yellow,
              border: XlsxBorder(vertical: XlsxBorderSide()),
            ),
            const XlsxStyle(fill: yellow),
          ),
          (
            'a none side with a color and no side',
            const XlsxStyle(
              fill: yellow,
              border: XlsxBorder(
                left: XlsxBorderSide(
                  style: XlsxBorderStyle.none,
                  color: XlsxColor.rgb(0xFF0000),
                ),
                horizontal: XlsxBorderSide(style: XlsxBorderStyle.none),
              ),
            ),
            const XlsxStyle(fill: yellow),
          ),
          (
            'a colored side without a style and no side',
            const XlsxStyle(
              fill: yellow,
              border: XlsxBorder(
                top: XlsxBorderSide(color: XlsxColor.rgb(0xFF0000)),
              ),
            ),
            const XlsxStyle(fill: yellow),
          ),
          (
            'default protection and no protection',
            const XlsxStyle(
              fill: yellow,
              protection: XlsxProtection(locked: true, hidden: false),
            ),
            const XlsxStyle(fill: yellow),
          ),
          (
            'an explicit General and no number format',
            const XlsxStyle(fill: yellow, numFmt: XlsxNumFmt.general),
            const XlsxStyle(fill: yellow),
          ),
        ];
    for (final (String name, XlsxStyle a, XlsxStyle b) in pairs) {
      test(name, () {
        final StyleRegistry r = StyleRegistry();
        final int id = r.idFor(a);
        expect(r.idFor(b), id);
        // Neither spelling adds a font, fill or border the other lacks.
        expect(_xml(r), _xml(StyleRegistry()..idFor(b)));
      });
    }

    test('every default spelling is cell format 0', () {
      final StyleRegistry r = StyleRegistry();
      for (final XlsxStyle style in <XlsxStyle>[
        const XlsxStyle(font: XlsxFont()),
        const XlsxStyle(font: XlsxFont(name: 'Calibri', size: 11)),
        const XlsxStyle(fill: XlsxFill.pattern(XlsxPatternType.none)),
        const XlsxStyle(border: XlsxBorder(diagonalUp: false, outline: true)),
        const XlsxStyle(alignment: XlsxAlignment(indent: 0)),
        const XlsxStyle(protection: XlsxProtection(locked: true)),
        const XlsxStyle(numFmt: XlsxNumFmt.general),
      ]) {
        expect(r.idFor(style), 0, reason: '$style');
      }
      expect(_xml(r), _emptyGolden);
    });

    test('a colorless gray125 pattern is fill 1', () {
      final StyleRegistry r = StyleRegistry();
      expect(
        r.idFor(
          const XlsxStyle(fill: XlsxFill.pattern(XlsxPatternType.gray125)),
        ),
        1,
      );
      final String xml = _xml(r);
      expect(xml, contains('<fills count="2">'));
      expect(xml, contains('fillId="1" borderId="0" xfId="0" applyFill="1"'));
    });
  });

  test('an empty registry writes the M1 styles.xml', () {
    expect(_xml(StyleRegistry()), _emptyGolden);
  });

  test('styles.xml golden with every part', () {
    final StyleRegistry r = StyleRegistry();
    expect(
      r.idFor(
        const XlsxStyle(
          font: XlsxFont(
            name: 'Arial',
            size: 14,
            bold: true,
            color: XlsxColor.rgb(0xFF0000),
          ),
        ),
      ),
      1,
    );
    expect(
      r.idFor(
        const XlsxStyle(
          fill: XlsxFill.solid(XlsxColor.rgb(0xFFFF00)),
          border: XlsxBorder.all(
            XlsxBorderSide(
              style: XlsxBorderStyle.thin,
              color: XlsxColor.rgb(0),
            ),
          ),
        ),
      ),
      2,
    );
    expect(
      r.idFor(
        XlsxStyle(
          fill: XlsxGradientFill.linear(
            degree: 90,
            stops: const <XlsxGradientStop>[
              XlsxGradientStop(0, XlsxColor.rgb(0xFFFFFF)),
              XlsxGradientStop(1, XlsxColor.rgb(0x4472C4)),
            ],
          ),
          alignment: const XlsxAlignment(
            horizontal: XlsxHorizontalAlignment.center,
            vertical: XlsxVerticalAlignment.center,
            wrapText: true,
          ),
        ),
      ),
      3,
    );
    expect(
      r.idFor(const XlsxStyle(protection: XlsxProtection(locked: false))),
      4,
    );
    expect(r.idFor(XlsxStyle(numFmt: XlsxNumFmt.money(symbol: '₺'))), 5);
    final String xml = _xml(r);
    expect(xml, _fullGolden);
    final XmlDocument doc = XmlDocument.parse(xml);
    expect(
      doc.rootElement.childElements.map((XmlElement e) => e.name.local),
      <String>[
        'numFmts',
        'fonts',
        'fills',
        'borders',
        'cellStyleXfs',
        'cellXfs',
        'cellStyles',
        'dxfs',
        'tableStyles',
      ],
    );
  });

  group('an invalid style part is an ArgumentError and registers nothing', () {
    final Map<String, XlsxStyle> invalid = <String, XlsxStyle>{
      'size': const XlsxStyle(font: XlsxFont(size: 0)),
      'name': const XlsxStyle(font: XlsxFont(name: '')),
      'foreground': const XlsxStyle(fill: XlsxFill.solid(XlsxColor.theme(12))),
      'stops': XlsxStyle(
        fill: XlsxGradientFill.linear(
          stops: const <XlsxGradientStop>[
            XlsxGradientStop(0, XlsxColor.rgb(0)),
          ],
        ),
      ),
      'left': const XlsxStyle(
        border: XlsxBorder(
          left: XlsxBorderSide(
            style: XlsxBorderStyle.thin,
            color: XlsxColor.indexed(66),
          ),
        ),
      ),
      'indent': const XlsxStyle(alignment: XlsxAlignment(indent: 251)),
    };
    invalid.forEach((String field, XlsxStyle style) {
      test(field, () {
        final StyleRegistry r = StyleRegistry();
        expect(
          () => r.idFor(style),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', field)),
        );
        expect(_xml(r), _emptyGolden);
      });
    });
  });

  test('an invalid part that is unused by the file is still rejected', () {
    // A none pattern writes fill 0 whatever its colors, but a bad color is
    // still the caller's mistake.
    expect(
      () => StyleRegistry().idFor(
        const XlsxStyle(
          fill: XlsxFill.pattern(
            XlsxPatternType.none,
            foreground: XlsxColor.theme(12),
          ),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('the 513th font throws and registers nothing', () {
    expect(XlsxLimits.maxFonts, 512);
    final StyleRegistry r = StyleRegistry();
    for (int i = 1; i < XlsxLimits.maxFonts; i++) {
      expect(r.idFor(XlsxStyle(font: XlsxFont(name: 'F$i'))), i);
    }
    expect(
      () => r.idFor(const XlsxStyle(font: XlsxFont(name: 'One too many'))),
      throwsA(
        isA<XlsxLimitError>()
            .having((e) => e.limit, 'limit', 'fonts')
            .having((e) => e.max, 'max', 512),
      ),
    );
    // Nothing was registered: a known font still works, a style without a
    // new font takes the next cell format id, and the table holds 512 fonts.
    expect(r.idFor(const XlsxStyle(font: XlsxFont(name: 'F1'))), 1);
    expect(
      r.idFor(const XlsxStyle(alignment: XlsxAlignment(wrapText: true))),
      512,
    );
    final String xml = _xml(r);
    expect(xml, contains('<fonts count="512">'));
    expect(xml, isNot(contains('One too many')));
  });

  group('idsFor', () {
    test('gives the ids idFor gives, in order', () {
      final StyleRegistry r = StyleRegistry();
      const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
      expect(r.idsFor(<XlsxStyle?>[null, bold, const XlsxStyle(), bold]), <int>[
        0,
        1,
        0,
        1,
      ]);
      expect(r.idFor(bold), 1);
    });

    test('a limit hit by a later style records none of the earlier', () {
      final StyleRegistry r = StyleRegistry();
      for (int i = 1; i < XlsxLimits.maxFonts - 1; i++) {
        r.idFor(XlsxStyle(font: XlsxFont(name: 'F$i')));
      }
      // 511 fonts: the first new font fits, the second does not.
      expect(
        () => r.idsFor(const <XlsxStyle?>[
          XlsxStyle(font: XlsxFont(name: 'F1')),
          XlsxStyle(
            font: XlsxFont(name: 'Fits'),
            numFmt: XlsxNumFmt.custom('0.0'),
          ),
          XlsxStyle(
            font: XlsxFont(name: 'F2'),
            fill: XlsxFill.solid(XlsxColor.rgb(1)),
          ),
          XlsxStyle(font: XlsxFont(name: 'Too many')),
        ]),
        throwsA(isA<XlsxLimitError>()),
      );
      final String xml = _xml(r);
      expect(xml, contains('<fonts count="511">'));
      expect(xml, contains('<fills count="2">'));
      expect(xml, isNot(contains('numFmts')));
      expect(xml, contains('<cellXfs count="511">'));
      // The font, code and cell format id handed out before the throw are
      // free again: the same style registers as if for the first time.
      expect(
        r.idFor(
          const XlsxStyle(
            font: XlsxFont(name: 'Fits'),
            numFmt: XlsxNumFmt.custom('0.0'),
          ),
        ),
        511,
      );
      expect(_xml(r), contains('<fonts count="512">'));
      expect(_xml(r), contains('numFmtId="164" formatCode="0.0"'));
    });

    test('an invalid later style records none of the earlier', () {
      final StyleRegistry r = StyleRegistry();
      expect(
        () => r.idsFor(const <XlsxStyle?>[
          XlsxStyle(font: XlsxFont(bold: true)),
          XlsxStyle(numFmt: XlsxNumFmt.builtin(200)),
        ]),
        throwsArgumentError,
      );
      expect(_xml(r), _xml(StyleRegistry()));
      expect(
        r.idFor(const XlsxStyle(alignment: XlsxAlignment(wrapText: true))),
        1,
      );
    });
  });

  test('a limit hit by one part records none of the others', () {
    final StyleRegistry r = StyleRegistry();
    for (int i = 0; i < XlsxLimits.maxNumberFormats; i++) {
      r.idFor(XlsxStyle(numFmt: XlsxNumFmt.custom('0.0"$i"')));
    }
    expect(
      () => r.idFor(
        const XlsxStyle(
          numFmt: XlsxNumFmt.custom('0.0"x"'),
          font: XlsxFont(name: 'Arial'),
          fill: XlsxFill.solid(XlsxColor.rgb(0xFFFF00)),
          border: XlsxBorder(top: XlsxBorderSide(style: XlsxBorderStyle.thin)),
        ),
      ),
      throwsA(isA<XlsxLimitError>()),
    );
    final String xml = _xml(r);
    expect(xml, contains('<fonts count="1">'));
    expect(xml, contains('<fills count="2">'));
    expect(xml, contains('<borders count="1">'));
    expect(xml, contains('<cellXfs count="201">'));
  });

  test('the 65,491st cell format throws and registers nothing', () {
    final StyleRegistry r = StyleRegistry();
    // Alignment alone makes enough distinct formats without reaching the
    // font or number format limits: 7 horizontal values (General is the
    // default) times 181 rotations times 251 indents.
    final Iterator<XlsxStyle> styles = _distinctAlignments().iterator;
    for (int id = 1; id < XlsxLimits.maxCellFormats; id++) {
      styles.moveNext();
      expect(r.idFor(styles.current), id);
    }
    styles.moveNext();
    final XlsxStyle next = styles.current;
    expect(
      () => r.idFor(next),
      throwsA(
        isA<XlsxLimitError>()
            .having((e) => e.limit, 'limit', 'cell formats')
            .having((e) => e.max, 'max', 65490),
      ),
    );
    expect(() => r.idFor(next), throwsA(isA<XlsxLimitError>()));
    // A known format, or an equivalent spelling of one, still works.
    expect(r.idFor(_distinctAlignments().first), 1);
    expect(r.idFor(const XlsxStyle(font: XlsxFont(name: 'Calibri'))), 0);
    final String xml = _xml(r);
    expect(xml, contains('<cellXfs count="65490">'));
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

String _xml(StyleRegistry r) {
  final StringBuffer out = StringBuffer();
  r.writeStylesXml(XmlWriter(out));
  return out.toString();
}

/// Styles that differ only in alignment, none of them the default.
Iterable<XlsxStyle> _distinctAlignments() sync* {
  for (final XlsxHorizontalAlignment h in XlsxHorizontalAlignment.values) {
    if (h == XlsxHorizontalAlignment.general) continue;
    for (int rotation = 0; rotation <= 180; rotation++) {
      for (int indent = 0; indent <= 250; indent++) {
        yield XlsxStyle(
          alignment: XlsxAlignment(
            horizontal: h,
            textRotation: rotation,
            indent: indent,
          ),
        );
      }
    }
  }
}

/// The `styles.xml` of a registry holding only the default style: M1's
/// fixed parts, byte for byte.
const String _emptyGolden =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet'
    ' xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font>'
    '</fonts><fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders><cellStyleXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/>'
    '</cellStyles><dxfs count="0"/><tableStyles count="0"/></styleSheet>';

/// The `styles.xml` for (1) bold red Arial 14, (2) a yellow solid fill with
/// a thin black border, (3) a linear gradient with centered wrapped text,
/// (4) an unlocked cell and (5) a lira money format.
const String _fullGolden =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet'
    ' xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1">'
    '<numFmt numFmtId="164" formatCode="#,##0.00&quot; ₺&quot;"/></numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font>'
    '<b/><sz val="14"/><color rgb="FFFF0000"/><name val="Arial"/></font>'
    '</fonts><fills count="4"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill><fill>'
    '<patternFill patternType="solid"><fgColor rgb="FFFFFF00"/></patternFill>'
    '</fill><fill><gradientFill degree="90"><stop position="0">'
    '<color rgb="FFFFFFFF"/></stop><stop position="1"><color rgb="FF4472C4"/>'
    '</stop></gradientFill></fill></fills><borders count="2"><border><left/>'
    '<right/><top/><bottom/><diagonal/></border><border><left style="thin">'
    '<color rgb="FF000000"/></left><right style="thin">'
    '<color rgb="FF000000"/></right><top style="thin"><color rgb="FF000000"/>'
    '</top><bottom style="thin"><color rgb="FF000000"/></bottom><diagonal/>'
    '</border></borders><cellStyleXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="6">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"'
    ' applyFont="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="1" xfId="0"'
    ' applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0"'
    ' applyFill="1" applyAlignment="1">'
    '<alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"'
    ' applyProtection="1">'
    '<protection locked="0"/></xf>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0"'
    ' applyNumberFormat="1"/>'
    '</cellXfs><cellStyles count="1">'
    '<cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '<dxfs count="0"/><tableStyles count="0"/></styleSheet>';
