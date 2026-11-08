/// Edits every document of a directory through `DocxDocument`, so that CI
/// can validate what the model saves after a change to a real file.
///
/// ```bash
/// dart run tool/edit_docx.dart build/fixtures build/edited-docx-fixtures
/// ```
///
/// For every `*.docx` in the first directory (a Word lock file, `~$name`,
/// is skipped) it opens the document with `DocxDocument.open` and edits the
/// body:
///
/// * it sets the text of the first run, in a body paragraph, that has text
///   to `Edited by the model`, and makes that run bold and
///   `DocxColor.theme(DocxThemeColor.accent1)`;
/// * it replaces the last paragraph whose inlines are all plain runs or
///   proofing marks (`w:proofErr`), other than the one just edited, with a
///   new paragraph holding `Replaced by the model`. A paragraph is left
///   alone when it has another inline that is not a run (a bookmark,
///   hyperlink or the like), a run
///   that holds a field or a drawing (`fldChar`, `instrText`, `drawing`,
///   `pict`, `object`) or a `w:pPr` with a `w:sectPr`, whose loss could
///   unpair markup or drop a section;
/// * in a document with a table (the first top-level `DocxTable` with a
///   cell) it sets the text of the first cell's first paragraph to
///   `Edited cell`, through the paragraph's first run or a new run, and
///   appends a row `New row` when the table has a grid the row fits;
/// * it adds to `section.footer` of the last section, the story it has or a
///   new one, a paragraph `Page ` + `PAGE` + ` of ` + `NUMPAGES`;
/// * it ends that section (`addSection(start: nextPage)`) and makes the new
///   last section landscape A4, so what follows sits on that page;
/// * it appends, in the new section, a table `addTable(columns: 2)`, whose
///   width follows the landscape page: a header row `Head one`, `Head two`, a
///   body row and a third row merged across both columns;
/// * it appends a paragraph `A picture, links to jet_office and the added
///   heading.`: a run `A picture`, a 4 by 2 pixel PNG picture
///   (`addPicture`, 3 by 1.5 points), a run, an external link `jet_office` to
///   `https://example.com/jet-office` and an internal link `the added heading`
///   to the bookmark `Model_edit` (`addHyperlink`);
/// * it appends a paragraph `Added by the model` styled with
///   `styles.ensure(DocxBuiltInStyle.heading1)`: the document's own heading
///   style, whatever its id (`Balk1` under a Turkish Word), or Word's
///   definition added when it has none; its text is inside the bookmark
///   `Model_edit` (`addBookmarkStart`, `addBookmarkEnd`);
/// * it adds a bullet list (`numbering.addBulletList`) of two items at the
///   end, `First item` and, at level 1, `Second item` (`addListItem`);
/// * it sets the document properties' title to `Edited by the model`, keeping
///   every other property.
///
/// A document without such a run or such a paragraph skips that edit. It
/// saves and writes the bytes to `<outDir>/<name>.docx`, then reads the
/// saved file back with `DocxDocument`: the edits must be there, the body
/// must have five blocks more than it had before the table (the table, the
/// paragraph of the picture and links, the heading and the two items), and six
/// when its last block could not take the break, a table or a paragraph with a
/// break of its own, so `addSection` added a paragraph for it. The run must be
/// bold, the heading must have the style `ensure` returned and the bookmark
/// with an id its end shares, the picture the PNG at its size, the links their
/// targets, the list items the new list's number, the document one section
/// more and the title set, the footer its two fields, in both last sections,
/// and the table the width of the landscape page. Last, `comparePackages` from
/// `tool/src/part_compare.dart` must find differences only in the allowed
/// parts: the main part (named by the root relationship, not assumed to be
/// `word/document.xml`), the numbering part, the styles part when `ensure`
/// added a style (`Heading1`, `TableGrid` or `Hyperlink`), one footer part,
/// the core properties part (and `_rels/.rels` when it is created, and the
/// extended properties part when the file lacks one), at most one media part
/// the file lacked (none when the file has the PNG already: the picture
/// shares it), `[Content_Types].xml` when the edit created a part, and the
/// main part's relationships, which may only gain relationships of the
/// hyperlink and image types, and of the footer, styles and numbering types
/// when the edit created such a part: a relationship that goes or changes, or
/// one of another type, is a problem.
///
/// Each problem is printed as `<file>: <problem>`. The exit code is 1 on any
/// problem, 2 when the arguments are unusable or the input directory holds
/// no `.docx`, and 0 otherwise, as `tool/edit_model.dart` does for
/// workbooks. The model's warnings are not problems.
///
/// CI runs it on the DOCX fixtures, on LibreOffice's re-save of them and on
/// the owner's Word files, and validates each output directory with
/// `tool/ooxml_validate`; the owner opens the edited owner files in Word
/// (`docs/word-checks.md`).
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/model/inlines.dart' show heldInlinesOf;
import 'package:xml/xml.dart';

