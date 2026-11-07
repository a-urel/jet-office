// Tests the section values and the codecs of `w:sectPr`: each value round
// trips, a value out of range throws, and a child the model cannot type reads
// `null` and is written as read. They build the XML in memory, so they run on
// the web as well.
import 'package:jet_office/src/docx/model/edit_sink.dart';
import 'package:jet_office/src/docx/model/numbering_formats.dart';
import 'package:jet_office/src/docx/model/property_set.dart';
import 'package:jet_office/src/docx/model/section_formatting.dart';
import 'package:jet_office/src/docx/paragraph_property_codecs.dart';
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/property_codec.dart';
import 'package:jet_office/src/docx/section_property_codecs.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

PropertyElement _element(String xml) {
  final XmlPullReader r = XmlPullReader(
    '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">$xml</w:document>',
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
    '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">$xml</w:document>',
  );
  r.nextTag();
  r.nextTag();
  return PropertyContainer.read(r, schema);
}

final class _Set extends PropertySet {
  _Set(PropertyContainer source)
    : super(source, sectionPropertiesSchema, () => DocxEditSink.none);
}

String _writtenSet(PropertySet s) {
  final StringBuffer b = StringBuffer();
  s.writeTo(
    XmlWriter(b),
    'w:sectPr',
    declaredAbove: const <String, String>{'w': Ns.w, 'r': Ns.rel},
  );
  return b.toString();
}

