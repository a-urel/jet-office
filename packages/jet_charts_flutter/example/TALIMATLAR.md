# Galeri: Excel ile yan yana karşılaştırma

Bu adımlar, `jet_charts_flutter`'ın çizdiği grafikleri Excel for Mac'in kendi
varsayılan grafikleriyle karşılaştırmak içindir. Aynı grafikler iki yerde
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

   Beklenen çıktı:
   `Wrote gallery.xlsx with 28 charts and 2 sparklines to build/excel_gallery.`
   (J3'teki 16 grafik ve J4'ün 14 yeni grafiği; J4 bölümü aşağıda.)

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
karşılaştır. İkisi de 360 x 216 nokta boyutundadır (J4'ün mini grafikleri
dışında). Bu bölüm J3'ün 16 grafiği içindir; yenileri için aşağıdaki J4
bölümüne bak. Şunlara bak:

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

Yedinci ve sekizinci serinin rengini Excel kendisi seçer (dosya bu iki seri için renk
yazmaz; her grafiğin yanına Excel'in kendi renk ve stil parçalarını,
`colorsN.xml` ve `styleN.xml`, yazar, Excel rengi oradaki renk döngüsünden
alır). İstersen bir de şunu yap: `column_eight_series` sayfasında `A1:I5`
hücrelerini seç, Ekle sekmesinden kümelenmiş sütun grafiği ekle ve 7. ve 8.
serinin rengine bak. Dosyayı kaydetme.

Çubuk grafiklerinde çubuklar arasındaki boşluk (gap width) henüz Excel'den
doğrulanmadı. `bar_clustered`, `column_stacked`, `column_percent` ve
`area_stacked` için istersen sayfanın verisinden Excel'in kendi grafiğini ekle
(renk adımındaki gibi) ve boşlukları karşılaştır.

## Ne gönderilecek

Her farkı bir satıra `ad: ne farklı` biçiminde yaz, örneğin
`bar_clustered: Excel'de çubuklar daha kalın`. Hiç fark yoksa `fark yok` yaz.
Ayrıca Excel'in tam sürümünü (Excel → Excel Hakkında) ve uygulamanın üst
satırının ne dediğini yaz. Dosyayı kaydetmeden kapat.

## J4 — B: yeni grafikler

Bu bölüm J4'ün 14 yeni grafiği içindir: pasta, halka, mini grafik
(sparkline), dağılım, birleşik grafik, ikincil eksen, düzgün çizgi ve yarı
saydam alan. Aynı `gallery.xlsx` ve aynı uygulama kullanılır; sayfalar ve
uygulamadaki grafikler J3'ün 16 grafiğinden sonra gelir.

Bu grafiklerde Excel'in kendi kaydettiği bir dosya henüz yok. Dosyadaki XML,
Excel'in Ekle menüsünün ne yazdığına dair tahminlerle yazıldı (dilim kenarı,
etiket yeri, işaretçiler, kılavuz çizgileri, ikincil eksen, mini grafik
renkleri); bunların hiçbiri kontrol edilmedi. Yani bu bölümde hem dosya hem
uygulama tahmindir. Excel'in kendi varsayılanlarını okumak için ayrı adımlar
`test/fixtures/owner/charts/TALIMATLAR_J4.md` dosyasında (E1). O dosya gelince
buradaki tahminler Excel'in yazdığı değerlerle değişir. Bu yüzden bu bölümde
bulduğun her fark değerlidir: ya uygulama ya dosya yanlıştır, belki ikisi de.
Hangisinin doğru olduğunu Excel'in kendi grafiği söyler (aşağıdaki
"Excel'in kendi grafiği" adımı).

Uygulamanın kendi tahminleri de kontrol edilmedi: ilk dilim saat 12'de başlar
ve saat yönünde gider; halka deliği %75'tir; dilim kenarı arka plan renginde
0,75 punttur; negatif dilim mutlak değeriyle çizilir; dağılımda yalnızca yatay
kılavuz çizgileri vardır; ikincil eksen sağdadır ve kılavuz çizgisi yoktur; iki
serili halkada ilk seri en içteki halkadır; mini grafik çizgisi 0,75 punttur.

### Hazırlık

