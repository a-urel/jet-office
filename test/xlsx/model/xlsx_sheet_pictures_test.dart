import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../fixtures/m4_fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

const String _xdr =
    'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="$relNs"';

String _marker(
  String name,
  int col,
  int row, {
  int colOff = 0,
  int rowOff = 0,
}) =>
    '<xdr:$name><xdr:col>$col</xdr:col><xdr:colOff>$colOff</xdr:colOff>'
    '<xdr:row>$row</xdr:row><xdr:rowOff>$rowOff</xdr:rowOff></xdr:$name>';

String _pic(
  int id, {
  String attributes = '<a:blip r:embed="rId1"/>',
  String name = 'Picture 1',
  String idAttribute = '',
}) =>
    '<xdr:pic><xdr:nvPicPr><xdr:cNvPr ${idAttribute.isEmpty ? 'id="$id"' : idAttribute} '
    'name="$name" descr="Alt &amp; text"/><xdr:cNvPicPr/></xdr:nvPicPr>'
    '<xdr:blipFill>$attributes</xdr:blipFill><xdr:spPr/></xdr:pic>';

String _oneCell(String pic, {String from = ''}) =>
    '<xdr:oneCellAnchor>${from.isEmpty ? _marker('from', 1, 2, colOff: 9525, rowOff: 19050) : from}'
    '<xdr:ext cx="95250" cy="190500"/>$pic<xdr:clientData/></xdr:oneCellAnchor>';

String _twoCell(String pic, {String editAs = ''}) =>
    '<xdr:twoCellAnchor${editAs.isEmpty ? '' : ' editAs="$editAs"'}>'
    '${_marker('from', 0, 0)}${_marker('to', 3, 4)}$pic<xdr:clientData/>'
    '</xdr:twoCellAnchor>';

String _drawing(String anchors, {String prefix = 'xdr'}) {
  final String xml = '<xdr:wsDr $_xdr>$anchors</xdr:wsDr>';
  return prefix == 'xdr'
      ? xml
      : xml
            .replaceAll('xdr:', '$prefix:')
            .replaceAll('xmlns:xdr', 'xmlns:$prefix');
}

/// A one-sheet package whose sheet draws [drawing], with the media [media]
/// (relationship id to part name and bytes) behind it; `extraRels` adds more
/// relationships of the drawing.
Uint8List _package(
  String drawing, {
  Map<String, (String, List<int>)> media =
      const <String, (String, List<int>)>{},
  String extraRels = '',
}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    buildWorkbook(<String, String>{
      'S':
          '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>'
          '<drawing r:id="rId1"/></worksheet>',
    }),
  );
  parts['xl/worksheets/_rels/sheet1.xml.rels'] = Uint8List.fromList(
    utf8.encode(
      '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
      'Type="$relNs/drawing" Target="../drawings/drawing1.xml"/>'
      '</Relationships>',
    ),
  );
  parts['xl/drawings/drawing1.xml'] = Uint8List.fromList(utf8.encode(drawing));
  parts['xl/drawings/_rels/drawing1.xml.rels'] = Uint8List.fromList(
    utf8.encode(
      '<Relationships xmlns="$pkgRelNs">'
      '${media.entries.map((MapEntry<String, (String, List<int>)> e) => '<Relationship Id="${e.key}" Type="$relNs/image" Target="../media/${e.value.$1}"/>').join()}'
      '$extraRels</Relationships>',
    ),
  );
  for (final (String, List<int>) m in media.values) {
    parts['xl/media/${m.$1}'] = Uint8List.fromList(m.$2);
  }
  return buildZip(<String, List<int>>{...parts});
}

int _invalid(XlsxWorkbook book, String detail) => book.warnings
    .where(
      (XlsxWarning w) =>
          w.code == XlsxWarningCode.featureEntryInvalid && w.detail == detail,
    )
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

void _unchanged(Uint8List input, XlsxWorkbook book) => expect(
  comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
  isEmpty,
);

/// A one-sheet workbook without a drawing; [tail] follows `<sheetData>`.
Uint8List _bare({String tail = ''}) => buildWorkbook(<String, String>{
  'S':
      '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>$tail'
      '</worksheet>',
});

/// A picture of [png4x2] at C2, sized, so it reads back equal.
XlsxPicture _sized({String? name = 'Logo', String? description}) => XlsxPicture(
  OfficeImage(png4x2),
  const XlsxOneCellAnchor(XlsxAnchorPoint(1, 2), width: 8, height: 4),
  name: name,
  description: description,
);