import '../test/fixtures/m4_fixtures.dart' show png4x2;
import 'src/part_compare.dart';

void main(List<String> args) {
  exitCode = editDocx(args, out: stdout, err: stderr);
}

/// The text the tool sets on the first run with text.
const String editedText = 'Edited by the model';

/// The text of the paragraph that replaces one.
const String replacedText = 'Replaced by the model';

/// The text of the paragraph the tool appends.
const String addedText = 'Added by the model';

/// The text of the first list item.
const String firstItemText = 'First item';

/// The text of the second list item, at level 1.
const String secondItemText = 'Second item';

/// The text the tool sets on the first cell of the first table.
const String editedCellText = 'Edited cell';

/// The text of the first cell of the row the tool appends to that table.
const String newRowText = 'New row';

/// The text before the `PAGE` field of the footer paragraph.
const String footerPageText = 'Page ';

/// The text between the two fields of the footer paragraph.
const String footerOfText = ' of ';

/// The text of the paragraph of the picture and the links.
const String linksText =
    'A picture, links to jet_office and the added heading.';

/// The address of the external link.
const String externalUrl = 'https://example.com/jet-office';

/// The text of the external link.
const String externalLinkText = 'jet_office';

/// The text of the internal link.
const String internalLinkText = 'the added heading';

/// The name of the bookmark over the added heading.
const String bookmarkName = 'Model_edit';

/// The namespace of the elements of a relationships part.
const String _relsNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';

/// The WordprocessingML namespace.
const String _wNs =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// Run content that makes a paragraph unfit to replace: a field or a
/// drawing.
const Set<String> _fieldOrDrawing = <String>{
  'fldChar',
  'delInstrText',
  'drawing',
  'pict',
  'object',
};

/// Runs the tool on [args] (`<inDir> <outDir>`), writing problems to [out]
/// and usage problems to [err], and returns the exit code.
///
/// [corruptForTest], when given, changes the saved bytes before they are
/// written and checked; the tests use it to prove that the checks fail.
int editDocx(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  Uint8List Function(Uint8List saved)? corruptForTest,
}) {
  if (args.length != 2) {
    err.writeln('Usage: dart run tool/edit_docx.dart <inDir> <outDir>');
    return 2;
  }
  final Directory input = Directory(args[0]);
  if (!input.existsSync()) {
    err.writeln('No such directory: ${input.path}');
    return 2;
  }
  final List<File> files = input.listSync().whereType<File>().where((File f) {
    final String name = f.uri.pathSegments.last;
    return name.endsWith('.docx') && !name.startsWith(r'~$');
  }).toList()..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    err.writeln('Nothing to edit: no .docx in ${input.path}.');
    return 2;
  }
  final Directory output = Directory(args[1])..createSync(recursive: true);
  int failed = 0;
  for (final File file in files) {
    final String name = file.uri.pathSegments.last;
    final List<String> problems = _edit(file, output, name, corruptForTest);
    for (final String line in problems) {
      out.writeln('$name: $line');
    }
    if (problems.isNotEmpty) failed++;
  }
  out.writeln(
    failed == 0
        ? 'All ${files.length} documents edited.'
        : '$failed of ${files.length} documents failed.',
  );
  return failed == 0 ? 0 : 1;
}

/// What [_edit] did to a document, for the read-back check.
typedef _Edits = ({
  int blocks,
  ({int block, int inline})? run,
  int? replaced,
  String style,
  bool stylesAdded,
  int numId,
  ({int block, int rows, bool added})? table,
  int tableBlock,
  int sections,
});

