/// Test helper: XLSX packages in the style of producers other than Excel and
/// `XlsxWriter`, each with the values the reader must return for it.
///
/// [producerFiles] lists them and [expectProducerFile] reads one and compares
/// everything: the date system, the sheets, every cell's value, hidden rows,
/// merges and the warnings.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'zip_builder.dart';

/// A package written in the style of one producer, and what the reader must
/// return for it.
final class ProducerFile {
  /// The package [bytes] of producer [name], whose [sheets] are expected in
  /// workbook order, with [warnings] in total per code and the date system
  /// [date1904].
  const ProducerFile(
    this.name,
    this.bytes,
    this.sheets, {
    this.warnings = const <XlsxWarningCode, int>{},
    this.date1904 = false,
  });

  /// The producer, such as `libreoffice` or `google_sheets`; also the test
  /// name.
  final String name;

  /// The XLSX package.
  final Uint8List bytes;

  /// The expected sheets, in workbook order.
  final List<ProducerSheet> sheets;

  /// The expected warnings: for each code, the sum of [XlsxWarning.count]
  /// over all sheets. A code not listed must not occur.
  final Map<XlsxWarningCode, int> warnings;

  /// Whether the workbook uses the 1904 date system.
  final bool date1904;
}

/// One expected sheet of a [ProducerFile].
final class ProducerSheet {
  /// The sheet [name] holding [rows], with its [visibility], [merges] in
  /// file order and the 0-based indexes of its [hiddenRows].
  const ProducerSheet(
    this.name,
    this.rows, {
    this.visibility = XlsxSheetVisibility.visible,
    this.merges = const <XlsxRange>[],
    this.hiddenRows = const <int>{},
  });

  /// The sheet name.
  final String name;

  /// The values, dense: `rows[0]` is sheet row 1, `rows[r][c]` column `c`.
  /// `null` means no cell, and a row past the end holds no cell.
  final List<List<Object?>> rows;

  /// Whether the sheet is visible, hidden or very hidden.
  final XlsxSheetVisibility visibility;

  /// The merged ranges, in file order.
  final List<XlsxRange> merges;

  /// The 0-based indexes of the rows the file hides. A hidden row is
  /// yielded by the reader even when it has no cell.
  final Set<int> hiddenRows;
}

/// Every producer package, for the tests that read each one and for the
/// fuzz corpus.
List<ProducerFile> producerFiles() => <ProducerFile>[
  libreOfficeFile(),
  googleSheetsFile(),
  dotNetSdkFile(),
  erpExportFile(),
];

/// Reads [f] and fails with a [TestFailure] listing every difference from
/// what it expects.
///
/// Values compare with `==`: an [XlsxDecimal] by its digits, a `DateTime`
/// exactly, an [XlsxErrorValue] by its code. A read row is densified to the
/// expected width; a cell beyond it, or a row beyond the expected rows, is a
/// difference. Warnings compare as `{code: total count}`.
void expectProducerFile(ProducerFile f) {
  final XlsxReader reader = XlsxReader(f.bytes);
  final List<String> problems = <String>[];
  if (reader.date1904 != f.date1904) {
    problems.add('date1904: expected ${f.date1904}, got ${reader.date1904}');
  }
  final List<XlsxReadSheet> sheets = reader.sheets;
  if (sheets.length != f.sheets.length) {
    problems.add(
      'sheets: expected ${f.sheets.map((ProducerSheet s) => s.name)}, '
      'got ${sheets.map((XlsxReadSheet s) => s.name)}',
    );
  }
  for (int i = 0; i < sheets.length && i < f.sheets.length; i++) {
    _compareSheet(reader, i, f.sheets[i], problems);
  }
  final Map<XlsxWarningCode, int> warnings = <XlsxWarningCode, int>{};
  for (final XlsxWarning w in reader.warnings) {
    warnings[w.code] = (warnings[w.code] ?? 0) + w.count;
  }
  for (final XlsxWarningCode code in <XlsxWarningCode>{
    ...warnings.keys,
    ...f.warnings.keys,
  }) {
    if (warnings[code] != f.warnings[code]) {
      problems.add(
        'warning ${code.name}: expected ${f.warnings[code] ?? 0}, '
        'got ${warnings[code] ?? 0}',
      );
    }
  }
  if (problems.isNotEmpty) {
    fail('${f.name} reads differently:\n  ${problems.join('\n  ')}');
  }
}

/// Compares sheet [index] of [reader] with [expected], adding each
/// difference to [problems].
void _compareSheet(
  XlsxReader reader,
  int index,
  ProducerSheet expected,
  List<String> problems,
) {
  final XlsxReadSheet sheet = reader.sheets[index];
  final String at = 'sheet ${expected.name}';
  if (sheet.name != expected.name) {
    problems.add('$at: name is ${sheet.name}');
  }
  if (sheet.visibility != expected.visibility) {
    problems.add(
      '$at: expected ${expected.visibility.name}, got '
      '${sheet.visibility.name}',
    );
  }
  final Map<int, XlsxReadRow> read = <int, XlsxReadRow>{};
  final Set<int> hidden = <int>{};
  for (final XlsxReadRow row in reader.rowsAt(index)) {
    if (read.containsKey(row.index)) {
      problems.add('$at: row ${row.index + 1} read twice');
    }
    read[row.index] = row;
    if (row.hidden) hidden.add(row.index);
  }
  for (final int row in hidden.difference(expected.hiddenRows)) {
    problems.add('$at: row ${row + 1} hidden, expected visible');
  }
  for (final int row in expected.hiddenRows.difference(hidden)) {
    problems.add('$at: row ${row + 1} expected hidden, not read as hidden');
  }
  final int height = <int>[
    expected.rows.length,
    for (final int row in read.keys) row + 1,
  ].reduce((int a, int b) => a > b ? a : b);
  for (int r = 0; r < height; r++) {
    final List<Object?> want = r < expected.rows.length
        ? expected.rows[r]
        : const <Object?>[];
    final List<XlsxReadCell> cells = read[r]?.cells ?? const <XlsxReadCell>[];
    final List<Object?> got = List<Object?>.filled(want.length, null);
    final Set<int> present = <int>{};
    for (final XlsxReadCell cell in cells) {
      if (cell.column >= want.length) {
        problems.add(
          '$at ${_cellName(r, cell.column)}: expected nothing, '
          'got ${_show(cell.value)}',
        );
      } else {
        got[cell.column] = cell.value;
        present.add(cell.column);
      }
    }
    for (int c = 0; c < want.length; c++) {
      if (want[c] == null && present.contains(c)) {
        problems.add(
          '$at ${_cellName(r, c)}: expected nothing, got ${_show(got[c])}',
        );
      } else if (want[c] != null && got[c] != want[c]) {
        problems.add(
          '$at ${_cellName(r, c)}: expected ${_show(want[c])}, '
          'got ${present.contains(c) ? _show(got[c]) : 'nothing'}',
        );
      }
    }
  }
  final List<XlsxRange> merges = reader.mergesAt(index);
  if (!_sameList(merges, expected.merges)) {
    problems.add('$at: merges expected ${expected.merges}, got $merges');
  }
}

