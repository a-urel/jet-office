/// Test helper: a consistency checker for generated XLSX files.
///
/// It checks the rules Excel enforces when it opens a file and refuses with
/// "We found a problem with some content". Every violation starts with
/// `rule N:`, N being the rule's number below. Later milestones add rules.
///
/// 1. every `.xml`, `.rels` and `.vml` part is well-formed XML;
/// 2. every relationship target exists;
/// 3. every part has a content type, and every override names a part;
/// 4. `sst/@count` equals the number of `t="s"` cells and
///    `sst/@uniqueCount` the number of `si`;
/// 5. every `t="s"` index is below `uniqueCount`;
/// 6. sheet names (after decoding `_xHHHH_`, as Excel does) are unique
///    ignoring case, at most 31 UTF-16 code units, free of `[]:*?/\`, not
///    the reserved `History` and not starting or ending with an apostrophe;
/// 7. `workbookView/@activeTab` is a valid sheet index;
/// 8. every cell `s` is below the `cellXfs` count;
/// 9. cell references in a row strictly increase and sit on that row;
/// 10. every formula (`<f>`) is non-empty and at most 8,192 UTF-16 code
///     units once its `_xHHHH_` escapes are decoded;
/// 11. row numbers (`row/@r`) strictly increase within a sheet;
/// 12. `cellXfs/@count` equals the number of its `xf` children;
/// 13. every `numFmtId` of 164 or more used by a `cellXfs` `xf` is declared
///     in `numFmts`;
/// 14. the `count` of `fonts`, `fills`, `borders` and `cellStyleXfs` equals
///     the number of their children; every `xf`'s `fontId`, `fillId` and
///     `borderId` is below the count of its table; fill 0 is
///     `patternType="none"` and fill 1 is `gray125`;
/// 15. worksheet children are elements `CT_Worksheet` knows, in its order,
///     each at most once (`conditionalFormatting` may repeat);
/// 16. every `<col>` has `1 <= min <= max <= 16384`, the ranges ascend
///     without overlapping, and `style` is below the `cellXfs` count;
/// 17. every `row/@outlineLevel` and `col/@outlineLevel` is in `0..7` and
///     at most `sheetFormatPr/@outlineLevelRow` or `@outlineLevelCol`
///     (0 when absent), and every `row/@ht` is in `0..409`;
/// 18. at least one `sheet` has no `state` (or `state="visible"`), and the
///     `activeTab` sheet is not hidden;
/// 19. a frozen `pane` has `topLeftCell` at the cell (`ySplit`, `xSplit`),
///     and `activePane` is `bottomRight` when both splits are non-zero,
///     `topRight` when only `xSplit` is and `bottomLeft` when only `ySplit`
///     is; a frozen pane with neither split, `xSplit` above 16383 or
///     `ySplit` above 1048575 is wrong too;
/// 20. every `mergeCell` covers at least two cells inside the sheet, with
///     its first corner not after its last; no two merges of a sheet
///     overlap; and `mergeCells/@count` equals the number of its children;
/// 21. defined names are unique per scope (the name ignoring case, and
///     `localSheetId`, which is absent for the workbook scope); every
///     `localSheetId` is a number below the sheet count; every
///     `autoFilter/@ref` is a valid range inside the sheet; and each sheet
///     with an `autoFilter` has exactly one `_xlnm._FilterDatabase` name,
///     sheet-scoped to it and spelling `'<sheet name>'!<absolute ref>`,
///     while a sheet without one has none; every `_xlnm.*` name has a
///     `localSheetId` (Excel scopes its built-in names to a sheet); and no
///     `definedName` has empty text;
/// 22. every `hyperlink` has a `ref` that is a valid range inside the
///     sheet and an `r:id` or a `location`; every `r:id` resolves in the
///     sheet's relationships to a hyperlink relationship whose
///     `TargetMode` is `External`; no two `hyperlink` elements of a sheet
///     share a `ref`; and a sheet has at most 65,530 of them;
/// 23. `dataValidations/@count` equals its `dataValidation` children; every
///     range of every `sqref` is a valid range inside the sheet; no two
///     ranges of a sheet's validations overlap; `formula1` is present
///     unless the type is `none` (or absent); and `formula2` is present for
///     `between` (the default operator) and `notBetween` on `whole`,
///     `decimal`, `date`, `time` and `textLength`;
/// 24. every range of every `conditionalFormatting/@sqref` is a valid range
///     inside the sheet; every `cfRule` has a `priority` of 1 or more,
///     unique on its sheet; every `dxfId` is below `dxfs/@count` (0 when
///     absent); a `cellIs` rule has one `formula`, or two for `between`
///     and `notBetween`; an `expression`, `containsText`,
///     `notContainsText`, `beginsWith` or `endsWith` rule has one; and a
///     `colorScale` has 2 or 3 `cfvo` and as many `color` children;
/// 25. in the Excel 2010 extensions of conditional formats: every `x14:id`
///     in the `extLst` of a `cfRule` names exactly one `x14:cfRule` of the
///     worksheet's `extLst`, and every `x14:cfRule` is named by exactly one
///     `x14:id`, except an x14-only rule (one no `x14:id` names), which
///     has a `priority` of 1 or more, unique among the sheet's `cfRule` and
///     x14-only priorities; no two `x14:cfRule` of the workbook share an
///     `id`; and a worksheet's `extLst` is its last child; an unnamed
///     `x14:cfRule` counts as x14-only only when it is an icon set of an
///     x14-only type (`3Stars`, `3Triangles`, `5Boxes` or `NoIcons`), any
///     other is a violation; and the `ext/@uri` of a `cfRule`'s `extLst` is
///     `{B025F937-C7B1-47D3-B67F-A62EFF666E3E}` and that of the worksheet's
///     `extLst` is `{78C0D931-6437-407d-A8EE-F0AAD7539E65}`, compared
///     exactly;
/// 26. every `sheetProtection/@password` and
///     `workbookProtection/@workbookPassword` is four uppercase hexadecimal
///     digits, and every `sheetProtection` has `sheet="1"`;
/// 27. in `docProps/custom.xml`, every `property` has a `pid` that is an
///     integer of at least 2, unique in the part, a `name` no earlier
///     property has (ignoring case), the `fmtid`
///     `{D5CDD505-2E9C-101B-9397-08002B2CF9AE}` and exactly one value child,
///     which is in the `vt:` namespace;
/// 28. every `si` of the shared strings holds either one `t`, or one or
///     more `r` and nothing else; and every `r` holds exactly one `t` and
///     at most one `rPr`, and nothing else;
/// 29. in a sheet's comments part, every `comment/@ref` is a single cell
///     inside the sheet, unique in its part, and every `authorId` is below
///     the number of `author`s; a sheet with a comments relationship has a
///     `legacyDrawing`, whose `r:id` is a VML drawing relationship of the
///     sheet, and that drawing holds exactly one `Note` shape per comment,
///     on the comment's cell by its `x:Row` and `x:Column` (zero-based),
///     and no `Note` shape without a comment; in every VML drawing, every
///     `x:Anchor` is 8 integers whose columns (the 1st and 5th) are within
///     0..16383 and rows (the 3rd and 7th) within 0..1048575, with left not
///     after right and top not after bottom; every `o:idmap` block is a
///     number listed by one drawing of the workbook only; and every
///     `v:shape/@id` is unique across the workbook and, when it is
///     `_x0000_s{n}`, n ÷ 1024 is a block of its drawing's `o:idmap`.
///
/// Element lookups use local names and assume the default SpreadsheetML
/// namespace: a part that declares a prefix for it (`<x:row>`) is not found.
/// The writer never does. Rule 25 matches the Excel 2010 elements by
/// namespace, whatever their prefix, and so does rule 29 the VML elements.
///
/// Pure Dart (no `dart:io`), so it runs in a browser too.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/xlsx/sheet_name.dart' show sheetNameKey;
import 'package:xml/xml.dart';