/// Edits [file], writes the result to [output], and returns the problems.
List<String> _edit(
  File file,
  Directory output,
  String name,
  Uint8List Function(Uint8List saved)? corruptForTest,
) {
  final Uint8List input = file.readAsBytesSync();
  Uint8List saved;
  final _Edits edits;
  try {
    final DocxDocument doc = DocxDocument.open(input);
    final DocxBody body = doc.body;
    final List<bool> keep = _mustKeep(input, body);
    final ({int block, int inline})? run = _firstRunWithText(body);
    if (run != null) {
      final DocxParagraph p = body.blocks[run.block] as DocxParagraph;
      (_flat(p)[run.inline] as DocxRun)
        ..text = editedText
        ..properties.bold = true
        ..properties.color = DocxColor.theme(DocxThemeColor.accent1);
    }
    final int? replaced = _paragraphToReplace(body, run?.block, keep);
    if (replaced != null) {
      body.replaceBlockAt(replaced, DocxParagraph.text(replacedText));
    }
    final int blocks = body.blocks.length;
    final int styles = doc.styles.styles.length;
    final ({int block, int rows, bool added})? table = _editFirstTable(body);
    _addFooter(doc.sections.last);
    final int sections = doc.sections.length;
    body.addSection().pageSize = DocxPageSize.a4(landscape: true);
    // The break's own paragraph comes before the table when one was added.
    final int tableBlock = body.blocks.length;
    _appendTable(body);
    _appendLinks(body);
    final String heading = doc.styles.ensure(DocxBuiltInStyle.heading1);
    final DocxParagraph headingParagraph = body.addParagraph()..style = heading;
    final DocxBookmarkStart start = headingParagraph.addBookmarkStart(
      bookmarkName,
    );
    headingParagraph
      ..addRun(addedText)
      ..addBookmarkEnd(start);
    final DocxNumberingInstance list = doc.numbering.addBulletList();
    body.addListItem(list, firstItemText);
    body.addListItem(list, secondItemText, level: 1);
    doc.properties = _withTitle(doc.properties, editedText);
    edits = (
      blocks: blocks,
      run: run,
      replaced: replaced,
      style: heading,
      stylesAdded: doc.styles.styles.length != styles,
      numId: list.id,
      table: table,
      tableBlock: tableBlock,
      sections: sections,
    );
    saved = doc.save().bytes;
  } on Object catch (e) {
    return <String>['the edit failed: $e'];
  }
  if (corruptForTest != null) saved = corruptForTest(saved);
  File('${output.path}/$name').writeAsBytesSync(saved);
  return <String>[
    ..._check(saved, edits),
    ..._partProblems(input, saved, edits),
  ];
}

/// Sets the text of the first cell of the first top-level table that has a
/// cell, and appends a row `New row` when the table has a grid the row fits.
/// Returns the table's block index, its row count before the edit and
/// whether the row was added, or null when no table qualifies.
///
/// The text goes through the first run of the cell's first paragraph, or a
/// new run, and a cell with no paragraph gets one.
({int block, int rows, bool added})? _editFirstTable(DocxBody body) {
  for (int b = 0; b < body.blocks.length; b++) {
    final DocxBlock block = body.blocks[b];
    if (block is! DocxTable ||
        block.rows.isEmpty ||
        block.rows.first.cells.isEmpty) {
      continue;
    }
    final DocxTableCell cell = block.rows.first.cells.first;
    final DocxParagraph paragraph =
        cell.blocks.whereType<DocxParagraph>().firstOrNull ??
        cell.addParagraph();
    final DocxRun? run = _flat(paragraph).whereType<DocxRun>().firstOrNull;
    if (run != null) {
      run.text = editedCellText;
    } else {
      paragraph.addRun(editedCellText);
    }
    final int rows = block.rows.length;
    final List<double?>? grid = block.gridColumnsPt;
    if (grid != null && grid.isNotEmpty) {
      try {
        block.addRow(<String?>[newRowText]);
      } on ArgumentError {
        // A row that does not fit this table is left out.
      }
    }
    return (block: b, rows: rows, added: block.rows.length > rows);
  }
  return null;
}

/// Adds a paragraph to the footer of [section]: the story it has, its own or
/// one it inherits, or a new one.
void _addFooter(DocxSection section) {
  section.footer.addParagraph(footerPageText)
    ..addField(DocxField.page())
    ..addRun(footerOfText)
    ..addField(DocxField.numPages());
}

/// Appends a table of two columns: a header row, a body row and a row merged
/// across both columns.
void _appendTable(DocxBody body) {
  final DocxTable table = body.addTable(columns: 2)
    ..addRow(<String?>['Head one', 'Head two'], header: true)
    ..addRow(<String?>['Body one', 'Body two'])
    ..addRow(<String?>['Merged', null]);
  table.mergeCells(firstRow: 2, firstColumn: 0, lastRow: 2, lastColumn: 1);
}

