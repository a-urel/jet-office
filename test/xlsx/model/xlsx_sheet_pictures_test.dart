import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
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
}
