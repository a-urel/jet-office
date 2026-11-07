// Tests reading complex fields: what is typed as a `DocxField`, what stays
// runs (each case with the paragraph's text as before, and the part saved as
// read after an edit elsewhere), the run content of marks and instructions,
// how a field's runs edit, move and report, and how far fields nest. They
// build documents in memory, so they run on the web as well;
// `owner_files_test.dart` reads the fields of the owner's `long.docx`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/docx/model/inlines.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';
import '../support/styles_documents.dart';

const String _decls = 'xmlns:w="${Ns.w}"';

const String _begin = '<w:r><w:fldChar w:fldCharType="begin"/></w:r>';
const String _separate = '<w:r><w:fldChar w:fldCharType="separate"/></w:r>';
const String _end = '<w:r><w:fldChar w:fldCharType="end"/></w:r>';

/// A run of the instruction [text].
String _instr(String text) =>
    '<w:r><w:instrText xml:space="preserve">$text</w:instrText></w:r>';

/// A run of [text].
String _r(String text) => '<w:r><w:t>$text</w:t></w:r>';

/// A paragraph of [content].
String _p(String content) => '<w:p>$content</w:p>';

/// A `PAGE` field whose result is [result].
String _page(String result) =>
    '$_begin${_instr(' PAGE ')}$_separate${_r(result)}$_end';