/// Appends the paragraph [linksText]: a picture of [png4x2], an external link
/// and an internal link to [bookmarkName].
void _appendLinks(DocxBody body) {
  body.addParagraph('A picture')
    ..addPicture(OfficeImage(png4x2), description: 'A PNG of 4 by 2 pixels')
    ..addRun(', links to ')
    ..addHyperlink(externalLinkText, url: externalUrl)
    ..addRun(' and ')
    ..addHyperlink(internalLinkText, anchor: bookmarkName)
    ..addRun('.');
}

/// [p] with the title [title].
OfficeProperties _withTitle(OfficeProperties p, String title) =>
    OfficeProperties(
      title: title,
      subject: p.subject,
      creator: p.creator,
      keywords: p.keywords,
      description: p.description,
      lastModifiedBy: p.lastModifiedBy,
      category: p.category,
      company: p.company,
      manager: p.manager,
      contentStatus: p.contentStatus,
      revision: p.revision,
      application: p.application,
      created: p.created,
      modified: p.modified,
      custom: p.custom,
    );

/// The problems of the parts [saved] changes: any difference outside the
/// allowed set.
List<String> _partProblems(Uint8List input, Uint8List saved, _Edits edits) {
  final List<String> problems = <String>[];
  final _Layout layout;
  final Set<String> footers;
  try {
    layout = _Layout(input);
    footers = _Layout(saved).footerParts;
  } on Object catch (e) {
    return <String>['reading the package layout failed: $e'];
  }
  final bool partCreated =
      (edits.stylesAdded && !layout.has(layout.stylesPart)) ||
      !layout.has(layout.numberingPart) ||
      !layout.footerParts.containsAll(footers);
  final String core = layout.corePart ?? 'docProps/core.xml';
  final bool coreCreated = !layout.has(core);
  final String app = layout.appPart ?? 'docProps/app.xml';
  final Set<String> media = <String>{};
  final Set<String> allowed = <String>{
    layout.mainPart,
    layout.numberingPart,
    if (edits.stylesAdded) layout.stylesPart,
    core,
    if (!layout.has(app)) app,
    if (coreCreated) '_rels/.rels',
  };
  bool contentTypes = false;
  bool rels = false;
  final Set<String> changedFooters = <String>{};
  for (final String d in comparePackages(input, saved)) {
    final int colon = d.indexOf(': ');
    final String part = colon < 0 ? d : d.substring(0, colon);
    if (footers.contains(part)) {
      changedFooters.add(part);
    } else if (part == '[Content_Types].xml') {
      contentTypes = true;
    } else if (part == layout.mainRels) {
      rels = true;
    } else if (part.startsWith(layout.mediaDir) &&
        d == '$part: added to the actual package') {
      media.add(part);
    } else if (!allowed.contains(part)) {
      problems.add('a part outside the allowed set: $d');
    }
  }
  if (media.length > 1) {
    problems.add('more than one media part was added: $media');
  }
  final bool created = partCreated || coreCreated || media.isNotEmpty;
  if (contentTypes && !created) {
    problems.add(
      'a part outside the allowed set: [Content_Types].xml, though no part '
      'was created',
    );
  }
  if (rels) {
    problems.addAll(
      _relationshipProblems(layout, _Layout(saved), allowCreated: partCreated),
    );
  }
  if (changedFooters.length > 1) {
    problems.add('more than one footer part changed: $changedFooters');
  }
  return problems;
}

/// The relationship types the edits add to the main part: a hyperlink's and
/// a picture's, and, with [created], those of a footer, a styles and a
/// numbering part.
Set<String> _addedTypes({required bool created}) => <String>{
  'hyperlink',
  'image',
  if (created) ...<String>['footer', 'styles', 'numbering'],
};

