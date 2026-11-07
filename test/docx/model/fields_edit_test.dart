// Tests building and editing fields: `DocxField` and its helpers, the shape
// the writer gives a built field, the `instruction` and `resultText` setters,
// the properties of every run of a field, and undo, redo and failure of each.
// They build documents in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/docx/model/inlines.dart' show paragraphOf;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';

const String _decls = 'xmlns:w="${Ns.w}"';

const String _begin = '<w:r><w:fldChar w:fldCharType="begin"/></w:r>';
const String _separate = '<w:r><w:fldChar w:fldCharType="separate"/></w:r>';
const String _end = '<w:r><w:fldChar w:fldCharType="end"/></w:r>';

/// A run of the instruction [text].
String _instr(String text) =>
    '<w:r><w:instrText xml:space="preserve">$text</w:instrText></w:r>';

/// A run of [text].
String _r(String text) => '<w:r><w:t>$text</w:t></w:r>';

/// The main part whose body holds [body].
String _main(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// A document whose body holds the paragraph of [content].
DocxDocument _open(String content) =>
    DocxDocument.open(buildDocx(document: _main('<w:p>$content</w:p>')));

/// The first paragraph of [doc].
DocxParagraph _first(DocxDocument doc) =>
    doc.body.blocks.first as DocxParagraph;

/// The text of the main part of [bytes].
String _savedMain(Uint8List bytes) =>
    utf8.decode(readXlsxBytes(bytes)['word/document.xml']!);

/// The text of the part [name] of [bytes].
String _part(Uint8List bytes, String name) =>
    utf8.decode(readXlsxBytes(bytes)[name]!);

/// The paragraph XML of [doc]'s first paragraph, as saved.
String _paragraphXml(DocxDocument doc) {
  final String main = _savedMain(doc.save().bytes);
  final int at = main.indexOf('<w:p>');
  return main.substring(at, main.indexOf('</w:p>', at) + 6);
}

void main() {
  group('building', () {
    test('page() writes exactly five runs', () {
      final DocxDocument doc = DocxDocument();
      _newParagraph(doc).addField(DocxField.page());
      expect(
        _paragraphXml(doc),
        '<w:p>$_begin'
        '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
        '$_separate<w:r><w:t>1</w:t></w:r>$_end</w:p>',
      );
    });

    test('numPages and sectionPages cache 1', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = _newParagraph(doc);
      p.addField(DocxField.numPages());
      p.addField(DocxField.sectionPages());
      final String xml = _paragraphXml(doc);
      expect(xml, contains('> NUMPAGES </w:instrText>'));
      expect(xml, contains('> SECTIONPAGES </w:instrText>'));
      expect(p.text, '11');
    });

    test('date and time write a picture switch, and a result as given', () {
      expect(
        DocxField.date(format: 'dd.MM.yyyy').instruction,
        ' DATE \\@ "dd.MM.yyyy" ',
      );
      expect(DocxField.date().instruction, ' DATE \\@ "dd.MM.yyyy" ');
      expect(DocxField.time().instruction, ' TIME \\@ "HH:mm" ');
      expect(DocxField.time(format: 'h:mm am/pm').name, 'TIME');
      expect(DocxField.date().text, '');
      expect(DocxField.date(result: '07.11.2026').text, '07.11.2026');
      expect(DocxField.time(result: '10:30').text, '10:30');
    });

    test('a format ending in a backslash throws', () {
      expect(() => DocxField.date(format: 'dd\\'), throwsArgumentError);
      expect(() => DocxField.time(format: 'HH\\'), throwsArgumentError);
    });

    test('a format holding a quote throws', () {
      expect(() => DocxField.date(format: 'dd"'), throwsArgumentError);
      expect(() => DocxField.time(format: '"'), throwsArgumentError);
    });

    test('an empty or blank instruction throws', () {
      expect(() => DocxField(''), throwsArgumentError);
      expect(() => DocxField(' \t '), throwsArgumentError);
      expect(() => DocxField('\u0001'), throwsArgumentError);
    });

    test('any instruction is a field, and the result is its text', () {
      final DocxField field = DocxField(' REF Bm \\h ', result: 'a\tb');
      expect(field.instruction, ' REF Bm \\h ');
      expect(field.name, 'REF');
      expect(field.text, 'a\tb');
      expect(field.result.single, isA<DocxRun>());
    });

    test('name stops at a backslash', () {
      expect(DocxField('PAGE\\* Arabic').name, 'PAGE');
      expect(DocxField(' page \\* Arabic ').name, 'PAGE');
      expect(DocxField('\\* MERGEFORMAT').name, isNull);
    });

    test('a built field reads back as the same field', () {
      final DocxDocument doc = DocxDocument();
      _newParagraph(doc)
        ..addRun('a')
        ..addField(DocxField.page());
      final DocxDocument back = DocxDocument.open(doc.save().bytes);
      final DocxParagraph p = back.body.blocks.last as DocxParagraph;
      expect(p.inlines, hasLength(2));
      final DocxField field = p.inlines[1] as DocxField;
      expect(field.instruction, ' PAGE ');
      expect(field.text, '1');
      expect(p.text, 'a1');
    });

    test('a forbidden character is removed and reported at the run', () {
      final DocxDocument doc = DocxDocument();
      _newParagraph(doc)
        ..addRun('x')
        ..addField(DocxField(' A\u0001B ', result: 'r\u0002'));
      final DocxResult saved = doc.save();
      expect(_savedMain(saved.bytes), contains('> AB </w:instrText>'));
      final List<DocxWarning> warnings = saved.warnings
          .where(
            (DocxWarning w) =>
                w.code == DocxWarningCode.invalidCharactersRemoved,
          )
          .toList();
      expect(warnings.expand((DocxWarning w) => w.locations).toList(), <String>[
        'body/p[1]/r[2]',
        'body/p[1]/r[4]',
      ]);
      expect(warnings.single.count, 2);
    });

    test('the section 6 footer sample', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.footer.addParagraph()
        ..addRun('Sayfa ')
        ..addField(DocxField.page())
        ..addRun(' / ')
        ..addField(DocxField.numPages());
      final Uint8List bytes = doc.save().bytes;
      final String footer = _part(bytes, 'word/footer1.xml');
      expect(
        footer,
        contains(
          '<w:p><w:r><w:t xml:space="preserve">Sayfa </w:t></w:r>'
          '$_begin'
          '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
          '$_separate<w:r><w:t>1</w:t></w:r>$_end'
          '<w:r><w:t xml:space="preserve"> / </w:t></w:r>'
          '$_begin'
          '<w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>'
          '$_separate<w:r><w:t>1</w:t></w:r>$_end</w:p>',
        ),
      );
      final DocxDocument back = DocxDocument.open(bytes);
      final DocxParagraph p =
          back.sections.last.footer.blocks.first as DocxParagraph;
      expect(p.text, 'Sayfa 1 / 1');
      expect(p.inlines.whereType<DocxField>(), hasLength(2));
    });

    test('a field in a paragraph of no document goes in with a document', () {
      final DocxParagraph p = DocxParagraph();
      final DocxField field = p.addField(DocxField.page());
      expect(p.inlines.single, same(field));
      field.instruction = ' NUMPAGES ';
      field.resultText = '5';
      field.properties.bold = true;
      expect(p.text, '5');

      final DocxDocument doc = DocxDocument();
      doc.body.insertBlock(0, p);
      final String xml = _paragraphXml(doc);
      expect(xml, contains('> NUMPAGES </w:instrText>'));
      expect(xml, contains('<w:t>5</w:t>'));
      expect('<w:b/>'.allMatches(xml), hasLength(5));
    });

    test('a field goes in one paragraph once', () {
      final DocxParagraph a = DocxParagraph();
      final DocxParagraph b = DocxParagraph();
      final DocxField field = a.addField(DocxField.page());
      expect(() => a.addField(field), throwsStateError);
      expect(() => b.insertInline(0, field), throwsStateError);
      expect(b.inlines, isEmpty);
      a.removeInlineAt(0);
      b.insertInline(0, field);
      expect(b.inlines.single, same(field));
    });

    test('a field removed and inserted again writes as it did', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = _newParagraph(doc);
      final DocxField field = p.addField(DocxField.page());
      final String before = _paragraphXml(doc);
      p.removeInlineAt(0);
      expect(p.inlines, isEmpty);
      field.resultText = '2';
      p.addField(field);
      expect(_paragraphXml(doc), before.replaceFirst('>1<', '>2<'));
    });
  });

  group('instruction', () {
    /// A field of two instruction runs with a mark between them, the first
    /// run bold.
    final String twoRuns =
        '$_begin'
        '<w:r><w:rPr><w:b/></w:rPr><w:instrText xml:space="preserve"> PA'
        '</w:instrText></w:r><w:proofErr w:type="spellStart"/>'
        '<w:r><w:rPr><w:i/></w:rPr><w:instrText>GE </w:instrText></w:r>'
        '$_separate${_r('3')}$_end';

    test('set keeps the first instruction run, and drops the others', () {
      final DocxDocument doc = _open(twoRuns);
      final DocxField field = _first(doc).inlines.single as DocxField;
      expect(field.instruction, ' PAGE ');
      field.instruction = ' NUMPAGES ';
      expect(field.instruction, ' NUMPAGES ');
      expect(
        _paragraphXml(doc),
        '<w:p>$_begin'
        '<w:r><w:rPr><w:b/></w:rPr>'
        '<w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>'
        '<w:proofErr w:type="spellStart"/>'
        '$_separate${_r('3')}$_end</w:p>',
      );
    });

    test('an empty one throws and changes nothing', () {
      final DocxDocument doc = _open(twoRuns);
      final DocxField field = _first(doc).inlines.single as DocxField;
      expect(() => field.instruction = '', throwsArgumentError);
      expect(() => field.instruction = '  \n', throwsArgumentError);
      expect(() => field.instruction = '\u0001', throwsArgumentError);
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(field.instruction, ' PAGE ');
    });

    test('the same text changes nothing', () {
      final DocxDocument doc = _open(twoRuns);
      final DocxField field = _first(doc).inlines.single as DocxField;
      field.instruction = ' PAGE ';
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a field with no instruction run gets one after its begin', () {
      final DocxDocument doc = _open('$_begin$_separate${_r('3')}$_end');
      final DocxField field = _first(doc).inlines.single as DocxField;
      expect(field.instruction, '');
      field.instruction = 'PAGE';
      expect(
        _paragraphXml(doc),
        '<w:p>$_begin'
        '<w:r><w:instrText xml:space="preserve">PAGE</w:instrText></w:r>'
        '$_separate${_r('3')}$_end</w:p>',
      );
      expect(field.text, '3');
    });

    test('a forbidden character is removed and reported', () {
      final DocxDocument doc = _open(twoRuns);
      final DocxField field = _first(doc).inlines.single as DocxField;
      field.instruction = 'X\u0001Y';
      expect(field.instruction, 'XY');
      final List<DocxWarning> warnings = doc
          .save()
          .warnings
          .where(
            (DocxWarning w) =>
                w.code == DocxWarningCode.invalidCharactersRemoved,
          )
          .toList();
      expect(warnings.single.count, 1);
      expect(warnings.single.locations, <String>['body/p[0]/r[1]']);
    });

    test('undo, redo and a failed transaction', () {
      final DocxDocument doc = _open(twoRuns);
      final DocxField field = _first(doc).inlines.single as DocxField;
      final String input = _savedMain(doc.save().bytes);
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => field.instruction = ' NUMPAGES ');
      final String edited = _savedMain(doc.save().bytes);
      expect(edited, isNot(input));
      changeLogOf(doc).revertSet(set);
      expect(field.instruction, ' PAGE ');
      expect(_savedMain(doc.save().bytes), input);
      changeLogOf(doc).reapplySet(set);
      expect(_savedMain(doc.save().bytes), edited);
      changeLogOf(doc).revertSet(set);

      expect(
        () => editsOf(doc).transaction(() {
          field.instruction = ' TIME ';
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(field.instruction, ' PAGE ');
      expect(_savedMain(doc.save().bytes), input);
    });
  });

  group('resultText', () {
    test('set keeps the first result run and its properties', () {
      final DocxDocument doc = _open(
        '$_begin${_instr(' PAGE ')}$_separate'
        '<w:r><w:rPr><w:b/></w:rPr><w:t>3</w:t></w:r>'
        '<w:proofErr w:type="spellStart"/>${_r('x')}$_end',
      );
      final DocxField field = _first(doc).inlines.single as DocxField;
      field.resultText = 'a\tb';
      expect(field.text, 'a\tb');
      expect(field.result, hasLength(1));
      expect(
        _paragraphXml(doc),
        '<w:p>$_begin${_instr(' PAGE ')}$_separate'
        '<w:r><w:rPr><w:b/></w:rPr><w:t>a</w:t><w:tab/><w:t>b</w:t></w:r>'
        '$_end</w:p>',
      );
    });

    test('a field with no separate gets a separate and a run', () {
      final DocxDocument doc = _open('$_begin${_instr(' PAGE ')}$_end');
      final DocxField field = _first(doc).inlines.single as DocxField;
      expect(field.text, '');
      field.resultText = '7';
      expect(
        _paragraphXml(doc),
        '<w:p>$_begin${_instr(' PAGE ')}'
        '$_separate${_r('7')}$_end</w:p>',
      );
      expect(_first(doc).text, '7');
    });

    test('a nested field in the result goes with the old result', () {
      final DocxDocument doc = _open(
        '$_begin${_instr(' IF ')}$_separate'
        '${_r('a')}$_begin${_instr(' PAGE ')}$_separate${_r('3')}$_end'
        '$_end',
      );
      final DocxField field = _first(doc).inlines.single as DocxField;
      expect(field.result.whereType<DocxField>(), hasLength(1));
      final DocxField nested = field.result.whereType<DocxField>().single;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => field.resultText = 'z');
      expect(field.result.whereType<DocxField>(), isEmpty);
      expect(paragraphOf(nested), isNull);
      expect(_first(doc).text, 'z');
      expect(_paragraphXml(doc), isNot(contains('PAGE')));
      changeLogOf(doc).revertSet(set);
      expect(_first(doc).text, 'a3');
      expect(paragraphOf(nested), same(_first(doc)));
      expect(_paragraphXml(doc), contains('PAGE'));
    });

    test('an empty result set empty changes nothing and adds nothing', () {
      for (final String content in <String>[
        '$_begin${_instr(' PAGE ')}$_end',
        '$_begin${_instr(' PAGE ')}$_separate$_end',
      ]) {
        final DocxDocument doc = _open(content);
        final String input = _savedMain(doc.save().bytes);
        final DocxField field = _first(doc).inlines.single as DocxField;
        field.resultText = '';
        expect(changeLogOf(doc).hasChanges, isFalse);
        expect(field.result, isEmpty);
        expect(_savedMain(doc.save().bytes), input);
      }
    });

    test('a result set to its own text keeps every inline of it', () {
      final DocxDocument doc = _open(
        '$_begin${_instr(' IF ')}$_separate'
        '<w:r><w:rPr><w:b/></w:rPr><w:t>a</w:t></w:r>'
        '<w:r><w:rPr><w:i/></w:rPr><w:t>b</w:t></w:r>'
        '$_begin${_instr(' PAGE ')}$_separate${_r('3')}$_end$_end',
      );
      final String input = _savedMain(doc.save().bytes);
      final DocxField field = _first(doc).inlines.single as DocxField;
      field.resultText = field.text;
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(field.result, hasLength(3));
      expect(_savedMain(doc.save().bytes), input);
    });

    test('the same result changes nothing', () {
      final DocxDocument doc = _open(
        '$_begin${_instr(' PAGE ')}$_separate${_r('3')}$_end',
      );
      final DocxField field = _first(doc).inlines.single as DocxField;
      field.resultText = '3';
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a forbidden character is removed and reported', () {
      final DocxDocument doc = DocxDocument();
      final DocxField field = _newParagraph(doc).addField(DocxField.page());
      field.resultText = 'a\u0001b';
      expect(field.text, 'ab');
      final DocxWarning w = doc.save().warnings.single;
      expect(w.code, DocxWarningCode.invalidCharactersRemoved);
      expect(w.locations, <String>['body/p[1]/r[3]']);
    });

    test('undo, redo and a failed transaction', () {
      final DocxDocument doc = _open(
        '$_begin${_instr(' PAGE ')}$_end${_r('after')}',
      );
      final DocxField field = _first(doc).inlines.first as DocxField;
      final String input = _savedMain(doc.save().bytes);
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => field.resultText = '9');
      final String edited = _savedMain(doc.save().bytes);
      expect(edited, contains('$_separate${_r('9')}'));
      changeLogOf(doc).revertSet(set);
      expect(field.text, '');
      expect(_savedMain(doc.save().bytes), input);
      changeLogOf(doc).reapplySet(set);
      expect(_savedMain(doc.save().bytes), edited);
      changeLogOf(doc).revertSet(set);

      expect(
        () => editsOf(doc).transaction(() {
          field.resultText = 'q';
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(field.text, '');
      expect(_savedMain(doc.save().bytes), input);
    });
  });

  group('properties', () {
    test('a set applies to every run of the field, nested ones too', () {
      final DocxDocument doc = _open(
        '$_begin${_instr(' IF ')}$_separate'
        '${_r('a')}$_begin${_instr(' PAGE ')}$_separate${_r('3')}$_end'
        '$_end',
      );
      final DocxField field = _first(doc).inlines.single as DocxField;
      expect(field.properties.bold, isNull);
      field.properties
        ..bold = true
        ..sizePt = 14;
      expect(field.properties.bold, isTrue);
      final String xml = _paragraphXml(doc);
      // begin, instr, separate, a, begin, instr, separate, 3, end, end.
      expect('<w:b/>'.allMatches(xml), hasLength(10));
      expect('<w:sz w:val="28"/>'.allMatches(xml), hasLength(10));
    });

    test('a read field reads the first run', () {
      final DocxDocument doc = _open(
        '<w:r><w:rPr><w:i/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>'
        '${_instr(' PAGE ')}$_separate${_r('3')}$_end',
      );
      final DocxField field = _first(doc).inlines.single as DocxField;
      expect(field.properties.italic, isTrue);
      expect(field.properties.bold, isNull);
      expect(identical(field.properties, field.properties), isTrue);
    });

    test('one transaction: undo and redo restore every run', () {
      final DocxDocument doc = _open(
        '<w:r><w:rPr><w:i/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>'
        '${_instr(' PAGE ')}$_separate${_r('3')}$_end',
      );
      final DocxField field = _first(doc).inlines.single as DocxField;
      final String input = _savedMain(doc.save().bytes);
      final ChangeSet set = editsOf(doc).transaction(() {
        field.properties.bold = true;
        field.properties.color = DocxColor.rgb('FF0000');
      });
      final String edited = _savedMain(doc.save().bytes);
      expect('<w:b/>'.allMatches(edited), hasLength(5));
      changeLogOf(doc).revertSet(set);
      expect(_savedMain(doc.save().bytes), input);
      changeLogOf(doc).reapplySet(set);
      expect(_savedMain(doc.save().bytes), edited);
    });

    test('one transaction records one change per run, and undoes them', () {
      final DocxDocument doc = DocxDocument();
      final DocxField field = _newParagraph(doc).addField(DocxField.page());
      final String before = _paragraphXml(doc);
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => field.properties.bold = true);
      expect(set.changes, hasLength(5));
      changeLogOf(doc).revertSet(set);
      expect(_paragraphXml(doc), before);
      expect(field.properties.bold, isNull);
    });

    test('clear removes it from every run', () {
      final DocxField field = DocxField.page();
      field.properties.bold = true;
      field.properties.clear(DocxRunProperty.bold);
      expect(field.properties.bold, isNull);
      final DocxParagraph p = DocxParagraph()..addField(field);
      final DocxDocument doc = DocxDocument()..body.insertBlock(0, p);
      expect(_paragraphXml(doc), contains('<w:r><w:instrText'));
    });

    test('a style set on a built field is checked on every run', () {
      final DocxDocument doc = DocxDocument();
      final DocxField field = _newParagraph(doc).addField(DocxField.page());
      field.properties.style = 'NoSuchStyle';
      expect(field.properties.style, 'NoSuchStyle');
      final List<String> locations = doc
          .save()
          .warnings
          .where((DocxWarning w) => w.code == DocxWarningCode.styleNotFound)
          .expand((DocxWarning w) => w.locations)
          .toList();
      expect(locations, hasLength(5));
    });

    test('a failed transaction leaves the runs as they were', () {
      final DocxDocument doc = DocxDocument();
      final DocxField field = _newParagraph(doc).addField(DocxField.page());
      final String before = _paragraphXml(doc);
      expect(
        () => editsOf(doc).transaction(() {
          field.properties.bold = true;
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(_paragraphXml(doc), before);
    });
  });
}

/// A new paragraph at the end of [doc]'s body.
DocxParagraph _newParagraph(DocxDocument doc) => doc.body.addParagraph();
