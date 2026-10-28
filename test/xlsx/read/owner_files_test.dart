/// Reads the real Excel and Google Sheets files the owner supplied
/// (`test/fixtures/owner/`) and compares them with the owner's confirmed
/// expected values. The format is in `test/support/owner_expected.dart` and
/// `test/fixtures/owner/README.md`; decision 0007 and the R3 plan, ruling
/// 12, say why. VM only: it reads files from disk.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../support/owner_expected.dart';

const String _dir = 'test/fixtures/owner';

void main() {
  final Directory dir = Directory(_dir);
  final List<String> names = <String>[
    for (final FileSystemEntity e in dir.listSync())
      if (e is File) e.uri.pathSegments.last,
  ];
  final Object? decoded = jsonDecode(
    File('$_dir/manifest.json').readAsStringSync(),
  );
  final List<String> manifest = decoded is List<Object?>
      ? <String>[
          for (final Object? e in decoded)
            if (e is String) e,
        ]
      : <String>[];

  test('manifest.json is a list of file names', () {
    expect(decoded, isA<List<Object?>>());
    expect((decoded! as List<Object?>).every((Object? e) => e is String), true);
  });

  test('every .xlsx and .expected.json is listed and has its partner', () {
    expect(ownerDirectoryProblems(names, manifest), isEmpty);
  });

  if (manifest.isEmpty) {
    test('no owner files yet', () {
      // ignore: avoid_print
      print('owner files pending');
    });
  }

  for (final String name in manifest) {
    test('$name reads as the owner confirmed', () {
      final String json = '${name.substring(0, name.length - 5)}.expected.json';
      final OwnerExpected expected = parseOwnerExpected(
        File('$_dir/$json').readAsStringSync(),
      );
      expect(ownerConfirmationProblems(expected, name), isEmpty);
      final Uint8List bytes = File('$_dir/$name').readAsBytesSync();
      final XlsxReader reader = XlsxReader(bytes);
      final List<String> mismatches = compareOwnerFile(expected, reader);
      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    });
  }
}