/// The problems of the main part's relationships in [after] against
/// [before]: a relationship that went or changed, and one added of a type the
/// edits do not add ([_addedTypes], those of a created part with
/// [allowCreated]).
List<String> _relationshipProblems(
  _Layout before,
  _Layout after, {
  required bool allowCreated,
}) {
  String key(XmlElement r) => <String?>[
    r.getAttribute('Id'),
    r.getAttribute('Type'),
    r.getAttribute('Target'),
    r.getAttribute('TargetMode'),
  ].join(' ');
  final Map<String, XmlElement> old = <String, XmlElement>{
    for (final XmlElement r in before.relationshipsOf(before.mainRels))
      r.getAttribute('Id') ?? '': r,
  };
  final Set<String> types = _addedTypes(created: allowCreated);
  final List<String> problems = <String>[];
  for (final XmlElement r in after.relationshipsOf(before.mainRels)) {
    final String id = r.getAttribute('Id') ?? '';
    final XmlElement? was = old.remove(id);
    if (was != null) {
      if (key(was) != key(r)) {
        problems.add(
          'a relationship the edits removed or changed: '
          '${before.mainRels}: ${key(was)}',
        );
      }
      continue;
    }
    final String type = r.getAttribute('Type') ?? '';
    if (!types.contains(type.substring(type.lastIndexOf('/') + 1))) {
      problems.add(
        'a relationship the edits do not add: ${before.mainRels}: ${key(r)}',
      );
    }
  }
  for (final XmlElement r in old.values) {
    problems.add(
      'a relationship the edits removed or changed: '
      '${before.mainRels}: ${key(r)}',
    );
  }
  return problems;
}

/// Where a package keeps the parts an edit may change.
final class _Layout {
  _Layout(Uint8List docx) : _archive = ZipDecoder().decodeBytes(docx) {
    final List<XmlElement> root = _relationships('_rels/.rels');
    final XmlElement? main = root
        .where((XmlElement r) => _type(r).endsWith('/officeDocument'))
        .firstOrNull;
    if (main == null) throw const FormatException('no officeDocument');
    String? rooted(String type) {
      for (final XmlElement r in root) {
        if (_type(r).endsWith('/$type') &&
            r.getAttribute('TargetMode') != 'External') {
          return _resolve('', r.getAttribute('Target') ?? '');
        }
      }
      return null;
    }

    corePart = rooted('core-properties');
    appPart = rooted('extended-properties');
    mainPart = _resolve('', main.getAttribute('Target') ?? '');
    final int slash = mainPart.lastIndexOf('/');
    final String dir = slash < 0 ? '' : mainPart.substring(0, slash + 1);
    mainRels = '${dir}_rels/${mainPart.substring(slash + 1)}.rels';
    mediaDir = '${dir}media/';
    String related(String type, String fallback) {
      for (final XmlElement r in _relationships(mainRels)) {
        if (_type(r).endsWith('/$type')) {
          return _resolve(dir, r.getAttribute('Target') ?? '');
        }
      }
      return '$dir$fallback';
    }

    stylesPart = related('styles', 'styles.xml');
    numberingPart = related('numbering', 'numbering.xml');
    footerParts = <String>{
      for (final XmlElement r in _relationships(mainRels))
        if (_type(r).endsWith('/footer'))
          _resolve(dir, r.getAttribute('Target') ?? ''),
    };
  }

  final Archive _archive;

  /// The main part, from the root `officeDocument` relationship.
  late final String mainPart;

  /// The relationships of the main part.
  late final String mainRels;

  /// Where the model puts a new media part: `media/` beside the main part.
  late final String mediaDir;

  /// The core properties part the root relationship names, or null.
  late final String? corePart;

  /// The extended properties part the root relationship names, or null.
  late final String? appPart;

  /// The styles part, or where the model creates one.
  late final String stylesPart;

  /// The numbering part, or where the model creates one.
  late final String numberingPart;

  /// The parts the main part's relationships name as a footer.
  late final Set<String> footerParts;

  bool has(String part) => _archive.findFile(part) != null;

  /// The bytes of [part], or null when the package has no such entry.
  List<int>? read(String part) => _archive.findFile(part)?.content;

  String _type(XmlElement r) => r.getAttribute('Type') ?? '';

  /// The relationships of the relationships part [part], empty when the
  /// package has none.
  List<XmlElement> relationshipsOf(String part) => _relationships(part);

  List<XmlElement> _relationships(String part) {
    final List<int>? file = read(part);
    if (file == null) return const <XmlElement>[];
    return XmlDocument.parse(utf8.decode(file)).rootElement.childElements
        .where((XmlElement e) => e.namespaceUri == _relsNs)
        .toList();
  }

  /// The part name of [target] relative to the directory [dir] (with a
  /// trailing slash), or from the package root when it starts with `/`.
  String _resolve(String dir, String target) {
    final String path = target.startsWith('/') ? target : '$dir$target';
    final List<String> out = <String>[];
    for (final String segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(segment);
    }
    return out.join('/');
  }
}

