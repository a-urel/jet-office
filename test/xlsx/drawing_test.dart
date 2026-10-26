import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xlsx/sheet_writer.dart';
import 'package:jet_office/src/xlsx/workbook_context.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import '../fixtures/m4_fixtures.dart' show jpeg3x5, png4x2;
import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const String _drawing1 = 'xl/drawings/drawing1.xml';
const String _drawingRels1 = 'xl/drawings/_rels/drawing1.xml.rels';
const String _sheet1 = 'xl/worksheets/sheet1.xml';
const String _sheetRels1 = 'xl/worksheets/_rels/sheet1.xml.rels';

/// The PNG at [row], [column] in its own size.
XlsxPicture _png(int row, int column, {Uint8List? bytes}) => XlsxPicture(
  XlsxImage(bytes ?? png4x2),
  XlsxOneCellAnchor(XlsxAnchorPoint(row, column)),
);

/// The workbook whose one sheet, `S`, [script] fills, built and checked:
/// the file must pass the checker.
Uint8List _book(void Function(XlsxSheetWriter sheet) script) {
  final XlsxWriter book = XlsxWriter();
  script(book.addSheet('S'));
  final XlsxResult result = book.close();
  expect(checkXlsx(result.bytes), isEmpty);
  return result.bytes;
}

/// The text parts of [_book].
Map<String, String> _parts(void Function(XlsxSheetWriter sheet) script) =>
    readXlsx(_book(script));

/// The `xdr:pic` of picture `id - 1` named [name], pointing at [embed],
/// whose `spPr` holds [spPr].
String _pic(int id, String name, String embed, String spPr) =>
    '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="$id" name="$name"/>'
    '<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>'
    '</xdr:nvPicPr><xdr:blipFill><a:blip r:embed="$embed"/>'
    '<a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
    '<xdr:spPr>$spPr</xdr:spPr></xdr:pic>';

/// A marker, `xdr:from` or `xdr:to`, at the cell ([row], [column]) with
/// the offsets [colOff] and [rowOff] in EMU.
String _marker(
  String name,
  int row,
  int column, {
  int colOff = 0,
  int rowOff = 0,
}) =>
    '<xdr:$name><xdr:col>$column</xdr:col><xdr:colOff>$colOff</xdr:colOff>'
    '<xdr:row>$row</xdr:row><xdr:rowOff>$rowOff</xdr:rowOff></xdr:$name>';

/// The `spPr` of a one-cell picture of [cx] × [cy] EMU.
String _oneCellSpPr(int cx, int cy) =>
    '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>';

const String _twoCellSpPr = '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>';

