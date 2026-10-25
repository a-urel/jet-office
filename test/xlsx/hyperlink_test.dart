import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/hyperlink.dart';
import 'package:jet_office/src/xlsx/worksheet_parts.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _sheet1 = 'xl/worksheets/sheet1.xml';
const String _rels1 = 'xl/worksheets/_rels/sheet1.xml.rels';

/// A one-sheet workbook with [rows], as its parts.
Map<String, String> _parts(
  List<List<Object?>> rows, {
  List<XlsxColumn?>? columns,
  XlsxStyle? rowStyle,
}) {
  final XlsxWriter book = XlsxWriter();
  final XlsxSheetWriter sheet = book.addSheet('S');
  if (columns != null) sheet.columns(columns);
  for (final List<Object?> row in rows) {
    sheet.row(row, style: rowStyle);
  }
  return readXlsx(book.close().bytes);
}

/// The `<font>` element of the cell A1 of sheet 1.
String _fontOfA1(Map<String, String> parts) {
  final XmlDocument sheet = XmlDocument.parse(parts[_sheet1]!);
  final int s = int.parse(
    sheet.findAllElements('c').first.getAttribute('s') ?? '0',
  );
  final XmlDocument styles = XmlDocument.parse(parts['xl/styles.xml']!);
  final XmlElement xf = styles
      .findAllElements('cellXfs')
      .first
      .findElements('xf')
      .elementAt(s);
  final int fontId = int.parse(xf.getAttribute('fontId')!);
  return styles
      .findAllElements('fonts')
      .first
      .findElements('font')
      .elementAt(fontId)
      .toXmlString();
}

