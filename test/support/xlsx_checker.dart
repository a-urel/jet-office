/// Test helper: a consistency checker for generated XLSX files.
///
/// It checks the rules Excel enforces when it opens a file and refuses with
/// "We found a problem with some content". Every violation starts with
/// `rule N:`, N being the rule's number below. Later milestones add rules.
///
/// 1. every part and `.rels` is well-formed XML;
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
///     units;
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
///     is; a frozen pane with neither split is wrong too.
///
/// Element lookups use local names and assume the default SpreadsheetML
/// namespace: a part that declares a prefix for it (`<x:row>`) is not found.
/// The writer never does.
///
/// Pure Dart (no `dart:io`), so it runs in a browser too.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/xlsx/cell_ref.dart' show cellRef;
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
    if (!name.endsWith('.xml') && !name.endsWith('.rels')) return;
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
      final String text = f.innerText;
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
      if (x < 0 || y < 0 || (x == 0 && y == 0)) {
        violations.add(
          'rule 19: ${sheet.key}: frozen pane has xSplit '
          '"${_attr(pane, 'xSplit')}" and ySplit "${_attr(pane, 'ySplit')}"; '
          'expected whole numbers, one at least 1',
        );
        continue;
      }
      String topLeft;
      try {
        topLeft = cellRef(y, x);
      } on RangeError {
        topLeft = '';
      }
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
