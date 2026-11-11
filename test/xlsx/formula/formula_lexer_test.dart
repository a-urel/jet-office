import 'package:jet_office/src/xlsx/formula/formula_lexer.dart';
import 'package:jet_office/src/xlsx/formula/formula_token.dart';
import 'package:test/test.dart';

typedef K = XlsxFormulaTokenKind;

/// The kinds and texts of [formula]'s tokens, as `kind:text` strings.
List<String> lexed(String formula) => <String>[
  for (final XlsxFormulaToken t in lexFormula(formula))
    '${t.kind.name}:${t.text}',
];

void expectJoins(String formula) {
  final List<XlsxFormulaToken> tokens = lexFormula(formula);
  expect(tokens.map((XlsxFormulaToken t) => t.text).join(), formula);
  int at = 0;
  for (final XlsxFormulaToken t in tokens) {
    expect(t.start, at, reason: 'offset of ${t.text} in $formula');
    expect(t.text, isNotEmpty, reason: formula);
    at = t.end;
  }
}

const List<String> fixedFormulas = <String>[
  // From the fixtures and producer files.
  '1/0',
  'A2&"-"&B2',
  'C2*1.2',
  'COUNTA(A2:A5)',
  'CONCATENATE(A2," / ",C2)',
  'Stock[[#This Row],[Qty]]*2',
  'SUM(A2:A9)',
  'Data!C5',
  'AND(TRUE,TRUE)',
  'IF(A2<0,"x&y",1)',
  'C2*(1+TaxRate)',
  'SUM(Sales[Amount])',
  'SUBTOTAL(109,Sales[Amount])',
  '"_x0041_"&"<"',
  'A1&"!"',
  // From Excel's documentation.
  'SUM(A1:A10)',
  'AVERAGE(B2:B5,C2:C5)',
  r'VLOOKUP(A2,Sheet2!$A$1:$C$100,3,FALSE)',
  'INDEX(A1:C10,MATCH(E1,A1:A10,0),2)',
  'IFERROR(A1/B1,"")',
  'SUMIFS(C:C,A:A,"East",B:B,">="&D1)',
  'COUNTIF(1:1,">0")',
  'SUM(\$3:\$5)',
  'SUM(Sheet1:Sheet3!B5)',
  "SUM('Q1 Sales'!A1:A3)",
  "'It''s'!A1+1",
  '[1]Sheet1!\$A\$1',
  "'[2]My Sheet'!B2",
  '[1]!Rate*2',
  '_xlfn.XLOOKUP(A1,B:B,C:C)',
  '_xlfn._xlws.FILTER(A2:C9,B2:B9>0)',
  '_xlfn.LET(_xlpm.x,2,_xlpm.x*3)',
  '_xlfn.LAMBDA(_xlpm.a,_xlpm.a+1)(5)',
  '{1,2,3;4,5,6}',
  'SUM({1;2;3})',
  '_xlfn.SORT(A2#)',
  '@A1:A10',
  '_xlfn.SINGLE(B:B)',
  'A1:A10 B5:C5',
  '(A1:B2,C3:D4)',
  '-A1^2',
  '10%',
  '1.5E+3*2',
  '.5+A1',
  'A1<>B1',
  'A1<=B1',
  'A1>=B1',
  '#REF!+1',
  'IF(ISERROR(A1),#N/A,A1)',
  'Sheet1!#REF!',
  'IFERROR(A1,#DIV/0!)',
  '#GETTING_DATA',
  'Table1[#All]',
  'Table1[[#Headers],[Col 1]:[Col 3]]',
  "Sales[['[Odd']]]",
  '[@Qty]*[@Price]',
  'TRUE()',
  'NOT(FALSE)',
  'A1 +\r\n B1',
  'XFD1048576+XFE1',
  'LOG10(100)',
  'Rate*\$B\$2',
  'SUM(Sheet1!A1:Sheet1!B2)',
  'TEXT(A1,"\$#,##0.00")',
  'IF(A1="","empty","""quoted""")',
];

