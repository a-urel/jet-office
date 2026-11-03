import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

void main() {
  test('WordprocessingML constants are the transitional values', () {
    expect(
      Ns.w,
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    );
    expect(Ns.w14, 'http://schemas.microsoft.com/office/word/2010/wordml');
    expect(
      Ns.wp,
      'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
    );
    expect(
      Ns.mc,
      'http://schemas.openxmlformats.org/markup-compatibility/2006',
    );
    expect(Ns.wStrict, 'http://purl.oclc.org/ooxml/wordprocessingml/main');

    const String rel =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/';
    expect(RelType.styles, '${rel}styles');
    expect(RelType.settings, '${rel}settings');
    expect(RelType.webSettings, '${rel}webSettings');
    expect(RelType.fontTable, '${rel}fontTable');
    expect(RelType.theme, '${rel}theme');
    expect(RelType.numbering, '${rel}numbering');
    expect(RelType.header, '${rel}header');
    expect(RelType.footer, '${rel}footer');
    expect(
      RelType.officeDocumentStrict,
      'http://purl.oclc.org/ooxml/officeDocument/relationships/'
      'officeDocument',
    );

    const String wml =
        'application/vnd.openxmlformats-officedocument.wordprocessingml.';
    expect(ContentType.wmlDocument, '${wml}document.main+xml');
    expect(ContentType.wmlTemplate, '${wml}template.main+xml');
    expect(
      ContentType.wmlMacroDocument,
      'application/vnd.ms-word.document.macroEnabled.main+xml',
    );
    expect(
      ContentType.wmlMacroTemplate,
      'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
    );
    expect(ContentType.wmlStyles, '${wml}styles+xml');
    expect(ContentType.wmlSettings, '${wml}settings+xml');
    expect(ContentType.wmlFontTable, '${wml}fontTable+xml');
    expect(ContentType.wmlWebSettings, '${wml}webSettings+xml');
    expect(
      ContentType.theme,
      'application/vnd.openxmlformats-officedocument.theme+xml',
    );
  });
}