/// For each block of [body], whether it must not be replaced because its
/// `w:pPr` holds a `w:sectPr`, which the model keeps but does not show.
///
/// The blocks are matched with the children of `w:body` other than its own
/// `w:sectPr`, in order; when their numbers differ, every block is kept.
List<bool> _mustKeep(Uint8List docx, DocxBody body) {
  final List<bool> all = List<bool>.filled(body.blocks.length, true);
  try {
    final _Layout layout = _Layout(docx);
    final List<int>? main = layout.read(layout.mainPart);
    if (main == null) return all;
    final XmlElement? bodyXml = XmlDocument.parse(utf8.decode(main))
        .rootElement
        .childElements
        .where((XmlElement e) {
          return e.namespaceUri == _wNs && e.localName == 'body';
        })
        .firstOrNull;
    if (bodyXml == null) return all;
    final List<XmlElement> children = bodyXml.childElements
        .where(
          (XmlElement e) =>
              !(e.namespaceUri == _wNs && e.localName == 'sectPr'),
        )
        .toList();
    if (children.length != body.blocks.length) return all;
    return <bool>[
      for (final XmlElement c in children)
        c.childElements.any(
          (XmlElement pPr) =>
              pPr.namespaceUri == _wNs &&
              pPr.localName == 'pPr' &&
              pPr.childElements.any(
                (XmlElement e) =>
                    e.namespaceUri == _wNs && e.localName == 'sectPr',
              ),
        ),
    ];
  } on Object {
    return all;
  }
}

/// The inlines of [paragraph] as they are in the file: a field's runs count,
/// so what the tool edits does not depend on what the model types as a field.
/// A hyperlink is one inline, as the opaque inline it was before D5, so the
/// run the tool edits is the one it edited then.
List<DocxInline> _flat(DocxParagraph paragraph) {
  final List<DocxInline> out = <DocxInline>[];
  void add(DocxInline inline) {
    if (inline is DocxField) {
      heldInlinesOf(inline)!.forEach(add);
    } else {
      out.add(inline);
    }
  }

  paragraph.inlines.forEach(add);
  return out;
}

/// The block and [_flat] index of the first run of a body paragraph whose
/// text is not empty, or null when there is none.
({int block, int inline})? _firstRunWithText(DocxBody body) {
  for (int b = 0; b < body.blocks.length; b++) {
    final DocxBlock block = body.blocks[b];
    if (block is! DocxParagraph) continue;
    final List<DocxInline> inlines = _flat(block);
    for (int i = 0; i < inlines.length; i++) {
      final DocxInline inline = inlines[i];
      if (inline is DocxRun && inline.text.isNotEmpty) {
        return (block: b, inline: i);
      }
    }
  }
  return null;
}

/// The index of the last paragraph of [body] whose inlines are all runs
/// without a field or a drawing, and whose `w:pPr` holds no `w:sectPr`
/// ([keep] is true for it otherwise), other than the block [edited], or
/// null when there is none.
int? _paragraphToReplace(DocxBody body, int? edited, List<bool> keep) {
  for (int b = body.blocks.length - 1; b >= 0; b--) {
    final DocxBlock block = body.blocks[b];
    if (b == edited || block is! DocxParagraph || keep[b]) continue;
    if (block.inlines.every(_isPlainRun)) return b;
  }
  return null;
}

/// Whether [inline] is a run that holds no field and no drawing, or a
/// proofing mark (`w:proofErr`), which pairs with nothing outside its
/// paragraph and is lost with it.
bool _isPlainRun(DocxInline inline) => switch (inline) {
  DocxRun() => !inline.content.any(
    (DocxRunContent c) =>
        c is DocxFieldMark ||
        c is DocxFieldInstruction ||
        c is DocxPicture ||
        c is DocxOpaqueRunContent && _fieldOrDrawing.contains(c.localName),
  ),
  DocxOpaqueInline() => inline.localName == 'proofErr',
  DocxField() => false,
  // A bookmark mark pairs with one outside the paragraph, as the opaque
  // inline it was before D5 did.
  DocxBookmarkStart() || DocxBookmarkEnd() => false,
  // Not a proofing mark, as the opaque inline it was before D5.
  DocxHyperlink() => false,
};