import '../../tool/src/csv_compare.dart' show decodeXstring;

const String _contentTypesPart = '[Content_Types].xml';
const String _sharedStringsPart = 'xl/sharedStrings.xml';
const String _stylesPart = 'xl/styles.xml';
const String _workbookPart = 'xl/workbook.xml';
final RegExp _sheetPart = RegExp(r'^xl/worksheets/[^/]+\.xml$');
final RegExp _forbiddenInName = RegExp(r'[\[\]:*?/\\]');
final RegExp _cellRef = RegExp(r'^([A-Z]+)([0-9]+)$');
final RegExp _legacyHash = RegExp(r'^[0-9A-F]{4}$');
final RegExp _rangeRef = RegExp(r'^([A-Z]+)([0-9]+)(?::([A-Z]+)([0-9]+))?$');

/// The violations found in the XLSX file [bytes]; empty means clean.
List<String> checkXlsx(Uint8List bytes) {
  final List<String> violations = <String>[];
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    return <String>['rule 1: not a readable ZIP archive ($e)'];
  }

  final Map<String, Uint8List> raw = <String, Uint8List>{
    for (final ArchiveFile f in archive.files)
      if (f.isFile) f.name: Uint8List.fromList(f.content),
  };

  // Rule 1.
  final Map<String, XmlDocument> docs = <String, XmlDocument>{};
  raw.forEach((String name, Uint8List data) {
    if (!name.endsWith('.xml') &&
        !name.endsWith('.rels') &&
        !name.endsWith('.vml')) {
      return;
    }
    try {
      docs[name] = XmlDocument.parse(utf8.decode(data));
    } on Object catch (e) {
      violations.add('rule 1: $name is not well-formed XML ($e)');
    }
  });

  _checkRelationships(raw, docs, violations);
  _checkContentTypes(raw, docs, violations);
  final List<String> sheetNames = _checkSheetNames(docs, violations);
  _checkActiveTab(docs, sheetNames.length, violations);
  _checkSharedStrings(docs, violations);
  _checkCells(docs, violations);
  _checkFormulas(docs, violations);
  _checkRowOrder(docs, violations);
  _checkStyles(docs, violations);
  _checkStyleTables(docs, violations);
  _checkWorksheetOrder(docs, violations);
  _checkColumns(docs, violations);
  _checkOutlines(docs, violations);
  _checkVisibility(docs, violations);
  _checkFrozenPanes(docs, violations);
  _checkMerges(docs, violations);
  _checkDefinedNames(docs, violations);
  _checkAutoFilters(docs, violations);
  _checkFilterNames(docs, violations);
  _checkHyperlinks(docs, violations);
  _checkDataValidations(docs, violations);
  _checkConditionalFormats(docs, violations);
  _checkConditionalExtensions(docs, violations);
  _checkProtection(docs, violations);
  _checkCustomProperties(docs, violations);
  _checkSharedStringItems(docs, violations);
  _checkNotes(docs, violations);
  _checkVmlDrawings(docs, violations);
  return violations;
}

String _attr(XmlElement e, String name) => e.getAttribute(name) ?? '';

Iterable<XmlElement> _all(XmlDocument doc, String local) =>
    doc.findAllElements(local);

/// Rule 2: every internal relationship target exists.
void _checkRelationships(
  Map<String, Uint8List> raw,
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  docs.forEach((String name, XmlDocument doc) {
    if (!name.endsWith('.rels')) return;
    final String dir = _dirOf(_sourceOf(name));
    for (final XmlElement rel in _all(doc, 'Relationship')) {
      if (_attr(rel, 'TargetMode') == 'External') continue;
      final String target = _attr(rel, 'Target');
      final String resolved = _resolve(dir, target);
      if (!raw.containsKey(resolved)) {
        violations.add(
          'rule 2: $name: target "$target" resolves to $resolved, which '
          'does not exist',
        );
      }
    }
  });
}

/// The part a `.rels` part describes: `xl/_rels/workbook.xml.rels` is the
/// relationships of `xl/workbook.xml`; `_rels/.rels` those of the package.
String _sourceOf(String relsName) {
  final int slash = relsName.lastIndexOf('/');
  final String dir = slash < 0 ? '' : relsName.substring(0, slash);
  final String file = relsName.substring(slash + 1);
  final String parent = dir == '_rels'
      ? ''
      : dir.endsWith('/_rels')
      ? dir.substring(0, dir.length - '_rels'.length)
      : dir.isEmpty
      ? ''
      : '$dir/';
  final String source = file.endsWith('.rels')
      ? file.substring(0, file.length - '.rels'.length)
      : file;
  return '$parent$source';
}

String _dirOf(String part) {
  final int slash = part.lastIndexOf('/');
  return slash < 0 ? '' : part.substring(0, slash + 1);
}

/// Resolves [target] against the directory [dir] (with trailing slash)
/// following OPC: a leading `/` is absolute; `.` and `..` segments fold.
String _resolve(String dir, String target) {
  final String full = target.startsWith('/')
      ? target.substring(1)
      : '$dir$target';
  final List<String> out = <String>[];
  for (final String segment in full.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(segment);
    }
  }
  return out.join('/');
}

/// Rule 3: content types cover every part; overrides name existing parts.
void _checkContentTypes(
  Map<String, Uint8List> raw,
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  final XmlDocument? doc = docs[_contentTypesPart];
  if (doc == null) {
    if (!raw.containsKey(_contentTypesPart)) {
      violations.add('rule 3: $_contentTypesPart is missing');
    }
    return;
  }
  final Set<String> defaults = <String>{
    for (final XmlElement d in _all(doc, 'Default'))
      _attr(d, 'Extension').toLowerCase(),
  };
  final Set<String> overrides = <String>{};
  for (final XmlElement o in _all(doc, 'Override')) {
    final String part = _attr(o, 'PartName');
    overrides.add(part);
    if (!raw.containsKey(part.startsWith('/') ? part.substring(1) : part)) {
      violations.add('rule 3: override names missing part $part');
    }
  }
  for (final String name in raw.keys) {
    if (name == _contentTypesPart) continue;
    final int dot = name.lastIndexOf('.');
    final String ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (!overrides.contains('/$name') && !defaults.contains(ext)) {
      violations.add('rule 3: part $name has no content type');
    }
  }
}

/// Rule 6; returns the sheet names in workbook order.
List<String> _checkSheetNames(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  final XmlDocument? doc = docs[_workbookPart];
  if (doc == null) return const <String>[];
  final List<String> names = <String>[
    for (final XmlElement s in _all(doc, 'sheet'))
      decodeXstring(_attr(s, 'name')),
  ];
  final Map<String, String> seen = <String, String>{};
  for (final String name in names) {
    final String key = sheetNameKey(name);
    final String? earlier = seen[key];
    if (earlier != null) {
      violations.add('rule 6: sheet "$name" duplicates "$earlier"');
    }
    seen[key] = name;
    if (name.isEmpty || name.length > 31) {
      violations.add(
        'rule 6: sheet name "$name" has ${name.length} characters; '
        'expected 1 to 31',
      );
    }
    if (sheetNameKey(name) == sheetNameKey('History')) {
      violations.add('rule 6: sheet name "$name" is reserved');
    }
    if (name.startsWith("'") || name.endsWith("'")) {
      violations.add(
        'rule 6: sheet name "$name" starts or ends with an apostrophe',
      );
    }
    if (_forbiddenInName.hasMatch(name)) {
      violations.add('rule 6: sheet name "$name" has a forbidden character');
    }
  }
  return names;
}

/// Rule 7.
void _checkActiveTab(
  Map<String, XmlDocument> docs,
  int sheetCount,
  List<String> violations,
) {
  final XmlDocument? doc = docs[_workbookPart];
  if (doc == null) return;
  for (final XmlElement view in _all(doc, 'workbookView')) {
    final String text = view.getAttribute('activeTab') ?? '0';
    final int? index = int.tryParse(text);
    if (index == null || index < 0 || index >= sheetCount) {
      violations.add(
        'rule 7: activeTab "$text" is not a valid index for $sheetCount '
        'sheets',
      );
    }
  }
}