1. Çalışma kitabını yaz ve doğrula (J3 bölümündeki gibi):

   ```bash
   dart run packages/jet_charts_flutter/example/tool/write_excel_gallery.dart build/excel_gallery
   dotnet run --project tool/ooxml_validate -- build/excel_gallery
   ```

   Beklenen çıktı:
   `Wrote gallery.xlsx with 28 charts and 2 sparklines to build/excel_gallery.`
   ve `1 file(s), no errors.`

2. Uygulamayı başlat:

   ```bash
   (cd packages/jet_charts_flutter/example && flutter run -d macos)
   ```

3. `gallery.xlsx` dosyasını Excel'de aç. Excel onarım önerirse kabul etme, dur
   ve iletiyi kelimesi kelimesine aynen yaz; özellikle `sparkline_line` ve
   `sparkline_area` sayfalarındaki `D2` hücresinin mini grafiği için (bu,
   dosyanın ilk kez yazdığı bir parçadır). Onarım iletisi, dosyayı yazan kodun
   hatasıdır. Yakınlaştırmayı %100 yap. İki pencereyi yan yana koy.

### Karşılaştırma

Her sayfanın adı uygulamadaki grafiğin adıdır. Grafikler 360 x 216 noktadır.
Her grafikte J3'teki genel noktalara (renkler, gösterge, başlık, yazı tipi,
çerçeve) bak. Ayrıca şunlara bak:

