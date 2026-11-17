// Tests the section fill of the template (T2 plan Rulings 1, 5, 6, 10 to 16,
// 19, 21 and 22): repeated rows and blocks, conditions, scopes, nesting,
// missing and malformed sections, annotations, locations in copies, the
// limits, one change set, merge fields in copies, tags in a loose field's
// result, and the listing. Documents are built in memory, filled, saved and
// reopened, so the tests run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart' show changeLogOf;
import 'package:jet_office/src/docx/template/fill.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../support/read_xlsx.dart';
import '../support/template_documents.dart';

String _p(String text, {String rPr = ''}) =>
    templateParagraph(templateRun(text, rPr: rPr));

String _tc(String inner, {String tcPr = ''}) =>
    '<w:tc>${tcPr.isEmpty ? '' : '<w:tcPr>$tcPr</w:tcPr>'}$inner</w:tc>';

String _tr(List<String> cells, {String trPr = ''}) =>
    '<w:tr>${trPr.isEmpty ? '' : '<w:trPr>$trPr</w:trPr>'}${cells.join()}'
    '</w:tr>';

String _tbl(List<String> rows, {int columns = 1}) =>
    '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid>'
    '${'<w:gridCol w:w="3000"/>' * columns}</w:tblGrid>${rows.join()}</w:tbl>';

Uint8List _bytes(String body, {String header = '', String footer = ''}) =>
    templateWithStories(
      body: body,
      header: header.isEmpty ? _p('') : header,
      footer: footer.isEmpty ? _p('') : footer,
    );

const FillSettings _turkish = FillSettings(locale: FormatLocale.trTR);

/// Fills [body] with [data]; the warnings and the body's lines (a table row
/// as its cells' texts joined by a tab) after a save and a reopen.
({List<DocxWarning> warnings, List<String> lines, DocxDocument doc}) _fill(
  String body,
  Map<String, Object?> data, {
  FillSettings settings = _turkish,
}) {
  final DocxDocument doc = DocxDocument.open(_bytes(body));
  final List<DocxWarning> warnings = fillTemplate(doc, data, settings);
  return (warnings: warnings, lines: _lines(doc), doc: doc);
}

List<String> _lines(DocxDocument doc) {
  final DocxDocument reopened = DocxDocument.open(doc.save().bytes);
  final List<String> out = <String>[];
  void walk(List<DocxBlock> blocks) {
    for (final DocxBlock b in blocks) {
      if (b is DocxParagraph) out.add(b.text);
      if (b is DocxTable) {
        for (final DocxTableRow r in b.rows) {
          out.add(
            r.cells
                .map(
                  (DocxTableCell c) => c.blocks
                      .whereType<DocxParagraph>()
                      .map((DocxParagraph p) => p.text)
                      .join('|'),
                )
                .join('\t'),
          );
        }
      }
    }
  }

  walk(reopened.body.blocks);
  return out;
}

List<DocxWarningCode> _codes(List<DocxWarning> warnings) =>
    warnings.map((DocxWarning w) => w.code).toList();

DocxWarning _one(List<DocxWarning> warnings, DocxWarningCode code) =>
    warnings.singleWhere((DocxWarning w) => w.code == code);

String _documentXml(DocxDocument doc) =>
    utf8.decode(readXlsxBytes(doc.save().bytes)['word/document.xml']!);

/// The invoice lines of the T2 plan.
final List<Object?> _lines3 = <Object?>[
  <String, Object?>{'aciklama': 'Danışmanlık', 'tutar': FormatDecimal('1000')},
  <String, Object?>{
    'aciklama': 'Yazılım lisansı',
    'tutar': FormatDecimal('234.56'),
  },
  <String, Object?>{'aciklama': 'Kurulum', 'tutar': FormatDecimal('0')},
];

String _invoiceTable({String firstCell = '{{#kalemler}}{{aciklama}}'}) =>
    _tbl(<String>[
      _tr(<String>[_tc(_p('Açıklama')), _tc(_p('Tutar'))]),
      _tr(<String>[
        _tc(_p(firstCell)),
        _tc(_p('{{tutar:#,##0.00 ₺}}{{/kalemler}}')),
      ]),
      _tr(<String>[_tc(_p('Toplam')), _tc(_p('{{tutar:#,##0.00 ₺}}'))]),
    ], columns: 2);