Iterable<MapEntry<String, XmlDocument>> _sheets(
  Map<String, XmlDocument> docs,
) => docs.entries.where(
  (MapEntry<String, XmlDocument> e) => _sheetPart.hasMatch(e.key),
);

/// Rules 4 and 5.
void _checkSharedStrings(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  int cells = 0;
  final List<(String, int)> indexes = <(String, int)>[];
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement c in _all(sheet.value, 'c')) {
      if (_attr(c, 't') != 's') continue;
      cells++;
      final String v = c.getElement('v')?.innerText ?? '';
      final int? index = int.tryParse(v);
      if (index == null) {
        violations.add(
          'rule 5: ${sheet.key}: string index "$v" is not a number',
        );
      } else {
        indexes.add((sheet.key, index));
      }
    }
  }
  final XmlDocument? sst = docs[_sharedStringsPart];
  if (sst == null) {
    if (cells > 0) {
      violations.add('rule 4: $cells string cells but no $_sharedStringsPart');
    }
    for (final (String part, int index) in indexes) {
      violations.add(
        'rule 5: $part: string index $index has no $_sharedStringsPart to '
        'point into',
      );
    }
    return;
  }
  final XmlElement root = sst.rootElement;
  final int si = root.findElements('si').length;
  final int? count = int.tryParse(_attr(root, 'count'));
  final int? unique = int.tryParse(_attr(root, 'uniqueCount'));
  if (count != cells) {
    violations.add('rule 4: sst count is $count but $cells cells use strings');
  }
  if (unique != si) {
    violations.add('rule 4: sst uniqueCount is $unique but there are $si si');
  }
  for (final (String part, int index) in indexes) {
    if (index < 0 || index >= (unique ?? 0)) {
      violations.add(
        'rule 5: $part: string index $index is not below uniqueCount '
        '$unique',
      );
    }
  }
}

int _columnNumber(String letters) {
  int n = 0;
  for (final int unit in letters.codeUnits) {
    n = n * 26 + (unit - 0x40);
  }
  return n;
}

/// Rules 8 and 9.
void _checkCells(Map<String, XmlDocument> docs, List<String> violations) {
  final int? xfCount = _cellXfsCount(docs);
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement row in _all(sheet.value, 'row')) {
      final String rowText = _attr(row, 'r');
      int lastColumn = 0;
      for (final XmlElement c in row.findElements('c')) {
        final String ref = _attr(c, 'r');
        final RegExpMatch? m = _cellRef.firstMatch(ref);
        if (m == null) {
          violations.add(
            'rule 9: ${sheet.key}: "$ref" is not a cell reference',
          );
        } else {
          if (m.group(2) != rowText) {
            violations.add(
              'rule 9: ${sheet.key}: cell $ref is in row "$rowText"',
            );
          }
          final int column = _columnNumber(m.group(1)!);
          if (column <= lastColumn) {
            violations.add(
              'rule 9: ${sheet.key}: cell $ref does not follow the previous '
              'cell in its row',
            );
          }
          lastColumn = column;
        }
        final String s = _attr(c, 's');
        if (s.isNotEmpty) {
          final int? style = int.tryParse(s);
          if (xfCount == null ||
              style == null ||
              style < 0 ||
              style >= xfCount) {
            violations.add(
              'rule 8: ${sheet.key}: cell $ref has style "$s"; cellXfs '
              'count is $xfCount',
            );
          }
        }
      }
    }
  }
}

/// Rule 10.
void _checkFormulas(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement f in _all(sheet.value, 'f')) {
      // Excel decodes `_xHHHH_` in a formula; its limit is on that text.
      final String text = decodeXstring(f.innerText);
      final String ref = f.parentElement == null
          ? '?'
          : _attr(f.parentElement!, 'r');
      if (text.isEmpty) {
        violations.add('rule 10: ${sheet.key}: cell $ref has an empty formula');
      } else if (text.length > 8192) {
        violations.add(
          'rule 10: ${sheet.key}: cell $ref has a formula of ${text.length} '
          'characters; Excel accepts 8192',
        );
      }
    }
  }
}

/// Rule 11.
void _checkRowOrder(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    int last = 0;
    for (final XmlElement row in _all(sheet.value, 'row')) {
      final String text = _attr(row, 'r');
      final int? number = int.tryParse(text);
      if (number == null || number <= last) {
        violations.add(
          'rule 11: ${sheet.key}: row "$text" does not follow row $last',
        );
      }
      if (number != null) last = number;
    }
  }
}

/// Rules 12 and 13.
void _checkStyles(Map<String, XmlDocument> docs, List<String> violations) {
  final XmlDocument? styles = docs[_stylesPart];
  if (styles == null) return;
  final XmlElement? cellXfs = _all(styles, 'cellXfs').firstOrNull;
  if (cellXfs == null) return;
  final List<XmlElement> xfs = cellXfs.findElements('xf').toList();
  final String count = _attr(cellXfs, 'count');
  if (int.tryParse(count) != xfs.length) {
    violations.add(
      'rule 12: cellXfs count is "$count" but it has ${xfs.length} xf',
    );
  }
  final Set<int> declared = <int>{
    for (final XmlElement f in _all(styles, 'numFmt'))
      if (int.tryParse(_attr(f, 'numFmtId')) case final int id) id,
  };
  for (int i = 0; i < xfs.length; i++) {
    final int? id = int.tryParse(_attr(xfs[i], 'numFmtId'));
    if (id != null && id >= 164 && !declared.contains(id)) {
      violations.add(
        'rule 13: cellXfs xf $i uses numFmtId $id, which numFmts does not '
        'declare',
      );
    }
  }
}

/// Rule 14.
void _checkStyleTables(Map<String, XmlDocument> docs, List<String> violations) {
  final XmlDocument? styles = docs[_stylesPart];
  if (styles == null) return;
  final XmlElement root = styles.rootElement;
  final Map<String, int> sizes = <String, int>{};
  for (final (String table, String child) in <(String, String)>[
    ('fonts', 'font'),
    ('fills', 'fill'),
    ('borders', 'border'),
    ('cellStyleXfs', 'xf'),
  ]) {
    final XmlElement? element = root.getElement(table);
    if (element == null) {
      violations.add('rule 14: styles.xml has no $table');
      continue;
    }
    final int children = element.findElements(child).length;
    sizes[table] = children;
    final String count = _attr(element, 'count');
    if (int.tryParse(count) != children) {
      violations.add(
        'rule 14: $table count is "$count" but it has $children $child',
      );
    }
  }
  for (final String list in <String>['cellStyleXfs', 'cellXfs']) {
    final List<XmlElement> xfs =
        root.getElement(list)?.findElements('xf').toList() ??
        const <XmlElement>[];
    for (int i = 0; i < xfs.length; i++) {
      for (final (String attribute, String table) in <(String, String)>[
        ('fontId', 'fonts'),
        ('fillId', 'fills'),
        ('borderId', 'borders'),
      ]) {
        final String text = _attr(xfs[i], attribute);
        final int? id = int.tryParse(text);
        final int? size = sizes[table];
        if (id == null || id < 0 || (size != null && id >= size)) {
          violations.add(
            'rule 14: $list xf $i has $attribute "$text"; $table holds '
            '$size',
          );
        }
      }
    }
  }
  final List<XmlElement> fills =
      root.getElement('fills')?.findElements('fill').toList() ??
      const <XmlElement>[];
  for (final (int index, String pattern) in <(int, String)>[
    (0, 'none'),
    (1, 'gray125'),
  ]) {
    final String? actual = index < fills.length
        ? fills[index].getElement('patternFill')?.getAttribute('patternType')
        : null;
    if (actual != pattern) {
      violations.add(
        'rule 14: fill $index has patternType "$actual"; Excel requires '
        '"$pattern"',
      );
    }
  }
}

