// Tests the numbering model: the abstract definitions, their levels and the
// instances read from numbering.xml, the ids new definitions take (plan
// Ruling 9), where they go, and the edits of a level and a start override.
// Documents are built in memory, so these tests run on the web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/docx/model/numbering.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../support/numbering_documents.dart';
import '../support/styles_documents.dart' show readDocxText;

DocxDocument _open(String children) =>
    DocxDocument.open(docxWithNumbering(numbering: numberingXml(children)));

String _numberingOf(DocxDocument doc) =>
    readDocxText(doc.save().bytes)['word/numbering.xml']!;

void main() {
  test('reads levels, format, text, start, alignment, indentation and '
      'bullet font', () {
    final DocxNumbering numbering = DocxDocument.open(
      docxWithNumbering(),
    ).numbering;
    final List<DocxAbstractNumbering> abstracts = numbering.abstractNumberings;
    expect(abstracts.map((DocxAbstractNumbering a) => a.id), <int>[0, 1]);
    final DocxNumberingLevel bullet = abstracts[0].levels[0];
    expect(bullet.level, 0);
    expect(bullet.format, DocxNumberFormat.bullet);
    expect(bullet.text, '');
    expect(bullet.start, 1);
    expect(bullet.alignment, DocxLevelAlignment.left);
    expect(bullet.indentation, DocxIndentation(leftPt: 36, hangingPt: 18));
    expect(bullet.bulletFont, DocxFonts(ascii: 'Symbol', hAnsi: 'Symbol'));
    final DocxNumberingLevel courier = abstracts[0].levels[1];
    expect(courier.level, 1);
    expect(courier.text, 'o');
    expect(courier.bulletFont?.ascii, 'Courier New');

    final List<DocxNumberingLevel> numbered = abstracts[1].levels;
    expect(numbered.map((DocxNumberingLevel l) => l.level), <int>[0, 1, 2]);
    expect(numbered.map((DocxNumberingLevel l) => l.format), <Object>[
      DocxNumberFormat.decimal,
      DocxNumberFormat.lowerLetter,
      DocxNumberFormat.lowerRoman,
    ]);
    expect(numbered.map((DocxNumberingLevel l) => l.text), <String>[
      '%1.',
      '%2)',
      '%3.',
    ]);
    expect(numbered[1].start, 3);
    expect(numbered[1].alignment, DocxLevelAlignment.center);
    expect(numbered[2].alignment, DocxLevelAlignment.right);
    expect(numbered[2].indentation, DocxIndentation(leftPt: 108, hangingPt: 9));
    expect(numbered[0].bulletFont, isNull);

    final List<DocxNumberingInstance> instances = numbering.instances;
    expect(instances.map((DocxNumberingInstance n) => n.id), <int>[1, 2]);
    expect(instances[0].abstractId, 0);
    expect(instances[0].abstractNumbering, same(abstracts[0]));
    expect(instances[0].overrides, isEmpty);
    expect(instances[1].abstractNumbering, same(abstracts[1]));
    expect(instances[1].overrides.single.level, 0);
    expect(instances[1].overrides.single.startOverride, 5);
    expect(numbering.instanceById(2), same(instances[1]));
    expect(numbering.instanceById(3), isNull);
    expect(instances[1].ref(level: 2), DocxNumberingRef(2, level: 2));
    expect(instances[1].ref(), DocxNumberingRef(2));
    expect(() => instances[1].ref(level: 9), throwsRangeError);
  });

  test('other formats and a custom format read null', () {
    final DocxNumberingLevel level = _open(
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
      '<w:numFmt w:val="custom" w:format="001, 002"/>'
      '<w:lvlText w:val="%1"/><w:lvlJc w:val="both"/></w:lvl>'
      '<w:lvl w:ilvl="1"><w:numFmt w:val="chicago"/></w:lvl>'
      '</w:abstractNum>',
    ).numbering.abstractNumberings.single.levels[0];
    expect(level.format, isNull);
    expect(level.alignment, isNull);
    expect(level.text, '%1');
  });

  test('new ids are the lowest unused', () {
    final DocxDocument doc = _open(
      '${abstractNumXml('0')}${abstractNumXml('2')}'
      '${abstractNumXml('999999999')}${abstractNumXml('abc')}'
      '${abstractNumXml('1234567890')}'
      '${numXml('1', '0')}${numXml('3', '2')}${numXml('abc', '0')}'
      '${numXml('1234567890', '0')}',
    );
    final DocxNumbering numbering = doc.numbering;
    expect(
      numbering.abstractNumberings.map((DocxAbstractNumbering a) => a.id),
      <int>[0, 2, 999999999],
    );
    expect(numbering.instances.map((DocxNumberingInstance n) => n.id), <int>[
      1,
      3,
    ]);
    final DocxAbstractNumbering added = addAbstractNumbering(
      numbering,
      decimalTemplate,
    );
    expect(added.id, 1);
    final DocxNumberingInstance first = numbering.addInstance(added);
    expect(first.id, 2);
    expect(first.abstractNumbering, same(added));
    expect(numbering.addInstance(added).id, 4);
    expect(addAbstractNumbering(numbering, decimalTemplate).id, 3);
    final String xml = _numberingOf(doc);
    expect(xml, contains('w:abstractNumId="abc"'));
    expect(xml, contains('w:abstractNumId="1234567890"'));
    expect(xml, contains('w:numId="abc"'));
    expect(xml, contains('w:numId="1234567890"'));
  });

  test('numId 0 is never given', () {
    final DocxDocument doc = _open(numXml('0', '0'));
    final DocxNumbering numbering = doc.numbering;
    final DocxAbstractNumbering a = addAbstractNumbering(
      numbering,
      decimalTemplate,
    );
    expect(a.id, 0);
    expect(numbering.addInstance(a).id, 1);
    final DocxNumbering empty = DocxDocument.open(
      docxWithNumbering(numbering: null, relationships: ''),
    ).numbering;
    expect(
      empty.addInstance(addAbstractNumbering(empty, decimalTemplate)).id,
      1,
    );
  });

  test('an opaque num with a numeric id still takes its id', () {
    final DocxDocument doc = _open(
      '${abstractNumXml('0')}<w:num w:numId="1"/>',
    );
    final DocxNumbering numbering = doc.numbering;
    expect(numbering.instances, isEmpty);
    expect(numbering.addInstance(numbering.abstractNumberings.single).id, 2);
  });

  test('startOverrides write lvlOverride with startOverride', () {
    final DocxDocument doc = _open(abstractNumXml('0'));
    final DocxNumbering numbering = doc.numbering;
    final DocxNumberingInstance n = numbering.addInstance(
      numbering.abstractNumberings.single,
      startOverrides: <int, int>{2: 7, 0: 3},
    );
    expect(n.overrides.map((DocxLevelOverride o) => o.level), <int>[0, 2]);
    expect(n.overrides.map((DocxLevelOverride o) => o.startOverride), <int>[
      3,
      7,
    ]);
    expect(
      _numberingOf(doc),
      contains(
        '<w:num w:numId="1"><w:abstractNumId w:val="0"/>'
        '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="3"/>'
        '</w:lvlOverride><w:lvlOverride w:ilvl="2">'
        '<w:startOverride w:val="7"/></w:lvlOverride></w:num>',
      ),
    );
  });

  test('startOverrides out of range throw RangeError and change nothing', () {
    final DocxDocument doc = _open(abstractNumXml('0'));
    final DocxNumbering numbering = doc.numbering;
    final DocxAbstractNumbering a = numbering.abstractNumberings.single;
    for (final Map<int, int> bad in <Map<int, int>>[
      <int, int>{9: 1},
      <int, int>{-1: 1},
      <int, int>{0: -1},
      <int, int>{0: 32768},
    ]) {
      expect(
        () => numbering.addInstance(a, startOverrides: bad),
        throwsRangeError,
      );
    }
    expect(numbering.instances, isEmpty);
    expect(changeLogOf(doc).hasChanges, isFalse);
  });

  test('an abstract of another document throws ArgumentError', () {
    final DocxDocument one = _open(abstractNumXml('0'));
    final DocxDocument two = _open(abstractNumXml('0'));
    expect(
      () => one.numbering.addInstance(two.numbering.abstractNumberings.single),
      throwsArgumentError,
    );
    expect(one.numbering.instances, isEmpty);
  });

  test('a dangling abstractNumId reads abstractNumbering null', () {
    final DocxNumbering numbering = _open(
      '${abstractNumXml('0')}${numXml('1', '5')}',
    ).numbering;
    final DocxNumberingInstance n = numbering.instances.single;
    expect(n.abstractId, 5);
    expect(n.abstractNumbering, isNull);
  });

  test('level text %0 throws ArgumentError', () {
    final DocxNumberingLevel level = DocxDocument.open(
      docxWithNumbering(),
    ).numbering.abstractNumberings[1].levels[0];
    for (final String bad in <String>['%0', 'a%', '%%1', '%a', 'x\u0001']) {
      expect(() => level.text = bad, throwsArgumentError, reason: bad);
    }
    expect(level.text, '%1.');
    level.text = '%1.%9 x';
    expect(level.text, '%1.%9 x');
  });

  test('a read level text that breaks the rule reads null and stays', () {
    final DocxDocument doc = _open(
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
      '<w:lvlText w:val="%0."/></w:lvl></w:abstractNum>',
    );
    expect(doc.numbering.abstractNumberings.single.levels.single.text, isNull);
    expect(_numberingOf(doc), contains('<w:lvlText w:val="%0."/>'));
  });

  test('setting level members writes them in schema order', () {
    final DocxDocument doc = _open(
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0" w:tplc="1">'
      '<w:lvlText w:val="%1."/><w14:x xmlns:w14="${Ns.w14}"/></w:lvl>'
      '</w:abstractNum>',
    );
    final DocxNumberingLevel level =
        doc.numbering.abstractNumberings.single.levels.single;
    level
      ..alignment = DocxLevelAlignment.end
      ..indentation = DocxIndentation(leftPt: 18, hangingPt: 18)
      ..bulletFont = DocxFonts(ascii: 'Wingdings', hAnsi: 'Wingdings')
      ..format = DocxNumberFormat.upperRoman
      ..start = 32767;
    expect(() => level.start = 32768, throwsRangeError);
    expect(() => level.start = -1, throwsRangeError);
    expect(
      _numberingOf(doc),
      contains(
        '<w:lvl w:ilvl="0" w:tplc="1"><w:start w:val="32767"/>'
        '<w:numFmt w:val="upperRoman"/><w:lvlText w:val="%1."/>'
        '<w14:x xmlns:w14="${Ns.w14}"/><w:lvlJc w:val="end"/>'
        '<w:pPr><w:ind w:left="360" w:hanging="360"/></w:pPr>'
        '<w:rPr><w:rFonts w:ascii="Wingdings" w:hAnsi="Wingdings" '
        'w:hint="default"/></w:rPr></w:lvl>',
      ),
    );
    expect(level.bulletFont, DocxFonts(ascii: 'Wingdings', hAnsi: 'Wingdings'));
  });

  test('bulletFont = null keeps the other attributes of w:rFonts, and clear '
      'removes the element', () {
    final DocxDocument doc = DocxDocument.open(docxWithNumbering());
    final DocxNumberingLevel level =
        doc.numbering.abstractNumberings[0].levels[1];
    level.bulletFont = null;
    expect(level.bulletFont, isNull);
    final String kept = _numberingOf(doc);
    expect(kept, contains('<w:rFonts w:cs="Courier New" w:hint="default"/>'));
    level.clear(DocxNumberingLevelProperty.bulletFont);
    expect(_numberingOf(doc), isNot(contains('w:cs="Courier New"')));
  });

  test('setting a bullet font keeps the other attributes of w:rFonts', () {
    final DocxDocument doc = DocxDocument.open(docxWithNumbering());
    final DocxNumberingLevel level =
        doc.numbering.abstractNumberings[0].levels[1];
    level.bulletFont = DocxFonts(ascii: 'Arial', hAnsi: 'Arial');
    expect(
      _numberingOf(doc),
      contains(
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Courier New" '
        'w:hint="default"/>',
      ),
    );
  });

  test('clear removes a child the model does not type', () {
    final DocxDocument doc = _open(
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0" w:tplc="7">'
      '<w:start w:val="1in"/><w:numFmt w:val="chicago"/>'
      '<w:lvlText w:val="%0"/><w:lvlJc w:val="both"/>'
      '<w:pPr><w:keepNext/><w:ind w:start="720"/></w:pPr>'
      '<w:rPr><w:rFonts w:ascii=""/><w:b/></w:rPr></w:lvl></w:abstractNum>'
      '<w:num w:numId="1"><w:abstractNumId w:val="0"/>'
      '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="-4"/>'
      '</w:lvlOverride></w:num>',
    );
    final DocxNumbering numbering = doc.numbering;
    final DocxNumberingLevel level =
        numbering.abstractNumberings.single.levels.single;
    final DocxLevelOverride o = numbering.instances.single.overrides.single;
    expect(level.start, isNull);
    level.start = null;
    o.startOverride = null;
    expect(changeLogOf(doc).hasChanges, isFalse);
    for (final DocxNumberingLevelProperty p
        in DocxNumberingLevelProperty.values) {
      level.clear(p);
    }
    o.clearStartOverride();
    expect(changeLogOf(doc).hasChanges, isTrue);
    final String xml = _numberingOf(doc);
    expect(
      xml,
      contains(
        '<w:lvl w:ilvl="0" w:tplc="7"><w:pPr><w:keepNext/></w:pPr>'
        '<w:rPr><w:b/></w:rPr></w:lvl>',
      ),
    );
    expect(xml, contains('<w:lvlOverride w:ilvl="0"/></w:num>'));
  });

  test('clearing what is not there records nothing', () {
    final DocxDocument doc = _open(
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"/>'
      '</w:abstractNum>',
    );
    final DocxNumberingLevel level =
        doc.numbering.abstractNumberings.single.levels.single;
    for (final DocxNumberingLevelProperty p
        in DocxNumberingLevelProperty.values) {
      level.clear(p);
    }
    expect(changeLogOf(doc).hasChanges, isFalse);
  });

  test('a bullet font set keeps a read w:hint', () {
    final DocxDocument doc = _open(
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:rPr>'
      '<w:rFonts w:ascii="A" w:hAnsi="A" w:hint="eastAsia"/></w:rPr>'
      '</w:lvl></w:abstractNum>',
    );
    doc.numbering.abstractNumberings.single.levels.single.bulletFont =
        DocxFonts(ascii: 'Symbol', hAnsi: 'Symbol');
    expect(
      _numberingOf(doc),
      contains(
        '<w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="eastAsia"/>',
      ),
    );
  });

  test('addAbstractNumbering refuses trailing input and undefined '
      'entities', () {
    final DocxNumbering numbering = _open('').numbering;
    for (final String bad in <String>[
      '<w:abstractNum/></w:numbering><w:numbering>',
      '<w:abstractNum><w:lvl w:ilvl="0"><w:lvlText w:val="&bogus;"/>'
          '</w:lvl></w:abstractNum>',
      '<w:abstractNum><w:name w:val="x"/>&bogus;</w:abstractNum>',
      '<w:abstractNum/><w:abstractNum/>',
      '<w:num/>',
      '',
    ]) {
      expect(
        () => addAbstractNumbering(numbering, bad),
        throwsArgumentError,
        reason: bad,
      );
    }
    expect(numbering.abstractNumberings, isEmpty);
  });

  test('a level edit and a start override edit are changes that revert', () {
    final DocxDocument doc = DocxDocument.open(docxWithNumbering());
    final DocxNumbering numbering = doc.numbering;
    final DocxNumberingLevel level = numbering.abstractNumberings[1].levels[0];
    final DocxLevelOverride o = numbering.instances[1].overrides.single;
    expect(
      () => editsOf(doc).transaction(() {
        level.format = DocxNumberFormat.upperLetter;
        level.text = '%1)';
        o.startOverride = 9;
        throw StateError('fail');
      }),
      throwsStateError,
    );
    expect(level.format, DocxNumberFormat.decimal);
    expect(level.text, '%1.');
    expect(o.startOverride, 5);
    o.startOverride = 9;
    expect(changeLogOf(doc).hasChanges, isTrue);
    expect(() => o.startOverride = 32768, throwsRangeError);
    expect(o.startOverride, 9);
  });

  test('a new abstract goes before the first num', () {
    final DocxDocument doc = DocxDocument.open(docxWithNumbering());
    final DocxNumbering numbering = doc.numbering;
    final DocxAbstractNumbering a = addAbstractNumbering(
      numbering,
      decimalTemplate,
    );
    expect(a.id, 2);
    expect(numbering.abstractNumberings.last, same(a));
    final DocxNumberingInstance n = numbering.addInstance(a);
    expect(n.id, 3);
    final String xml = _numberingOf(doc);
    final int added = xml.indexOf('<w:abstractNum w:abstractNumId="2">');
    expect(added, greaterThan(xml.indexOf('w:abstractNumId="1"')));
    expect(added, lessThan(xml.indexOf('<w:num ')));
    final int num = xml.indexOf('<w:num w:numId="3">');
    expect(num, greaterThan(xml.indexOf('<w:num w:numId="2"')));
    expect(num, lessThan(xml.indexOf('<w:numIdMacAtCleanup')));
  });

  test('a new abstract goes after the picture bullets when there is none', () {
    final DocxDocument doc = _open(
      '<w:numPicBullet w:numPicBulletId="0"/>${numXml('1', '0')}',
    );
    addAbstractNumbering(doc.numbering, decimalTemplate);
    final String xml = _numberingOf(doc);
    expect(
      xml,
      contains(
        '<w:numPicBullet w:numPicBulletId="0"/>'
        '<w:abstractNum w:abstractNumId="0">',
      ),
    );
    expect(xml.indexOf('<w:abstractNum '), lessThan(xml.indexOf('<w:num ')));
  });

  test('a part that binds WordprocessingML as the default namespace gets '
      'prefixed new definitions', () {
    final DocxDocument doc = DocxDocument.open(
      docxWithNumbering(
        numbering:
            '<numbering xmlns="${Ns.w}">'
            '<abstractNum xmlns:w="${Ns.w}" w:abstractNumId="0">'
            '<lvl w:ilvl="0"><start w:val="1"/></lvl></abstractNum>'
            '</numbering>',
      ),
    );
    final DocxNumbering numbering = doc.numbering;
    expect(numbering.abstractNumberings.single.levels.single.start, 1);
    numbering.addInstance(
      addAbstractNumbering(numbering, decimalTemplate),
      startOverrides: <int, int>{0: 2},
    );
    final Uint8List bytes = doc.save().bytes;
    final DocxNumbering back = DocxDocument.open(bytes).numbering;
    expect(
      back.abstractNumberings.map((DocxAbstractNumbering a) => a.id),
      <int>[0, 1],
    );
    expect(back.instances.single.overrides.single.startOverride, 2);
    expect(back.abstractNumberings[1].levels.single.text, '%1.');
  });

  test('the lists are unmodifiable', () {
    final DocxNumbering numbering = DocxDocument.open(
      docxWithNumbering(),
    ).numbering;
    expect(
      () => numbering.abstractNumberings.removeLast(),
      throwsUnsupportedError,
    );
    expect(() => numbering.instances.removeLast(), throwsUnsupportedError);
    expect(
      () => numbering.abstractNumberings[0].levels.removeLast(),
      throwsUnsupportedError,
    );
    expect(
      () => numbering.instances[1].overrides.removeLast(),
      throwsUnsupportedError,
    );
  });
}