/// A chart anchor with a `cNvPr` id of [id].
String _chart(int id) =>
    '<xdr:twoCellAnchor>${_marker('from', 0, 0)}${_marker('to', 2, 2)}'
    '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
    '<xdr:cNvPr id="$id" name="Chart 1"/><xdr:cNvGraphicFramePr/>'
    '</xdr:nvGraphicFramePr><xdr:xfrm/></xdr:graphicFrame>'
    '<xdr:clientData/></xdr:twoCellAnchor>';

String _drawingOf(Uint8List bytes, [int n = 1]) =>
    partText(bytes, 'xl/drawings/drawing$n.xml');

String _drawingRels(Uint8List bytes, [int n = 1]) =>
    partText(bytes, 'xl/drawings/_rels/drawing$n.xml.rels');

void main() {
  test("reads the fixture's pictures", () {
    final Uint8List input = _fixture('m4_images');
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final List<XlsxPicture> pictures = book.sheets[0].pictures;
    expect(pictures, hasLength(3));
    expect(pictures[0].image.bytes, png4x2);
    expect(
      pictures[0].anchor,
      const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 4, height: 2),
    );
    expect(pictures[0].name, 'Picture 1');
    expect(pictures[0].description, isNull);
    expect(pictures[1].image.bytes, jpeg3x5);
    expect(
      pictures[1].anchor,
      const XlsxOneCellAnchor(XlsxAnchorPoint(1, 4), width: 60, height: 100),
    );
    expect(pictures[2].image.bytes, png4x2);
    expect(
      pictures[2].anchor,
      XlsxTwoCellAnchor.range(
        XlsxRange.parse('B6:D10'),
        resize: XlsxPictureResize.move,
      ),
    );
    expect(pictures[2].name, 'Picture 3');
    expect(pictures[2].description, 'The PNG over B6:D10');
    final List<XlsxPicture> again = book.sheets[1].pictures;
    expect(again, hasLength(1));
    expect(
      identical(again.single.image.bytes, pictures[0].image.bytes),
      isTrue,
    );
    expect(identical(pictures[2].image.bytes, pictures[0].image.bytes), isTrue);
    expect(() => pictures.add(pictures.first), throwsUnsupportedError);
    expect(book.warnings, isEmpty);
    _unchanged(input, book);
  });

  test('a sheet without a drawing has no pictures', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_notes'));
    expect(book.sheets.first.pictures, isEmpty);
  });

  test('a chart and a shape beside a picture stay kept and unlisted', () {
    final Uint8List input = _package(
      _drawing(
        '<xdr:twoCellAnchor>${_marker('from', 0, 0)}${_marker('to', 2, 2)}'
        '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
        '<xdr:cNvPr id="5" name="Chart 1"/><xdr:cNvGraphicFramePr/>'
        '</xdr:nvGraphicFramePr><xdr:xfrm/></xdr:graphicFrame>'
        '<xdr:clientData/></xdr:twoCellAnchor>'
        '<xdr:oneCellAnchor>${_marker('from', 0, 5)}<xdr:ext cx="1" cy="1"/>'
        '<xdr:sp><xdr:nvSpPr><xdr:cNvPr id="6" name="Rect"/><xdr:cNvSpPr/>'
        '</xdr:nvSpPr><xdr:spPr/></xdr:sp><xdr:clientData/></xdr:oneCellAnchor>'
        '<xdr:absoluteAnchor><xdr:pos x="0" y="0"/><xdr:ext cx="1" cy="1"/>'
        '${_pic(7)}<xdr:clientData/></xdr:absoluteAnchor>'
        '${_oneCell(_pic(8))}',
      ),
      media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final List<XlsxPicture> pictures = book.sheets.single.pictures;
    expect(pictures, hasLength(1));
    expect(pictures.single.name, 'Picture 1');
    expect(book.warnings, isEmpty);
    _unchanged(input, book);
  });

  test('a linked picture is unlisted without a warning', () {
    final Uint8List input = _package(
      _drawing(_oneCell(_pic(2, attributes: '<a:blip r:link="rId9"/>'))),
      extraRels:
          '<Relationship Id="rId9" Type="$relNs/image" '
          'Target="file:///x.png" TargetMode="External"/>',
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(book.sheets.single.pictures, isEmpty);
    expect(book.warnings, isEmpty);
    _unchanged(input, book);
  });

  test('a dangling embed warns once', () {
    final Uint8List input = _package(
      _drawing(
        _oneCell(_pic(2, attributes: '<a:blip r:embed="rId5"/>')) +
            _oneCell(_pic(3, attributes: '<a:blip r:embed="rId6"/>')),
      ),
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(book.sheets.single.pictures, isEmpty);
    expect(book.sheets.single.pictures, isEmpty);
    expect(_invalid(book, 'pic'), 1);
    _unchanged(input, book);
  });

  test('a marker that is not a number is kept, unlisted and warned', () {
    final Uint8List input = _package(
      _drawing(
        _oneCell(
          _pic(2),
          from: _marker('from', 0, 0).replaceFirst('<xdr:col>0', '<xdr:col>x'),
        ),
      ),
      media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(book.sheets.single.pictures, isEmpty);
    expect(_invalid(book, 'pic'), 1);
    _unchanged(input, book);
  });

  test('a cNvPr without an id is kept, unlisted and warned', () {
    final Uint8List input = _package(
      _drawing(_oneCell(_pic(2, idAttribute: 'idx="1"'))),
      media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(book.sheets.single.pictures, isEmpty);
    expect(_invalid(book, 'pic'), 1);
  });

  test('a GIF is listed with format null', () {
    final List<int> gif = <int>[
      ...'GIF89a'.codeUnits,
      1, 0, 1, 0, 0, 0, 0, 0x3B, //
    ];
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        _drawing(_oneCell(_pic(2))),
        media: <String, (String, List<int>)>{'rId1': ('image1.gif', gif)},
      ),
    );
    final XlsxPicture picture = book.sheets.single.pictures.single;
    expect(picture.image.format, isNull);
    expect(picture.image.bytes, gif);
    expect(book.warnings, isEmpty);
  });

  test('a prefix other than xdr reads', () {
    final Uint8List input = _package(
      _drawing(_twoCell(_pic(2), editAs: 'absolute'), prefix: 'sd'),
      media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxPicture picture = book.sheets.single.pictures.single;
    expect(
      picture.anchor,
      const XlsxTwoCellAnchor(
        XlsxAnchorPoint(0, 0),
        XlsxAnchorPoint(4, 3),
        resize: XlsxPictureResize.none,
      ),
    );
    expect(picture.description, 'Alt & text');
    _unchanged(input, book);
  });

  test('editAs maps to the resize modes', () {
    XlsxPictureResize of(String editAs) {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing(_twoCell(_pic(2), editAs: editAs)),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      return (book.sheets.single.pictures.single.anchor as XlsxTwoCellAnchor)
          .resize;
    }

    expect(of(''), XlsxPictureResize.moveAndSize);
    expect(of('twoCell'), XlsxPictureResize.moveAndSize);
    expect(of('oneCell'), XlsxPictureResize.move);
    expect(of('absolute'), XlsxPictureResize.none);
  });

  test('reading saves the input unchanged', () {
    final Uint8List input = _fixture('m4_images');
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    for (final XlsxSheet sheet in book.sheets) {
      sheet.pictures;
    }
    _unchanged(input, book);
  });
  group('addPicture', () {
    test('adds to a sheet without a drawing', () {
      final Uint8List input = _bare(
        tail:
            '<pageMargins left="1" right="1" top="1" bottom="1" header="0" '
            'footer="0"/><tableParts count="0"/>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxPicture picture = _sized(description: 'The logo');
      book.sheets.single.addPicture(picture);
      expect(book.sheets.single.pictures, <XlsxPicture>[picture]);

      final Uint8List saved = book.save().bytes;
      final String types = partText(saved, '[Content_Types].xml');
      expect(types, contains('Extension="png"'));
      expect(types, contains('ContentType="image/png"'));
      expect(types, contains('PartName="/xl/drawings/drawing1.xml"'));
      expect(types, isNot(contains('PartName="/xl/media')));
      expect(readXlsxBytes(saved)['xl/media/image1.png'], png4x2);
      expect(
        partText(saved, 'xl/worksheets/_rels/sheet1.xml.rels'),
        contains('Target="../drawings/drawing1.xml"'),
      );
      expect(_drawingRels(saved), contains('Target="../media/image1.png"'));
      final String sheet = partText(saved, 'xl/worksheets/sheet1.xml');
      final int margins = sheet.indexOf('<pageMargins');
      final int drawing = sheet.indexOf('<drawing r:id="rId1"');
      expect(margins, greaterThan(0));
      expect(drawing, greaterThan(margins));
      expect(sheet.indexOf('<tableParts'), greaterThan(drawing));

      final XlsxWorkbook again = XlsxWorkbook.open(saved);
      expect(again.sheets.single.pictures, <XlsxPicture>[picture]);
      expect(again.warnings, isEmpty);
    });

    test('renders as the writer does', () {
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('S').picture(_sized(name: null, description: 'A & B'));
      final Uint8List written = writer.close().bytes;
      final XlsxWorkbook book = XlsxWorkbook.open(_bare());
      book.sheets.single.addPicture(_sized(name: null, description: 'A & B'));
      expect(
        compareXml(
          'xl/drawings/drawing1.xml',
          _drawingOf(written),
          _drawingOf(book.save().bytes),
        ),
        isEmpty,
      );
    });

    test('a size left out is the one read back', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_bare());
      final XlsxSheet sheet = book.sheets.single;
      sheet.addPicture(
        XlsxPicture(
          OfficeImage(png4x2),
          const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
        ),
      );
      expect(
        sheet.pictures.single.anchor,
        const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0), width: 4, height: 2),
      );
      expect(sheet.pictures.single.name, 'Picture 1');
    });

    test('adds to a sheet the workbook just added', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_bare());
      final XlsxSheet sheet = book.addSheet('New');
      sheet.addPicture(_sized());
      expect(sheet.pictures, hasLength(1));
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.sheets.last.pictures, <XlsxPicture>[_sized()]);
      expect(again.warnings, isEmpty);
    });

    test('adds beside a chart, keeping it character for character', () {
      final String chart = _chart(5);
      final Uint8List input = _package(_drawing(chart));
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single.addPicture(_sized());
      final Uint8List saved = book.save().bytes;
      final String drawing = _drawingOf(saved);
      expect(drawing, contains(chart));
      expect(drawing.indexOf(chart), lessThan(drawing.indexOf('Logo')));
      expect(drawing, contains('<xdr:cNvPr id="6" name="Logo"'));
      expect(XlsxWorkbook.open(saved).sheets.single.pictures, hasLength(1));
    });

    test("ids stay unique over a group's inner cNvPr", () {
      final Uint8List input = _package(
        _drawing(
          '<xdr:oneCellAnchor>${_marker('from', 0, 0)}'
          '<xdr:ext cx="1" cy="1"/><xdr:grpSp><xdr:nvGrpSpPr>'
          '<xdr:cNvPr id="3" name="Group"/><xdr:cNvGrpSpPr/></xdr:nvGrpSpPr>'
          '<xdr:grpSpPr/><xdr:sp><xdr:nvSpPr>'
          '<xdr:cNvPr id="40" name="Inner"/><xdr:cNvSpPr/></xdr:nvSpPr>'
          '<xdr:spPr/></xdr:sp></xdr:grpSp><xdr:clientData/>'
          '</xdr:oneCellAnchor>',
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single.addPicture(_sized());
      expect(
        _drawingOf(book.save().bytes),
        contains('<xdr:cNvPr id="41" name="Logo"'),
      );
    });

    test('the first id of an empty drawing is 2', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_package(_drawing('')));
      book.sheets.single.addPicture(_sized());
      expect(
        _drawingOf(book.save().bytes),
        contains('<xdr:cNvPr id="2" name="Logo"'),
      );
    });

    test('a default name counts the listed pictures', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_images'));
      final XlsxSheet sheet = book.sheets.first;
      sheet.addPicture(_sized(name: null));
      expect(sheet.pictures.last.name, 'Picture 4');
    });

    test('a root of other prefixes binds what the anchor uses', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing(_oneCell(_pic(2)), prefix: 'sd')
              .replaceAll('xmlns:a=', 'xmlns:dm=')
              .replaceAll('<a:blip', '<dm:blip')
              .replaceAll('xmlns:r=', 'xmlns:rr=')
              .replaceAll(' r:embed', ' rr:embed'),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      book.sheets.single.addPicture(_sized());
      final Uint8List saved = book.save().bytes;
      final XlsxWorkbook again = XlsxWorkbook.open(saved);
      expect(again.sheets.single.pictures, hasLength(2));
      expect(again.sheets.single.pictures.last.name, 'Logo');
      expect(again.warnings, isEmpty);
      expect(_drawingOf(saved), contains('<xdr:oneCellAnchor xmlns:'));
    });

    test('the same bytes share one media part', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String>{'A': worksheet(''), 'B': worksheet('')}),
      );
      book.sheets[0]
        ..addPicture(_sized())
        ..addPicture(_sized());
      book.sheets[1].addPicture(
        XlsxPicture(
          OfficeImage(Uint8List.fromList(png4x2)),
          const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
        ),
      );
      final Uint8List saved = book.save().bytes;
      final Iterable<String> media = readXlsxBytes(
        saved,
      ).keys.where((String name) => name.startsWith('xl/media/'));
      expect(media, <String>['xl/media/image1.png']);
      expect(
        RegExp('<Relationship ').allMatches(_drawingRels(saved)),
        hasLength(1),
      );
      expect(_drawingRels(saved, 2), contains('../media/image1.png'));
    });

    test('the bytes of a part the file had share that part', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_images'));
      book.sheets[1].addPicture(
        XlsxPicture(
          OfficeImage(Uint8List.fromList(jpeg3x5)),
          const XlsxOneCellAnchor(XlsxAnchorPoint(5, 5)),
        ),
      );
      book.sheets[0].addPicture(_sized());
      final Uint8List saved = book.save().bytes;
      final Iterable<String> media = readXlsxBytes(
        saved,
      ).keys.where((String name) => name.startsWith('xl/media/'));
      expect(media, hasLength(2));
      expect(_drawingRels(saved, 2), contains('../media/image2.jpeg'));
      expect(
        RegExp('<Relationship ').allMatches(_drawingRels(saved)),
        hasLength(2),
      );
    });

    test('a new extension adds a Default and takes the next number', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String>{'S': worksheet('')}),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.addPicture(_sized());
      sheet.addPicture(
        XlsxPicture(
          OfficeImage(jpeg3x5),
          const XlsxOneCellAnchor(XlsxAnchorPoint(9, 9)),
        ),
      );
      final Uint8List saved = book.save().bytes;
      expect(readXlsxBytes(saved)['xl/media/image2.jpeg'], jpeg3x5);
      final String types = partText(saved, '[Content_Types].xml');
      expect(types, contains('Extension="jpeg"'));
      expect(types, contains('ContentType="image/jpeg"'));
      expect(sheet.pictures[1].image.bytes, jpeg3x5);
    });

    test('a broken drawing throws StateError', () {
      final Uint8List notDrawing = _package('<other/>');
      final XlsxWorkbook first = XlsxWorkbook.open(notDrawing);
      expect(() => first.sheets.single.addPicture(_sized()), throwsStateError);
      _unchanged(notDrawing, first);

      final Map<String, Uint8List> parts = readXlsxBytes(_package(_drawing('')))
        ..remove('xl/drawings/drawing1.xml');
      final XlsxWorkbook second = XlsxWorkbook.open(
        buildZip(<String, List<int>>{...parts}),
      );
      expect(() => second.sheets.single.addPicture(_sized()), throwsStateError);
    });

    test('a chartsheet throws StateError', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String?>{'C': '<chartsheet xmlns="$mainNs"/>'}),
      );
      expect(() => book.sheets.single.addPicture(_sized()), throwsStateError);
    });

    test('a bad image throws and nothing changes', () {
      final Uint8List input = _bare();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(
        () => book.sheets.single.addPicture(
          XlsxPicture(
            OfficeImage(Uint8List.fromList(<int>[1, 2, 3])),
            const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'image',
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(book.sheets.single.pictures, isEmpty);
      _unchanged(input, book);
    });
  });
  group('movePicture', () {
    const XlsxAnchorPoint from = XlsxAnchorPoint(3, 4);
    const XlsxAnchorPoint to = XlsxAnchorPoint(6, 7, offsetX: 2);

    test('moves one-cell to two-cell keeping pic and clientData', () {
      final String pic = _pic(2);
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing(
            _oneCell(pic)
                .replaceFirst(
                  '<xdr:oneCellAnchor>',
                  '<xdr:oneCellAnchor x:keep="1" xmlns:x="urn:x">',
                )
                .replaceFirst(
                  '<xdr:clientData/>',
                  '<xdr:clientData fPrintsWithSheet="0"/>',
                ),
          ),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      const XlsxAnchor anchor = XlsxTwoCellAnchor(
        from,
        to,
        resize: XlsxPictureResize.none,
      );
      sheet.movePicture(0, anchor);
      expect(sheet.pictures.single.anchor, anchor);
      final Uint8List saved = book.save().bytes;
      final String drawing = _drawingOf(saved);
      expect(drawing, contains(pic));
      expect(drawing, contains('<xdr:clientData fPrintsWithSheet="0"/>'));
      expect(drawing, contains('x:keep="1"'));
      expect(drawing, contains('xmlns:x="urn:x"'));
      expect(drawing, contains('editAs="absolute"'));
      expect(drawing, isNot(contains('oneCellAnchor')));
      expect(drawing, isNot(contains('<xdr:ext')));
      expect(
        drawing,
        contains(
          '<xdr:from><xdr:col>4</xdr:col><xdr:colOff>0</xdr:colOff>'
          '<xdr:row>3</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
          '<xdr:to><xdr:col>7</xdr:col><xdr:colOff>19050</xdr:colOff>'
          '<xdr:row>6</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>$pic',
        ),
      );
      final XlsxWorkbook again = XlsxWorkbook.open(saved);
      expect(again.sheets.single.pictures.single.anchor, anchor);
      expect(again.warnings, isEmpty);
    });

    test('moves two-cell to one-cell, a size left out being the image', () {
      final String pic = _pic(2);
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing(_twoCell(pic, editAs: 'oneCell')),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.movePicture(0, const XlsxOneCellAnchor(from, height: 4));
      expect(
        sheet.pictures.single.anchor,
        const XlsxOneCellAnchor(from, width: 8, height: 4),
      );
      final String drawing = _drawingOf(book.save().bytes);
      expect(drawing, contains(pic));
      expect(drawing, isNot(contains('editAs')));
      expect(drawing, isNot(contains('<xdr:to>')));
      expect(drawing, contains('<xdr:ext cx="76200" cy="38100"/>'));
    });

    test('a move keeps the entries around it and their order', () {
      final String chart = _chart(5);
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing('$chart${_oneCell(_pic(2))}${_oneCell(_pic(3, name: 'B'))}'),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.movePicture(1, const XlsxOneCellAnchor(from, width: 1, height: 1));
      expect(sheet.pictures[1].name, 'B');
      expect(sheet.pictures[1].anchor.from, from);
      expect(sheet.pictures[0].anchor.from, isNot(from));
      final String drawing = _drawingOf(book.save().bytes);
      expect(drawing.indexOf(chart), greaterThan(0));
    });

    test('a default namespace and a prefix other than xdr move', () {
      for (final String prefix in <String>['sd', '']) {
        String xml = _drawing(_oneCell(_pic(2)), prefix: 'sd');
        if (prefix.isEmpty) {
          xml = xml.replaceAll('sd:', '').replaceAll('xmlns:sd', 'xmlns');
        }
        final XlsxWorkbook book = XlsxWorkbook.open(
          _package(
            xml,
            media: <String, (String, List<int>)>{
              'rId1': ('image1.png', png4x2),
            },
          ),
        );
        book.sheets.single.movePicture(0, const XlsxTwoCellAnchor(from, to));
        final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
        expect(
          again.sheets.single.pictures.single.anchor,
          const XlsxTwoCellAnchor(from, to),
        );
        expect(again.warnings, isEmpty);
      }
    });

    test('an unsizable image moved to a size-less anchor throws', () {
      final List<int> gif = <int>[
        ...'GIF89a'.codeUnits,
        1, 0, 1, 0, 0, 0, 0, 0x3B, //
      ];
      final Uint8List input = _package(
        _drawing(_oneCell(_pic(2))),
        media: <String, (String, List<int>)>{'rId1': ('image1.gif', gif)},
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      for (final XlsxAnchor anchor in const <XlsxAnchor>[
        XlsxOneCellAnchor(from),
        XlsxOneCellAnchor(from, width: 5),
        XlsxOneCellAnchor(from, height: 5),
      ]) {
        expect(
          () => sheet.movePicture(0, anchor),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'anchor',
            ),
          ),
        );
      }
      expect(changeLogOf(book).hasChanges, isFalse);
      _unchanged(input, book);
      const XlsxAnchor sized = XlsxOneCellAnchor(from, width: 5, height: 6);
      sheet.movePicture(0, sized);
      expect(sheet.pictures.single.anchor, sized);
      sheet.movePicture(0, const XlsxTwoCellAnchor(from, to));
      expect(sheet.pictures.single.anchor, const XlsxTwoCellAnchor(from, to));
    });

    test('an equal anchor is no edit', () {
      final Uint8List input = _fixture('m4_images');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      sheet.movePicture(2, sheet.pictures[2].anchor);
      sheet.movePicture(0, sheet.pictures[0].anchor);
      sheet.movePicture(0, XlsxOneCellAnchor(sheet.pictures[0].anchor.from));
      expect(changeLogOf(book).hasChanges, isFalse);
      _unchanged(input, book);
    });

    test('a bad index or anchor throws and nothing changes', () {
      final Uint8List input = _fixture('m4_images');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      expect(
        () => sheet.movePicture(3, const XlsxOneCellAnchor(from)),
        throwsRangeError,
      );
      expect(
        () => sheet.movePicture(-1, const XlsxOneCellAnchor(from)),
        throwsRangeError,
      );
      expect(
        () => sheet.movePicture(0, const XlsxTwoCellAnchor(to, from)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'to',
          ),
        ),
      );
      expect(
        () => sheet.movePicture(
          0,
          const XlsxOneCellAnchor(XlsxAnchorPoint(-1, 0)),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'from',
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      _unchanged(input, book);
    });

    test('an index past what is listed skips what is not', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing('${_chart(5)}${_oneCell(_pic(2))}'),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      expect(
        () => book.sheets.single.movePicture(1, const XlsxOneCellAnchor(from)),
        throwsRangeError,
      );
    });

    test('a chartsheet throws StateError', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String?>{'C': '<chartsheet xmlns="$mainNs"/>'}),
      );
      expect(
        () => book.sheets.single.movePicture(0, const XlsxOneCellAnchor(from)),
        throwsStateError,
      );
    });
  });
  group('removePicture', () {
    Iterable<String> mediaOf(Uint8List bytes) => readXlsxBytes(
      bytes,
    ).keys.where((String name) => name.startsWith('xl/media/'));

    test("removes and keeps media another sheet's unloaded drawing shows", () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_images'));
      book.sheets[1].removePicture(0);
      final Uint8List saved = book.save().bytes;
      expect(mediaOf(saved), contains('xl/media/image1.png'));
      final XlsxWorkbook again = XlsxWorkbook.open(saved);
      expect(again.sheets[0].pictures, hasLength(3));
      expect(again.sheets[1].pictures, isEmpty);
    });

    test('removes the media nothing else uses', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_images'));
      final XlsxSheet sheet = book.sheets[0];
      expect(sheet.pictures[1].image.bytes, jpeg3x5);
      sheet.removePicture(1);
      expect(sheet.pictures, hasLength(2));
      final Uint8List saved = book.save().bytes;
      expect(mediaOf(saved), <String>['xl/media/image1.png']);
      expect(_drawingRels(saved), isNot(contains('image2.jpeg')));
      final String types = partText(saved, '[Content_Types].xml');
      expect(types, isNot(contains('PartName="/xl/media')));
      // Its bytes are no more found: adding them again makes a new part.
      sheet.addPicture(
        XlsxPicture(
          OfficeImage(Uint8List.fromList(jpeg3x5)),
          const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
        ),
      );
      expect(mediaOf(book.save().bytes), hasLength(2));
      expect(sheet.pictures.last.image.bytes, jpeg3x5);
    });

    test('keeps a relationship another picture of the drawing names', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_images'));
      final XlsxSheet sheet = book.sheets[0];
      sheet.removePicture(0);
      final Uint8List saved = book.save().bytes;
      expect(_drawingRels(saved), contains('../media/image1.png'));
      expect(sheet.pictures.last.image.bytes, png4x2);
    });

    test('keeps the relationship an opaque entry names', () {
      const String shape =
          '<xdr:oneCellAnchor><xdr:from/><xdr:ext cx="1" cy="1"/><xdr:sp>'
          '<xdr:nvSpPr><xdr:cNvPr id="9" name="S"/><xdr:cNvSpPr/></xdr:nvSpPr>'
          '<xdr:spPr><a:blipFill><a:blip r:embed="rId1"/></a:blipFill>'
          '</xdr:spPr></xdr:sp><xdr:clientData/></xdr:oneCellAnchor>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing('$shape${_oneCell(_pic(2))}'),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      book.sheets.single.removePicture(0);
      final Uint8List saved = book.save().bytes;
      expect(_drawingOf(saved), contains(shape));
      expect(_drawingOf(saved), isNot(contains('<xdr:pic>')));
      expect(_drawingRels(saved), contains('Id="rId1"'));
      expect(mediaOf(saved), <String>['xl/media/image1.png']);
    });

    test("the relationships of the picture's other names go too", () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing(
            '${_chart(5)}${_oneCell(_pic(2, attributes: '<a:blip r:embed="rId1"><a:extLst><a:ext uri="x"><s:svgBlip xmlns:s="urn:s" r:embed="rId2"/></a:ext></a:extLst></a:blip>'))}',
          ),
          media: <String, (String, List<int>)>{
            'rId1': ('image1.png', png4x2),
            'rId2': ('image2.svg', <int>[1, 2, 3]),
          },
        ),
      );
      book.sheets.single.removePicture(0);
      final Uint8List saved = book.save().bytes;
      expect(mediaOf(saved), isEmpty);
      expect(_drawingRels(saved), isNot(contains('Relationship ')));
    });

    test('removing the last entry removes the drawing', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_images'));
      final XlsxSheet sheet = book.sheets[1];
      sheet.removePicture(0);
      final Uint8List saved = book.save().bytes;
      final Map<String, Uint8List> parts = readXlsxBytes(saved);
      expect(parts, isNot(contains('xl/drawings/drawing2.xml')));
      expect(parts, isNot(contains('xl/drawings/_rels/drawing2.xml.rels')));
      expect(
        partText(saved, '[Content_Types].xml'),
        isNot(contains('drawing2.xml')),
      );
      expect(
        partText(saved, 'xl/worksheets/sheet2.xml'),
        isNot(contains('<drawing')),
      );
      expect(
        parts['xl/worksheets/_rels/sheet2.xml.rels'] == null ||
            !partText(
              saved,
              'xl/worksheets/_rels/sheet2.xml.rels',
            ).contains('drawing2'),
        isTrue,
      );
      expect(sheet.pictures, isEmpty);
      // A new picture starts a new drawing.
      sheet.addPicture(_sized());
      expect(sheet.pictures, hasLength(1));
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.sheets[1].pictures, hasLength(1));
      expect(again.warnings, isEmpty);
    });

    test('a drawing that holds something else stays', () {
      final String chart = _chart(5);
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing('$chart${_oneCell(_pic(2))}'),
          media: <String, (String, List<int>)>{'rId1': ('image1.png', png4x2)},
        ),
      );
      book.sheets.single.removePicture(0);
      final Uint8List saved = book.save().bytes;
      expect(_drawingOf(saved), contains(chart));
      expect(partText(saved, 'xl/worksheets/sheet1.xml'), contains('<drawing'));
      expect(mediaOf(saved), isEmpty);
    });

    test('media only a dropped drawing still related goes too', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          _drawing(_oneCell(_pic(2))),
          media: <String, (String, List<int>)>{
            'rId1': ('image1.png', png4x2),
            'rId2': ('image2.jpeg', jpeg3x5),
          },
        ),
      );
      book.sheets.single.removePicture(0);
      expect(mediaOf(book.save().bytes), isEmpty);
    });

    test('a bad index throws and nothing changes', () {
      final Uint8List input = _fixture('m4_images');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(() => book.sheets[0].removePicture(3), throwsRangeError);
      expect(() => book.sheets[0].removePicture(-1), throwsRangeError);
      expect(changeLogOf(book).hasChanges, isFalse);
      _unchanged(input, book);
    });

    test('a chartsheet throws StateError', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String?>{'C': '<chartsheet xmlns="$mainNs"/>'}),
      );
      expect(() => book.sheets.single.removePicture(0), throwsStateError);
    });

    test('unreadable relationships of another part fail with no change', () {
      final Map<String, Uint8List> parts = readXlsxBytes(_fixture('m4_images'));
      parts['xl/worksheets/_rels/sheet9.xml.rels'] = Uint8List.fromList(
        utf8.encode('<Relationships'),
      );
      final Uint8List input = buildZip(<String, List<int>>{...parts});
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets[0];
      final int count = sheet.pictures.length;
      expect(() => sheet.removePicture(1), throwsA(isA<XlsxReadException>()));
      expect(sheet.pictures, hasLength(count));
      expect(changeLogOf(book).hasChanges, isFalse);
    });
  });

  group('undo of add, move and remove restores the file', () {
    void undone(Uint8List input, void Function(XlsxSheet sheet) edit) {
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      final ChangeLog log = changeLogOf(book);
      final List<XlsxPicture> before = sheet.pictures;
      final ChangeSet set = log.transaction(() => edit(sheet));
      final List<XlsxPicture> after = sheet.pictures;
      final Uint8List edited = book.save().bytes;
      log.revertSet(set);
      expect(sheet.pictures, before);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
      log.reapplySet(set);
      expect(sheet.pictures, after);
      expect(
        comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
      log.revertSet(set);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
    }

    final XlsxPicture jpeg = XlsxPicture(
      OfficeImage(jpeg3x5),
      const XlsxOneCellAnchor(XlsxAnchorPoint(7, 7)),
    );

    test('add on a sheet without a drawing', () {
      undone(_bare(), (XlsxSheet s) => s.addPicture(_sized()));
    });

    test('add beside what the drawing holds', () {
      undone(_fixture('m4_images'), (XlsxSheet s) {
        s.addPicture(_sized());
      });
      undone(_package(_drawing(_chart(5))), (XlsxSheet s) {
        s
          ..addPicture(_sized())
          ..addPicture(jpeg);
      });
    });

    test('move', () {
      undone(_fixture('m4_images'), (XlsxSheet s) {
        s
          ..movePicture(
            0,
            const XlsxTwoCellAnchor(
              XlsxAnchorPoint(0, 0),
              XlsxAnchorPoint(1, 1),
            ),
          )
          ..movePicture(2, const XlsxOneCellAnchor(XlsxAnchorPoint(9, 9)));
      });
    });

    test('remove', () {
      undone(_fixture('m4_images'), (XlsxSheet s) => s.removePicture(1));
      undone(_fixture('m4_images'), (XlsxSheet s) => s.removePicture(0));
      undone(_fixture('m4_images'), (XlsxSheet s) {
        s
          ..removePicture(2)
          ..removePicture(1)
          ..removePicture(0);
      });
    });

    test('an add removed in the same breath', () {
      undone(_bare(), (XlsxSheet s) {
        s
          ..addPicture(jpeg)
          ..removePicture(0);
      });
    });

    test('a failed edit leaves no part behind', () {
      final Uint8List input = _bare();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.first;
      expect(
        () => changeLogOf(book).transaction(() {
          sheet.addPicture(_sized());
          throw StateError('later');
        }),
        throwsStateError,
      );
      expect(sheet.pictures, isEmpty);
      _unchanged(input, book);
      // The index forgot the part, so its bytes get a new one.
      sheet.addPicture(_sized());
      expect(readXlsxBytes(book.save().bytes)['xl/media/image1.png'], png4x2);
    });
  });
}
