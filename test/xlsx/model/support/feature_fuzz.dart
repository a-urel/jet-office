/// Test helper: seeded mutation fuzzing of the workbook model's sheet and
/// workbook features (milestones W3 and W4).
///
/// [featureCorpus] is its own corpus, so the reader's pinned one and its
/// cases do not change: the `m3_*` and `m4_*` fixtures, [excelFeatureFile], a
/// sheet as Excel writes it, with Excel 2010 rules, and [excelObjectsFile],
/// with more objects than the model types. [featureFuzzCases] derives
/// mutated copies with the machinery of `test/support/fuzz_mutations.dart`,
/// and with mutations that keep the XML well formed, so most cases reach the
/// features' own parsers instead of stopping at the XML reader.
/// [exerciseFeatures] reads, sets, undoes and saves every W3 and W4 member.
/// `feature_fuzz_test.dart` runs a fixed range of seeds in the quality gate;
/// `tool/fuzz_reader.dart --features` runs any range by hand.
///
/// As in the reader's corpus, entries are stored, so a seed gives the same
/// cases on the VM and in a browser.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';

import '../../../../tool/src/part_compare.dart';
import '../../../fixtures/fixture.dart';
import '../../../fixtures/m3_fixtures.dart';
import '../../../fixtures/m4_fixtures.dart';
import '../../../support/fuzz_mutations.dart';
import '../../../support/read_xlsx.dart';
import '../../read/support/producers.dart';
import '../../read/support/workbook_builder.dart';
import '../../read/support/zip_builder.dart';

export '../../../support/fuzz_mutations.dart' show FuzzCase, mutatedPart;

const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRelNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _x14Ns =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';
const String _xmNs = 'http://schemas.microsoft.com/office/excel/2006/main';
const String _mcNs =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';
const String _x14acNs =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';
const String _barId = '{5C1A1F40-6E0B-4E5B-8C0A-7A1A0C7F0001}';
const String _starsId = '{5C1A1F40-6E0B-4E5B-8C0A-7A1A0C7F0002}';

