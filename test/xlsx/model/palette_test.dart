import 'package:jet_office/src/xlsx/model/palette.dart';
import 'package:test/test.dart';

void main() {
  test('the default palette', () {
    expect(defaultIndexedColors, hasLength(64));
    expect(defaultIndexedColors[8], 0xFF000000);
    expect(defaultIndexedColors[10], 0xFFFF0000);
    expect(defaultIndexedColors[22], 0xFFC0C0C0);
    expect(defaultIndexedColors[63], 0xFF333333);
    for (var i = 0; i < 8; i++) {
      expect(
        defaultIndexedColors[i],
        defaultIndexedColors[i + 8],
        reason: '$i',
      );
    }
    for (final int c in defaultIndexedColors) {
      expect(c >>> 24, 0xFF);
    }
  });
}
