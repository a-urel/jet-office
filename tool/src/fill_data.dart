/// The fixed Turkish data `tool/fill_docx.dart` fills every document with, and
/// the T1 fixtures (`t1_values`, `t1_merge_fields`) are filled with.
///
/// Not ported from Quds; written for jet_office (decision 0024, T1). It uses
/// no `dart:io`, so the fixtures that import it run in a browser too.
library;

import 'package:jet_core/jet_core.dart';

/// The data of a fill: the values the T1 tags and merge fields name.
///
/// * `firma.unvan` and `firma.adres`, nested in the map `firma`;
/// * `tarih`, `DateTime(2026, 11, 14)`;
/// * `musteri.ad`, nested in the map `musteri`;
/// * `tutar`, `FormatDecimal('1234.56')`, and `miktar`, `FormatDecimal('2.5')`;
/// * the merge field keys `Ad`, `Müşteri Adı` and `Tarih`, whole names as a
///   `MERGEFIELD` looks them up (no dot paths).
///
/// A new map every call, so a caller may change it.
Map<String, Object?> fillDocxData() => <String, Object?>{
  'firma': <String, Object?>{
    'unvan': 'Acme A.Ş.',
    'adres': 'Atatürk Bulvarı No: 1, Çankaya / Ankara',
  },
  'tarih': DateTime(2026, 11, 14),
  'musteri': <String, Object?>{'ad': 'Ayşe Yılmaz'},
  'tutar': FormatDecimal('1234.56'),
  'miktar': FormatDecimal('2.5'),
  'Ad': 'Ayşe',
  'Müşteri Adı': 'ayşe yılmaz',
  'Tarih': DateTime(2026, 11, 14),
};

/// Whether [data] has a value at [name], a tag's path joined by `.` (each
/// segment a key of a nested map), as a `{{}}` tag looks it up.
bool dataHasPath(Map<String, Object?> data, String name) {
  Object? current = data;
  for (final String segment in name.split('.')) {
    if (current is! Map || !current.containsKey(segment)) return false;
    current = current[segment];
  }
  return true;
}