/// Whether [a] and [b] hold equal elements in the same order.
bool _sameList(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The A1 name of the cell at 0-based [row] and [column].
String _cellName(int row, int column) {
  String letters = '';
  for (int c = column + 1; c > 0; c = (c - 1) ~/ 26) {
    letters = String.fromCharCode(0x41 + (c - 1) % 26) + letters;
  }
  return '$letters${row + 1}';
}

/// [value] with its type, so `'5'` and `XlsxDecimal(5)` read apart.
String _show(Object? value) => switch (value) {
  null => 'null',
  final String s => "'$s'",
  final DateTime d => 'DateTime($d)',
  _ => '$value',
};

// Namespaces and types every producer writes.
const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRelNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _ctNs =
    'http://schemas.openxmlformats.org/package/2006/content-types';
const String _mcNs =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';
const String _x14acNs =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';
const String _x14Ns =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';
const String _ctSheet =
    'application/vnd.openxmlformats-officedocument.spreadsheetml';
const String _ctRels =
    'application/vnd.openxmlformats-package.relationships+xml';

/// The declaration LibreOffice writes, on a line of its own.
const String _loDecl =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

/// A file in the style of LibreOffice Calc, saved as "Excel 2007-365".
///
/// Written from knowledge of Calc's output and checked against one file
/// LibreOffice 26.8 saved, not copied from it (plan ruling 6). As in that
/// file: the declaration and `standalone="yes"`, `fileVersion` with
/// `appName="Calc" lowestEdited="4"`, the `<workbookPr>` and `<calcPr>`
/// attributes, `General` written as `numFmtId="164"` (cell format 0 and the
/// default cell style use it, Calc's own formats follow from 165), `t="n"`
/// and `s` on every cell, the row attributes (`customFormat`, `ht`,
/// `hidden`), `<f aca="false">`, a date-time serial rounded to 15
/// significant digits, the page setup after `<mergeCells>`, the content
/// types (`Default` for `fntdata`, `jpeg`, `png`, `rels`, `xml`, then an
/// `Override` per part) and the entry order (relationships, workbook,
/// shared strings, styles, sheets, `docProps`, `[Content_Types].xml`
/// last). From knowledge only, and not in what 26.8 writes: `spans` on
/// rows, `mc:Ignorable="x14ac"` and `x14ac:dyDescent` (older Calc versions
/// wrote them; the R3 plan asks for them), the rich-text run properties,
/// `hidden="true"` on a hidden row and the second, hidden sheet. The styles
/// part is shorter than Calc's, and there is no theme part.
///
/// Sheet `Ürünler` holds codes with leading zeros (text), a 13-digit
/// barcode (number in format `0`), prices in a lira format, dates, times, a
/// date-time, booleans, number, text and error formula results, a
/// rich-text shared string, the merge `F2:F3` and a hidden empty row 4.
/// Sheet `Notlar` is hidden and holds one cell. No warning is expected.
ProducerFile libreOfficeFile() {
  const String sst =
      '<sst xmlns="$_main" count="14" uniqueCount="14">'
      '<si><t xml:space="preserve">Kod</t></si>'
      '<si><t xml:space="preserve">Barkod</t></si>'
      '<si><t xml:space="preserve">Fiyat</t></si>'
      '<si><t xml:space="preserve">Tarih</t></si>'
      '<si><t xml:space="preserve">Saat</t></si>'
      '<si><t xml:space="preserve">Stokta</t></si>'
      '<si><t xml:space="preserve">KDV Dahil</t></si>'
      '<si><t xml:space="preserve">Etiket</t></si>'
      '<si><t xml:space="preserve">Kontrol</t></si>'
      '<si><t xml:space="preserve">00123</t></si>'
      '<si><r><rPr><b val="true"/><sz val="10"/><rFont val="Arial"/>'
      '<family val="2"/><charset val="162"/></rPr>'
      '<t xml:space="preserve">Kampanyalı</t></r>'
      '<r><rPr><sz val="10"/><rFont val="Arial"/><family val="2"/>'
      '<charset val="162"/></rPr><t xml:space="preserve"> ürün</t></r></si>'
      '<si><t xml:space="preserve">00124</t></si>'
      '<si><t xml:space="preserve">Toplam</t></si>'
      '<si><t xml:space="preserve">Fiyatlar KDV hariçtir.</t></si>'
      '</sst>';
  const String rowAttrs =
      'customFormat="false" ht="12.8" customHeight="false" '
      'outlineLevel="0" collapsed="false" x14ac:dyDescent="0.2"';
  const String sheet1 =
      '$_loDecl<worksheet xmlns="$_main" xmlns:r="$_relNs" '
      'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/'
      'spreadsheetDrawing" xmlns:x14="$_x14Ns" '
      'xmlns:xr2="http://schemas.microsoft.com/office/spreadsheetml/2015/'
      'revision2" xmlns:mc="$_mcNs" xmlns:x14ac="$_x14acNs" '
      'mc:Ignorable="x14ac">'
      '<sheetPr filterMode="false"><pageSetUpPr fitToPage="false"/>'
      '</sheetPr>'
      '<dimension ref="A1:I6"/>'
      '<sheetViews><sheetView showFormulas="false" showGridLines="true" '
      'showRowColHeaders="true" showZeros="true" rightToLeft="false" '
      'tabSelected="true" showOutlineSymbols="true" defaultGridColor="true" '
      'view="normal" topLeftCell="A1" colorId="64" zoomScale="100" '
      'zoomScaleNormal="100" zoomScalePageLayoutView="100" '
      'workbookViewId="0"><selection pane="topLeft" activeCell="H2" '
      'activeCellId="0" sqref="H2"/></sheetView></sheetViews>'
      '<sheetFormatPr defaultColWidth="11.53515625" defaultRowHeight="12.8" '
      'zeroHeight="false" outlineLevelRow="0" outlineLevelCol="0" '
      'x14ac:dyDescent="0.2"/>'
      '<cols><col collapsed="false" customWidth="true" hidden="false" '
      'outlineLevel="0" max="1" min="1" style="0" width="16.4"/>'
      '<col collapsed="false" customWidth="true" hidden="false" '
      'outlineLevel="0" max="2" min="2" style="0" width="15.2"/>'
      '<col collapsed="false" customWidth="false" hidden="false" '
      'outlineLevel="0" max="1025" min="3" style="0" width="11.52"/></cols>'
      '<sheetData>'
      '<row r="1" spans="1:9" $rowAttrs hidden="false">'
      '<c r="A1" s="5" t="s"><v>0</v></c>'
      '<c r="B1" s="5" t="s"><v>1</v></c>'
      '<c r="C1" s="5" t="s"><v>2</v></c>'
      '<c r="D1" s="5" t="s"><v>3</v></c>'
      '<c r="E1" s="5" t="s"><v>4</v></c>'
      '<c r="F1" s="5" t="s"><v>5</v></c>'
      '<c r="G1" s="5" t="s"><v>6</v></c>'
      '<c r="H1" s="5" t="s"><v>7</v></c>'
      '<c r="I1" s="5" t="s"><v>8</v></c>'
      '</row>'
      '<row r="2" spans="1:9" $rowAttrs hidden="false">'
      '<c r="A2" s="0" t="s"><v>9</v></c>'
      '<c r="B2" s="1" t="n"><v>8690000000017</v></c>'
      '<c r="C2" s="2" t="n"><v>149.9</v></c>'
      '<c r="D2" s="3" t="n"><v>46323</v></c>'
      '<c r="E2" s="4" t="n"><v>0.5625</v></c>'
      '<c r="F2" s="6" t="b"><v>1</v></c>'
      '<c r="G2" s="2" t="n"><f aca="false">C2*1.2</f><v>179.88</v></c>'
      '<c r="H2" s="0" t="str"><f aca="false">A2&amp;"-"&amp;B2</f>'
      '<v>00123-8690000000017</v></c>'
      '<c r="I2" s="0" t="e"><f aca="false">1/0</f><v>#DIV/0!</v></c>'
      '</row>'
      '<row r="3" spans="1:9" $rowAttrs hidden="false">'
      '<c r="A3" s="0" t="s"><v>10</v></c>'
      '<c r="C3" s="2" t="n"><v>100</v></c>'
      '<c r="D3" s="3" t="n"><v>46324</v></c>'
      '<c r="F3" s="6"/>'
      '<c r="G3" s="2" t="n"><f aca="false">C3*1.2</f><v>120</v></c>'
      '<c r="I3" s="7" t="n"><v>46319.5729166667</v></c>'
      '</row>'
      '<row r="4" spans="1:9" $rowAttrs hidden="true"/>'
      '<row r="5" spans="1:9" $rowAttrs hidden="false">'
      '<c r="A5" s="0" t="s"><v>11</v></c>'
      '<c r="B5" s="1" t="n"><v>8690000000024</v></c>'
      '<c r="C5" s="2" t="n"><v>1250</v></c>'
      '<c r="D5" s="3" t="n"><v>46023</v></c>'
      '<c r="E5" s="4" t="n"><v>0.75</v></c>'
      '<c r="F5" s="6" t="b"><v>0</v></c>'
      '<c r="G5" s="2" t="n"><f aca="false">C5*1.2</f><v>1500</v></c>'
      '<c r="H5" s="0" t="str"><f aca="false">A5&amp;"-"&amp;B5</f>'
      '<v>00124-8690000000024</v></c>'
      '</row>'
      '<row r="6" spans="1:9" $rowAttrs hidden="false">'
      '<c r="A6" s="5" t="s"><v>12</v></c>'
      '<c r="B6" s="0" t="n"><f aca="false">COUNTA(A2:A5)</f><v>3</v></c>'
      '</row>'
      '</sheetData>'
      '<mergeCells count="1"><mergeCell ref="F2:F3"/></mergeCells>'
      '<printOptions headings="false" gridLines="false" gridLinesSet="true" '
      'horizontalCentered="false" verticalCentered="false"/>'
      '<pageMargins left="0.7875" right="0.7875" top="1.05277777777778" '
      'bottom="1.05277777777778" header="0.7875" footer="0.7875"/>'
      '<pageSetup paperSize="9" scale="100" fitToWidth="1" fitToHeight="1" '
      'pageOrder="downThenOver" orientation="portrait" blackAndWhite="false" '
      'draft="false" cellComments="none" horizontalDpi="300" '
      'verticalDpi="300" copies="1"/>'
      '<headerFooter differentFirst="false" differentOddEven="false">'
      '<oddHeader>&amp;C&amp;"Times New Roman,Regular"&amp;12&amp;A'
      '</oddHeader><oddFooter>&amp;C&amp;"Times New Roman,Regular"&amp;12'
      'Sayfa &amp;P</oddFooter></headerFooter>'
      '</worksheet>';
  const String sheet2 =
      '$_loDecl<worksheet xmlns="$_main" xmlns:r="$_relNs" '
      'xmlns:mc="$_mcNs" xmlns:x14ac="$_x14acNs" mc:Ignorable="x14ac">'
      '<sheetPr filterMode="false"><pageSetUpPr fitToPage="false"/>'
      '</sheetPr>'
      '<dimension ref="A1"/>'
      '<sheetViews><sheetView showFormulas="false" showGridLines="true" '
      'showRowColHeaders="true" showZeros="true" rightToLeft="false" '
      'tabSelected="false" showOutlineSymbols="true" '
      'defaultGridColor="true" view="normal" topLeftCell="A1" colorId="64" '
      'zoomScale="100" zoomScaleNormal="100" zoomScalePageLayoutView="100" '
      'workbookViewId="0"><selection pane="topLeft" activeCell="A1" '
      'activeCellId="0" sqref="A1"/></sheetView></sheetViews>'
      '<sheetFormatPr defaultColWidth="11.53515625" defaultRowHeight="12.8" '
      'zeroHeight="false" outlineLevelRow="0" outlineLevelCol="0" '
      'x14ac:dyDescent="0.2"/>'
      '<cols><col collapsed="false" customWidth="false" hidden="false" '
      'outlineLevel="0" max="1025" min="1" style="0" width="11.52"/></cols>'
      '<sheetData><row r="1" spans="1:1" $rowAttrs hidden="false">'
      '<c r="A1" s="0" t="s"><v>13</v></c></row></sheetData>'
      '<printOptions headings="false" gridLines="false" gridLinesSet="true" '
      'horizontalCentered="false" verticalCentered="false"/>'
      '<pageMargins left="0.7875" right="0.7875" top="1.05277777777778" '
      'bottom="1.05277777777778" header="0.7875" footer="0.7875"/>'
      '<pageSetup paperSize="9" scale="100" fitToWidth="1" fitToHeight="1" '
      'pageOrder="downThenOver" orientation="portrait" blackAndWhite="false" '
      'draft="false" cellComments="none" horizontalDpi="300" '
      'verticalDpi="300" copies="1"/>'
      '<headerFooter differentFirst="false" differentOddEven="false">'
      '<oddHeader>&amp;C&amp;A</oddHeader><oddFooter>&amp;CSayfa &amp;P'
      '</oddFooter></headerFooter>'
      '</worksheet>';
  const String xfTail =
      'fontId="0" fillId="0" borderId="0" xfId="0" applyFont="false" '
      'applyBorder="false" applyAlignment="false" applyProtection="false">'
      '<alignment horizontal="general" vertical="bottom" textRotation="0" '
      'wrapText="false" indent="0" shrinkToFit="false"/>'
      '<protection locked="true" hidden="false"/></xf>';
  const String styles =
      '$_loDecl<styleSheet xmlns="$_main">'
      '<numFmts count="5">'
      '<numFmt numFmtId="164" formatCode="General"/>'
      r'<numFmt numFmtId="165" formatCode="#,##0.00\ &quot;₺&quot;"/>'
      '<numFmt numFmtId="166" formatCode="DD.MM.YYYY"/>'
      '<numFmt numFmtId="167" formatCode="HH:MM"/>'
      r'<numFmt numFmtId="168" formatCode="DD.MM.YYYY\ HH:MM"/>'
      '</numFmts>'
      '<fonts count="2">'
      '<font><sz val="10"/><name val="Arial"/><family val="2"/>'
      '<charset val="162"/></font>'
      '<font><b val="true"/><sz val="10"/><name val="Arial"/>'
      '<family val="2"/><charset val="162"/></font>'
      '</fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border diagonalUp="false" diagonalDown="false">'
      '<left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="164" fontId="0" fillId="0" '
      'borderId="0" applyFont="true" applyBorder="true" '
      'applyAlignment="true" applyProtection="true">'
      '<alignment horizontal="general" vertical="bottom" textRotation="0" '
      'wrapText="false" indent="0" shrinkToFit="false"/>'
      '<protection locked="true" hidden="false"/></xf></cellStyleXfs>'
      '<cellXfs count="8">'
      '<xf numFmtId="164" $xfTail'
      '<xf numFmtId="1" $xfTail'
      '<xf numFmtId="165" $xfTail'
      '<xf numFmtId="166" $xfTail'
      '<xf numFmtId="167" $xfTail'
      '<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" '
      'applyFont="true" applyBorder="false" applyAlignment="false" '
      'applyProtection="false"><alignment horizontal="general" '
      'vertical="bottom" textRotation="0" wrapText="false" indent="0" '
      'shrinkToFit="false"/><protection locked="true" hidden="false"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" '
      'applyFont="false" applyBorder="false" applyAlignment="true" '
      'applyProtection="false"><alignment horizontal="center" '
      'vertical="center" textRotation="0" wrapText="false" indent="0" '
      'shrinkToFit="false"/><protection locked="true" hidden="false"/></xf>'
      '<xf numFmtId="168" $xfTail'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" '
      'builtinId="0"/></cellStyles>'
      '<colors><indexedColors><rgbColor rgb="FF000000"/>'
      '<rgbColor rgb="FFFFFFFF"/></indexedColors></colors>'
      '</styleSheet>';
  const String workbook =
      '$_loDecl<workbook xmlns="$_main" xmlns:r="$_relNs">'
      '<fileVersion appName="Calc" lowestEdited="4"/>'
      '<workbookPr backupFile="false" showObjects="all" date1904="false"/>'
      '<workbookProtection/>'
      '<bookViews><workbookView showHorizontalScroll="true" '
      'showVerticalScroll="true" showSheetTabs="true" xWindow="0" '
      'yWindow="0" windowWidth="16384" windowHeight="8192" tabRatio="500" '
      'firstSheet="0" activeTab="0"/></bookViews>'
      '<sheets>'
      '<sheet name="Ürünler" sheetId="1" state="visible" r:id="rId2"/>'
      '<sheet name="Notlar" sheetId="2" state="hidden" r:id="rId3"/>'
      '</sheets>'
      '<calcPr iterateCount="100" refMode="A1" iterate="false" '
      'iterateDelta="0.001"/>'
      '<extLst><ext xmlns:loext="http://schemas.libreoffice.org/" '
      'uri="{7626C862-2A13-11E5-B345-FEFF819CDC9F}">'
      '<loext:extCalcPr stringRefSyntax="CalcA1"/></ext></extLst>'
      '</workbook>';
  const String workbookRels =
      '$_loDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="$_relNs/styles" Target="styles.xml"/>'
      '<Relationship Id="rId2" Type="$_relNs/worksheet" '
      'Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId3" Type="$_relNs/worksheet" '
      'Target="worksheets/sheet2.xml"/>'
      '<Relationship Id="rId4" Type="$_relNs/sharedStrings" '
      'Target="sharedStrings.xml"/>'
      '</Relationships>';
  const String rootRels =
      '$_loDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="$_pkgRelNs/metadata/core-properties" '
      'Target="docProps/core.xml"/>'
      '<Relationship Id="rId2" Type="$_relNs/extended-properties" '
      'Target="docProps/app.xml"/>'
      '<Relationship Id="rId3" Type="$_relNs/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';
  const String core =
      '$_loDecl<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org'
      '/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dcterms:created xsi:type="dcterms:W3CDTF">2026-10-28T09:12:44Z'
      '</dcterms:created><dc:creator></dc:creator>'
      '<dc:description></dc:description><dc:language>tr-TR</dc:language>'
      '<cp:lastModifiedBy></cp:lastModifiedBy>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">2026-10-28T10:01:12Z'
      '</dcterms:modified><cp:revision>2</cp:revision>'
      '<dc:subject></dc:subject><dc:title></dc:title></cp:coreProperties>';
  const String app =
      '$_loDecl<Properties xmlns="http://schemas.openxmlformats.org/'
      'officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/'
      'docPropsVTypes"><Template></Template><TotalTime>3</TotalTime>'
      '<Application>LibreOffice/7.6.4.1\$Linux_X86_64 LibreOffice_project/'
      'e19e193f88cd6c0525a17fb7a176ed8e6a3e2aa1</Application>'
      '<AppVersion>15.0000</AppVersion></Properties>';
  const String contentTypes =
      '<?xml version="1.0" encoding="UTF-8"?>\n<Types xmlns="$_ctNs">'
      '<Default Extension="fntdata" ContentType="application/x-fontdata"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="rels" ContentType="$_ctRels"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" '
      'ContentType="$_ctSheet.sheet.main+xml"/>'
      '<Override PartName="/xl/sharedStrings.xml" '
      'ContentType="$_ctSheet.sharedStrings+xml"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="$_ctSheet.styles+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="$_ctSheet.worksheet+xml"/>'
      '<Override PartName="/xl/worksheets/sheet2.xml" '
      'ContentType="$_ctSheet.worksheet+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/'
      'vnd.openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.extended-properties+xml"/>'
      '\n</Types>';
  final Uint8List bytes = buildZipOrdered(<(String, List<int>)>[
    ('_rels/.rels', utf8.encode(rootRels)),
    ('xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)),
    ('xl/workbook.xml', utf8.encode(workbook)),
    ('xl/sharedStrings.xml', utf8.encode('$_loDecl$sst')),
    ('xl/styles.xml', utf8.encode(styles)),
    ('xl/worksheets/sheet1.xml', utf8.encode(sheet1)),
    ('xl/worksheets/sheet2.xml', utf8.encode(sheet2)),
    ('docProps/core.xml', utf8.encode(core)),
    ('docProps/app.xml', utf8.encode(app)),
    ('[Content_Types].xml', utf8.encode(contentTypes)),
  ]);
  return ProducerFile('libreoffice', bytes, <ProducerSheet>[
    ProducerSheet(
      'Ürünler',
      <List<Object?>>[
        <Object?>[
          'Kod',
          'Barkod',
          'Fiyat',
          'Tarih',
          'Saat',
          'Stokta',
          'KDV Dahil',
          'Etiket',
          'Kontrol',
        ],
        <Object?>[
          '00123',
          XlsxDecimal('8690000000017'),
          XlsxDecimal('149.9'),
          DateTime.utc(2026, 10, 28),
          const Duration(hours: 13, minutes: 30),
          true,
          XlsxDecimal('179.88'),
          '00123-8690000000017',
          XlsxErrorValue.div0,
        ],
        <Object?>[
          'Kampanyalı ürün',
          null,
          XlsxDecimal('100'),
          DateTime.utc(2026, 10, 29),
          null,
          null,
          XlsxDecimal('120'),
          null,
          // 46319.5729166667: 13:45 plus 0.00288 ms, to the millisecond.
          DateTime.utc(2026, 10, 24, 13, 45),
        ],
        <Object?>[],
        <Object?>[
          '00124',
          XlsxDecimal('8690000000024'),
          XlsxDecimal('1250'),
          DateTime.utc(2026),
          const Duration(hours: 18),
          false,
          XlsxDecimal('1500'),
          '00124-8690000000024',
        ],
        <Object?>['Toplam', XlsxDecimal('3')],
      ],
      merges: <XlsxRange>[XlsxRange.parse('F2:F3')],
      hiddenRows: const <int>{3},
    ),
    const ProducerSheet('Notlar', <List<Object?>>[
      <Object?>['Fiyatlar KDV hariçtir.'],
    ], visibility: XlsxSheetVisibility.hidden),
  ]);
}

/// The declaration Google Sheets writes: no encoding, so UTF-8.
const String _gsDecl = '<?xml version="1.0" ?>';

/// The namespaces Google Sheets declares on its workbook and worksheets.
const String _gsNamespaces =
    'xmlns="$_main" xmlns:r="$_relNs" '
    'xmlns:mx="http://schemas.microsoft.com/office/mac/excel/2008/main" '
    'xmlns:mc="$_mcNs" xmlns:mv="urn:schemas-microsoft-com:mac:vml" '
    'xmlns:x14="$_x14Ns" '
    'xmlns:x15="http://schemas.microsoft.com/office/spreadsheetml/2010/11/'
    'main" xmlns:x14ac="$_x14acNs" '
    'xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main"';

/// The 300-character note of [googleSheetsFile]'s first customer.
final String _longNote =
    ('Ödeme planı görüşüldü, taksit tarihleri '
                'yeniden düzenlenecek; ' *
            6)
        .substring(0, 300);

/// A shared-string item as Google Sheets writes every one.
String _gsItem(String text) => '<si><t xml:space="preserve">$text</t></si>';

/// A file in the style of Google Sheets' "Download as Microsoft Excel".
///
/// Written from knowledge of Google's export, not copied from a downloaded
/// file (plan ruling 6): the declaration without an encoding, the namespace
/// list (`mx`, `mv`, `x14`, `x15`, `x14ac`, `xm`), `ContentType` written
/// before `PartName`, no `docProps`, the entry order (the workbook's
/// relationships first, `[Content_Types].xml` last), `outlinePr` with
/// `summaryBelow="0" summaryRight="0"` in `<sheetPr>`, a frozen header pane, no
/// `<dimension>`, `<sheetFormatPr customHeight="1" defaultColWidth="12.63"
/// defaultRowHeight="15.75"/>`, rows with `customHeight="1" ht="15.75"`,
/// `<t xml:space="preserve">` in every `<si>`, number formats 164
/// `yyyy-mm-dd` and 165 `m/d/yyyy h:mm:ss`, formulas without `aca` and
/// `t="str"` text results, and a drawing part the sheet relates to (Google
/// writes one for a sheet with an image or chart) are as Google writes them
/// as far as known. The theme part is cut down to its root.
///
/// Sheet `Müşteriler` holds a phone number and a tax number with a leading
/// zero (text), a negative balance, a date and a date-time, a 300-character
/// note, a text formula and a styled blank between two values. No warning
/// is expected.
ProducerFile googleSheetsFile() {
  assert(_longNote.length == 300, 'the note must be 300 characters');
  final List<String> strings = <String>[
    'Müşteri',
    'Telefon',
    'Vergi No',
    'Bakiye',
    'Kayıt Tarihi',
    'Son Giriş',
    'Not',
    'Etiket',
    'Ayşe Yılmaz',
    '+90 532 000 00 00',
    '0123456789',
    _longNote,
    'Mehmet Öz',
    '0987654321',
  ];
  final String sst =
      '$_gsDecl<sst xmlns="$_main" count="14" uniqueCount="14">'
      '${strings.map(_gsItem).join()}</sst>';
  const String row = 'customHeight="1" ht="15.75"';
  const String sheet =
      '$_gsDecl<worksheet $_gsNamespaces>'
      '<sheetPr><outlinePr summaryBelow="0" summaryRight="0"/></sheetPr>'
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="1.0" topLeftCell="A2" activePane="bottomLeft" '
      'state="frozen"/><selection activeCell="B3" sqref="B3" '
      'pane="bottomLeft"/></sheetView></sheetViews>'
      '<sheetFormatPr customHeight="1" defaultColWidth="12.63" '
      'defaultRowHeight="15.75"/>'
      '<cols><col customWidth="1" min="1" max="1" width="18.0"/>'
      '<col customWidth="1" min="7" max="7" width="42.5"/></cols>'
      '<sheetData>'
      '<row r="1">'
      '<c r="A1" s="1" t="s"><v>0</v></c>'
      '<c r="B1" s="1" t="s"><v>1</v></c>'
      '<c r="C1" s="1" t="s"><v>2</v></c>'
      '<c r="D1" s="1" t="s"><v>3</v></c>'
      '<c r="E1" s="1" t="s"><v>4</v></c>'
      '<c r="F1" s="1" t="s"><v>5</v></c>'
      '<c r="G1" s="1" t="s"><v>6</v></c>'
      '<c r="H1" s="1" t="s"><v>7</v></c>'
      '</row>'
      '<row r="2" $row>'
      '<c r="A2" s="2" t="s"><v>8</v></c>'
      '<c r="B2" s="2" t="s"><v>9</v></c>'
      '<c r="C2" s="2" t="s"><v>10</v></c>'
      '<c r="D2" s="5"><v>-1250.5</v></c>'
      '<c r="E2" s="3"><v>46323.0</v></c>'
      '<c r="F2" s="4"><v>46323.5625</v></c>'
      '<c r="G2" s="6" t="s"><v>11</v></c>'
      '<c r="H2" s="2" t="str"><f>CONCATENATE(A2," / ",C2)</f>'
      '<v>Ayşe Yılmaz / 0123456789</v></c>'
      '</row>'
      '<row r="3" $row>'
      '<c r="A3" s="2" t="s"><v>12</v></c>'
      '<c r="B3" s="2"/>'
      '<c r="C3" s="2" t="s"><v>13</v></c>'
      '<c r="D3" s="5"><v>3400.75</v></c>'
      '<c r="E3" s="3"><v>46324.0</v></c>'
      '<c r="H3" s="2" t="str"><f>CONCATENATE(A3," / ",C3)</f>'
      '<v>Mehmet Öz / 0987654321</v></c>'
      '</row>'
      '</sheetData>'
      '<drawing r:id="rId1"/>'
      '</worksheet>';
  const String sheetRels =
      '$_gsDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="$_relNs/drawing" '
      'Target="../drawings/drawing1.xml"/>'
      '</Relationships>';
  const String drawing =
      '$_gsDecl<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/'
      'drawingml/2006/spreadsheetDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="$_relNs" xmlns:c="http://schemas.openxmlformats.org/'
      'drawingml/2006/chart" xmlns:cx="http://schemas.microsoft.com/office/'
      'drawing/2014/chartex" xmlns:cx1="http://schemas.microsoft.com/office/'
      'drawing/2015/9/8/chartex" xmlns:mc="$_mcNs" '
      'xmlns:dgm="http://schemas.openxmlformats.org/drawingml/2006/diagram" '
      'xmlns:x3Unk="http://schemas.microsoft.com/office/drawing/2010/'
      'slicer" xmlns:sle15="http://schemas.microsoft.com/office/drawing/'
      '2012/slicer"/>';
  const String xf =
      'borderId="0" fillId="0" xfId="0" applyAlignment="1" applyFont="1"';
  const String align =
      '<alignment readingOrder="0" shrinkToFit="0" vertical="bottom" '
      'wrapText="0"/>';
  const String styles =
      '$_gsDecl<styleSheet xmlns="$_main" xmlns:x14ac="$_x14acNs" '
      'xmlns:mc="$_mcNs">'
      '<numFmts count="2">'
      '<numFmt numFmtId="164" formatCode="yyyy-mm-dd"/>'
      '<numFmt numFmtId="165" formatCode="m/d/yyyy h:mm:ss"/>'
      '</numFmts>'
      '<fonts count="2">'
      '<font><sz val="10.0"/><color rgb="FF000000"/><name val="Arial"/>'
      '<scheme val="minor"/></font>'
      '<font><b/><color theme="1"/><name val="Arial"/><scheme val="minor"/>'
      '</font>'
      '</fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="lightGray"/></fill></fills>'
      '<borders count="1"><border/></borders>'
      '<cellStyleXfs count="1"><xf borderId="0" fillId="0" fontId="0" '
      'numFmtId="0" applyAlignment="1" applyFont="1"/></cellStyleXfs>'
      '<cellXfs count="7">'
      '<xf $xf fontId="0" numFmtId="0">$align</xf>'
      '<xf $xf fontId="1" numFmtId="0">$align</xf>'
      '<xf $xf fontId="0" numFmtId="0">$align</xf>'
      '<xf $xf fontId="0" numFmtId="164" applyNumberFormat="1">$align</xf>'
      '<xf $xf fontId="0" numFmtId="165" applyNumberFormat="1">$align</xf>'
      '<xf $xf fontId="0" numFmtId="4" applyNumberFormat="1">$align</xf>'
      '<xf $xf fontId="0" numFmtId="0"><alignment readingOrder="0" '
      'shrinkToFit="0" vertical="top" wrapText="1"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle xfId="0" name="Normal" '
      'builtinId="0"/></cellStyles>'
      '<dxfs count="0"/>'
      '</styleSheet>';
  const String workbook =
      '$_gsDecl<workbook $_gsNamespaces>'
      '<workbookPr/>'
      '<sheets><sheet state="visible" name="Müşteriler" sheetId="1" '
      'r:id="rId4"/></sheets>'
      '<definedNames/><calcPr/>'
      '</workbook>';
  const String workbookRels =
      '$_gsDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="$_relNs/theme" '
      'Target="theme/theme1.xml"/>'
      '<Relationship Id="rId2" Type="$_relNs/styles" Target="styles.xml"/>'
      '<Relationship Id="rId3" Type="$_relNs/sharedStrings" '
      'Target="sharedStrings.xml"/>'
      '<Relationship Id="rId4" Type="$_relNs/worksheet" '
      'Target="worksheets/sheet1.xml"/>'
      '</Relationships>';
  const String theme =
      '$_gsDecl<a:theme xmlns:a="http://schemas.openxmlformats.org/'
      'drawingml/2006/main" name="Sheets"/>';
  const String rootRels =
      '$_gsDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="$_relNs/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';
  const String contentTypes =
      '$_gsDecl<Types xmlns="$_ctNs">'
      '<Default ContentType="application/xml" Extension="xml"/>'
      '<Default ContentType="$_ctRels" Extension="rels"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument'
      '.drawing+xml" PartName="/xl/drawings/drawing1.xml"/>'
      '<Override ContentType="$_ctSheet.worksheet+xml" '
      'PartName="/xl/worksheets/sheet1.xml"/>'
      '<Override ContentType="$_ctSheet.sharedStrings+xml" '
      'PartName="/xl/sharedStrings.xml"/>'
      '<Override ContentType="$_ctSheet.styles+xml" '
      'PartName="/xl/styles.xml"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument'
      '.theme+xml" PartName="/xl/theme/theme1.xml"/>'
      '<Override ContentType="$_ctSheet.sheet.main+xml" '
      'PartName="/xl/workbook.xml"/>'
      '</Types>';
  final Uint8List bytes = buildZipOrdered(<(String, List<int>)>[
    ('xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)),
    ('xl/drawings/drawing1.xml', utf8.encode(drawing)),
    ('xl/worksheets/sheet1.xml', utf8.encode(sheet)),
    ('xl/worksheets/_rels/sheet1.xml.rels', utf8.encode(sheetRels)),
    ('xl/theme/theme1.xml', utf8.encode(theme)),
    ('xl/sharedStrings.xml', utf8.encode(sst)),
    ('xl/styles.xml', utf8.encode(styles)),
    ('xl/workbook.xml', utf8.encode(workbook)),
    ('_rels/.rels', utf8.encode(rootRels)),
    ('[Content_Types].xml', utf8.encode(contentTypes)),
  ]);
  return ProducerFile('google_sheets', bytes, <ProducerSheet>[
    ProducerSheet('Müşteriler', <List<Object?>>[
      <Object?>[
        'Müşteri',
        'Telefon',
        'Vergi No',
        'Bakiye',
        'Kayıt Tarihi',
        'Son Giriş',
        'Not',
        'Etiket',
      ],
      <Object?>[
        'Ayşe Yılmaz',
        '+90 532 000 00 00',
        '0123456789',
        XlsxDecimal('-1250.5'),
        DateTime.utc(2026, 10, 28),
        DateTime.utc(2026, 10, 28, 13, 30),
        _longNote,
        'Ayşe Yılmaz / 0123456789',
      ],
      <Object?>[
        'Mehmet Öz',
        null,
        '0987654321',
        XlsxDecimal('3400.75'),
        DateTime.utc(2026, 10, 29),
        null,
        null,
        'Mehmet Öz / 0987654321',
      ],
    ]),
  ]);
}

/// The UTF-8 byte order mark and declaration the Open XML SDK writes
/// before every part (`encoding` in lower case).
const String _sdkDecl = '\uFEFF<?xml version="1.0" encoding="utf-8"?>';

/// A file in the style of an exporter built on the Open XML SDK for .NET.
///
/// Written from knowledge of the SDK's output, not copied from a file
/// (plan ruling 6): a byte order mark and `encoding="utf-8"` on every part,
/// the `x:` prefix on every SpreadsheetML element, `" />"` on empty
/// elements, generated relationship ids (`R` and hex digits), absolute
/// relationship targets and none of the parts an SDK program must add
/// itself (no styles, no shared strings, no `docProps`) are as the SDK
/// writes them. A `[Content_Types].xml` whose default type for `xml` is
/// generic, and entries in the order `System.IO.Packaging` writes them
/// (parts as created, relationships and content types last), are as it
/// writes them as far as known: the packaging layer may instead make the
/// first part's type the default for `xml`. The workbook override written as `/XL/Workbook.xml` for
/// the entry `xl/workbook.xml`, rows and cells without `r`, `t="n"` on
/// every number, an exponent and `t="d"` are what hand-written SDK code
/// commonly produces, as the R3 plan sets them. The `<x:dimension>` claims
/// `A1:Z99999` for 4 rows.
///
/// Expected: `1.5E-05` is `XlsxDecimal('0.000015')`, the ISO text is a UTC
/// `DateTime`, and no warning.
ProducerFile dotNetSdkFile() {
  const String x = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  String inline(String text) =>
      '<x:c t="inlineStr"><x:is><x:t>$text</x:t></x:is></x:c>';
  String number(String digits) => '<x:c t="n"><x:v>$digits</x:v></x:c>';
  final String sheet =
      '$_sdkDecl<x:worksheet xmlns:x="$x">'
      '<x:dimension ref="A1:Z99999" />'
      '<x:sheetData>'
      '<x:row>${inline('Kod')}${inline('Miktar')}${inline('Oran')}'
      '${inline('Aktif')}${inline('Tarih')}</x:row>'
      '<x:row>${inline('A-001')}${number('12')}${number('1.5E-05')}'
      '<x:c t="b"><x:v>1</x:v></x:c>'
      '<x:c t="d"><x:v>2026-10-28T13:45:00</x:v></x:c></x:row>'
      '<x:row>${inline('A-002')}${number('-3')}${number('0.25')}'
      '<x:c t="b"><x:v>0</x:v></x:c>'
      '<x:c t="d"><x:v>2026-10-29T00:00:00</x:v></x:c></x:row>'
      '<x:row>${inline('Toplam &amp; KDV')}${number('9')}</x:row>'
      '</x:sheetData>'
      '</x:worksheet>';
  const String workbook =
      '$_sdkDecl<x:workbook xmlns:r="$_relNs" xmlns:x="$x">'
      '<x:sheets><x:sheet name="Stok Hareketleri" sheetId="1" '
      'r:id="R3f2a9c1e" /></x:sheets>'
      '</x:workbook>';
  const String workbookRels =
      '$_sdkDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Type="$_relNs/worksheet" '
      'Target="/xl/worksheets/sheet1.xml" Id="R3f2a9c1e" />'
      '</Relationships>';
  const String rootRels =
      '$_sdkDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Type="$_relNs/officeDocument" '
      'Target="/xl/workbook.xml" Id="Rd4a7e2b90c5f4e18" />'
      '</Relationships>';
  const String contentTypes =
      '$_sdkDecl<Types xmlns="$_ctNs">'
      '<Default Extension="xml" ContentType="application/xml" />'
      '<Default Extension="rels" ContentType="$_ctRels" />'
      '<Override PartName="/XL/Workbook.xml" '
      'ContentType="$_ctSheet.sheet.main+xml" />'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="$_ctSheet.worksheet+xml" />'
      '</Types>';
  final Uint8List bytes = buildZipOrdered(<(String, List<int>)>[
    ('xl/workbook.xml', utf8.encode(workbook)),
    ('xl/worksheets/sheet1.xml', utf8.encode(sheet)),
    ('xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)),
    ('_rels/.rels', utf8.encode(rootRels)),
    ('[Content_Types].xml', utf8.encode(contentTypes)),
  ]);
  return ProducerFile('dotnet_sdk', bytes, <ProducerSheet>[
    ProducerSheet('Stok Hareketleri', <List<Object?>>[
      <Object?>['Kod', 'Miktar', 'Oran', 'Aktif', 'Tarih'],
      <Object?>[
        'A-001',
        XlsxDecimal('12'),
        XlsxDecimal('0.000015'),
        true,
        DateTime.utc(2026, 10, 28, 13, 45),
      ],
      <Object?>[
        'A-002',
        XlsxDecimal('-3'),
        XlsxDecimal('0.25'),
        false,
        DateTime.utc(2026, 10, 29),
      ],
      <Object?>['Toplam & KDV', XlsxDecimal('9')],
    ]),
  ]);
}

/// The declaration SheetJS writes, ended by CRLF.
const String _jsDecl =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n';

/// A file in the style of a minimal ERP export (a PHP library or SheetJS
/// with shared strings off).
///
/// Written from knowledge, not copied from a file (plan ruling 6): the
/// declaration ended by CRLF and text as `t="str"` without a formula are
/// how SheetJS writes; the 1904 date system, the sheet part outside `xl/`
/// reached through a relationship target with backslashes, no
/// `<dimension>`, a styles part of two `cellXfs` whose second is the
/// built-in date format 14, a number with trailing zeros (`4500.00`, as a
/// PHP exporter formats it) and a repeated `A3` are the cases the R3 plan
/// sets for exporters of this kind.
///
/// Expected: `date1904` true, serial 44861 is 2026-10-28, the later `A3`
/// wins, and one `cellDuplicated`.
ProducerFile erpExportFile() {
  String text(String ref, String value) =>
      '<c r="$ref" t="str"><v>$value</v></c>';
  final String sheet =
      '$_jsDecl<worksheet xmlns="$_main" xmlns:r="$_relNs">'
      '<sheetData>'
      '<row r="1">${text('A1', 'Fatura No')}${text('B1', 'Tarih')}'
      '${text('C1', 'Tutar')}${text('D1', 'Açıklama')}</row>'
      '<row r="2">${text('A2', 'FT-2026-0001')}'
      '<c r="B2" s="1"><v>44861</v></c><c r="C2"><v>4500.00</v></c>'
      '${text('D2', 'Ofis kirası &amp; aidat')}</row>'
      '<row r="3">${text('A3', 'FT-2026-0002')}'
      '${text('A3', 'FT-2026-0002/R')}'
      '<c r="B3" s="1"><v>44862</v></c><c r="C3"><v>-120.5</v></c>'
      '${text('D3', 'İade &lt;kısmi&gt;')}</row>'
      '</sheetData>'
      '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
      'header="0.3" footer="0.3"/>'
      '</worksheet>';
  const String styles =
      '$_jsDecl<styleSheet xmlns="$_main">'
      '<numFmts count="0"/>'
      '<fonts count="1"><font><sz val="12"/><color theme="1"/>'
      '<name val="Calibri"/><family val="2"/><scheme val="minor"/></font>'
      '</fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/>'
      '<diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
      'borderId="0"/></cellStyleXfs>'
      '<cellXfs count="2">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" '
      'applyNumberFormat="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" '
      'builtinId="0"/></cellStyles>'
      '</styleSheet>';
  const String workbook =
      '$_jsDecl<workbook xmlns="$_main" xmlns:r="$_relNs">'
      '<workbookPr date1904="true"/>'
      '<sheets><sheet name="Faturalar" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';
  const String workbookRels =
      '$_jsDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="$_relNs/worksheet" '
      r'Target="..\worksheets\data.xml"/>'
      '<Relationship Id="rId2" Type="$_relNs/styles" Target="styles.xml"/>'
      '</Relationships>';
  const String rootRels =
      '$_jsDecl<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="$_relNs/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';
  const String contentTypes =
      '$_jsDecl<Types xmlns="$_ctNs">'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="rels" ContentType="$_ctRels"/>'
      '<Override PartName="/xl/workbook.xml" '
      'ContentType="$_ctSheet.sheet.main+xml"/>'
      '<Override PartName="/worksheets/data.xml" '
      'ContentType="$_ctSheet.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="$_ctSheet.styles+xml"/>'
      '</Types>';
  final Uint8List bytes = buildZipOrdered(<(String, List<int>)>[
    ('[Content_Types].xml', utf8.encode(contentTypes)),
    ('_rels/.rels', utf8.encode(rootRels)),
    ('xl/workbook.xml', utf8.encode(workbook)),
    ('xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)),
    ('xl/styles.xml', utf8.encode(styles)),
    ('worksheets/data.xml', utf8.encode(sheet)),
  ]);
  return ProducerFile(
    'erp_export',
    bytes,
    <ProducerSheet>[
      ProducerSheet('Faturalar', <List<Object?>>[
        <Object?>['Fatura No', 'Tarih', 'Tutar', 'Açıklama'],
        <Object?>[
          'FT-2026-0001',
          DateTime.utc(2026, 10, 28),
          XlsxDecimal('4500.00'),
          'Ofis kirası & aidat',
        ],
        <Object?>[
          'FT-2026-0002/R',
          DateTime.utc(2026, 10, 29),
          XlsxDecimal('-120.5'),
          'İade <kısmi>',
        ],
      ]),
    ],
    warnings: const <XlsxWarningCode, int>{XlsxWarningCode.cellDuplicated: 1},
    date1904: true,
  );
}
