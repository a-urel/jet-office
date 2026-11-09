# Grafik referansı J4: pasta, halka, dağılım, birleşik grafik

Bu adımlar, Excel for Mac'in J4'ün yeni grafiklerini nasıl yazdığını görmek
içindir: pasta, halka, dağılım (XY), ikincil eksenli birleşik grafik ve
düzgünleştirilmiş çizgi. Dosyadan okunan değerler (halka deliğinin büyüklüğü,
ilk dilimin açısı, dilim kenarı, negatif değerin nasıl çizildiği, ikincil
eksenin yeri) `jet_charts`'ın Office temasına yazılır. O zamana kadar bu
değerler tahmindir ve belgelerde "kontrol edilmedi" diye geçer. Yalnızca senin
çalıştırman sonuç sayılır; hiçbir sonuç uydurulmaz. Menü adlarını Türkçe
Excel'e göre yazdım; bir ad farklıysa yanındaki İngilizce adına bak.

## 1. Çalışma kitabı

1. Excel'de yeni boş bir çalışma kitabı aç.
2. İlk sayfanın adını `Veri` yap (sayfa sekmesine çift tıkla).
3. Hücrelere şunları yaz. A1 boş kalsın. `-4` bilerek negatif.

   |   | A     | B     | C     |
   |---|-------|-------|-------|
   | 1 |       | Satış | Adet  |
   | 2 | Kuzey | 12    | 120   |
   | 3 | Güney | 18    | 95    |
   | 4 | Doğu  | -4    | 140   |
   | 5 | Batı  | 9     | 80    |

## 2. Grafikler

Her grafik için önce istenen aralığı seç, sonra **Ekle > Grafik** menüsünden
(Insert > Chart) istenen türü ekle. Yalnızca adı geçen şeyi değiştir; başka
hiçbir ayara dokunma. Grafikleri aynı sayfaya, üst üste gelmeyecek biçimde
yerleştir. Sırayı koru, numaralar sıradır.

1. `A1:B5` seçili: **Pasta** (Pie), ilk 2-B pasta.
2. `A1:B5` seçili: **Halka** (Doughnut).
3. `A1:C5` seçili: **Halka** (iki seri, iki halka).
4. `B2:C5` seçili: **Dağılım** (X Y Scatter), yalnızca işaretçili ilk tür.
5. `A1:C5` seçili: **Birleşik** (Combo) menüsünden **Kümelenmiş Sütun - İkincil
   Eksende Çizgi** (Clustered Column - Line on Secondary Axis).
6. `A1:A5` seç, Cmd tuşunu basılı tutup `C1:C5` seç: **İşaretçili Çizgi**
   (Line with Markers). Sonra çizgiye çift tıkla; sağdaki **Veri Serisini
   Biçimlendir** bölmesinde, boya kovası simgesinin altında, **Düzgünleştirilmiş
   çizgi** (Smoothed line) kutusunu işaretle.
7. `A1:B5` seçili: yine **Pasta**. Grafiği seç, **Grafik Tasarımı > Grafik Öğesi
   Ekle > Veri Etiketleri > En İyi Sığdırma** (Add Chart Element > Data Labels >
   Best Fit). Başka bir şey değiştirme.

## 3. Kaydet ve gönder

1. **Dosya > Farklı Kaydet**, biçim **Excel Çalışma Kitabı (.xlsx)**, ad
   `chart_reference_j4.xlsx`. Masaüstüne kaydet.
2. İstersen sayfanın ekran görüntüsünü de al (Cmd+Shift+4, sonra boşluk ve
   pencereye tıkla). Görüntü dilimlerin ve etiketlerin nasıl göründüğünü
   karşılaştırmaya yarar.
3. Dosyayı (ve görüntüyü) bana gönder ya da yolunu yaz. Excel'in tam sürümünü de
   yaz (**Excel > Excel Hakkında**).

Dosya senin onayınla `test/fixtures/owner/charts/` altına eklenir; değerler
kaynağıyla birlikte `packages/jet_charts_core/docs/excel-checks.md`
dosyasına yazılır.