/// The children of `CT_Worksheet`, in schema order (ECMA-376 Part 1,
/// §18.3.1.99).
const List<String> _worksheetChildren = <String>[
  'sheetPr',
  'dimension',
  'sheetViews',
  'sheetFormatPr',
  'cols',
  'sheetData',
  'sheetCalcPr',
  'sheetProtection',
  'protectedRanges',
  'scenarios',
  'autoFilter',
  'sortState',
  'dataConsolidate',
  'customSheetViews',
  'mergeCells',
  'phoneticPr',
  'conditionalFormatting',
  'dataValidations',
  'hyperlinks',
  'printOptions',
  'pageMargins',
  'pageSetup',
  'headerFooter',
  'rowBreaks',
  'colBreaks',
  'customProperties',
  'cellWatches',
  'ignoredErrors',
  'smartTags',
  'drawing',
  'legacyDrawing',
  'legacyDrawingHF',
  'drawingHF',
  'picture',
  'oleObjects',
  'controls',
  'webPublishItems',
  'tableParts',
  'extLst',
];

/// Rule 15.
void _checkWorksheetOrder(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    int last = -1;
    String? previous;
    for (final XmlElement child in sheet.value.rootElement.childElements) {
      final String local = child.name.local;
      final int index = _worksheetChildren.indexOf(local);
      if (index < 0) {
        violations.add(
          'rule 15: ${sheet.key}: <$local> is not a child of a worksheet',
        );
        continue;
      }
      if (index < last || (index == last && local != 'conditionalFormatting')) {
        violations.add(
          'rule 15: ${sheet.key}: <$local> after <$previous> breaks the '
          'CT_Worksheet order',
        );
      }
      last = index;
      previous = local;
    }
  }
}

/// The `cellXfs` count of styles.xml, or null when it has none.
int? _cellXfsCount(Map<String, XmlDocument> docs) {
  final XmlDocument? styles = docs[_stylesPart];
  final XmlElement? cellXfs = styles == null
      ? null
      : _all(styles, 'cellXfs').firstOrNull;
  return cellXfs == null ? null : int.tryParse(_attr(cellXfs, 'count'));
}

/// Rule 16.
void _checkColumns(Map<String, XmlDocument> docs, List<String> violations) {
  final int? xfCount = _cellXfsCount(docs);
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    int lastMax = 0;
    for (final XmlElement col in _all(sheet.value, 'col')) {
      final String minText = _attr(col, 'min');
      final String maxText = _attr(col, 'max');
      final int? min = int.tryParse(minText);
      final int? max = int.tryParse(maxText);
      if (min == null || max == null || min < 1 || min > max || max > 16384) {
        violations.add(
          'rule 16: ${sheet.key}: col min="$minText" max="$maxText" is not '
          'a range within 1..16384',
        );
      } else {
        if (min <= lastMax) {
          violations.add(
            'rule 16: ${sheet.key}: col $min..$max does not follow the '
            'previous range, which ends at $lastMax',
          );
        }
        lastMax = max;
      }
      final String s = _attr(col, 'style');
      if (s.isNotEmpty) {
        final int? style = int.tryParse(s);
        if (xfCount == null || style == null || style < 0 || style >= xfCount) {
          violations.add(
            'rule 16: ${sheet.key}: col $minText..$maxText has style "$s"; '
            'cellXfs count is $xfCount',
          );
        }
      }
    }
  }
}

/// Rule 17.
void _checkOutlines(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    final XmlElement? format = _all(sheet.value, 'sheetFormatPr').firstOrNull;
    for (final (String element, String limit) in <(String, String)>[
      ('row', 'outlineLevelRow'),
      ('col', 'outlineLevelCol'),
    ]) {
      final int deepest =
          int.tryParse(format?.getAttribute(limit) ?? '0') ?? -1;
      for (final XmlElement e in _all(sheet.value, element)) {
        final String text = e.getAttribute('outlineLevel') ?? '0';
        final int? level = int.tryParse(text);
        if (level == null || level < 0 || level > 7) {
          violations.add(
            'rule 17: ${sheet.key}: $element outlineLevel "$text" is not in '
            '0..7',
          );
        } else if (level > deepest) {
          violations.add(
            'rule 17: ${sheet.key}: $element outlineLevel $level is deeper '
            'than sheetFormatPr $limit $deepest',
          );
        }
      }
    }
    for (final XmlElement row in _all(sheet.value, 'row')) {
      final String? text = row.getAttribute('ht');
      if (text == null) continue;
      final double? height = double.tryParse(text);
      if (height == null || height < 0 || height > 409) {
        violations.add(
          'rule 17: ${sheet.key}: row ${_attr(row, 'r')} has ht "$text"; '
          'expected 0..409',
        );
      }
    }
  }
}

/// Rule 18.
void _checkVisibility(Map<String, XmlDocument> docs, List<String> violations) {
  final XmlDocument? doc = docs[_workbookPart];
  if (doc == null) return;
  final List<XmlElement> sheets = _all(doc, 'sheet').toList();
  if (sheets.isEmpty) return;
  bool hidden(XmlElement sheet) {
    final String? state = sheet.getAttribute('state');
    return state != null && state != 'visible';
  }

  if (sheets.every(hidden)) {
    violations.add('rule 18: every sheet is hidden; one must be visible');
  }
  for (final XmlElement view in _all(doc, 'workbookView')) {
    final int? index = int.tryParse(view.getAttribute('activeTab') ?? '0');
    if (index != null &&
        index >= 0 &&
        index < sheets.length &&
        hidden(sheets[index])) {
      violations.add(
        'rule 18: activeTab $index is the sheet '
        '"${_attr(sheets[index], 'name')}", which is '
        '${_attr(sheets[index], 'state')}',
      );
    }
  }
}

/// Rule 19.
void _checkFrozenPanes(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement pane in _all(sheet.value, 'pane')) {
      if (pane.getAttribute('state') != 'frozen') continue;
      final int x = int.tryParse(pane.getAttribute('xSplit') ?? '0') ?? -1;
      final int y = int.tryParse(pane.getAttribute('ySplit') ?? '0') ?? -1;
      if (x < 0 || y < 0 || (x == 0 && y == 0) || x > 16383 || y > 1048575) {
        violations.add(
          'rule 19: ${sheet.key}: frozen pane has xSplit '
          '"${_attr(pane, 'xSplit')}" and ySplit "${_attr(pane, 'ySplit')}"; '
          'expected whole numbers, one at least 1, xSplit at most 16383 and '
          'ySplit at most 1048575',
        );
        continue;
      }
      final String topLeft = '${_columnLetters(x)}${y + 1}';
      if (pane.getAttribute('topLeftCell') != topLeft) {
        violations.add(
          'rule 19: ${sheet.key}: frozen pane topLeftCell is '
          '"${_attr(pane, 'topLeftCell')}"; the splits ($x, $y) put it at '
          '"$topLeft"',
        );
      }
      final String active = x == 0
          ? 'bottomLeft'
          : y == 0
          ? 'topRight'
          : 'bottomRight';
      if (pane.getAttribute('activePane') != active) {
        violations.add(
          'rule 19: ${sheet.key}: frozen pane activePane is '
          '"${_attr(pane, 'activePane')}"; the splits make it "$active"',
        );
      }
    }
  }
}

/// The letters of the 0-based column [index], computed here so that the rule
/// does not lean on the writer's own conversion.
String _columnLetters(int index) {
  String letters = '';
  int n = index + 1;
  while (n > 0) {
    final int rest = (n - 1) % 26;
    letters = String.fromCharCode(65 + rest) + letters;
    n = (n - 1) ~/ 26;
  }
  return letters;
}

/// A rectangle of cells for rules 20 and 21: 1-based, inclusive.
typedef _Rect = ({int row1, int col1, int row2, int col2});

