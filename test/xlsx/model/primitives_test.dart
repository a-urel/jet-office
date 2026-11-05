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
      final OpcPackage p = OpcPackage.read(
        ZipReader(
          buildZipOrdered(<(String, List<int>)>[
            ('a.xml', '<a/>'.codeUnits),
            (
              '_rels/a.xml.rels',
              ('<Relationships><Relationship Id="rId1" Type="t" Target="x"/>'
                      '<Relationship Id="rId1" Type="t" Target="y"/>'
                      '</Relationships>')
                  .codeUnits,
            ),
          ]),
          maxEntries: 10,
          maxEntryBytes: 1 << 20,
          maxTotalBytes: 1 << 20,
          maxCompressionRatio: 1000,
        ),
        maxDepth: 64,
      );
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        removeStoredRelationship(log, p, '/a.xml', 'rId1');
      });
      expect(set.isEmpty, isTrue);
      expect(p.relationshipsOf('/a.xml').length, 2);
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

final class _Xml implements PartContent {
  @override
  List<Uint8List> encode() => <Uint8List>[Uint8List(0)];
}
