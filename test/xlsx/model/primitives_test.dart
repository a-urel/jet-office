import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/element_node.dart';
import 'package:jet_office/src/xlsx/model/primitives.dart';
import 'package:jet_office/src/xlsx/model/styles_part.dart';
import 'package:jet_office/src/xlsx/model/workbook_part.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import '../read/support/zip_builder.dart';

RawCell _num(String v) => RawCell(kind: RawCellKind.number, value: v);

RawCell _f(RawFormula f, [String? v]) =>
    RawCell(kind: RawCellKind.number, value: v, formula: f);

void main() {
  test('relationshipTarget gives the path from the source to the part', () {
    expect(
      relationshipTarget('/xl/worksheets/sheet1.xml', '/xl/comments1.xml'),
      '../comments1.xml',
    );
    expect(
      relationshipTarget(
        '/xl/worksheets/sheet1.xml',
        '/xl/drawings/vmlDrawing1.vml',
      ),
      '../drawings/vmlDrawing1.vml',
    );
    expect(
      relationshipTarget('/xl/worksheets/sub/sheet1.xml', '/xl/comments1.xml'),
      '../../comments1.xml',
    );
    expect(
      relationshipTarget('/xl/worksheets/sheet1.xml', '/xl/worksheets/a.xml'),
      'a.xml',
    );
    expect(relationshipTarget('/sheet1.xml', '/xl/a.xml'), 'xl/a.xml');
    expect(relationshipTarget('/other/s.xml', '/xl/a.xml'), '../xl/a.xml');
  });

  group('setStoredCell', () {
    test('records old and new; revert restores', () {
      final CellStore store = CellStore()..put(0, 0, _num('1'));
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        setStoredCell(log, store, 0, 0, _num('2'));
        setStoredCell(log, store, 1, 1, _num('3'));
      });
      expect(store.cellAt(0, 0)!.value, '2');
      expect(store.cellAt(1, 1)!.value, '3');
      expect(log.hasChanges, isTrue);

      log.revertSet(set);
      expect(store.cellAt(0, 0)!.value, '1');
      expect(store.cellAt(1, 1), isNull);

      log.reapplySet(set);
      expect(store.cellAt(0, 0)!.value, '2');
      expect(store.cellAt(1, 1)!.value, '3');
    });

    test('null removes the cell and revert puts it back', () {
      final CellStore store = CellStore()..put(0, 0, _num('1'));
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(
        () => setStoredCell(log, store, 0, 0, null),
      );
      expect(store.cellAt(0, 0), isNull);
      log.revertSet(set);
      expect(store.cellAt(0, 0)!.value, '1');
    });

    test('outside a transaction it throws and leaves the store unchanged', () {
      final CellStore store = CellStore();
      final ChangeLog log = ChangeLog();
      expect(
        () => setStoredCell(log, store, 0, 0, _num('1')),
        throwsStateError,
      );
      expect(store.cellAt(0, 0), isNull);
    });
  });

  group('setStoredRowAttributes', () {
    const KeptAttribute ht = (
      qualifiedName: 'ht',
      namespaceUri: '',
      value: '9',
    );

    test('records old and new; revert restores, and a bare row goes', () {
      final CellStore store = CellStore();
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(
        () => setStoredRowAttributes(log, store, 3, <KeptAttribute>[ht]),
      );
      expect(store.rowAttributes(3), <KeptAttribute>[ht]);
      expect(store.rowIndexes, <int>[3]);
      log.revertSet(set);
      expect(store.rowAttributes(3), isEmpty);
      expect(store.rowIndexes, isEmpty);
      log.reapplySet(set);
      expect(store.rowAttributes(3), <KeptAttribute>[ht]);
    });

    test('outside a transaction it throws and leaves the store unchanged', () {
      final CellStore store = CellStore();
      expect(
        () =>
            setStoredRowAttributes(ChangeLog(), store, 0, <KeptAttribute>[ht]),
        throwsStateError,
      );
      expect(store.rowAttributes(0), isEmpty);
    });
  });

  group('groupRoleAt', () {
    final CellStore store = CellStore()
      ..put(
        1,
        1,
        _f(
          const RawFormula(
            type: FormulaType.shared,
            text: 'A2*2',
            ref: 'B2:B4',
            si: '0',
          ),
        ),
      )
      ..put(2, 1, _f(const RawFormula(type: FormulaType.shared, si: '0')))
      ..put(3, 1, _f(const RawFormula(type: FormulaType.shared, si: '0')))
      ..put(
        1,
        3,
        _f(
          const RawFormula(
            type: FormulaType.array,
            text: 'A1:A2',
            ref: 'D2:D3',
          ),
        ),
      )
      ..put(2, 3, _num('5'))
      ..put(5, 5, _f(const RawFormula(type: FormulaType.normal, text: '1')))
      ..put(6, 6, _f(const RawFormula(type: FormulaType.shared, si: '9')));

    test('shared master and children', () {
      expect(groupRoleAt(store, 1, 1), GroupRole.sharedMaster);
      expect(groupRoleAt(store, 2, 1), GroupRole.sharedChild);
      expect(groupRoleAt(store, 3, 1), GroupRole.sharedChild);
    });

    test('array master and member, with or without a stored cell', () {
      expect(groupRoleAt(store, 1, 3), GroupRole.arrayOrTableMember);
      expect(groupRoleAt(store, 2, 3), GroupRole.arrayOrTableMember);
      expect(groupRoleAt(store, 4, 3), GroupRole.none);
    });

    test('none for plain, normal and orphan shared cells', () {
      expect(groupRoleAt(store, 0, 0), GroupRole.none);
      expect(groupRoleAt(store, 5, 5), GroupRole.none);
      expect(groupRoleAt(store, 6, 6), GroupRole.none);
    });

    test('a store without formulas is none everywhere', () {
      expect(groupRoleAt(CellStore(), 0, 0), GroupRole.none);
    });
  });

  group('appendStyle', () {
    StylesPart styles() => StylesPart.read(
      XmlPullReader(
        '<styleSheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main"><cellXfs><xf numFmtId="0"/></cellXfs>'
        '</styleSheet>',
      ),
      const XlsxReadLimits(),
    );
    const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));

    test('records what it appended; revert and reapply', () {
      final StylesPart part = styles();
      final StylesMark before = part.mark();
      final ChangeLog log = ChangeLog();
      late int id;
      final ChangeSet set = log.transaction(() {
        id = appendStyle(log, part, bold);
      });
      expect(set.changes.single, isA<StylesAppendChange>());
      final StylesMark after = part.mark();
      expect(after, isNot(before));
      log.revertSet(set);
      expect(part.mark(), before);
      log.reapplySet(set);
      expect(part.mark(), after);
      expect(part.styleOf(id).font?.bold, isTrue);
    });

    test('records nothing for a style the part has', () {
      final StylesPart part = styles();
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        expect(appendStyle(log, part, null), 0);
      });
      expect(set.isEmpty, isTrue);
      expect(log.hasChanges, isFalse);
    });

    test('a failed transaction removes the appended entries', () {
      final StylesPart part = styles();
      final StylesMark before = part.mark();
      final ChangeLog log = ChangeLog();
      expect(
        () => log.transaction(() {
          appendStyle(log, part, bold);
          throw StateError('later');
        }),
        throwsStateError,
      );
      expect(part.mark(), before);
    });
  });

  group('appendDifferentialStyle', () {
    StylesPart styles() => StylesPart.read(
      XmlPullReader(
        '<styleSheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main"><cellXfs><xf numFmtId="0"/></cellXfs>'
        '<dxfs count="1"><dxf><font><b/></font></dxf></dxfs></styleSheet>',
      ),
      const XlsxReadLimits(),
    );
    const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
    const XlsxStyle italic = XlsxStyle(font: XlsxFont(italic: true));

    test('records what it appended; revert and reapply', () {
      final StylesPart part = styles();
      final StylesMark before = part.mark();
      final ChangeLog log = ChangeLog();
      late int id;
      final ChangeSet set = log.transaction(() {
        id = appendDifferentialStyle(log, part, italic);
      });
      expect(id, 1);
      expect(set.changes.single, isA<StylesAppendChange>());
      final StylesMark after = part.mark();
      expect(after.dxfs, before.dxfs + 1);
      log.revertSet(set);
      expect(part.mark(), before);
      expect(part.dxfCount, 1);
      log.reapplySet(set);
      expect(part.mark(), after);
      expect(part.differentialStyle(id), italic);
    });

    test('records nothing for a dxf the part has', () {
      final StylesPart part = styles();
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        expect(appendDifferentialStyle(log, part, bold), 0);
      });
      expect(set.isEmpty, isTrue);
      expect(log.hasChanges, isFalse);
    });

    test('a failed transaction removes the appended entry', () {
      final StylesPart part = styles();
      final StylesMark before = part.mark();
      final ChangeLog log = ChangeLog();
      expect(
        () => log.transaction(() {
          appendDifferentialStyle(log, part, italic);
          throw StateError('later');
        }),
        throwsStateError,
      );
      expect(part.mark(), before);
    });
  });

  group('editWorkbook', () {
    const String ns =
        'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    WorkbookPart book() => WorkbookPart.read(
      XmlPullReader(
        '<workbook xmlns="$ns"><workbookProtection lockStructure="1"/>'
        '<sheets/></workbook>',
      ),
      const XlsxReadLimits(),
    );

    test('records a change that reverts and reapplies', () {
      final WorkbookPart part = book();
      final Object before = part.element('workbookProtection')!;
      final XmlNode next = (before as XmlNode).withChanges(<String, String?>{
        'lockWindows': '1',
      });
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        editWorkbook(
          log,
          part,
          'workbookProtection',
          () => part.swapElement('workbookProtection', before, next),
        );
      });
      expect(set.changes.single, isA<SetWorkbookElementChange>());
      expect(part.element('workbookProtection'), same(next));
      log.revertSet(set);
      expect(part.element('workbookProtection'), same(before));
      log.reapplySet(set);
      expect(part.element('workbookProtection'), same(next));
    });

    test('an edit that changes nothing records nothing', () {
      final WorkbookPart part = book();
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        editWorkbook(log, part, 'workbookProtection', () {});
      });
      expect(set.isEmpty, isTrue);
      expect(log.hasChanges, isFalse);
    });

    test('a failed edit puts the element back', () {
      final WorkbookPart part = book();
      final Object before = part.element('workbookProtection')!;
      final ChangeLog log = ChangeLog();
      expect(
        () => log.transaction(() {
          editWorkbook(log, part, 'workbookProtection', () {
            part.swapElement('workbookProtection', before, null);
            throw StateError('no');
          });
        }),
        throwsStateError,
      );
      expect(part.element('workbookProtection'), same(before));
      expect(log.hasChanges, isFalse);
    });

    test('recording outside a transaction leaves the element', () {
      final WorkbookPart part = book();
      final Object before = part.element('workbookProtection')!;
      expect(
        () => editWorkbook(
          ChangeLog(),
          part,
          'workbookProtection',
          () => part.swapElement('workbookProtection', before, null),
        ),
        throwsStateError,
      );
      expect(part.element('workbookProtection'), same(before));
    });
  });

  group('attachStoredPart', () {
    OpcPackage package() => OpcPackage.read(
      ZipReader(
        buildZip(<String, List<int>>{
          'xl/a.xml': <int>[60, 97, 47, 62],
        }),
        maxEntries: 10,
        maxEntryBytes: 1000,
        maxTotalBytes: 1000,
        maxCompressionRatio: 1000,
      ),
      maxDepth: 8,
    );

    List<int> written(OpcPackage p) =>
        p.openXml('xl/a.xml').sourceText(0, 4).codeUnits;

    test('gives the part its content; undone, the file bytes come back', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      final Set<String> attached = <String>{};
      final ChangeSet set = log.transaction(() {
        attachStoredPart(log, p, attached, 'xl/a.xml', _Typed());
      });
      expect(attached, <String>{'xl/a.xml'});
      expect(set.changes, hasLength(1));
      log.revertSet(set);
      expect(attached, isEmpty);
      expect(written(p), <int>[60, 97, 47, 62]);
      log.reapplySet(set);
      expect(attached, <String>{'xl/a.xml'});
      expect(written(p), '<b/>'.codeUnits);
    });

    test('a part attached, or created, records nothing', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        attachStoredPart(log, p, <String>{'xl/a.xml'}, 'xl/a.xml', _Xml());
      });
      expect(set.isEmpty, isTrue);
    });

    test('a failed transaction takes it back', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      final Set<String> attached = <String>{};
      expect(
        () => log.transaction(() {
          attachStoredPart(log, p, attached, 'xl/a.xml', _Xml());
          throw StateError('later');
        }),
        throwsStateError,
      );
      expect(attached, isEmpty);
      expect(written(p), <int>[60, 97, 47, 62]);
    });
  });

  group('stored parts', () {
    OpcPackage package() => OpcPackage.empty()
      ..addPart('/xl/sheet1.xml', 'x/sheet', _Xml())
      ..addRelationship('/xl/sheet1.xml', type: 't', target: 'x');

    // The written package: every entry name with its bytes.
    List<String> written(OpcPackage p) {
      final ZipWriter writer = ZipWriter();
      p.writeTo(writer);
      final ZipReader zip = ZipReader(
        writer.close()!,
        maxEntries: 100,
        maxEntryBytes: 1 << 20,
        maxTotalBytes: 1 << 20,
        maxCompressionRatio: 1000,
      );
      return <String>[
        for (final String n in zip.names)
          '$n:${String.fromCharCodes(zip.read(n))}',
      ];
    }

    test('addStoredPart undone leaves no part, Default or Override', () {
      final OpcPackage p = package();
      final List<String> before = written(p);
      final ChangeLog log = ChangeLog();
      late String name;
      final ChangeSet set = log.transaction(() {
        name = addStoredPart(
          log,
          p,
          '/xl/drawings/drawing1.xml',
          'x/d',
          _Xml(),
        );
        addStoredPart(
          log,
          p,
          '/xl/media/image1.png',
          'image/png',
          _Xml(),
          byExtension: true,
        );
      });
      expect(name, '/xl/drawings/drawing1.xml');
      expect(p.hasPart('/xl/media/image1.png'), isTrue);
      expect(p.contentTypeOf('/xl/media/image1.png'), 'image/png');
      expect(log.hasChanges, isTrue);

      log.revertSet(set);
      expect(p.hasPart(name), isFalse);
      expect(p.hasPart('/xl/media/image1.png'), isFalse);
      expect(p.contentTypeOf('/xl/media/image1.png'), isNull);
      expect(written(p), before);
    });

    test('reapply after revert gives the same name', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      late String name;
      final ChangeSet set = log.transaction(() {
        name = addStoredPart(log, p, '/xl/sheet1.xml', 'x/sheet', _Xml());
        addStoredPart(
          log,
          p,
          '/xl/media/image1.png',
          'image/png',
          _Xml(),
          byExtension: true,
        );
      });
      expect(name, '/xl/sheet2.xml');
      final List<String> after = written(p);
      log.revertSet(set);
      log.reapplySet(set);
      expect(p.hasPart('/xl/sheet2.xml'), isTrue);
      expect(p.contentTypeOf('/xl/media/image1.png'), 'image/png');
      expect(written(p), after);
    });

    test('a Default that was already there stays when the part is undone', () {
      final OpcPackage p = package();
      p.addPart('/xl/media/image1.png', 'image/png', _Xml(), byExtension: true);
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        addStoredPart(
          log,
          p,
          '/xl/media/image1.png',
          'image/png',
          _Xml(),
          byExtension: true,
        );
      });
      log.revertSet(set);
      expect(p.hasPart('/xl/media/image2.png'), isFalse);
      expect(p.contentTypeOf('/xl/media/image2.png'), 'image/png');
    });

    test('removeStoredPart undone restores it', () {
      final OpcPackage p = package();
      final List<String> before = written(p);
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        removeStoredPart(log, p, '/xl/sheet1.xml');
      });
      expect(p.hasPart('/xl/sheet1.xml'), isFalse);
      expect(p.contentTypeOf('/xl/sheet1.xml'), isNull);
      log.revertSet(set);
      expect(written(p), before);
      log.reapplySet(set);
      expect(p.hasPart('/xl/sheet1.xml'), isFalse);
      log.revertSet(set);
      expect(written(p), before);
    });

    test('a failed transaction gives the part back', () {
      final OpcPackage p = package();
      final List<String> before = written(p);
      final ChangeLog log = ChangeLog();
      expect(
        () => log.transaction(() {
          removeStoredPart(log, p, '/xl/sheet1.xml');
          addStoredPart(
            log,
            p,
            '/xl/media/a.png',
            'image/png',
            _Xml(),
            byExtension: true,
          );
          throw StateError('x');
        }),
        throwsStateError,
      );
      expect(written(p), before);
    });

    test('outside a transaction nothing changes', () {
      final OpcPackage p = package();
      final List<String> before = written(p);
      final ChangeLog log = ChangeLog();
      expect(
        () => addStoredPart(
          log,
          p,
          '/xl/media/a.png',
          'image/png',
          _Xml(),
          byExtension: true,
        ),
        throwsStateError,
      );
      expect(
        () => removeStoredPart(log, p, '/xl/sheet1.xml'),
        throwsStateError,
      );
      expect(written(p), before);
    });

    test('removing an unknown part throws and records nothing', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      late ChangeSet set;
      expect(
        () => log.transaction(() => removeStoredPart(log, p, '/nope.xml')),
        throwsArgumentError,
      );
      expect(log.hasChanges, isFalse);
      set = log.transaction(() {});
      expect(set.isEmpty, isTrue);
    });
  });

  group('stored relationships', () {
    OpcPackage package() => OpcPackage.empty()
      ..addPart('/a.xml', 'x/a', _Xml())
      ..addRelationship('/a.xml', type: 't', target: 'first')
      ..addRelationship(
        '/a.xml',
        type: 'u',
        target: 'https://example.com',
        external: true,
      );

    /// A package whose part `/a.xml` has the relationships [elements].
    OpcPackage withRels(String elements) => OpcPackage.read(
      ZipReader(
        buildZipOrdered(<(String, List<int>)>[
          ('a.xml', '<a/>'.codeUnits),
          (
            '_rels/a.xml.rels',
            '<Relationships>$elements</Relationships>'.codeUnits,
          ),
        ]),
        maxEntries: 10,
        maxEntryBytes: 1 << 20,
        maxTotalBytes: 1 << 20,
        maxCompressionRatio: 1000,
      ),
      maxDepth: 64,
    );

    List<String> ids(OpcPackage p) => <String>[
      for (final OpcRelationship r in p.relationshipsOf('/a.xml')) r.id,
    ];

    test('an added relationship reverts and comes back with its id', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      late String id;
      final ChangeSet set = log.transaction(() {
        id = addStoredRelationship(log, p, '/a.xml', type: 't', target: 'x');
      });
      expect(id, 'rId3');
      expect(set.changes.single, isA<SetRelationshipChange>());
      log.revertSet(set);
      expect(ids(p), <String>['rId1', 'rId2']);
      log.reapplySet(set);
      expect(p.relationshipsOf('/a.xml').last, (
        id: 'rId3',
        type: 't',
        target: 'x',
        external: false,
      ));
    });

    test('a removed relationship comes back whole', () {
      final OpcPackage p = package();
      final OpcRelationship gone = p.relationshipsOf('/a.xml').last;
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        removeStoredRelationship(log, p, '/a.xml', 'rId2');
      });
      expect(ids(p), <String>['rId1']);
      log.revertSet(set);
      expect(p.relationshipsOf('/a.xml').last, gone);
      log.reapplySet(set);
      expect(ids(p), <String>['rId1']);
    });

    test('removing an unknown id records nothing', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        removeStoredRelationship(log, p, '/a.xml', 'rId9');
      });
      expect(set.isEmpty, isTrue);
    });

    test('an id a file repeats stays, as it could not be put back', () {
      final OpcPackage p = withRels(
        '<Relationship Id="rId1" Type="t" Target="x"/>'
        '<Relationship Id="rId1" Type="t" Target="y"/>',
      );
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        removeStoredRelationship(log, p, '/a.xml', 'rId1');
      });
      expect(set.isEmpty, isTrue);
      expect(p.relationshipsOf('/a.xml').length, 2);
    });

    for (final (String what, String element) in <(String, String)>[
      ('target', '<Relationship Id="rId1" Type="t" Target=""/>'),
      ('type', '<Relationship Id="rId1" Type="" Target="x"/>'),
    ]) {
      test('a relationship with an empty $what stays', () {
        final OpcPackage p = withRels(element);
        final ChangeLog log = ChangeLog();
        final ChangeSet set = log.transaction(() {
          removeStoredRelationship(log, p, '/a.xml', 'rId1');
        });
        expect(set.isEmpty, isTrue);
        expect(p.relationshipsOf('/a.xml').length, 1);
      });
    }

    test('a relationship with an empty id stays', () {
      final OpcPackage p = withRels(
        '<Relationship Id="" Type="t" Target="x"/>',
      );
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        removeStoredRelationship(log, p, '/a.xml', '');
      });
      expect(set.isEmpty, isTrue);
      expect(p.relationshipsOf('/a.xml').length, 1);
    });

    test('a failed transaction undoes both kinds', () {
      final OpcPackage p = package();
      final ChangeLog log = ChangeLog();
      expect(
        () => log.transaction(() {
          removeStoredRelationship(log, p, '/a.xml', 'rId1');
          addStoredRelationship(log, p, '/a.xml', type: 't', target: 'x');
          throw StateError('no');
        }),
        throwsStateError,
      );
      expect(ids(p).toSet(), <String>{'rId1', 'rId2'});
      expect(ids(p).length, 2);
    });

    test('recording outside a transaction changes nothing', () {
      final OpcPackage p = package();
      expect(
        () => addStoredRelationship(
          ChangeLog(),
          p,
          '/a.xml',
          type: 't',
          target: 'x',
        ),
        throwsStateError,
      );
      expect(ids(p), <String>['rId1', 'rId2']);
      expect(
        () => removeStoredRelationship(ChangeLog(), p, '/a.xml', 'rId1'),
        throwsStateError,
      );
      expect(ids(p).toSet(), <String>{'rId1', 'rId2'});
    });
  });
}

final class _Typed implements PartContent {
  @override
  List<Uint8List> encode() => <Uint8List>[Uint8List.fromList('<b/>'.codeUnits)];
}

final class _Xml implements PartContent {
  @override
  List<Uint8List> encode() => <Uint8List>[Uint8List(0)];
}
