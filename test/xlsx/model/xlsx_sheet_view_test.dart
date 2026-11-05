import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

XlsxWorkbook _open(String before, {String after = '', String root = ''}) =>
    XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S':
            '<worksheet xmlns="$mainNs"$root>$before'
            '<sheetData/>$after</worksheet>',
      }),
    );

String _xml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

String _element(String xml, String name) =>
    RegExp('<$name[^>]*/>|<$name[ >].*?</$name>').firstMatch(xml)?.group(0) ??
    '';

List<XlsxWarning> _invalid(XlsxWorkbook book) => <XlsxWarning>[
  for (final XlsxWarning w in book.warnings)
    if (w.code == XlsxWarningCode.layoutInvalid) w,
];

/// The `sheetViews` and `sheetPr` the writer writes for a sheet set up by
/// [setUp].
({String views, String pr}) _written(void Function(XlsxSheetWriter) setUp) {
  final XlsxWriter writer = XlsxWriter();
  setUp(writer.addSheet('S'));
  final String xml = partText(writer.close().bytes, 'xl/worksheets/sheet1.xml');
  return (views: _element(xml, 'sheetViews'), pr: _element(xml, 'sheetPr'));
}

const String _frozen =
    '<sheetViews><sheetView tabSelected="1" topLeftCell="B2" '
    'workbookViewId="0"><pane xSplit="1" ySplit="1" topLeftCell="B2" '
    'activePane="bottomRight" state="frozen"/>'
    '<selection pane="topRight" activeCell="B1" sqref="B1"/>'
    '<selection pane="bottomLeft" activeCell="A2" sqref="A2"/>'
    '<selection pane="bottomRight" activeCell="B2" sqref="B2"/>'
    '</sheetView></sheetViews>';

