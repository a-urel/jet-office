import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:test/test.dart';

void main() {
  test('the defaults are the documented numbers', () {
    const XlsxReadLimits limits = XlsxReadLimits();
    expect(limits.maxEntries, 10000);
    expect(limits.maxEntryBytes, 256 * 1024 * 1024);
    expect(limits.maxTotalBytes, 1024 * 1024 * 1024);
    expect(limits.maxCompressionRatio, 1000);
    expect(limits.maxSharedStrings, 2000000);
    expect(limits.maxDepth, 256);
    expect(limits.maxTextLength, 1048576);
    limits.check();
  });

  test('check() accepts 1 and names the field that is below 1', () {
    const XlsxReadLimits(maxEntries: 1).check();
    final Map<String, XlsxReadLimits> bad = <String, XlsxReadLimits>{
      'maxEntries': const XlsxReadLimits(maxEntries: 0),
      'maxEntryBytes': const XlsxReadLimits(maxEntryBytes: 0),
      'maxTotalBytes': const XlsxReadLimits(maxTotalBytes: -1),
      'maxCompressionRatio': const XlsxReadLimits(maxCompressionRatio: 0),
      'maxSharedStrings': const XlsxReadLimits(maxSharedStrings: 0),
      'maxDepth': const XlsxReadLimits(maxDepth: 0),
      'maxTextLength': const XlsxReadLimits(maxTextLength: 0),
    };
    for (final MapEntry<String, XlsxReadLimits> e in bad.entries) {
      expect(
        e.value.check,
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError a) => a.message.toString(),
            'message',
            contains(e.key),
          ),
        ),
        reason: e.key,
      );
    }
  });
}
