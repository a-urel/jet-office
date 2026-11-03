/// The default indexed colour palette of SpreadsheetML.
///
/// Not ported from Quds; written for jet_office.
library;

/// The 64 colours of the default palette (ECMA-376 Part 1, §18.8.27), as
/// ARGB values by index: what `<color indexed="N"/>` shows when the styles
/// part has no `<indexedColors>` (or lists fewer than N + 1 colours).
///
/// Entries 0 to 7 repeat entries 8 to 15. Indexes 64 and 65, the system
/// foreground and background, are not part of the palette.
const List<int> defaultIndexedColors = <int>[
  0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00, // 0-3
  0xFF0000FF, 0xFFFFFF00, 0xFFFF00FF, 0xFF00FFFF, // 4-7
  0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00, // 8-11
  0xFF0000FF, 0xFFFFFF00, 0xFFFF00FF, 0xFF00FFFF, // 12-15
  0xFF800000, 0xFF008000, 0xFF000080, 0xFF808000, // 16-19
  0xFF800080, 0xFF008080, 0xFFC0C0C0, 0xFF808080, // 20-23
  0xFF9999FF, 0xFF993366, 0xFFFFFFCC, 0xFFCCFFFF, // 24-27
  0xFF660066, 0xFFFF8080, 0xFF0066CC, 0xFFCCCCFF, // 28-31
  0xFF000080, 0xFFFF00FF, 0xFFFFFF00, 0xFF00FFFF, // 32-35
  0xFF800080, 0xFF800000, 0xFF008080, 0xFF0000FF, // 36-39
  0xFF00CCFF, 0xFFCCFFFF, 0xFFCCFFCC, 0xFFFFFF99, // 40-43
  0xFF99CCFF, 0xFFFF99CC, 0xFFCC99FF, 0xFFFFCC99, // 44-47
  0xFF3366FF, 0xFF33CCCC, 0xFF99CC00, 0xFFFFCC00, // 48-51
  0xFFFF9900, 0xFFFF6600, 0xFF666699, 0xFF969696, // 52-55
  0xFF003366, 0xFF339966, 0xFF003300, 0xFF333300, // 56-59
  0xFF993300, 0xFF993366, 0xFF333399, 0xFF333333, // 60-63
];
