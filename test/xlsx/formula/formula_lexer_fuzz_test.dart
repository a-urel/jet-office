import 'dart:convert';

import 'package:jet_office/src/xlsx/formula/formula_lexer.dart';
import 'package:jet_office/src/xlsx/formula/formula_token.dart';
import 'package:test/test.dart';

import '../../support/fuzz_mutations.dart';
import '../../support/timing.dart';

/// The seeds the quality gate fuzzes, each with [_cases] strings.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The strings per seed in the quality gate.
const int _cases = 1000;

/// Adler-32 of every string of [_seeds] and its token count, computed once
/// on the VM. The Chrome leg compares it, which proves a seed gives the same
/// strings, and the lexer the same tokens, in a browser.
const int _casesDigest = 2191313149;

/// What formulas are made of: reference, function, string, error, array,
/// structured reference and operator characters, a space, a non-ASCII
/// letter and a lone surrogate.
const String _alphabet = 'AZaz019\$!:;,.()[]{}"\'#@%&*+-/^<>= _?çİ\ud800';

/// Formulas as the fixtures, the producer files and Excel's documentation
/// write them, which the mutations start from.
const List<String> _formulas = <String>[
  '1/0',
  'A2&"-"&B2',
  'COUNTA(A2:A5)',
  'Stock[[#This Row],[Qty]]*2',
  'Data!C5',
  'IF(A2<0,"x&y",1)',
  'C2*(1+TaxRate)',
  'SUBTOTAL(109,Sales[Amount])',
  r'VLOOKUP(A2,Sheet2!$A$1:$C$100,3,FALSE)',
  'SUMIFS(C:C,A:A,"East",B:B,">="&D1)',
  r'SUM($3:$5)',
  'SUM(Sheet1:Sheet3!B5)',
  "SUM('Q1 Sales'!A1:A3)",
  "'It''s'!A1+1",
  r'[1]Sheet1!$A$1',
  '[1]!Rate*2',
  '_xlfn.LET(_xlpm.x,2,_xlpm.x*3)',
  '{1,2,3;4,5,6}',
  '_xlfn.SORT(A2#)',
  'A1:A10 B5:C5',
  '(A1:B2,C3:D4)',
  '1.5E+3*2',
  'Sheet1!#REF!',
  'Table1[[#Headers],[Col 1]:[Col 3]]',
  'Rate:B2',
  'LOG10(A1)+LOG10',
];

/// Adler-32 of [data], in arithmetic that stays exact in a browser.
int _adler32(List<int> data) {
  int a = 1;
  int b = 0;
  for (final int byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return b * 65536 + a;
}

/// The strings of [seed]: half random strings of up to 40 characters of
/// [_alphabet], half a formula of [_formulas] with one to three mutations
/// (a character inserted, a slice deleted or repeated, or a cut).
Iterable<String> _strings(int seed, int count) sync* {
  final Xorshift32 random = Xorshift32(seed);
  for (int i = 0; i < count; i++) {
    if (random.nextInt(2) == 0) {
      final int length = random.nextInt(41);
      yield String.fromCharCodes(<int>[
        for (int j = 0; j < length; j++)
          _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
      ]);
      continue;
    }
    String text = _formulas[random.nextInt(_formulas.length)];
    for (int m = random.nextInt(3); m >= 0; m--) {
      final int at = random.nextInt(text.length + 1);
      final int end = at + random.nextInt(text.length - at + 1);
      text = switch (random.nextInt(4)) {
        0 => text.replaceRange(
          at,
          at,
          _alphabet[random.nextInt(_alphabet.length)],
        ),
        1 => text.replaceRange(at, end, ''),
        2 => text.replaceRange(at, at, text.substring(at, end)),
        _ => text.substring(0, at),
      };
    }
    yield text;
  }
}

/// The problems of lexing [text]: a throw, tokens that do not join back to
/// it, a gap or an empty token, or more tokens than code units.
List<String> _problems(String text) {
  final List<XlsxFormulaToken> tokens;
  try {
    tokens = lexFormula(text);
  } on Object catch (e) {
    return <String>['${jsonEncode(text)} threw $e'];
  }
  final List<String> problems = <String>[];
  if (tokens.map((XlsxFormulaToken t) => t.text).join() != text) {
    problems.add('${jsonEncode(text)} does not join back');
  }
  if (tokens.length > text.length) {
    problems.add('${jsonEncode(text)} has ${tokens.length} tokens');
  }
  int at = 0;
  for (final XlsxFormulaToken t in tokens) {
    if (t.start != at || t.text.isEmpty) {
      problems.add('${jsonEncode(text)} has a gap or empty token at $at');
      break;
    }
    at = t.end;
  }
  return problems;
}

void main() {
  test('a seed gives the same strings and tokens everywhere', () {
    final StringBuffer all = StringBuffer();
    for (final int seed in _seeds) {
      for (final String text in _strings(seed, _cases)) {
        all.writeln('${jsonEncode(text)} ${lexFormula(text).length}');
      }
    }
    expect(_adler32(utf8.encode(all.toString())), _casesDigest);
  });

  test('the lexer never throws and its tokens join back to the input', () {
    final List<String> problems = <String>[
      for (final int seed in _seeds)
        for (final String text in _strings(seed, _cases)) ..._problems(text),
    ];
    expect(problems, isEmpty);
  });

  test('a formula past the length limit lexes in bounded time', () {
    final String long = List<String>.filled(3000, 'A1+').join();
    final Stopwatch watch = Stopwatch()..start();
    expect(_problems(long), isEmpty);
    // A run over the bound runs again, as a busy machine can slow one run;
    // only a lexer slow in every run fails.
    expect(
      confirmedHang(
        watch.elapsed,
        () => _problems(long),
        bound: const Duration(seconds: 2),
      ),
      isNull,
    );
  });
}
