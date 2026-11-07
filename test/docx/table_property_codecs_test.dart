// Tests the codecs of table, row and cell properties: what each reads of an
// element, what it refuses, and the exact attributes it writes, then the
// three schemas through a container. They need no file, so they run on the
// web as well.
import 'package:jet_office/src/docx/model/formatting.dart';
import 'package:jet_office/src/docx/model/table_formatting.dart';
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/property_codec.dart';
import 'package:jet_office/src/docx/table_property_codecs.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

PropertyElement _element(String xml) {
  final XmlPullReader r = XmlPullReader(
    '<w:document xmlns:w="${Ns.w}">$xml</w:document>',
  );
  r.nextTag();
  r.nextTag();
  final PropertyElementBuilder builder = PropertyElementBuilder();
  OpaqueXml.capture(r, onEvent: builder.add);
  return builder.element!;
}

String _written<T extends Object>(PropertyCodec<T> codec, T value) {
  final StringBuffer b = StringBuffer();
  codec.write(XmlWriter(b), 'w', value, null);
  return b.toString();
}

T? _parse<T extends Object>(PropertyCodec<T> codec, String xml) =>
    codec.parse(_element(xml));

/// The container [xml] (a `w:<name>`) read by [schema].
PropertyContainer _container(String xml, ContainerSchema schema) {
  final XmlPullReader r = XmlPullReader(
    '<w:document xmlns:w="${Ns.w}">$xml</w:document>',
  );
  r.nextTag();
  r.nextTag();
  return PropertyContainer.read(r, schema);
}