void main() {
  test('view reads m2_views', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      allFixtures().firstWhere((Fixture f) => f.name == 'm2_views').build(),
    );
    XlsxSheet sheet(String name) =>
        book.sheets.firstWhere((XlsxSheet s) => s.name == name);
    expect(
      sheet('Frozen').view,
      const XlsxSheetView(pane: XlsxPane.frozen(rows: 1, columns: 1)),
    );
    expect(
      sheet('Split').view,
      const XlsxSheetView(pane: XlsxPane.split(x: 120, y: 60)),
    );
    expect(
      sheet('View').view,
      const XlsxSheetView(
        zoom: 85,
        showGridLines: false,
        showHeadings: false,
        showZeros: false,
      ),
    );
    expect(sheet('RTL').view, const XlsxSheetView(rightToLeft: true));
    expect(sheet('Outline').view, const XlsxSheetView());
    expect(sheet('View').tabColor, const XlsxColor.rgb(0xFF0000));
    expect(sheet('Frozen').tabColor, isNull);
    expect(sheet('Outline').outlineSummary, (below: false, right: true));
    expect(sheet('Frozen').outlineSummary, (below: true, right: true));
    expect(book.warnings, isEmpty);
  });

  test('a sheet without sheetViews has the default view', () {
    final XlsxSheet sheet = _open('').sheets.single;
    expect(sheet.view, const XlsxSheetView());
    expect(sheet.tabColor, isNull);
    expect(sheet.outlineSummary, (below: true, right: true));
  });

  test('view reads showFormulas, a frozenSplit and a twips split', () {
    final XlsxSheet frozen = _open(
      '<sheetViews><sheetView showFormulas="1" zoomScale="250">'
      '<pane ySplit="3" state="frozenSplit"/></sheetView></sheetViews>',
    ).sheets.single;
    expect(
      frozen.view,
      const XlsxSheetView(
        showFormulas: true,
        zoom: 250,
        pane: XlsxPane.frozen(rows: 3),
      ),
    );
    final XlsxSheet split = _open(
      '<sheetViews><sheetView><pane xSplit="2400" ySplit="1200.5" '
      'activePane="bottomRight"/></sheetView></sheetViews>',
    ).sheets.single;
    expect(split.view.pane, const XlsxPane.split(x: 120, y: 60.025));
    // A pane that splits nothing is no pane.
    expect(
      _open(
        '<sheetViews><sheetView><pane state="frozen"/>'
        '</sheetView></sheetViews>',
      ).sheets.single.view.pane,
      isNull,
    );
  });

  test('setting a view writes what the writer writes', () {
    final List<XlsxSheetView> views = <XlsxSheetView>[
      const XlsxSheetView(),
      const XlsxSheetView(zoom: 85, showGridLines: false),
      const XlsxSheetView(
        showHeadings: false,
        rightToLeft: true,
        showZeros: false,
        showFormulas: true,
        zoom: 400,
      ),
      const XlsxSheetView(pane: XlsxPane.frozen(rows: 2, columns: 3)),
      const XlsxSheetView(pane: XlsxPane.frozen(rows: 1)),
      const XlsxSheetView(pane: XlsxPane.frozen(columns: 4)),
      const XlsxSheetView(pane: XlsxPane.split(x: 120, y: 60)),
      const XlsxSheetView(pane: XlsxPane.split(y: 37.5)),
    ];
    for (final XlsxSheetView view in views) {
      final String expected = _written((XlsxSheetWriter s) {
        s.view(view);
      }).views;
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.view = view;
      expect(sheet.view, view, reason: '$view');
      final String xml = _xml(book);
      expect(_element(xml, 'sheetViews'), expected, reason: '$view');
      expect(xml.indexOf('<sheetViews'), lessThan(xml.indexOf('<sheetData')));
    }
  });

  test('removing a pane drops the selections that name its parts', () {
    final XlsxWorkbook book = _open(_frozen);
    final XlsxSheet sheet = book.sheets.single;
    expect(
      sheet.view,
      const XlsxSheetView(pane: XlsxPane.frozen(rows: 1, columns: 1)),
    );
    sheet.view = const XlsxSheetView();
    final String views = _element(_xml(book), 'sheetViews');
    expect(
      views,
      '<sheetViews><sheetView tabSelected="1" topLeftCell="B2" '
      'workbookViewId="0"/></sheetViews>',
    );
    expect(views, isNot(contains('selection')));
  });

  test('a frozen sheet with a bottomLeft selection and no pane', () {
    final XlsxWorkbook book = _open(
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" '
      'state="frozen"/>'
      '<selection pane="bottomLeft" activeCell="A3" sqref="A3"/>'
      '</sheetView></sheetViews>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.view = const XlsxSheetView();
    final String views = _element(_xml(book), 'sheetViews');
    expect(views, isNot(contains('bottomLeft')));
    expect(views, isNot(contains('<pane')));
  });

  test('changing a pane keeps the selections of parts that remain', () {
    final XlsxWorkbook book = _open(_frozen);
    final XlsxSheet sheet = book.sheets.single;
    // Rows only: topRight and bottomRight are gone, bottomLeft stays.
    sheet.view = const XlsxSheetView(pane: XlsxPane.frozen(rows: 4));
    expect(
      _element(_xml(book), 'sheetViews'),
      '<sheetViews><sheetView tabSelected="1" topLeftCell="B2" '
      'workbookViewId="0"><pane ySplit="4" topLeftCell="A5" '
      'activePane="bottomLeft" state="frozen"/>'
      '<selection pane="bottomLeft" activeCell="A2" sqref="A2"/>'
      '</sheetView></sheetViews>',
    );
    expect(sheet.view.pane, const XlsxPane.frozen(rows: 4));
  });

  test('a new pane gets a selection of its active part', () {
    final XlsxWorkbook book = _open(
      '<sheetViews><sheetView workbookViewId="0">'
      '<selection activeCell="C3" sqref="C3"/>'
      '</sheetView></sheetViews>',
    );
    book.sheets.single.view = const XlsxSheetView(
      pane: XlsxPane.frozen(columns: 2),
    );
    expect(
      _element(_xml(book), 'sheetViews'),
      '<sheetViews><sheetView workbookViewId="0"><pane xSplit="2" '
      'topLeftCell="C1" activePane="topRight" state="frozen"/>'
      '<selection activeCell="C3" sqref="C3"/>'
      '<selection pane="topRight"/></sheetView></sheetViews>',
    );
  });

  test('an equal view keeps the element as written', () {
    final XlsxWorkbook book = _open(_frozen);
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.view.zoom, 100);
    final String before = _xml(book);
    sheet.view = const XlsxSheetView(
      pane: XlsxPane.frozen(rows: 1, columns: 1),
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_xml(book), before);
    expect(_element(before, 'sheetViews'), _frozen);
  });

  test('a view change edits the attributes and keeps the rest', () {
    final XlsxWorkbook book = _open(_frozen);
    final XlsxSheet sheet = book.sheets.single;
    sheet.view = const XlsxSheetView(
      zoom: 70,
      showGridLines: false,
      pane: XlsxPane.frozen(rows: 1, columns: 1),
    );
    expect(
      _element(_xml(book), 'sheetViews'),
      _frozen.replaceFirst(
        'workbookViewId="0">',
        'showGridLines="0" zoomScale="70" workbookViewId="0">',
      ),
    );
    sheet.view = const XlsxSheetView(
      pane: XlsxPane.frozen(rows: 1, columns: 1),
    );
    expect(_element(_xml(book), 'sheetViews'), _frozen);
  });

  test('a view is undone and redone with the change log', () {
    final XlsxWorkbook book = _open(_frozen);
    final XlsxSheet sheet = book.sheets.single;
    final ChangeLog log = changeLogOf(book);
    final ChangeSet set = log.transaction(() {
      sheet.view = const XlsxSheetView(zoom: 150);
    });
    expect(sheet.view, const XlsxSheetView(zoom: 150));
    log.revertSet(set);
    expect(_element(_xml(book), 'sheetViews'), _frozen);
    expect(sheet.view.pane, const XlsxPane.frozen(rows: 1, columns: 1));
    log.reapplySet(set);
    expect(sheet.view, const XlsxSheetView(zoom: 150));
  });

  test('a zoom of 500 throws ArgumentError named zoom; nothing changes', () {
    final XlsxWorkbook book = _open(_frozen);
    final XlsxSheet sheet = book.sheets.single;
    final String before = _xml(book);
    expect(
      () => sheet.view = const XlsxSheetView(zoom: 500),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'zoom',
        ),
      ),
    );
    expect(
      () => sheet.view = const XlsxSheetView(pane: XlsxPane.frozen(rows: -1)),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'rows',
        ),
      ),
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_xml(book), before);
  });

  test('unreadable view attributes read as defaults and warn once', () {
    final XlsxWorkbook book = _open(
      '<sheetViews><sheetView zoomScale="500" showZeros="maybe">'
      '<pane xSplit="abc" state="frozen"/></sheetView></sheetViews>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.view, const XlsxSheetView());
    expect(sheet.view, const XlsxSheetView());
    expect(_invalid(book), hasLength(3));
    final String before = _xml(book);
    // Equal to what it reads as: kept as written.
    sheet.view = const XlsxSheetView();
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_xml(book), before);
    // Setting the field replaces it.
    sheet.view = const XlsxSheetView(zoom: 120);
    expect(_element(_xml(book), 'sheetView'), contains('zoomScale="120"'));
  });

  test('a sheetViews without a sheetView gets one; others are kept', () {
    final XlsxWorkbook book = _open('<sheetViews><extLst/></sheetViews>');
    book.sheets.single.view = const XlsxSheetView(zoom: 90);
    expect(
      _element(_xml(book), 'sheetViews'),
      '<sheetViews><sheetView zoomScale="90" workbookViewId="0"/>'
      '<extLst/></sheetViews>',
    );
  });

  test('sheetPr and sheetViews go in schema position', () {
    final XlsxWorkbook book = _open(
      '<dimension ref="A1"/><sheetFormatPr defaultRowHeight="15"/>',
      after:
          '<pageMargins left="1" right="1" top="1" bottom="1" '
          'header="0" footer="0"/>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.view = const XlsxSheetView(zoom: 90);
    sheet.tabColor = const XlsxColor.rgb(0x010203);
    final String xml = _xml(book);
    final List<String> order = <String>[
      '<sheetPr',
      '<dimension',
      '<sheetViews',
      '<sheetFormatPr',
      '<sheetData',
      '<pageMargins',
    ];
    final List<int> at = <int>[for (final String t in order) xml.indexOf(t)];
    expect(at, everyElement(isNonNegative));
    expect(at, orderedEquals(<int>[...at]..sort()));
  });

  test('prefixed elements keep their prefix', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': '<x:worksheet xmlns:x="$mainNs"><x:sheetData/></x:worksheet>',
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.view = const XlsxSheetView(zoom: 90, pane: XlsxPane.frozen(rows: 1));
    sheet.tabColor = const XlsxColor.rgb(0x00FF00);
    final String xml = _xml(book);
    expect(
      xml,
      contains('<x:sheetPr><x:tabColor rgb="FF00FF00"/></x:sheetPr>'),
    );
    expect(xml, contains('<x:sheetView zoomScale="90" workbookViewId="0">'));
    expect(xml, contains('<x:pane ySplit="1"'));
    final XlsxSheet reopened = XlsxWorkbook.open(
      book.save().bytes,
    ).sheets.single;
    expect(reopened.view.zoom, 90);
    expect(reopened.view.pane, const XlsxPane.frozen(rows: 1));
    expect(reopened.tabColor, const XlsxColor.rgb(0x00FF00));
  });

  test('tab colour and outline summary read and set', () {
    final ({String views, String pr}) expected = _written((XlsxSheetWriter s) {
      s
        ..tabColor(const XlsxColor.theme(4, tint: -0.25))
        ..outlineSummary(below: false, right: false);
    });
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S');
    sheet.tabColor = const XlsxColor.theme(4, tint: -0.25);
    sheet.setOutlineSummary(below: false, right: false);
    expect(sheet.tabColor, const XlsxColor.theme(4, tint: -0.25));
    expect(sheet.outlineSummary, (below: false, right: false));
    final String xml = _xml(book);
    expect(_element(xml, 'sheetPr'), expected.pr);
    expect(xml.indexOf('<sheetPr'), lessThan(xml.indexOf('<sheetData')));

    sheet.setOutlineSummary(right: false);
    expect(sheet.outlineSummary, (below: true, right: false));
    expect(
      _element(_xml(book), 'sheetPr'),
      '<sheetPr><tabColor theme="4" tint="-0.25"/>'
      '<outlinePr summaryRight="0"/></sheetPr>',
    );
    sheet.tabColor = const XlsxColor.indexed(10);
    expect(
      _element(_xml(book), 'sheetPr'),
      '<sheetPr><tabColor indexed="10"/><outlinePr summaryRight="0"/>'
      '</sheetPr>',
    );
    sheet.tabColor = null;
    expect(sheet.tabColor, isNull);
    expect(
      _element(_xml(book), 'sheetPr'),
      '<sheetPr><outlinePr summaryRight="0"/></sheetPr>',
    );
    sheet.setOutlineSummary();
    // An empty sheetPr goes.
    expect(_xml(book), isNot(contains('sheetPr')));
  });

  test('sheetPr keeps its attributes and other children', () {
    final XlsxWorkbook book = _open(
      '<sheetPr codeName="Sheet1"><pageSetUpPr fitToPage="1"/></sheetPr>',
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.tabColor = const XlsxColor.rgb(0xFF0000);
    sheet.setOutlineSummary(below: false);
    expect(
      _element(_xml(book), 'sheetPr'),
      '<sheetPr codeName="Sheet1"><tabColor rgb="FFFF0000"/>'
      '<outlinePr summaryBelow="0"/><pageSetUpPr fitToPage="1"/></sheetPr>',
    );
    sheet.tabColor = null;
    sheet.setOutlineSummary();
    expect(
      _element(_xml(book), 'sheetPr'),
      '<sheetPr codeName="Sheet1"><pageSetUpPr fitToPage="1"/></sheetPr>',
    );
  });

  test('an equal tab colour or outline summary keeps the element', () {
    const String pr =
        '<sheetPr><tabColor rgb="ff0000"/><outlinePr summaryBelow="false" '
        'applyStyles="1"/></sheetPr>';
    final XlsxWorkbook book = _open(pr);
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.tabColor, const XlsxColor.rgb(0xFF0000));
    expect(sheet.outlineSummary, (below: false, right: true));
    sheet.tabColor = const XlsxColor.rgb(0xFF0000);
    sheet.setOutlineSummary(below: false);
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_element(_xml(book), 'sheetPr'), pr);
    // Other outlinePr attributes survive an edit.
    sheet.setOutlineSummary();
    expect(
      _element(_xml(book), 'sheetPr'),
      '<sheetPr><tabColor rgb="ff0000"/><outlinePr applyStyles="1"/>'
      '</sheetPr>',
    );
  });

  test('a bad tab colour throws; an unreadable one reads as none', () {
    final XlsxWorkbook book = _open(
      '<sheetPr><tabColor theme="99"/></sheetPr>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.tabColor, isNull);
    expect(_invalid(book), hasLength(1));
    expect(
      () => sheet.tabColor = const XlsxColor.theme(12),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'tabColor',
        ),
      ),
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    sheet.tabColor = const XlsxColor.rgb(0x112233);
    expect(
      _element(_xml(book), 'sheetPr'),
      '<sheetPr><tabColor rgb="FF112233"/></sheetPr>',
    );
  });

  test('tab colour and view edits undo independently', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('S');
    final ChangeLog log = changeLogOf(book);
    final ChangeSet first = log.transaction(() {
      sheet.tabColor = const XlsxColor.rgb(0xFF0000);
    });
    final ChangeSet second = log.transaction(() {
      sheet.view = const XlsxSheetView(zoom: 80);
    });
    log.revertSet(first);
    expect(sheet.tabColor, isNull);
    expect(sheet.view.zoom, 80);
    log.revertSet(second);
    expect(sheet.view, const XlsxSheetView());
    expect(_xml(book), isNot(contains('zoomScale')));
    expect(_xml(book), isNot(contains('tabColor')));
    log.reapplySet(first);
    log.reapplySet(second);
    expect(sheet.tabColor, const XlsxColor.rgb(0xFF0000));
    expect(sheet.view.zoom, 80);
  });

  test('the tabSelected hook reads and sets the first sheet view', () {
    final XlsxWorkbook book = _open(_frozen);
    final XlsxSheet sheet = book.sheets.single;
    final ChangeLog log = changeLogOf(book);
    expect(sheetTabSelected(sheet), isTrue);
    log.transaction(() => setSheetTabSelected(sheet, true));
    expect(log.hasChanges, isFalse);
    log.transaction(() => setSheetTabSelected(sheet, false));
    expect(sheetTabSelected(sheet), isFalse);
    expect(
      _element(_xml(book), 'sheetView'),
      _element(_frozen, 'sheetView').replaceFirst(' tabSelected="1"', ''),
    );
    log.transaction(() => setSheetTabSelected(sheet, true));
    expect(_element(_xml(book), 'sheetView'), contains('tabSelected="1"'));
    // The view itself did not change.
    expect(sheet.view.pane, const XlsxPane.frozen(rows: 1, columns: 1));

    final XlsxWorkbook bare = _open('');
    final XlsxSheet none = bare.sheets.single;
    final ChangeLog bareLog = changeLogOf(bare);
    bareLog.transaction(() => setSheetTabSelected(none, false));
    expect(bareLog.hasChanges, isFalse);
    bareLog.transaction(() => setSheetTabSelected(none, true));
    expect(
      _element(_xml(bare), 'sheetViews'),
      '<sheetViews><sheetView tabSelected="1" workbookViewId="0"/>'
      '</sheetViews>',
    );
    expect(sheetTabSelected(none), isTrue);
  });

  test('tabColor = null removes a colour that cannot be read', () {
    final XlsxWorkbook book = _open(
      '<sheetPr codeName="A"><tabColor theme="99"/></sheetPr>',
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.tabColor, isNull);
    sheet.tabColor = null;
    expect(_element(_xml(book), 'sheetPr'), '<sheetPr codeName="A"/>');
    // With nothing left the sheetPr goes too, and no colour stays a no-op.
    final XlsxWorkbook only = _open(
      '<sheetPr><tabColor theme="99"/></sheetPr>',
    );
    only.sheets.single.tabColor = null;
    expect(_xml(only), isNot(contains('sheetPr')));
    final XlsxWorkbook none = _open('<sheetPr codeName="A"/>');
    final ChangeSet set = changeLogOf(none).transaction(() {
      none.sheets.single.tabColor = null;
    });
    expect(set.isEmpty, isTrue);
  });
}