/// The rectangle of [ref] (`B2` or `B2:D10`), or null when [ref] is not a
/// range of cell references. It may lie outside the sheet or be reversed;
/// [_problemWith] says whether it does.
_Rect? _parseRect(String ref) {
  final RegExpMatch? m = _rangeRef.firstMatch(ref);
  if (m == null) return null;
  final int row1 = int.parse(m.group(2)!);
  final int col1 = _columnNumber(m.group(1)!);
  final bool two = m.group(3) != null;
  return (
    row1: row1,
    col1: col1,
    row2: two ? int.parse(m.group(4)!) : row1,
    col2: two ? _columnNumber(m.group(3)!) : col1,
  );
}

/// What is wrong with [r] as a range of the sheet, or null when nothing is.
String? _problemWith(_Rect r) {
  if (r.row1 < 1 || r.col1 < 1 || r.row2 > 1048576 || r.col2 > 16384) {
    return 'lies outside the sheet';
  }
  if (r.row1 > r.row2 || r.col1 > r.col2) {
    return 'has its first corner after its last';
  }
  return null;
}

/// Rule 20.
void _checkMerges(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement merges in _all(sheet.value, 'mergeCells')) {
      final List<XmlElement> cells = merges.findElements('mergeCell').toList();
      final String count = _attr(merges, 'count');
      if (int.tryParse(count) != cells.length) {
        violations.add(
          'rule 20: ${sheet.key}: mergeCells count is "$count" but it has '
          '${cells.length} mergeCell',
        );
      }
      final List<(String, _Rect)> seen = <(String, _Rect)>[];
      for (final XmlElement cell in cells) {
        final String ref = _attr(cell, 'ref');
        final _Rect? r = _parseRect(ref);
        final String? problem = r == null ? 'is not a range' : _problemWith(r);
        if (problem != null) {
          violations.add('rule 20: ${sheet.key}: mergeCell "$ref" $problem');
          continue;
        }
        if (r!.row1 == r.row2 && r.col1 == r.col2) {
          violations.add(
            'rule 20: ${sheet.key}: mergeCell "$ref" covers a single cell',
          );
        }
        for (final (String other, _Rect o) in seen) {
          if (r.row1 <= o.row2 &&
              o.row1 <= r.row2 &&
              r.col1 <= o.col2 &&
              o.col1 <= r.col2) {
            violations.add(
              'rule 20: ${sheet.key}: mergeCell "$ref" overlaps "$other"',
            );
          }
        }
        seen.add((ref, r));
      }
    }
  }
}

/// Rule 21, defined names.
void _checkDefinedNames(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  final XmlDocument? doc = docs[_workbookPart];
  if (doc == null) return;
  final int sheetCount = _all(doc, 'sheet').length;
  final Map<String, String> seen = <String, String>{};
  for (final XmlElement n in _all(doc, 'definedName')) {
    final String name = _attr(n, 'name');
    final String? scopeText = n.getAttribute('localSheetId');
    if (name.toLowerCase().startsWith('_xlnm.') && scopeText == null) {
      violations.add(
        'rule 21: defined name "$name" has no localSheetId; Excel scopes '
        'its built-in names to a sheet',
      );
    }
    if (n.innerText.trim().isEmpty) {
      violations.add('rule 21: defined name "$name" has no text');
    }
    String scope = 'workbook';
    if (scopeText != null) {
      final int? id = int.tryParse(scopeText);
      if (id == null || id < 0 || id >= sheetCount) {
        violations.add(
          'rule 21: defined name "$name" has localSheetId "$scopeText"; '
          'the workbook has $sheetCount sheets',
        );
      }
      scope = 'sheet ${id ?? scopeText}';
    }
    final String key = '${name.toLowerCase()}|$scope';
    if (seen.containsKey(key)) {
      violations.add(
        'rule 21: defined name "$name" is defined twice in $scope '
        '(as "${seen[key]}" too)',
      );
    }
    seen[key] = name;
  }
}

/// Rule 21, auto filter ranges.
void _checkAutoFilters(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement filter in _all(sheet.value, 'autoFilter')) {
      final String ref = _attr(filter, 'ref');
      final _Rect? r = _parseRect(ref);
      final String? problem = r == null ? 'is not a range' : _problemWith(r);
      if (problem != null) {
        violations.add('rule 21: ${sheet.key}: autoFilter ref "$ref" $problem');
      }
    }
  }
}

/// Rule 21, the `_xlnm._FilterDatabase` name of each filtered sheet.
void _checkFilterNames(Map<String, XmlDocument> docs, List<String> violations) {
  final XmlDocument? book = docs[_workbookPart];
  final XmlDocument? rels = docs['xl/_rels/workbook.xml.rels'];
  if (book == null || rels == null) return;
  final Map<String, String> targets = <String, String>{
    for (final XmlElement r in _all(rels, 'Relationship'))
      _attr(r, 'Id'): 'xl/${_attr(r, 'Target')}',
  };
  final List<XmlElement> names = <XmlElement>[
    for (final XmlElement n in _all(book, 'definedName'))
      if (_attr(n, 'name').toLowerCase() == '_xlnm._filterdatabase') n,
  ];
  final List<XmlElement> sheets = _all(book, 'sheet').toList();
  for (int index = 0; index < sheets.length; index++) {
    final String name = _attr(sheets[index], 'name');
    final XmlDocument? doc = docs[targets[_attr(sheets[index], 'r:id')]];
    if (doc == null) continue;
    final List<XmlElement> filters = _all(doc, 'autoFilter').toList();
    final List<XmlElement> mine = <XmlElement>[
      for (final XmlElement n in names)
        if (n.getAttribute('localSheetId') == '$index') n,
    ];
    if (filters.isEmpty) {
      if (mine.isNotEmpty) {
        violations.add(
          'rule 21: sheet "$name" has no autoFilter but a '
          '_xlnm._FilterDatabase name',
        );
      }
      continue;
    }
    if (mine.length != 1) {
      violations.add(
        'rule 21: sheet "$name" has an autoFilter and ${mine.length} '
        '_xlnm._FilterDatabase names; expected exactly one',
      );
      continue;
    }
    final String ref = _attr(filters.first, 'ref');
    final _Rect? r = _parseRect(ref);
    if (r == null || _problemWith(r) != null) continue; // reported above
    // A single cell is written as one absolute cell, a range as two.
    final String first = '\$${_columnLetters(r.col1 - 1)}\$${r.row1}';
    final String last = '\$${_columnLetters(r.col2 - 1)}\$${r.row2}';
    final String want =
        "'${name.replaceAll("'", "''")}'!"
        '${ref.contains(':') ? '$first:$last' : first}';
    if (mine.single.innerText != want) {
      violations.add(
        'rule 21: sheet "$name" _xlnm._FilterDatabase is '
        '"${mine.single.innerText}"; the filter makes it "$want"',
      );
    }
  }
}

const String _hyperlinkRelType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'hyperlink';

/// Rule 22.
void _checkHyperlinks(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    final List<XmlElement> links = _all(sheet.value, 'hyperlink').toList();
    if (links.isEmpty) continue;
    if (links.length > 65530) {
      violations.add(
        'rule 22: ${sheet.key}: ${links.length} hyperlinks; Excel allows '
        '65530',
      );
    }
    final String relsName =
        '${_dirOf(sheet.key)}_rels/'
        '${sheet.key.substring(sheet.key.lastIndexOf('/') + 1)}.rels';
    final Map<String, XmlElement> rels = <String, XmlElement>{
      if (docs[relsName] case final XmlDocument doc)
        for (final XmlElement rel in _all(doc, 'Relationship'))
          _attr(rel, 'Id'): rel,
    };
    final Set<String> refs = <String>{};
    for (final XmlElement link in links) {
      final String ref = _attr(link, 'ref');
      final _Rect? r = _parseRect(ref);
      final String? problem = r == null ? 'is not a range' : _problemWith(r);
      if (problem != null) {
        violations.add('rule 22: ${sheet.key}: hyperlink ref "$ref" $problem');
      }
      if (!refs.add(ref)) {
        violations.add(
          'rule 22: ${sheet.key}: two hyperlinks share the ref "$ref"',
        );
      }
      final String? id = link.getAttribute('r:id');
      final String? location = link.getAttribute('location');
      if (id == null && location == null) {
        violations.add(
          'rule 22: ${sheet.key}: hyperlink "$ref" has neither r:id nor '
          'location',
        );
      }
      if (id == null) continue;
      final XmlElement? rel = rels[id];
      if (rel == null) {
        violations.add(
          'rule 22: ${sheet.key}: hyperlink "$ref" has r:id "$id", which '
          '$relsName does not declare',
        );
      } else if (_attr(rel, 'Type') != _hyperlinkRelType ||
          _attr(rel, 'TargetMode') != 'External') {
        violations.add(
          'rule 22: ${sheet.key}: hyperlink "$ref" r:id "$id" is not an '
          'external hyperlink relationship',
        );
      }
    }
  }
}