/// A workbook as Excel writes one, with one of each feature: hashed sheet
/// and workbook protection, an auto filter, print names, a user name, Excel
/// 2007 and 2010 conditional formats beside a sparkline `ext`, a validation,
/// hyperlinks, page setup and a header.
Uint8List excelFeatureFile() {
  const String sheet =
      '<worksheet xmlns="$mainNs" xmlns:r="$_relNs" xmlns:mc="$_mcNs" '
      'xmlns:x14ac="$_x14acNs" mc:Ignorable="x14ac">'
      '<sheetPr><tabColor rgb="FF00B050"/><pageSetUpPr fitToPage="1"/>'
      '</sheetPr><dimension ref="A1:C3"/>'
      '<sheetViews><sheetView tabSelected="1" workbookViewId="0"/></sheetViews>'
      '<sheetFormatPr defaultRowHeight="15" x14ac:dyDescent="0.25"/>'
      '<sheetData><row r="1"><c r="A1"><v>1</v></c><c r="B1"><v>2</v></c>'
      '<c r="C1"><v>3</v></c></row>'
      '<row r="2"><c r="A2"><v>4</v></c><c r="B2"><v>5</v></c>'
      '<c r="C2"><v>6</v></c></row>'
      '<row r="3"><c r="A3"><v>7</v></c><c r="B3"><v>8</v></c>'
      '<c r="C3"><v>9</v></c></row></sheetData>'
      '<sheetProtection algorithmName="SHA-512" hashValue="AAAA" '
      'saltValue="BBBB" spinCount="100000" sheet="1" objects="1" '
      'scenarios="1" formatColumns="0"/>'
      '<autoFilter ref="A1:C3"/>'
      '<mergeCells count="1"><mergeCell ref="E1:F1"/></mergeCells>'
      '<conditionalFormatting sqref="A1:A3">'
      '<cfRule type="dataBar" priority="2"><dataBar><cfvo type="min"/>'
      '<cfvo type="max"/><color rgb="FF638EC6"/></dataBar>'
      '<extLst><ext uri="{B025F937-C7B1-47D3-B67F-A62EFF666E3E}" '
      'xmlns:x14="$_x14Ns"><x14:id>$_barId</x14:id></ext></extLst></cfRule>'
      '</conditionalFormatting>'
      '<conditionalFormatting sqref="B1:B3">'
      '<cfRule type="cellIs" dxfId="0" priority="1" operator="greaterThan">'
      '<formula>4</formula></cfRule>'
      '<cfRule type="timePeriod" dxfId="0" priority="3" timePeriod="today">'
      '<formula>FLOOR(B1,1)=TODAY()</formula></cfRule>'
      '</conditionalFormatting>'
      '<dataValidations count="2"><dataValidation type="list" allowBlank="1" '
      'showInputMessage="1" showErrorMessage="1" sqref="C1:C2">'
      '<formula1>"a,b"</formula1></dataValidation>'
      '<dataValidation type="whole" operator="between" errorStyle="warning" '
      'sqref="C3"><formula1>1</formula1><formula2>9</formula2>'
      '</dataValidation></dataValidations>'
      '<hyperlinks><hyperlink ref="A1" r:id="rId1" tooltip="Go"/>'
      '<hyperlink ref="B1:B2" location="Data!A1" display="Here"/></hyperlinks>'
      '<printOptions gridLines="1" gridLinesSet="0"/>'
      '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
      'header="0.3" footer="0.3"/>'
      '<pageSetup paperSize="9" orientation="landscape" fitToHeight="0" '
      'horizontalDpi="300"/>'
      '<headerFooter differentFirst="1"><oddHeader>&amp;LTop&amp;RR&amp;&amp;D'
      '</oddHeader><firstFooter>Page &amp;P</firstFooter></headerFooter>'
      '<extLst><ext uri="{78C0D931-6437-407d-A8EE-F0AAD7539E65}" '
      'xmlns:x14="$_x14Ns"><x14:conditionalFormattings>'
      '<x14:conditionalFormatting xmlns:xm="$_xmNs">'
      '<x14:cfRule type="dataBar" id="$_barId">'
      '<x14:dataBar minLength="0" maxLength="100" border="1" '
      'negativeBarBorderColorSameAsPositive="0">'
      '<x14:cfvo type="autoMin"/><x14:cfvo type="autoMax"/>'
      '<x14:borderColor rgb="FF638EC6"/>'
      '<x14:negativeFillColor rgb="FFFF0000"/>'
      '<x14:negativeBorderColor rgb="FFFF0000"/>'
      '<x14:axisColor rgb="FF000000"/></x14:dataBar></x14:cfRule>'
      '<xm:sqref>A1:A3</xm:sqref></x14:conditionalFormatting>'
      '<x14:conditionalFormatting xmlns:xm="$_xmNs">'
      '<x14:cfRule type="iconSet" priority="4" id="$_starsId">'
      '<x14:iconSet iconSet="3Stars">'
      '<x14:cfvo type="percent"><xm:f>0</xm:f></x14:cfvo>'
      '<x14:cfvo type="percent"><xm:f>33</xm:f></x14:cfvo>'
      '<x14:cfvo type="percent"><xm:f>67</xm:f></x14:cfvo>'
      '</x14:iconSet></x14:cfRule><xm:sqref>C1:C3</xm:sqref>'
      '</x14:conditionalFormatting></x14:conditionalFormattings></ext>'
      '<ext uri="{05C60535-1F16-4fd2-B633-F4F36F0B64E0}" xmlns:x14="$_x14Ns">'
      '<x14:sparklineGroups xmlns:xm="$_xmNs"><x14:sparklineGroup>'
      '<x14:sparklines><x14:sparkline><xm:f>Data!A1:C1</xm:f>'
      '<xm:sqref>D1</xm:sqref></x14:sparkline></x14:sparklines>'
      '</x14:sparklineGroup></x14:sparklineGroups></ext></extLst>'
      '</worksheet>';
  final Uint8List bytes = buildWorkbook(
    <String, String>{'Data': sheet},
    styles:
        '<styleSheet xmlns="$mainNs"><dxfs count="1"><dxf><font><b/></font>'
        '<fill><patternFill><bgColor rgb="FFFFC7CE"/></patternFill></fill>'
        '</dxf></dxfs></styleSheet>',
  );
  return buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> e in readXlsxBytes(bytes).entries)
      (
        e.key,
        e.key == 'xl/workbook.xml'
            ? utf8.encode(
                utf8
                    .decode(e.value)
                    .replaceFirst(
                      '<sheets>',
                      '<workbookProtection workbookAlgorithmName="SHA-512" '
                          'workbookHashValue="AAAA" workbookSaltValue="BBBB" '
                          'workbookSpinCount="100000" lockStructure="1"/>'
                          '<sheets>',
                    )
                    .replaceFirst(
                      '</sheets>',
                      '</sheets><definedNames>'
                          '<definedName name="_xlnm._FilterDatabase" '
                          r'localSheetId="0" hidden="1">Data!$A$1:$C$3'
                          '</definedName>'
                          '<definedName name="_xlnm.Print_Area" '
                          r'localSheetId="0">Data!$A$1:$C$3</definedName>'
                          '<definedName name="_xlnm.Print_Titles" '
                          r'localSheetId="0">Data!$1:$1</definedName>'
                          '<definedName name="Rate" comment="Tax">0.18'
                          '</definedName>'
                          '<definedName name="Here" localSheetId="0">'
                          r'Data!$B$2</definedName></definedNames>',
                    ),
              )
            : e.value,
      ),
    (
      'xl/worksheets/_rels/sheet1.xml.rels',
      utf8.encode(
        '<Relationships xmlns="$_pkgRelNs"><Relationship Id="rId1" '
        'Type="$_relNs/hyperlink" Target="https://example.com/a%20b" '
        'TargetMode="External"/></Relationships>',
      ),
    ),
  ], store: true);
}

/// The packages the fuzzer mutates, in a fixed order, entries stored: every
/// fixture of `m3Fixtures()` and `m4Fixtures()`, then [excelFeatureFile] as
/// `excel_features` and [excelObjectsFile] as `excel_objects`.
List<({String name, Uint8List bytes})> featureCorpus() =>
    <({String name, Uint8List bytes})>[
      for (final Fixture f in <Fixture>[...m3Fixtures(), ...m4Fixtures()])
        (name: f.name, bytes: _stored(f.build())),
      (name: 'excel_features', bytes: excelFeatureFile()),
      (name: 'excel_objects', bytes: _stored(excelObjectsFile().bytes)),
    ];

/// [zip] with the same entries in the same order, stored.
Uint8List _stored(Uint8List zip) => buildZipOrdered(<(String, List<int>)>[
  for (final MapEntry<String, Uint8List> e in readXlsxBytes(zip).entries)
    (e.key, e.value),
], store: true);

/// The tokens the byte mutations insert: what the features' parsers treat
/// specially.
const List<String> _tokens = <String>[
  '<',
  '"',
  '&',
  ' dxfId="99"',
  ' sqref="A"',
  ' r:id="rId99"',
  ' localSheetId="99"',
  ' priority="-1"',
  ' xmlns:o="urn:&#1;o"',
  ' o:a="&#1;"',
  '<formula>1</formula>',
  '<cfvo type="num" val="x"/>',
  '<x14:id>{X}</x14:id>',
  '<extLst/>',
  '<hyperlink ref="A1"/>',
  '<!-- c -->',
  '&#1;',
];