void main() {
  group('encodeUriText', () {
    test('percent-encodes the UTF-8 bytes in uppercase', () {
      expect(
        encodeUriText('https://example.com/a b?q=ç'),
        'https://example.com/a%20b?q=%C3%A7',
      );
    });
    test('keeps an existing percent escape', () {
      expect(encodeUriText('https://x.org/%20'), 'https://x.org/%20');
    });
    test('keeps every reserved and unreserved character', () {
      const String kept = 'AZaz09-._~:/?#[]@!\$&\'()*+,;=%';
      expect(encodeUriText(kept), kept);
    });
    test('encodes quotes, angle brackets, backslash and braces', () {
      expect(encodeUriText('"<>\\^`{|}'), '%22%3C%3E%5C%5E%60%7B%7C%7D');
    });
    test('encodes a character outside the BMP as four bytes', () {
      expect(encodeUriText('\u{1F600}'), '%F0%9F%98%80');
    });
  });

  group('XlsxHyperlink', () {
    test('url encodes the address and defaults the text to the url', () {
      final XlsxHyperlink link = XlsxHyperlink.url('https://x.org/a b');
      expect(link.address, 'https://x.org/a%20b');
      expect(link.location, isNull);
      expect(link.text, 'https://x.org/a b');
      expect(link.tooltip, isNull);
    });
    test('url takes text and tooltip', () {
      final XlsxHyperlink link = XlsxHyperlink.url(
        'https://x.org',
        text: 'X',
        tooltip: 'go',
      );
      expect(link.text, 'X');
      expect(link.tooltip, 'go');
    });
    test('email builds a mailto address with an encoded subject', () {
      final XlsxHyperlink link = XlsxHyperlink.email(
        'a@b.com',
        subject: 'Q&A ç',
      );
      expect(link.address, 'mailto:a@b.com?subject=Q%26A%20%C3%A7');
      expect(link.text, 'a@b.com');
    });
    test('the subject is a URI component: = ? # are encoded too', () {
      expect(
        XlsxHyperlink.email('a@b.com', subject: 'a=b?c#d').address,
        'mailto:a@b.com?subject=a%3Db%3Fc%23d',
      );
    });
    test('email without a subject has no query', () {
      expect(XlsxHyperlink.email('a@b.com').address, 'mailto:a@b.com');
    });
    test('location defaults the text to the location', () {
      final XlsxHyperlink link = XlsxHyperlink.location('Target');
      expect(link.location, 'Target');
      expect(link.address, isNull);
      expect(link.text, 'Target');
    });
    test('sheet quotes the name and defaults the range to A1', () {
      final XlsxHyperlink link = XlsxHyperlink.sheet("O'Brien");
      expect(link.location, "'O''Brien'!A1");
      expect(link.text, "O'Brien");
      expect(
        XlsxHyperlink.sheet('S', range: XlsxRange.parse('B2:C3')).location,
        "'S'!B2:C3",
      );
    });
    test('has value equality and a toString', () {
      expect(XlsxHyperlink.url('http://a'), XlsxHyperlink.url('http://a'));
      expect(
        XlsxHyperlink.url('http://a').hashCode,
        XlsxHyperlink.url('http://a').hashCode,
      );
      expect(
        XlsxHyperlink.url('http://a'),
        isNot(XlsxHyperlink.url('http://a', tooltip: 't')),
      );
      expect(XlsxHyperlink.url('http://a').toString(), contains('http://a'));
    });
  });

  group('writing', () {
    test('a url link: shared string, hyperlinks element and rels part', () {
      final Map<String, String> parts = _parts(<List<Object?>>[
        <Object?>[XlsxHyperlink.url('https://example.com/a b')],
      ]);
      expect(
        parts['xl/sharedStrings.xml'],
        contains('https://example.com/a b'),
      );
      expect(
        parts[_sheet1],
        contains(
          '</sheetData><hyperlinks><hyperlink ref="A1" r:id="rId1" '
          'display="https://example.com/a b"/></hyperlinks></worksheet>',
        ),
      );
      expect(
        parts[_rels1],
        contains(
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
          'relationships/hyperlink" '
          'Target="https://example.com/a%20b" TargetMode="External"/>',
        ),
      );
    });

    test('the output passes the checker', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').row(<Object?>[XlsxHyperlink.url('https://a.org')]);
      expect(checkXlsx(book.close().bytes), isEmpty);
    });

    test('two links to one address share a relationship', () {
      final Map<String, String> parts = _parts(<List<Object?>>[
        <Object?>[
          XlsxHyperlink.url('https://a.org'),
          XlsxHyperlink.url('https://a.org', text: 'again'),
          XlsxHyperlink.url('https://b.org'),
        ],
      ]);
      expect(RegExp('<Relationship ').allMatches(parts[_rels1]!), hasLength(2));
      expect(parts[_sheet1], contains('ref="A1" r:id="rId1"'));
      expect(parts[_sheet1], contains('ref="B1" r:id="rId1"'));
      expect(parts[_sheet1], contains('ref="C1" r:id="rId2"'));
    });

    test('a link inside an XlsxCell is written', () {
      final Map<String, String> parts = _parts(<List<Object?>>[
        <Object?>[XlsxCell(XlsxHyperlink.url('https://a.org'))],
      ]);
      expect(parts[_sheet1], contains('<hyperlink ref="A1"'));
    });

    test('a sheet link writes a location and no r:id or rels part', () {
      final Map<String, String> parts = _parts(<List<Object?>>[
        <Object?>[XlsxHyperlink.sheet("O'Brien", range: XlsxRange.parse('B2'))],
      ]);
      expect(
        parts[_sheet1],
        contains(
          '<hyperlink ref="A1" location="\'O\'\'Brien\'!B2" '
          'display="O\'Brien"/>',
        ),
      );
      expect(parts[_sheet1], isNot(contains('r:id')));
      expect(parts.containsKey(_rels1), isFalse);
    });

    test('a tooltip is written between location and display', () {
      final Map<String, String> parts = _parts(<List<Object?>>[
        <Object?>[XlsxHyperlink.location('Target', tooltip: 'a & b')],
      ]);
      expect(
        parts[_sheet1],
        contains(
          '<hyperlink ref="A1" location="Target" tooltip="a &amp; b" '
          'display="Target"/>',
        ),
      );
    });

    test(
      '_xHHHH_ look-alikes in location, tooltip and display are escaped',
      () {
        final Map<String, String> parts = _parts(<List<Object?>>[
          <Object?>[
            XlsxHyperlink.location(
              '_x0041_',
              text: '_x0042_',
              tooltip: '_x0043_',
            ),
          ],
        ]);
        expect(
          parts[_sheet1],
          contains(
            'location="_x005F_x0041_" tooltip="_x005F_x0043_" '
            'display="_x005F_x0042_"',
          ),
        );
      },
    );

    test('the sheet link to a sheet named _x0041_ is escaped like its tab', () {
      final Map<String, String> parts = _parts(<List<Object?>>[
        <Object?>[XlsxHyperlink.sheet('_x0041_')],
      ]);
      expect(parts[_sheet1], contains("location=\"'_x005F_x0041_'!A1\""));
    });

    test('text is subject to the usual cell warnings', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').row(<Object?>[
        XlsxHyperlink.url('https://a.org', text: 'x' * 40000),
      ]);
      final XlsxResult result = book.close();
      expect(result.warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
        XlsxWarningCode.textTruncated,
      ]);
    });

    test('links in several rows keep their cell references', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..row(<Object?>['a'])
        ..blankRow()
        ..row(<Object?>[null, XlsxHyperlink.location('X')]);
      final Map<String, String> parts = readXlsx(book.close().bytes);
      expect(parts[_sheet1], contains('<hyperlink ref="B3"'));
    });
  });

  group('style', () {
    test('a plain link cell is theme 10 and underlined', () {
      final String font = _fontOfA1(
        _parts(<List<Object?>>[
          <Object?>[XlsxHyperlink.url('https://a.org')],
        ]),
      );
      expect(font, contains('<u/>'));
      expect(font, contains('<color theme="10"/>'));
      expect(font, isNot(contains('<b/>')));
    });

    test('in a bold column it is bold, theme 10 and underlined', () {
      final String font = _fontOfA1(
        _parts(
          <List<Object?>>[
            <Object?>[XlsxHyperlink.url('https://a.org')],
          ],
          columns: <XlsxColumn?>[
            const XlsxColumn(style: XlsxStyle(font: XlsxFont(bold: true))),
          ],
        ),
      );
      expect(font, contains('<b/>'));
      expect(font, contains('<u/>'));
      expect(font, contains('<color theme="10"/>'));
    });

    test('a red cell font stays red and underlined', () {
      final String font = _fontOfA1(
        _parts(<List<Object?>>[
          <Object?>[
            XlsxCell(
              XlsxHyperlink.url('https://a.org'),
              style: const XlsxStyle(
                font: XlsxFont(color: XlsxColor.rgb(0xFF0000)),
              ),
            ),
          ],
        ]),
      );
      expect(font, contains('<u/>'));
      expect(font, contains('FFFF0000'));
      expect(font, isNot(contains('theme="10"')));
    });

    test('a row style font wins over the hyperlink font', () {
      final String font = _fontOfA1(
        _parts(
          <List<Object?>>[
            <Object?>[XlsxHyperlink.url('https://a.org')],
          ],
          rowStyle: const XlsxStyle(
            font: XlsxFont(color: XlsxColor.rgb(0x00FF00)),
          ),
        ),
      );
      expect(font, contains('FF00FF00'));
      expect(font, contains('<u/>'));
    });

    test('underline none wins', () {
      final String font = _fontOfA1(
        _parts(<List<Object?>>[
          <Object?>[
            XlsxCell(
              XlsxHyperlink.url('https://a.org'),
              style: const XlsxStyle(
                font: XlsxFont(underline: XlsxUnderline.none),
              ),
            ),
          ],
        ]),
      );
      expect(font, isNot(contains('<u')));
      expect(font, contains('<color theme="10"/>'));
    });

    test('a link and a plain string do not share a cell format', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').row(<Object?>[
        'plain',
        XlsxHyperlink.url('https://a.org'),
        'plain',
      ]);
      final String sheet = readXlsx(book.close().bytes)[_sheet1]!;
      expect(sheet, contains('<c r="A1" t="s">'));
      expect(sheet, contains('<c r="B1" s="1" t="s">'));
      expect(sheet, contains('<c r="C1" t="s">'));
    });

    test('many link cells in one column resolve their style once', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
      for (int i = 0; i < 50; i++) {
        sheet.row(<Object?>[XlsxHyperlink.location('X$i')], style: bold);
      }
      final String xml = readXlsx(book.close().bytes)['xl/styles.xml']!;
      expect(xml, contains('<cellXfs count="2">'));
    });
  });

  group('validation', () {
    void expectRejected(Object? link, {String? field}) {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      expect(
        () => sheet.row(<Object?>['before', link]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            field ?? isNotNull,
          ),
        ),
      );
      // Atomic: the failing cell is not written, nothing is recorded.
      final Map<String, String> parts = readXlsx(book.close().bytes);
      expect(parts[_sheet1], isNot(contains('<hyperlink')));
      expect(parts[_sheet1], contains('<c r="A1"'));
      expect(parts[_sheet1], isNot(contains('r="B1"')));
      expect(parts.containsKey(_rels1), isFalse);
    }

    test('an empty url', () {
      expectRejected(XlsxHyperlink.url(''), field: 'address');
    });
    test('an address of 2,080 units; 2,079 is accepted', () {
      expectRejected(
        XlsxHyperlink.url('http://${'a' * 2073}'),
        field: 'address',
      );
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').row(<Object?>[
        XlsxHyperlink.url('http://${'a' * 2072}'),
      ]);
      expect(book.close().bytes, isNotEmpty);
    });
    test('a tooltip of 256 units; 255 is accepted', () {
      expectRejected(
        XlsxHyperlink.url('http://a', tooltip: 't' * 256),
        field: 'tooltip',
      );
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').row(<Object?>[
        XlsxHyperlink.url('http://a', tooltip: 't' * 255),
      ]);
      expect(book.close().bytes, isNotEmpty);
    });
    test('an empty location', () {
      expectRejected(XlsxHyperlink.location(''), field: 'location');
    });
    test('text holding U+0001', () {
      expectRejected(
        XlsxHyperlink.url('http://a', text: 'a\u0001b'),
        field: 'text',
      );
    });
    test('a tooltip or location holding U+0001', () {
      expectRejected(
        XlsxHyperlink.url('http://a', tooltip: 'a\u0001'),
        field: 'tooltip',
      );
      expectRejected(XlsxHyperlink.location('a\u0001'), field: 'location');
    });
    test('an address holding U+0001', () {
      // encodeUriText encodes the control character, so build the link
      // from an email address, whose address part is not encoded.
      expectRejected(XlsxHyperlink.email('a\u0001@b.com'), field: 'address');
    });
    test('a link inside an XlsxCell is checked too', () {
      expectRejected(XlsxCell(XlsxHyperlink.url('')), field: 'address');
    });
  });

  group('worksheetRelationshipsXml', () {
    test('has no part without addresses', () {
      expect(worksheetRelationshipsXml(const <String>[]), isNull);
    });
    test('lists the addresses as external hyperlink relationships', () {
      final String xml = worksheetRelationshipsXml(<String>['a', 'b'])!;
      expect(xml, contains('Id="rId1"'));
      expect(xml, contains('Id="rId2"'));
      expect(xml, contains('Target="b" TargetMode="External"'));
    });
    test('names the part by sheet number', () {
      expect(worksheetRelsPartName(3), 'xl/worksheets/_rels/sheet3.xml.rels');
    });
  });
}
