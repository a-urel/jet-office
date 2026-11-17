/// The fixed Turkish data `tool/fill_docx.dart` fills every document with, and
/// the T1 and T2 fixtures (`t1_values`, `t1_merge_fields`, `t2_values`,
/// `t2_empty`, `t2_nested`) are filled with.
///
/// Not ported from Quds; written for jet_office (decision 0024, T1 and T2). It uses
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
///   `MERGEFIELD` looks them up (no dot paths);
/// * for T2's sections: `kalemler`, three invoice lines of `aciklama`,
///   `miktar` and `tutar` (the root `tutar` is their total); `odendi`,
///   `true`; `notlar`, two notes; `iskonto`, `false`; and `gruplar`, two
///   groups of a `baslik`, an `acil` flag and their own `kalemler` of `ad`
///   and `tutar`.
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
  'kalemler': <Object?>[
    <String, Object?>{
      'aciklama': 'Danışmanlık',
      'miktar': FormatDecimal('2.5'),
      'tutar': FormatDecimal('1000'),
    },
    <String, Object?>{
      'aciklama': 'Yazılım lisansı',
      'miktar': FormatDecimal('1.5'),
      'tutar': FormatDecimal('234.56'),
    },
    <String, Object?>{
      'aciklama': 'Kurulum',
      'miktar': FormatDecimal('0.75'),
      'tutar': FormatDecimal('0'),
    },
  ],
  'odendi': true,
  'notlar': <Object?>['Teslim 30 gün içindedir.', 'Fiyatlara KDV dahildir.'],
  'iskonto': false,
  'gruplar': <Object?>[
    <String, Object?>{
      'baslik': 'Donanım',
      'acil': true,
      'kalemler': <Object?>[
        <String, Object?>{'ad': 'Klavye', 'tutar': FormatDecimal('450')},
      ],
    },
    <String, Object?>{
      'baslik': 'Hizmet',
      'acil': false,
      'kalemler': <Object?>[
        <String, Object?>{'ad': 'Kurulum', 'tutar': FormatDecimal('300')},
        <String, Object?>{'ad': 'Eğitim', 'tutar': FormatDecimal('1250.5')},
      ],
    },
  ],
};

/// [fillDocxData] with no lines, unpaid, no notes and the discount shown:
/// `kalemler` and `notlar` empty, `odendi` `false`, `iskonto` `true`.
Map<String, Object?> fillDocxEmptyData() => fillDocxData()
  ..['kalemler'] = <Object?>[]
  ..['odendi'] = false
  ..['notlar'] = <Object?>[]
  ..['iskonto'] = true;

/// [fillDocxData] with [count] lines `Kalem 1` to `Kalem <count>`, each of
/// `miktar` 1.5 and `tutar` 10.25, `odendi` [paid], and the root `tutar` their
/// exact total, computed in whole hundredths.
Map<String, Object?> fillDocxLines(int count, {required bool paid}) {
  final int hundredths = 1025 * count;
  final String total =
      '${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}';
  return fillDocxData()
    ..['kalemler'] = <Object?>[
      for (int i = 1; i <= count; i++)
        <String, Object?>{
          'aciklama': 'Kalem $i',
          'miktar': FormatDecimal('1.5'),
          'tutar': FormatDecimal('10.25'),
        },
    ]
    ..['odendi'] = paid
    ..['tutar'] = FormatDecimal(total);
}

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
