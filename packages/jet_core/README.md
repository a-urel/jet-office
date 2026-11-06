# jet_core

Pure-Dart building blocks shared by the jet_ packages. It has no dependencies,
knows no file format and runs on the web, desktop, mobile and server alike.

Today it holds one thing: the number format engine, extracted from
`jet_office`. It shows a value as Excel for Mac does: it applies a number
format code, in the region's separators, names and words, and gives back the
text with its parts and its colour. The engine is checked against Excel's own
output (`docs/number-format.md`).

```dart
final NumberFormatter formatter = NumberFormatter();
final FormattedValue shown = formatter.format(
  FormatDecimal('-1234.5'),
  numberFormat: '#,##0.00;(#,##0.00)',
);
print(shown.text); // (1,234.50)

final NumberFormatter german = NumberFormatter(locale: FormatLocale.deDE);
print(german.format(46323, numberFormat: 'dddd, d. mmmm yyyy').text);
// Mittwoch, 28. Oktober 2026
```

`format` takes a `FormatDecimal`, a `num`, a `DateTime`, a `Duration`, a
`String`, a `bool`, a `FormatErrorValue` or `null`. It never throws for any
format code; a code it cannot read shows the value as `General` and says so in
`FormattedValue.warning`.

Not published to pub.dev. Use it as a git dependency:

```yaml
dependencies:
  jet_core:
    git:
      url: https://github.com/a-urel/jet-office.git
      path: packages/jet_core
```

See `AGENTS.md` for the rules of the package and
`docs/decisions/0001-jet-core-holds-what-the-families-share.md` for why it
exists.
