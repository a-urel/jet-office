/// Word's own bullet and numbered lists: the two abstract definitions that
/// Word for Mac writes for its Bullets and Numbering toolbar buttons, which
/// `DocxNumbering.addBulletList` and `addNumberedList` add to a document.
///
/// Not ported from Quds; written for jet_office. Each definition is built
/// here from its values, those of Word for Mac 16.114, read from
/// `test/fixtures/owner/docx/builtins.docx`;
/// `test/docx/builtin_numbering_oracle_test.dart` compares them with that
/// file (decision 0011). They carry none of the identifiers Word writes and
/// does not need (`w:abstractNumId`, which the writer sets as the lowest
/// unused, `w:nsid`, `w:tmpl`, `w:lvl/@w:tplc` and
/// `@w15:restartNumberingAfterBreak`). Without `w:nsid` Word may treat two
/// pasted lists of one kind as one.
///
/// Each one is a `w:abstractNum` element whose prefix `w` is
/// WordprocessingML, in the form `addAbstractNumbering` takes.
library;

/// The nine levels of a list, each indented 720 twips further than the last
/// and marked `w:tentative` from the third on.
String _abstract(String Function(int level) body) {
  final StringBuffer xml = StringBuffer(
    '<w:abstractNum><w:multiLevelType w:val="hybridMultilevel"/>',
  );
  for (int level = 0; level < 9; level++) {
    final String tentative = level < 2 ? '' : ' w:tentative="1"';
    xml.write(
      '<w:lvl w:ilvl="$level"$tentative><w:start w:val="1"/>${body(level)}'
      '</w:lvl>',
    );
  }
  xml.write('</w:abstractNum>');
  return xml.toString();
}

/// What follows `w:start` in a level: its [format], its [text], and
/// the indent of [level] with the number hanging by [hanging].
String _level(
  int level,
  String format,
  String text, {
  String justification = 'left',
  int hanging = 360,
  String run = '',
}) =>
    '<w:numFmt w:val="$format"/><w:lvlText w:val="$text"/>'
    '<w:lvlJc w:val="$justification"/><w:pPr>'
    '<w:ind w:left="${720 * (level + 1)}" w:hanging="$hanging"/></w:pPr>'
    '$run';

/// The numbered list of Word's Numbering button: decimal, lower letter
/// and lower roman numbers, repeating, indented as the bullets.
final String numberedAbstractXml = _abstract((int level) {
  final String text = '%${level + 1}.';
  return switch (level % 3) {
    0 => _level(level, 'decimal', text),
    1 => _level(level, 'lowerLetter', text),
    _ => _level(
      level,
      'lowerRoman',
      text,
      justification: 'right',
      hanging: 180,
    ),
  };
});

/// A run in the bullet font [name]; [complex] also sets it for complex
/// scripts.
String _bulletFont(String name, {bool complex = false}) =>
    '<w:rPr><w:rFonts w:ascii="$name" w:hAnsi="$name"'
    '${complex ? ' w:cs="$name"' : ''} w:hint="default"/></w:rPr>';

/// The bullet list of Word's Bullets button: Symbol's bullet at level 0,
/// `o` in Courier New at level 1, Wingdings' square at level 2, repeating.
final String bulletAbstractXml = _abstract(
  (int level) => switch (level % 3) {
    0 => _level(level, 'bullet', '\uF0B7', run: _bulletFont('Symbol')),
    1 => _level(
      level,
      'bullet',
      'o',
      run: _bulletFont('Courier New', complex: true),
    ),
    _ => _level(level, 'bullet', '\uF0A7', run: _bulletFont('Wingdings')),
  },
);
