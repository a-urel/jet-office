# Grafik referansı E3: ikincil eksen ve sayısal dağılım

J4'ün E1 dosyasında iki grafik talimattan farklı çıktı. Bu yüzden iki değer
hâlâ kontrol edilmedi: ikincil değer ekseni ve x değerleri sayı olan dağılım
grafiği. Bu adımlar o ikisi içindir. Acelesi yok, uygun olduğunda yap.
Yalnızca senin çalıştırman sonuç sayılır.

1. Excel'de yeni boş bir çalışma kitabı aç. İlk sayfanın adını `Veri` yap.
2. Hücrelere şunları yaz. A1 boş kalsın.

   |   | A     | B     | C     |
   |---|-------|-------|-------|
   | 1 |       | Satış | Adet  |
   | 2 | Kuzey | 12    | 120   |
   | 3 | Güney | 18    | 95    |
   | 4 | Doğu  | -4    | 140   |
   | 5 | Batı  | 9     | 80    |

3. `A1:C5` seçili: **Ekle > Grafik > Birleşik**, tam olarak **Kümelenmiş
   Sütun - İkincil Eksende Çizgi** (Clustered Column - Line on Secondary
   Axis). Menüdeki diğer birleşik türleri değil.
4. Yalnızca `B2:C5`'i seç (A sütunu ve 1. satır seçili olmasın): **Ekle >
   Grafik > Dağılım (X Y)**, yalnızca işaretçili ilk tür. Bu grafikte tek seri
   olmalı: x değerleri B sütunu, y değerleri C sütunu.
5. Başka hiçbir ayara dokunma. **Dosya > Farklı Kaydet**, biçim **Excel
   Çalışma Kitabı (.xlsx)**, ad `chart_reference_e3.xlsx`, Masaüstüne.
6. Sayfanın ekran görüntüsünü al (Cmd+Shift+4, boşluk, pencereye tıkla); iki
   grafik de tam görünsün, önünde pencere olmasın.
7. Dosyanın ve görüntünün yolunu yaz.

Sonuç `packages/jet_charts_core/docs/excel-checks.md` dosyasına seninle
birlikte yazılır; dosya senin onayınla bu klasöre eklenir.