/// The values the well-formed mutations give an attribute.
const List<String> _values = <String>[
  '',
  '0',
  '1',
  '-1',
  '2',
  '99',
  '1.5',
  '99999999999999999999',
  '1e999',
  'NaN',
  'true',
  'false',
  'x',
  'A',
  'A1',
  'A1:',
  'A1 B2',
  'A1:A1048577',
  'XFD1048576',
  r'$A:$A',
  '#REF!',
  'rId1',
  'rId99',
  '_xlnm.Print_Area',
  '_xlnm._FilterDatabase',
  "O'Brien",
  '{00000000-0000-0000-0000-000000000000}',
  'SHA-512',
  '&#1;',
  '&#xFFFE;',
  '&amp;',
  '&lt;',
  ' ',
];

/// The texts the well-formed mutations give an element.
const List<String> _texts = <String>[
  '',
  ' ',
  '0',
  '-1',
  'x',
  '=A1',
  '#REF!',
  'A1',
  r'$A$1:$B$2',
  r'Data!$A:$A',
  r'Data!$1:$1,Data!$A:$A',
  r"'O''Brien'!$A$1",
  r'Nope!$A$1:$B$2',
  'OFFSET(A1,1,1)',
  'Data!',
  '"a,b',
  '{X}',
  '&amp;L&amp;P&amp;',
  '&amp;',
  '_xD800_',
  '_x0041_',
  '&#1;',
  '&bad;',
  '2026-13-45T99:99:99Z',
  '99999999999999999999',
];

/// Whether the corpus part [name] holds a feature: everything the mutations
/// aim at. Other parts are reached by the archive's byte mutations only.
bool _holdsFeatures(String name) =>
    name == 'xl/workbook.xml' ||
    name == 'xl/styles.xml' ||
    name == 'xl/sharedStrings.xml' ||
    name.startsWith('xl/worksheets/') ||
    name.startsWith('xl/comments') ||
    name.startsWith('xl/drawings/') ||
    name.startsWith('xl/tables/') ||
    name.startsWith('docProps/');

/// The offset in [text] where the features start, past the cells of a sheet.
int _featuresStart(String text) {
  final int end = text.indexOf('</sheetData>');
  if (end >= 0) return end;
  final int empty = text.indexOf('<sheetData/>');
  return empty >= 0 ? empty : 0;
}

/// The first [count] cases of [seed], each one mutation of one corpus entry.
///
/// One case in eight changes the archive's bytes. The others change one part
/// that [_holdsFeatures], past the cells of a sheet: two in eight with the
/// shared byte mutations, five with a mutation that keeps the XML well
/// formed (see [_wellFormed]). Lazy, and the same for the same arguments
/// every time.
Iterable<FuzzCase> featureFuzzCases(int seed, int count) sync* {
  final List<({String name, Uint8List bytes})> corpus = featureCorpus();
  final List<List<(String, Uint8List)>> parts = <List<(String, Uint8List)>>[
    for (final ({String name, Uint8List bytes}) entry in corpus)
      <(String, Uint8List)>[
        for (final MapEntry<String, Uint8List> e in readXlsxBytes(
          entry.bytes,
        ).entries)
          (e.key, e.value),
      ],
  ];
  final Xorshift32 random = Xorshift32(seed);
  for (int index = 0; index < count; index++) {
    final int pick = random.nextInt(corpus.length);
    final ({String name, Uint8List bytes}) entry = corpus[pick];
    final int kind = random.nextInt(8);
    if (kind == 0) {
      final (String what, Uint8List bytes) = mutateArchive(
        entry.bytes,
        random.nextInt(3),
        random,
      );
      yield (
        seed: seed,
        index: index,
        mutation: '${entry.name} $what',
        bytes: bytes,
      );
      continue;
    }
    final List<(String, Uint8List)> files = parts[pick];
    final List<int> targets = <int>[
      for (int i = 0; i < files.length; i++)
        if (_holdsFeatures(files[i].$1)) i,
    ];
    final int which = targets[random.nextInt(targets.length)];
    final (String name, Uint8List part) = files[which];
    final String text = utf8.decode(part);
    final int start = _featuresStart(text);
    final String head = text.substring(0, start);
    final String tail = text.substring(start);
    final String what;
    final List<int> mutated;
    if (kind < 3) {
      final (String done, List<int> bytes) = mutateBytes(
        Uint8List.fromList(utf8.encode(tail)),
        random.nextInt(5),
        random,
        _tokens,
      );
      what = done;
      mutated = <int>[...utf8.encode(head), ...bytes];
    } else {
      final (String done, String changed) = _wellFormed(tail, random);
      what = done;
      mutated = utf8.encode('$head$changed');
    }
    yield (
      seed: seed,
      index: index,
      mutation: '${entry.name} $name: $what',
      bytes: buildZipOrdered(<(String, List<int>)>[
        for (int i = 0; i < files.length; i++)
          i == which ? (name, mutated) : files[i],
      ], store: true),
    );
  }
}

final RegExp _attribute = RegExp(r'\s([\w:]+)="([^"<]*)"');
final RegExp _openTag = RegExp(r'<([A-Za-z][\w:.]*)(?:\s[^<>]*?)?(/?)>');
final RegExp _elementText = RegExp(r'>([^<>]+)</');