/// The table edits the read-back [blocks] lack.
List<String> _checkTables(List<DocxBlock> blocks, _Edits edits) {
  final List<String> problems = <String>[];
  final ({int block, int rows, bool added})? edited = edits.table;
  if (edited != null) {
    final DocxBlock b = blocks[edited.block];
    if (b is! DocxTable || b.rows.isEmpty || b.rows.first.cells.isEmpty) {
      problems.add('the edited table is missing');
    } else {
      final DocxParagraph? p = b.rows.first.cells.first.blocks
          .whereType<DocxParagraph>()
          .firstOrNull;
      final DocxRun? r = p == null
          ? null
          : _flat(p).whereType<DocxRun>().firstOrNull;
      if (r == null || r.text != editedCellText) {
        problems.add('the edited cell text is missing');
      }
      final int rows = edited.rows + (edited.added ? 1 : 0);
      if (b.rows.length != rows) {
        problems.add('the edited table has ${b.rows.length} rows, not $rows');
      } else if (edited.added && b.rows.last.cells.first.text != newRowText) {
        problems.add('the new row text is missing');
      }
    }
  }
  final DocxBlock added = blocks[edits.tableBlock];
  if (added is! DocxTable || added.rows.length != 3) {
    problems.add('the added table is missing');
    return problems;
  }
  final List<DocxTableRow> rows = added.rows;
  if (!rows[0].isHeader ||
      rows[0].cells.map((DocxTableCell c) => c.text).join('|') !=
          'Head one|Head two') {
    problems.add('the added table header row is missing');
  }
  if (rows[1].cells.map((DocxTableCell c) => c.text).join('|') !=
      'Body one|Body two') {
    problems.add('the added table body row is missing');
  }
  if (rows[2].cells.length != 1 ||
      rows[2].cells.first.text != 'Merged' ||
      rows[2].cells.first.properties.gridSpan != 2) {
    problems.add('the added table merged row is missing');
  }
  return problems;
}

/// Whether the last paragraph of [story] is the one [_addFooter] adds.
bool _hasFooterParagraph(DocxHeaderFooter story) {
  final DocxBlock? last = story.blocks.lastOrNull;
  if (last is! DocxParagraph || last.inlines.length != 4) return false;
  final [DocxInline start, DocxInline page, DocxInline of, DocxInline pages] =
      last.inlines;
  return start is DocxRun &&
      start.text == footerPageText &&
      page is DocxField &&
      page.instruction == ' PAGE ' &&
      of is DocxRun &&
      of.text == footerOfText &&
      pages is DocxField &&
      pages.instruction == ' NUMPAGES ';
}

/// The section edits [doc] lacks when read back: the new last section, on its
/// landscape page, the break before the table, the footer of the section that
/// was last, which the new one shows too, and the table's width.
List<String> _checkSections(DocxDocument doc, _Edits edits) {
  final List<DocxSection> sections = doc.sections;
  if (sections.length != edits.sections + 1) {
    return <String>[
      'the document has ${sections.length} sections, '
          'not ${edits.sections + 1}',
    ];
  }
  final DocxSection last = sections.last;
  final DocxSection ended = sections[sections.length - 2];
  final DocxBlock broken = doc.body.blocks[edits.tableBlock - 1];
  final DocxBlock table = doc.body.blocks[edits.tableBlock];
  return <String>[
    if (edits.tableBlock - edits.blocks > 1)
      'the break added ${edits.tableBlock - edits.blocks} blocks',
    if (last.pageSize != DocxPageSize.a4(landscape: true))
      'the new section is not landscape A4',
    if (last.start != DocxSectionStart.nextPage)
      'the new section does not start on the next page',
    if (broken is! DocxParagraph || !identical(broken.section, ended))
      'the break is not before the added table',
    if (!_hasFooterParagraph(ended.footer) || !_hasFooterParagraph(last.footer))
      'the footer of the last section is missing',
    if (table is DocxTable && !_fills(table, last))
      'the added table is not as wide as the section',
  ];
}

/// Whether the two columns of [table] share the text width of [section], less
/// the 10 twips of `addTable`, or the 9062 twips it has without one.
bool _fills(DocxTable table, DocxSection section) {
  final double? width = section.textWidthPt;
  final int twips = width == null ? 9062 : (width * 20).round() - 10;
  return table.gridColumnsPt?.first == (twips ~/ 2) / 20;
}

