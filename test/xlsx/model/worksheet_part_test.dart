import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/cell_encoder.dart';
import 'package:jet_office/src/xlsx/model/element_node.dart';
import 'package:jet_office/src/xlsx/model/item_group.dart';
import 'package:jet_office/src/xlsx/model/primitives.dart';
import 'package:jet_office/src/xlsx/model/worksheet_part.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/producers.dart';
import '../read/support/zip_builder.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _mc =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';
const String _x14ac =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';
const XlsxReadLimits _limits = XlsxReadLimits();

/// A worksheet part name, as producers name them.
final RegExp _worksheetName = RegExp(r'(^|/)worksheets/[^/]+\.xml$');

/// Repairs the reader makes, applied to the expected part: the producer file
/// repeats a cell on purpose, and the later one wins with
/// `cellDuplicated`, so the saved part has only the later one.
const Map<String, (String, String, String)> _repaired =
    <String, (String, String, String)>{
      'producer erp_export': (
        'worksheets/data.xml',
        '<c r="A3" t="str"><v>FT-2026-0002</v></c>',
        '',
      ),
    };

WorksheetPart _read(
  String xml, {
  List<XlsxWarningCode>? warnings,
  XlsxReadLimits limits = _limits,
}) => WorksheetPart.read(
  XmlPullReader(xml),
  part: 'xl/worksheets/sheet1.xml',
  limits: limits,
  warn: (XlsxWarningCode code, String? cell, {String? detail}) =>
      warnings?.add(code),
);

CellEncoder _encoder() => CellEncoder(
  strings: SharedStrings(),
  styles: StyleRegistry(),
  warnings: WarningCollector(),
);

String _encode(WorksheetPart part) {
  part.bindEncoder(_encoder());
  return utf8.decode(<int>[for (final Uint8List c in part.encode()) ...c]);
}

String _sheet(String body, {String attrs = ''}) =>
    '<worksheet xmlns="$_main"$attrs>$body</worksheet>';

/// Every package of the writer fixtures and the producer files.
Map<String, Uint8List> _allPackages() => <String, Uint8List>{
  for (final Fixture f in allFixtures()) f.name: f.build(),
  for (final ProducerFile p in producerFiles()) 'producer ${p.name}': p.bytes,
};

/// The local names of the root's child elements, in order.
List<String> _childNames(String xml) {
  final XmlPullReader r = XmlPullReader(xml);
  final List<String> out = <String>[];
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.depth == 2) {
      out.add(r.localName);
    }
  }
  return out;
}