/// [text] with one change that keeps it well formed: an attribute's value
/// replaced from `_values` or removed, an element's text replaced from
/// `_texts`, or an element removed, repeated, or copied before another one.
(String, String) _wellFormed(String text, Xorshift32 random) {
  final List<RegExpMatch> attributes = _attribute.allMatches(text).toList();
  final List<RegExpMatch> tags = _openTag.allMatches(text).toList();
  final List<RegExpMatch> texts = _elementText.allMatches(text).toList();
  // A part with nothing to change comes back as it is.
  switch (random.nextInt(7)) {
    case 0 || 1 || 2 when attributes.isNotEmpty:
      final RegExpMatch a = attributes[random.nextInt(attributes.length)];
      final String value = _values[random.nextInt(_values.length)];
      return (
        'set ${a.group(1)} to ${jsonEncode(value)}',
        text.replaceRange(a.start, a.end, ' ${a.group(1)}="$value"'),
      );
    case 3 when attributes.isNotEmpty:
      final RegExpMatch a = attributes[random.nextInt(attributes.length)];
      return ('remove ${a.group(1)}', text.replaceRange(a.start, a.end, ''));
    case 4 when texts.isNotEmpty:
      final RegExpMatch t = texts[random.nextInt(texts.length)];
      final String value = _texts[random.nextInt(_texts.length)];
      return (
        'set text ${jsonEncode(t.group(1))} to ${jsonEncode(value)}',
        text.replaceRange(t.start, t.end, '>$value</'),
      );
    case 5 || 6 when tags.length > 1:
      // The first tag may be the end of `<sheetData`, or a root to keep.
      final RegExpMatch tag = tags[1 + random.nextInt(tags.length - 1)];
      final int end = _elementEnd(text, tag);
      if (end < 0) return ('nothing', text);
      final String element = text.substring(tag.start, end);
      final String name = tag.group(1)!;
      switch (random.nextInt(3)) {
        case 0:
          return ('remove <$name>', text.replaceRange(tag.start, end, ''));
        case 1:
          return ('repeat <$name>', text.replaceRange(end, end, element));
        default:
          final int at = tags[random.nextInt(tags.length)].start;
          return ('copy <$name> to $at', text.replaceRange(at, at, element));
      }
    default:
      return ('nothing', text);
  }
}

/// The offset just past the element [tag] opens, or -1 when it does not end.
int _elementEnd(String text, RegExpMatch tag) {
  if (tag.group(2) == '/') return tag.end;
  final String name = tag.group(1)!;
  int depth = 1;
  for (final RegExpMatch m in RegExp(
    '<(/?)${RegExp.escape(name)}(?:\\s[^<>]*?)?(/?)>',
  ).allMatches(text, tag.end)) {
    if (m.group(1) == '/') {
      depth--;
    } else if (m.group(2) != '/') {
      depth++;
    }
    if (depth == 0) return m.end;
  }
  return -1;
}

/// Reads, sets, undoes and saves every W3 and W4 member of [bytes].
///
/// It opens the file and reads every getter of the workbook and of each
/// sheet. Then, one edit at a time: every value read is set back, which must
/// record nothing and which only a part the model cannot edit may refuse,
/// never the value (a value read always goes back); the first validation,
/// format, link and name of each sheet are removed, which the value must
/// not stop either; each feature is cleared and given a new value, which may
/// be refused as the API documents, and so may a read name or validation or
/// format added back: `definedNames` lists a name as the file has it,
/// whatever the writer's rules, and a twin of what was removed may remain.
/// The objects take the same steps: every rich text, note, picture's anchor
/// and table's style is set back; the first note, picture and table are
/// removed and added back; and a rich text, a note, a picture and a table
/// are set, changed, removed and set again on free cells.
///
/// It renders the warnings, undoes every edit in reverse order and saves,
/// redoes them, saves, reopens and reads the saved file, undoes them again
/// and saves. With [proveUndo], a save comes before the edits too, and the
/// first save after undo must equal it by [undoDifferences], told that
/// [mutated] was the part a mutation changed.
///
/// Returns normally or throws [XlsxReadException]: from `open`, or after the
/// rest has run, the first a sheet's or part's read threw. Anything else,
/// and any refusal outside those above, is a defect, and is rethrown as a
/// [StateError] naming the step. `save()` must never throw.
void exerciseFeatures(
  Uint8List bytes, {
  bool proveUndo = false,
  String? mutated,
}) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  final _Run run = _Run(book);
  if (proveUndo) run.before = _save(book, 'save() before the edits');
  run.read('workbook', () => _readWorkbook(book));
  final Set<int> unreadable = <int>{};
  for (int i = 0; i < book.sheets.length; i++) {
    final XlsxSheet sheet = book.sheets[i];
    if (!run.read(sheet.name, () => _readSheet(sheet))) unreadable.add(i);
  }
  run.editWorkbook();
  for (int i = 0; i < book.sheets.length; i++) {
    if (!unreadable.contains(i)) run.editSheet(book.sheets[i]);
  }
  for (final XlsxWarning warning in book.warnings) {
    for (final OfficeLocale locale in OfficeLocale.values) {
      warning.message(locale);
    }
  }
  run.undo();
  final Uint8List undone = _save(book, 'save() after undo');
  final Uint8List? before = run.before;
  if (before != null) {
    final List<String> differences = undoDifferences(
      before,
      undone,
      mutated: mutated,
    );
    if (differences.isNotEmpty) {
      throw StateError('undo left: ${differences.join('; ')}');
    }
  }
  run.redo();
  run.reopen(_save(book, 'save()'), unreadable);
  run.undo();
  _save(book, 'save() after a save and undo');
  final XlsxReadException? first = run.first;
  if (first != null) throw first;
}

/// What [undoDifferences] takes for a mutation of the archive's bytes.
const String archiveMutated = '(archive)';

