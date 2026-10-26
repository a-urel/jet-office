import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/cell_encoder.dart';
import 'package:jet_office/src/xlsx/rich_text.dart'
    show cleanRichText, writeTextElement, writeTextRuns;
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const XlsxFont _bold = XlsxFont(bold: true);

XlsxRichText _rich(List<XlsxTextRun> runs) => XlsxRichText(runs);

void main() {
  group('XlsxTextRun', () {
    test('== and hashCode compare the text and the font', () {
      expect(
        const XlsxTextRun('a', font: _bold),
        const XlsxTextRun('a', font: XlsxFont(bold: true)),
      );
      expect(
        const XlsxTextRun('a', font: _bold).hashCode,
        const XlsxTextRun('a', font: XlsxFont(bold: true)).hashCode,
      );
      expect(const XlsxTextRun('a'), isNot(const XlsxTextRun('b')));
      expect(
        const XlsxTextRun('a'),
        isNot(const XlsxTextRun('a', font: _bold)),
      );
    });

    test('toString names the text and the font', () {
      expect(
        const XlsxTextRun('a', font: _bold).toString(),
        'XlsxTextRun(a, font: XlsxFont(bold: true))',
      );
      expect(const XlsxTextRun('b').toString(), 'XlsxTextRun(b, font: null)');
    });
  });

  group('XlsxRichText', () {
    test('== compares the runs in order', () {
      XlsxRichText rich(List<XlsxTextRun> runs) => XlsxRichText(runs);
      const XlsxTextRun a = XlsxTextRun('a', font: _bold);
      const XlsxTextRun b = XlsxTextRun('b');
      expect(rich(<XlsxTextRun>[a, b]), rich(<XlsxTextRun>[a, b]));
      expect(
        rich(<XlsxTextRun>[a, b]).hashCode,
        rich(<XlsxTextRun>[a, b]).hashCode,
      );
      expect(rich(<XlsxTextRun>[a, b]), isNot(rich(<XlsxTextRun>[b, a])));
      expect(rich(<XlsxTextRun>[a]), isNot(rich(<XlsxTextRun>[a, b])));
      expect(
        rich(<XlsxTextRun>[const XlsxTextRun('ab')]),
        isNot(rich(<XlsxTextRun>[const XlsxTextRun('a'), b])),
      );
    });

    test('holds an unmodifiable copy of the runs', () {
      final List<XlsxTextRun> runs = <XlsxTextRun>[const XlsxTextRun('a')];
      final XlsxRichText rich = XlsxRichText(runs);
      runs.add(const XlsxTextRun('b'));
      expect(rich.runs, <XlsxTextRun>[const XlsxTextRun('a')]);
      expect(
        () => rich.runs.add(const XlsxTextRun('c')),
        throwsUnsupportedError,
      );
    });

    test('text joins the runs', () {
      expect(
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('Total: ', font: _bold),
          XlsxTextRun('42'),
        ]).text,
        'Total: 42',
      );
      expect(XlsxRichText(const <XlsxTextRun>[]).text, '');
    });

    test('toString names the runs', () {
      expect(
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('a', font: _bold),
          XlsxTextRun('b'),
        ]).toString(),
        'XlsxRichText([XlsxTextRun(a, font: XlsxFont(bold: true)), '
        'XlsxTextRun(b, font: null)])',
      );
    });
  });

  group('cleanRichText', () {
    test('returns the very rich text when nothing needs cleaning', () {
      final XlsxRichText rich = _rich(<XlsxTextRun>[
        const XlsxTextRun('a', font: _bold),
        XlsxTextRun('b' * 32766),
      ]);
      final ({XlsxRichText text, int removed, bool truncated}) clean =
          cleanRichText(rich);
      expect(clean.text, same(rich));
      expect(clean.removed, 0);
      expect(clean.truncated, isFalse);
    });

    test('removes forbidden characters run by run and counts them', () {
      final ({XlsxRichText text, int removed, bool truncated}) clean =
          cleanRichText(
            _rich(const <XlsxTextRun>[
              XlsxTextRun('a\u0001b', font: _bold),
              XlsxTextRun('\uFFFEc\u0002'),
            ]),
          );
      expect(
        clean.text,
        _rich(const <XlsxTextRun>[
          XlsxTextRun('ab', font: _bold),
          XlsxTextRun('c'),
        ]),
      );
      expect(clean.removed, 3);
      expect(clean.truncated, isFalse);
    });

    test('a surrogate pair split across two runs is removed from both', () {
      // Each run is its own `<t>`, so neither half may stay.
      final ({XlsxRichText text, int removed, bool truncated}) clean =
          cleanRichText(
            _rich(const <XlsxTextRun>[
              XlsxTextRun('a\uD83D'),
              XlsxTextRun('\uDE00b', font: _bold),
            ]),
          );
      expect(
        clean.text,
        _rich(const <XlsxTextRun>[
          XlsxTextRun('a'),
          XlsxTextRun('b', font: _bold),
        ]),
      );
      expect(clean.removed, 2);
    });

    test('keeps a run that only scrubbing left empty', () {
      expect(
        cleanRichText(
          _rich(const <XlsxTextRun>[
            XlsxTextRun('\u0001', font: _bold),
            XlsxTextRun('a'),
          ]),
        ).text,
        _rich(const <XlsxTextRun>[
          XlsxTextRun('', font: _bold),
          XlsxTextRun('a'),
        ]),
      );
    });

    test(
      'cuts inside the run that crosses 32,767 units and drops the rest',
      () {
        final ({XlsxRichText text, int removed, bool truncated}) clean =
            cleanRichText(
              _rich(<XlsxTextRun>[
                XlsxTextRun('a' * 20000, font: _bold),
                XlsxTextRun('b' * 20000),
                const XlsxTextRun('c', font: _bold),
              ]),
            );
        expect(
          clean.text,
          _rich(<XlsxTextRun>[
            XlsxTextRun('a' * 20000, font: _bold),
            XlsxTextRun('b' * 12767),
          ]),
        );
        expect(clean.removed, 0);
        expect(clean.truncated, isTrue);
      },
    );

    test('the limit is counted after scrubbing', () {
      final ({XlsxRichText text, int removed, bool truncated}) clean =
          cleanRichText(
            _rich(<XlsxTextRun>[
              XlsxTextRun('\u0001${'a' * 32766}'),
              const XlsxTextRun('b', font: _bold),
            ]),
          );
      expect(clean.text.text, '${'a' * 32766}b');
      expect(clean.removed, 1);
      expect(clean.truncated, isFalse);
    });

    test('a cut that would split a surrogate pair keeps the pair out', () {
      final ({XlsxRichText text, int removed, bool truncated}) clean =
          cleanRichText(
            _rich(<XlsxTextRun>[
              XlsxTextRun('a' * 20000),
              XlsxTextRun('${'b' * 12766}\u{1F600}c', font: _bold),
            ]),
          );
      expect(
        clean.text,
        _rich(<XlsxTextRun>[
          XlsxTextRun('a' * 20000),
          XlsxTextRun('b' * 12766, font: _bold),
        ]),
      );
      expect(clean.truncated, isTrue);
    });

    test('drops a run the cut leaves empty', () {
      // At the limit exactly: the next run is after the cut.
      expect(
        cleanRichText(
          _rich(<XlsxTextRun>[
            XlsxTextRun('a' * 32767),
            const XlsxTextRun('b', font: _bold),
          ]),
        ).text,
        _rich(<XlsxTextRun>[XlsxTextRun('a' * 32767)]),
      );
      // One unit short, and the next run starts with a pair.
      final ({XlsxRichText text, int removed, bool truncated}) clean =
          cleanRichText(
            _rich(<XlsxTextRun>[
              XlsxTextRun('a' * 32766),
              const XlsxTextRun('\u{1F600}b', font: _bold),
            ]),
          );
      expect(clean.text, _rich(<XlsxTextRun>[XlsxTextRun('a' * 32766)]));
      expect(clean.truncated, isTrue);
    });

    test('32,767 units across runs are not truncated', () {
      final ({XlsxRichText text, int removed, bool truncated}) clean =
          cleanRichText(
            _rich(<XlsxTextRun>[
              XlsxTextRun('a' * 32766),
              const XlsxTextRun('b', font: _bold),
              const XlsxTextRun('', font: _bold),
            ]),
          );
      expect(clean.text.runs, hasLength(3));
      expect(clean.truncated, isFalse);
    });
  });

  group('writeTextRuns', () {
    String runs(XlsxRichText text) {
      final StringBuffer out = StringBuffer();
      writeTextRuns(XmlWriter(out), text);
      return out.toString();
    }

    test('one <r> per run, an <rPr> only for a run with a font', () {
      expect(
        runs(
          _rich(const <XlsxTextRun>[
            XlsxTextRun('Total:', font: _bold),
            XlsxTextRun('42'),
          ]),
        ),
        '<r><rPr><b/></rPr><t>Total:</t></r><r><t>42</t></r>',
      );
    });

    test('a padded run keeps its spaces', () {
      expect(
        runs(
          _rich(const <XlsxTextRun>[
            XlsxTextRun('Total: ', font: _bold),
            XlsxTextRun(' 42'),
            XlsxTextRun('\t'),
            XlsxTextRun('a b'),
          ]),
        ),
        '<r><rPr><b/></rPr><t xml:space="preserve">Total: </t></r>'
        '<r><t xml:space="preserve"> 42</t></r>'
        '<r><t xml:space="preserve">\t</t></r>'
        '<r><t>a b</t></r>',
      );
    });

    test('the text is escaped as ST_Xstring and XML', () {
      expect(
        runs(
          _rich(const <XlsxTextRun>[
            XlsxTextRun('_x0041_', font: _bold),
            XlsxTextRun('R&D <1>'),
          ]),
        ),
        '<r><rPr><b/></rPr><t>_x005F_x0041_</t></r>'
        '<r><t>R&amp;D &lt;1&gt;</t></r>',
      );
    });
  });

  test('writeTextElement writes one <t>, preserved only when padded', () {
    String t(String text) {
      final StringBuffer out = StringBuffer();
      writeTextElement(XmlWriter(out), text);
      return out.toString();
    }

    expect(t('a'), '<t>a</t>');
    expect(t(''), '<t></t>');
    expect(t(' a'), '<t xml:space="preserve"> a</t>');
    expect(t('a\n'), '<t xml:space="preserve">a\n</t>');
    expect(t('_x0041_'), '<t>_x005F_x0041_</t>');
  });

  group('in a cell', () {
    late SharedStrings strings;
    late StyleRegistry styles;
    late WarningCollector warnings;
    late CellEncoder encoder;

    setUp(() {
      strings = SharedStrings();
      styles = StyleRegistry();
      warnings = WarningCollector();
      encoder = CellEncoder(
        strings: strings,
        styles: styles,
        warnings: warnings,
      );
    });

    void encodeTo(
      StringBuffer out,
      Object? value, {
      XlsxStyle? rowStyle,
      XlsxStyle? columnStyle,
    }) => encoder.encode(
      XmlWriter(out),
      sheet: 'S',
      row: 0,
      column: 0,
      value: value,
      rowStyle: rowStyle,
      columnStyle: columnStyle,
    );

    String enc(Object? value, {XlsxStyle? rowStyle, XlsxStyle? columnStyle}) {
      final StringBuffer out = StringBuffer();
      encodeTo(out, value, rowStyle: rowStyle, columnStyle: columnStyle);
      return out.toString();
    }

    /// The `<si>` items of the table, in index order.
    List<String> items() {
      final StringBuffer out = StringBuffer();
      strings.writeXml(XmlWriter(out));
      return <String>[
        for (final RegExpMatch m in RegExp(
          '<si>.*?</si>',
          dotAll: true,
        ).allMatches(out.toString()))
          m.group(0)!,
      ];
    }

    String stylesXml() {
      final StringBuffer out = StringBuffer();
      styles.writeStylesXml(XmlWriter(out));
      return out.toString();
    }

    final XlsxRichText total = XlsxRichText(const <XlsxTextRun>[
      XlsxTextRun('Total: ', font: _bold),
      XlsxTextRun('42'),
    ]);
    const XlsxStyle arial14 = XlsxStyle(
      font: XlsxFont(name: 'Arial', size: 14),
    );

    test('a default cell writes a t="s" cell and one <r> per run', () {
      expect(enc(total), '<c r="A1" t="s"><v>0</v></c>');
      expect(items(), <String>[
        '<si><r><rPr><b/><sz val="11"/><rFont val="Calibri"/></rPr>'
            '<t xml:space="preserve">Total: </t></r><r><t>42</t></r></si>',
      ]);
      expect(warnings.warnings, isEmpty);
    });

    test('the cell font is merged under the run font (Decision 3)', () {
      enc(total);
      expect(
        enc(XlsxCell(total, style: arial14)),
        '<c r="A1" s="1" t="s"><v>1</v></c>',
      );
      expect(items(), hasLength(2));
      expect(
        items()[1],
        '<si><r><rPr><b/><sz val="14"/><rFont val="Arial"/></rPr>'
        '<t xml:space="preserve">Total: </t></r><r><t>42</t></r></si>',
      );
      expect(strings.count, 2);
    });

    test('the effective font merges column, row and cell under the run', () {
      expect(
        enc(
          XlsxCell(
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun(
                'a',
                font: XlsxFont(bold: false, color: XlsxColor.rgb(0xFF0000)),
              ),
              XlsxTextRun('b'),
            ]),
            style: const XlsxStyle(font: XlsxFont(italic: true)),
          ),
          rowStyle: const XlsxStyle(font: XlsxFont(bold: true, size: 9)),
          columnStyle: const XlsxStyle(font: XlsxFont(name: 'Arial')),
        ),
        '<c r="A1" s="1" t="s"><v>0</v></c>',
      );
      // The run's bold: false wins over the row's bold; italic, size and
      // name come from the cell, row and column.
      expect(
        items().single,
        '<si><r><rPr><i/><sz val="9"/><color rgb="FFFF0000"/>'
        '<rFont val="Arial"/></rPr><t>a</t></r><r><t>b</t></r></si>',
      );
    });

    test('equal rich texts in equal fonts share one <si>', () {
      enc(total);
      enc(
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('Total: ', font: XlsxFont(bold: true)),
          XlsxTextRun('42'),
        ]),
      );
      enc(XlsxCell(total, style: arial14));
      enc(XlsxCell(total, style: arial14));
      expect(strings.count, 4);
      expect(strings.uniqueCount, 2);
    });

    test('one run without a font shares the <si> of the plain string', () {
      expect(
        enc(XlsxRichText(const <XlsxTextRun>[XlsxTextRun('abc')])),
        '<c r="A1" t="s"><v>0</v></c>',
      );
      expect(enc('abc'), '<c r="A1" t="s"><v>0</v></c>');
      expect(strings.count, 2);
      expect(items(), <String>['<si><t>abc</t></si>']);
    });

    test('forbidden characters are removed, one warning for the cell', () {
      expect(
        enc(
          XlsxRichText(const <XlsxTextRun>[
            XlsxTextRun('a\u0001', font: _bold),
            XlsxTextRun('\u0002b'),
          ]),
        ),
        '<c r="A1" t="s"><v>0</v></c>',
      );
      expect(items().single, endsWith('<t>a</t></r><r><t>b</t></r></si>'));
      final XlsxWarning warning = warnings.warnings.single;
      expect(warning.code, XlsxWarningCode.invalidCharactersRemoved);
      expect(warning.count, 1);
      expect(warning.sheet, 'S');
      expect(warning.cells, <String>['A1']);
    });

    test('20,000 + 20,000 units keep the first run and cut the second', () {
      enc(
        XlsxRichText(<XlsxTextRun>[
          XlsxTextRun('a' * 20000, font: _bold),
          XlsxTextRun('b' * 20000),
        ]),
      );
      expect(strings.values.single, '${'a' * 20000}${'b' * 12767}');
      expect(
        items().single,
        endsWith('<t>${'a' * 20000}</t></r><r><t>${'b' * 12767}</t></r></si>'),
      );
      expect(warnings.warnings.single.code, XlsxWarningCode.textTruncated);
      expect(warnings.warnings.single.count, 1);
    });

    test('a cut that would split a surrogate pair keeps the pair out', () {
      enc(
        XlsxRichText(<XlsxTextRun>[
          XlsxTextRun('a' * 20000, font: _bold),
          XlsxTextRun('${'b' * 12766}\u{1F600}c'),
        ]),
      );
      expect(strings.values.single, '${'a' * 20000}${'b' * 12766}');
      expect(warnings.warnings.single.code, XlsxWarningCode.textTruncated);
    });

    test('a cut that leaves one fontless run shares the plain string', () {
      enc('a' * 32767);
      enc(
        XlsxRichText(<XlsxTextRun>[
          XlsxTextRun('a' * 32767),
          const XlsxTextRun('b', font: _bold),
        ]),
      );
      expect(strings.uniqueCount, 1);
      expect(strings.count, 2);
    });

    group('a programmer error throws before the cell is written', () {
      void expectUntouched(StringBuffer out) {
        expect(out.toString(), '');
        expect(strings.count, 0);
        expect(strings.uniqueCount, 0);
        expect(warnings.warnings, isEmpty);
        expect(stylesXml(), contains('<cellXfs count="1">'));
        expect(stylesXml(), contains('<fonts count="1">'));
      }

      Matcher named(String name) => throwsA(
        isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name),
      );

      test('a rich text without runs, named runs', () {
        final StringBuffer out = StringBuffer();
        expect(
          () => encodeTo(
            out,
            XlsxCell(XlsxRichText(const <XlsxTextRun>[]), style: arial14),
          ),
          named('runs'),
        );
        expectUntouched(out);
      });

      test('a run font of size 0, named runs[0].font.size', () {
        final StringBuffer out = StringBuffer();
        expect(
          () => encodeTo(
            out,
            XlsxCell(
              XlsxRichText(const <XlsxTextRun>[
                XlsxTextRun('a\u0001', font: XlsxFont(size: 0)),
              ]),
              style: arial14,
            ),
          ),
          named('runs[0].font.size'),
        );
        expectUntouched(out);
      });

      test('an invalid font of a later run names that run and field', () {
        final StringBuffer out = StringBuffer();
        expect(
          () => encodeTo(
            out,
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun('a', font: _bold),
              XlsxTextRun('b'),
              XlsxTextRun('c', font: XlsxFont(color: XlsxColor.theme(12))),
            ]),
          ),
          named('runs[2].font.color'),
        );
        expectUntouched(out);
      });

      test('an invalid cell style with forbidden characters in a run', () {
        final StringBuffer out = StringBuffer();
        expect(
          () => encodeTo(
            out,
            XlsxRichText(const <XlsxTextRun>[
              XlsxTextRun('a\u0001', font: _bold),
              XlsxTextRun('b'),
            ]),
            rowStyle: const XlsxStyle(numFmt: XlsxNumFmt.builtin(200)),
          ),
          throwsArgumentError,
        );
        expectUntouched(out);
      });
    });
  });

  test('a sheet row takes rich text, bare and in an XlsxCell', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxRichText total = XlsxRichText(const <XlsxTextRun>[
      XlsxTextRun('Total: ', font: _bold),
      XlsxTextRun('42'),
    ]);
    book.addSheet('S').row(<Object?>[
      total,
      XlsxCell(
        total,
        style: const XlsxStyle(font: XlsxFont(name: 'Arial', size: 14)),
      ),
    ]);
    final XlsxResult result = book.close();
    expect(checkXlsx(result.bytes), isEmpty);
    expect(result.warnings, isEmpty);
    final Map<String, String> parts = readXlsx(result.bytes);
    expect(
      parts['xl/worksheets/sheet1.xml'],
      contains(
        '<c r="A1" t="s"><v>0</v></c><c r="B1" s="1" t="s"><v>1</v></c>',
      ),
    );
    expect(
      parts['xl/sharedStrings.xml'],
      endsWith(
        'count="2" uniqueCount="2">'
        '<si><r><rPr><b/><sz val="11"/><rFont val="Calibri"/></rPr>'
        '<t xml:space="preserve">Total: </t></r><r><t>42</t></r></si>'
        '<si><r><rPr><b/><sz val="14"/><rFont val="Arial"/></rPr>'
        '<t xml:space="preserve">Total: </t></r><r><t>42</t></r></si>'
        '</sst>',
      ),
    );
  });
}