/// The `xdr:ext` of a one-cell picture in [parts]' first drawing, as
/// (cx, cy).
(int, int) _extent(Map<String, String> parts) {
  final RegExpMatch m = RegExp(
    r'<xdr:ext cx="(\d+)" cy="(\d+)"/>',
  ).firstMatch(parts[_drawing1]!)!;
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

void main() {
  group('XlsxAnchorPoint', () {
    test('takes a cell and offsets in pixels, 0 by default', () {
      const XlsxAnchorPoint point = XlsxAnchorPoint(
        2,
        3,
        offsetX: 1.5,
        offsetY: 2.5,
      );
      expect(point.row, 2);
      expect(point.column, 3);
      expect(point.offsetX, 1.5);
      expect(point.offsetY, 2.5);
      expect(const XlsxAnchorPoint(0, 0).offsetX, 0);
      expect(const XlsxAnchorPoint(0, 0).offsetY, 0);
    });

    test('== compares every field', () {
      const XlsxAnchorPoint point = XlsxAnchorPoint(1, 2);
      expect(point, const XlsxAnchorPoint(1, 2, offsetX: 0, offsetY: 0));
      expect(point.hashCode, const XlsxAnchorPoint(1, 2).hashCode);
      expect(point, isNot(const XlsxAnchorPoint(2, 2)));
      expect(point, isNot(const XlsxAnchorPoint(1, 3)));
      expect(point, isNot(const XlsxAnchorPoint(1, 2, offsetX: 1)));
      expect(point, isNot(const XlsxAnchorPoint(1, 2, offsetY: 1)));
    });

    test('toString names every field, alike on every platform', () {
      expect(
        const XlsxAnchorPoint(1, 2, offsetX: 1.5).toString(),
        'XlsxAnchorPoint(row: 1, column: 2, offsetX: 1.5, offsetY: 0)',
      );
      expect(
        const XlsxAnchorPoint(0, 0, offsetY: double.nan).toString(),
        'XlsxAnchorPoint(row: 0, column: 0, offsetX: 0, offsetY: NaN)',
      );
    });
  });

  group('XlsxOneCellAnchor', () {
    test('takes a corner and an optional size', () {
      const XlsxOneCellAnchor anchor = XlsxOneCellAnchor(
        XlsxAnchorPoint(1, 1),
        width: 8,
        height: 4,
      );
      expect(anchor.from, const XlsxAnchorPoint(1, 1));
      expect(anchor.width, 8);
      expect(anchor.height, 4);
      const XlsxOneCellAnchor natural = XlsxOneCellAnchor(
        XlsxAnchorPoint(1, 1),
      );
      expect(natural.width, isNull);
      expect(natural.height, isNull);
    });

    test('== compares every field', () {
      const XlsxOneCellAnchor anchor = XlsxOneCellAnchor(
        XlsxAnchorPoint(1, 1),
        width: 8,
      );
      expect(anchor, const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 8));
      expect(
        anchor.hashCode,
        const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 8).hashCode,
      );
      expect(
        anchor,
        isNot(const XlsxOneCellAnchor(XlsxAnchorPoint(1, 2), width: 8)),
      );
      expect(anchor, isNot(const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1))));
      expect(
        anchor,
        isNot(
          const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 8, height: 4),
        ),
      );
    });

    test('toString names every field', () {
      expect(
        const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 7.5).toString(),
        'XlsxOneCellAnchor(XlsxAnchorPoint(row: 1, column: 1, offsetX: 0, '
        'offsetY: 0), width: 7.5, height: null)',
      );
    });
  });

  group('XlsxTwoCellAnchor', () {
    test('takes two corners and moves and sizes with cells by default', () {
      const XlsxTwoCellAnchor anchor = XlsxTwoCellAnchor(
        XlsxAnchorPoint(1, 1),
        XlsxAnchorPoint(5, 4),
      );
      expect(anchor.from, const XlsxAnchorPoint(1, 1));
      expect(anchor.to, const XlsxAnchorPoint(5, 4));
      expect(anchor.resize, XlsxPictureResize.moveAndSize);
    });

    test('range covers the range: to is the cell after its last', () {
      final XlsxTwoCellAnchor anchor = XlsxTwoCellAnchor.range(
        const XlsxRange(1, 1, 4, 3),
        resize: XlsxPictureResize.move,
      );
      expect(anchor.from, const XlsxAnchorPoint(1, 1));
      expect(anchor.to, const XlsxAnchorPoint(5, 4));
      expect(anchor.resize, XlsxPictureResize.move);
      expect(
        XlsxTwoCellAnchor.range(const XlsxRange(0, 0)).resize,
        XlsxPictureResize.moveAndSize,
      );
    });

    test('range does not validate', () {
      final XlsxTwoCellAnchor anchor = XlsxTwoCellAnchor.range(
        const XlsxRange(1048575, 16383),
      );
      expect(anchor.to, const XlsxAnchorPoint(1048576, 16384));
    });

    test('== compares every field', () {
      const XlsxTwoCellAnchor anchor = XlsxTwoCellAnchor(
        XlsxAnchorPoint(1, 1),
        XlsxAnchorPoint(5, 4),
      );
      expect(anchor, XlsxTwoCellAnchor.range(const XlsxRange(1, 1, 4, 3)));
      expect(
        anchor.hashCode,
        XlsxTwoCellAnchor.range(const XlsxRange(1, 1, 4, 3)).hashCode,
      );
      expect(
        anchor,
        isNot(
          const XlsxTwoCellAnchor(XlsxAnchorPoint(1, 2), XlsxAnchorPoint(5, 4)),
        ),
      );
      expect(
        anchor,
        isNot(
          const XlsxTwoCellAnchor(XlsxAnchorPoint(1, 1), XlsxAnchorPoint(5, 5)),
        ),
      );
      expect(
        anchor,
        isNot(
          const XlsxTwoCellAnchor(
            XlsxAnchorPoint(1, 1),
            XlsxAnchorPoint(5, 4),
            resize: XlsxPictureResize.none,
          ),
        ),
      );
      expect(anchor, isNot(const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1))));
    });

    test('toString names every field', () {
      expect(
        const XlsxTwoCellAnchor(
          XlsxAnchorPoint(1, 1),
          XlsxAnchorPoint(5, 4),
          resize: XlsxPictureResize.none,
        ).toString(),
        'XlsxTwoCellAnchor(XlsxAnchorPoint(row: 1, column: 1, offsetX: 0, '
        'offsetY: 0), XlsxAnchorPoint(row: 5, column: 4, offsetX: 0, '
        'offsetY: 0), resize: none)',
      );
    });
  });

  group('XlsxPicture', () {
    const XlsxAnchor anchor = XlsxOneCellAnchor(XlsxAnchorPoint(1, 1));

    test('takes an image, an anchor, a name and a description', () {
      final XlsxImage image = XlsxImage(png4x2);
      final XlsxPicture picture = XlsxPicture(
        image,
        anchor,
        name: 'Logo',
        description: 'The company logo',
      );
      expect(picture.image, image);
      expect(picture.anchor, anchor);
      expect(picture.name, 'Logo');
      expect(picture.description, 'The company logo');
      final XlsxPicture plain = XlsxPicture(image, anchor);
      expect(plain.name, isNull);
      expect(plain.description, isNull);
    });

    test('== compares every field, the image by its bytes', () {
      final XlsxPicture picture = XlsxPicture(
        XlsxImage(png4x2),
        anchor,
        name: 'n',
        description: 'd',
      );
      final XlsxPicture copy = XlsxPicture(
        XlsxImage(Uint8List.fromList(png4x2)),
        anchor,
        name: 'n',
        description: 'd',
      );
      expect(picture, copy);
      expect(picture.hashCode, copy.hashCode);
      expect(
        picture,
        isNot(
          XlsxPicture(XlsxImage(jpeg3x5), anchor, name: 'n', description: 'd'),
        ),
      );
      expect(
        picture,
        isNot(
          XlsxPicture(
            XlsxImage(png4x2),
            const XlsxOneCellAnchor(XlsxAnchorPoint(1, 2)),
            name: 'n',
            description: 'd',
          ),
        ),
      );
      expect(
        picture,
        isNot(XlsxPicture(XlsxImage(png4x2), anchor, description: 'd')),
      );
      expect(picture, isNot(XlsxPicture(XlsxImage(png4x2), anchor, name: 'n')));
    });

    test('toString names every field', () {
      expect(
        XlsxPicture(
          XlsxImage(png4x2),
          anchor,
          name: 'Logo',
          description: 'd',
        ).toString(),
        'XlsxPicture(XlsxImage(png, 87 bytes), XlsxOneCellAnchor('
        'XlsxAnchorPoint(row: 1, column: 1, offsetX: 0, offsetY: 0), '
        'width: null, height: null), name: Logo, description: d)',
      );
    });
  });

  group('WorkbookContext.mediaPartFor', () {
    test('numbers media in first-use order, by the identity of the bytes', () {
      final WorkbookContext context = WorkbookContext(ZipWriter());
      expect(context.mediaPartFor(XlsxImage(png4x2)), (
        'xl/media/image1.png',
        true,
      ));
      expect(context.mediaPartFor(XlsxImage(png4x2)), (
        'xl/media/image1.png',
        false,
      ));
      expect(context.mediaPartFor(XlsxImage(jpeg3x5)), (
        'xl/media/image2.jpeg',
        true,
      ));
      expect(context.mediaPartFor(XlsxImage(Uint8List.fromList(png4x2))), (
        'xl/media/image3.png',
        true,
      ));
      expect(context.mediaPartFor(XlsxImage(jpeg3x5)), (
        'xl/media/image2.jpeg',
        false,
      ));
    });

    test('numbers each workbook on its own', () {
      final WorkbookContext first = WorkbookContext(ZipWriter());
      final WorkbookContext second = WorkbookContext(ZipWriter());
      first.mediaPartFor(XlsxImage(jpeg3x5));
      expect(second.mediaPartFor(XlsxImage(png4x2)), (
        'xl/media/image1.png',
        true,
      ));
      expect(first.mediaPartFor(XlsxImage(png4x2)), (
        'xl/media/image2.png',
        true,
      ));
    });

    test('refuses bytes that are neither PNG nor JPEG, taking no number', () {
      final WorkbookContext context = WorkbookContext(ZipWriter());
      expect(
        () => context.mediaPartFor(XlsxImage(Uint8List.fromList(<int>[1]))),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'image',
          ),
        ),
      );
      expect(context.mediaPartFor(XlsxImage(png4x2)).$1, 'xl/media/image1.png');
    });
  });

  group('the drawing part', () {
    test('uses the DrawingML namespaces, types and content type', () {
      expect(
        Ns.xdr,
        'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing',
      );
      expect(
        Ns.drawingMain,
        'http://schemas.openxmlformats.org/drawingml/2006/main',
      );
      expect(
        RelType.drawing,
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
        'drawing',
      );
      expect(
        RelType.image,
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
        'image',
      );
      expect(
        ContentType.drawing,
        'application/vnd.openxmlformats-officedocument.drawing+xml',
      );
    });

    test('holds a one-cell picture in its own size', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.picture(_png(1, 1)),
      );
      expect(
        parts[_drawing1],
        '$_decl<xdr:wsDr xmlns:xdr="${Ns.xdr}" xmlns:a="${Ns.drawingMain}" '
        'xmlns:r="${Ns.rel}">'
        '<xdr:oneCellAnchor>${_marker('from', 1, 1)}'
        '<xdr:ext cx="38100" cy="19050"/>'
        '${_pic(2, 'Picture 1', 'rId1', _oneCellSpPr(38100, 19050))}'
        '<xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>',
      );
    });

    test('writes a description as descr after the name', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.picture(
          XlsxPicture(
            XlsxImage(png4x2),
            const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
            name: 'Logo',
            description: 'The logo',
          ),
        ),
      );
      expect(
        parts[_drawing1],
        contains('<xdr:cNvPr id="2" name="Logo" descr="The logo"/>'),
      );
    });

    test('escapes name and descr as plain XML, not as ST_Xstring', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.picture(
          XlsxPicture(
            XlsxImage(png4x2),
            const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
            name: 'a & <b> "c"',
            description: '_x0041_\ttab',
          ),
        ),
      );
      expect(
        parts[_drawing1],
        contains(
          '<xdr:cNvPr id="2" name="a &amp; &lt;b&gt; &quot;c&quot;" '
          'descr="_x0041_&#9;tab"/>',
        ),
      );
    });

    test('keeps the aspect of a width given alone', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.picture(
          XlsxPicture(
            XlsxImage(png4x2),
            const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1), width: 8),
          ),
        ),
      );
      expect(_extent(parts), (76200, 38100));
      expect(parts[_drawing1], contains('<a:ext cx="76200" cy="38100"/>'));
    });

    test('keeps the aspect of a height given alone', () {
      expect(
        _extent(
          _parts(
            (XlsxSheetWriter s) => s.picture(
              XlsxPicture(
                XlsxImage(jpeg3x5),
                const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0), height: 10),
              ),
            ),
          ),
        ),
        // 10 × 3 / 5 = 6 pixels wide.
        (57150, 95250),
      );
    });

    test('rounds a size to a whole EMU', () {
      expect(
        _extent(
          _parts(
            (XlsxSheetWriter s) => s.picture(
              XlsxPicture(
                XlsxImage(jpeg3x5),
                const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0), width: 60.5),
              ),
            ),
          ),
        ),
        // 60.5 × 9,525 = 576,262.5; 60.5 × 5 / 3 = 100.8333… pixels,
        // 960,437.5 EMU.
        (576263, 960438),
      );
    });

    test('takes both sizes as given, stretching the image', () {
      expect(
        _extent(
          _parts(
            (XlsxSheetWriter s) => s.picture(
              XlsxPicture(
                XlsxImage(png4x2),
                const XlsxOneCellAnchor(
                  XlsxAnchorPoint(0, 0),
                  width: 8,
                  height: 8,
                ),
              ),
            ),
          ),
        ),
        (76200, 76200),
      );
    });

    test('writes offsets in EMU', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.picture(
          XlsxPicture(
            XlsxImage(png4x2),
            const XlsxOneCellAnchor(
              XlsxAnchorPoint(3, 2, offsetX: 2, offsetY: 0.5),
            ),
          ),
        ),
      );
      expect(
        parts[_drawing1],
        contains(_marker('from', 3, 2, colOff: 19050, rowOff: 4763)),
      );
    });

    test('holds a two-cell picture over a range, moving with its cells', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.picture(
          XlsxPicture(
            XlsxImage(png4x2),
            XlsxTwoCellAnchor.range(
              const XlsxRange(1, 1, 4, 3),
              resize: XlsxPictureResize.move,
            ),
          ),
        ),
      );
      expect(
        parts[_drawing1],
        '$_decl<xdr:wsDr xmlns:xdr="${Ns.xdr}" xmlns:a="${Ns.drawingMain}" '
        'xmlns:r="${Ns.rel}">'
        '<xdr:twoCellAnchor editAs="oneCell">'
        '${_marker('from', 1, 1)}${_marker('to', 5, 4)}'
        '${_pic(2, 'Picture 1', 'rId1', _twoCellSpPr)}'
        '<xdr:clientData/></xdr:twoCellAnchor></xdr:wsDr>',
      );
    });

    test('maps resize to editAs, writing nothing for moveAndSize', () {
      for (final (XlsxPictureResize resize, String start)
          in <(XlsxPictureResize, String)>[
            (XlsxPictureResize.moveAndSize, '<xdr:twoCellAnchor>'),
            (XlsxPictureResize.move, '<xdr:twoCellAnchor editAs="oneCell">'),
            (XlsxPictureResize.none, '<xdr:twoCellAnchor editAs="absolute">'),
          ]) {
        final Map<String, String> parts = _parts(
          (XlsxSheetWriter s) => s.picture(
            XlsxPicture(
              XlsxImage(png4x2),
              XlsxTwoCellAnchor(
                const XlsxAnchorPoint(0, 0, offsetX: 1, offsetY: 2),
                const XlsxAnchorPoint(0, 1, offsetX: 3, offsetY: 4),
                resize: resize,
              ),
            ),
          ),
        );
        expect(
          parts[_drawing1],
          contains(
            '$start${_marker('from', 0, 0, colOff: 9525, rowOff: 19050)}'
            '${_marker('to', 0, 1, colOff: 28575, rowOff: 38100)}<xdr:pic>',
          ),
        );
      }
    });

    test('numbers the pictures 2, 3, … and names them by position', () {
      final String drawing = _parts(
        (XlsxSheetWriter s) => s
          ..picture(_png(0, 0))
          ..picture(
            XlsxPicture(
              XlsxImage(png4x2),
              const XlsxOneCellAnchor(XlsxAnchorPoint(0, 1)),
              name: 'Logo',
            ),
          )
          ..picture(_png(0, 2)),
      )[_drawing1]!;
      expect(
        RegExp(
          '<xdr:cNvPr id="([0-9]+)" name="([^"]*)"',
        ).allMatches(drawing).map((RegExpMatch m) => '${m[1]} ${m[2]}'),
        <String>['2 Picture 1', '3 Logo', '4 Picture 3'],
      );
    });

    test('relates each distinct media once, in first-use order', () {
      final Uint8List copy = Uint8List.fromList(png4x2);
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..picture(_png(0, 0))
          ..picture(
            XlsxPicture(
              XlsxImage(jpeg3x5),
              const XlsxOneCellAnchor(XlsxAnchorPoint(0, 1)),
            ),
          )
          ..picture(_png(0, 2))
          ..picture(_png(0, 3, bytes: copy)),
      );
      expect(
        parts[_drawingRels1],
        '$_decl<Relationships xmlns="${Ns.packageRel}">'
        '<Relationship Id="rId1" Type="${RelType.image}" '
        'Target="../media/image1.png"/>'
        '<Relationship Id="rId2" Type="${RelType.image}" '
        'Target="../media/image2.jpeg"/>'
        '<Relationship Id="rId3" Type="${RelType.image}" '
        'Target="../media/image3.png"/>'
        '</Relationships>',
      );
      expect(
        RegExp(
          'r:embed="(rId[0-9]+)"',
        ).allMatches(parts[_drawing1]!).map((RegExpMatch m) => m[1]),
        <String>['rId1', 'rId2', 'rId1', 'rId3'],
      );
    });
  });

  group('the sheet', () {
    test('refers to its drawing', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..row(<Object?>['x'])
          ..picture(_png(0, 0)),
      );
      expect(parts[_sheet1], endsWith('<drawing r:id="rId1"/></worksheet>'));
    });

    test('with only a picture gets a relationships part for its drawing', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s.picture(_png(0, 0)),
      );
      expect(
        parts[_sheet1],
        endsWith('<sheetData/><drawing r:id="rId1"/></worksheet>'),
      );
      expect(
        parts[_sheetRels1],
        '$_decl<Relationships xmlns="${Ns.packageRel}">'
        '<Relationship Id="rId1" Type="${RelType.drawing}" '
        'Target="../drawings/drawing1.xml"/>'
        '</Relationships>',
      );
    });

    test('numbers links, then the drawing, the VML and the comments', () {
      final Map<String, String> parts = _parts(
        (XlsxSheetWriter s) => s
          ..row(<Object?>[XlsxHyperlink.url('https://example.com')])
          ..note(0, 1, XlsxNote.plain('n'))
          ..picture(_png(0, 2)),
      );
      expect(
        parts[_sheet1],
        endsWith(
          '<hyperlinks><hyperlink ref="A1" r:id="rId1" '
          'display="https://example.com"/></hyperlinks>'
          '<drawing r:id="rId2"/><legacyDrawing r:id="rId3"/></worksheet>',
        ),
      );
      expect(
        parts[_sheetRels1],
        allOf(
          contains(
            '<Relationship Id="rId1" Type="${RelType.hyperlink}" '
            'Target="https://example.com" TargetMode="External"/>',
          ),
          contains(
            '<Relationship Id="rId2" Type="${RelType.drawing}" '
            'Target="../drawings/drawing1.xml"/>'
            '<Relationship Id="rId3" Type="${RelType.vmlDrawing}" '
            'Target="../drawings/vmlDrawing1.vml"/>'
            '<Relationship Id="rId4" Type="${RelType.comments}" '
            'Target="../comments1.xml"/>',
          ),
        ),
      );
    });

    test('without pictures writes no drawing and no media', () {
      final Map<String, Uint8List> parts = readXlsxBytes(
        _book((XlsxSheetWriter s) => s.row(<Object?>['x'])),
      );
      expect(parts.keys.where((String k) => k.contains('drawing')), isEmpty);
      expect(parts.keys.where((String k) => k.contains('media')), isEmpty);
      expect(
        readXlsx(
          _book((XlsxSheetWriter s) => s.row(<Object?>['x'])),
        )['[Content_Types].xml'],
        allOf(isNot(contains('png')), isNot(contains('drawing'))),
      );
    });

    test('writes the worksheet, its rels, the drawing, its rels, the media '
        'and then the notes', () {
      final List<String> names = readXlsxBytes(
        _book(
          (XlsxSheetWriter s) => s
            ..note(0, 0, XlsxNote.plain('n'))
            ..picture(_png(0, 1))
            ..picture(
              XlsxPicture(
                XlsxImage(jpeg3x5),
                const XlsxOneCellAnchor(XlsxAnchorPoint(0, 2)),
              ),
            )
            ..picture(_png(0, 3)),
        ),
      ).keys.toList();
      final int sheet = names.indexOf(_sheet1);
      expect(sheet, isNonNegative);
      expect(names.sublist(sheet, sheet + 8), <String>[
        _sheet1,
        _sheetRels1,
        _drawing1,
        _drawingRels1,
        'xl/media/image1.png',
        'xl/media/image2.jpeg',
        'xl/comments1.xml',
        'xl/drawings/vmlDrawing1.vml',
      ]);
    });

    test('registers each image default once and each drawing part', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('A')
        ..picture(_png(0, 0))
        ..picture(_png(1, 0, bytes: Uint8List.fromList(png4x2)));
      book.addSheet('B').row(<Object?>[1]);
      book
          .addSheet('C')
          .picture(
            XlsxPicture(
              XlsxImage(jpeg3x5),
              const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
            ),
          );
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final String types = readXlsx(result.bytes)['[Content_Types].xml']!;
      for (final String extension in <String>['png', 'jpeg']) {
        expect(
          '<Default Extension="$extension" ContentType="image/$extension"/>'
              .allMatches(types),
          hasLength(1),
        );
      }
      for (final int n in <int>[1, 3]) {
        expect(
          types,
          contains(
            '<Override PartName="/xl/drawings/drawing$n.xml" '
            'ContentType="${ContentType.drawing}"/>',
          ),
        );
      }
      expect(types, isNot(contains('/xl/drawings/drawing2.xml')));
    });

    test('registers no jpeg default for PNGs only', () {
      final String types = readXlsx(
        _book((XlsxSheetWriter s) => s.picture(_png(0, 0))),
      )['[Content_Types].xml']!;
      expect(types, contains('<Default Extension="png" '));
      expect(types, isNot(contains('jpeg')));
    });
  });

  group('media', () {
    test('the same bytes on two sheets are one part both drawings use', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('A').picture(_png(0, 0));
      book.addSheet('B').picture(_png(2, 2));
      book.addSheet('C').picture(_png(0, 0, bytes: Uint8List.fromList(png4x2)));
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, Uint8List> parts = readXlsxBytes(result.bytes);
      expect(
        parts.keys.where((String k) => k.startsWith('xl/media/')),
        <String>['xl/media/image1.png', 'xl/media/image2.png'],
      );
      expect(parts['xl/media/image1.png'], png4x2);
      expect(parts['xl/media/image2.png'], png4x2);
      final Map<String, String> text = readXlsx(result.bytes);
      for (final (int n, String target) in <(int, String)>[
        (1, '../media/image1.png'),
        (2, '../media/image1.png'),
        (3, '../media/image2.png'),
      ]) {
        expect(
          text['xl/drawings/_rels/drawing$n.xml.rels'],
          contains('Target="$target"'),
        );
      }
    });

    test('numbers do not collide across drawings (Quds wrote image111 '
        'twice)', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('S1');
      for (int i = 0; i < 11; i++) {
        first.picture(_png(i, 0, bytes: Uint8List.fromList(png4x2)));
      }
      for (int n = 2; n <= 10; n++) {
        book.addSheet('S$n');
      }
      book
          .addSheet('S11')
          .picture(_png(0, 0, bytes: Uint8List.fromList(png4x2)));
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, Uint8List> parts = readXlsxBytes(result.bytes);
      expect(
        parts.keys.where((String k) => k.startsWith('xl/media/')),
        <String>[for (int k = 1; k <= 12; k++) 'xl/media/image$k.png'],
      );
      expect(
        readXlsx(result.bytes)['xl/drawings/_rels/drawing11.xml.rels'],
        contains('Target="../media/image12.png"'),
      );
    });
  });

  group('XlsxSheetWriter.picture', () {
    test('throws StateError once the sheet is finished', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('First');
      book.addSheet('Second');
      expect(() => first.picture(_png(0, 0)), throwsStateError);
    });

    test('holds its pictures until the sheet finishes', () {
      final XlsxWriter book = XlsxWriter();
      final WorksheetWriter sheet = book.addSheet('S') as WorksheetWriter;
      expect(sheet.holdsTrailerData, isFalse);
      sheet.picture(_png(0, 0));
      expect(sheet.holdsTrailerData, isTrue);
      book.addSheet('T');
      expect(sheet.holdsTrailerData, isFalse);
      expect(readXlsx(book.close().bytes), contains(_drawing1));
    });
  });

  group('XlsxSheetWriter.picture refuses', () {
    Matcher argumentError(String name) => throwsA(
      isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name),
    );

    XlsxPicture oneCell(
      XlsxAnchorPoint from, {
      double? width,
      double? height,
      Uint8List? bytes,
    }) => XlsxPicture(
      XlsxImage(bytes ?? png4x2),
      XlsxOneCellAnchor(from, width: width, height: height),
    );

    XlsxPicture twoCell(XlsxAnchorPoint from, XlsxAnchorPoint to) =>
        XlsxPicture(XlsxImage(png4x2), XlsxTwoCellAnchor(from, to));

    const List<double> notFinite = <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ];

    test('bytes that are neither PNG nor JPEG, naming the picture', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      final Uint8List gif = Uint8List.fromList('GIF89a'.codeUnits);
      expect(
        () => sheet.picture(oneCell(const XlsxAnchorPoint(0, 0), bytes: gif)),
        throwsA(
          isA<ArgumentError>()
              .having((ArgumentError e) => e.name, 'name', 'image')
              .having(
                (ArgumentError e) => e.message,
                'message',
                allOf(contains('Picture 1 on sheet "S"'), contains('PNG')),
              ),
        ),
      );
    });

    test('a negative, NaN or infinite offset', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      for (final double bad in <double>[-1, -0.001, ...notFinite]) {
        expect(
          () => sheet.picture(oneCell(XlsxAnchorPoint(0, 0, offsetX: bad))),
          argumentError('from.offsetX'),
        );
        expect(
          () => sheet.picture(oneCell(XlsxAnchorPoint(0, 0, offsetY: bad))),
          argumentError('from.offsetY'),
        );
        expect(
          () => sheet.picture(
            twoCell(
              const XlsxAnchorPoint(0, 0),
              XlsxAnchorPoint(2, 2, offsetX: bad),
            ),
          ),
          argumentError('to.offsetX'),
        );
        expect(
          () => sheet.picture(
            twoCell(
              const XlsxAnchorPoint(0, 0),
              XlsxAnchorPoint(2, 2, offsetY: bad),
            ),
          ),
          argumentError('to.offsetY'),
        );
      }
    });

    test('a negative, NaN, infinite or zero size', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      for (final double bad in <double>[0, -0.0, -1, ...notFinite]) {
        expect(
          () => sheet.picture(oneCell(const XlsxAnchorPoint(0, 0), width: bad)),
          argumentError('width'),
        );
        expect(
          () =>
              sheet.picture(oneCell(const XlsxAnchorPoint(0, 0), height: bad)),
          argumentError('height'),
        );
      }
    });

    test('a size that rounds to 0 EMU, given or kept by the aspect', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      expect(
        () =>
            sheet.picture(oneCell(const XlsxAnchorPoint(0, 0), width: 0.00005)),
        argumentError('width'),
      );
      // 0.0001 × 9,525 = 0.95 rounds to 1 EMU, but the height, half of it
      // for the 4 × 2 image, rounds to 0.
      expect(
        () =>
            sheet.picture(oneCell(const XlsxAnchorPoint(0, 0), width: 0.0001)),
        argumentError('height'),
      );
    });

    test('a size past 2^31 - 1 EMU or an offset past ST_Coordinate', () {
      // Sizes: 2,147,483,647 EMU, about 225,457.3 pixels, the bound the
      // Open XML SDK checks on cx and cy. Offsets: 27,273,042,316,900 EMU,
      // about 2,863,311,529.4 pixels.
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      const double largestSize = 225457;
      const double largestOffset = 2863311529;
      expect(
        () => sheet.picture(
          oneCell(const XlsxAnchorPoint(0, 0), width: largestSize + 1),
        ),
        argumentError('width'),
      );
      expect(
        () => sheet.picture(
          oneCell(
            const XlsxAnchorPoint(0, 0),
            width: 1,
            height: largestSize + 1,
          ),
        ),
        argumentError('height'),
      );
      // A width that fits whose height, at the image's aspect, does not.
      expect(
        () => sheet.picture(
          oneCell(
            const XlsxAnchorPoint(0, 0),
            width: largestSize,
            bytes: jpeg3x5,
          ),
        ),
        argumentError('height'),
      );
      expect(
        () => sheet.picture(
          oneCell(const XlsxAnchorPoint(0, 0, offsetX: largestOffset + 1)),
        ),
        argumentError('from.offsetX'),
      );
      expect(
        () => sheet.picture(
          twoCell(
            const XlsxAnchorPoint(0, 0),
            const XlsxAnchorPoint(1, 1, offsetY: largestOffset + 1),
          ),
        ),
        argumentError('to.offsetY'),
      );
      sheet
        ..picture(oneCell(const XlsxAnchorPoint(0, 0), width: largestSize))
        ..picture(oneCell(const XlsxAnchorPoint(0, 0, offsetY: largestOffset)));
      final String drawing = readXlsx(book.close().bytes)[_drawing1]!;
      expect(drawing, contains('<xdr:ext cx="2147477925" '));
      expect(drawing, contains('<xdr:rowOff>27273042313725</xdr:rowOff>'));
    });

    test('an anchor point outside the sheet', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      for (final XlsxAnchorPoint outside in <XlsxAnchorPoint>[
        const XlsxAnchorPoint(-1, 0),
        const XlsxAnchorPoint(1048576, 0),
        const XlsxAnchorPoint(0, -1),
        const XlsxAnchorPoint(0, 16384),
      ]) {
        expect(() => sheet.picture(oneCell(outside)), argumentError('from'));
        expect(
          () => sheet.picture(twoCell(outside, const XlsxAnchorPoint(2, 2))),
          argumentError('from'),
        );
        expect(
          () => sheet.picture(twoCell(const XlsxAnchorPoint(0, 0), outside)),
          argumentError('to'),
        );
      }
    });

    test('a two-cell to before its from, or on it', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      const XlsxAnchorPoint from = XlsxAnchorPoint(
        5,
        5,
        offsetX: 4,
        offsetY: 4,
      );
      for (final XlsxAnchorPoint to in <XlsxAnchorPoint>[
        const XlsxAnchorPoint(4, 8),
        const XlsxAnchorPoint(8, 4),
        const XlsxAnchorPoint(5, 8, offsetY: 3),
        const XlsxAnchorPoint(8, 5, offsetX: 3),
        const XlsxAnchorPoint(5, 8, offsetY: 4),
        const XlsxAnchorPoint(8, 5, offsetX: 4),
        from,
      ]) {
        expect(
          () => sheet.picture(twoCell(from, to)),
          argumentError('to'),
          reason: '$to',
        );
      }
    });

    test('a range on the last row or column, whose to falls outside', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      for (final XlsxRange range in <XlsxRange>[
        const XlsxRange(1048575, 0),
        const XlsxRange(0, 16383),
        const XlsxRange(1048570, 16380, 1048575, 16383),
      ]) {
        expect(
          () => sheet.picture(
            XlsxPicture(XlsxImage(png4x2), XlsxTwoCellAnchor.range(range)),
          ),
          argumentError('to'),
        );
      }
      sheet.picture(
        XlsxPicture(
          XlsxImage(png4x2),
          XlsxTwoCellAnchor.range(const XlsxRange(1048574, 16382)),
        ),
      );
      expect(
        readXlsx(book.close().bytes)[_drawing1],
        contains(_marker('to', 1048575, 16383)),
      );
    });

    test('a name or description with a character XML forbids', () {
      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      const XlsxAnchor anchor = XlsxOneCellAnchor(XlsxAnchorPoint(0, 0));
      for (final String bad in <String>['a\u0001', 'b￾', 'c\uD800']) {
        expect(
          () =>
              sheet.picture(XlsxPicture(XlsxImage(png4x2), anchor, name: bad)),
          argumentError('name'),
        );
        expect(
          () => sheet.picture(
            XlsxPicture(XlsxImage(png4x2), anchor, description: bad),
          ),
          argumentError('description'),
        );
      }
    });

    test('and records nothing when it throws: no picture, no media number', () {
      final XlsxWriter book = XlsxWriter();
      final WorksheetWriter sheet = book.addSheet('S') as WorksheetWriter;
      final Uint8List refused = Uint8List.fromList(png4x2);
      expect(
        () => sheet.picture(
          oneCell(const XlsxAnchorPoint(-1, 0), bytes: refused),
        ),
        throwsArgumentError,
      );
      expect(
        () => sheet.picture(
          XlsxPicture(
            XlsxImage(refused),
            const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
            description: '\u0001',
          ),
        ),
        throwsArgumentError,
      );
      expect(sheet.holdsTrailerData, isFalse);
      // A valid picture on the same sheet is its first, with the first
      // shape id and the first media number: the refused ones took none.
      sheet.picture(_png(0, 0, bytes: refused));
      final Map<String, Uint8List> parts = readXlsxBytes(book.close().bytes);
      expect(
        utf8Text(parts[_drawing1]!),
        contains('<xdr:cNvPr id="2" name="Picture 1"/>'),
      );
      expect(
        parts.keys.where((String k) => k.startsWith('xl/media/')),
        <String>['xl/media/image1.png'],
      );
      expect(
        utf8Text(parts['xl/drawings/_rels/drawing1.xml.rels']!),
        contains('Target="../media/image1.png"'),
      );
    });
  });
}

/// [bytes] decoded as UTF-8.
String utf8Text(Uint8List bytes) => utf8.decode(bytes);