/// [exerciseFeatures] on the case [c], proving undo with what it mutated.
void exerciseFeatureCase(FuzzCase c) => exerciseFeatures(
  c.bytes,
  proveUndo: true,
  mutated: mutatedPart(c.mutation) ?? archiveMutated,
);

/// What differs by meaning between the save [before] the edits and the save
/// [after] undoing them.
///
/// Left out everywhere, as a part a save writes afresh is not the bytes it
/// read: what asks Excel to recalculate (`fullCalcOnLoad`, which an undone
/// edit keeps, the log saying a change still counts), a character reference
/// XML forbids, which such a part scrubs, a styles group's `count`, which it
/// recomputes, and the namespace of a `.rels` root, which it states.
///
/// Left out only for the part [mutated], the one a case changed, so every
/// other part must come back whole. It is `null` for a file as it was made.
/// A mutated part a strict parser refuses cannot be compared by meaning: it
/// is left out when the lenient reader wrote it well formed or when both are
/// the same text, and the shared strings with it, whose comparison counts
/// the cells it holds. A mutated `.rels` part `Relationships.parse` loses
/// something of is left out with what it resolves in its source, as an edit
/// writes it from that parse and it stays repaired after undo: a part with a
/// second root (a `<Relationship>` copied before `<Relationships>`) comes
/// back well formed, an element that is no relationship and a relationship
/// without `Id`, `Type` or `Target` go, and a `TargetMode` other than
/// `External` becomes none. Text between the elements of a mutated part goes
/// too, which nothing reads and a part written afresh leaves out, and all
/// text of a mutated styles part.
///
/// When [mutated] is the shared strings, or [archiveMutated], the strings
/// and what cells show through them are left out and the rest is compared.
/// An edit writes that part afresh from what it read, a repair that stays:
/// `<si>` items of two `<t>` become one, and a part in another namespace, or
/// an entry a mutated archive renamed, reads as no strings, so the strings
/// an edit added give the file's indexes a meaning they lacked. With such a
/// rename the workbook's relationship to the strings goes with them, as the
/// save adds it.
List<String> undoDifferences(
  Uint8List before,
  Uint8List after, {
  String? mutated,
}) {
  final Map<String, Uint8List> a = _normalized(before, mutated);
  final Map<String, Uint8List> b = _normalized(after, mutated);
  Uint8List zip(Map<String, Uint8List> parts) =>
      buildZipOrdered(<(String, List<int>)>[
        for (final MapEntry<String, Uint8List> e in parts.entries)
          (e.key, e.value),
      ], store: true);
  final List<String> lines = comparePackages(
    zip(a),
    zip(b),
    ignoreBookkeeping: true,
  );
  String partOf(String line) => line.substring(0, line.indexOf(':'));
  final bool refused = lines.any(
    (String line) =>
        partOf(line) == mutated &&
        line.contains('the expected part is not well-formed'),
  );
  final bool lossy =
      mutated != null &&
      mutated.endsWith('.rels') &&
      a.containsKey(mutated) &&
      _lossyRelationships(utf8.decode(a[mutated]!));
  final bool blind = refused || lossy;
  final String? source = blind && mutated!.endsWith('.rels')
      ? mutated.replaceFirst('_rels/', '').replaceFirst(RegExp(r'\.rels$'), '')
      : null;
  final bool strings =
      blind || mutated == 'xl/sharedStrings.xml' || mutated == archiveMutated;
  final bool archive = mutated == archiveMutated;
  return <String>[
    for (final String line in lines)
      if (!(blind && partOf(line) == mutated) &&
          !(partOf(line) == source && _resolvedId.hasMatch(line)) &&
          !(strings && partOf(line) == 'xl/sharedStrings.xml') &&
          !((mutated == 'xl/sharedStrings.xml' || archive) &&
              _stringCell.hasMatch(line)) &&
          !(archive && partOf(line) == 'xl/_rels/workbook.xml.rels') &&
          !RegExp(r'^xl/styles\.xml: .*: attribute count ').hasMatch(line) &&
          !RegExp(r'\.rels: /Relationships: element ').hasMatch(line))
        line,
  ];
}

/// A difference of `comparePackages` in the string a shared string cell
/// shows; a cell of any other type stays a difference.
final RegExp _stringCell = RegExp(
  r'^xl/worksheets/[^:]*: [A-Z]+\d+/v: text "(<si>|unresolved:).*" vs '
  r'"(<si>|unresolved:)',
);

/// A difference of `comparePackages` in what a relationship id resolves to,
/// which it gives as `type|target|mode`.
final RegExp _resolvedId = RegExp(r': attribute \w+ .*\|');

/// Whether `Relationships.parse` loses something of the `.rels` [text].
bool _lossyRelationships(String text) =>
    RegExp(r'<(?!/?Relationships?[\s/>])[A-Za-z]').hasMatch(text) ||
    RegExp(r'<Relationship\s[^>]*>').allMatches(text).any((Match m) {
      final String tag = m.group(0)!;
      final String? mode = RegExp(
        r'\sTargetMode\s*=\s*"([^"]*)"',
      ).firstMatch(tag)?.group(1);
      return (mode != null && mode != 'External' && mode != 'Internal') ||
          !<String>[
            'Id',
            'Type',
            'Target',
          ].every((String name) => RegExp('\\s$name\\s*=').hasMatch(tag));
    });

