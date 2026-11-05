import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/model/defined_names.dart';
import 'package:jet_office/src/xlsx/model/element_node.dart';
import 'package:jet_office/src/xlsx/model/item_group.dart';
import 'package:jet_office/src/xlsx/model/workbook_part.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/sheet_view.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../read/support/producers.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const XlsxReadLimits _limits = XlsxReadLimits();

String? _workbookXml(Uint8List package) {
  final Archive zip = ZipDecoder().decodeBytes(package);
  for (final ArchiveFile f in zip.files) {
    if (f.name.endsWith('workbook.xml') && !f.name.contains('_rels')) {
      return utf8.decode(f.content as List<int>);
    }
  }
  return null;
}

Map<String, String> _allWorkbooks() {
  final Map<String, String> out = <String, String>{};
  for (final Fixture f in allFixtures()) {
    final String? xml = _workbookXml(f.build());
    if (xml != null) out[f.name] = xml;
  }
  for (final ProducerFile p in producerFiles()) {
    final String? xml = _workbookXml(p.bytes);
    if (xml != null) out['producer ${p.name}'] = xml;
  }
  return out;
}

WorkbookPart _read(String xml, {XlsxReadLimits limits = _limits}) =>
    WorkbookPart.read(XmlPullReader(xml), limits);

String _encode(PartContent part) =>
    utf8.decode(<int>[for (final Uint8List c in part.encode()) ...c]);

String _book(String body, {String attrs = ''}) =>
    '<workbook xmlns="$_main" xmlns:r="$_rel"$attrs>$body</workbook>';

