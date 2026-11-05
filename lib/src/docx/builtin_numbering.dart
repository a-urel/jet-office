/// Word's own bullet and numbered lists: the two abstract definitions that
/// Word for Mac writes for its Bullets and Numbering toolbar buttons, which
/// `DocxNumbering.addBulletList` and `addNumberedList` add to a document.
///
/// Not ported from Quds; written for jet_office. The definitions are
/// transcribed from `test/fixtures/owner/docx/builtins.docx`, saved by
/// Microsoft Word for Mac 16.114 with the personal information removed.
/// Removed from them: the identifiers that Word writes and does not need
/// (`w:abstractNumId`, which the writer sets as the lowest unused,
/// `w:nsid`, `w:tmpl`, `w:lvl/@w:tplc` and
/// `@w15:restartNumberingAfterBreak`). The template codes carry the
/// locale of the system the file was saved on (`041F`, Turkish). Without
/// `w:nsid` Word may treat two pasted lists of one kind as one.
///
/// Each constant is one `w:abstractNum` element whose prefix `w` is
/// WordprocessingML, in the form `addAbstractNumbering` takes.
library;

/// The numbered list of Word's Numbering button: decimal, lower letter
/// and lower roman numbers, repeating, indented as the bullets.
const String numberedAbstractXml =
    '<w:abstractNum><w:multiLevelType w:val="hybridMultilevel"/>'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
    '<w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="1"><w:start w:val="1"/>'
    '<w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2."/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1440" w:hanging="360"/>'
    '</w:pPr></w:lvl><w:lvl w:ilvl="2" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="lowerRoman"/>'
    '<w:lvlText w:val="%3."/><w:lvlJc w:val="right"/><w:pPr>'
    '<w:ind w:left="2160" w:hanging="180"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="3" w:tentative="1"><w:start w:val="1"/>'
    '<w:numFmt w:val="decimal"/><w:lvlText w:val="%4."/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="2880" w:hanging="360"/>'
    '</w:pPr></w:lvl><w:lvl w:ilvl="4" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="lowerLetter"/>'
    '<w:lvlText w:val="%5."/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="3600" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="5" w:tentative="1"><w:start w:val="1"/>'
    '<w:numFmt w:val="lowerRoman"/><w:lvlText w:val="%6."/>'
    '<w:lvlJc w:val="right"/><w:pPr>'
    '<w:ind w:left="4320" w:hanging="180"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="6" w:tentative="1"><w:start w:val="1"/>'
    '<w:numFmt w:val="decimal"/><w:lvlText w:val="%7."/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="5040" w:hanging="360"/>'
    '</w:pPr></w:lvl><w:lvl w:ilvl="7" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="lowerLetter"/>'
    '<w:lvlText w:val="%8."/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="5760" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="8" w:tentative="1"><w:start w:val="1"/>'
    '<w:numFmt w:val="lowerRoman"/><w:lvlText w:val="%9."/>'
    '<w:lvlJc w:val="right"/><w:pPr>'
    '<w:ind w:left="6480" w:hanging="180"/></w:pPr></w:lvl>'
    '</w:abstractNum>';

/// The bullet list of Word's Bullets button: Symbol's bullet at level 0,
/// `o` in Courier New at level 1, Wingdings' square at level 2, repeating,
/// each level indented 360 twips further, hanging 360.
const String bulletAbstractXml =
    '<w:abstractNum><w:multiLevelType w:val="hybridMultilevel"/>'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="\uF0B7"/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="720" w:hanging="360"/></w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/>'
    '<w:numFmt w:val="bullet"/><w:lvlText w:val="o"/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1440" w:hanging="360"/>'
    '</w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"'
    ' w:cs="Courier New" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="2" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="\uF0A7"/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="2160" w:hanging="360"/></w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Wingdings" w:hAnsi="Wingdings" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="3" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="\uF0B7"/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="2880" w:hanging="360"/></w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="4" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="o"/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="3600" w:hanging="360"/>'
    '</w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"'
    ' w:cs="Courier New" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="5" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="\uF0A7"/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="4320" w:hanging="360"/></w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Wingdings" w:hAnsi="Wingdings" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="6" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="\uF0B7"/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="5040" w:hanging="360"/></w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="7" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="o"/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="5760" w:hanging="360"/>'
    '</w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"'
    ' w:cs="Courier New" w:hint="default"/>'
    '</w:rPr></w:lvl><w:lvl w:ilvl="8" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="\uF0A7"/><w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="6480" w:hanging="360"/></w:pPr><w:rPr>'
    '<w:rFonts w:ascii="Wingdings" w:hAnsi="Wingdings" w:hint="default"/>'
    '</w:rPr></w:lvl></w:abstractNum>';