void main() {
  test('a repeated row fills each copy from its item', () {
    final r = _fill('${_invoiceTable()}${_p('son')}', <String, Object?>{
      'kalemler': _lines3,
      'tutar': FormatDecimal('1234.56'),
    });
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>[
      'Açıklama\tTutar',
      'Danışmanlık\t1.000,00 ₺',
      'Yazılım lisansı\t234,56 ₺',
      'Kurulum\t0,00 ₺',
      'Toplam\t1.234,56 ₺',
      'son',
    ]);
  });

  test('an empty list removes the row and keeps the header row', () {
    final r = _fill('${_invoiceTable()}${_p('son')}', <String, Object?>{
      'kalemler': <Object?>[],
      'tutar': FormatDecimal('0'),
    });
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>['Açıklama\tTutar', 'Toplam\t0,00 ₺', 'son']);
  });

  test('paid and unpaid', () {
    const String body =
        '<w:p><w:r><w:t xml:space="preserve">Durum: </w:t></w:r>'
        '<w:r><w:t>{{#odendi}}Ödendi{{/odendi}}{{^odendi}}Ödenmedi'
        '{{/odendi}}</w:t></w:r></w:p>';
    expect(_fill(body, <String, Object?>{'odendi': true}).lines, <String>[
      'Durum: Ödendi',
    ]);
    expect(_fill(body, <String, Object?>{'odendi': false}).lines, <String>[
      'Durum: Ödenmedi',
    ]);
  });

  test('a map section is a scope', () {
    final r = _fill(
      _p('{{#musteri}}Sayın {{ad}},{{/musteri}}'),
      <String, Object?>{
        'musteri': <String, Object?>{'ad': 'Ayşe Yılmaz'},
      },
    );
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>['Sayın Ayşe Yılmaz,']);
  });

  test('{{.}} is the current item', () {
    final r = _fill(
      '${_p('{{#notlar}}')}${_p('Not: {{.}}')}${_p('{{/notlar}}')}${_p('son')}',
      <String, Object?>{
        'notlar': <Object?>['a', 'b'],
      },
    );
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>['Not: a', 'Not: b', 'son']);
  });

  test('a value shown once is the current item', () {
    final r = _fill(
      _p('{{#tarih}}Tarih: {{.:dd.mm.yyyy}}{{/tarih}}'),
      <String, Object?>{'tarih': DateTime(2026, 11, 14)},
    );
    expect(r.lines, <String>['Tarih: 14.11.2026']);
  });

  test('names inside a section fall back outward', () {
    final r = _fill(
      _p('{{#kalemler}}{{firma.unvan}}/{{aciklama}};{{/kalemler}}'),
      <String, Object?>{
        'firma': <String, Object?>{'unvan': 'Acme'},
        'kalemler': _lines3.take(2).toList(),
      },
    );
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>['Acme/Danışmanlık;Acme/Yazılım lisansı;']);
  });

  test('a missing section keeps its tags and shows its content once, warned '
      'once', () {
    final DocxDocument doc = DocxDocument.open(
      _bytes(_p('Eksik: {{#yok}}gizli {{a}}{{/yok}}')),
    );
    final Uint8List before = doc.save().bytes;
    final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
      'a': 'A',
    }, _turkish);
    expect(_codes(warnings), <DocxWarningCode>[
      DocxWarningCode.templateValueMissing,
    ]);
    expect(warnings.single.detail, '{{#yok}}');
    expect(warnings.single.locations, <String>['body/p[0]']);
    expect(_lines(doc), <String>['Eksik: {{#yok}}gizli A{{/yok}}']);
    expect(before, isNotEmpty);

    final r = _fill(
      _p('Eksik: {{#yok}}gizli{{/yok}}'),
      <String, Object?>{},
      settings: const FillSettings(removeMissing: true),
    );
    expect(r.lines, <String>['Eksik: gizli']);
    expect(_codes(r.warnings), <DocxWarningCode>[
      DocxWarningCode.templateValueMissing,
    ]);
  });

  test('malformed sections stay as text, their content filled', () {
    final r = _fill(_p('{{#a}}{{#b}}{{v}}{{/a}}{{/b}}'), <String, Object?>{
      'a': true,
      'b': true,
      'v': 'V',
    });
    expect(r.lines, <String>['{{#a}}{{#b}}V{{/a}}{{/b}}']);
    expect(_codes(r.warnings), <DocxWarningCode>[
      DocxWarningCode.templateSectionMalformed,
      DocxWarningCode.templateSectionMalformed,
      DocxWarningCode.templateSectionMalformed,
      DocxWarningCode.templateSectionMalformed,
    ]);
  });

  test(
    'nested: rows inside a block repeat, inline condition inside the rows',
    () {
      final String body =
          '${_p('{{#gruplar}}')}${_p('Grup: {{baslik}}')}'
          '${_tbl(<String>[
            _tr(<String>[_tc(_p('Ürün')), _tc(_p('Tutar'))]),
            _tr(<String>[_tc(_p('{{#kalemler}}{{ad}}')), _tc(_p('{{tutar:#,##0.00 ₺}}{{#acil}} (acil){{/acil}}{{/kalemler}}'))]),
          ], columns: 2)}${_p('{{/gruplar}}')}${_p('Son.')}';
      final r = _fill(body, <String, Object?>{
        'gruplar': <Object?>[
          <String, Object?>{
            'baslik': 'Donanım',
            'acil': true,
            'kalemler': <Object?>[
              <String, Object?>{'ad': 'Klavye', 'tutar': FormatDecimal('450')},
            ],
          },
          <String, Object?>{
            'baslik': 'Hizmet',
            'acil': false,
            'kalemler': <Object?>[
              <String, Object?>{'ad': 'Kurulum', 'tutar': FormatDecimal('300')},
              <String, Object?>{
                'ad': 'Eğitim',
                'tutar': FormatDecimal('1250.5'),
              },
            ],
          },
        ],
      });
      expect(r.warnings, isEmpty);
      expect(r.lines, <String>[
        'Grup: Donanım',
        'Ürün\tTutar',
        'Klavye\t450,00 ₺ (acil)',
        'Grup: Hizmet',
        'Ürün\tTutar',
        'Kurulum\t300,00 ₺',
        'Eğitim\t1.250,50 ₺',
        'Son.',
      ]);
    },
  );

  test('copies of a block section holding a repeating one fill in place', () {
    // Pinned from the template fuzz: filling the first copy changed how many
    // blocks it had, and the next copy was looked for at its old index.
    final r = _fill(
      '${_p('{{#a}}')}${_p('{{#b}}')}${_p('{{.}}')}${_p('{{/b}}')}'
      '${_p('{{/a}}')}${_p('son')}',
      <String, Object?>{
        'a': <Object?>[
          <String, Object?>{
            'b': <Object?>[1, 2],
          },
          <String, Object?>{
            'b': <Object?>[3],
          },
          <String, Object?>{'b': <Object?>[]},
        ],
      },
    );
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>['1', '2', '3', 'son']);
  });

  group('100,000 items repeat in linear time', () {
    // Review of P3: each copy was inserted, and looked for, from the start of
    // its list, so the default copy limit took about 25 s.
    final List<Object?> items = List<Object?>.filled(100000, 1);
    for (final (String form, String body) in <(String, String)>[
      (
        'rows',
        '${_tbl(<String>[
          _tr(<String>[_tc(_p('{{#a}}'))]),
          _tr(<String>[_tc(_p('x{{/a}}'))]),
          _tr(<String>[_tc(_p('total'))]),
        ])}${_p('son')}',
      ),
      ('blocks', '${_p('{{#a}}')}${_p('x')}${_p('{{/a}}')}${_p('son')}'),
      ('inline', '${_p('{{#a}}x{{/a}}')}${_p('son')}'),
    ]) {
      test(form, () {
        final DocxDocument doc = DocxDocument.open(_bytes(body));
        final Stopwatch watch = Stopwatch()..start();
        final List<DocxWarning> warnings = fillTemplate(doc, <String, Object?>{
          'a': items,
        }, _turkish);
        expect(watch.elapsed, lessThan(const Duration(seconds: 12)));
        expect(warnings, isEmpty);
        final List<DocxBlock> blocks = doc.body.blocks;
        switch (form) {
          case 'rows':
            expect((blocks.first as DocxTable).rows, hasLength(200001));
          case 'blocks':
            expect(blocks, hasLength(100001));
          default:
            expect((blocks.first as DocxParagraph).text, 'x' * 100000);
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  test('16,000 sections list and fill in linear time', () {
    // Review of P3: the listing asked every section about every tag, so
    // opening this small template took about 10 s.
    final Uint8List bytes = _bytes(
      '${List<String>.filled(16000, _p('{{#a}}x{{v}}{{/a}}')).join()}'
      '${_p('son')}',
    );
    final Stopwatch watch = Stopwatch()..start();
    final DocxTemplate template = DocxTemplate(bytes);
    expect(template.tags, hasLength(48000));
    expect(
      template.tags.where((DocxTemplateTag t) => t.text == '{{v}}').first.depth,
      1,
    );
    final DocxResult filled = template.fill(<String, Object?>{
      'a': true,
      'v': 'V',
    });
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(filled.warnings, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('copies without a bookmark are filled where they are', () {
    // A copy leaves the bookmark out, so it is shorter than the original:
    // the next copy starts where it ends.
    final r = _fill(
      '${_p('{{#a}}')}<w:bookmarkStart w:id="3" w:name="b"/>${_p('x {{.}}')}'
      '<w:bookmarkEnd w:id="3"/>${_p('{{/a}}')}'
      '${templateParagraph('${templateRun('[{{#a}}')}'
      '<w:bookmarkStart w:id="4" w:name="c"/>${templateRun('{{.}}')}'
      '<w:bookmarkEnd w:id="4"/>${templateRun('{{/a}}]')}')}',
      <String, Object?>{
        'a': <Object?>[1, 2, 3],
      },
    );
    expect(r.lines, <String>['x 1', 'x 2', 'x 3', '[123]']);
    final DocxWarning w = r.warnings.single;
    expect(w.code, DocxWarningCode.templateRepeatDroppedAnnotation);
    expect(w.count, 2);
  });

  test('outer tags and an inline section in one paragraph', () {
    final r = _fill(
      _p('Durum: {{#odendi}}Ödendi{{/odendi}} {{tarih:dd.mm.yyyy}} {{x}}'),
      <String, Object?>{
        'odendi': true,
        'tarih': DateTime(2026, 11, 14),
        'x': '{{tarih}}',
      },
    );
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>['Durum: Ödendi 14.11.2026 {{tarih}}']);
    final r2 = _fill(_p('{{x}} {{#a}}{{x}}{{/a}}'), <String, Object?>{
      'x': '{{#a}}',
      'a': <Object?>[1, 2],
    });
    expect(r2.lines, <String>['{{#a}} {{#a}}{{#a}}']);
  });

  test('a repeated row keeps its bookmark once and warns', () {
    final String table = _tbl(<String>[
      _tr(<String>[
        _tc(
          templateParagraph(
            '${templateRun('{{#kalemler}}')}'
            '<w:bookmarkStart w:id="4" w:name="kalem"/>'
            '${templateRun('{{aciklama}}')}<w:bookmarkEnd w:id="4"/>',
          ),
        ),
        _tc(_p('.{{/kalemler}}')),
      ]),
    ], columns: 2);
    final r = _fill('$table${_p('son')}', <String, Object?>{
      'kalemler': _lines3,
    });
    expect(r.lines, <String>[
      'Danışmanlık\t.',
      'Yazılım lisansı\t.',
      'Kurulum\t.',
      'son',
    ]);
    final DocxWarning w = _one(
      r.warnings,
      DocxWarningCode.templateRepeatDroppedAnnotation,
    );
    expect(w.detail, '{{#kalemler}}');
    expect(w.locations, <String>['body/tbl[0]/tr[0]/tc[0]/p[0]']);
    expect(r.warnings, hasLength(1));
    expect(
      RegExp('w:name="kalem"').allMatches(_documentXml(r.doc)),
      hasLength(1),
    );
  });

  test('removing half a bookmark removes the other half and warns', () {
    final String body =
        '${_p('{{#iskonto}}')}'
        '${templateParagraph('<w:bookmarkStart w:id="5" w:name="aralik"/>'
        '${templateRun('İskonto uygulandı.')}')}'
        '${_p('{{/iskonto}}')}'
        '${templateParagraph('${templateRun('İskonto yok.')}'
        '<w:bookmarkEnd w:id="5"/>')}';
    final r = _fill(body, <String, Object?>{'iskonto': false});
    expect(r.lines, <String>['İskonto yok.']);
    expect(_codes(r.warnings), <DocxWarningCode>[
      DocxWarningCode.templateRemovalDroppedAnnotation,
    ]);
    expect(r.warnings.single.detail, '{{#iskonto}}');
    expect(_documentXml(r.doc), isNot(contains('bookmarkEnd')));
  });

  test('a warning in a copy names the template\'s paragraph', () {
    final String table = _tbl(<String>[
      _tr(<String>[_tc(_p('head')), _tc(_p(''))]),
      _tr(<String>[_tc(_p('{{#kalemler}}{{yok}}')), _tc(_p('{{/kalemler}}'))]),
    ], columns: 2);
    final r = _fill('$table${_p('son')}', <String, Object?>{
      'kalemler': _lines3,
    });
    final DocxWarning w = r.warnings.single;
    expect(w.code, DocxWarningCode.templateValueMissing);
    expect(w.detail, '{{yok}}');
    expect(w.count, 3);
    expect(w.locations.toSet(), <String>{'body/tbl[0]/tr[1]/tc[0]/p[0]'});
  });

  test('a list past maxCopies is refused before copying', () {
    final r = _fill('${_invoiceTable()}${_p('son')}', <String, Object?>{
      'kalemler': _lines3,
      'tutar': 1,
    }, settings: const FillSettings(locale: FormatLocale.trTR, maxCopies: 1));
    expect(_codes(r.warnings), <DocxWarningCode>[
      DocxWarningCode.templateLimitExceeded,
      DocxWarningCode.templateValueMissing,
    ]);
    expect(r.warnings.first.detail, '{{#kalemler}}');
    expect(r.lines, <String>[
      'Açıklama\tTutar',
      '{{#kalemler}}{{aciklama}}\t1,00 ₺{{/kalemler}}',
      'Toplam\t1,00 ₺',
      'son',
    ]);

    final Stopwatch watch = Stopwatch()..start();
    final r2 = _fill(
      '${_p('{{#a}}')}${_p('{{.}}')}${_p('{{/a}}')}${_p('son')}',
      <String, Object?>{'a': List<Object?>.filled(1000000, 'x')},
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(
      _codes(r2.warnings),
      contains(DocxWarningCode.templateLimitExceeded),
    );
    expect(r2.lines.first, '{{#a}}');
    expect(r2.lines, hasLength(4));
  });

  test('a section deeper than maxSectionDepth is not expanded', () {
    final r = _fill(
      _p('{{#a}}A{{#b}}B{{#c}}C{{/c}}{{/b}}{{/a}}'),
      <String, Object?>{'a': true, 'b': true, 'c': true},
      settings: const FillSettings(maxSectionDepth: 2),
    );
    expect(r.lines, <String>['AB{{#c}}C{{/c}}']);
    final DocxWarning w = r.warnings.single;
    expect(w.code, DocxWarningCode.templateLimitExceeded);
    expect(w.detail, '{{#c}}');
  });

  test('maxTags stops filling and warns', () {
    final r = _fill(_p('{{a}} {{b}} {{c}}'), <String, Object?>{
      'a': 'A',
      'b': 'B',
      'c': 'C',
    }, settings: const FillSettings(maxTags: 2));
    expect(r.lines, <String>['A B {{c}}']);
    final DocxWarning w = r.warnings.single;
    expect(w.code, DocxWarningCode.templateLimitExceeded);
    expect(w.detail, '{{c}}');

    final r2 = _fill(_p('{{#a}}{{.}}{{/a}}'), <String, Object?>{
      'a': <Object?>[1, 2, 3],
    }, settings: const FillSettings(maxTags: 2));
    expect(r2.lines, <String>['{{#a}}{{.}}{{/a}}']);
    expect(r2.warnings.first.code, DocxWarningCode.templateLimitExceeded);
  });

  test('a fill with sections is one change set, undone whole', () {
    final Uint8List template = _bytes(
      '${_invoiceTable()}${_p('{{#notlar}}')}${_p('Not: {{.}}')}'
      '${_p('{{/notlar}}')}${_p('Durum: {{#odendi}}Ödendi{{/odendi}}')}',
    );
    final DocxDocument doc = DocxDocument.open(template);
    final fill = fillTemplateWithChanges(doc, <String, Object?>{
      'kalemler': _lines3,
      'tutar': 1,
      'notlar': <Object?>['a', 'b'],
      'odendi': false,
    }, _turkish);
    expect(changeLogOf(doc).hasChanges, isTrue);
    changeLogOf(doc).undo(fill.changes);
    expect(comparePackages(template, doc.save().bytes), isEmpty);
  });

  test('merge fields in a repeated row are filled from the item', () {
    final String table = _tbl(<String>[
      _tr(<String>[
        _tc(
          templateParagraph(
            '${templateRun('{{#kisiler}}')}'
            '${complexMergeField(' MERGEFIELD Ad ', '«Ad»')}',
          ),
        ),
        _tc(_p('{{/kisiler}}')),
      ]),
    ], columns: 2);
    final r = _fill('$table${_p('son')}', <String, Object?>{
      'kisiler': <Object?>[
        <String, Object?>{'Ad': 'Ayşe'},
        <String, Object?>{'Ad': 'Can'},
      ],
    });
    expect(r.warnings, isEmpty);
    expect(r.lines, <String>['Ayşe\t', 'Can\t', 'son']);
  });

  test('a tag in the result of a field across paragraphs stays', () {
    const String run = '<w:r><w:fldChar w:fldCharType="begin"/></w:r>';
    final String body =
        '${templateParagraph('$run<w:r><w:instrText xml:space="preserve"> TOC '
        r'\o </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>')}'
        '${_p('{{a}} {{#b}}x{{/b}}')}'
        '${templateParagraph('<w:r><w:fldChar w:fldCharType="end"/></w:r>')}'
        '${_p('{{a}}')}';
    final r = _fill(body, <String, Object?>{'a': 'A', 'b': true});
    expect(r.lines, <String>['', '{{a}} {{#b}}x{{/b}}', '', 'A']);
    expect(_codes(r.warnings), <DocxWarningCode>[
      DocxWarningCode.templateTagMalformed,
      DocxWarningCode.templateSectionMalformed,
      DocxWarningCode.templateSectionMalformed,
    ]);
  });

  test(
    'a rows section inside one of the same rows is malformed in the copies',
    () {
      final String table = _tbl(<String>[
        _tr(<String>[
          _tc(_p('{{#a}}')),
          _tc(_p('{{#b}}{{.}}')),
          _tc(_p('{{/b}}')),
          _tc(_p('{{/a}}')),
        ]),
      ], columns: 4);
      final r = _fill('$table${_p('son')}', <String, Object?>{
        'a': <Object?>[1, 2],
        'b': <Object?>[9],
      });
      expect(r.lines, <String>[
        '\t{{#b}}1\t{{/b}}\t',
        '\t{{#b}}2\t{{/b}}\t',
        'son',
      ]);
      expect(_codes(r.warnings).toSet(), <DocxWarningCode>{
        DocxWarningCode.templateSectionMalformed,
      });
    },
  );

  test('listing pairs sections', () {
    const String restart = '<w:vMerge w:val="restart"/>';
    const String continues = '<w:vMerge/>';
    final DocxDocument doc = DocxDocument.open(
      _bytes(
        '${_invoiceTable()}${_p('{{#x}}{{#y}}{{/x}}{{/y}}')}'
        '${_tbl(<String>[
          _tr(<String>[_tc(_p('top'), tcPr: restart)]),
          _tr(<String>[_tc(_p('{{#m}}'), tcPr: continues)]),
          _tr(<String>[_tc(_p('{{/m}}'))]),
        ])}${_p('son')}',
      ),
    );
    final List<DocxTemplateTag> tags = DocxTemplate.tagsOf(doc);
    DocxTemplateTag tag(String text) =>
        tags.firstWhere((DocxTemplateTag t) => t.text == text);
    expect(tag('{{#kalemler}}').problem, isNull);
    expect(tag('{{#kalemler}}').depth, 0);
    expect(tag('{{/kalemler}}').problem, isNull);
    expect(tag('{{aciklama}}').depth, 1);
    expect(tags[2].text, '{{tutar:#,##0.00 ₺}}');
    expect(tags[2].depth, 1);
    expect(tag('{{#x}}').problem, DocxWarningCode.templateSectionMalformed);
    expect(tag('{{/y}}').problem, DocxWarningCode.templateSectionMalformed);
    expect(tag('{{#m}}').problem, DocxWarningCode.templateSectionMalformed);
    expect(tag('{{/m}}').problem, DocxWarningCode.templateSectionMalformed);
  });
}
