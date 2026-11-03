// Tests the styles model: the document defaults and styles read from a
// styles part, lookup by id and by name, adding a custom style with its
// checks, and style properties that set, write in schema order and revert
// with their transaction. The documents are built in memory, so these tests
// run on the web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../support/styles_documents.dart';

/// The `styles.xml` [doc] saves.
String _saved(DocxDocument doc) =>
    readDocxText(doc.save().bytes)['word/styles.xml']!;

/// A document whose styles part holds [styles] inside `w:styles`.
DocxDocument _withStyles(String styles) => DocxDocument.open(
  docxWithStyles(
    styles:
        '<w:styles xmlns:w="${Ns.w}" '
        'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">'
        '$styles</w:styles>',
  ),
);

/// Expects [body] to throw an [ArgumentError] and change nothing in
/// [styles].
void _rejects(DocxStyles styles, void Function() body) {
  final int before = styles.styles.length;
  expect(body, throwsArgumentError);
  expect(styles.styles, hasLength(before));
}

void main() {
  group('reading', () {
    test('reads docDefaults of blank', () {
      final DocxDocumentDefaults defaults = DocxDocument().styles.defaults;
      expect(defaults.runProperties.sizePt, 12);
      expect(defaults.runProperties.fonts?.asciiTheme, 'minorHAnsi');
      expect(defaults.runProperties.language, 'en-US');
      expect(
        defaults.paragraphProperties.spacing,
        DocxSpacing(afterPt: 8, line: DocxLineSpacing.multiple(278 / 240)),
      );
    });

    test('byName is case-insensitive', () {
      final DocxStyles styles = DocxDocument().styles;
      expect(styles.byName('HEADING 1')?.id, 'Heading1');
      expect(styles.byName('normal')?.id, 'Normal');
      expect(styles.byName('Heading 99'), isNull);
    });

    test('byId is exact', () {
      final DocxStyles styles = DocxDocument().styles;
      expect(styles.byId('Heading1')?.name, 'heading 1');
      expect(styles.byId('heading1'), isNull);
    });

    test('reads a style of a Word file', () {
      final DocxStyles styles = DocxDocument.open(docxWithStyles()).styles;
      expect(styles.styles.map((DocxStyle s) => s.id), <String>[
        'Normal',
        'Balk1',
        'VarsaylanParagrafYazTipi',
        'Balk1Char',
        'NormalTablo',
        'TabloKlavuzu',
        'ListeYok',
      ]);
      final DocxStyle h = styles.byName('heading 1')!;
      expect(h.type, DocxStyleType.paragraph);
      expect(h.id, 'Balk1');
      expect(h.basedOn, 'Normal');
      expect(h.next, 'Normal');
      expect(h.link, 'Balk1Char');
      expect(h.uiPriority, 9);
      expect(h.quickFormat, isTrue);
      expect(h.isDefault, isFalse);
      expect(h.isCustom, isFalse);
      expect(h.paragraphProperties.keepWithNext, isTrue);
      expect(h.paragraphProperties.outlineLevel, 0);
      expect(h.runProperties.sizePt, 20);
      expect(styles.byId('Normal')!.isDefault, isTrue);
      expect(styles.byId('Balk1Char')!.isCustom, isTrue);
      expect(styles.byId('Balk1Char')!.type, DocxStyleType.character);
      expect(styles.byId('NormalTablo')!.type, DocxStyleType.table);
      expect(styles.byId('ListeYok')!.type, DocxStyleType.numbering);
      expect(styles.byId('ListeYok')!.quickFormat, isFalse);
    });

    test('a style without w:type is a paragraph style, one of another type '
        'has none', () {
      final DocxStyles styles = _withStyles(
        '<w:style w:styleId="A"><w:name w:val="a"/></w:style>'
        '<w:style w:type="weird" w:styleId="B"><w:name w:val="b"/></w:style>',
      ).styles;
      expect(styles.byId('A')!.type, DocxStyleType.paragraph);
      expect(styles.byId('B')!.type, isNull);
    });

    test('the styles list cannot be modified and shows later adds', () {
      final DocxStyles styles = DocxDocument().styles;
      final List<DocxStyle> list = styles.styles;
      final int before = list.length;
      expect(() => list.add(list.first), throwsUnsupportedError);
      styles.add(
        DocxStyle(type: DocxStyleType.paragraph, id: 'Note', name: 'Note'),
      );
      expect(list, hasLength(before + 1));
      expect(list.last.id, 'Note');
    });
  });

  group('adding', () {
    test('add rejects a used id, a used name, an unknown basedOn, a basedOn '
        'of another type and a cycle', () {
      final DocxStyles styles = DocxDocument().styles;
      DocxStyle p(String id, {String? name, String? basedOn}) => DocxStyle(
        type: DocxStyleType.paragraph,
        id: id,
        name: name ?? id,
        basedOn: basedOn,
      );
      _rejects(styles, () => styles.add(p('normal', name: 'Mine')));
      _rejects(styles, () => styles.add(p('Mine', name: 'HEADING 1')));
      _rejects(styles, () => styles.add(p('Mine', basedOn: 'Missing')));
      _rejects(
        styles,
        () => styles.add(
          DocxStyle(
            type: DocxStyleType.character,
            id: 'Mine',
            name: 'Mine',
            basedOn: 'Normal',
          ),
        ),
      );
      _rejects(styles, () => styles.add(p('Mine', basedOn: 'Mine')));
      _rejects(
        styles,
        () => styles.add(
          DocxStyle(
            type: DocxStyleType.paragraph,
            id: 'Mine',
            name: 'Mine',
            next: 'Missing',
          ),
        ),
      );
      _rejects(
        styles,
        () => styles.add(
          DocxStyle(
            type: DocxStyleType.paragraph,
            id: 'Mine',
            name: 'Mine',
            link: 'Missing',
          ),
        ),
      );
      // A cycle through a basedOn the file holds, dangling until now.
      final DocxStyles read = _withStyles(
        '<w:style w:type="paragraph" w:styleId="A"><w:name w:val="a"/>'
        '<w:basedOn w:val="New"/></w:style>',
      ).styles;
      _rejects(read, () => read.add(p('New', basedOn: 'A')));
      // next may name the style itself.
      styles.add(
        DocxStyle(
          type: DocxStyleType.paragraph,
          id: 'Mine',
          name: 'Mine',
          basedOn: 'Normal',
          next: 'Mine',
        ),
      );
      expect(styles.byId('Mine')!.next, 'Mine');
    });

    test('a style already in a document throws StateError', () {
      final DocxStyles styles = DocxDocument().styles;
      final DocxStyle note = DocxStyle(
        type: DocxStyleType.paragraph,
        id: 'Note',
        name: 'Note',
      );
      styles.add(note);
      expect(() => styles.add(note), throwsStateError);
      expect(() => DocxDocument().styles.add(note), throwsStateError);
      expect(
        () => DocxDocument().styles.add(styles.byId('Normal')!),
        throwsStateError,
      );
    });

    test('the constructor checks its arguments', () {
      expect(
        () => DocxStyle(type: DocxStyleType.paragraph, id: '', name: 'a'),
        throwsArgumentError,
      );
      expect(
        () => DocxStyle(type: DocxStyleType.paragraph, id: 'a', name: ''),
        throwsArgumentError,
      );
      expect(
        () => DocxStyle(
          type: DocxStyleType.paragraph,
          id: 'a',
          name: 'a',
          uiPriority: 100,
        ),
        throwsRangeError,
      );
      expect(
        () =>
            DocxStyle(type: DocxStyleType.paragraph, id: 'a', name: 'a\u0001'),
        throwsArgumentError,
      );
    });

    test('add writes customStyle and the children in styleOrder', () {
      final DocxDocument doc = DocxDocument();
      final DocxStyles styles = doc.styles;
      styles.add(
        DocxStyle(
          type: DocxStyleType.character,
          id: 'NoteChar',
          name: 'Note Char',
          basedOn: 'DefaultParagraphFont',
        ),
      );
      final DocxStyle note = DocxStyle(
        type: DocxStyleType.paragraph,
        id: 'Note',
        name: 'Note',
        basedOn: 'Normal',
        next: 'Normal',
        link: 'NoteChar',
        uiPriority: 5,
        quickFormat: true,
      );
      note.runProperties.bold = true;
      note.paragraphProperties.alignment = DocxAlignment.center;
      expect(note.isCustom, isTrue);
      expect(note.isDefault, isFalse);
      expect(styles.add(note), same(note));
      expect(
        _saved(doc),
        endsWith(
          '<w:style w:type="character" w:customStyle="1" '
          'w:styleId="NoteChar"><w:name w:val="Note Char"/>'
          '<w:basedOn w:val="DefaultParagraphFont"/></w:style>'
          '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Note">'
          '<w:name w:val="Note"/><w:basedOn w:val="Normal"/>'
          '<w:next w:val="Normal"/><w:link w:val="NoteChar"/>'
          '<w:uiPriority w:val="5"/><w:qFormat/>'
          '<w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:b/></w:rPr>'
          '</w:style></w:styles>',
        ),
      );
      final DocxStyle back = DocxDocument.open(
        doc.save().bytes,
      ).styles.byId('Note')!;
      expect(back.isCustom, isTrue);
      expect(back.runProperties.bold, isTrue);
      expect(back.link, 'NoteChar');
    });

    test('a style is appended after the last w:style', () {
      final DocxDocument doc = _withStyles(
        '<w:style w:type="paragraph" w:styleId="A"><w:name w:val="a"/>'
        '</w:style><w14:tail/>',
      );
      doc.styles.add(
        DocxStyle(type: DocxStyleType.paragraph, id: 'B', name: 'b'),
      );
      expect(
        _saved(doc),
        contains(
          '<w:name w:val="a"/></w:style><w:style w:type="paragraph" '
          'w:customStyle="1" w:styleId="B"><w:name w:val="b"/></w:style>'
          '<w14:tail/>',
        ),
      );
    });

    test('document defaults are created before the latent styles', () {
      final DocxDocument doc = _withStyles(
        '<w:latentStyles w:count="1"/>'
        '<w:style w:type="paragraph" w:styleId="A"><w:name w:val="a"/>'
        '</w:style>',
      );
      doc.styles.defaults.paragraphProperties.keepLines = true;
      doc.styles.defaults.runProperties.italic = true;
      expect(
        _saved(doc),
        contains(
          '<w:docDefaults><w:rPrDefault><w:rPr><w:i/></w:rPr></w:rPrDefault>'
          '<w:pPrDefault><w:pPr><w:keepLines/></w:pPr></w:pPrDefault>'
          '</w:docDefaults><w:latentStyles w:count="1"/>',
        ),
      );
    });
  });

  group('editing', () {
    test('setting a style property is one change that reverts', () {
      final DocxDocument doc = DocxDocument.open(docxWithStyles());
      final DocxStyle h = doc.styles.byId('Balk1')!;
      final ChangeLog log = changeLogOf(doc);
      for (final void Function() edit in <void Function()>[
        () => h.uiPriority = 3,
        () => h.name = 'My heading',
        () => h.basedOn = null,
        () => h.quickFormat = false,
        () => h.runProperties.bold = true,
        () => h.paragraphProperties.alignment = DocxAlignment.right,
      ]) {
        final String before = _saved(doc);
        final ChangeSet set = editsOf(doc).transaction(edit);
        expect(set.changes, hasLength(1));
        expect(_saved(doc), isNot(before));
        log.revertSet(set);
        expect(_saved(doc), before);
      }
      expect(h.uiPriority, 9);
      expect(h.name, 'heading 1');
      expect(h.basedOn, 'Normal');
      expect(h.quickFormat, isTrue);
    });

    test('a default property set is one change that reverts', () {
      final DocxDocument doc = DocxDocument();
      final DocxDocumentDefaults d = doc.styles.defaults;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => d.runProperties.sizePt = 11);
      expect(set.changes, hasLength(1));
      expect(d.runProperties.sizePt, 11);
      changeLogOf(doc).revertSet(set);
      expect(d.runProperties.sizePt, 12);
    });

    test('setters check against the document', () {
      final DocxDocument doc = DocxDocument.open(docxWithStyles());
      final DocxStyles styles = doc.styles;
      final DocxStyle h = styles.byId('Balk1')!;
      expect(() => h.basedOn = 'Missing', throwsArgumentError);
      expect(() => h.basedOn = 'VarsaylanParagrafYazTipi', throwsArgumentError);
      expect(() => h.basedOn = 'Balk1', throwsArgumentError);
      expect(() => h.next = 'Missing', throwsArgumentError);
      expect(() => h.link = 'Missing', throwsArgumentError);
      expect(() => h.name = 'NORMAL', throwsArgumentError);
      expect(() => h.name = null, throwsArgumentError);
      expect(() => h.uiPriority = 100, throwsRangeError);
      expect(changeLogOf(doc).hasChanges, isFalse);
      // A cycle: Normal basedOn heading 1, which is based on Normal.
      expect(
        () => styles.byId('Normal')!.basedOn = 'Balk1',
        throwsArgumentError,
      );
      h.name = 'HEADING 1';
      expect(h.name, 'HEADING 1');
      h.next = 'Balk1';
      expect(h.next, 'Balk1');
    });

    test('setting quickFormat false removes w:qFormat', () {
      final DocxDocument doc = DocxDocument.open(docxWithStyles());
      final DocxStyle normal = doc.styles.byId('Normal')!;
      normal.quickFormat = false;
      expect(_saved(doc), contains('<w:name w:val="Normal"/></w:style>'));
    });

    test('a style property set then saved writes only that child anew', () {
      final DocxDocument doc = DocxDocument.open(docxWithStyles());
      doc.styles.byId('TabloKlavuzu')!.uiPriority = 40;
      final String xml = _saved(doc);
      expect(
        xml,
        contains(
          '<w:style w:type="table" w:styleId="TabloKlavuzu" w14:x="1">'
          '<w:name w:val="Table Grid"/><w:basedOn w:val="NormalTablo"/>'
          '<w:uiPriority w:val="40"/><w:tblPr>',
        ),
      );
      expect(
        xml,
        contains(
          '<w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr>'
          '</w:tblStylePr></w:style>',
        ),
      );
    });

    test('a style not in a document records nothing', () {
      final DocxDocument doc = DocxDocument();
      final DocxStyle s = DocxStyle(
        type: DocxStyleType.paragraph,
        id: 'Free',
        name: 'Free',
      );
      s.uiPriority = 4;
      s.basedOn = 'Anything';
      s.runProperties.italic = true;
      expect(s.uiPriority, 4);
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(() => doc.styles.add(s), throwsArgumentError);
      s.basedOn = 'Normal';
      doc.styles.add(s);
      expect(changeLogOf(doc).hasChanges, isTrue);
    });
  });

  test('the bytes of an unchanged read style are kept', () {
    final Uint8List input = docxWithStyles();
    final DocxDocument doc = DocxDocument.open(input);
    doc.styles.byId('Normal')!.uiPriority = 0;
    expect(
      _saved(doc),
      contains(
        '<w:style w:type="paragraph" w:styleId="Balk1">'
        '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
        '<w:next w:val="Normal"/><w:link w:val="Balk1Char"/>'
        '<w:uiPriority w:val="9"/><w:qFormat/><w:rsid w:val="00A13F2E"/>',
      ),
    );
  });
}
