/// Pure-Dart building blocks shared by the jet_ packages.
///
/// jet_core knows no file format and has no dependencies. It holds what two
/// families of packages really use: today, the number format engine that
/// shows a value as Excel for Mac does. Values in, text out: nothing here
/// touches `dart:io`, `dart:ui`, `dart:html` or Flutter, so it runs on the
/// web, desktop, mobile and server alike.
///
/// The public API is exactly what this library exports; everything under
/// `lib/src/` is private.
library;

export 'src/format/builtin_formats.dart' show builtinNumberFormatCode;
export 'src/format/format_code.dart' show FormatColor;
export 'src/format/format_kind.dart' show FormatKind, classifyFormatCode;
export 'src/format/format_locale.dart' show FormatLocale;
export 'src/format/format_value.dart' show FormatDecimal, FormatErrorValue;
export 'src/format/formatted_value.dart'
    show
        FormatFill,
        FormatPadding,
        FormatPart,
        FormatText,
        FormatWarning,
        FormattedValue;
export 'src/format/formatter.dart' show NumberFormatter;