void main() {
  test('every token kind lexes', () {
    final Map<String, List<String>> cases = <String, List<String>>{
      '1.5': <String>['number:1.5'],
      '"a""b"': <String>['string:"a""b"'],
      'TRUE': <String>['boolean:TRUE'],
      '#SPILL!': <String>['error:#SPILL!'],
      r'$A$1': <String>[r'cell:$A$1'],
      r'A1:$B2': <String>[r'area:A1:$B2'],
      r'3:$5': <String>[r'rowRange:3:$5'],
      r'B:$D': <String>[r'columnRange:B:$D'],
      "'My Sheet'!A1": <String>["sheetPrefix:'My Sheet'!", 'cell:A1'],
      'T[Qty]': <String>['structured:T[Qty]'],
      'Rate': <String>['name:Rate'],
      'SUM(1)': <String>[
        'function:SUM',
        'parenOpen:(',
        'number:1',
        'parenClose:)',
      ],
      '{1,2;3}': <String>[
        'arrayOpen:{',
        'number:1',
        'comma:,',
        'number:2',
        'semicolon:;',
        'number:3',
        'arrayClose:}',
      ],
      '1<>2': <String>['number:1', 'operator:<>', 'number:2'],
      'A1#': <String>['cell:A1', 'spill:#'],
      '@A1': <String>['implicitIntersection:@', 'cell:A1'],
      '1 \r\n+2': <String>[
        'number:1',
        'whitespace: \r\n',
        'operator:+',
        'number:2',
      ],
      '"open': <String>['invalid:"open'],
    };
    expect(K.values.toSet().length, K.values.length);
    final Set<String> seen = <String>{};
    cases.forEach((String formula, List<String> expected) {
      expect(lexed(formula), expected, reason: formula);
      for (final XlsxFormulaToken t in lexFormula(formula)) {
        seen.add(t.kind.name);
      }
    });
    expect(seen, K.values.map((K k) => k.name).toSet());
  });

  test('joined texts give the input back', () {
    expect(fixedFormulas.length, greaterThanOrEqualTo(60));
    for (final String f in fixedFormulas) {
      expectJoins(f);
      expect(
        lexFormula(f).where((XlsxFormulaToken t) => t.kind == K.invalid),
        isEmpty,
        reason: f,
      );
    }
    // Broken input joins back too.
    for (final String f in <String>[
      '',
      'A1;B1',
      "'unclosed",
      'T[[x]',
      '"x',
      '~`',
      "'a'B",
      '#',
      '[1',
      'Ürün*2',
    ]) {
      expectJoins(f);
    }
  });

  test("quoted sheet names with '' and spaces", () {
    expect(lexed("'O''Brien Q1'!\$A\$1:B2"), <String>[
      "sheetPrefix:'O''Brien Q1'!",
      r'area:$A$1:B2',
    ]);
    expect(lexed("'unclosed!A1"), <String>["invalid:'unclosed!A1"]);
  });

  test('3D and external prefixes', () {
    expect(lexed('Sheet1:Sheet3!B5'), <String>[
      'sheetPrefix:Sheet1:Sheet3!',
      'cell:B5',
    ]);
    expect(lexed("'Jan:Mar'!B5"), <String>[
      "sheetPrefix:'Jan:Mar'!",
      'cell:B5',
    ]);
    expect(lexed('[1]Sheet1!A1'), <String>[
      'sheetPrefix:[1]Sheet1!',
      'cell:A1',
    ]);
    expect(lexed('[1]!Rate'), <String>['sheetPrefix:[1]!', 'name:Rate']);
    expect(lexed("'[1]My Sheet'!A1"), <String>[
      "sheetPrefix:'[1]My Sheet'!",
      'cell:A1',
    ]);
    expect(lexed('Sheet1!A1:Sheet1!B2'), <String>[
      'sheetPrefix:Sheet1!',
      'cell:A1',
      'operator::',
      'sheetPrefix:Sheet1!',
      'cell:B2',
    ]);
  });

  test('structured refs with specials and escapes', () {
    expect(lexed("Sales[[#This Row],['[Odd']]]+1"), <String>[
      "structured:Sales[[#This Row],['[Odd']]]",
      'operator:+',
      'number:1',
    ]);
    expect(lexed('[@Qty]*[@Price]'), <String>[
      'structured:[@Qty]',
      'operator:*',
      'structured:[@Price]',
    ]);
    expect(lexed('T[[#Headers],[A]:[B]]'), <String>[
      'structured:T[[#Headers],[A]:[B]]',
    ]);
    expect(lexed('T[[x]'), <String>['invalid:T[[x]']);
  });

  test('XFD1048576 is a cell, XFE1 and A1048577 are names', () {
    expect(lexed('XFD1048576'), <String>['cell:XFD1048576']);
    expect(lexed('XFE1'), <String>['name:XFE1']);
    expect(lexed('A1048577'), <String>['name:A1048577']);
    expect(lexed('A1B'), <String>['name:A1B']);
    expect(lexed('A0'), <String>['name:A0']);
    expect(lexed('LOG10(1)').first, 'function:LOG10');
    expect(lexed('Rate:B2'), <String>['area:Rate:B2']);
  });

  test('_xlfn. and _xlws. functions', () {
    expect(lexed('_xlfn._xlws.FILTER(A:A,1)').take(2), <String>[
      'function:_xlfn._xlws.FILTER',
      'parenOpen:(',
    ]);
    expect(lexed('_xlfn.LET(_xlpm.x,1)'), <String>[
      'function:_xlfn.LET',
      'parenOpen:(',
      'name:_xlpm.x',
      'comma:,',
      'number:1',
      'parenClose:)',
    ]);
    expect(lexed('TRUE()').first, 'function:TRUE');
  });

  test('arrays with rows', () {
    expect(lexed('{1,"a";TRUE,#N/A}'), <String>[
      'arrayOpen:{',
      'number:1',
      'comma:,',
      'string:"a"',
      'semicolon:;',
      'boolean:TRUE',
      'comma:,',
      'error:#N/A',
      'arrayClose:}',
    ]);
    expect(lexed('A1;B1'), <String>['cell:A1', 'invalid:;', 'cell:B1']);
  });

  test('spill and @', () {
    expect(lexed('SUM(A2#)'), <String>[
      'function:SUM',
      'parenOpen:(',
      'cell:A2',
      'spill:#',
      'parenClose:)',
    ]);
    expect(lexed('Rate#'), <String>['name:Rate', 'spill:#']);
    expect(lexed('@Rate'), <String>['implicitIntersection:@', 'name:Rate']);
    expect(lexed('A1 #REF!'), <String>[
      'cell:A1',
      'whitespace: ',
      'error:#REF!',
    ]);
  });

  test('an unterminated string is one invalid tail', () {
    expect(lexed('A1&"abc+1)'), <String>[
      'cell:A1',
      'operator:&',
      'invalid:"abc+1)',
    ]);
  });

  test('a 100,000-character formula lexes in linear time', () {
    const String unit = "SUM('A b'!A1:B2,T[[#This Row],[x]],{1;2})+";
    final String formula = (unit * (100000 ~/ unit.length + 1)).substring(
      0,
      100000,
    );
    final Stopwatch watch = Stopwatch()..start();
    final List<XlsxFormulaToken> tokens = lexFormula(formula);
    watch.stop();
    expect(tokens.length, lessThanOrEqualTo(formula.length));
    expectJoins(formula);
    // Pathological input: one unclosed bracket and quote runs.
    final String worst = '[' * 50000 + "'" * 50000;
    final Stopwatch w2 = Stopwatch()..start();
    expectJoins(worst);
    w2.stop();
    printOnFailure('100,000 chars: ${watch.elapsedMilliseconds} ms');
    // ignore: avoid_print
    print(
      'lexFormula: 100,000 chars in ${watch.elapsedMilliseconds} ms '
      '(${tokens.length} tokens); worst case ${w2.elapsedMilliseconds} ms',
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(w2.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