/// The parts of [zip] without what [undoDifferences] leaves out of its text,
/// [mutated] being the part a case changed.
Map<String, Uint8List> _normalized(Uint8List zip, String? mutated) =>
    <String, Uint8List>{
      for (final MapEntry<String, Uint8List> e in readXlsxBytes(zip).entries)
        e.key: Uint8List.fromList(
          utf8.encode(
            (e.key == mutated
                    ? _withoutStrayText(
                        e.key,
                        utf8.decode(e.value, allowMalformed: true),
                      )
                    : utf8.decode(e.value, allowMalformed: true))
                .replaceAll(RegExp('&#1;|&#xFFFE;'), '')
                .replaceAll(RegExp(r'<(\w+:)?calcPr fullCalcOnLoad="1"/>'), '')
                .replaceAll(' fullCalcOnLoad="1"', ''),
          ),
        ),
    };

/// [text] without the text between the elements of the part [name]; the
/// text of a VML drawing may be mixed with its elements, and no element of a
/// styles part has text.
String _withoutStrayText(String name, String text) => name.endsWith('.vml')
    ? text
    : name == 'xl/styles.xml'
    ? text.replaceAll(RegExp(r'>[^<]+<'), '><')
    : text
          .replaceAllMapped(
            RegExp(r'(/>|</[\w:]+>)[^<]+<'),
            (Match m) => '${m.group(1)}<',
          )
          .replaceAll(RegExp(r'>[^<]+<(?=[A-Za-z])'), '><');

Uint8List _save(XlsxWorkbook book, String step) {
  try {
    return book.save().bytes;
  } on Object catch (e) {
    throw StateError('$step threw: $e');
  }
}

/// Reads the workbook's W3 members.
void _readWorkbook(XlsxWorkbook book) {
  book.definedNames.toString();
  book.protection.toString();
  book.hasStoredPassword.toString();
  book.properties.toString();
}

/// The cells of [sheet] that hold a string, by row and column.
List<(int, int)> _stringCells(XlsxSheet sheet) => <(int, int)>[
  for (final XlsxReadRow row in sheet.rows)
    for (final XlsxReadCell cell in row.cells)
      if (cell.value is String) (row.index, cell.column),
];

/// Reads the sheet's rows and its W3 and W4 members.
void _readSheet(XlsxSheet sheet) {
  sheet.rows.toList();
  for (final (int row, int column) in _stringCells(sheet)) {
    sheet.richTextAt(row, column).toString();
  }
  sheet.notes.toString();
  sheet.noteAt(0, 0).toString();
  sheet.pictures.toString();
  sheet.tables.toString();
  sheet.definedNames.toString();
  sheet.printArea.toString();
  sheet.printTitles.toString();
  sheet.autoFilter.toString();
  sheet.protection.toString();
  sheet.hasStoredPassword.toString();
  sheet.pageSetup.toString();
  sheet.headerFooter.toString();
  sheet.hyperlinks.toString();
  sheet.hyperlinkAt(0, 0).toString();
  sheet.dataValidations.toString();
  sheet.conditionalFormats.toString();
}

/// The [StateError]s the API documents for an edit: a part it cannot edit, or
/// a cell inside an array, a table header or a link over several cells.
final RegExp _refusedStates = RegExp(
  'has no worksheet part|is not a worksheet|'
  'styles part( of the workbook)? is not a SpreadsheetML|'
  'document properties part is not|<cols> cannot|<sheetFormatPr> cannot|'
  'part of an array|is a header cell|is covered by|'
  'belongs to a threaded comment|comments part of sheet|VML drawing of sheet|'
  'drawing of sheet|has a totals row|has a sort state|'
  'has relationships of its own|cannot be removed:',
);

/// The fields an [ArgumentError] of an edit names.
final RegExp _refusedFields = RegExp(
  r'^(name|formula\d?|comment|cell|validation|format|ranges?(\[\d+\].*)?|'
  r'runs.*|author|style|columns.*|values.*)$',
);

/// One [exerciseFeatures] over a workbook: the edits it made and the first
/// [XlsxReadException] it met.
final class _Run {
  _Run(this.book) : log = changeLogOf(book);

  final XlsxWorkbook book;
  final ChangeLog log;
  final List<ChangeSet> sets = <ChangeSet>[];

  /// The save before the edits, which a save after undo must equal.
  Uint8List? before;
  XlsxReadException? first;

  /// Runs [body], which may throw only an [XlsxReadException], and says
  /// whether it ran to its end.
  bool read(String what, void Function() body) {
    try {
      body();
      return true;
    } on XlsxReadException catch (e) {
      e.toString();
      first ??= e;
      return false;
    } on Object catch (e) {
      throw StateError('reading $what threw: $e');
    }
  }

  /// Sets back what was read: an equal set records nothing, and only a part
  /// the model cannot edit may refuse.
  void back(String what, void Function() body) {
    final ChangeSet? set = _edit(what, body, false);
    if (set != null && !set.isEmpty) {
      throw StateError('$what recorded a change setting back a value read');
    }
  }

  /// Removes what was read: only a part the model cannot edit may refuse.
  void remove(String what, void Function() body) => _edit(what, body, false);

  /// Sets a new value: the API may refuse it as an [ArgumentError] too,
  /// for a clash with what a mutated file holds.
  void change(String what, void Function() body) => _edit(what, body, true);

  /// Runs the edit [body] and keeps its changes, which it returns; `null`
  /// when it was refused. A refusal must be one the API documents: an
  /// [ArgumentError] only when [refusable], naming a field, and a
  /// [StateError] matching [_refusedStates]. Any other, a [RangeError] or
  /// an [IndexError] above all, is an internal crash.
  ChangeSet? _edit(String what, void Function() body, bool refusable) {
    try {
      final ChangeSet set = log.transaction(body);
      if (!set.isEmpty) sets.add(set);
      return set;
    } on XlsxReadException catch (e) {
      first ??= e;
    } on UnsupportedError {
      // A shared formula's master: refused by design until W5.
    } on XlsxLimitError {
      // A file already past a writer limit: refused by design.
    } on RangeError catch (e) {
      throw StateError('$what threw: $e');
    } on StateError catch (e) {
      if (!_refusedStates.hasMatch(e.message)) {
        throw StateError('$what threw: $e');
      }
    } on ArgumentError catch (e) {
      if (!refusable) throw StateError('$what refused a value read: $e');
      if (!_refusedFields.hasMatch('${e.name}')) {
        throw StateError('$what threw: $e');
      }
    } on Object catch (e) {
      throw StateError('$what threw: $e');
    }
    return null;
  }

