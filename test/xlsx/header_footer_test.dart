import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _sheet1 = 'xl/worksheets/sheet1.xml';

/// Sheet 1 of a workbook in which [setup] sets up the sheet `S`.
String _sheet(void Function(XlsxSheetWriter sheet) setup) {
  final XlsxWriter book = XlsxWriter();
  final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>['x']);
  setup(sheet);
  return readXlsx(book.close().bytes)[_sheet1]!;
}

String _write(XlsxHeaderFooter hf) =>
    _sheet((XlsxSheetWriter s) => s.headerFooter(hf));

Matcher _argumentNamed(String name) => throwsA(
  isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name),
);

void main() {
  group('text helpers', () {
    test('literal doubles every ampersand (Quds wrote R&D raw)', () {
      expect(XlsxHeaderFooter.literal('R&D'), 'R&&D');
      expect(XlsxHeaderFooter.literal('a&&b&'), 'a&&&&b&&');
      expect(XlsxHeaderFooter.literal('none'), 'none');
    });

    test('sections joins &L, &C and &R and skips absent ones', () {
      expect(
        XlsxHeaderFooter.sections(
          left: XlsxHeaderFooter.literal('R&D'),
          right: 'Page &P of &N',
        ),
        '&LR&&D&RPage &P of &N',
      );
      expect(XlsxHeaderFooter.sections(center: 'x'), '&Cx');
      expect(XlsxHeaderFooter.sections(), '');
      expect(
        XlsxHeaderFooter.sections(left: 'l', center: 'c', right: 'r'),
        '&Ll&Cc&Rr',
      );
    });

    test('code constants are the field codes', () {
      expect(XlsxHeaderFooter.pageNumber, '&P');
      expect(XlsxHeaderFooter.pageCount, '&N');
      expect(XlsxHeaderFooter.date, '&D');
      expect(XlsxHeaderFooter.time, '&T');
      expect(XlsxHeaderFooter.sheetName, '&A');
      expect(XlsxHeaderFooter.fileName, '&F');
      expect(XlsxHeaderFooter.filePath, '&Z');
    });
  });

  group('writing', () {
    test('odd footer and first header derive differentFirst', () {
      final String xml = _write(
        const XlsxHeaderFooter(
          oddFooter: 'Page &P of &N',
          firstHeader: 'Cover',
        ),
      );
      expect(
        xml,
        contains(
          '<headerFooter differentFirst="1"><oddFooter>Page &amp;P of '
          '&amp;N</oddFooter><firstHeader>Cover</firstHeader></headerFooter>',
        ),
      );
    });

    test('follows pageSetup', () {
      final String xml = _sheet(
        (XlsxSheetWriter s) => s
          ..headerFooter(const XlsxHeaderFooter(oddHeader: 'H'))
          ..pageSetup(const XlsxPageSetup(scale: 90)),
      );
      expect(xml.indexOf('<pageSetup'), lessThan(xml.indexOf('<headerFooter')));
    });

    test('an even text derives differentOddEven', () {
      final String xml = _write(const XlsxHeaderFooter(evenHeader: 'E'));
      expect(
        xml,
        contains(
          '<headerFooter differentOddEven="1"><evenHeader>E</evenHeader>'
          '</headerFooter>',
        ),
      );
    });

    test('children follow CT_HeaderFooter order', () {
      final String xml = _write(
        const XlsxHeaderFooter(
          firstFooter: '6',
          firstHeader: '5',
          evenFooter: '4',
          evenHeader: '3',
          oddFooter: '2',
          oddHeader: '1',
        ),
      );
      expect(
        xml,
        contains(
          '<headerFooter differentOddEven="1" differentFirst="1">'
          '<oddHeader>1</oddHeader><oddFooter>2</oddFooter>'
          '<evenHeader>3</evenHeader><evenFooter>4</evenFooter>'
          '<firstHeader>5</firstHeader><firstFooter>6</firstFooter>'
          '</headerFooter>',
        ),
      );
    });

    test('explicit flags win over the derived ones', () {
      final String off = _write(
        const XlsxHeaderFooter(
          evenHeader: 'E',
          firstHeader: 'F',
          differentOddEven: false,
          differentFirst: false,
        ),
      );
      expect(off, contains('<headerFooter><evenHeader>'));
      final String on = _write(
        const XlsxHeaderFooter(
          oddHeader: 'O',
          differentOddEven: true,
          differentFirst: true,
        ),
      );
      expect(
        on,
        contains(
          '<headerFooter differentOddEven="1" differentFirst="1">'
          '<oddHeader>O</oddHeader></headerFooter>',
        ),
      );
    });

    test('scaleWithDocument and alignWithMargins write only when false', () {
      final String xml = _write(
        const XlsxHeaderFooter(
          oddHeader: 'H',
          scaleWithDocument: false,
          alignWithMargins: false,
        ),
      );
      expect(
        xml,
        contains(
          '<headerFooter scaleWithDoc="0" alignWithMargins="0">'
          '<oddHeader>H</oddHeader></headerFooter>',
        ),
      );
    });

    test('a header/footer with nothing to say writes nothing', () {
      expect(_write(const XlsxHeaderFooter()), isNot(contains('headerFooter')));
    });

    test('text is XML-escaped and _xHHHH_ is escaped as ST_Xstring', () {
      final String xml = _write(
        const XlsxHeaderFooter(oddHeader: '_x0041_ <b> "q"'),
      );
      expect(
        xml,
        contains('<oddHeader>_x005F_x0041_ &lt;b&gt; "q"</oddHeader>'),
      );
    });

    test('a literal ampersand is written as a doubled one', () {
      final String xml = _write(
        XlsxHeaderFooter(oddHeader: XlsxHeaderFooter.literal('R&D')),
      );
      expect(xml, contains('<oddHeader>R&amp;&amp;D</oddHeader>'));
    });

    test('a later call replaces the earlier one', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        s.headerFooter(const XlsxHeaderFooter(oddHeader: 'one'));
        s.headerFooter(const XlsxHeaderFooter(oddHeader: 'two'));
      });
      expect(xml, contains('<oddHeader>two</oddHeader>'));
      expect(xml, isNot(contains('<oddHeader>one')));
    });
  });

  group('order', () {
    test('pageSetup < headerFooter < x14 extLst', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..row(<Object?>[1])
        ..conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[XlsxRange.parse('A1:A5')],
            <XlsxConditionalRule>[XlsxDataBar(color: XlsxColor.hex('638EC6'))],
          ),
        )
        ..headerFooter(const XlsxHeaderFooter(oddFooter: '&P'))
        ..pageSetup(const XlsxPageSetup(scale: 90));
      final XlsxResult result = book.close();
      final String xml = readXlsx(result.bytes)[_sheet1]!;
      final List<int> at = <int>[
        xml.indexOf('<pageSetup'),
        xml.indexOf('<headerFooter'),
        xml.indexOf('<extLst>', xml.indexOf('<headerFooter')),
      ];
      expect(at, everyElement(greaterThan(-1)));
      expect(at[0], lessThan(at[1]));
      expect(at[1], lessThan(at[2]));
      expect(xml, endsWith('</extLst></worksheet>'));
      expect(checkXlsx(result.bytes), isEmpty);
    });
  });

  group('checks', () {
    final Map<String, XlsxHeaderFooter Function(String)> fields =
        <String, XlsxHeaderFooter Function(String)>{
          'oddHeader': (String t) => XlsxHeaderFooter(oddHeader: t),
          'oddFooter': (String t) => XlsxHeaderFooter(oddFooter: t),
          'evenHeader': (String t) => XlsxHeaderFooter(evenHeader: t),
          'evenFooter': (String t) => XlsxHeaderFooter(evenFooter: t),
          'firstHeader': (String t) => XlsxHeaderFooter(firstHeader: t),
          'firstFooter': (String t) => XlsxHeaderFooter(firstFooter: t),
        };

    for (final MapEntry<String, XlsxHeaderFooter Function(String)> f
        in fields.entries) {
      test('${f.key}: 255 units pass, 256 throw', () {
        expect(_write(f.value('a' * 255)), contains('<${f.key}>'));
        expect(() => _write(f.value('a' * 256)), _argumentNamed(f.key));
      });

      test('${f.key}: a lone trailing & throws', () {
        expect(() => _write(f.value('abc&')), _argumentNamed(f.key));
        expect(() => _write(f.value('a&&&')), _argumentNamed(f.key));
        expect(_write(f.value('a&&')), contains('<${f.key}>a&amp;&amp;'));
        expect(_write(f.value('a&P')), contains('<${f.key}>a&amp;P'));
      });

      test('${f.key}: a character XML forbids throws', () {
        expect(() => _write(f.value('a\u0001b')), _argumentNamed(f.key));
      });
    }

    test('a failed call leaves the earlier setting', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        s.headerFooter(const XlsxHeaderFooter(oddHeader: 'kept'));
        expect(
          () => s.headerFooter(const XlsxHeaderFooter(oddFooter: 'bad&')),
          throwsArgumentError,
        );
      });
      expect(xml, contains('<oddHeader>kept</oddHeader>'));
    });

    test('headerFooter on a finished sheet is a StateError', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('A');
      book.addSheet('B');
      expect(
        () => first.headerFooter(const XlsxHeaderFooter(oddHeader: 'x')),
        throwsStateError,
      );
    });
  });

  group('value type', () {
    test('equal values are equal, with a hash and a description', () {
      const XlsxHeaderFooter a = XlsxHeaderFooter(oddHeader: 'x');
      expect(a, const XlsxHeaderFooter(oddHeader: 'x'));
      expect(a.hashCode, const XlsxHeaderFooter(oddHeader: 'x').hashCode);
      expect(a, isNot(const XlsxHeaderFooter(oddHeader: 'y')));
      expect(
        a,
        isNot(const XlsxHeaderFooter(oddHeader: 'x', differentFirst: true)),
      );
      expect(
        a,
        isNot(const XlsxHeaderFooter(oddHeader: 'x', alignWithMargins: false)),
      );
      expect(a.toString(), contains('oddHeader: x'));
    });
  });
}
