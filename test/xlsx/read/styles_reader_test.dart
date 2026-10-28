import 'package:jet_office/src/xlsx/read/format_kind.dart';
import 'package:jet_office/src/xlsx/read/package_reader.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/read/styles_reader.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';

const String _part = 'xl/styles.xml';

StyleTable _read(String xml, {XlsxReadLimits limits = const XlsxReadLimits()}) {
  final PackageReader p = PackageReader(
    buildWorkbook(<String, String?>{}, styles: xml),
    limits,
  );
  return readStyles(p, _part, limits);
}

String _sheet(String body) => '<styleSheet xmlns="$mainNs">$body</styleSheet>';

String _xfs(List<int?> ids) =>
    '<cellXfs count="${ids.length}">'
    '${ids.map((int? i) => i == null ? '<xf/>' : '<xf numFmtId="$i"/>').join()}'
    '</cellXfs>';

XlsxReadException _failure(void Function() body) {
  try {
    body();
  } on XlsxReadException catch (e) {
    return e;
  }
  throw StateError('expected an XlsxReadException');
}

void main() {
  test('Quds defect: 164 is not a built-in', () {
    final StyleTable t = _read(_sheet(_xfs(<int?>[164])));
    expect(t.formatOf('0').id, 164);
    expect(t.formatOf('0').code, isNull);
    expect(t.formatOf('0').kind, FormatKind.number);
    expect(t.formatOf('0').invalid, isFalse);
  });

  test('reads custom codes and kinds', () {
    final StyleTable t = _read(
      _sheet(
        '<numFmts count="3">'
        '<numFmt numFmtId="164" formatCode="dd.mm.yyyy"/>'
        '<numFmt numFmtId="165" formatCode="[h]:mm"/>'
        '<numFmt numFmtId="166" formatCode="0.000"/></numFmts>'
        '${_xfs(<int?>[0, 164, 165, 166])}',
      ),
    );
    expect(t.formatOf('0').code, 'General');
    expect(t.formatOf('0').kind, FormatKind.number);
    expect(t.formatOf('1').code, 'dd.mm.yyyy');
    expect(t.formatOf('1').kind, FormatKind.date);
    expect(t.formatOf('2').code, '[h]:mm');
    expect(t.formatOf('2').kind, FormatKind.time);
    expect(t.formatOf('3').code, '0.000');
    expect(t.formatOf('3').kind, FormatKind.number);
  });

  test('built-ins from the invariant table', () {
    final StyleTable t = _read(_sheet(_xfs(<int?>[14, 22, 49, 27, 50])));
    expect(t.formatOf('0').code, 'mm-dd-yy');
    expect(t.formatOf('0').kind, FormatKind.date);
    expect(t.formatOf('1').code, 'm/d/yy h:mm');
    expect(t.formatOf('2').code, '@');
    expect(t.formatOf('3').code, isNull);
    expect(t.formatOf('4').code, isNull);
  });

  test("the file's code wins for a built-in id", () {
    final StyleTable t = _read(
      _sheet(
        '<numFmts count="1"><numFmt numFmtId="14" formatCode="0.0"/></numFmts>'
        '${_xfs(<int?>[14])}',
      ),
    );
    expect(t.formatOf('0').code, '0.0');
    expect(t.formatOf('0').kind, FormatKind.number);
  });

  test('a later numFmt with the same id wins, bad ones are ignored', () {
    final StyleTable t = _read(
      _sheet(
        '<numFmts count="4">'
        '<numFmt numFmtId="164" formatCode="0.0"/>'
        '<numFmt numFmtId="164" formatCode="yyyy"/>'
        '<numFmt numFmtId="x" formatCode="yyyy"/>'
        '<numFmt numFmtId="165"/></numFmts>'
        '${_xfs(<int?>[164, 165])}',
      ),
    );
    expect(t.formatOf('0').code, 'yyyy');
    expect(t.formatOf('1').code, isNull);
  });

  test('formatCode is XML-string decoded', () {
    final StyleTable t = _read(
      _sheet(
        '<numFmts count="1"><numFmt numFmtId="164" '
        'formatCode="_x0079_yyy"/></numFmts>${_xfs(<int?>[164])}',
      ),
    );
    expect(t.formatOf('0').code, 'yyyy');
    expect(t.formatOf('0').kind, FormatKind.date);
  });

  test('cellStyleXfs do not count', () {
    final StyleTable t = _read(
      _sheet(
        '<cellStyleXfs count="2"><xf numFmtId="14"/><xf numFmtId="14"/>'
        '</cellStyleXfs>${_xfs(<int?>[49])}',
      ),
    );
    expect(t.formatOf('0').id, 49);
    expect(t.formatOf('1').invalid, isTrue);
  });

  test('formatOf', () {
    final StyleTable t = _read(_sheet(_xfs(<int?>[null, 14, 49])));
    expect(t.formatOf(null), same(CellFormat.general));
    expect(t.formatOf('0').id, 0);
    expect(t.formatOf('0').invalid, isFalse);
    expect(t.formatOf('2').id, 49);
    for (final String s in <String>[
      '99',
      '-1',
      'x',
      '0000000001',
      '1234567890',
    ]) {
      expect(t.formatOf(s), same(CellFormat.broken), reason: s);
    }
  });

  test('an empty table', () {
    expect(StyleTable.empty.formatOf('0'), same(CellFormat.general));
    expect(StyleTable.empty.formatOf('1'), same(CellFormat.broken));
    expect(StyleTable.empty.formatOf(null), same(CellFormat.general));
  });

  test('an unparseable xf numFmtId is broken', () {
    final StyleTable t = _read(
      _sheet(
        '<cellXfs count="2"><xf numFmtId="abc"/><xf numFmtId="14"/></cellXfs>',
      ),
    );
    expect(t.formatOf('0'), same(CellFormat.broken));
    expect(t.formatOf('1').id, 14);
  });

  test('prefixed elements read, foreign ones skipped', () {
    final StyleTable t = _read(
      '<s:styleSheet xmlns:s="$mainNs" xmlns:x="urn:other">'
      '<x:cellXfs><x:xf numFmtId="14"/></x:cellXfs>'
      '<s:numFmts><s:numFmt numFmtId="164" formatCode="yyyy"/>'
      '<x:numFmt numFmtId="165" formatCode="yyyy"/></s:numFmts>'
      '<s:cellXfs><s:xf numFmtId="164"><x:xf numFmtId="14"/></s:xf>'
      '<x:xf numFmtId="14"/><s:xf numFmtId="165"/></s:cellXfs>'
      '</s:styleSheet>',
    );
    expect(t.formatOf('0').code, 'yyyy');
    expect(t.formatOf('1').id, 165);
    expect(t.formatOf('1').code, isNull);
    expect(t.formatOf('2').invalid, isTrue);
  });

  test('a Strict root is unsupportedFormat', () {
    final XlsxReadException e = _failure(
      () => _read(
        '<styleSheet xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main"/>',
      ),
    );
    expect(e.reason, XlsxReadFailure.unsupportedFormat);
    expect(e.part, _part);
  });

  test('a non-styleSheet root is an empty table', () {
    final StyleTable t = _read(
      '<other xmlns="$mainNs">${_xfs(<int?>[14])}</other>',
    );
    expect(t.formatOf('0'), same(CellFormat.general));
    expect(t.formatOf('1'), same(CellFormat.broken));
  });

  test('maxCellFormats', () {
    const XlsxReadLimits limits = XlsxReadLimits(maxCellFormats: 2);
    _read(_sheet(_xfs(<int?>[1, 2])), limits: limits);
    final XlsxReadException xf = _failure(
      () => _read(_sheet(_xfs(<int?>[1, 2, 3])), limits: limits),
    );
    expect(xf.reason, XlsxReadFailure.limitExceeded);
    expect(xf.message, contains('maxCellFormats'));
    final XlsxReadException fmt = _failure(
      () => _read(
        _sheet(
          '<numFmts><numFmt numFmtId="164" formatCode="0"/>'
          '<numFmt numFmtId="165" formatCode="0"/>'
          '<numFmt numFmtId="166" formatCode="0"/></numFmts>',
        ),
        limits: limits,
      ),
    );
    expect(fmt.reason, XlsxReadFailure.limitExceeded);
    expect(fmt.message, contains('maxCellFormats'));
  });

  test('formatCode longer than maxTextLength is limitExceeded', () {
    const XlsxReadLimits limits = XlsxReadLimits(maxTextLength: 4);
    final StyleTable ok = _read(
      _sheet(
        '<numFmts><numFmt numFmtId="164" formatCode="yyyy"/></numFmts>'
        '${_xfs(<int?>[164])}',
      ),
      limits: limits,
    );
    expect(ok.formatOf('0').code, 'yyyy');
    final XlsxReadException e = _failure(
      () => _read(
        _sheet(
          '<numFmts><numFmt numFmtId="164" formatCode="yyyyy"/></numFmts>',
        ),
        limits: limits,
      ),
    );
    expect(e.reason, XlsxReadFailure.limitExceeded);
    expect(e.message, contains('maxTextLength'));
  });

  test('shares one CellFormat per id', () {
    final StyleTable t = _read(_sheet(_xfs(<int?>[14, 14, 49])));
    expect(t.formatOf('0'), same(t.formatOf('1')));
    expect(t.formatOf('0'), isNot(same(t.formatOf('2'))));
  });

  test('only the first cellXfs and numFmts are read', () {
    const XlsxReadLimits limits = XlsxReadLimits(maxCellFormats: 2);
    final StyleTable xfs = _read(
      _sheet('${_xfs(<int?>[14, 49])}${_xfs(<int?>[22, 22])}'),
      limits: limits,
    );
    expect(xfs.formatOf('1').id, 49);
    expect(xfs.formatOf('2'), same(CellFormat.broken));
    final StyleTable fmts = _read(
      _sheet(
        '<numFmts><numFmt numFmtId="164" formatCode="yyyy"/>'
        '<numFmt numFmtId="165" formatCode="yyyy"/></numFmts>'
        '<numFmts><numFmt numFmtId="166" formatCode="yyyy"/>'
        '<numFmt numFmtId="167" formatCode="yyyy"/></numFmts>'
        '${_xfs(<int?>[164, 166])}',
      ),
      limits: limits,
    );
    expect(fmts.formatOf('0').code, 'yyyy');
    expect(fmts.formatOf('1').code, isNull);
  });

  test('ids of more than 9 digits are invalid on every platform', () {
    final StyleTable t = _read(
      _sheet(
        '<numFmts><numFmt numFmtId="99999999999999999999" '
        'formatCode="yyyy"/><numFmt numFmtId="0000000164" '
        'formatCode="yyyy"/></numFmts>'
        '<cellXfs><xf numFmtId="99999999999999999999"/>'
        '<xf numFmtId="0000000164"/><xf numFmtId="1234567890"/></cellXfs>',
      ),
    );
    expect(t.formatOf('0'), same(CellFormat.broken));
    expect(t.formatOf('1').id, 164);
    expect(t.formatOf('1').code, 'yyyy');
    expect(t.formatOf('2'), same(CellFormat.broken));
  });

  test('cellXfs before numFmts still resolves codes', () {
    final StyleTable t = _read(
      _sheet(
        '${_xfs(<int?>[164])}'
        '<numFmts><numFmt numFmtId="164" formatCode="yyyy"/></numFmts>',
      ),
    );
    expect(t.formatOf('0').kind, FormatKind.date);
  });
}