void main() {
  group('TableWidthCodec', () {
    const TableWidthCodec codec = TableWidthCodec('tblW');

    test('reads auto, nil, dxa (also without a type) and pct', () {
      expect(
        _parse(codec, '<w:tblW w:w="0" w:type="auto"/>'),
        const DocxTableWidth.auto(),
      );
      expect(
        _parse(codec, '<w:tblW w:w="0" w:type="nil"/>'),
        const DocxTableWidth.nil(),
      );
      expect(
        _parse(codec, '<w:tblW w:w="2410" w:type="dxa"/>'),
        DocxTableWidth.points(120.5),
      );
      expect(
        _parse(codec, '<w:tblW w:w="2410"/>'),
        DocxTableWidth.points(120.5),
      );
      expect(
        _parse(codec, '<w:tblW w:w="2500" w:type="pct"/>'),
        DocxTableWidth.percent(50),
      );
    });

    test('a percent with a sign, a bad type or a bad number has no view', () {
      for (final String bad in <String>[
        '<w:tblW w:w="50%" w:type="pct"/>',
        '<w:tblW w:w="abc" w:type="dxa"/>',
        '<w:tblW w:w="12345678901234567890" w:type="dxa"/>',
        '<w:tblW w:w="1in" w:type="dxa"/>',
        '<w:tblW w:w="-1" w:type="dxa"/>',
        '<w:tblW w:w="99999" w:type="dxa"/>',
        '<w:tblW w:type="dxa"/>',
        '<w:tblW w:w="0" w:type="other"/>',
        '<w:tblW w:w="60000" w:type="pct"/>',
      ]) {
        expect(_parse(codec, bad), isNull, reason: bad);
      }
    });

    test('writes each kind, points rounded to twips', () {
      expect(
        _written(codec, const DocxTableWidth.auto()),
        '<w:tblW w:w="0" w:type="auto"/>',
      );
      expect(
        _written(codec, const DocxTableWidth.nil()),
        '<w:tblW w:w="0" w:type="nil"/>',
      );
      expect(
        _written(codec, DocxTableWidth.points(100.03)),
        '<w:tblW w:w="2001" w:type="dxa"/>',
      );
      expect(
        _written(codec, DocxTableWidth.percent(33.333)),
        '<w:tblW w:w="1667" w:type="pct"/>',
      );
    });

    test('values compare by kind and stored number and refuse bad input', () {
      expect(DocxTableWidth.points(100), DocxTableWidth.points(100.01));
      expect(
        DocxTableWidth.points(100).hashCode,
        DocxTableWidth.points(100.01).hashCode,
      );
      expect(DocxTableWidth.points(0) == const DocxTableWidth.auto(), isFalse);
      expect(DocxTableWidth.points(1).widthPt, 1);
      expect(DocxTableWidth.percent(50).percent, 50);
      expect(const DocxTableWidth.auto().widthPt, isNull);
      expect(const DocxTableWidth.auto().toString(), contains('auto'));
      expect(
        () => DocxTableWidth.points(double.nan),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => DocxTableWidth.points(1585), throwsA(isA<RangeError>()));
      expect(() => DocxTableWidth.points(-1), throwsA(isA<RangeError>()));
      expect(() => DocxTableWidth.percent(1001), throwsA(isA<RangeError>()));
      expect(
        () => DocxTableWidth.percent(double.infinity),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => DocxTableWidth.percent(1e300), throwsA(isA<RangeError>()));
    });

    test('the cell width codec has its own name', () {
      expect(
        _written(const TableWidthCodec('tcW'), DocxTableWidth.points(72)),
        '<w:tcW w:w="1440" w:type="dxa"/>',
      );
    });
  });

  group('TableLayoutCodec', () {
    const TableLayoutCodec codec = TableLayoutCodec();

    test('reads fixed and autofit from w:type', () {
      expect(
        _parse(codec, '<w:tblLayout w:type="fixed"/>'),
        DocxTableLayout.fixed,
      );
      expect(
        _parse(codec, '<w:tblLayout w:type="autofit"/>'),
        DocxTableLayout.autofit,
      );
      expect(_parse(codec, '<w:tblLayout/>'), isNull);
      expect(_parse(codec, '<w:tblLayout w:type="abc"/>'), isNull);
    });

    test('writes w:type', () {
      expect(
        _written(codec, DocxTableLayout.fixed),
        '<w:tblLayout w:type="fixed"/>',
      );
    });
  });

  group('TableAlignmentCodec', () {
    const TableAlignmentCodec codec = TableAlignmentCodec();

    test('reads left, center and right; start and end have no view', () {
      expect(_parse(codec, '<w:jc w:val="left"/>'), DocxTableAlignment.left);
      expect(
        _parse(codec, '<w:jc w:val="center"/>'),
        DocxTableAlignment.center,
      );
      expect(_parse(codec, '<w:jc w:val="right"/>'), DocxTableAlignment.right);
      expect(_parse(codec, '<w:jc w:val="start"/>'), isNull);
      expect(_parse(codec, '<w:jc w:val="end"/>'), isNull);
      expect(_parse(codec, '<w:jc w:val="abc"/>'), isNull);
    });

    test('writes the value', () {
      expect(
        _written(codec, DocxTableAlignment.center),
        '<w:jc w:val="center"/>',
      );
    });
  });

  group('TableBordersCodec', () {
    const TableBordersCodec codec = TableBordersCodec();
    final DocxBorder single = DocxBorder(
      style: DocxBorderStyle.single,
      widthPt: 0.5,
    );

    test('reads the six sides', () {
      final DocxTableBorders? b = _parse(
        codec,
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:left w:val="single" w:sz="4"/>'
        '<w:bottom w:val="single" w:sz="4"/>'
        '<w:right w:val="single" w:sz="4"/>'
        '<w:insideH w:val="single" w:sz="4"/>'
        '<w:insideV w:val="none" w:sz="0"/>'
        '</w:tblBorders>',
      );
      expect(b, isNotNull);
      expect(b!.top!.style, DocxBorderStyle.single);
      expect(b.insideHorizontal!.style, DocxBorderStyle.single);
      expect(b.insideVertical!.style, DocxBorderStyle.none);
      expect(b.left, isNotNull);
      expect(b.right, isNotNull);
      expect(b.bottom, isNotNull);
    });

    test('an empty element reads as no borders', () {
      expect(_parse(codec, '<w:tblBorders/>'), const DocxTableBorders());
    });

    test('start, end, a side twice, an unknown child or a bad side give no '
        'view', () {
      for (final String bad in <String>[
        '<w:tblBorders><w:start w:val="single" w:sz="4"/></w:tblBorders>',
        '<w:tblBorders><w:end w:val="single" w:sz="4"/></w:tblBorders>',
        '<w:tblBorders><w:top w:val="single" w:sz="4"/>'
            '<w:top w:val="single" w:sz="4"/></w:tblBorders>',
        '<w:tblBorders><w:tl2br w:val="single" w:sz="4"/></w:tblBorders>',
        '<w:tblBorders><w:top w:val="single" w:sz="abc"/></w:tblBorders>',
        '<w:tblBorders><w:x/></w:tblBorders>',
        '<w:tblBorders w:val="x"/>',
      ]) {
        expect(_parse(codec, bad), isNull, reason: bad);
      }
    });

    test('writes the sides in schema order', () {
      expect(
        _written(
          codec,
          DocxTableBorders(insideVertical: single, top: single, left: single),
        ),
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0"/>'
        '<w:left w:val="single" w:sz="4" w:space="0"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0"/>'
        '</w:tblBorders>',
      );
    });
  });

  group('CellBordersCodec', () {
    const CellBordersCodec codec = CellBordersCodec();
    final DocxBorder single = DocxBorder(
      style: DocxBorderStyle.single,
      widthPt: 0.5,
    );

    test('reads the sides and the two diagonals', () {
      final DocxCellBorders? b = _parse(
        codec,
        '<w:tcBorders><w:top w:val="single" w:sz="4"/>'
        '<w:tl2br w:val="single" w:sz="4"/>'
        '<w:tr2bl w:val="single" w:sz="4"/>'
        '<w:insideH w:val="single" w:sz="4"/></w:tcBorders>',
      );
      expect(b!.top, isNotNull);
      expect(b.topLeftToBottomRight, isNotNull);
      expect(b.topRightToBottomLeft, isNotNull);
      expect(b.insideHorizontal, isNotNull);
      expect(b.bottom, isNull);
    });

    test('start and end give no view', () {
      expect(
        _parse(
          codec,
          '<w:tcBorders><w:start w:val="single" w:sz="4"/></w:tcBorders>',
        ),
        isNull,
      );
      expect(
        _parse(
          codec,
          '<w:tcBorders><w:end w:val="single" w:sz="4"/></w:tcBorders>',
        ),
        isNull,
      );
    });

    test('writes the sides and diagonals in schema order', () {
      expect(
        _written(
          codec,
          DocxCellBorders(
            topRightToBottomLeft: single,
            topLeftToBottomRight: single,
            bottom: single,
            top: single,
          ),
        ),
        '<w:tcBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0"/>'
        '<w:tl2br w:val="single" w:sz="4" w:space="0"/>'
        '<w:tr2bl w:val="single" w:sz="4" w:space="0"/>'
        '</w:tcBorders>',
      );
    });
  });

  group('TableIndentCodec', () {
    const TableIndentCodec codec = TableIndentCodec();

    test('reads signed twips of type dxa, or no type', () {
      expect(_parse(codec, '<w:tblInd w:w="108" w:type="dxa"/>'), 5.4);
      expect(_parse(codec, '<w:tblInd w:w="-108"/>'), -5.4);
      expect(_parse(codec, '<w:tblInd w:w="31680" w:type="dxa"/>'), 1584);
    });

    test('a type other than dxa, a bad or far number or a child give no '
        'view', () {
      for (final String bad in <String>[
        '<w:tblInd w:w="108" w:type="pct"/>',
        '<w:tblInd w:w="108" w:type="auto"/>',
        '<w:tblInd w:w="1in" w:type="dxa"/>',
        '<w:tblInd w:w="31681" w:type="dxa"/>',
        '<w:tblInd w:w="-31681" w:type="dxa"/>',
        '<w:tblInd/>',
        '<w:tblInd w:w="1"><w:x/></w:tblInd>',
      ]) {
        expect(_parse(codec, bad), isNull, reason: bad);
      }
    });

    test('writes w:w in twips and w:type dxa', () {
      expect(_written(codec, -5.0), '<w:tblInd w:w="-100" w:type="dxa"/>');
      expect(_written(codec, 5.4), '<w:tblInd w:w="108" w:type="dxa"/>');
    });
  });

  group('TableMarginsCodec', () {
    const TableMarginsCodec codec = TableMarginsCodec();

    test('reads dxa sides, with or without a type', () {
      final DocxTableMargins? m = _parse(
        codec,
        '<w:tblCellMar><w:top w:w="0" w:type="dxa"/>'
        '<w:left w:w="108" w:type="dxa"/><w:bottom w:w="0"/>'
        '<w:right w:w="108" w:type="dxa"/></w:tblCellMar>',
      );
      expect(m!.topPt, 0);
      expect(m.leftPt, 5.4);
      expect(m.bottomPt, 0);
      expect(m.rightPt, 5.4);
    });

    test('a side in pct, start or end, a bad number or a side twice give no '
        'view', () {
      for (final String bad in <String>[
        '<w:tblCellMar><w:left w:w="50" w:type="pct"/></w:tblCellMar>',
        '<w:tblCellMar><w:start w:w="1" w:type="dxa"/></w:tblCellMar>',
        '<w:tblCellMar><w:end w:w="1" w:type="dxa"/></w:tblCellMar>',
        '<w:tblCellMar><w:left w:w="abc" w:type="dxa"/></w:tblCellMar>',
        '<w:tblCellMar><w:left w:w="12345678901234567890"/></w:tblCellMar>',
        '<w:tblCellMar><w:left w:w="1in"/></w:tblCellMar>',
        '<w:tblCellMar><w:left w:type="dxa"/></w:tblCellMar>',
        '<w:tblCellMar><w:left w:w="1"/><w:left w:w="2"/></w:tblCellMar>',
      ]) {
        expect(_parse(codec, bad), isNull, reason: bad);
      }
    });

    test('writes dxa sides in schema order, rounded', () {
      expect(
        _written(codec, DocxTableMargins(rightPt: 5.43, topPt: 1, leftPt: 2)),
        '<w:tblCellMar>'
        '<w:top w:w="20" w:type="dxa"/>'
        '<w:left w:w="40" w:type="dxa"/>'
        '<w:right w:w="109" w:type="dxa"/>'
        '</w:tblCellMar>',
      );
    });

    test('values compare, print and refuse bad input', () {
      expect(DocxTableMargins(topPt: 1), DocxTableMargins(topPt: 1.01));
      expect(
        DocxTableMargins(topPt: 1).hashCode,
        DocxTableMargins(topPt: 1.01).hashCode,
      );
      expect(DocxTableMargins(topPt: 1).toString(), contains('topPt: '));
      expect(() => DocxTableMargins(leftPt: -1), throwsA(isA<RangeError>()));
      expect(
        () => DocxTableMargins(leftPt: double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TableLookCodec', () {
    const TableLookCodec codec = TableLookCodec();

    test('Word\'s look of builtins.docx reads and writes 04A0', () {
      final DocxTableLook? look = _parse(
        codec,
        '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" '
        'w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>',
      );
      expect(
        look,
        const DocxTableLook(
          firstRow: true,
          firstColumn: true,
          noVerticalBands: true,
        ),
      );
      expect(
        _written(codec, look!),
        '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" '
        'w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>',
      );
    });

    test('without attributes the bits of w:val are read', () {
      expect(
        _parse(codec, '<w:tblLook w:val="0660"/>'),
        const DocxTableLook(
          firstRow: true,
          lastRow: true,
          noHorizontalBands: true,
          noVerticalBands: true,
        ),
      );
      expect(
        _parse(codec, '<w:tblLook w:val="0180"/>'),
        const DocxTableLook(firstColumn: true, lastColumn: true),
      );
    });

    test('the attributes win over w:val', () {
      expect(
        _parse(codec, '<w:tblLook w:val="0000" w:firstRow="1"/>'),
        const DocxTableLook(firstRow: true),
      );
    });

    test('a bad value or a bit the model lacks has no view', () {
      for (final String bad in <String>[
        '<w:tblLook w:val="abc"/>',
        '<w:tblLook w:val="12345"/>',
        '<w:tblLook w:val="0001"/>',
        '<w:tblLook w:val="0800"/>',
        '<w:tblLook w:firstRow="maybe"/>',
        '<w:tblLook w:val="04A0" w:firstRow="abc"/>',
      ]) {
        expect(_parse(codec, bad), isNull, reason: bad);
      }
    });

    test('an element with neither reads as no flag on', () {
      expect(_parse(codec, '<w:tblLook/>'), const DocxTableLook());
    });

    test('writes the bits of every flag', () {
      expect(
        _written(
          codec,
          const DocxTableLook(
            lastRow: true,
            lastColumn: true,
            noHorizontalBands: true,
          ),
        ),
        '<w:tblLook w:val="0340" w:firstRow="0" w:lastRow="1" '
        'w:firstColumn="0" w:lastColumn="1" w:noHBand="1" w:noVBand="0"/>',
      );
    });

    test('values compare and print', () {
      expect(const DocxTableLook(), const DocxTableLook());
      expect(const DocxTableLook(firstRow: true), isNot(const DocxTableLook()));
      expect(
        const DocxTableLook(firstRow: true).hashCode,
        const DocxTableLook(firstRow: true).hashCode,
      );
      expect(const DocxTableLook().toString(), contains('firstRow: false'));
    });
  });

  group('RowHeightCodec', () {
    const RowHeightCodec codec = RowHeightCodec();

    test('reads the height and rule', () {
      expect(_parse(codec, '<w:trHeight w:val="567"/>'), DocxRowHeight(28.35));
      expect(
        _parse(codec, '<w:trHeight w:val="567" w:hRule="auto"/>'),
        DocxRowHeight(28.35),
      );
      expect(
        _parse(codec, '<w:trHeight w:val="567" w:hRule="atLeast"/>'),
        DocxRowHeight(28.35),
      );
      expect(
        _parse(codec, '<w:trHeight w:val="567" w:hRule="exact"/>'),
        DocxRowHeight(28.35, rule: DocxRowHeightRule.exact),
      );
    });

    test('a bad number or rule, or no height, has no view', () {
      for (final String bad in <String>[
        '<w:trHeight w:val="abc"/>',
        '<w:trHeight w:val="12345678901234567890"/>',
        '<w:trHeight w:val="1in"/>',
        '<w:trHeight w:val="-1"/>',
        '<w:trHeight w:val="99999"/>',
        '<w:trHeight/>',
        '<w:trHeight w:val="1" w:hRule="abc"/>',
      ]) {
        expect(_parse(codec, bad), isNull, reason: bad);
      }
    });

    test('writes the height rounded and the rule', () {
      expect(
        _written(codec, DocxRowHeight(28.34)),
        '<w:trHeight w:val="567" w:hRule="atLeast"/>',
      );
      expect(
        _written(codec, DocxRowHeight(20, rule: DocxRowHeightRule.exact)),
        '<w:trHeight w:val="400" w:hRule="exact"/>',
      );
    });

    test('values compare, print and refuse bad input', () {
      expect(DocxRowHeight(10), DocxRowHeight(10.01));
      expect(DocxRowHeight(10).hashCode, DocxRowHeight(10.01).hashCode);
      expect(
        DocxRowHeight(10) == DocxRowHeight(10, rule: DocxRowHeightRule.exact),
        isFalse,
      );
      expect(DocxRowHeight(10).toString(), contains('atLeast'));
      expect(() => DocxRowHeight(-1), throwsA(isA<RangeError>()));
      expect(() => DocxRowHeight(1585), throwsA(isA<RangeError>()));
      expect(() => DocxRowHeight(double.nan), throwsA(isA<ArgumentError>()));
    });
  });

  group('VerticalMergeCodec', () {
    const VerticalMergeCodec codec = VerticalMergeCodec();

    test('no w:val and continue are a continuation', () {
      expect(_parse(codec, '<w:vMerge/>'), DocxVerticalMerge.continuation);
      expect(
        _parse(codec, '<w:vMerge w:val="continue"/>'),
        DocxVerticalMerge.continuation,
      );
      expect(
        _parse(codec, '<w:vMerge w:val="restart"/>'),
        DocxVerticalMerge.restart,
      );
      expect(_parse(codec, '<w:vMerge w:val="abc"/>'), isNull);
    });

    test('writes restart with its value and a continuation as Word does', () {
      expect(
        _written(codec, DocxVerticalMerge.restart),
        '<w:vMerge w:val="restart"/>',
      );
      expect(_written(codec, DocxVerticalMerge.continuation), '<w:vMerge/>');
    });
  });

  group('CellAlignmentCodec', () {
    const CellAlignmentCodec codec = CellAlignmentCodec();

    test('reads top, center and bottom; both has no view', () {
      expect(_parse(codec, '<w:vAlign w:val="top"/>'), DocxCellAlignment.top);
      expect(
        _parse(codec, '<w:vAlign w:val="center"/>'),
        DocxCellAlignment.center,
      );
      expect(
        _parse(codec, '<w:vAlign w:val="bottom"/>'),
        DocxCellAlignment.bottom,
      );
      expect(_parse(codec, '<w:vAlign w:val="both"/>'), isNull);
      expect(_parse(codec, '<w:vAlign/>'), isNull);
    });

    test('writes the value', () {
      expect(
        _written(codec, DocxCellAlignment.bottom),
        '<w:vAlign w:val="bottom"/>',
      );
    });
  });

  group('TextDirectionCodec', () {
    const TextDirectionCodec codec = TextDirectionCodec();
    const Map<String, DocxTextDirection> spellings =
        <String, DocxTextDirection>{
          'lrTb': DocxTextDirection.leftToRightTopToBottom,
          'tbRl': DocxTextDirection.topToBottomRightToLeft,
          'btLr': DocxTextDirection.bottomToTopLeftToRight,
          'lrTbV': DocxTextDirection.lrTbV,
          'tbRlV': DocxTextDirection.tbRlV,
          'tbLrV': DocxTextDirection.tbLrV,
        };

    test('reads and writes the six spellings', () {
      spellings.forEach((String xml, DocxTextDirection value) {
        expect(_parse(codec, '<w:textDirection w:val="$xml"/>'), value);
        expect(_written(codec, value), '<w:textDirection w:val="$xml"/>');
      });
    });

    test('the other spellings have no view', () {
      for (final String other in <String>['lr', 'rl', 'tb', 'tbV', 'abc']) {
        expect(_parse(codec, '<w:textDirection w:val="$other"/>'), isNull);
      }
    });
  });

  group('the schemas', () {
    test('tablePropertiesSchema types the seven properties and tblStyle', () {
      expect(tablePropertiesSchema.codecs.keys.toSet(), <String>{
        'tblStyle', 'tblW', 'jc', 'tblInd', 'tblBorders', 'tblLayout', //
        'tblCellMar', 'tblLook',
      });
      final PropertyContainer c = _container(
        '<w:tblPr><w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/><w:jc w:val="center"/>'
        '<w:tblLayout w:type="fixed"/><w:tblInd w:w="0" w:type="dxa"/>'
        '</w:tblPr>',
        tablePropertiesSchema,
      );
      expect(c.viewOf('tblStyle'), 'TableGrid');
      expect(c.viewOf('tblW'), const DocxTableWidth.auto());
      expect(c.viewOf('jc'), DocxTableAlignment.center);
      expect(c.viewOf('tblLayout'), DocxTableLayout.fixed);
      expect(c.viewOf('tblInd'), 0);
    });

    test('tableRowPropertiesSchema types five properties', () {
      expect(tableRowPropertiesSchema.codecs.keys.toSet(), <String>{
        'gridBefore', 'gridAfter', 'cantSplit', 'trHeight', 'tblHeader', //
      });
      final PropertyContainer c = _container(
        '<w:trPr><w:gridBefore w:val="1"/><w:cantSplit/>'
        '<w:trHeight w:val="400" w:hRule="exact"/><w:tblHeader w:val="0"/>'
        '<w:jc w:val="center"/></w:trPr>',
        tableRowPropertiesSchema,
      );
      expect(c.viewOf('gridBefore'), 1);
      expect(c.viewOf('gridAfter'), isNull);
      expect(c.viewOf('cantSplit'), isTrue);
      expect(
        c.viewOf('trHeight'),
        DocxRowHeight(20, rule: DocxRowHeightRule.exact),
      );
      expect(c.viewOf('tblHeader'), isFalse);
      expect(c.viewOf('jc'), isNull);
    });

    test('tableCellPropertiesSchema types seven properties', () {
      expect(tableCellPropertiesSchema.codecs.keys.toSet(), <String>{
        'tcW', 'gridSpan', 'vMerge', 'tcBorders', 'shd', 'textDirection', //
        'vAlign',
      });
      final PropertyContainer c = _container(
        '<w:tcPr><w:tcW w:w="2410" w:type="dxa"/><w:gridSpan w:val="2"/>'
        '<w:vMerge w:val="restart"/><w:shd w:val="clear" w:fill="FFFF00"/>'
        '<w:vAlign w:val="center"/><w:noWrap/></w:tcPr>',
        tableCellPropertiesSchema,
      );
      expect(c.viewOf('tcW'), DocxTableWidth.points(120.5));
      expect(c.viewOf('gridSpan'), 2);
      expect(c.viewOf('vMerge'), DocxVerticalMerge.restart);
      expect(c.viewOf('shd'), isA<DocxShading>());
      expect(c.viewOf('vAlign'), DocxCellAlignment.center);
      expect(c.viewOf('noWrap'), isNull);
    });

    test('gridSpan below 1 and gridBefore below 0 have no view', () {
      expect(
        _container(
          '<w:tcPr><w:gridSpan w:val="0"/></w:tcPr>',
          tableCellPropertiesSchema,
        ).viewOf('gridSpan'),
        isNull,
      );
      expect(
        _container(
          '<w:trPr><w:gridBefore w:val="-1"/></w:trPr>',
          tableRowPropertiesSchema,
        ).viewOf('gridBefore'),
        isNull,
      );
    });

    test('an attribute a codec does not know gives the child no view', () {
      expect(
        _container(
          '<w:tcPr><w:tcW w:w="1" w:type="dxa" w:x="1"/></w:tcPr>',
          tableCellPropertiesSchema,
        ).viewOf('tcW'),
        isNull,
      );
    });
  });
}