void main() {
  group('read then encode', () {
    final Map<String, Uint8List> all = _allPackages();
    var sheets = 0;
    for (final MapEntry<String, Uint8List> e in all.entries) {
      final Map<String, Uint8List> parts = readXlsxBytes(e.value);
      for (final String name in parts.keys.where(_worksheetName.hasMatch)) {
        sheets++;
        test('is semantically equal: ${e.key} $name', () {
          final WorksheetPart part = WorksheetPart.read(
            XmlPullReader(utf8.decode(parts[name]!)),
            part: name,
            limits: _limits,
            warn: (XlsxWarningCode code, String? cell, {String? detail}) {},
          );
          final String out = _encode(part);
          final Uint8List replaced = buildZipOrdered(<(String, List<int>)>[
            for (final MapEntry<String, Uint8List> p in parts.entries)
              (p.key, p.key == name ? utf8.encode(out) : p.value),
          ]);
          Uint8List expected = e.value;
          final (String, String, String)? repair = _repaired[e.key];
          if (repair != null && repair.$1 == name) {
            final String text = utf8.decode(parts[name]!);
            expect(text, contains(repair.$2));
            expected = buildZipOrdered(<(String, List<int>)>[
              for (final MapEntry<String, Uint8List> p in parts.entries)
                (
                  p.key,
                  p.key == name
                      ? utf8.encode(text.replaceFirst(repair.$2, repair.$3))
                      : p.value,
                ),
            ]);
          }
          // dimension and spans are recomputed; the tests below pin them.
          expect(
            comparePackages(expected, replaced, ignoreBookkeeping: true),
            isEmpty,
          );
        });
      }
    }

    test('there are worksheet parts to check', () {
      expect(sheets, greaterThan(20));
    });

    test('a row and cell without r get theirs; t="n" is dropped', () {
      final String out = _encode(
        _read(
          _sheet(
            '<sheetData><row><c t="n"><v>1</v></c><c><v>2</v></c></row>'
            '</sheetData>',
          ),
        ),
      );
      expect(
        out,
        contains(
          '<row r="1" spans="1:2"><c r="A1"><v>1</v></c>'
          '<c r="B1"><v>2</v></c></row>',
        ),
      );
    });

    test('a sheet with correct dimension and spans is unchanged', () {
      final String xml = _sheet(
        '<dimension ref="B2:C3"/><sheetData>'
        '<row r="2" spans="2:3"><c r="B2"><v>1</v></c><c r="C2"><v>2</v></c>'
        '</row><row r="3" spans="3:3"><c r="C3"><v>3</v></c></row>'
        '</sheetData>',
      );
      expect(compareXml('s', xml, _encode(_read(xml))), isEmpty);
    });
  });

  group('children', () {
    test('opaque children keep their position', () {
      const String r =
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
      final String xml = _sheet(
        '<sheetPr><tabColor rgb="FFFF0000"/></sheetPr>'
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
        '<sheetData><row r="1" spans="1:1"><c r="A1"><v>1</v></c></row>'
        '</sheetData><hyperlinks><hyperlink ref="A1" r:id="rId1"/></hyperlinks>'
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>'
        '<legacyDrawing r:id="rId2"/>'
        '<extLst><ext uri="{X}"><foo/></ext></extLst>',
        attrs: ' xmlns:r="$r"',
      );
      final String out = _encode(_read(xml));
      expect(_childNames(out), <String>[
        'sheetPr',
        'sheetViews',
        'sheetData',
        'hyperlinks',
        'pageMargins',
        'legacyDrawing',
        'extLst',
      ]);
      expect(compareXml('s', xml, out), isEmpty);
    });

    test('a row extLst survives, after the cells', () {
      final String xml = _sheet(
        '<dimension ref="A1"/><sheetData>'
        '<row r="1" spans="1:1"><c r="A1"><v>1</v></c>'
        '<extLst><ext uri="{X}"><y/></ext></extLst></row>'
        '<row r="2"><extLst/></row></sheetData>',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('<v>1</v></c><extLst><ext uri="{X}"><y/></ext>'));
      expect(compareXml('s', xml, out), isEmpty);
    });

    test('a foreign element inside sheetData survives at its end', () {
      final String xml = _sheet(
        '<dimension ref="A1"/><sheetData><foo a="1"/>'
        '<row r="1" spans="1:1"><c r="A1"><v>1</v></c></row>'
        '</sheetData>',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('</row><foo a="1"/></sheetData>'));
    });

    test('mc:Ignorable and x14ac:dyDescent survive', () {
      final String xml = _sheet(
        '<dimension ref="A1"/>'
        '<sheetFormatPr defaultRowHeight="15" x14ac:dyDescent="0.25"/>'
        '<sheetData><row r="1" spans="1:1" x14ac:dyDescent="0.25">'
        '<c r="A1"><v>1</v></c></row></sheetData>',
        attrs: ' xmlns:mc="$_mc" xmlns:x14ac="$_x14ac" mc:Ignorable="x14ac"',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('mc:Ignorable="x14ac"'));
      expect(out, contains('xmlns:x14ac="$_x14ac"'));
      expect(out, contains('<row r="1" spans="1:1" x14ac:dyDescent="0.25">'));
      expect(compareXml('s', xml, out), isEmpty);
    });

    test('a strict root is refused', () {
      expect(
        () => _read(
          '<worksheet xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main">'
          '<sheetData/></worksheet>',
        ),
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.unsupportedFormat,
          ),
        ),
      );
    });

    test('a root that is not a worksheet is written back unchanged', () {
      const String xml =
          '<?xml version="1.0"?>\n'
          '<chartsheet xmlns="$_main"><sheetViews/></chartsheet>';
      final WorksheetPart part = _read(xml);
      expect(part.cells.cellCount, 0);
      expect(_encode(part), xml);
    });

    test('cells put in a part that is not a worksheet fail the save', () {
      final WorksheetPart part = _read('<chartsheet xmlns="$_main"/>');
      part.cells.put(0, 0, const RawCell(kind: RawCellKind.number, value: '1'));
      part.bindEncoder(_encoder());
      expect(part.encode, throwsStateError);
    });

    test('encode without an encoder throws', () {
      expect(WorksheetPart.empty().encode, throwsStateError);
    });

    test('a prefixed worksheet writes its cells in the main namespace', () {
      const String xml =
          '<x:worksheet xmlns:x="$_main"><x:sheetData><x:row r="1" spans="1:1">'
          '<x:c r="A1"><x:v>5</x:v></x:c></x:row></x:sheetData>'
          '</x:worksheet>';
      final String out = _encode(_read(xml));
      expect(compareXml('s', xml, out), isEmpty);
    });

    test('a kept element in no namespace keeps none in a prefixed sheet', () {
      // The model declares the main namespace as the default on
      // <sheetData>, so an unqualified kept element must undeclare it.
      const String xml =
          '<x:worksheet xmlns:x="$_main"><x:sheetData><x:row r="1" spans="1:1">'
          '<x:c r="A1"><x:v>5</x:v><foo a="1"/></x:c><bar/></x:row>'
          '</x:sheetData></x:worksheet>';
      final String out = _encode(_read(xml));
      expect(out, contains('<foo xmlns="" a="1"/>'));
      expect(out, contains('<bar xmlns=""/>'));
      expect(compareXml('s', xml, out), isEmpty);
    });
  });

  group('dimension and spans', () {
    test('dimension and spans are recomputed', () {
      final String xml = _sheet(
        '<dimension ref="A1:Z9"/><sheetData>'
        '<row r="2" spans="1:26"><c r="B2"><v>1</v></c><c r="D2"><v>2</v></c>'
        '</row><row r="4" spans="1:2"><c r="C4"><v>3</v></c></row>'
        '</sheetData>',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('<dimension ref="B2:D4"/>'));
      expect(out, contains('<row r="2" spans="2:4">'));
      expect(out, contains('<row r="4" spans="3:3">'));
    });

    test('a single cell gives a single-cell dimension', () {
      final String xml = _sheet(
        '<dimension ref="A1:B2"/><sheetData>'
        '<row r="3"><c r="C3"><v>1</v></c></row></sheetData>',
      );
      expect(_encode(_read(xml)), contains('<dimension ref="C3"/>'));
    });

    test('a row without cells keeps its attributes and gets no spans', () {
      final String xml = _sheet(
        '<dimension ref="A1"/><sheetData>'
        '<row r="1" spans="1:3"><c r="A1"><v>1</v></c></row>'
        '<row r="2" spans="1:3" hidden="1" ht="20" customHeight="1"/>'
        '</sheetData>',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('<row r="2" hidden="1" ht="20" customHeight="1"/>'));
      expect('hidden='.allMatches(out).length, 1);
    });

    test('rows out of order are written in order', () {
      final String xml = _sheet(
        '<sheetData><row r="3"><c r="A3"><v>3</v></c></row>'
        '<row r="1"><c r="A1"><v>1</v></c></row></sheetData>',
      );
      final List<XlsxWarningCode> warnings = <XlsxWarningCode>[];
      final String out = _encode(_read(xml, warnings: warnings));
      expect(warnings, contains(XlsxWarningCode.rowOutOfOrder));
      expect(out.indexOf('<row r="1"'), lessThan(out.indexOf('<row r="3"')));
    });

    test('a changed cell moves the dimension', () {
      final WorksheetPart part = _read(
        _sheet(
          '<dimension ref="A1"/><sheetData>'
          '<row r="1"><c r="A1"><v>1</v></c></row></sheetData>',
        ),
      );
      part.cells.put(9, 4, const RawCell(kind: RawCellKind.number, value: '2'));
      final String out = _encode(part);
      expect(out, contains('<dimension ref="A1:E10"/>'));
      expect(out, contains('<row r="10" spans="5:5">'));
    });
  });

  group('empty and missing parts', () {
    test('an empty part has sheetData and dimension A1', () {
      final String out = _encode(WorksheetPart.empty());
      expect(_childNames(out), <String>['dimension', 'sheetData']);
      expect(out, contains('<dimension ref="A1"/>'));
      expect(out, startsWith('<?xml'));
    });

    test('an emptied part writes dimension A1', () {
      final WorksheetPart part = _read(
        _sheet(
          '<dimension ref="A1:B2"/><sheetData>'
          '<row r="2"><c r="B2"><v>1</v></c></row></sheetData>',
        ),
      );
      part.cells.remove(1, 1);
      final String out = _encode(part);
      expect(out, contains('<dimension ref="A1"/>'));
      expect(out, isNot(contains('<row')));
    });

    test('a missing sheetData is inserted in schema position', () {
      final String xml = _sheet(
        '<sheetPr/><dimension ref="A1"/><sheetViews/><cols>'
        '<col min="1" max="1" width="9"/></cols>'
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>',
      );
      final String out = _encode(_read(xml));
      expect(_childNames(out), <String>[
        'sheetPr',
        'dimension',
        'sheetViews',
        'cols',
        'sheetData',
        'pageMargins',
      ]);
    });

    test('an empty root gets sheetData', () {
      final String out = _encode(_read('<worksheet xmlns="$_main"/>'));
      expect(_childNames(out), <String>['sheetData']);
    });

    test('the child order runs from sheetPr to extLst', () {
      expect(worksheetChildOrder.first, 'sheetPr');
      expect(worksheetChildOrder.last, 'extLst');
      expect(
        worksheetChildOrder.indexOf('dimension'),
        lessThan(worksheetChildOrder.indexOf('sheetData')),
      );
    });
  });

  test('a part is a PartContent', () {
    expect(WorksheetPart.empty(), isA<PartContent>());
  });

  test('changeSheetFormat keeps the element when nothing changes', () {
    final WorksheetPart part = _read(
      '<worksheet xmlns="$_main"><sheetFormatPr defaultRowHeight="15"/>'
      '<sheetData/></worksheet>',
    );
    final Object? before = part.layoutElement('sheetFormatPr');
    expect(before, isNotNull);
    part.changeSheetFormat(<String, String?>{
      'defaultRowHeight': '15',
      'customHeight': null,
    });
    expect(part.layoutElement('sheetFormatPr'), same(before));
    part.changeSheetFormat(<String, String?>{'defaultRowHeight': '16'});
    expect(part.layoutElement('sheetFormatPr'), isNot(same(before)));
  });

  group('feature slots', () {
    /// The single elements read as [XmlNode]s, with a body for each.
    const Map<String, String> singles = <String, String>{
      'sheetProtection': '<sheetProtection sheet="1" objects="0"/>',
      'autoFilter':
          '<autoFilter ref="A1:B2"><filterColumn colId="0"/></autoFilter>',
      'printOptions': '<printOptions gridLines="1"/>',
      'pageMargins': '<pageMargins left="1" right="1"/>',
      'pageSetup': '<pageSetup orientation="landscape"/>',
      'headerFooter':
          '<headerFooter><oddHeader>&amp;CTop</oddHeader></headerFooter>',
      'extLst': '<extLst><ext uri="{A}"><o:x xmlns:o="urn:o"/></ext></extLst>',
    };

    /// A group holding one `<dataValidation>`, as the writer renders it.
    ItemGroup<String> validations(String prefix) {
      final OpaqueXml item = renderElements((XmlWriter w) {
        w
          ..start('dataValidation')
          ..attribute('sqref', 'A1')
          ..end();
      }).single;
      return ItemGroup<String>(
        '${prefix}dataValidations',
        'dataValidations',
        const <String, String>{},
        const <KeptAttribute>[],
        <GroupItem<String>>[GroupItem<String>('A1', item)],
        edited: true,
      );
    }

    for (final MapEntry<String, String> e in singles.entries) {
      test('the first ${e.key} is typed, a second stays as written', () {
        final String body = '<sheetData/>${e.value}${e.value}';
        final WorksheetPart part = _read(_sheet(body));
        final Object? element = part.layoutElement(e.key);
        expect(element, isA<XmlNode>());
        expect((element! as XmlNode).localName, e.key);
        expect(_encode(part), contains('<sheetData/>${e.value}${e.value}'));
      });
    }

    test('a foreign element of a slot name stays opaque', () {
      final WorksheetPart part = _read(
        _sheet('<sheetData/><o:pageMargins xmlns:o="urn:o"/>'),
      );
      expect(part.layoutElement('pageMargins'), isNull);
    });

    test('extLst types its ext and keeps what is inside', () {
      final WorksheetPart part = _read(
        _sheet(
          '<sheetData/><extLst><ext uri="{A}" xmlns:x14="urn:x14">'
          '<x14:a/></ext><o:b xmlns:o="urn:o"/></extLst>',
        ),
      );
      final XmlNode node = part.layoutElement('extLst')! as XmlNode;
      expect(node.child('ext')!.attribute('uri'), '{A}');
      expect(node.child('ext')!.children.single, isA<OpaqueXml>());
      expect(node.children.last, isA<OpaqueXml>());
      expect(
        _encode(part),
        contains(
          '<extLst><ext xmlns:x14="urn:x14" uri="{A}"><x14:a/></ext>'
          '<o:b xmlns:o="urn:o"/></extLst>',
        ),
      );
    });

    test('headerFooter keeps its children opaque', () {
      final WorksheetPart part = _read(_sheet(singles['headerFooter']!));
      final XmlNode node = part.layoutElement('headerFooter')! as XmlNode;
      expect(node.children.single, isA<OpaqueXml>());
    });

    test('validations, links and conditional formats stay opaque', () {
      const String body =
          '<sheetData/>'
          '<conditionalFormatting sqref="A1"/>'
          '<dataValidations count="9"/>'
          '<hyperlinks/>';
      final WorksheetPart part = _read(_sheet(body));
      for (final String slot in <String>[
        'conditionalFormatting',
        'dataValidations',
        'hyperlinks',
      ]) {
        expect(part.layoutElement(slot), isNull, reason: slot);
      }
      expect(_encode(part), contains(body));
    });

    group('a declaration with a forbidden character saves', () {
      /// The namespace of the element named [name] in [xml].
      String namespaceOf(String xml, String name) {
        final XmlPullReader r = XmlPullReader(xml);
        while (r.next()) {
          if (r.eventType == XmlEventType.startElement && r.localName == name) {
            return r.namespaceUri;
          }
        }
        fail('No $name in $xml');
      }

      test('on pageMargins, with a child that uses the prefix', () {
        final WorksheetPart part = _read(
          _sheet(
            '<sheetData/><pageMargins xmlns:o="urn:&#1;o" o:a="1" left="1">'
            '<o:x/></pageMargins>',
          ),
        );
        expect(part.layoutElement('pageMargins'), isA<XmlNode>());
        final String out = _encode(part);
        expect(out, contains('<pageMargins xmlns:o="urn:o" o:a="1" left="1">'));
        expect(out, contains('<o:x/></pageMargins>'));
        expect(namespaceOf(out, 'x'), 'urn:o');
      });

      test('on an ext, with a child that uses the prefix', () {
        final WorksheetPart part = _read(
          _sheet(
            '<sheetData/><extLst><ext xmlns:o="urn:&#1;o" uri="{A}"><o:x/>'
            '</ext></extLst>',
          ),
        );
        final String out = _encode(part);
        expect(out, contains('<ext xmlns:o="urn:o" uri="{A}"><o:x/></ext>'));
        expect(namespaceOf(out, 'x'), 'urn:o');
      });
    });

    test('an unknown slot throws', () {
      expect(
        () => WorksheetPart.empty().layoutElement('sheetData'),
        throwsArgumentError,
      );
    });

    test('slots swap and undo', () {
      final WorksheetPart part = _read(
        _sheet('<sheetData/><printOptions/><pageMargins left="1"/><drawing/>'),
      );
      final String before = _encode(part);
      final Object margins = part.layoutElement('pageMargins')!;
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        editLayout(
          log,
          part,
          'pageMargins',
          () => part.swapLayout('pageMargins', margins, null),
        );
      });
      expect(set.changes.single, isA<SetLayoutChange>());
      expect(part.layoutElement('pageMargins'), isNull);
      expect(_childNames(_encode(part)), <String>[
        'sheetData',
        'printOptions',
        'drawing',
      ]);
      log.revertSet(set);
      expect(part.layoutElement('pageMargins'), same(margins));
      expect(_encode(part), before);
      log.reapplySet(set);
      expect(part.layoutElement('pageMargins'), isNull);
    });

    test('a failed edit puts a group back', () {
      final WorksheetPart part = _read(_sheet('<sheetData/><drawing/>'));
      final ChangeLog log = ChangeLog();
      expect(
        () => log.transaction(() {
          editLayout(log, part, 'dataValidations', () {
            part.swapLayout('dataValidations', null, validations(''));
            throw StateError('no');
          });
        }),
        throwsStateError,
      );
      expect(part.layoutElement('dataValidations'), isNull);
      expect(_childNames(_encode(part)), <String>['sheetData', 'drawing']);
    });

    test('a new element goes in schema position, past a group', () {
      final WorksheetPart part = _read(
        _sheet('<sheetData/><mergeCells/><drawing/>'),
      );
      part.swapLayout('pageSetup', null, XmlNode.made('', 'pageSetup'));
      part.swapLayout('dataValidations', null, validations(''));
      part.swapLayout('pageMargins', null, XmlNode.made('', 'pageMargins'));
      part.swapLayout(
        'sheetProtection',
        null,
        XmlNode.made('', 'sheetProtection'),
      );
      expect(_childNames(_encode(part)), <String>[
        'sheetData',
        'sheetProtection',
        'mergeCells',
        'dataValidations',
        'pageMargins',
        'pageSetup',
        'drawing',
      ]);
      // A group is found by a later element's position, and by its slot.
      expect(part.layoutElement('dataValidations'), isA<ItemGroup<String>>());
      part.swapLayout(
        'conditionalFormatting',
        null,
        renderElements((XmlWriter w) {
          w
            ..start('conditionalFormatting')
            ..attribute('sqref', 'A1')
            ..end();
        }).single,
      );
      expect(
        _childNames(_encode(part)).indexOf('conditionalFormatting'),
        lessThan(_childNames(_encode(part)).indexOf('dataValidations')),
      );
    });

    test('an edited dataValidations counts, an edited hyperlinks does not', () {
      final OpaqueXml link = renderElements((XmlWriter w) {
        w
          ..start('hyperlink')
          ..attribute('ref', 'A1')
          ..attribute('r:id', 'rId1')
          ..end();
      }).single;
      final WorksheetPart part = WorksheetPart.empty();
      part.swapLayout('dataValidations', null, validations(''));
      part.swapLayout(
        'hyperlinks',
        null,
        ItemGroup<String>(
          'hyperlinks',
          'hyperlinks',
          const <String, String>{},
          const <KeptAttribute>[],
          <GroupItem<String>>[GroupItem<String>('A1', link)],
          edited: true,
        ),
      );
      final String out = _encode(part);
      expect(
        out,
        contains(
          '<dataValidations count="1"><dataValidation sqref="A1"/>'
          '</dataValidations><hyperlinks><hyperlink ref="A1" r:id="rId1"/>'
          '</hyperlinks>',
        ),
      );
    });

    group('a rendered element keeps its namespace', () {
      /// The namespace of the first element named [name] in [xml].
      String namespaceOf(String xml, String name) {
        final XmlPullReader r = XmlPullReader(xml);
        while (r.next()) {
          if (r.eventType == XmlEventType.startElement && r.localName == name) {
            return r.namespaceUri;
          }
        }
        fail('No $name in $xml');
      }

      test('under a root that declares only a prefix', () {
        final WorksheetPart part = _read(
          '<x:worksheet xmlns:x="$_main"><x:sheetData/></x:worksheet>',
        );
        part.swapLayout('dataValidations', null, validations('x:'));
        part.swapLayout(
          'hyperlinks',
          null,
          ItemGroup<String>(
            'x:hyperlinks',
            'hyperlinks',
            const <String, String>{},
            const <KeptAttribute>[],
            <GroupItem<String>>[
              GroupItem<String>(
                'A1',
                renderElements((XmlWriter w) {
                  w
                    ..start('hyperlink')
                    ..attribute('r:id', 'rId1')
                    ..end();
                }).single,
              ),
            ],
          ),
        );
        final String out = _encode(part);
        expect(namespaceOf(out, 'dataValidations'), _main);
        expect(namespaceOf(out, 'dataValidation'), _main);
        final XmlPullReader r = XmlPullReader(out);
        while (r.next()) {
          if (r.eventType == XmlEventType.startElement &&
              r.localName == 'hyperlink') {
            expect(r.namespaceUri, _main);
            expect(r.getAttribute('id', namespaceUri: Ns.rel), 'rId1');
            return;
          }
        }
        fail('No hyperlink in $out');
      });

      test('a rendered element alone in a prefixed part', () {
        final WorksheetPart part = _read(
          '<x:worksheet xmlns:x="$_main"><x:sheetData/></x:worksheet>',
        );
        part.swapLayout(
          'dataValidations',
          null,
          renderElements((XmlWriter w) {
            w
              ..start('dataValidations')
              ..attribute('count', '0')
              ..end();
          }).single,
        );
        expect(namespaceOf(_encode(part), 'dataValidations'), _main);
      });

      test('under a root with that default, no xmlns is written', () {
        final WorksheetPart part = _read(_sheet('<sheetData/>'));
        part.swapLayout(
          'dataValidations',
          null,
          renderElements((XmlWriter w) {
            w
              ..start('dataValidations')
              ..attribute('count', '0')
              ..end();
          }).single,
        );
        part.swapLayout(
          'hyperlinks',
          null,
          ItemGroup<String>(
            'hyperlinks',
            'hyperlinks',
            const <String, String>{},
            const <KeptAttribute>[],
            <GroupItem<String>>[
              GroupItem<String>(
                'A1',
                renderElements((XmlWriter w) {
                  w
                    ..start('hyperlink')
                    ..attribute('ref', 'A1')
                    ..end();
                }).single,
              ),
            ],
          ),
        );
        final String out = _encode(part);
        expect(out, contains('<dataValidations count="0"/>'));
        expect(out, contains('<hyperlink ref="A1"/>'));
        expect('xmlns='.allMatches(out).length, 1);
      });
    });
  });
}