const Set<String> _comparingTypes = <String>{
  'whole',
  'decimal',
  'date',
  'time',
  'textLength',
};

/// Rule 23.
void _checkDataValidations(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement root in _all(sheet.value, 'dataValidations')) {
      final List<XmlElement> items = root
          .findElements('dataValidation')
          .toList();
      final String count = _attr(root, 'count');
      if (int.tryParse(count) != items.length) {
        violations.add(
          'rule 23: ${sheet.key}: dataValidations count is "$count" but it '
          'has ${items.length} dataValidation',
        );
      }
      final List<(String, _Rect)> seen = <(String, _Rect)>[];
      for (final XmlElement item in items) {
        final String sqref = _attr(item, 'sqref');
        if (sqref.trim().isEmpty) {
          violations.add(
            'rule 23: ${sheet.key}: a dataValidation has no sqref',
          );
        }
        for (final String ref
            in sqref.split(' ').where((String r) => r != '')) {
          final _Rect? r = _parseRect(ref);
          final String? problem = r == null
              ? 'is not a range'
              : _problemWith(r);
          if (problem != null) {
            violations.add('rule 23: ${sheet.key}: sqref "$ref" $problem');
            continue;
          }
          for (final (String other, _Rect o) in seen) {
            if (r!.row1 <= o.row2 &&
                o.row1 <= r.row2 &&
                r.col1 <= o.col2 &&
                o.col1 <= r.col2) {
              violations.add(
                'rule 23: ${sheet.key}: sqref "$ref" overlaps "$other"',
              );
            }
          }
          seen.add((ref, r!));
        }
        final String type = item.getAttribute('type') ?? 'none';
        final bool hasFormula1 = item.getElement('formula1') != null;
        if (type != 'none' && !hasFormula1) {
          violations.add(
            'rule 23: ${sheet.key}: dataValidation "$sqref" of type $type '
            'has no formula1',
          );
        }
        final String operator = item.getAttribute('operator') ?? 'between';
        if (_comparingTypes.contains(type) &&
            (operator == 'between' || operator == 'notBetween') &&
            item.getElement('formula2') == null) {
          violations.add(
            'rule 23: ${sheet.key}: dataValidation "$sqref" with operator '
            '$operator has no formula2',
          );
        }
      }
    }
  }
}

/// The `cfRule` types that carry exactly one `formula`.
const Set<String> _oneFormulaTypes = <String>{
  'expression',
  'containsText',
  'notContainsText',
  'beginsWith',
  'endsWith',
};

/// Rule 24.
void _checkConditionalFormats(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  final XmlElement? dxfs = docs[_stylesPart]
      ?.findAllElements('dxfs')
      .firstOrNull;
  final int dxfCount = int.tryParse(dxfs?.getAttribute('count') ?? '') ?? 0;
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    final Set<int> priorities = <int>{};
    // Direct children of the worksheet only: the x14 rules of an extLst
    // follow their own schema.
    for (final XmlElement format in sheet.value.rootElement.findElements(
      'conditionalFormatting',
    )) {
      final String sqref = _attr(format, 'sqref');
      if (sqref.trim().isEmpty) {
        violations.add(
          'rule 24: ${sheet.key}: a conditionalFormatting has no sqref',
        );
      }
      for (final String ref in sqref.split(' ').where((String r) => r != '')) {
        final _Rect? r = _parseRect(ref);
        final String? problem = r == null ? 'is not a range' : _problemWith(r);
        if (problem != null) {
          violations.add('rule 24: ${sheet.key}: sqref "$ref" $problem');
        }
      }
      for (final XmlElement rule in format.findElements('cfRule')) {
        final String type = _attr(rule, 'type');
        final String where = 'rule 24: ${sheet.key}: cfRule $type on "$sqref"';
        final String priorityText = _attr(rule, 'priority');
        final int? priority = int.tryParse(priorityText);
        if (priority == null || priority < 1) {
          violations.add('$where has priority "$priorityText"');
        } else if (!priorities.add(priority)) {
          violations.add('$where repeats priority $priority');
        }
        final String? dxfText = rule.getAttribute('dxfId');
        if (dxfText != null) {
          final int? dxf = int.tryParse(dxfText);
          if (dxf == null || dxf < 0 || dxf >= dxfCount) {
            violations.add('$where has dxfId "$dxfText"; dxfs holds $dxfCount');
          }
        }
        final int formulas = rule.findElements('formula').length;
        if (type == 'cellIs') {
          final String operator = _attr(rule, 'operator');
          final int want = operator == 'between' || operator == 'notBetween'
              ? 2
              : 1;
          if (formulas != want) {
            violations.add(
              '$where with operator "$operator" has $formulas formula; '
              'expected $want',
            );
          }
        } else if (_oneFormulaTypes.contains(type) && formulas != 1) {
          violations.add('$where has $formulas formula; expected 1');
        }
        final XmlElement? scale = rule.getElement('colorScale');
        if (scale != null) {
          final int cfvos = scale.findElements('cfvo').length;
          final int colors = scale.findElements('color').length;
          if (cfvos < 2 || cfvos > 3 || colors != cfvos) {
            violations.add(
              '$where has $cfvos cfvo and $colors color; expected 2 or 3 '
              'of each',
            );
          }
        }
      }
    }
  }
}

/// The namespace of the Excel 2010 SpreadsheetML extensions (`x14:`).
const String _x14 =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';

/// The descendants of [e] named [local] in the `x14` namespace.
Iterable<XmlElement> _x14Elements(XmlElement e, String local) =>
    e.descendantElements.where(
      (XmlElement d) => d.name.local == local && d.name.namespaceUri == _x14,
    );

/// The `ext/@uri` of a `cfRule`'s `extLst`, as the writer's `_ruleExtUri`.
const String _ruleExtUri = '{B025F937-C7B1-47D3-B67F-A62EFF666E3E}';

/// The `ext/@uri` of the worksheet's conditional-format `extLst`, as the
/// writer's `_sheetExtUri`. Excel writes the lowercase `d`.
const String _sheetExtUri = '{78C0D931-6437-407d-A8EE-F0AAD7539E65}';

/// The icon sets only Excel 2010 has, which have no Excel 2007 `cfRule`.
const Set<String> _x14OnlyIconSets = <String>{
  '3Stars',
  '3Triangles',
  '5Boxes',
  'NoIcons',
};

/// Whether [rule], an `x14:cfRule` no `x14:id` names, is one an Excel 2007
/// `cfRule` does not stand for: an icon set of an x14-only type.
bool _isX14Only(XmlElement rule) =>
    _attr(rule, 'type') == 'iconSet' &&
    _x14Elements(
      rule,
      'iconSet',
    ).any((XmlElement set) => _x14OnlyIconSets.contains(_attr(set, 'iconSet')));

