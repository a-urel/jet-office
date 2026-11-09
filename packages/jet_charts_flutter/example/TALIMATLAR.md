# Galeri: Excel ile yan yana karşılaştırma

Bu adımlar, `jet_charts_flutter`'ın çizdiği grafikleri Excel for Mac'in kendi
varsayılan grafikleriyle karşılaştırmak içindir. Aynı 16 grafik iki yerde
var: uygulamada (`JetChart` ile çizilmiş) ve `gallery.xlsx` dosyasında
(Excel'in kendi grafiği olarak). Amaç, Excel'den ayrılan yerleri bulmak.
Yalnızca senin karşılaştırman sonuç sayılır. Sonuç, seninle birlikte
`packages/jet_charts_core/docs/excel-checks.md` dosyasına yazılır.

Komutların hepsi deponun kök klasöründen çalışır.

## Hazırlık

1. Çalışma kitabını yaz:

   ```bash
   dart run packages/jet_charts_flutter/example/tool/write_excel_gallery.dart build/excel_gallery
   ```

   Beklenen çıktı: `Wrote gallery.xlsx with 16 charts to build/excel_gallery.`

   Depo `.claude` altındaysa Excel dosyayı oradan açamayabilir. O zaman dışarı
   kopyala ve kopyayı aç:

   ```bash
   mkdir -p ~/Documents/jet_charts_oracle
   cp build/excel_gallery/gallery.xlsx ~/Documents/jet_charts_oracle/
   ```

2. Uygulamayı başlat:

   ```bash
   (cd packages/jet_charts_flutter/example && flutter run -d macos)
   ```

   Uygulamanın üstündeki satır, `Aptos Narrow` yazı tipinin bulunup
   bulunmadığını söyler. Excel'in dili Türkçeyse sağ üstteki `Türkçe (tr-TR)`
   anahtarını aç; sayılar Excel'deki gibi yazılır.

3. `gallery.xlsx` dosyasını Excel'de aç. Excel onarım önerirse kabul etme, dur
   ve iletiyi aynen yaz: bu, dosyayı yazan kodun hatasıdır. Yakınlaştırmayı
   %100 yap. İki pencereyi yan yana koy.

## Karşılaştırma

Her sayfanın adı, uygulamadaki bir grafiğin adıdır (`column_clustered`,
`bar_clustered` gibi). Her sayfadaki grafiği uygulamadaki aynı adlı grafikle
karşılaştır. İkisi de 360 x 216 nokta boyutundadır. Şunlara bak:

- eksen aralığı ve çizgileri (en küçük, en büyük değer, aradaki adım);
- etiketlerin metni ve sayı biçimi (`turkish_amounts`'ta `₺`);
- renkler; özellikle `column_eight_series`'in 7. ve 8. serisi;
- göstergenin (legend) yeri;
- başlık;
- çubuklar arasındaki boşluk;
- çizgi kalınlığı ve işaretçiler (`line_gap`);
- grafik çerçevesi;
- yazı tipleri. Uygulama `Aptos Narrow` bulunamadı diyorsa yazı tipi farkları
  sayılmaz.

Şunlar sayılmaz: fareyle üstüne gelince çıkan kutu, uygulamadaki hareket
(animasyon), Excel'in seçim çerçeveleri ve tutamaçları.

Bilinen bir fark: `one_series`'te uygulama göstergeyi gösterir. Excel'in tek
serili varsayılan grafiği göstermez; bu dosyada gösterge açıkça yazıldığı için
Excel de gösterir. Bu farkı not etmen gerekmez.

7. ve 8. serinin rengini Excel kendisi seçer (dosya bu iki seri için renk
yazmaz). İstersen bir de şunu yap: `column_eight_series` sayfasında `A1:I5`
hücrelerini seç, Ekle sekmesinden kümelenmiş sütun grafiği ekle ve 7. ve 8.
serinin rengine bak. Dosyayı kaydetme.

## Ne gönderilecek

Her farkı bir satıra `ad: ne farklı` biçiminde yaz, örneğin
`bar_clustered: Excel'de çubuklar daha kalın`. Hiç fark yoksa `fark yok` yaz.
Ayrıca Excel'in tam sürümünü (Excel → Excel Hakkında) ve uygulamanın üst
satırının ne dediğini yaz. Dosyayı kaydetmeden kapat.
