// Tests tool/write_w6_check.dart: the files of the owner's W6 Excel check.
// It writes files, so it runs on the VM only. The two big workbooks are
// written with small row counts here.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_w6_check.dart';
import '../support/read_xlsx.dart';

void main() {
  late Directory temp;
  late List<String> written;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('w6_check');
    written = writeW6Check('${temp.path}/w6', smallRows: 50, largeRows: 100);
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  String path(String name) => '${temp.path}/w6/$name';

  String drawing(String name) {
    final Map<String, String> parts = readXlsx(
      File(path(name)).readAsBytesSync(),
    );
    return parts.entries
        .singleWhere(
          (MapEntry<String, String> e) => e.key.endsWith('drawing1.xml'),
        )
        .value;
  }

  test('writes the four workbooks and the final folder', () {
    final List<String> top = <String>[
      for (final String p in written)
        if (!p.contains('/final/')) p.split('/').last,
    ];
    expect(top, <String>[
      'w6_generated_100k.xlsx',
      'w6_generated_1m.xlsx',
      'w6_shapes.xlsx',
      'w6_wrapped.xlsx',
    ]);
    final List<String> finals = <String>[
      for (final String p in written)
        if (p.contains('/final/')) p,
    ];
    expect(finals, isNotEmpty);
    expect(
      finals.where(
        (String p) => p.endsWith('/final/owner/chart_reference.xlsx'),
      ),
      hasLength(1),
    );
    expect(
      finals.where((String p) => p.endsWith('/final/c1_kinds.xlsx')),
      hasLength(1),
    );
    expect(
      finals.where((String p) => p.endsWith('/final/w1_generated.xlsx')),
      hasLength(1),
    );
    expect(finals.where((String p) => p.contains('/final/owner/')), isNotEmpty);
  });

  test(
    'the owner files are written to final/owner, apart from the fixtures',
    () {
      final Set<String> fixtureNames = <String>{
        for (final String p in written)
          if (p.contains('/final/') && !p.contains('/final/owner/'))
            p.split('/').last,
      };
      expect(fixtureNames, contains('c1_kinds.xlsx'));
      expect(fixtureNames, isNot(contains('chart_reference.xlsx')));
    },
  );

  test("Excel's lock files in final/ are not listed as written", () {
    final Directory dir = Directory.systemTemp.createTempSync('w6_lock');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Excel leaves `~$<name>.xlsx` beside a workbook it has open.
    File('${dir.path}/w6/final/~\$m4_tables.xlsx')
      ..createSync(recursive: true)
      ..writeAsStringSync('lock');
    final List<String> paths = writeW6Check(
      '${dir.path}/w6',
      smallRows: 5,
      largeRows: 10,
    );
    expect(paths.where((String p) => p.contains(r'~$')), isEmpty);
    expect(
      paths.where((String p) => p.endsWith('/final/m4_tables.xlsx')),
      hasLength(1),
    );
  });

  test('every written workbook opens with the model', () {
    for (final String p in written) {
      expect(
        () => XlsxWorkbook.open(File(p).readAsBytesSync()),
        returnsNormally,
        reason: p,
      );
    }
  });

  test('the generated workbooks hold the requested rows', () {
    final XlsxWorkbook small = XlsxWorkbook.open(
      File(path('w6_generated_100k.xlsx')).readAsBytesSync(),
    );
    expect(small.sheets.single.cellAt(50, 0)?.value, 'C-50');
    final XlsxWorkbook large = XlsxWorkbook.open(
      File(path('w6_generated_1m.xlsx')).readAsBytesSync(),
    );
    expect(large.sheets.single.cellAt(100, 0)?.value, 'C-100');
  });

  test('w6_shapes: the textlinks moved with the edits', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      File(path('w6_shapes.xlsx')).readAsBytesSync(),
    );
    expect(book.sheets.map((XlsxSheet s) => s.name), <String>[
      'Veri',
      'S',
      'Veri 3',
    ]);
    final String xml = drawing('w6_shapes.xlsx');
    expect(xml, contains(r'textlink="$B$2"'));
    expect(xml, contains('''textlink="'Veri 3'!\$B\$3"'''));
    expect(xml, isNot(contains(r'textlink="$A$1"')));
    expect(xml, isNot(contains("'Veri 2'")));
  });

  test('w6_wrapped: Choice and Fallback anchors moved to C4:E7', () {
    final String xml = drawing('w6_wrapped.xlsx');
    expect(xml, contains('<mc:Choice'));
    expect(xml, contains('<mc:Fallback>'));
    const String from =
        '<xdr:from><xdr:col>2</xdr:col><xdr:colOff>0</xdr:colOff>'
        '<xdr:row>3</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>';
    const String to =
        '<xdr:to><xdr:col>5</xdr:col><xdr:colOff>0</xdr:colOff>'
        '<xdr:row>7</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>';
    expect(from.allMatches(xml), hasLength(2));
    expect(to.allMatches(xml), hasLength(2));
  });
}