/// The picture, link, bookmark and title edits [doc] lacks when read back:
/// [links] must be the paragraph [_appendLinks] added and [heading] must hold
/// the bookmark.
List<String> _checkLinks(DocxDocument doc, DocxBlock links, DocxBlock heading) {
  final List<String> problems = <String>[];
  final List<DocxInline> inlines = links is DocxParagraph
      ? links.inlines
      : const <DocxInline>[];
  if (links is! DocxParagraph || links.text != linksText) {
    problems.add('the paragraph of the picture and links is missing');
  }
  final DocxPicture? picture = inlines
      .whereType<DocxRun>()
      .expand((DocxRun r) => r.content)
      .whereType<DocxPicture>()
      .firstOrNull;
  if (picture == null ||
      picture.image != OfficeImage(png4x2) ||
      picture.widthPt != 3 ||
      picture.heightPt != 1.5) {
    problems.add('the added picture is missing');
  }
  final List<DocxHyperlink> hyperlinks = inlines
      .whereType<DocxHyperlink>()
      .toList();
  if (!hyperlinks.any(
    (DocxHyperlink h) => h.url == externalUrl && h.text == externalLinkText,
  )) {
    problems.add('the external link is missing');
  }
  if (!hyperlinks.any(
    (DocxHyperlink h) => h.anchor == bookmarkName && h.text == internalLinkText,
  )) {
    problems.add('the internal link is missing');
  }
  final List<DocxInline> marks = heading is DocxParagraph
      ? heading.inlines
      : const <DocxInline>[];
  final DocxInline? first = marks.firstOrNull;
  final DocxInline? last = marks.lastOrNull;
  if (first is! DocxBookmarkStart ||
      first.name != bookmarkName ||
      first.id == null ||
      last is! DocxBookmarkEnd ||
      last.id != first.id) {
    problems.add('the bookmark is missing');
  }
  if (doc.properties.title != editedText) {
    problems.add('the title is missing');
  }
  return problems;
}

/// The edits [saved] lacks when read back with `DocxDocument`.
List<String> _check(Uint8List saved, _Edits edits) {
  final List<String> problems = <String>[];
  try {
    final DocxDocument doc = DocxDocument.open(saved);
    final List<DocxBlock> blocks = doc.body.blocks;
    // The table, the paragraph of the picture and links, the heading and the
    // two items, after any paragraph `addSection` added for its break.
    final int expected = edits.tableBlock + 5;
    if (blocks.length != expected) {
      problems.add('the body has ${blocks.length} blocks, not $expected');
      return problems;
    }
    problems.addAll(_checkTables(blocks, edits));
    problems.addAll(_checkSections(doc, edits));
    final ({int block, int inline})? run = edits.run;
    if (run != null) {
      final DocxBlock b = blocks[run.block];
      final List<DocxInline> inlines = b is DocxParagraph
          ? _flat(b)
          : const <DocxInline>[];
      final DocxInline? i = run.inline < inlines.length
          ? inlines[run.inline]
          : null;
      if (i is! DocxRun || i.text != editedText) {
        problems.add('the edited run text is missing');
      } else if (i.properties.bold != true) {
        problems.add('the edited run is not bold');
      } else if (i.properties.color !=
          DocxColor.theme(DocxThemeColor.accent1)) {
        problems.add('the edited run is not accent 1');
      }
    }
    final int? replaced = edits.replaced;
    if (replaced != null) {
      final DocxBlock b = blocks[replaced];
      if (b is! DocxParagraph || b.text != replacedText) {
        problems.add('the replacing paragraph is missing');
      }
    }
    final DocxBlock heading = blocks[blocks.length - 3];
    if (heading is! DocxParagraph ||
        heading.text != addedText ||
        heading.style != edits.style) {
      problems.add('the added ${edits.style} paragraph is missing');
    }
    problems.addAll(_checkLinks(doc, blocks[blocks.length - 4], heading));
    final List<(String, int)> items = <(String, int)>[
      (firstItemText, 0),
      (secondItemText, 1),
    ];
    for (int k = 0; k < items.length; k++) {
      final DocxBlock b = blocks[blocks.length - 2 + k];
      final DocxNumberingRef? ref = b is DocxParagraph
          ? b.properties.numbering
          : null;
      if (b is! DocxParagraph ||
          b.text != items[k].$1 ||
          ref == null ||
          ref.numId != edits.numId ||
          ref.level != items[k].$2) {
        problems.add('the list item "${items[k].$1}" is missing');
      }
    }
  } on Object catch (e) {
    problems.add('reading the saved document failed: $e');
  }
  return problems;
}
