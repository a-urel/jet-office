// Tests the template fill of decision 0024 (T1, values): `{{}}` tags and
// MERGEFIELDs in the body, tables, headers and footers, the warnings for what
// cannot be filled, one change set per fill, and the listing of a template's
// tags. Every fill is saved and reopened. Documents are built in memory, so
// the tests run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/docx/template/fill.dart';
import 'package:jet_office/src/docx/template/tag_scanner.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../support/docx_builder.dart';
import '../support/styles_documents.dart' show readDocxText;
import '../support/template_documents.dart';

const String _main = '/word/document.xml';

String _run(String text, {String rPr = ''}) =>
    '<w:r>${rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>'}'
    '<w:t xml:space="preserve">$text</w:t></w:r>';

String _p(String inner) => '<w:p>$inner</w:p>';

String _table(String cellContent) =>
    '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid>'
    '<w:gridCol w:w="4000"/></w:tblGrid><w:tr><w:tc><w:tcPr>'
    '<w:tcW w:w="4000" w:type="dxa"/></w:tcPr>$cellContent</w:tc></w:tr>'
    '</w:tbl>';

/// A complex field of [instruction] with the cached [result], every run of
/// it with the run properties [rPr].
String _complexField(String instruction, String result, {String rPr = ''}) {
  final String props = rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>';
  return '<w:r>$props<w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r>$props<w:instrText xml:space="preserve">$instruction'
      '</w:instrText></w:r>'
      '<w:r>$props<w:fldChar w:fldCharType="separate"/></w:r>'
      '<w:r>$props<w:t>$result</w:t></w:r>'
      '<w:r>$props<w:fldChar w:fldCharType="end"/></w:r>';
}

String _documentXml(String body, {String sectPr = ''}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">'
    '<w:body>$body$sectPr</w:body></w:document>';

/// A document of [body] with a header and a footer part of one paragraph
/// each, [header] and [footer], and a footnotes part of [footnote] when
/// given.
Uint8List _withStories(
  String body, {
  String header = '',
  String footer = '',
  String? footnote,
}) => buildDocx(
  document: _documentXml(
    body,
    sectPr:
        '<w:sectPr><w:headerReference w:type="default" r:id="rId11"/>'
        '<w:footerReference w:type="default" r:id="rId12"/>'
        '<w:pgSz w:w="11906" w:h="16838"/></w:sectPr>',
  ),
  extra: <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$contentTypesNs">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="${ContentType.wmlDocument}"/>'
      '<Override PartName="/word/header1.xml" '
      'ContentType="${ContentType.wmlHeader}"/>'
      '<Override PartName="/word/footer1.xml" '
      'ContentType="${ContentType.wmlFooter}"/>'
      '<Override PartName="/word/footnotes.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>'
      '</Types>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">'
      '<Relationship Id="rId11" Type="${RelType.header}" '
      'Target="header1.xml"/>'
      '<Relationship Id="rId12" Type="${RelType.footer}" '
      'Target="footer1.xml"/>'
      '${footnote == null ? '' : '<Relationship Id="rId13" '
                'Type="${RelType.footnotes}" Target="footnotes.xml"/>'}'
      '</Relationships>',
    ),
    'word/header1.xml': utf8.encode(
      '<w:hdr xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">${_p(header)}</w:hdr>',
    ),
    'word/footer1.xml': utf8.encode(
      '<w:ftr xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">${_p(footer)}</w:ftr>',
    ),
    if (footnote != null)
      'word/footnotes.xml': utf8.encode(
        '<w:footnotes xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">'
        '<w:footnote w:id="1">${_p(footnote)}</w:footnote></w:footnotes>',
      ),
  },
);

DocxDocument _open(Uint8List bytes) => DocxDocument.open(bytes);

DocxDocument _reopen(DocxDocument doc) => DocxDocument.open(doc.save().bytes);

