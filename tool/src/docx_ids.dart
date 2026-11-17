/// The id check of the template fill's tools: a filled document writes no
/// drawing, revision or content control id twice (T2 plan Ruling 9).
///
/// Not ported from Quds; written for jet_office (decision 0024, T2). It uses
/// no `dart:io`, so the fuzz tests that import it run in a browser too.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The revision elements whose `w:id` a copy renews (Ruling 9).
const List<String> _revisions = <String>[
  'ins',
  'del',
  'moveFrom',
  'moveTo',
  'rPrChange',
  'pPrChange',
  'sectPrChange',
  'tblPrChange',
  'tblGridChange',
  'trPrChange',
  'tcPrChange',
  'cellIns',
  'cellDel',
  'cellMerge',
  'numberingChange',
];

final RegExp _storyPart = RegExp(
  r'^word/(document|header\d*|footer\d*|footnotes|endnotes|comments)\.xml$',
);
final RegExp _drawing = RegExp(r'<wp:docPr\b[^>]*?\sid="([^"]*)"');
final RegExp _revision = RegExp(
  '<w:(?:${_revisions.join('|')})\\b[^>]*?\\sw:id="([^"]*)"',
);
final RegExp _contentControl = RegExp(r'<w:id\b[^>]*?\sw:val="([^"]*)"');

/// The ids of each kind in the story parts of [docx] (the body, headers,
/// footers, notes and comments), each id as often as it is written; empty
/// for bytes that are no ZIP.
Map<String, List<String>> _ids(Uint8List docx) {
  final Map<String, List<String>> out = <String, List<String>>{
    'drawing': <String>[],
    'revision': <String>[],
    'content control': <String>[],
  };
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(docx);
  } on Object {
    return out;
  }
  for (final ArchiveFile file in archive.files) {
    if (!file.isFile || !_storyPart.hasMatch(file.name)) continue;
    final String text;
    try {
      text = utf8.decode(file.content as List<int>, allowMalformed: true);
    } on Object {
      continue;
    }
    for (final (String kind, RegExp pattern) in <(String, RegExp)>[
      ('drawing', _drawing),
      ('revision', _revision),
      ('content control', _contentControl),
    ]) {
      for (final Match m in pattern.allMatches(text)) {
        out[kind]!.add(m[1]!);
      }
    }
  }
  return out;
}

/// The ids [docx] writes more often than [template] did (at most once when
/// [template] is `null` or wrote it once or not at all), one line each, as
/// `<kind> id <id> written <n> times`: a fill's copies must get ids of their
/// own (`wp:docPr/@id`, the `w:id` of a revision, `w:sdtPr/w:id/@w:val`).
/// Ids the template itself repeats may stay repeated as often.
///
/// The parts are read as text: a `wp:` or `w:` prefix other than Word's is
/// not seen.
List<String> duplicateIds(Uint8List docx, {Uint8List? template}) {
  final Map<String, List<String>> after = _ids(docx);
  final Map<String, List<String>> before = template == null
      ? const <String, List<String>>{}
      : _ids(template);
  final List<String> out = <String>[];
  for (final MapEntry<String, List<String>> kind in after.entries) {
    final Map<String, int> counts = <String, int>{};
    for (final String id in kind.value) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final Map<String, int> was = <String, int>{};
    for (final String id in before[kind.key] ?? const <String>[]) {
      was[id] = (was[id] ?? 0) + 1;
    }
    counts.forEach((String id, int n) {
      final int allowed = (was[id] ?? 0) > 1 ? was[id]! : 1;
      if (n > allowed) out.add('${kind.key} id $id written $n times');
    });
  }
  return out;
}