/// Rule 25.
void _checkConditionalExtensions(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  final Map<String, String> idSheets = <String, String>{};
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    final String where = 'rule 25: ${sheet.key}';
    final XmlElement root = sheet.value.rootElement;
    final List<XmlElement> children = root.childElements.toList();
    for (int i = 0; i < children.length - 1; i++) {
      if (children[i].name.local == 'extLst') {
        violations.add(
          '$where: <extLst> is followed by <${children[i + 1].name.local}>; '
          'it must be the last child',
        );
      }
    }
    // The ids the Excel 2007 rules name, and their priorities.
    final Map<String, int> named = <String, int>{};
    final Set<int> priorities = <int>{};
    for (final XmlElement format in root.findElements(
      'conditionalFormatting',
    )) {
      for (final XmlElement rule in format.findElements('cfRule')) {
        final int? priority = int.tryParse(_attr(rule, 'priority'));
        if (priority != null) priorities.add(priority);
        for (final XmlElement ext in rule.findElements('extLst')) {
          for (final XmlElement e in ext.findElements('ext')) {
            if (e.getAttribute('uri') != _ruleExtUri) {
              violations.add(
                '$where: a cfRule ext has uri "${_attr(e, 'uri')}", '
                'expected $_ruleExtUri',
              );
            }
          }
          for (final XmlElement id in _x14Elements(ext, 'id')) {
            named.update(id.innerText, (int n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
    }
    // The Excel 2010 rules of the worksheet's extLst, by id.
    final Map<String, int> rules = <String, int>{};
    final List<XmlElement> x14Rules = <XmlElement>[
      for (final XmlElement ext in root.findElements('extLst'))
        ..._x14Elements(ext, 'cfRule'),
    ];
    for (final XmlElement ext in root.findElements('extLst')) {
      for (final XmlElement e in ext.findElements('ext')) {
        if (e.getAttribute('uri') != _sheetExtUri) {
          violations.add(
            '$where: the worksheet ext has uri "${_attr(e, 'uri')}", '
            'expected $_sheetExtUri',
          );
        }
      }
    }
    for (final XmlElement rule in x14Rules) {
      final String id = _attr(rule, 'id');
      rules.update(id, (int n) => n + 1, ifAbsent: () => 1);
      final String? other = idSheets[id];
      if (other != null && other != sheet.key && id != '') {
        violations.add('$where: x14:cfRule id $id is used in $other too');
      }
      idSheets[id] = sheet.key;
    }
    named.forEach((String id, int count) {
      final int found = rules[id] ?? 0;
      if (count != 1 || found != 1) {
        violations.add(
          '$where: x14:id $id is named by $count cfRule and has $found '
          'x14:cfRule; expected 1 of each',
        );
      }
    });
    final Set<String> repeated = <String>{};
    for (final XmlElement rule in x14Rules) {
      final String id = _attr(rule, 'id');
      if (named.containsKey(id)) continue;
      final String type = _attr(rule, 'type');
      if ((rules[id] ?? 0) > 1 && repeated.add(id)) {
        violations.add('$where: ${rules[id]} x14:cfRule share the id "$id"');
      }
      // An x14-only rule: it has no Excel 2007 rule to hold its priority.
      if (!_isX14Only(rule)) {
        violations.add(
          '$where: x14:cfRule $type "$id" is named by no x14:id and is not '
          'an icon set only Excel 2010 has',
        );
        continue;
      }
      final String text = _attr(rule, 'priority');
      final int? priority = int.tryParse(text);
      if (priority == null || priority < 1) {
        violations.add(
          '$where: x14-only x14:cfRule $type "$id" has priority "$text"',
        );
      } else if (!priorities.add(priority)) {
        violations.add(
          '$where: x14-only x14:cfRule $type "$id" repeats priority '
          '$priority',
        );
      }
    }
  }
}

/// Rule 26.
void _checkProtection(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    for (final XmlElement p in _all(sheet.value, 'sheetProtection')) {
      final String? password = p.getAttribute('password');
      if (password != null && !_legacyHash.hasMatch(password)) {
        violations.add(
          'rule 26: ${sheet.key}: sheetProtection password "$password" is '
          'not four uppercase hexadecimal digits',
        );
      }
      if (p.getAttribute('sheet') != '1') {
        violations.add(
          'rule 26: ${sheet.key}: sheetProtection has sheet="'
          '${_attr(p, 'sheet')}", expected "1"',
        );
      }
    }
  }
  final XmlDocument? book = docs[_workbookPart];
  if (book == null) return;
  for (final XmlElement p in _all(book, 'workbookProtection')) {
    final String? password = p.getAttribute('workbookPassword');
    if (password != null && !_legacyHash.hasMatch(password)) {
      violations.add(
        'rule 26: workbook: workbookPassword "$password" is not four '
        'uppercase hexadecimal digits',
      );
    }
  }
}

/// The `fmtid` every custom property has.
const String _customFmtid = '{D5CDD505-2E9C-101B-9397-08002B2CF9AE}';

/// The namespace of the `vt:` value elements of document properties.
const String _vtNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes';

/// Rule 27.
void _checkCustomProperties(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  final XmlDocument? doc = docs['docProps/custom.xml'];
  if (doc == null) return;
  final Set<String> pids = <String>{};
  final Set<String> names = <String>{};
  for (final XmlElement p in _all(doc, 'property')) {
    final String name = _attr(p, 'name');
    final String pid = _attr(p, 'pid');
    final int? number = int.tryParse(pid);
    if (number == null || number < 2) {
      violations.add(
        'rule 27: custom property "$name": pid "$pid" is not an integer of '
        'at least 2',
      );
    }
    if (!pids.add(pid)) {
      violations.add('rule 27: custom property "$name": pid "$pid" repeats');
    }
    if (!names.add(name.toLowerCase())) {
      violations.add(
        'rule 27: custom property name "$name" repeats an earlier name, '
        'ignoring case',
      );
    }
    if (p.getAttribute('fmtid') != _customFmtid) {
      violations.add(
        'rule 27: custom property "$name": fmtid "${_attr(p, 'fmtid')}" is '
        'not $_customFmtid',
      );
    }
    final List<XmlElement> children = p.childElements.toList();
    if (children.length != 1) {
      violations.add(
        'rule 27: custom property "$name" has ${children.length} value '
        'children, expected 1',
      );
    }
    for (final XmlElement value in children) {
      if (value.name.namespaceUri != _vtNamespace) {
        violations.add(
          'rule 27: custom property "$name": value <${value.name.qualified}> '
          'is not in the vt namespace',
        );
      }
    }
  }
}

/// The local names of the child elements of [e], as `<a>, <b>`, or
/// `nothing`.
String _describeChildren(XmlElement e) {
  final List<String> names = <String>[
    for (final XmlElement child in e.childElements) '<${child.name.local}>',
  ];
  return names.isEmpty ? 'nothing' : names.join(', ');
}

/// Rule 28.
void _checkSharedStringItems(
  Map<String, XmlDocument> docs,
  List<String> violations,
) {
  final XmlDocument? sst = docs[_sharedStringsPart];
  if (sst == null) return;
  int index = 0;
  for (final XmlElement si in sst.rootElement.findElements('si')) {
    final List<String> children = <String>[
      for (final XmlElement child in si.childElements) child.name.local,
    ];
    final bool plain = children.length == 1 && children.single == 't';
    final bool runs =
        children.isNotEmpty && children.every((String c) => c == 'r');
    if (!plain && !runs) {
      violations.add(
        'rule 28: si $index holds ${_describeChildren(si)}; expected one '
        '<t> or one or more <r>',
      );
    }
    if (runs) {
      int run = 0;
      for (final XmlElement r in si.childElements) {
        final List<String> parts = <String>[
          for (final XmlElement child in r.childElements) child.name.local,
        ];
        final int texts = parts.where((String p) => p == 't').length;
        final int properties = parts.where((String p) => p == 'rPr').length;
        if (texts != 1 ||
            properties > 1 ||
            texts + properties != parts.length) {
          violations.add(
            'rule 28: si $index run $run holds ${_describeChildren(r)}; '
            'expected one <t> and at most one <rPr>',
          );
        }
        run++;
      }
    }
    index++;
  }
}

const String _commentsRelType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'comments';

const String _vmlDrawingRelType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'vmlDrawing';

/// The VML namespaces (`v:`, `o:` and `x:`).
const String _vml = 'urn:schemas-microsoft-com:vml';
const String _vmlOffice = 'urn:schemas-microsoft-com:office:office';
const String _vmlExcel = 'urn:schemas-microsoft-com:office:excel';

/// The descendants of [node] named [local] in the namespace [namespace].
Iterable<XmlElement> _elementsIn(
  XmlNode node,
  String namespace,
  String local,
) => node.descendantElements.where(
  (XmlElement d) => d.name.local == local && d.name.namespaceUri == namespace,
);

/// The relationships of the worksheet part [sheet], by id.
Map<String, XmlElement> _sheetRelationships(
  Map<String, XmlDocument> docs,
  String sheet,
) {
  final String relsName =
      '${_dirOf(sheet)}_rels/${sheet.substring(sheet.lastIndexOf('/') + 1)}'
      '.rels';
  return <String, XmlElement>{
    if (docs[relsName] case final XmlDocument doc)
      for (final XmlElement rel in _all(doc, 'Relationship'))
        _attr(rel, 'Id'): rel,
  };
}

/// Rule 29, per sheet: comments, `legacyDrawing` and note shapes.
void _checkNotes(Map<String, XmlDocument> docs, List<String> violations) {
  for (final MapEntry<String, XmlDocument> sheet in _sheets(docs)) {
    final String where = 'rule 29: ${sheet.key}';
    final Map<String, XmlElement> rels = _sheetRelationships(docs, sheet.key);
    final XmlElement? commentsRel = rels.values
        .where((XmlElement r) => _attr(r, 'Type') == _commentsRelType)
        .firstOrNull;
    final XmlElement? legacy = sheet.value.rootElement.getElement(
      'legacyDrawing',
    );
    if (commentsRel == null && legacy == null) continue;
    // The refs of the comments, by their zero-based cell as "row, column".
    final Map<String, String> commented = <String, String>{};
    if (commentsRel != null) {
      final String part = _resolve(
        _dirOf(sheet.key),
        _attr(commentsRel, 'Target'),
      );
      final XmlDocument? comments = docs[part];
      // A missing part is rule 2's.
      if (comments != null) {
        _checkComments(comments, '$where: $part', commented, violations);
      }
      if (legacy == null) {
        violations.add(
          '$where: has a comments relationship but no <legacyDrawing>',
        );
        continue;
      }
    }
    final String id = _attr(legacy!, 'r:id');
    final XmlElement? rel = rels[id];
    if (rel == null || _attr(rel, 'Type') != _vmlDrawingRelType) {
      violations.add(
        '$where: legacyDrawing r:id "$id" is not a VML drawing relationship',
      );
      continue;
    }
    final String vmlPart = _resolve(_dirOf(sheet.key), _attr(rel, 'Target'));
    final XmlDocument? vml = docs[vmlPart];
    if (vml == null) continue;
    final Map<String, int> shapes = <String, int>{};
    for (final XmlElement data in _elementsIn(vml, _vmlExcel, 'ClientData')) {
      if (_attr(data, 'ObjectType') != 'Note') continue;
      String field(String local) =>
          _elementsIn(data, _vmlExcel, local).firstOrNull?.innerText.trim() ??
          '';
      final String cell = '${field('Row')}, ${field('Column')}';
      shapes.update(cell, (int n) => n + 1, ifAbsent: () => 1);
    }
    commented.forEach((String cell, String ref) {
      final int count = shapes[cell] ?? 0;
      if (count != 1) {
        violations.add(
          '$where: the comment on $ref has $count note shapes in $vmlPart; '
          'expected 1',
        );
      }
    });
    for (final String cell in shapes.keys) {
      if (!commented.containsKey(cell)) {
        final List<String> rowColumn = cell.split(', ');
        violations.add(
          '$where: $vmlPart has a note shape on row ${rowColumn.first}, '
          'column ${rowColumn.last}, which has no comment',
        );
      }
    }
  }
}

/// Rule 29 for the comments part [comments], reported as [where]: adds the
/// ref of each comment inside the sheet to [commented], keyed by its
/// zero-based cell as "row, column".
void _checkComments(
  XmlDocument comments,
  String where,
  Map<String, String> commented,
  List<String> violations,
) {
  final int authors = _all(comments, 'author').length;
  final Set<String> refs = <String>{};
  for (final XmlElement comment in _all(comments, 'comment')) {
    final String ref = _attr(comment, 'ref');
    final RegExpMatch? m = _cellRef.firstMatch(ref);
    if (m == null) {
      violations.add('$where: comment ref "$ref" is not a single cell');
    } else {
      final _Rect cell = _parseRect(ref)!;
      final String? problem = _problemWith(cell);
      if (problem != null) {
        violations.add('$where: comment ref "$ref" $problem');
      } else {
        commented['${cell.row1 - 1}, ${cell.col1 - 1}'] = ref;
      }
    }
    if (!refs.add(ref)) {
      violations.add('$where: two comments share the ref "$ref"');
    }
    final String text = _attr(comment, 'authorId');
    final int? authorId = int.tryParse(text);
    if (authorId == null || authorId < 0 || authorId >= authors) {
      violations.add(
        '$where: comment "$ref" has authorId "$text"; the part has $authors '
        'authors',
      );
    }
  }
}

final RegExp _shapeId = RegExp(r'^_x0000_s(\d+)$');

/// Rule 29 across the workbook's VML drawings: anchors, id blocks and
/// shape ids.
void _checkVmlDrawings(Map<String, XmlDocument> docs, List<String> violations) {
  final Map<int, String> blockParts = <int, String>{};
  final Map<String, String> shapeParts = <String, String>{};
  docs.forEach((String part, XmlDocument vml) {
    if (!part.endsWith('.vml')) return;
    final String where = 'rule 29: $part';
    final Set<int> blocks = <int>{};
    for (final XmlElement idmap in _elementsIn(vml, _vmlOffice, 'idmap')) {
      final String data = idmap.getAttribute('data') ?? '';
      for (final String text in data.split(',')) {
        final int? block = int.tryParse(text.trim());
        if (block == null || block < 0) {
          violations.add('$where: o:idmap data "$data" is not a block list');
          continue;
        }
        blocks.add(block);
        final String? other = blockParts[block];
        if (other != null) {
          violations.add('$where: id block $block is listed by $other too');
        }
        blockParts[block] = part;
      }
    }
    for (final XmlElement shape in _elementsIn(vml, _vml, 'shape')) {
      final String id = _attr(shape, 'id');
      final String? other = shapeParts[id];
      if (other != null) {
        violations.add('$where: shape id $id is used by $other too');
      }
      shapeParts[id] = part;
      final RegExpMatch? m = _shapeId.firstMatch(id);
      if (m != null && !blocks.contains(int.parse(m.group(1)!) ~/ 1024)) {
        violations.add(
          '$where: shape id $id lies outside the id blocks of its o:idmap',
        );
      }
    }
    for (final XmlElement anchor in _elementsIn(vml, _vmlExcel, 'Anchor')) {
      final String text = anchor.innerText;
      final List<int?> values = <int?>[
        for (final String v in text.split(',')) int.tryParse(v.trim()),
      ];
      if (values.length != 8 || values.contains(null)) {
        violations.add('$where: x:Anchor "$text" is not 8 integers');
        continue;
      }
      final int left = values[0]!;
      final int top = values[2]!;
      final int right = values[4]!;
      final int bottom = values[6]!;
      if (<int>[left, right].any((int c) => c < 0 || c > 16383) ||
          <int>[top, bottom].any((int r) => r < 0 || r > 1048575)) {
        violations.add('$where: x:Anchor "$text" lies outside the sheet');
      } else if (left > right || top > bottom) {
        violations.add('$where: x:Anchor "$text" ends before it starts');
      }
    }
  });
}