- `pie_basic`, `pie_small_slices`, `pie_negative` (pasta):
  - dilimlerin sırası ve ilk dilimin başladığı yer (saat 12 mi, saat yönünde
    mi);
  - dilim renkleri (`accent1`'den başlayarak);
  - dilim kenarı: rengi ve kalınlığı. Dosya da bir tahmin yazar (beyaz, 1,5
    punt; kontrol edilmedi), uygulama da kendi tahminini çizer (arka plan
    rengi, 0,75 punt; kontrol edilmedi); hangisinin Excel'in kendi grafiğine
    uyduğunu yaz;
  - veri etiketlerinin yeri; dosyada etiket yeri "En İyi Sığdırma"dır
    (kontrol edilmedi);
  - etiketlerin kılavuz çizgileri (leader lines); dosyada açıktır (kontrol
    edilmedi);
  - `pie_small_slices`: küçük dilimlerin etiketleri ve yüzdeler;
  - `pie_negative`: `-4` nasıl çizildi (mutlak değer mi, hiç mi); etiketi ne
    yazıyor.
- `donut_center`, `donut_two_series` (halka):
  - delik büyüklüğü. `donut_center`'da delik %55 (grafiğin kendi değeri),
    `donut_two_series`'te %75 (tahmin, kontrol edilmedi);
  - ilk dilimin yeri ve dilim kenarı, pastadaki gibi (kontrol edilmedi);
  - ortadaki metin (`Toplam 45`): Excel'de yoktur. Bunu karşılaştırma, geri
    kalanını karşılaştır;
  - `donut_center`'ın üçüncü dilimi bilerek kırmızıdır (`C0392B`);
    `donut_center`'da %10'dan küçük dilimlerin etiketi uygulamada gizlenir,
    Excel'de gizlenmez: bu fark beklenir;
  - `donut_two_series`: hangi seri içte, hangisi dışta.
- `sparkline_line`, `sparkline_area` (mini grafik): Excel'de grafik değil,
  `D2` hücresindeki mini grafiktir (Ekle > Mini Grafikler > Çizgi). Uygulamada
  120 x 40 noktadır; hücre de yaklaşık bu boyuttadır. Çizgi kalınlığına,
  rengine (dosyadaki renkler tahmin, kontrol edilmedi) ve en küçük değerin 0
  olmasına bak. Excel'de alan mini grafiği
  yoktur: `sparkline_area` Excel'de çizgidir, alan dolgusunu karşılaştırma.
- `scatter_basic`, `scatter_dates` (dağılım):
  - iki eksenin aralığı ve adımı;
  - kılavuz çizgileri: dosyada da uygulamada da yalnızca yatay (kontrol
    edilmedi);
  - işaretçiler; dosyada noktalar arasında çizgi yok (kontrol edilmedi);
  - `scatter_basic`: `North` ve `South` serisinin noktaları kendi x
    değerlerinde mi (her serinin x değerleri sayfada kendi sütunundadır);
  - `scatter_dates`: yatay eksendeki tarihlerin biçimi (`d mmm`, örneğin
    `1 Jan`).
- `combo_column_line`, `line_secondary` (ikincil eksen):
  - ikincil eksenin yeri (dosyada da uygulamada da sağda; kontrol edilmedi)
    ve aralığı;
  - ikincil eksende kılavuz çizgisi: dosyada da uygulamada da yok (kontrol
    edilmedi);
  - `combo_column_line`: çizgide işaretçi var mı. Dosyada yok, uygulamada
    var; ikisi de tahmin (kontrol edilmedi). Negatif sütun (`-4`);
  - `line_secondary`: ikincil eksenin başlığı (`Units`).
- `combo_area_column_line` (alan, sütun ve çizgi tek eksende): çizim sırası
  (alan arkada, çizgi önde), renkler ve çizgideki işaretçiler (dosyada yok,
  uygulamada var; kontrol edilmedi).
- `line_smooth` (düzgün çizgi): `Smooth` serisinin eğrisinin biçimi; tepe
  noktalarını aşıyor mu. `Straight` serisi düz kalmalı ve boşluğu (Çarşamba)
  korumalı.
- `area_translucent` (yarı saydam alan): Excel'in varsayılan alanı yarı saydam
  değildir; dosyada bu sayfa düz yığılmış alandır. Saydamlığı karşılaştırma;
  yalnızca eksenlere, renklere ve göstergeye bak.

### Excel'in kendi grafiği

J3'te çubuk boşlukları için yaptığın gibi, tahminleri Excel'in kendi
grafiğiyle karşılaştır. Her adımda yalnızca grafiği ekle, hiçbir ayarı
değiştirme. Menü adları Türkçe Excel'e göredir; yanında İngilizcesi var.

1. `pie_basic` sayfasında `A1:B5` hücrelerini seç. **Ekle > Grafik > Pasta**
   (Insert > Chart > Pie), ilk 2-B pasta. Sonra **Grafik Tasarımı > Grafik
   Öğesi Ekle > Veri Etiketleri > En İyi Sığdırma** (Add Chart Element > Data
   Labels > Best Fit).
2. `donut_two_series` sayfasında `A1:C5` hücrelerini seç. **Ekle > Grafik >
   Halka** (Doughnut).
3. `combo_column_line` sayfasında `A1:C5` hücrelerini seç. **Ekle > Grafik >
   Birleşik > Kümelenmiş Sütun - İkincil Eksende Çizgi** (Combo > Clustered
   Column - Line on Secondary Axis).

Her eklenen grafiği hem dosyadaki grafikle hem uygulamadakiyle karşılaştır:
dilim kenarının rengi ve kalınlığı, delik büyüklüğü, ilk dilimin yeri ve yönü,
etiketlerin yeri ve kılavuz çizgileri, ikincil eksenin yeri ve kılavuz
çizgileri, çizgideki işaretçiler. Her fark için hangisinin (dosya mı, uygulama
mı) Excel'in kendi grafiğinden ayrıldığını yaz, örneğin
`pie_basic: Excel'in kendi pastasında kenar beyaz ve kalın; uygulamada ince`.
Dosyayı kaydetme.

### Monépro görünümü

Uygulamanın üstündeki `Monépro look` düğmesi ayrı bir sayfa açar:
`donut_center`, `sparkline_area`, `line_smooth` ve `combo_column_line`, açık ve
koyu bir uygulama temasında. Excel'de karşılığı yoktur; yalnızca ekranda bak.
Sayfanın üst satırı `DM Sans` yazı tipinin bulunup bulunmadığını söyler (uygulama
bu yazı tipini içermez). Şunlara bak: yazılar okunuyor mu, koyu temada renkler
yeterince ayrışıyor mu, alan saydamlığı (`sparkline_area`) göze hoş geliyor mu,
üst üste binen bir şey var mı (`overlaps: 0` yazmalı).

### Ne gönderilecek

J3'teki gibi: her farkı bir satıra `ad: ne farklı` biçiminde yaz, örneğin
`pie_basic: Excel'de ilk dilim saat 3'te başlıyor`. Fark yoksa `fark yok`
yaz. Monépro sayfası için ayrı satırlar yaz, örneğin
`monepro donut_center (dark): etiketler zor okunuyor`. Excel'in tam sürümünü,
uygulamanın üst satırını ve Monépro sayfasının üst satırını da yaz. Dosyayı
kaydetmeden kapat. Sonuç, seninle birlikte
`packages/jet_charts_core/docs/excel-checks.md` dosyasına yazılır; E1 dosyası
gelince oradaki tahminler de düzeltilir.
