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
/// 6. sheet names are unique ignoring case, at most 31 UTF-16 code units,
///    free of `[]:*?/\`, not the reserved `History` and not starting or
///    ending with an apostrophe;
/// 7. `workbookView/@activeTab` is a valid sheet index;
/// 8. every cell `s` is below the `cellXfs` count;
/// 9. cell references in a row strictly increase and sit on that row;
/// 10. every formula (`<f>`) is non-empty and at most 8,192 UTF-16 code
///     units;
/// 11. row numbers (`row/@r`) strictly increase within a sheet;
/// 12. `cellXfs/@count` equals the number of its `xf` children;
/// 13. every `numFmtId` of 164 or more used by a `cellXfs` `xf` is declared
///     in `numFmts`.
///
/// Pure Dart (no `dart:io`), so it runs in a browser too.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/xlsx/sheet_name.dart' show sheetNameKey;
import 'package:xml/xml.dart';

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
  final String parent = dir.endsWith('_rels')
      ? dir.substring(0, dir.length - '_rels'.length)
      : dir;
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
    for (final XmlElement s in _all(doc, 'sheet')) _attr(s, 'name'),
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
  final XmlDocument? styles = docs[_stylesPart];
  final XmlElement? cellXfs = styles == null
      ? null
      : _all(styles, 'cellXfs').firstOrNull;
  final int? xfCount = cellXfs == null
      ? null
      : int.tryParse(_attr(cellXfs, 'count'));
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
