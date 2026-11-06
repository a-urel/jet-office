// ignore_for_file: avoid_dynamic_calls
// Pins what the exported run and paragraph properties, styles and document
// defaults offer: only the typed members (and clear), none of the untyped
// property set behind them or of the styles part's internals. It
// imports the public library only, so it runs on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import 'support/docx_builder.dart';
import 'support/numbering_documents.dart';

/// The members of the internal property set, as calls on [p].
Map<String, void Function()> _internalCalls(dynamic p, String child) =>
    <String, void Function()>{
      'setValue': () => p.setValue(child, 1e9),
      'valueOf': () => p.valueOf(child),
      'isSet': () => p.isSet(child),
      'stateOf': () => p.stateOf(child),
      'restore': () => p.restore(child, null),
      'clearChild': () => p.clearChild(child),
      'writeTo': () => p.writeTo(null, 'rPr'),
      'source': () => p.source,
      'schema': () => p.schema,
      'writesNothing': () => p.writesNothing,
    };

void main() {
  test('DocxRunProperties exposes no member of the internal property set', () {
    final dynamic p = DocxRun('a').properties;
    _internalCalls(p, 'sz').forEach((String name, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: name);
    });
    expect((p as DocxRunProperties).sizePt, isNull);
  });

  test(
    'DocxParagraphProperties exposes no member of the internal property set',
    () {
      final dynamic p = DocxParagraph().properties;
      _internalCalls(p, 'ind').forEach((String name, void Function() call) {
        expect(call, throwsA(isA<NoSuchMethodError>()), reason: name);
      });
      expect((p as DocxParagraphProperties).indentation, isNull);
    },
  );

  test('DocxStyle exposes no member of the internal property set', () {
    final dynamic s = DocxStyle(
      type: DocxStyleType.paragraph,
      id: 'Note',
      name: 'Note',
    );
    _internalCalls(s, 'uiPriority').forEach((String n, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: n);
    });
    expect((s as DocxStyle).uiPriority, isNull);
  });

  test('DocxDocumentDefaults and DocxStyles expose no internals', () {
    final DocxStyles styles = DocxDocument().styles;
    final dynamic d = styles.defaults;
    _internalCalls(d, 'rPrDefault').forEach((String n, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: n);
    });
    final dynamic st = styles;
    for (final MapEntry<String, void Function()> e in <String, void Function()>{
      'root': () => st.root,
      'children': () => st.children,
      'encode': () => st.encode(),
      'writeTo': () => st.writeTo(null, 'styles'),
      'resolveLink': () => st.resolveLink('Normal'),
    }.entries) {
      expect(e.value, throwsA(isA<NoSuchMethodError>()), reason: e.key);
    }
    expect(styles.byId('Normal'), isNotNull);
  });

  test('a numbering level and a level override expose no member of the '
      'internal property set', () {
    final DocxNumbering numbering = DocxDocument.open(
      docxWithNumbering(),
    ).numbering;
    final dynamic level = numbering.abstractNumberings[1].levels[0];
    _internalCalls(level, 'start').forEach((String n, void Function() call) {
      expect(call, throwsA(isA<NoSuchMethodError>()), reason: n);
    });
    expect((level as DocxNumberingLevel).start, 1);
    final dynamic o = numbering.instances[1].overrides.single;
    _internalCalls(o, 'startOverride').forEach((String n, void Function() c) {
      expect(c, throwsA(isA<NoSuchMethodError>()), reason: n);
    });
    expect((o as DocxLevelOverride).startOverride, 5);
    for (final MapEntry<String, void Function()> e in <String, void Function()>{
      'level clearChild': () => (level as dynamic).clearChild('start'),
      'level clear by name': () => (level as dynamic).clear('start'),
      'override clear': () => (o as dynamic).clear('startOverride'),
    }.entries) {
      expect(
        e.value,
        throwsA(anyOf(isA<NoSuchMethodError>(), isA<TypeError>())),
        reason: e.key,
      );
    }
  });

  test('the numbering, its definitions and instances expose no internals', () {
    final DocxNumbering numbering = DocxDocument.open(
      docxWithNumbering(),
    ).numbering;
    final dynamic n = numbering;
    final dynamic a = numbering.abstractNumberings.first;
    final dynamic i = numbering.instances.first;
    for (final MapEntry<String, void Function()> e in <String, void Function()>{
      'root': () => n.root,
      'children': () => n.children,
      'edits': () => n.edits,
      'encode': () => n.encode(),
      'abstractById': () => n.abstractById(0),
      'lastIndexOf': () => n.lastIndexOf('num'),
      'abstract start': () => a.start,
      'abstract children': () => a.children,
      'abstract attachment': () => a.attachment,
      'instance start': () => i.start,
      'instance children': () => i.children,
      'instance attachment': () => i.attachment,
      'level set': () => (a.levels.first as dynamic).set,
      'level pPr': () => (a.levels.first as dynamic).pPr,
    }.entries) {
      expect(e.value, throwsA(isA<NoSuchMethodError>()), reason: e.key);
    }
    expect(numbering.instances.first.abstractId, 0);
  });

  test('the members of a level and an override have no setter where they '
      'are read-only', () {
    final DocxNumbering numbering = DocxDocument.open(
      docxWithNumbering(),
    ).numbering;
    final dynamic level = numbering.abstractNumberings.first.levels.first;
    final dynamic o = numbering.instances[1].overrides.single;
    final dynamic a = numbering.abstractNumberings.first;
    final dynamic i = numbering.instances.first;
    for (final MapEntry<String, void Function()> e in <String, void Function()>{
      'level.level': () => level.level = 1,
      'override.level': () => o.level = 1,
      'abstract.id': () => a.id = 1,
      'instance.id': () => i.id = 1,
      'instance.abstractId': () => i.abstractId = 1,
    }.entries) {
      expect(e.value, throwsA(isA<NoSuchMethodError>()), reason: e.key);
    }
  });

  test('the properties of a style and of the defaults have no setter', () {
    final dynamic style = DocxStyle(
      type: DocxStyleType.paragraph,
      id: 'Note',
      name: 'Note',
    );
    final dynamic defaults = DocxDocument().styles.defaults;
    for (final dynamic o in <dynamic>[style, defaults]) {
      expect(
        () => o.runProperties = DocxRun('a').properties,
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(
        () => o.paragraphProperties = DocxParagraph().properties,
        throwsA(isA<NoSuchMethodError>()),
      );
    }
  });

  test('tables, rows and cells are exported and expose no internals', () {
    final DocxDocument doc = DocxDocument.open(
      buildDocx(
        document:
            '<w:document xmlns:w="${Ns.w}"><w:body><w:tbl><w:tr><w:tc><w:p/>'
            '</w:tc></w:tr></w:tbl></w:body></w:document>',
      ),
    );
    final DocxBlock block = doc.body.blocks.single;
    final DocxTable table = block as DocxTable;
    final DocxTableRow row = table.rows.single;
    final DocxTableCell cell = row.cells.single;
    expect(cell.blocks.single, isA<DocxParagraph>());
    expect(cell.text, '');
    for (final dynamic o in <dynamic>[table, row, cell]) {
      expect(() => o.children, throwsA(isA<NoSuchMethodError>()));
      expect(() => o.source, throwsA(isA<NoSuchMethodError>()));
    }
  });

  test('the values of tables, rows and cells are exported', () {
    expect(DocxTableWidth.points(72).widthPt, 72);
    expect(DocxTableWidth.percent(50).kind, DocxTableWidthKind.percent);
    expect(DocxTableLayout.values, hasLength(2));
    expect(DocxTableAlignment.values, hasLength(3));
    expect(const DocxTableBorders().top, isNull);
    expect(const DocxCellBorders().topLeftToBottomRight, isNull);
    expect(DocxTableMargins(leftPt: 5.4).leftPt, 5.4);
    expect(const DocxTableLook(firstRow: true).firstRow, isTrue);
    expect(DocxRowHeight(20, rule: DocxRowHeightRule.exact).heightPt, 20);
    expect(DocxVerticalMerge.values, hasLength(2));
    expect(DocxCellAlignment.values, hasLength(3));
    expect(DocxTextDirection.values, hasLength(6));
  });
}