void main() {
  group('values', () {
    test('page sizes: A4 and Letter, portrait and landscape', () {
      expect(DocxPageSize.a4().widthPt, 595.3);
      expect(DocxPageSize.a4().heightPt, 841.9);
      expect(DocxPageSize.a4().orientation, DocxPageOrientation.portrait);
      final DocxPageSize land = DocxPageSize.a4(landscape: true);
      expect(land.widthPt, 841.9);
      expect(land.heightPt, 595.3);
      expect(land.orientation, DocxPageOrientation.landscape);
      expect(DocxPageSize.letter().widthPt, 612);
      expect(DocxPageSize.letter().heightPt, 792);
      expect(DocxPageSize.letter(landscape: true).widthPt, 792);
      expect(DocxPageSize(612, 792), DocxPageSize.letter());
      expect(
        DocxPageSize(612, 792) == DocxPageSize.letter(landscape: true),
        isFalse,
      );
    });

    test('a page size out of range throws RangeError', () {
      expect(() => DocxPageSize(-1, 10), throwsRangeError);
      expect(() => DocxPageSize(10, 1585), throwsRangeError);
      expect(() => DocxPageSize(0, 1584), returnsNormally);
      expect(() => DocxPageSize(double.nan, 10), throwsArgumentError);
    });

    test('margins: top and bottom are signed, the rest are not', () {
      DocxPageMargins m({
        double top = 72,
        double right = 72,
        double bottom = 72,
        double left = 72,
        double header = 36,
        double footer = 36,
        double gutter = 0,
      }) => DocxPageMargins(
        top: top,
        right: right,
        bottom: bottom,
        left: left,
        header: header,
        footer: footer,
        gutter: gutter,
      );
      expect(m(top: -36, bottom: -1584).topPt, -36);
      expect(() => m(top: -1585), throwsRangeError);
      expect(() => m(bottom: 1585), throwsRangeError);
      expect(() => m(left: -1), throwsRangeError);
      expect(() => m(right: -1), throwsRangeError);
      expect(() => m(header: -1), throwsRangeError);
      expect(() => m(footer: 1585), throwsRangeError);
      expect(() => m(gutter: -0.1), throwsRangeError);
      expect(m(), m());
    });

    test('columns', () {
      expect(DocxColumns().count, 1);
      expect(DocxColumns(count: 3, spacingPt: 18).spacingPt, 18);
      expect(() => DocxColumns(count: 0), throwsRangeError);
      expect(() => DocxColumns(count: 46), throwsRangeError);
      expect(() => DocxColumns(spacingPt: -1), throwsRangeError);
      final DocxColumns unequal = DocxColumns(
        widths: <DocxColumn>[DocxColumn(200, spacingPt: 10), DocxColumn(100)],
      );
      expect(unequal.count, 2);
      expect(unequal.widths, hasLength(2));
      expect(unequal.widths![0].spacingPt, 10);
      expect(
        () => DocxColumns(count: 3, widths: unequal.widths),
        throwsArgumentError,
      );
      expect(() => DocxColumns(widths: <DocxColumn>[]), throwsArgumentError);
      expect(() => DocxColumn(-1), throwsRangeError);
      expect(() => unequal.widths!.add(DocxColumn(1)), throwsUnsupportedError);
      expect(
        unequal,
        DocxColumns(
          widths: <DocxColumn>[DocxColumn(200, spacingPt: 10), DocxColumn(100)],
        ),
      );
    });

    test('page and line numbering', () {
      expect(() => DocxPageNumbering(start: -1), throwsRangeError);
      expect(() => DocxPageNumbering(start: 32768), throwsRangeError);
      expect(() => DocxLineNumbering(countBy: 0), throwsRangeError);
      expect(() => DocxLineNumbering(start: -1), throwsRangeError);
      expect(() => DocxLineNumbering(distancePt: -1), throwsRangeError);
      expect(() => DocxLineNumbering(distancePt: 1585), throwsRangeError);
    });
  });

  group('PageSizeCodec', () {
    const PageSizeCodec codec = PageSizeCodec();

    test('round trips', () {
      for (final DocxPageSize v in <DocxPageSize>[
        DocxPageSize.a4(),
        DocxPageSize.letter(landscape: true),
        DocxPageSize(0, 1584),
      ]) {
        expect(_parse(codec, _written(codec, v)), v);
      }
      expect(
        _written(codec, DocxPageSize.letter()),
        '<w:pgSz w:w="12240" w:h="15840"/>',
      );
      expect(
        _written(codec, DocxPageSize.letter(landscape: true)),
        '<w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/>',
      );
    });

    test('refuses what it cannot type', () {
      expect(_parse(codec, '<w:pgSz w:w="abc" w:h="100"/>'), isNull);
      expect(_parse(codec, '<w:pgSz w:w="100"/>'), isNull);
      expect(_parse(codec, '<w:pgSz w:w="100" w:h="31681"/>'), isNull);
      expect(_parse(codec, '<w:pgSz w:w="-1" w:h="10"/>'), isNull);
      expect(_parse(codec, '<w:pgSz w:w="1" w:h="1" w:orient="x"/>'), isNull);
    });

    test('keeps the paper code as read', () {
      final PropertyElement e = _element(
        '<w:pgSz w:w="11906" w:h="16838" w:code="9"/>',
      );
      expect(codec.parse(e), DocxPageSize.a4());
      final StringBuffer b = StringBuffer();
      codec.write(XmlWriter(b), 'w', DocxPageSize.letter(), e);
      expect(b.toString(), '<w:pgSz w:w="12240" w:h="15840" w:code="9"/>');
    });
  });

  group('PageMarginsCodec', () {
    const PageMarginsCodec codec = PageMarginsCodec();
    final DocxPageMargins margins = DocxPageMargins(
      top: 72,
      right: 54,
      bottom: -36,
      left: 54,
      header: 35.4,
      footer: 35.4,
      gutter: 0,
    );

    test('round trips', () {
      expect(_parse(codec, _written(codec, margins)), margins);
    });

    test('refuses a missing or bad side', () {
      const String all =
          'w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
          'w:header="708" w:footer="708" w:gutter="0"';
      expect(_parse(codec, '<w:pgMar $all/>'), isNotNull);
      expect(
        _parse(
          codec,
          '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" '
          'w:left="1440" w:header="708" w:footer="708"/>',
        ),
        isNull,
      );
      expect(
        _parse(
          codec,
          '<w:pgMar ${all.replaceFirst('w:left="1440"', 'w:left="-1"')}/>',
        ),
        isNull,
      );
      expect(
        _parse(
          codec,
          '<w:pgMar ${all.replaceFirst('w:top="1440"', 'w:top="1in"')}/>',
        ),
        isNull,
      );
    });
  });

  group('ColumnsCodec', () {
    const ColumnsCodec codec = ColumnsCodec();

    test('round trips equal and unequal columns', () {
      for (final DocxColumns v in <DocxColumns>[
        DocxColumns(),
        DocxColumns(count: 3, spacingPt: 18, separator: true),
        DocxColumns(
          widths: <DocxColumn>[DocxColumn(200, spacingPt: 10), DocxColumn(100)],
        ),
      ]) {
        expect(_parse(codec, _written(codec, v)), v);
      }
    });

    test('keeps w:col children as widths', () {
      final DocxColumns? v = _parse(
        codec,
        '<w:cols w:num="2" w:equalWidth="0" w:space="720">'
        '<w:col w:w="4000" w:space="500"/><w:col w:w="2000"/></w:cols>',
      );
      expect(v!.count, 2);
      expect(v.widths![0].widthPt, 200);
      expect(v.widths![0].spacingPt, 25);
      expect(v.widths![1].widthPt, 100);
      expect(v.widths![1].spacingPt, 0);
    });

    test('reads the defaults of an element with no attributes', () {
      final DocxColumns? v = _parse(codec, '<w:cols w:space="708"/>');
      expect(v, DocxColumns(spacingPt: 35.4));
      expect(_parse(codec, '<w:cols/>'), DocxColumns(spacingPt: 36));
    });

    test('refuses what it cannot type', () {
      expect(_parse(codec, '<w:cols w:num="x"/>'), isNull);
      expect(_parse(codec, '<w:cols w:num="0"/>'), isNull);
      expect(_parse(codec, '<w:cols w:sep="maybe"/>'), isNull);
      expect(_parse(codec, '<w:cols w:space="-1"/>'), isNull);
      // Children with equal widths on, a count that is not theirs, a child
      // that is not a column.
      expect(
        _parse(codec, '<w:cols w:num="1"><w:col w:w="100"/></w:cols>'),
        isNull,
      );
      expect(
        _parse(
          codec,
          '<w:cols w:num="3" w:equalWidth="0"><w:col w:w="100"/></w:cols>',
        ),
        isNull,
      );
      expect(_parse(codec, '<w:cols w:equalWidth="0"><w:x/></w:cols>'), isNull);
      expect(
        _parse(codec, '<w:cols w:equalWidth="0"><w:col/></w:cols>'),
        isNull,
      );
      expect(_parse(codec, '<w:cols w:equalWidth="0"/>'), isNull);
    });
  });

  group('enum codecs', () {
    test('type and vAlign', () {
      const SectionStartCodec start = SectionStartCodec();
      for (final DocxSectionStart v in DocxSectionStart.values) {
        expect(_parse(start, _written(start, v)), v);
      }
      expect(_parse(start, '<w:type w:val="x"/>'), isNull);
      expect(_parse(start, '<w:type/>'), isNull);
      const SectionVerticalAlignmentCodec align =
          SectionVerticalAlignmentCodec();
      for (final DocxSectionVerticalAlignment v
          in DocxSectionVerticalAlignment.values) {
        expect(_parse(align, _written(align, v)), v);
      }
      expect(_parse(align, '<w:vAlign w:val="middle"/>'), isNull);
    });
  });

  group('PageNumberingCodec', () {
    const PageNumberingCodec codec = PageNumberingCodec();

    test('round trips', () {
      for (final DocxPageNumbering v in <DocxPageNumbering>[
        DocxPageNumbering(),
        DocxPageNumbering(format: DocxNumberFormat.lowerRoman),
        DocxPageNumbering(start: 5),
        DocxPageNumbering(format: DocxNumberFormat.decimal, start: 0),
      ]) {
        expect(_parse(codec, _written(codec, v)), v);
      }
    });

    test('refuses what it cannot type, keeps the chapter attributes', () {
      expect(_parse(codec, '<w:pgNumType w:fmt="chicago"/>'), isNull);
      expect(_parse(codec, '<w:pgNumType w:start="x"/>'), isNull);
      final PropertyElement e = _element(
        '<w:pgNumType w:fmt="decimal" w:chapStyle="1" w:chapSep="colon"/>',
      );
      expect(
        codec.parse(e),
        DocxPageNumbering(format: DocxNumberFormat.decimal),
      );
      expect(codec.keepsRest(e), isTrue);
      final StringBuffer rest = StringBuffer();
      codec.writeRest(XmlWriter(rest), 'w', e);
      expect(
        rest.toString(),
        '<w:pgNumType w:chapStyle="1" w:chapSep="colon"/>',
      );
      final StringBuffer set = StringBuffer();
      codec.write(XmlWriter(set), 'w', DocxPageNumbering(start: 2), e);
      expect(
        set.toString(),
        '<w:pgNumType w:start="2" w:chapStyle="1" w:chapSep="colon"/>',
      );
      expect(codec.keepsRest(_element('<w:pgNumType w:start="1"/>')), isFalse);
    });
  });

  group('LineNumberingCodec', () {
    const LineNumberingCodec codec = LineNumberingCodec();

    test('round trips', () {
      for (final DocxLineNumbering v in <DocxLineNumbering>[
        DocxLineNumbering(),
        DocxLineNumbering(
          countBy: 5,
          start: 3,
          distancePt: 18,
          restart: DocxLineNumberRestart.continuous,
        ),
        DocxLineNumbering(restart: DocxLineNumberRestart.newSection),
      ]) {
        expect(_parse(codec, _written(codec, v)), v);
      }
    });

    test('refuses what it cannot type', () {
      expect(_parse(codec, '<w:lnNumType w:restart="x"/>'), isNull);
      expect(_parse(codec, '<w:lnNumType w:countBy="0"/>'), isNull);
      expect(_parse(codec, '<w:lnNumType w:distance="abc"/>'), isNull);
    });
  });

  group('SectionReferenceCodec', () {
    const SectionReferenceCodec codec = SectionReferenceCodec(
      'headerReference',
    );

    test('round trips', () {
      for (final SectionReferenceType t in SectionReferenceType.values) {
        final SectionReference v = SectionReference(t, 'rId7');
        final String xml = _written(codec, v);
        expect(_parse(codec, xml.replaceFirst('<w:', '<w:')), v);
      }
      expect(
        _written(
          codec,
          const SectionReference(SectionReferenceType.defaultPage, 'rId1'),
        ),
        '<w:headerReference w:type="default" r:id="rId1"/>',
      );
    });

    test('refuses an unknown type or a missing id', () {
      expect(
        _parse(codec, '<w:headerReference w:type="odd" r:id="rId1"/>'),
        isNull,
      );
      expect(_parse(codec, '<w:headerReference r:id="rId1"/>'), isNull);
      expect(_parse(codec, '<w:headerReference w:type="first"/>'), isNull);
      expect(
        _parse(codec, '<w:headerReference w:type="first" r:id=""/>'),
        isNull,
      );
    });
  });

  group('the section schema', () {
    test('reads a w:sectPr as Word writes it', () {
      final PropertyContainer c = _container(
        '<w:sectPr w:rsidR="00A1">'
        '<w:headerReference w:type="default" r:id="rId8"/>'
        '<w:type w:val="continuous"/>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
        'w:header="708" w:footer="708" w:gutter="0"/>'
        '<w:cols w:space="708"/><w:titlePg/><w:docGrid w:linePitch="360"/>'
        '</w:sectPr>',
        sectionPropertiesSchema,
      );
      expect(c.viewOf('type'), DocxSectionStart.continuous);
      expect(c.viewOf('pgSz'), DocxPageSize.a4());
      expect(c.viewOf('titlePg'), true);
      expect(c.viewOf('cols'), DocxColumns(spacingPt: 35.4));
      expect(c.viewOf('docGrid'), isNull);
      expect(c.repeatedViewsOf('headerReference'), hasLength(1));
      expect(c.repeatedViewsOf('footerReference'), isEmpty);
    });

    test('w:pPr reads w:sectPr as a nested container', () {
      expect(
        paragraphPropertiesSchema.nested['sectPr'],
        same(sectionPropertiesSchema),
      );
      expect(paragraphPropertiesGeneralSchema.nested, isEmpty);
    });

    test('a w:sectPr is written as read until a value is set', () {
      const String xml =
          '<w:sectPr w:rsidR="00A1"><w:pgSz w:w="abc" w:h="1"/>'
          '<w:pgMar w:top="1" w:right="1" w:bottom="1" w:left="1" '
          'w:header="1" w:footer="1"/></w:sectPr>';
      final _Set s = _Set(_container(xml, sectionPropertiesSchema));
      expect(s.valueOf('pgSz'), isNull);
      expect(s.valueOf('pgMar'), isNull);
      expect(_writtenSet(s), xml);
    });
  });
}