  void editWorkbook() {
    final XlsxWorkbook b = book;
    back('book.protection', () => b.protection = b.protection);
    back('book.properties', () => b.properties = b.properties);
    read('names', () {
      final List<XlsxDefinedName> names = b.definedNames.toList();
      for (final XlsxDefinedName name in names.take(1)) {
        remove('book.removeName', () => b.removeName(name.name));
        change('book.defineName', () => b.defineName(name));
      }
    });
    change('book.defineName', () {
      b.defineName(const XlsxDefinedName('FuzzName', '1'));
    });
    change('book.removeName', () => b.removeName('FuzzName'));
    change('book.defineName', () {
      b.defineName(const XlsxDefinedName('FuzzName', 'SUM(1,2)'));
    });
    change('book.protection', () => b.protection = null);
    change('book.protection', () {
      b.protection = const XlsxWorkbookProtection(password: 'x');
    });
    change('book.properties', () {
      b.properties = XlsxProperties(
        title: 'Fuzz',
        modified: DateTime.utc(2026, 11, 5),
        custom: const <String, Object>{'Fuzz': 1},
      );
    });
  }

  void editSheet(XlsxSheet s) {
    _setBack(s);
    _removeFirst(s);
    _clear(s);
    _setNew(s);
    _setObjectsBack(s);
    _removeFirstObjects(s);
    _setNewObjects(s);
  }

  void _setObjectsBack(XlsxSheet s) {
    read('objects', () {
      for (final (int row, int column) in _stringCells(s)) {
        final XlsxRichText? rich = s.richTextAt(row, column);
        if (rich != null) back('setCell', () => s.setCell(row, column, rich));
      }
      for (final XlsxCellNote n in s.notes) {
        back('setNote', () => s.setNote(n.row, n.column, n.note));
      }
      final List<XlsxPicture> pictures = s.pictures;
      for (int i = 0; i < pictures.length; i++) {
        back('movePicture', () => s.movePicture(i, pictures[i].anchor));
      }
      for (final XlsxTable t in s.tables) {
        back('setTableStyle', () => s.setTableStyle(t.name, t.style));
      }
    });
  }

  void _removeFirstObjects(XlsxSheet s) {
    read('first objects', () {
      for (final XlsxCellNote n in s.notes.take(1).toList()) {
        remove('setNote', () => s.setNote(n.row, n.column, null));
        change('setNote', () => s.setNote(n.row, n.column, n.note));
      }
      for (final XlsxPicture p in s.pictures.take(1).toList()) {
        remove('removePicture', () => s.removePicture(0));
        change('addPicture', () => s.addPicture(p));
      }
      for (final XlsxTable t in s.tables.take(1).toList()) {
        remove('removeTable', () => s.removeTable(t.name));
        change('addTable', () => s.addTable(t));
      }
    });
  }

  void _setNewObjects(XlsxSheet s) {
    const XlsxFont bold = XlsxFont(bold: true);
    final String table = 'FuzzTable${book.sheets.indexOf(s)}';
    final XlsxPicture picture = XlsxPicture(
      OfficeImage(png4x2),
      const XlsxOneCellAnchor(XlsxAnchorPoint(1100, 31)),
    );
    change('setCell', () {
      s.setCell(
        1100,
        30,
        XlsxRichText(const <XlsxTextRun>[XlsxTextRun('Fuzz', font: bold)]),
      );
    });
    change('setNote', () => s.setNote(1100, 30, XlsxNote.plain('One')));
    change('setNote', () {
      s.setNote(1100, 30, XlsxNote.plain('Two', visible: true));
    });
    change('setNote', () => s.setNote(1100, 30, null));
    change('setNote', () => s.setNote(1100, 30, XlsxNote.plain('Three')));
    change('addPicture', () => s.addPicture(picture));
    read('new picture', () {
      final int last = s.pictures.length - 1;
      if (last < 0) return;
      change('movePicture', () {
        s.movePicture(last, const XlsxOneCellAnchor(XlsxAnchorPoint(1101, 31)));
      });
      change('removePicture', () => s.removePicture(last));
    });
    change('addPicture', () => s.addPicture(picture));
    change('addTable', () {
      s.addTable(
        XlsxTable(
          table,
          XlsxRange.parse('AK1100:AL1102'),
          const <XlsxTableColumn>[
            XlsxTableColumn('One'),
            XlsxTableColumn('Two'),
          ],
        ),
      );
    });
    change('setTableStyle', () {
      s.setTableStyle(table, XlsxTableStyle.light(1));
    });
    change('resizeTable', () {
      s.resizeTable(table, XlsxRange.parse('AK1100:AL1103'));
    });
    change('removeTable', () => s.removeTable(table));
    change('addTable', () {
      s.addTable(
        XlsxTable(
          table,
          XlsxRange.parse('AK1100:AL1102'),
          const <XlsxTableColumn>[
            XlsxTableColumn('One'),
            XlsxTableColumn('Two'),
          ],
        ),
      );
    });
  }

