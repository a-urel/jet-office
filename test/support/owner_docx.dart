/// Test helper: the manifest of the owner's Word files
/// (`test/fixtures/owner/docx/manifest.json`), its parser and the rules
/// for what the directory may hold.
///
/// Web-safe on purpose (no `dart:io`), so `test/fixtures/owner_docx_test.dart`
/// runs on Chrome too; `test/docx/owner_files_test.dart` (VM only) reads
/// the files. The format is documented in `test/fixtures/owner/README.md`.
/// In short, the manifest is a JSON list with one object per file:
///
/// ```json
/// [
///   {"file": "features.docx",
///    "producer": "Microsoft Word for Mac 16.114.1",
///    "confirmedBy": null}
/// ]
/// ```
///
/// `file` is a `.docx` name in the directory, `producer` the program,
/// version and platform that saved it, and `confirmedBy` either `null` (a
/// draft) or exactly `"owner"`. The expected text is `<stem>.expected.txt`
/// beside the file, drafted by `tool/draft_expected_docx.dart`.
library;

import 'dart:convert';

/// One file of the owner's manifest.
final class OwnerDocx {
  /// Creates an entry for [file].
  const OwnerDocx(this.file, this.producer, this.confirmedBy);

  /// The `.docx` file name.
  final String file;

  /// The program, version and platform that saved the file; may be empty
  /// in a draft.
  final String producer;

  /// `"owner"` once the owner has confirmed the expected text, else null.
  final String? confirmedBy;

  /// Whether the owner has confirmed the expected text.
  bool get confirmed => confirmedBy == 'owner';
}

/// The keys an entry may have; all three are required.
const Set<String> _keys = <String>{'file', 'producer', 'confirmedBy'};

/// The entries of the manifest [json].
///
/// Throws a [FormatException] that names the path of the first problem,
/// such as `[1].confirmedBy`: the manifest is not a list of objects, a key
/// is missing or unknown, `file` is not a plain `.docx` name, `producer`
/// is not a string or is empty in a confirmed entry, or `confirmedBy` is
/// neither null nor exactly `"owner"`.
List<OwnerDocx> parseOwnerDocxManifest(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! List<Object?>) {
    throw const FormatException('manifest.json: expected a list of objects');
  }
  final List<OwnerDocx> entries = <OwnerDocx>[];
  for (int i = 0; i < decoded.length; i++) {
    final Object? item = decoded[i];
    if (item is! Map<String, Object?>) {
      throw FormatException('manifest.json: [$i] is not an object');
    }
    for (final String key in item.keys) {
      if (!_keys.contains(key)) {
        throw FormatException('manifest.json: [$i].$key is not a known key');
      }
    }
    for (final String key in _keys) {
      if (!item.containsKey(key)) {
        throw FormatException('manifest.json: [$i].$key is missing');
      }
    }
    final Object? file = item['file'];
    if (file is! String ||
        !file.endsWith('.docx') ||
        file.length == 5 ||
        file.contains('/') ||
        file.contains(r'\')) {
      throw FormatException('manifest.json: [$i].file is not a .docx name');
    }
    final Object? confirmedBy = item['confirmedBy'];
    if (confirmedBy != null && confirmedBy != 'owner') {
      throw FormatException(
        'manifest.json: [$i].confirmedBy must be null or "owner"',
      );
    }
    final Object? producer = item['producer'];
    if (producer is! String || (confirmedBy != null && producer.isEmpty)) {
      throw FormatException(
        'manifest.json: [$i].producer must name the program that saved '
        'the file',
      );
    }
    entries.add(OwnerDocx(file, producer, confirmedBy as String?));
  }
  return entries;
}

/// Whether [name] is a Word lock file (`~$name.docx`), which Word for Mac
/// leaves beside an open document; `.gitignore` keeps it out of the
/// repository, and the directory rules ignore it.
bool isWordLockFile(String name) => name.startsWith(r'~$');

/// What is wrong with a directory holding [fileNames] for [manifest]:
/// a listed file that is missing or listed twice, a `.docx` not listed or
/// without its `.expected.txt`, an `.expected.txt` without its `.docx`,
/// and any other file but `manifest.json`. Word lock files are ignored.
List<String> ownerDocxDirectoryProblems(
  Iterable<String> fileNames,
  List<OwnerDocx> manifest,
) {
  const String textSuffix = '.expected.txt';
  final Set<String> files = <String>{
    for (final String name in fileNames)
      if (!isWordLockFile(name)) name,
  };
  final Set<String> listed = <String>{};
  final List<String> problems = <String>[];
  for (final OwnerDocx entry in manifest) {
    if (!files.contains(entry.file)) {
      problems.add('manifest.json: "${entry.file}" is not in the directory');
    } else if (!listed.add(entry.file)) {
      problems.add('manifest.json: "${entry.file}" is listed twice');
    }
  }
  for (final String name in files.toList()..sort()) {
    if (name == 'manifest.json') continue;
    if (name.endsWith('.docx')) {
      if (!listed.contains(name)) problems.add('$name is not in manifest.json');
      final String text = '${name.substring(0, name.length - 5)}$textSuffix';
      if (!files.contains(text)) problems.add('$name has no $text');
    } else if (name.endsWith(textSuffix)) {
      final String docx =
          '${name.substring(0, name.length - textSuffix.length)}.docx';
      if (!files.contains(docx)) problems.add('$name has no $docx');
    } else {
      problems.add('$name does not belong here');
    }
  }
  return problems;
}
