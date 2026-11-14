// Tests the scan of content the model keeps opaque for template tags and
// MERGEFIELD instructions (decision 0024, Ruling 14): text is joined per
// `w:p`, so a tag split over two paragraphs is no tag. Documents are built in
// memory, so they run on the web as well.
import 'dart:convert';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/run_content.dart';
import 'package:jet_office/src/docx/template/opaque_scan.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../support/docx_builder.dart';
import '../support/template_documents.dart' show textBoxDrawing;

/// The body's first paragraph's first run's content of a document whose
/// one paragraph is a run of [runContent].
DocxRunContent _contentOf(String runContent) {
  final DocxDocument doc = DocxDocument.open(
    buildDocx(
      document:
          '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"><w:body>'
          '<w:p><w:r>$runContent</w:r></w:p></w:body></w:document>',
    ),
  );
  final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
  return (p.inlines.first as DocxRun).content.first;
}

List<String> _scan(String runContent) {
  final DocxRunContent c = _contentOf(runContent);
  return placeholdersIn(opaqueRunContentXml(c as DocxOpaqueRunContent));
}

void main() {
  group('placeholdersIn', () {
    test('a tag split over two paragraphs of a text box is no tag', () {
      expect(_scan(textBoxDrawing(<String>['{{a', '}}'])), isEmpty);
    });

    test('a tag in a text box paragraph is found', () {
      expect(_scan(textBoxDrawing(<String>['{{a}}'])), <String>['{{a}}']);
    });

    test('tags in two paragraphs, joined over runs, in order', () {
      final String drawing = textBoxDrawing(<String>['{{a']).replaceFirst(
        '<w:t>{{a</w:t></w:r>',
        '<w:t>{{a</w:t></w:r><w:r><w:t>}} {{b}}</w:t></w:r>',
      );
      expect(_scan(drawing), <String>['{{a}}', '{{b}}']);
    });

    test('a MERGEFIELD instruction is found', () {
      // A loose instruction run holds a typed DocxFieldInstruction, so the
      // scan is tried on an opaque element that holds one.
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document:
              '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"><w:body>'
              '<w:sdt><w:sdtContent><w:p><w:r>'
              '<w:instrText xml:space="preserve"> MERGEFIELD Ad </w:instrText>'
              '</w:r><w:r><w:instrText> PAGE </w:instrText></w:r></w:p>'
              '</w:sdtContent></w:sdt></w:body></w:document>',
        ),
      );
      final DocxOpaqueBlock block = doc.body.blocks.first as DocxOpaqueBlock;
      expect(placeholdersIn(opaqueBlockXml(block)), <String>[
        ' MERGEFIELD Ad ',
      ]);
    });

    test('a w:fldSimple MERGEFIELD instruction is found', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document:
              '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"><w:body>'
              '<w:sdt><w:sdtContent><w:p>'
              '<w:fldSimple w:instr=" MERGEFIELD Soyad "><w:r><w:t>«Soyad»'
              '</w:t></w:r></w:fldSimple>'
              '<w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r>'
              '</w:fldSimple></w:p></w:sdtContent></w:sdt>'
              '</w:body></w:document>',
        ),
      );
      final DocxOpaqueBlock block = doc.body.blocks.first as DocxOpaqueBlock;
      expect(placeholdersIn(opaqueBlockXml(block)), <String>[
        ' MERGEFIELD Soyad ',
      ]);
    });

    test('the fallback of mc:AlternateContent is not scanned twice', () {
      final String drawing = textBoxDrawing(<String>['{{a}}']);
      final String alternate =
          '<mc:AlternateContent xmlns:mc="${Ns.mc}"><mc:Choice Requires="wps">'
          '$drawing</mc:Choice><mc:Fallback><w:pict><w:p><w:r><w:t>{{a}}'
          '</w:t></w:r></w:p></w:pict></mc:Fallback></mc:AlternateContent>';
      expect(_scan(alternate), <String>['{{a}}']);
    });
  });

  group('placeholdersInPart', () {
    test('a footnotes part is scanned per paragraph', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          extra: <String, List<int>>{
            'word/footnotes.xml': utf8.encode(
              '<w:footnotes xmlns:w="${Ns.w}"><w:footnote w:id="1"><w:p>'
              '<w:r><w:t>{{not}}</w:t></w:r></w:p><w:p><w:r><w:t>{{x</w:t>'
              '</w:r></w:p><w:p><w:r><w:t>}}</w:t></w:r></w:p></w:footnote>'
              '</w:footnotes>',
            ),
          },
        ),
      );
      expect(
        placeholdersInPart(docxPackageOf(doc), '/word/footnotes.xml'),
        <String>['{{not}}'],
      );
    });

    test('a damaged part gives nothing', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          extra: <String, List<int>>{
            'word/footnotes.xml': utf8.encode(
              '<w:footnotes xmlns:w="${Ns.w}"><w:footnote><w:p><w:r><w:t>'
              '{{not}}</w:t></w:r></w:p>',
            ),
          },
        ),
      );
      expect(
        placeholdersInPart(docxPackageOf(doc), '/word/footnotes.xml'),
        isEmpty,
      );
    });

    test('a part the package lacks gives nothing', () {
      final DocxDocument doc = DocxDocument.open(buildDocx());
      expect(
        placeholdersInPart(docxPackageOf(doc), '/word/endnotes.xml'),
        isEmpty,
      );
    });
  });
}