  void _setBack(XlsxSheet s) {
    back('protection', () => s.protection = s.protection);
    back('pageSetup', () => s.pageSetup = s.pageSetup);
    back('headerFooter', () => s.headerFooter = s.headerFooter);
    back('autoFilter', () => s.autoFilter = s.autoFilter);
    back('printArea', () => s.printArea = s.printArea);
    back('setPrintTitles', () {
      final ({(int, int)? rows, (int, int)? columns}) t = s.printTitles;
      s.setPrintTitles(rows: t.rows, columns: t.columns);
    });
    read('sheet names', () {
      final List<XlsxDefinedName> names = s.definedNames.toList();
      for (final XlsxDefinedName name in names.take(1)) {
        remove('removeName', () => s.removeName(name.name));
        change('defineName', () => s.defineName(name));
      }
    });
  }

  void _removeFirst(XlsxSheet s) {
    read('sheet entries', () {
      for (final XlsxDataValidation v in s.dataValidations.take(1).toList()) {
        remove('removeDataValidation', () => s.removeDataValidation(v));
        change('addDataValidation', () => s.addDataValidation(v));
      }
      for (final XlsxConditionalFormat f
          in s.conditionalFormats.take(1).toList()) {
        remove('removeConditionalFormat', () => s.removeConditionalFormat(f));
        change('addConditionalFormat', () => s.addConditionalFormat(f));
      }
      for (final ({XlsxRange range, XlsxHyperlink link}) l
          in s.hyperlinks.take(1).toList()) {
        remove(
          'removeHyperlink',
          () => s.removeHyperlink(l.range.firstRow, l.range.firstColumn),
        );
      }
      for (final XlsxDefinedName name in s.definedNames.take(1).toList()) {
        remove('removeName', () => s.removeName(name.name));
      }
    });
  }

  void _clear(XlsxSheet s) {
    change('autoFilter', () => s.autoFilter = null);
    change('printArea', () => s.printArea = const <XlsxRange>[]);
    change('setPrintTitles', s.setPrintTitles);
    change('protection', () => s.protection = null);
    change('pageSetup', () => s.pageSetup = null);
    change('headerFooter', () => s.headerFooter = null);
  }

  void _setNew(XlsxSheet s) {
    final XlsxRange far = XlsxRange.parse('AA1000:AB1001');
    final XlsxConditionalFormat bar = XlsxConditionalFormat(
      <XlsxRange>[far],
      <XlsxConditionalRule>[
        XlsxDataBar(
          color: XlsxColor.hex('638EC6'),
          axis: XlsxDataBarAxis.middle,
        ),
      ],
    );
    final XlsxConditionalFormat styled = XlsxConditionalFormat(
      <XlsxRange>[far],
      const <XlsxConditionalRule>[
        XlsxCellValueRule(
          XlsxComparison.lessThan,
          '40',
          style: XlsxStyle(font: XlsxFont(bold: true)),
        ),
      ],
    );
    final XlsxDataValidation validation = XlsxDataValidation.whole(
      <XlsxRange>[far],
      XlsxComparison.between,
      1,
      b: 2,
    );
    change('autoFilter', () => s.autoFilter = XlsxRange.parse('A1:B2'));
    change('printArea', () => s.printArea = <XlsxRange>[far]);
    change('setPrintTitles', () => s.setPrintTitles(rows: (0, 1)));
    change('protection', () {
      s.protection = const XlsxSheetProtection(allowFormatColumns: true);
    });
    change('pageSetup', () {
      s.pageSetup = const XlsxPageSetup(fitToWidth: 1, printHeadings: true);
    });
    change('headerFooter', () {
      s.headerFooter = const XlsxHeaderFooter(oddHeader: 'Fuzz');
    });
    change('setCell', () {
      s.setCell(999, 26, XlsxHyperlink.url('https://example.com/fuzz'));
    });
    change('removeHyperlink', () => s.removeHyperlink(999, 26));
    change('setCell', () {
      s.setCell(999, 26, XlsxHyperlink.location('FuzzName', text: 'Fuzz'));
    });
    change('addDataValidation', () => s.addDataValidation(validation));
    change('removeDataValidation', () => s.removeDataValidation(validation));
    change('addDataValidation', () => s.addDataValidation(validation));
    change('addConditionalFormat', () => s.addConditionalFormat(bar));
    change('removeConditionalFormat', () => s.removeConditionalFormat(bar));
    change('addConditionalFormat', () => s.addConditionalFormat(bar));
    change('addConditionalFormat', () => s.addConditionalFormat(styled));
    change('defineName', () {
      s.defineName(const XlsxDefinedName('FuzzLocal', '2'));
    });
    change('removeName', () => s.removeName('FuzzLocal'));
  }

  /// Opens [saved] and reads it: a sheet at the [unreadable] positions may
  /// throw an [XlsxReadException], and only those.
  void reopen(Uint8List saved, Set<int> unreadable) {
    final XlsxWorkbook again;
    try {
      again = XlsxWorkbook.open(saved);
    } on Object catch (e) {
      throw StateError('opening the saved workbook threw: $e');
    }
    for (int i = 0; i < again.sheets.length; i++) {
      try {
        _readSheet(again.sheets[i]);
      } on XlsxReadException catch (e) {
        if (!unreadable.contains(i)) {
          throw StateError('sheet $i of the saved workbook threw: $e');
        }
      } on Object catch (e) {
        throw StateError('sheet $i of the saved workbook threw: $e');
      }
    }
  }

  /// Undoes every edit in reverse order: a change whose revert throws is a
  /// defect.
  void undo() {
    try {
      sets.reversed.forEach(log.revertSet);
    } on Object catch (e) {
      throw StateError('undo threw: $e');
    }
  }

  /// Redoes every edit in order.
  void redo() {
    try {
      sets.forEach(log.reapplySet);
    } on Object catch (e) {
      throw StateError('redo threw: $e');
    }
  }
}