void main() {
  group('read then encode', () {
    final Map<String, String> all = _allWorkbooks();

    test('there are workbook parts to check', () {
      expect(all.length, greaterThan(10));
    });

    for (final MapEntry<String, String> e in all.entries) {
      test('is semantically equal: ${e.key}', () {
        final String out = _encode(_read(e.value));
        expect(compareXml('xl/workbook.xml', e.value, out), isEmpty);
      });
    }
  });

  group('sheets', () {
    test('are typed with name, id, state and relationship', () {
      final WorkbookPart p = _read(
        _book(
          '<sheets><sheet name="A" sheetId="1" r:id="rId1"/>'
          '<sheet name="B" sheetId="4" state="veryHidden" r:id="rId2" '
          'foo="x"/></sheets>',
        ),
      );
      expect(p.sheets.map((SheetEntry s) => s.name), <String>['A', 'B']);
      expect(p.sheets[1].sheetId, 4);
      expect(p.sheets[1].visibility, XlsxSheetVisibility.veryHidden);
      expect(p.sheets[1].relationshipId, 'rId2');
      expect(p.sheets[1].attributes.single.qualifiedName, 'foo');
      expect(_encode(p), contains('foo="x"'));
      expect(_encode(p), contains('state="veryHidden"'));
    });

    test('an _x0041_ name round-trips', () {
      final WorkbookPart p = _read(
        _book(
          '<sheets><sheet name="_x005F_x0041_" sheetId="1" r:id="rId1"/>'
          '</sheets>',
        ),
      );
      expect(p.sheets.single.name, '_x0041_');
      expect(_encode(p), contains('name="_x005F_x0041_"'));
      expect(_encode(_read(_encode(p))), _encode(p));
    });

    test('addSheet takes the next free sheetId', () {
      final WorkbookPart p = _read(
        _book(
          '<sheets><sheet name="A" sheetId="1" r:id="rId1"/>'
          '<sheet name="B" sheetId="5" r:id="rId2"/></sheets>',
        ),
      );
      final SheetEntry s = p.addSheet('C', 'rId9');
      expect(s.sheetId, 6);
      expect(p.sheets.length, 3);
      final WorkbookPart back = _read(_encode(p));
      expect(back.sheets[2].name, 'C');
      expect(back.sheets[2].sheetId, 6);
      expect(back.sheets[2].relationshipId, 'rId9');
    });

    group('a sheetId that is not an unsigned int', () {
      for (final (String label, String attr, int? id)
          in <(String, String, int?)>[
            ('missing', '', null),
            ('abc', ' sheetId="abc"', null),
            ('-1', ' sheetId="-1"', null),
            ('0', ' sheetId="0"', 0),
          ]) {
        test('$label round-trips unchanged', () {
          final String xml = _book(
            '<sheets><sheet name="A"$attr r:id="rId1"/></sheets>',
          );
          final WorkbookPart p = _read(xml);
          expect(p.sheets.single.sheetId, id);
          final String out = _encode(p);
          expect(compareXml('xl/workbook.xml', xml, out), isEmpty);
          if (attr.isEmpty) {
            expect(out, isNot(contains('sheetId')));
          } else {
            expect(out, contains(attr.trim()));
          }
        });
      }

      test('addSheet next to them picks max parsable + 1', () {
        final WorkbookPart p = _read(
          _book(
            '<sheets><sheet name="A" sheetId="abc" r:id="rId1"/>'
            '<sheet name="B" sheetId="7" r:id="rId2"/>'
            '<sheet name="C" sheetId="-1" r:id="rId3"/></sheets>',
          ),
        );
        expect(p.addSheet('D', 'rId4').sheetId, 8);
        final String out = _encode(p);
        expect(out, contains('sheetId="abc"'));
        expect(out, contains('sheetId="-1"'));
      });

      test('addSheet with none parsable gives 1', () {
        final WorkbookPart p = _read(
          _book('<sheets><sheet name="A" r:id="rId1"/></sheets>'),
        );
        expect(p.addSheet('B', 'rId2').sheetId, 1);
      });
    });

    test('addSheet creates sheets in schema position', () {
      final WorkbookPart p = _read(
        _book(
          '<bookViews><workbookView/></bookViews>'
          '<definedNames><definedName name="n">A1</definedName>'
          '</definedNames>',
        ),
      );
      expect(p.addSheet('X', 'rId1').sheetId, 1);
      final String out = _encode(p);
      expect(out.indexOf('<sheets'), greaterThan(out.indexOf('</bookViews>')));
      expect(out.indexOf('<sheets'), lessThan(out.indexOf('<definedNames')));
    });

    test('an r prefix bound to another namespace is redeclared', () {
      final WorkbookPart p = _read(
        '<workbook xmlns="$_main" xmlns:r="urn:other">'
        '<sheets><sheet name="A" sheetId="1"/></sheets></workbook>',
      );
      p.addSheet('B', 'rId2');
      final String out = _encode(p);
      expect(out, contains('xmlns:r="$_rel"'));
      expect(_read(out).sheets[1].relationshipId, 'rId2');
    });

    test('a prefixed producer keeps its prefixes', () {
      final WorkbookPart p = _read(
        '<x:workbook xmlns:x="$_main" xmlns:q="$_rel">'
        '<x:sheets><x:sheet name="A" sheetId="1" q:id="rId1"/></x:sheets>'
        '</x:workbook>',
      );
      p.addSheet('B', 'rId2');
      final WorkbookPart back = _read(_encode(p));
      expect(back.sheets.map((SheetEntry s) => s.relationshipId), <String>[
        'rId1',
        'rId2',
      ]);
    });

    test('more sheets than the limit is a limitExceeded', () {
      expect(
        () => _read(
          _book(
            '<sheets><sheet name="A" sheetId="1"/>'
            '<sheet name="B" sheetId="2"/></sheets>',
          ),
          limits: const XlsxReadLimits(maxSheets: 1),
        ),
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.limitExceeded,
          ),
        ),
      );
    });
  });

  group('date1904', () {
    test('is read from workbookPr', () {
      expect(_read(_book('<workbookPr date1904="1"/>')).date1904, isTrue);
      expect(_read(_book('<workbookPr date1904="true"/>')).date1904, isTrue);
      expect(_read(_book('<workbookPr date1904="0"/>')).date1904, isFalse);
      expect(_read(_book('<workbookPr/>')).date1904, isFalse);
      expect(_read(_book('')).date1904, isFalse);
    });

    test('workbookPr is kept as written', () {
      final String out = _encode(
        _read(_book('<workbookPr date1904="1" defaultThemeVersion="1"/>')),
      );
      expect(
        out,
        contains('<workbookPr date1904="1" defaultThemeVersion="1"/>'),
      );
    });
  });

  group('requestFullCalculation', () {
    test('adds calcPr after definedNames and before extLst', () {
      final WorkbookPart p = _read(
        _book(
          '<sheets><sheet name="A" sheetId="1" r:id="rId1"/></sheets>'
          '<definedNames><definedName name="n">A1</definedName>'
          '</definedNames><extLst/>',
        ),
      );
      p.requestFullCalculation();
      final String out = _encode(p);
      expect(out, contains('<calcPr fullCalcOnLoad="1"/>'));
      expect(
        out.indexOf('<calcPr'),
        greaterThan(out.indexOf('</definedNames>')),
      );
      expect(out.indexOf('<calcPr'), lessThan(out.indexOf('<extLst')));
    });

    test('keeps calcId', () {
      final WorkbookPart p = _read(_book('<calcPr calcId="191029"/>'));
      p.requestFullCalculation();
      final String out = _encode(p);
      expect(out, contains('calcId="191029"'));
      expect(out, contains('fullCalcOnLoad="1"'));
      expect('<calcPr'.allMatches(out).length, 1);
    });

    test('replaces an existing fullCalcOnLoad', () {
      final WorkbookPart p = _read(_book('<calcPr fullCalcOnLoad="0"/>'));
      p.requestFullCalculation();
      final String out = _encode(p);
      expect(out, contains('fullCalcOnLoad="1"'));
      expect('fullCalcOnLoad'.allMatches(out).length, 1);
    });
  });

  group('untyped parts', () {
    test('a foreign root is written back unchanged', () {
      const String xml = '<other xmlns="urn:x"><sheets/></other>';
      final WorkbookPart p = _read(xml);
      expect(p.sheets, isEmpty);
      expect(p.date1904, isFalse);
      expect(_encode(p), xml);
      expect(() => p.addSheet('A', 'rId1'), throwsStateError);
      expect(p.requestFullCalculation, throwsStateError);
    });

    test('an empty text is untyped', () {
      expect(_encode(_read('')), '');
    });

    test('a Strict root is unsupported', () {
      expect(
        () => _read(
          '<workbook xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main"/>',
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
  });

  test('workbookChildOrder is the CT_Workbook sequence', () {
    expect(workbookChildOrder.first, 'fileVersion');
    expect(
      workbookChildOrder.indexOf('calcPr'),
      greaterThan(workbookChildOrder.indexOf('definedNames')),
    );
    expect(workbookChildOrder.last, 'extLst');
    expect(workbookChildOrder.length, 19);
  });

  group('element slots', () {
    /// A `<definedNames>` group holding nothing.
    ItemGroup<String> names() => const ItemGroup<String>(
      'definedNames',
      'definedNames',
      <String, String>{},
      <KeptAttribute>[],
      <GroupItem<String>>[],
    );

    test('the first workbookProtection is typed, a second stays', () {
      final WorkbookPart part = _read(
        _book(
          '<workbookProtection lockStructure="1"/><workbookProtection/>'
          '<sheets/>',
        ),
      );
      final Object? element = part.element('workbookProtection');
      expect(element, isA<XmlNode>());
      expect((element! as XmlNode).attribute('lockStructure'), '1');
      expect(
        _encode(part),
        contains(
          '<workbookProtection lockStructure="1"/><workbookProtection/>',
        ),
      );
    });

    test('bookViews is not taken for the protection before it', () {
      final WorkbookPart part = _read(
        _book(
          '<workbookProtection/><bookViews><workbookView activeTab="2"/>'
          '</bookViews><sheets/>',
        ),
      );
      expect(part.activeTab, 2);
      expect(part.bookViews!.localName, 'bookViews');
      part.setActiveTabIndex(1);
      expect(part.activeTab, 1);
      expect(part.element('workbookProtection'), isA<XmlNode>());
    });

    test('definedNames is typed, and a repeated one stays', () {
      const String body =
          '<sheets/><definedNames><definedName name="a">1'
          '</definedName></definedNames><definedNames><definedName '
          'name="b">2</definedName></definedNames>';
      final WorkbookPart part = _read(_book(body));
      expect(part.element('definedNames'), isA<ItemGroup<NameEntry>>());
      expect(part.names.map((NameEntry e) => e.name), <String>['a']);
      expect(_encode(part), contains(body));
    });

    test('addName and removeName leave nameEdits alone', () {
      final WorkbookPart part = _read(_book('<sheets/>'));
      final NameEntry entry = NameEntry(
        name: '_xlnm.Print_Area',
        formula: 'S!\$A\$1',
        localSheetId: 0,
      );
      expect(entry.builtIn, isTrue);
      part.addName(entry);
      expect(part.names, <NameEntry>[entry]);
      expect(_encode(part), contains('<definedName name="_xlnm.Print_Area"'));
      part.removeName(entry);
      expect(part.names, isEmpty);
      expect(part.element('definedNames'), isNull);
      expect(part.nameEdits, 0);
      expect(() => part.removeName(entry), throwsArgumentError);
    });

    test('an element swaps in schema position, in place and out', () {
      final WorkbookPart part = _read(
        _book('<workbookPr/><bookViews/><sheets/><calcPr/>'),
      );
      final XmlNode lock = XmlNode.made('', 'workbookProtection');
      part.swapElement('workbookProtection', null, lock);
      part.swapElement('definedNames', null, names());
      expect(_children(_encode(part)), <String>[
        'workbookPr',
        'workbookProtection',
        'bookViews',
        'sheets',
        'definedNames',
        'calcPr',
      ]);
      expect(part.element('workbookProtection'), same(lock));
      expect(part.element('definedNames'), isA<ItemGroup<String>>());

      final XmlNode next = lock.withChanges(<String, String?>{
        'lockStructure': '1',
      });
      part.swapElement('workbookProtection', lock, next);
      expect(part.element('workbookProtection'), same(next));
      expect(
        _encode(part),
        contains('<workbookProtection lockStructure="1"/>'),
      );

      part.swapElement('workbookProtection', next, null);
      part.swapElement('definedNames', part.element('definedNames'), null);
      expect(part.element('workbookProtection'), isNull);
      expect(part.element('definedNames'), isNull);
      expect(_children(_encode(part)), <String>[
        'workbookPr',
        'bookViews',
        'sheets',
        'calcPr',
      ]);
    });

    test('a group is found by a later element\'s position', () {
      final WorkbookPart part = _read(_book('<sheets/>'));
      part.swapElement('definedNames', null, names());
      part.requestFullCalculation();
      expect(_children(_encode(part)), <String>[
        'sheets',
        'definedNames',
        'calcPr',
      ]);
    });

    test('an edited group has no count', () {
      final WorkbookPart part = _read(_book('<sheets/>'));
      part.swapElement('definedNames', null, names().withItems(const []));
      expect(_encode(part), contains('<definedNames/>'));
    });

    test('an unknown slot throws', () {
      final WorkbookPart part = _read(_book('<sheets/>'));
      expect(() => part.element('bookViews'), throwsArgumentError);
      expect(() => part.swapElement('sheets', null, null), throwsArgumentError);
    });

    test('an untyped part has no elements and takes none', () {
      final WorkbookPart part = _read('<other/>');
      expect(part.element('workbookProtection'), isNull);
      expect(
        () => part.swapElement(
          'workbookProtection',
          null,
          XmlNode.made('', 'workbookProtection'),
        ),
        throwsStateError,
      );
    });
  });
}

/// The local names of the root's child elements, in order.
List<String> _children(String xml) {
  final XmlPullReader r = XmlPullReader(xml);
  final List<String> out = <String>[];
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.depth == 2) {
      out.add(r.localName);
    }
  }
  return out;
}
