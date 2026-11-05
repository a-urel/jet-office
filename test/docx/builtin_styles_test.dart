// Tests Word's built-in style catalog (`builtin_styles.dart`): every public
// built-in has a definition of its type and name, the definitions refer to
// each other only inside the catalog, those a new document holds are the
// document's own, and nothing of the Turkish file they were transcribed from
// is left. They read nothing from disk, so they run on the web as well; the
// comparison with `builtins.docx` is in
// `builtin_styles_oracle_test.dart`.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/blank_document.dart';
import 'package:jet_office/src/docx/builtin_styles.dart';
import 'package:test/test.dart';

/// The `w:type` of the style element [xml].
String _type(String xml) =>
    RegExp(r'w:type="(\w+)"').firstMatch(xml)!.group(1)!;

/// The `w:styleId` of the style element [xml].
String _id(String xml) =>
    RegExp(r'w:styleId="([^"]+)"').firstMatch(xml)!.group(1)!;

/// The `w:name` of the style element [xml].
String _name(String xml) =>
    RegExp(r'<w:name w:val="([^"]*)"').firstMatch(xml)!.group(1)!;

/// The styles of [blankStyles], by id, as elements.
Map<String, String> _blank() => <String, String>{
  for (final RegExpMatch m in RegExp(
    r'<w:style [^>]*w:styleId="([^"]+)">.*?</w:style>',
    dotAll: true,
  ).allMatches(blankStyles))
    m.group(1)!: m.group(0)!,
};

void main() {
  group('the built-in style catalog', () {
    test('every built-in has a definition of its type and name', () {
      for (final DocxBuiltInStyle style in DocxBuiltInStyle.values) {
        final String xml = builtInStyleXml(style.id);
        expect(_id(xml), style.id, reason: style.id);
        expect(_name(xml), style.name, reason: style.id);
        expect(_type(xml), switch (style.type) {
          DocxStyleType.paragraph => 'paragraph',
          DocxStyleType.character => 'character',
          DocxStyleType.table => 'table',
          DocxStyleType.numbering => 'numbering',
        }, reason: style.id);
      }
    });

    test('the built-ins have the ids and names the task lists', () {
      expect(DocxBuiltInStyle.heading1.id, 'Heading1');
      expect(DocxBuiltInStyle.heading1.name, 'heading 1');
      expect(DocxBuiltInStyle.heading9.name, 'heading 9');
      expect(DocxBuiltInStyle.tableNormal.name, 'Normal Table');
      expect(DocxBuiltInStyle.header.name, 'header');
      expect(DocxBuiltInStyle.footer.name, 'footer');
      expect(DocxBuiltInStyle.noSpacing.name, 'No Spacing');
      expect(DocxBuiltInStyle.listParagraph.name, 'List Paragraph');
      expect(DocxBuiltInStyle.tableGrid.type, DocxStyleType.table);
      expect(DocxBuiltInStyle.noList.type, DocxStyleType.numbering);
      expect(
        DocxBuiltInStyle.defaultParagraphFont.type,
        DocxStyleType.character,
      );
    });

    test('every basedOn, next and link of a definition names a catalog '
        'entry', () {
      final Set<String> ids = builtInStyleIds.toSet();
      expect(ids, containsAll(<String>['Header', 'HeaderChar', 'FooterChar']));
      for (final String id in ids) {
        final String xml = builtInStyleXml(id);
        for (final RegExpMatch m in RegExp(
          r'<w:(basedOn|next|link) w:val="([^"]+)"',
        ).allMatches(xml)) {
          expect(ids, contains(m.group(2)), reason: '$id ${m.group(1)}');
        }
      }
    });

    test('linked styles link back', () {
      for (final String id in builtInStyleIds) {
        final String xml = builtInStyleXml(id);
        final RegExpMatch? link = RegExp(
          r'<w:link w:val="([^"]+)"',
        ).firstMatch(xml);
        if (link == null) continue;
        expect(
          builtInStyleXml(link.group(1)!),
          contains('<w:link w:val="$id"'),
          reason: id,
        );
      }
    });

    test('catalog entries in the blank document equal its styles', () {
      final Map<String, String> blank = _blank();
      expect(blank, isNotEmpty);
      for (final MapEntry<String, String> style in blank.entries) {
        expect(
          builtInStyleXml(style.key),
          style.value.replaceFirst(
            '<w:style ',
            '<w:style xmlns:w="http://schemas.openxmlformats.org/'
                'wordprocessingml/2006/main" ',
          ),
          reason: style.key,
        );
      }
    });

    test('no definition carries an rsid or a Turkish id or name', () {
      for (final String id in builtInStyleIds) {
        final String xml = builtInStyleXml(id);
        expect(xml, isNot(contains('rsid')), reason: id);
        expect(xml, isNot(matches(RegExp('[ışğİÜçö]'))), reason: id);
        for (final String turkish in <String>[
          'stBilgi',
          'AltBilgi',
          'TabloKlavuzu',
          'Kpr',
          'Balk',
        ]) {
          expect(xml, isNot(contains(turkish)), reason: id);
        }
      }
    });

    test('Header and Footer carry the tab stops of A4', () {
      for (final String id in <String>['Header', 'Footer']) {
        expect(
          builtInStyleXml(id),
          contains(
            '<w:tabs><w:tab w:val="center" w:pos="4536"/>'
            '<w:tab w:val="right" w:pos="9072"/></w:tabs>',
          ),
        );
      }
    });

    test('an id outside the catalog is an ArgumentError', () {
      expect(() => builtInStyleXml('Balk1'), throwsArgumentError);
    });
  });
}