/// The texts of the body's top-level paragraphs.
List<String> _texts(DocxDocument doc) => <String>[
  for (final DocxBlock b in doc.body.blocks)
    if (b is DocxParagraph) b.text,
];

DocxParagraph _firstParagraph(DocxDocument doc) =>
    doc.body.blocks.whereType<DocxParagraph>().first;

/// The one warning of [code] in [warnings].
DocxWarning _one(List<DocxWarning> warnings, DocxWarningCode code) {
  final List<DocxWarning> found = warnings
      .where((DocxWarning w) => w.code == code)
      .toList();
  expect(found, hasLength(1), reason: '$code in $warnings');
  return found.single;
}

List<DocxWarningCode> _codes(List<DocxWarning> warnings) => <DocxWarningCode>[
  for (final DocxWarning w in warnings) w.code,
];

const FillSettings _en = FillSettings();
const FillSettings _tr = FillSettings(locale: FormatLocale.trTR);

void main() {
  group('fillTemplate: stories', () {
    test('fills the body, a cell, a nested cell, a header and a footer', () {
      final DocxDocument doc = _open(
        _withStories(
          _p(wordSplitTag('{{ad}}')) +
              _table(_p(_run('{{ad}}')) + _table(_p(_run('x {{ad}} y')))) +
              _p(''),
          header: _run('H {{ad}}'),
          footer: wordSplitTag('{{ad}}'),
        ),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'ad': 'Ayşe',
      }, _en);
      expect(warnings, isEmpty);
      final DocxDocument saved = _reopen(doc);
      expect(_texts(saved).first, 'Ayşe');
      final DocxTable outer = saved.body.blocks.whereType<DocxTable>().first;
      final DocxTableCell cell = outer.rows.first.cells.first;
      expect((cell.blocks.first as DocxParagraph).text, 'Ayşe');
      final DocxTable inner = cell.blocks.whereType<DocxTable>().single;
      expect(
        (inner.rows.first.cells.first.blocks.first as DocxParagraph).text,
        'x Ayşe y',
      );
      final DocxSection section = saved.sections.first;
      expect((section.header.blocks.first as DocxParagraph).text, 'H Ayşe');
      expect((section.footer.blocks.first as DocxParagraph).text, 'Ayşe');
    });

    test('a format code and a locale', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[_run('{{tutar:#,##0.00 ₺}}')]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'tutar': FormatDecimal('1234.56'),
      }, _tr);
      expect(warnings, isEmpty);
      expect(_texts(_reopen(doc)), <String>['1.234,56 ₺']);
    });

    test('a dotted path walks maps', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[wordSplitTag('{{musteri.unvan}}')]),
      );
      fillTemplate(doc, <String, Object?>{
        'musteri': <String, Object?>{'unvan': 'Acme A.Ş.'},
      }, _en);
      expect(_texts(_reopen(doc)), <String>['Acme A.Ş.']);
    });

    test('a value with {{ is not filled again', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          _run('{{a}} ') + _complexField(' MERGEFIELD b ', '«b»') + _run(''),
        ]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'a': '{{b}}',
        'b': '{{a}}',
      }, _en);
      expect(warnings, isEmpty);
      expect(_texts(_reopen(doc)), <String>['{{b}} {{a}}']);
    });
  });

  group('fillTemplate: missing and not text', () {
    test('a missing value stays and warns', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[_run('A {{yok}} B')]),
      );
      final List<DocxWarning> warnings = fillTemplate(
        doc,
        <String, Object?>{},
        _en,
      );
      final DocxWarning w = _one(
        warnings,
        DocxWarningCode.templateValueMissing,
      );
      expect(warnings, hasLength(1));
      expect(w.detail, '{{yok}}');
      expect(w.part, _main);
      expect(w.locations, <String>['body/p[0]']);
      expect(_texts(_reopen(doc)), <String>['A {{yok}} B']);
    });

    test('removeMissing removes it and still warns', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[_run('A {{yok}} B')]),
      );
      final List<DocxWarning> warnings = fillTemplate(
        doc,
        <String, Object?>{},
        const FillSettings(removeMissing: true),
      );
      _one(warnings, DocxWarningCode.templateValueMissing);
      expect(_texts(_reopen(doc)), <String>['A  B']);
    });

    test('a list is not text', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[_run('{{liste}}')]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'liste': <Object?>[1, 2],
      }, _en);
      expect(
        _one(warnings, DocxWarningCode.templateValueNotText).detail,
        '{{liste}}',
      );
      expect(_texts(_reopen(doc)), <String>['{{liste}}']);
    });

    test('{{.}} at the root is the root map, not text', () {
      final DocxDocument doc = _open(templateDocument(<String>[_run('{{.}}')]));
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'a': 1,
      }, _en);
      _one(warnings, DocxWarningCode.templateValueNotText);
      expect(_texts(_reopen(doc)), <String>['{{.}}']);
    });

    test('a format warning still fills', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[_run('{{n:[Red}}')]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'n': 1.5,
      }, _en);
      expect(
        _one(warnings, DocxWarningCode.templateFormatWarning).detail,
        '{{n:[Red}}',
      );
      expect(_texts(_reopen(doc)).single, isNot(contains('{{')));
    });

    test('section tags stay, each warned, the value inside filled', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          _run('{{#kalemler}}'),
          _run('{{ad}}'),
          _run('{{/kalemler}}'),
        ]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'ad': 'Ayşe',
        'kalemler': <Object?>[],
      }, _en);
      expect(_codes(warnings), <DocxWarningCode>[
        DocxWarningCode.templateSectionMalformed,
        DocxWarningCode.templateSectionMalformed,
      ]);
      expect(warnings.map((DocxWarning w) => w.detail), <String>[
        '{{#kalemler}}',
        '{{/kalemler}}',
      ]);
      expect(warnings.last.locations, <String>['body/p[2]']);
      expect(_texts(_reopen(doc)), <String>[
        '{{#kalemler}}',
        'Ayşe',
        '{{/kalemler}}',
      ]);
    });
  });

  group('fillTemplate: tags that cannot be filled', () {
    final Map<String, Object?> data = <String, Object?>{'a': 'X', 'ab': 'Y'};

    test('across a tab', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[tagAroundTab()]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, data, _en);
      expect(
        _one(warnings, DocxWarningCode.templateTagMalformed).detail,
        '{{a￼b}}',
      );
      expect(_texts(_reopen(doc)), <String>['{{a\tb}}']);
    });

    test('inside w:ins', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[tagInInsertion('{{a}}')]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, data, _en);
      expect(
        _one(warnings, DocxWarningCode.templatePlaceholderInRevision).detail,
        '{{a}}',
      );
      expect(_texts(_reopen(doc)), <String>['{{a}}']);
    });

    test('inside an inline w:sdt', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[tagInInlineSdt('{{a}}')]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, data, _en);
      _one(warnings, DocxWarningCode.templatePlaceholderInContentControl);
      expect(_texts(_reopen(doc)), <String>['{{a}}']);
    });

    test('in a PAGE result', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[tagInFieldResult('{{a}}')]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, data, _en);
      _one(warnings, DocxWarningCode.templateTagMalformed);
      expect(_texts(_reopen(doc)), <String>['{{a}}']);
    });

    test('an unclosed tag', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[_run('{{a {{a}}')]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, data, _en);
      expect(
        _one(warnings, DocxWarningCode.templateTagMalformed).detail,
        '{{a ',
      );
      expect(_texts(_reopen(doc)), <String>['{{a X']);
    });
  });

  group('fillTemplate: merge fields', () {
    test('MERGEFORMAT is silent', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          _complexField(
            ' MERGEFIELD "Müşteri Adı" \\* MERGEFORMAT ',
            '«Müşteri Adı»',
            rPr: '<w:i/>',
          ),
        ]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'Müşteri Adı': 'Ayşe Yılmaz',
      }, _en);
      expect(warnings, isEmpty);
      final DocxDocument saved = _reopen(doc);
      final DocxParagraph p = _firstParagraph(saved);
      expect(p.inlines, hasLength(1));
      final DocxRun run = p.inlines.single as DocxRun;
      expect(run.text, 'Ayşe Yılmaz');
      expect(run.properties.italic, isTrue);
      final String xml = readDocxText(doc.save().bytes)['word/document.xml']!;
      expect(xml, isNot(contains('fldChar')));
      expect(xml, isNot(contains('instrText')));
    });

    test('a date picture', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          _complexField(' MERGEFIELD Tarih \\@ "dd.MM.yyyy" ', '«Tarih»'),
        ]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'Tarih': DateTime(2026, 11, 14),
      }, _en);
      expect(warnings, isEmpty);
      expect(_texts(_reopen(doc)), <String>['14.11.2026']);
    });

    test('a number picture in the fill locale\'s separators', () {
      Uint8List template(String picture) => templateDocument(<String>[
        _complexField(' MERGEFIELD Tutar \\# "$picture" ', '«Tutar»'),
      ]);
      final Map<String, Object?> data = <String, Object?>{
        'Tutar': FormatDecimal('1234.56'),
      };
      final DocxDocument tr = _open(template('#.##0,00'));
      expect(fillTemplate(tr, data, _tr), isEmpty);
      expect(_texts(_reopen(tr)), <String>['1.234,56']);
      final DocxDocument en = _open(template('#,##0.00'));
      expect(fillTemplate(en, data, _en), isEmpty);
      expect(_texts(_reopen(en)), <String>['1,234.56']);
    });

    test('text before and after, only around a value', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          _complexField(' MERGEFIELD Ad \\b "Sayın " \\f "," ', '«Ad»'),
          _complexField(' MERGEFIELD Ad \\b "Sayın " ', '«Ad»'),
        ]),
      );
      fillTemplate(doc, <String, Object?>{'Ad': ''}, _en);
      expect(_texts(_reopen(doc)), <String>['', '']);
      final DocxDocument other = _open(
        templateDocument(<String>[
          _complexField(' MERGEFIELD Ad \\b "Sayın " \\f "," ', '«Ad»'),
        ]),
      );
      fillTemplate(other, <String, Object?>{'Ad': 'Ayşe'}, _en);
      expect(_texts(_reopen(other)), <String>['Sayın Ayşe,']);
    });

    test('casing with the locale', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          _complexField(' MERGEFIELD Ad \\* Upper ', '«Ad»'),
        ]),
      );
      fillTemplate(doc, <String, Object?>{'Ad': 'istanbul'}, _tr);
      expect(_texts(_reopen(doc)), <String>['İSTANBUL']);
    });

    test('an unsupported switch fills and warns', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          _complexField(' MERGEFIELD Ad \\v ', '«Ad»'),
        ]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'Ad': 'Ayşe',
      }, _en);
      final DocxWarning w = _one(
        warnings,
        DocxWarningCode.templateSwitchUnsupported,
      );
      expect(w.detail, ' MERGEFIELD Ad \\v ');
      expect(_texts(_reopen(doc)), <String>['Ayşe']);
    });

    test('a missing merge field stays, or goes with removeMissing', () {
      final String field = _complexField(' MERGEFIELD Yok ', '«Yok»');
      final DocxDocument doc = _open(templateDocument(<String>[field]));
      final List<DocxWarning> warnings = fillTemplate(
        doc,
        <String, Object?>{},
        _en,
      );
      expect(
        _one(warnings, DocxWarningCode.templateValueMissing).detail,
        ' MERGEFIELD Yok ',
      );
      expect(_texts(_reopen(doc)), <String>['«Yok»']);
      final DocxDocument removed = _open(templateDocument(<String>[field]));
      final List<DocxWarning> again = fillTemplate(
        removed,
        <String, Object?>{},
        const FillSettings(removeMissing: true),
      );
      _one(again, DocxWarningCode.templateValueMissing);
      final DocxDocument saved = _reopen(removed);
      expect(_texts(saved), <String>['']);
      expect(_firstParagraph(saved).inlines, isEmpty);
    });

    test('a w:fldSimple takes its inner run properties', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          '<w:fldSimple w:instr=" MERGEFIELD Ad "><w:r><w:rPr><w:b/></w:rPr>'
              '<w:t>«Ad»</w:t></w:r></w:fldSimple>',
        ]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'Ad': 'Ayşe',
      }, _en);
      expect(warnings, isEmpty);
      final DocxParagraph p = _firstParagraph(_reopen(doc));
      expect(p.inlines, hasLength(1));
      final DocxRun run = p.inlines.single as DocxRun;
      expect(run.text, 'Ayşe');
      expect(run.properties.bold, isTrue);
    });

    test('a merge field in a hyperlink is filled there', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          '<w:hyperlink w:anchor="x">'
              '${_complexField(' MERGEFIELD Ad ', '«Ad»')}</w:hyperlink>',
        ]),
      );
      expect(fillTemplate(doc, <String, Object?>{'Ad': 'Ayşe'}, _en), isEmpty);
      final DocxParagraph p = _firstParagraph(_reopen(doc));
      expect(p.text, 'Ayşe');
      expect(p.inlines.single, isA<DocxHyperlink>());
    });

    test('a MERGEFIELD inside an IF instruction is not typed', () {
      const String nested =
          '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r><w:instrText xml:space="preserve"> IF </w:instrText></w:r>'
          '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r><w:instrText xml:space="preserve"> MERGEFIELD Ad '
          '</w:instrText></w:r>'
          '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
          '<w:r><w:t>«Ad»</w:t></w:r>'
          '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
          '<w:r><w:instrText xml:space="preserve"> = "x" "a" "b" '
          '</w:instrText></w:r>'
          '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
          '<w:r><w:t>b</w:t></w:r>'
          '<w:r><w:fldChar w:fldCharType="end"/></w:r>';
      final DocxDocument doc = _open(templateDocument(<String>[nested]));
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'Ad': 'Ayşe',
      }, _en);
      expect(
        _one(warnings, DocxWarningCode.templateFieldNotTyped).detail,
        ' MERGEFIELD Ad ',
      );
      expect(warnings, hasLength(1));
      final String xml = readDocxText(doc.save().bytes)['word/document.xml']!;
      expect(xml, contains(' MERGEFIELD Ad '));
      expect(xml, isNot(contains('Ayşe')));
    });

    test('loose instruction runs are not typed', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          '<w:r><w:instrText xml:space="preserve"> MERGEFIELD Ad '
              '</w:instrText></w:r>${_run('«Ad»')}',
        ]),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'Ad': 'Ayşe',
      }, _en);
      _one(warnings, DocxWarningCode.templateFieldNotTyped);
      expect(_texts(_reopen(doc)), <String>['«Ad»']);
    });
  });

  group('fillTemplate: opaque content and parts', () {
    test('a text box and a footnote are warned, not changed', () {
      final DocxDocument doc = _open(
        _withStories(
          _p('<w:r>${textBoxDrawing(<String>['{{logo}}'])}</w:r>') + _p(''),
          footnote: _run('{{not}}'),
        ),
      );
      final Uint8List before = doc.save().bytes;
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'logo': 'L',
        'not': 'N',
      }, _en);
      expect(_codes(warnings), <DocxWarningCode>[
        DocxWarningCode.templatePlaceholderNotTyped,
        DocxWarningCode.templatePlaceholderNotTyped,
      ]);
      expect(warnings.first.detail, '{{logo}}');
      expect(warnings.first.part, _main);
      expect(warnings.first.locations, <String>['body/p[0]']);
      expect(warnings.last.detail, '{{not}}');
      expect(warnings.last.part, '/word/footnotes.xml');
      final Map<String, String> was = readDocxText(before);
      final Map<String, String> now = readDocxText(doc.save().bytes);
      expect(now['word/document.xml'], was['word/document.xml']);
      expect(now['word/footnotes.xml'], was['word/footnotes.xml']);
    });

    test('a block content control is warned as one', () {
      final DocxDocument doc = _open(
        buildDocx(
          document: _documentXml(
            '<w:sdt><w:sdtContent>${_p(_run('{{a}}'))}</w:sdtContent>'
            '</w:sdt>${_p('')}',
          ),
        ),
      );
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'a': 'X',
      }, _en);
      expect(
        _one(
          warnings,
          DocxWarningCode.templatePlaceholderInContentControl,
        ).detail,
        '{{a}}',
      );
    });
  });

  group('fillTemplate: untrusted opaque content', () {
    const String nestedInstruction =
        '<w:r><w:instrText><w:instrText>a</w:instrText>b</w:instrText></w:r>';

    test('a nested w:instrText in a footnote does not throw', () {
      Uint8List bytes() => _withStories(
        _p(''),
        footnote: '$nestedInstruction${_run('{{not}}')}',
      );
      final List<FoundTag> tags = listTemplateTags(_open(bytes()));
      expect(tags.map((FoundTag t) => t.text), <String>['{{not}}']);
      final List<DocxWarning> warnings = fillTemplate(
        _open(bytes()),
        <String, Object?>{},
        _en,
      );
      expect(
        _one(warnings, DocxWarningCode.templatePlaceholderNotTyped).detail,
        '{{not}}',
      );
    });

    test('a nested w:instrText in a body text box does not throw', () {
      Uint8List bytes() => templateDocument(<String>[
        '<w:r>${textBoxDrawing(<String>['{{logo}}']).replaceFirst('<w:r><w:t>{{logo}}', '$nestedInstruction<w:r><w:t>{{logo}}')}</w:r>',
      ]);
      final List<FoundTag> tags = listTemplateTags(_open(bytes()));
      expect(tags.map((FoundTag t) => t.text), <String>['{{logo}}']);
      final List<DocxWarning> warnings = fillTemplate(
        _open(bytes()),
        <String, Object?>{'logo': 'L'},
        _en,
      );
      expect(
        _one(warnings, DocxWarningCode.templatePlaceholderNotTyped).detail,
        '{{logo}}',
      );
    });

    test('a text box in a w:ins with visible text is reported', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[
          '<w:ins w:id="1" w:author="Ada" w:date="2026-01-01T00:00:00Z">'
              '${_run('abc')}<w:r>${textBoxDrawing(<String>['{{x}}'])}</w:r>'
              '</w:ins>',
        ]),
      );
      final List<FoundTag> tags = listTemplateTags(doc);
      expect(tags.map((FoundTag t) => t.text), <String>['{{x}}']);
      expect(tags.single.problem, DocxWarningCode.templatePlaceholderNotTyped);
      final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
        'x': 'X',
      }, _en);
      expect(warnings, hasLength(1));
      expect(
        _one(warnings, DocxWarningCode.templatePlaceholderNotTyped).detail,
        '{{x}}',
      );
      expect(_texts(_reopen(doc)), <String>['abc']);
    });

    test('a tag in the visible text of a w:ins is reported once', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[tagInInsertion('{{a}}')]),
      );
      final List<FoundTag> tags = listTemplateTags(doc);
      expect(tags, hasLength(1));
      expect(
        tags.single.problem,
        DocxWarningCode.templatePlaceholderInRevision,
      );
    });
  });

  group('fillTemplate: transaction', () {
    test('a data error changes nothing and records nothing', () {
      final DocxDocument doc = _open(templateDocument(<String>[_run('{{a}}')]));
      expect(
        () => fillTemplate(doc, <String, Object?>{'a': Object()}, _en),
        throwsArgumentError,
      );
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(lastFillChangeSet(doc), isNull);
      expect(_texts(doc), <String>['{{a}}']);
    });

    test('one fill is one change set, undone whole', () {
      final DocxDocument doc = _open(
        templateDocument(<String>[_run('{{a}} {{b}}'), wordSplitTag('{{c}}')]),
      );
      expect(changeLogOf(doc).hasChanges, isFalse);
      fillTemplate(doc, <String, Object?>{'a': 'A', 'b': 'B', 'c': 'C'}, _en);
      expect(changeLogOf(doc).hasChanges, isTrue);
      expect(_texts(doc), <String>['A B', 'C']);
      final ChangeSet? set = lastFillChangeSet(doc);
      expect(set, isNotNull);
      expect(set!.isEmpty, isFalse);
      changeLogOf(doc).undo(set);
      expect(_texts(doc), <String>['{{a}} {{b}}', '{{c}}']);
      expect(_texts(_reopen(doc)), <String>['{{a}} {{b}}', '{{c}}']);
    });
  });

  group('listTemplateTags', () {
    test('lists every tag in reading order without changing anything', () {
      final DocxDocument doc = _open(
        _withStories(
          _p(_run('{{a:0.00}}')) +
              _p(_run('{{#s}}{{b}}{{/s}}')) +
              _p(_run('{{x')) +
              _table(_p(_complexField(' MERGEFIELD Ad \\* Upper ', '«Ad»'))) +
              _p(''),
          header: wordSplitTag('{{firma.ad}}'),
        ),
      );
      final List<FoundTag> tags = listTemplateTags(doc);
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(tags.map((FoundTag t) => t.text), <String>[
        '{{a:0.00}}',
        '{{#s}}',
        '{{b}}',
        '{{/s}}',
        '{{x',
        ' MERGEFIELD Ad \\* Upper ',
        '{{firma.ad}}',
      ]);
      expect(tags.map((FoundTag t) => t.kind), <TagKind?>[
        TagKind.value,
        TagKind.section,
        TagKind.value,
        TagKind.sectionEnd,
        null,
        null,
        TagKind.value,
      ]);
      expect(tags.map((FoundTag t) => t.mergeField), <bool>[
        false,
        false,
        false,
        false,
        false,
        true,
        false,
      ]);
      expect(tags.map((FoundTag t) => t.problem), <DocxWarningCode?>[
        null,
        DocxWarningCode.templateSectionMalformed,
        null,
        DocxWarningCode.templateSectionMalformed,
        DocxWarningCode.templateTagMalformed,
        null,
        null,
      ]);
      expect(tags.map((FoundTag t) => t.depth), <int>[0, 0, 1, 0, 0, 0, 0]);
      expect(tags.first.format, '0.00');
      expect(tags.first.path, <String>['a']);
      expect(tags[5].path, <String>['Ad']);
      expect(tags.last.path, <String>['firma', 'ad']);
      expect(tags.map((FoundTag t) => t.part), <String>[
        _main,
        _main,
        _main,
        _main,
        _main,
        _main,
        '/word/header1.xml',
      ]);
      expect(tags.map((FoundTag t) => t.location), <String>[
        'body/p[0]',
        'body/p[1]',
        'body/p[1]',
        'body/p[1]',
        'body/p[2]',
        'body/tbl[0]/tr[0]/tc[0]/p[0]',
        'header1.xml/p[0]',
      ]);
    });

    test('lists opaque and part placeholders as not typed', () {
      final DocxDocument doc = _open(
        _withStories(
          _p('<w:r>${textBoxDrawing(<String>['{{logo}}'])}</w:r>') + _p(''),
          footnote: _run('{{not}}'),
        ),
      );
      final List<FoundTag> tags = listTemplateTags(doc);
      expect(tags.map((FoundTag t) => t.text), <String>['{{logo}}', '{{not}}']);
      expect(
        tags.map((FoundTag t) => t.problem),
        everyElement(DocxWarningCode.templatePlaceholderNotTyped),
      );
      expect(tags.last.part, '/word/footnotes.xml');
      expect(tags.last.location, isNull);
    });
  });
}
