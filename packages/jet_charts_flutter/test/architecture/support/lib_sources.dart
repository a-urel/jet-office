/// Reads the package's `lib/` sources for the architecture guards.
library;

import 'dart:io';

/// A Dart file under `lib/`.
final class LibSource {
  /// A source at [path] (relative to the package root, `/`-separated) whose
  /// file content is [text].
  const LibSource(this.path, this.text);

  /// The path relative to the package root, such as
  /// `lib/src/theme/chart_theme.dart`.
  final String path;

  /// The file content as written.
  final String text;

  /// [text] without lines that are only a `//` comment, dartdoc included, so
  /// a doc comment that names a forbidden URI or tag does not trip a guard.
  String get code => text
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

/// Every `.dart` file under the package's `lib/`, sorted by path.
///
/// Throws a [StateError] when the tests do not run from the package root or
/// `lib/` holds no Dart file, so a guard can never pass by scanning nothing.
List<LibSource> libSources() {
  final File pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync() ||
      !RegExp(
        r'^name: jet_charts_flutter$',
        multiLine: true,
      ).hasMatch(pubspec.readAsStringSync())) {
    throw StateError(
      'Run the architecture tests from the jet_charts_flutter package root.',
    );
  }
  final Directory lib = Directory('lib');
  final List<LibSource> sources = <LibSource>[
    if (lib.existsSync())
      for (final FileSystemEntity entity in lib.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          LibSource(
            entity.path.replaceAll(r'\', '/'),
            entity.readAsStringSync(),
          ),
  ]..sort((LibSource a, LibSource b) => a.path.compareTo(b.path));
  if (sources.isEmpty) {
    throw StateError('No Dart files under lib/, so there is nothing to guard.');
  }
  return sources;
}

/// Every URI that an `import` or `export` directive of [source] names,
/// conditional ones included, in source order.
///
/// Comment lines are left out ([LibSource.code]), so a URI in dartdoc is not
/// a directive.
List<String> directiveUris(LibSource source) {
  final List<String> uris = <String>[];
  final RegExp directive = RegExp(
    r'^\s*(?:import|export)\b[^;]*;',
    multiLine: true,
  );
  final RegExp quoted = RegExp(r'''['"]([^'"]+)['"]''');
  for (final RegExpMatch match in directive.allMatches(source.code)) {
    for (final RegExpMatch uri in quoted.allMatches(match.group(0)!)) {
      uris.add(uri.group(1)!);
    }
  }
  return uris;
}