/// The main part whose body holds [body].
String _main(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// A document whose body holds [body].
DocxDocument _open(String body) =>
    DocxDocument.open(buildDocx(document: _main(body)));

/// The first paragraph of the document whose body holds [body].
DocxParagraph _first(String body) =>
    _open(body).body.blocks.first as DocxParagraph;

/// A document with Word's styles whose body holds [body].
DocxDocument _styled(String body) =>
    DocxDocument.open(docxWithStyles(document: _main(body)));

/// The locations of the styles [doc] does not define, as a save reports them.
List<String> _styleWarnings(DocxDocument doc) => doc
    .save()
    .warnings
    .where((DocxWarning w) => w.code == DocxWarningCode.styleNotFound)
    .expand((DocxWarning w) => w.locations)
    .toList();

/// The text of the main part of [bytes].
String _savedMain(Uint8List bytes) =>
    utf8.decode(readXlsxBytes(bytes)['word/document.xml']!);

/// The kinds of the inlines of [paragraph], in order.
List<Type> _kinds(DocxParagraph paragraph) => <Type>[
  for (final DocxInline inline in paragraph.inlines) inline.runtimeType,
];

/// Expects the paragraph of [content] to type no field, to give [text], and
/// to be saved as read after an edit of the paragraph before it.
void _expectRefused(String content, String text) {
  final String before = _p(_r('other'));
  final DocxDocument doc = _open('$before${_p(content)}');
  final DocxParagraph p = doc.body.blocks[1] as DocxParagraph;
  expect(p.inlines.whereType<DocxField>(), isEmpty);
  expect(p.text, text);
  ((doc.body.blocks[0] as DocxParagraph).inlines.single as DocxRun).text =
      'edited';
  expect(
    _savedMain(doc.save().bytes),
    _main('${_p(_r('edited'))}${_p(content)}'),
  );
}

void main() {
  group('a plain field', () {
    test('reads as one DocxField, as Word writes it', () {
      final DocxParagraph p = _first(
        _p('${_r('Page ')}${_page('1')}${_r(' end')}'),
      );
      expect(_kinds(p), <Type>[DocxRun, DocxField, DocxRun]);
      final DocxField field = p.inlines[1] as DocxField;
      expect(field.name, 'PAGE');
      expect(field.instruction, ' PAGE ');
      expect(field.text, '1');
      expect((field.result.single as DocxRun).text, '1');
      expect(p.text, 'Page 1 end');
    });

    test('joins an instruction split over runs and in one run', () {
      final DocxParagraph p = _first(
        _p(
          '$_begin${_instr(' DATE ')}<w:r><w:instrText>\\@ </w:instrText>'
          '<w:instrText>"dd"</w:instrText></w:r>$_separate${_r('07')}$_end',
        ),
      );
      final DocxField field = p.inlines.single as DocxField;
      expect(field.instruction, ' DATE \\@ "dd"');
      expect(field.name, 'DATE');
    });

    test('decodes entities and CDATA in the instruction', () {
      final DocxField field =
          _first(
                _p(
                  '$_begin<w:r><w:instrText>IF a &lt; <![CDATA[b]]>'
                  '</w:instrText></w:r>$_end',
                ),
              ).inlines.single
              as DocxField;
      expect(field.instruction, 'IF a < b');
    });

    test('has an empty result without separate', () {
      final DocxParagraph p = _first(_p('$_begin${_instr('PAGE')}$_end'));
      final DocxField field = p.inlines.single as DocxField;
      expect(field.result, isEmpty);
      expect(field.text, '');
      expect(field.name, 'PAGE');
    });

    test('names the first word in upper case, and nothing without one', () {
      DocxField fieldOf(String instruction) =>
          _first(_p('$_begin${_instr(instruction)}$_end')).inlines.single
              as DocxField;
      expect(fieldOf('  mergefield\tName \\* x').name, 'MERGEFIELD');
      expect(fieldOf('   ').name, isNull);
      expect(
        (_first(_p('$_begin$_end')).inlines.single as DocxField).name,
        null,
      );
    });

    test('a field in a result is a DocxField in the result', () {
      final DocxParagraph p = _first(
        _p(
          '$_begin${_instr('IF x')}$_separate${_r('a')}${_page('2')}'
          '${_r('b')}$_end',
        ),
      );
      final DocxField outer = p.inlines.single as DocxField;
      expect(outer.name, 'IF');
      expect(outer.result, hasLength(3));
      final DocxField inner = outer.result[1] as DocxField;
      expect(inner.name, 'PAGE');
      expect(outer.text, 'a2b');
      expect(p.text, 'a2b');
    });

    test('keeps other inlines in place, in the instruction and the result', () {
      const String proof = '<w:proofErr w:type="spellStart"/>';
      const String mark = '<w:bookmarkStart w:id="1" w:name="b"/>';
      final String content =
          '$_begin$proof${_instr('PAGE')}$mark$_separate$proof${_r('1')}'
          '<w:hyperlink w:anchor="a">${_r('2')}</w:hyperlink>$_end';
      final DocxDocument doc = _open('${_p(_r('x'))}${_p(content)}');
      final DocxParagraph p = doc.body.blocks[1] as DocxParagraph;
      final DocxField field = p.inlines.single as DocxField;
      expect(field.instruction, 'PAGE');
      expect(field.result.map((DocxInline i) => i.runtimeType), <Type>[
        DocxOpaqueInline,
        DocxRun,
        DocxOpaqueInline,
      ]);
      expect(field.text, '12');
      expect(
        _savedMain(doc.save().bytes),
        _main('${_p(_r('x'))}${_p(content)}'),
      );
    });

    test('a complete field in a hyperlink of the result stays typed', () {
      final DocxParagraph p = _first(
        _p(
          '$_begin${_instr('TOC')}$_separate'
          '<w:hyperlink w:anchor="a">${_page('4')}</w:hyperlink>$_end',
        ),
      );
      final DocxField field = p.inlines.single as DocxField;
      expect(field.result.single, isA<DocxOpaqueInline>());
      expect(field.text, '4');
    });

    test('types a field in a cell', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tr><w:tc>${_p(_page('1'))}</w:tc></w:tr></w:tbl>${_p('')}',
      );
      final DocxTable table = doc.body.blocks.first as DocxTable;
      final DocxParagraph p =
          table.rows.single.cells.single.blocks.single as DocxParagraph;
      expect(p.inlines.single, isA<DocxField>());
    });

    test('writes every run with its w:rPr and attributes as read', () {
      const String rPr = '<w:rPr><w:b/><w:noProof/></w:rPr>';
      const String content =
          '<w:r w:rsidR="00A1">$rPr<w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r w:rsidRPr="00A2">$rPr<w:instrText xml:space="preserve"> PAGE '
          '</w:instrText></w:r>'
          '<w:r>$rPr</w:r>'
          '<w:r>$rPr<w:fldChar w:fldCharType="separate"/></w:r>'
          '<w:r>$rPr<w:t>1</w:t></w:r>'
          '<w:r>$rPr<w:fldChar w:fldCharType="end"/></w:r>';
      final DocxDocument doc = _open('${_p(_r('x'))}${_p(content)}');
      final DocxParagraph p = doc.body.blocks[1] as DocxParagraph;
      expect(p.inlines.single, isA<DocxField>());
      ((doc.body.blocks[0] as DocxParagraph).inlines.single as DocxRun).text =
          'y';
      expect(
        _savedMain(doc.save().bytes),
        _main('${_p(_r('y'))}${_p(content)}'),
      );
    });
  });

  group('marks with more on them stay typed', () {
    for (final String mark in <String>[
      '<w:fldChar w:fldCharType="begin" w:fldLock="1"/>',
      '<w:fldChar w:fldCharType="begin" w:dirty="true"/>',
      '<w:fldChar w:fldCharType="begin"><w:fldData>AAAA</w:fldData></w:fldChar>',
    ]) {
      test(mark, () {
        final String content =
            '<w:r>$mark</w:r>${_instr('PAGE')}$_separate${_r('1')}$_end';
        final DocxDocument doc = _open('${_p(_r('x'))}${_p(content)}');
        final DocxParagraph p = doc.body.blocks[1] as DocxParagraph;
        expect(p.inlines.single, isA<DocxField>());
        ((doc.body.blocks[0] as DocxParagraph).inlines.single as DocxRun).text =
            'y';
        expect(
          _savedMain(doc.save().bytes),
          _main('${_p(_r('y'))}${_p(content)}'),
        );
      });
    }
  });

  group('run content', () {
    test('marks and instructions are typed, with no text', () {
      final DocxParagraph p = _first(
        _p('$_begin${_instr(' PAGE ')}$_separate$_end$_end'),
      );
      // The second end has no partner; the first four runs are a field, and
      // the stray mark stays a run with its typed content.
      final DocxRun stray = p.inlines[1] as DocxRun;
      final DocxFieldMark mark = stray.content.single as DocxFieldMark;
      expect(mark.type, DocxFieldMarkType.end);
      expect(stray.text, '');
    });

    test('an instruction with no field is typed content', () {
      final DocxRun run =
          _first(_p(_instr(' PAGE '))).inlines.single as DocxRun;
      final DocxFieldInstruction c = run.content.single as DocxFieldInstruction;
      expect(c.text, ' PAGE ');
      expect(run.text, '');
    });

    test('marks and instructions compare by value', () {
      final DocxRun a = _first(_p(_begin)).inlines.single as DocxRun;
      final DocxRun b = _first(_p(_begin)).inlines.single as DocxRun;
      final DocxRun c = _first(_p(_end)).inlines.single as DocxRun;
      expect(a.content.single, b.content.single);
      expect(a.content.single.hashCode, b.content.single.hashCode);
      expect(a.content.single, isNot(c.content.single));
      final DocxRun d = _first(_p(_instr('x'))).inlines.single as DocxRun;
      final DocxRun e = _first(_p(_instr('x'))).inlines.single as DocxRun;
      expect(d.content.single, e.content.single);
      expect(d.content.single.hashCode, e.content.single.hashCode);
    });

    test('w:delInstrText stays opaque', () {
      final DocxRun run =
          _first(
                _p('<w:r><w:delInstrText>x</w:delInstrText></w:r>'),
              ).inlines.single
              as DocxRun;
      expect(run.content.single, isA<DocxOpaqueRunContent>());
    });

    test('a w:fldChar of no known type stays opaque', () {
      for (final String mark in <String>[
        '<w:fldChar/>',
        '<w:fldChar w:fldCharType="other"/>',
      ]) {
        final DocxRun run =
            _first(_p('<w:r>$mark</w:r>')).inlines.single as DocxRun;
        expect(run.content.single, isA<DocxOpaqueRunContent>());
      }
    });

    test('an instruction past maxTextLength is refused', () {
      final Uint8List bytes = buildDocx(document: _main(_p(_instr('x' * 11))));
      expect(
        () => DocxDocument.open(
          bytes,
          limits: const DocxReadLimits(maxTextLength: 10),
        ).body,
        throwsA(
          isA<DocxReadException>().having(
            (DocxReadException e) => e.reason,
            'reason',
            DocxReadFailure.limitExceeded,
          ),
        ),
      );
    });
  });

  group('a field that is not plain stays runs', () {
    final Map<String, (String, String)> cases = <String, (String, String)>{
      'begin with no end': (
        '$_begin${_instr('PAGE')}$_separate${_r('1')}',
        '1',
      ),
      'end alone': ('${_r('1')}$_end', '1'),
      'separate alone': ('${_r('1')}$_separate${_r('2')}', '12'),
      'two marks in one run': (
        '<w:r><w:fldChar w:fldCharType="begin"/>'
            '<w:fldChar w:fldCharType="separate"/></w:r>'
            '${_instr('PAGE')}${_r('1')}$_end',
        '1',
      ),
      'a begin run with text': (
        '<w:r><w:t>a</w:t><w:fldChar w:fldCharType="begin"/></w:r>'
            '${_instr('PAGE')}$_separate${_r('1')}$_end',
        'a1',
      ),
      'a separate run with text': (
        '$_begin${_instr('PAGE')}'
            '<w:r><w:fldChar w:fldCharType="separate"/><w:t>a</w:t></w:r>'
            '${_r('1')}$_end',
        'a1',
      ),
      'an end run with text': (
        '$_begin${_instr('PAGE')}$_separate${_r('1')}'
            '<w:r><w:t>a</w:t><w:fldChar w:fldCharType="end"/></w:r>',
        '1a',
      ),
      'an instruction run with text': (
        '$_begin<w:r><w:instrText>PAGE</w:instrText><w:t>a</w:t></w:r>'
            '$_separate${_r('1')}$_end',
        'a1',
      ),
      'a run of text in the instruction': (
        '$_begin${_instr('PAGE')}${_r('a')}$_separate${_r('1')}$_end',
        'a1',
      ),
      'a field nested in the instruction': (
        '$_begin${_instr('IF ')}$_begin${_instr('PAGE')}$_separate${_r('1')}'
            '$_end$_separate${_r('2')}$_end',
        '12',
      ),
      'two fields nested in the instruction': (
        '$_begin$_begin${_instr('A')}$_end$_begin${_instr('B')}$_separate'
            '${_r('1')}$_end$_separate${_r('2')}$_end',
        '12',
      ),
      'a field nested in a nested instruction': (
        '$_begin$_begin$_separate$_begin${_instr('A')}$_end$_end$_end',
        '',
      ),
      'two separates': (
        '$_begin${_instr('PAGE')}$_separate${_r('1')}$_separate${_r('2')}$_end',
        '12',
      ),
      'a separate in a hyperlink': (
        '$_begin${_instr('PAGE')}<w:hyperlink w:anchor="a">$_separate'
            '</w:hyperlink>${_r('1')}$_end',
        '1',
      ),
      'an end in a hyperlink': (
        '$_begin${_instr('PAGE')}$_separate${_r('1')}'
            '<w:hyperlink w:anchor="a">$_end</w:hyperlink>',
        '1',
      ),
      'an unbalanced mark in a w:ins of the result': (
        '$_begin${_instr('PAGE')}$_separate${_r('1')}'
            '<w:ins w:id="1" w:author="A">$_end</w:ins>${_r('2')}$_end',
        '12',
      ),
      'a marked up instruction in a w:ins': (
        '$_begin<w:ins w:id="1" w:author="A">${_instr('PAGE')}</w:ins>'
            '$_separate${_r('1')}$_end',
        '1',
      ),
      'text in an inline of the instruction': (
        '$_begin${_instr('PAGE')}<w:ins w:id="1" w:author="A">${_r('a')}'
            '</w:ins>$_separate${_r('1')}$_end',
        'a1',
      ),
      'a w:fldSimple in the instruction': (
        '$_begin<w:fldSimple w:instr="PAGE"/>$_end',
        '',
      ),
      'an instruction in the result': (
        '$_begin${_instr('PAGE')}$_separate${_instr('x')}${_r('1')}$_end',
        '1',
      ),
      'a w:delInstrText in the instruction': (
        '$_begin<w:r><w:delInstrText>x</w:delInstrText></w:r>$_end',
        '',
      ),
      'a begin of no type': (
        '<w:r><w:fldChar/></w:r>${_instr('PAGE')}$_separate${_r('1')}$_end',
        '1',
      ),
      'a separate of an unknown type': (
        '$_begin${_instr('PAGE')}<w:r><w:fldChar w:fldCharType="x"/></w:r>'
            '${_r('1')}$_end',
        '1',
      ),
      'an unknown mark in the result': (
        '$_begin${_instr('PAGE')}$_separate${_r('1')}'
            '<w:r><w:fldChar w:fldCharType="x"/></w:r>${_r('2')}$_end',
        '12',
      ),
      'an end of no type': (
        '$_begin${_instr('PAGE')}$_separate${_r('1')}<w:r><w:fldChar/></w:r>',
        '1',
      ),
    };
    cases.forEach((String name, (String, String) value) {
      test(name, () => _expectRefused(value.$1, value.$2));
    });

    test('a mark keeps its typed content in a run', () {
      final DocxParagraph p = _first(_p('$_begin${_instr('PAGE')}'));
      expect(_kinds(p), <Type>[DocxRun, DocxRun]);
      expect((p.inlines[0] as DocxRun).content.single, isA<DocxFieldMark>());
      expect(
        (p.inlines[1] as DocxRun).content.single,
        isA<DocxFieldInstruction>(),
      );
    });

    test('a field across paragraphs', () {
      final String body =
          '${_p('$_begin${_instr('TOC')}$_separate${_r('a')}')}'
          '${_p(_r('b'))}${_p('${_r('c')}$_end')}';
      final DocxDocument doc = _open('${_p(_r('x'))}$body');
      final Iterable<DocxParagraph> ps = doc.body.blocks
          .whereType<DocxParagraph>();
      expect(ps.expand((p) => p.inlines).whereType<DocxField>(), isEmpty);
      expect(ps.map((p) => p.text), <String>['x', 'a', 'b', 'c']);
      ((doc.body.blocks[0] as DocxParagraph).inlines.single as DocxRun).text =
          'y';
      expect(_savedMain(doc.save().bytes), _main('${_p(_r('y'))}$body'));
    });

    test('a field inside one across paragraphs is typed', () {
      final DocxParagraph p = _first(
        _p('$_begin${_instr('TOC')}$_separate${_page('1')}'),
      );
      expect(_kinds(p), <Type>[DocxRun, DocxRun, DocxRun, DocxField]);
      expect(p.text, '1');
    });

    test('the only end closes the inner of two open fields', () {
      final DocxParagraph p = _first(
        _p(
          '$_begin${_instr('A')}$_separate$_begin${_instr('B')}$_separate'
          '${_r('1')}$_end${_r('2')}',
        ),
      );
      expect(p.inlines.whereType<DocxField>().single.name, 'B');
      expect(p.text, '12');
    });

    test('a field after a refused one is typed', () {
      final DocxParagraph p = _first(_p('$_end${_page('1')}$_end'));
      expect(_kinds(p), <Type>[DocxRun, DocxField, DocxRun]);
    });

    test('a refused field in a result refuses what holds it', () {
      final DocxParagraph p = _first(
        _p(
          '$_begin${_instr('A')}$_separate'
          '<w:r><w:fldChar w:fldCharType="begin"/><w:t>x</w:t></w:r>'
          '$_end$_end',
        ),
      );
      expect(p.inlines.whereType<DocxField>(), isEmpty);
      expect(p.text, 'x');
    });
  });

  group('marks inside an opaque inline', () {
    test('stay in it, and a whole field there is no DocxField', () {
      final String content =
          '<w:hyperlink w:anchor="a">${_page('4')}</w:hyperlink>';
      _expectRefused(content, '4');
      final DocxParagraph p = _first(_p(content));
      expect(p.inlines.single, isA<DocxOpaqueInline>());
    });

    test('do not touch a field after them', () {
      final DocxParagraph p = _first(
        _p('<w:hyperlink w:anchor="a">$_begin</w:hyperlink>${_page('1')}'),
      );
      expect(_kinds(p), <Type>[DocxOpaqueInline, DocxField]);
    });
  });

  group('nesting', () {
    test(
      'a field past maxFieldNesting stays runs, and so does nothing else',
      () {
        String nest(int levels) =>
            '${'$_begin${_instr('A')}$_separate' * levels}${_r('x')}'
            '${_end * levels}';
        DocxField? deepest(DocxInline inline) {
          DocxField? at = inline is DocxField ? inline : null;
          while (at != null) {
            final DocxField? next = at.result
                .whereType<DocxField>()
                .firstOrNull;
            if (next == null) break;
            at = next;
          }
          return at;
        }

        int depth(DocxField field) {
          int levels = 1;
          for (
            DocxField? at = field.result.whereType<DocxField>().firstOrNull;
            at != null;
            at = at.result.whereType<DocxField>().firstOrNull
          ) {
            levels++;
          }
          return levels;
        }

        final DocxParagraph fits = _first(_p(nest(maxFieldNesting)));
        expect(depth(fits.inlines.single as DocxField), maxFieldNesting);
        expect(fits.text, 'x');

        final DocxParagraph past = _first(_p(nest(maxFieldNesting + 1)));
        final DocxField field = past.inlines.single as DocxField;
        expect(depth(field), maxFieldNesting);
        expect(deepest(field)!.result.whereType<DocxRun>(), hasLength(5));
        expect(past.text, 'x');
      },
    );

    test('a hundred thousand levels open, read and save as read', () {
      const int levels = 100000;
      final String content =
          '${'$_begin$_separate' * levels}${_r('x')}${_end * levels}';
      final DocxDocument doc = _open(_p(content));
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      expect(p.text, 'x');
      p.addRun('y');
      expect(_savedMain(doc.save().bytes), _main(_p('$content${_r('y')}')));
    });

    test(
      'many open fields and broken marks cost no more than their number',
      () {
        const int count = 50000;
        const String broken =
            '<w:r><w:fldChar w:fldCharType="end"/><w:t>a</w:t></w:r>'
            '<w:r><w:fldChar w:fldCharType="begin"/><w:t>b</w:t></w:r>';
        final DocxParagraph p = _first(
          _p('${_begin * count}${broken * count}'),
        );
        expect(p.text, 'ab' * count);
      },
    );
  });

  group('the runs of a field', () {
    /// The body of [_edited]: the paragraph, then a `PAGE` field in another.
    String body(String style) => _p(
      '${_r('a')}$_begin${_instr('PAGE')}$_separate'
      '<w:r><w:rPr><w:rStyle w:val="$style"/></w:rPr><w:t>1</w:t></w:r>$_end',
    );

    test('report to the paragraph, and undo', () {
      final DocxDocument doc = _open(body('X'));
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      final DocxField field = p.inlines[1] as DocxField;
      final DocxRun run = field.result.single as DocxRun;
      expect(paragraphOf(run), same(p));
      run.text = '9';
      expect(field.text, '9');
      expect(p.text, 'a9');
      expect(changeLogOf(doc).hasChanges, isTrue);
      expect(_savedMain(doc.save().bytes), contains('<w:t>9</w:t>'));
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => run.properties.bold = true);
      changeLogOf(doc).revertSet(set);
      expect(run.properties.bold, isNull);
    });

    test('removing a field detaches every run; inserting attaches them', () {
      final DocxDocument doc = _open(body('X'));
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      final DocxField field = p.inlines[1] as DocxField;
      final DocxRun run = field.result.single as DocxRun;
      p.removeInlineAt(1);
      expect(paragraphOf(field), isNull);
      expect(paragraphOf(run), isNull);
      expect(p.text, 'a');
      expect(changeLogOf(doc).hasChanges, isTrue);

      // Detached, its edits report to nothing.
      run.text = '2';
      expect(field.text, '2');

      p.insertInline(0, field);
      expect(paragraphOf(run), same(p));
      expect(p.text, '2a');
      final DocxParagraph other = DocxParagraph();
      expect(() => other.insertInline(0, field), throwsStateError);
    });

    test('undoing the removal of a field puts its runs back', () {
      final DocxDocument doc = _open(body('X'));
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      final DocxField field = p.inlines[1] as DocxField;
      final String input = _savedMain(doc.save().bytes);
      final ChangeSet set = editsOf(doc).transaction(() => p.removeInlineAt(1));
      expect(paragraphOf(field.result.single), isNull);
      changeLogOf(doc).revertSet(set);
      expect(paragraphOf(field.result.single), same(p));
      expect(_savedMain(doc.save().bytes), input);
    });

    test('a run of a field cannot go in a paragraph on its own', () {
      final DocxParagraph p = _first(_p(_page('1')));
      final DocxField field = p.inlines.single as DocxField;
      final DocxInline run = field.result.single;
      final DocxParagraph other = DocxParagraph();
      expect(() => other.insertInline(0, run), throwsStateError);
      p.removeInlineAt(0);
      expect(() => other.insertInline(0, run), throwsStateError);
      expect(other.inlines, isEmpty);
    });

    test('a field in a result moves with what holds it', () {
      final DocxParagraph p = _first(
        _p('$_begin${_instr('A')}$_separate${_page('1')}$_end'),
      );
      final DocxField outer = p.inlines.single as DocxField;
      final DocxField inner = outer.result.single as DocxField;
      expect(paragraphOf(inner.result.single), same(p));
      p.removeInlineAt(0);
      expect(paragraphOf(inner), isNull);
      expect(paragraphOf(inner.result.single), isNull);
    });

    test('the result cannot be modified', () {
      final DocxField field =
          _first(_p(_page('1'))).inlines.single as DocxField;
      expect(() => field.result.removeLast(), throwsUnsupportedError);
    });

    test('a style read in another document counts as set when moved', () {
      final DocxDocument from = _open(body('Gone'));
      final DocxParagraph moved = from.body.blocks.first as DocxParagraph;
      from.body.removeBlockAt(0);
      final DocxDocument other = _styled(_p(''));
      other.body.insertBlock(1, moved);
      expect(_styleWarnings(other), <String>['body/p[1]/r[4]']);
    });

    test('moving a field of a run keeps its style check', () {
      final DocxDocument from = _open(body('Gone'));
      final DocxParagraph p = from.body.blocks.first as DocxParagraph;
      final DocxField field = p.inlines[1] as DocxField;
      p.removeInlineAt(1);
      final DocxDocument other = _styled(_p(''));
      (other.body.blocks.first as DocxParagraph).insertInline(0, field);
      expect(_styleWarnings(other), <String>['body/p[0]/r[3]']);
    });

    test('a style set on a result run resolves against the document', () {
      final DocxDocument doc = _styled(_p(_page('1')));
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      final DocxRun run =
          (p.inlines.single as DocxField).result.single as DocxRun;
      run.style = 'NoSuchStyle';
      expect(_styleWarnings(doc), <String>['body/p[0]/r[3]']);
    });

    test('a warning keeps the location of the run as read', () {
      final DocxDocument doc = _open(
        _p(
          '${_r('a')}$_begin${_instr('PAGE')}$_separate${_r('1')}$_end${_r('b')}',
        ),
      );
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      ((p.inlines[1] as DocxField).result.single as DocxRun).text = 'x\u0001';
      (p.inlines[2] as DocxRun).text = 'y\u0001';
      expect(doc.save().warnings.single.locations, <String>[
        'body/p[0]/r[4]',
        'body/p[0]/r[6]',
      ]);
    });
  });
}
