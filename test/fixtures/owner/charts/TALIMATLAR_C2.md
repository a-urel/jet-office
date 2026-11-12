# C2 Excel kontrolü: çalışma kitabı modelinin grafikleri

C2 ile `XlsxWorkbook` grafik ekliyor, değiştiriyor, taşıyor, siliyor ve
grafiğin verisini hücrelere yazıyor. Bu adımlar, bu dosyaların Excel for Mac'te
onarım uyarısı olmadan açıldığını ve doğru göründüğünü görmek içindir.
Yalnızca senin çalıştırman sonuç sayılır; hiçbir sonuç uydurulmaz. Sonuç
seninle birlikte `docs/excel-checks.md` dosyasının "C2" bölümüne yazılır.
Menü adlarını Türkçe Excel'e göre yazdım; bir ad farklıysa yanındaki İngilizce
adına bak.

Komutların hepsi deponun kök klasöründen çalışır.

## 1. Hazırlık

1. Dosyaları yaz ve doğrula:

   ```bash
   dart run tool/write_c2_check.dart build/c2
   dotnet run --project tool/ooxml_validate -- build/c2
   dotnet run --project tool/ooxml_validate -- build/c2/c2_edited
   ```

   İlk komut dokuz dosya yolu yazar. Diğer ikisi `no errors` ile bitmeli.

2. Depo `.claude` altındaysa Excel dosyayı oradan açamayabilir. O zaman
   dışarı kopyala ve kopyaları aç:

   ```bash
   mkdir -p ~/Documents/jet_c2
   cp -R build/c2/. ~/Documents/jet_c2/
   ```

3. Galeri uygulamasını başlat:

   ```bash
   (cd packages/jet_charts_flutter/example && flutter run -d macos)
   ```

## 2. Her dosya onarımsız açılıyor mu

Şu dokuz dosyayı Excel'de tek tek aç:

- `c2_kinds.xlsx`, `c2_data.xlsx`, `c1_kinds.xlsx`, `c1_options.xlsx`,
  `c2_dashboard.xlsx`
- `c2_edited/chart_reference.xlsx`, `c2_edited/chart_reference_undone.xlsx`,
  `c2_edited/chart_reference_j4.xlsx`,
  `c2_edited/chart_reference_j4_undone.xlsx`

Excel "Bazı içeriklerde sorun bulduk" (onarım) derse kabul etme, dur ve
iletiyi aynen yaz: bu bir hatadır.

Açtıkça şunlara bak:

1. `c1_kinds.xlsx` ve `c1_options.xlsx`: C1'de baktığın dosyaların aynısı
   olmalı. Artık grafikleri model ekliyor; görünüş değişmemeli.
2. `c2_kinds.xlsx`, sayfa `Data`: yedi grafik.
   - `Giderler`: pasta, dilimlerde değer ve yüzde.
   - `İki yıl`: iki halkalı halka.
   - `Ölçümler`: dağılım, x değerleri sayı (x ekseni yaklaşık 0 ile 7 arası),
     yalnızca işaretçiler.
   - `Gelir ve hedef`: sütun ve çizgi, tek eksen.
   - `Gelir ve marj`: sütun ve çizgi; çizgi sağdaki ikinci eksende, o eksen
     yüzde (`%12` gibi).
   - `Üç tür`: alan, sütun ve çizgi bir arada.
   - `Eğri`: düzgünleştirilmiş iki çizgi.
3. `c2_data.xlsx`: sayfa `O'Brien` veriyi tutar, sayfa `Pano` üç grafiği.
   - `Gelir ve gider`: kategoriler tarih (`01.01.2026` biçiminde), değer ekseni
     `TL` ile.
   - `Haftalık`: sabit renkli çizgi grafiği.
   - `Literal`: hücreye bağlı olmayan çubuk grafik.

## 3. Pano ile galeriyi yan yana karşılaştır

`c2_dashboard.xlsx`, sayfa `Pano` (dosya bu sayfada açılmalı). Yakınlaştırmayı
%100 yap, Excel'i ve uygulamayı yan yana koy. Her grafiğin adı (grafiği seç,
sol üstteki ad kutusunda görünür) uygulamadaki aynı adlı grafiktir:

| Pano'daki grafik | Uygulamada karşılığı |
|---|---|
| `column_clustered` | `column_clustered` |
| `bar_stacked` | yok; veri ve renkler `bar_clustered` gibi, çubuklar üst üste |
| `line_smooth` | "Monépro look" sayfasındaki açık temalı `line_smooth` |
| `area_stacked` | `area_stacked` |
| `pie_basic` | `pie_basic` |
| `donut_two_series` | `donut_two_series` |
| `scatter_basic` | `scatter_basic` |
| `combo_column_line` | `combo_column_line` |

Şunlara bak:

- tür, veri, başlık ve renkler aynı mı;
- `line_smooth`: Monépro renkleri (mavi ve yeşil); yazı tipi `DM Sans`
  (Mac'te yüklü değilse Excel başka yazı tipi gösterir, sorun değil);
- `combo_column_line`: `Adet` çizgisi sağdaki ikinci eksende mi, `Doğu`'nun
  `-4` sütunu sıfırın altında mı;
- `scatter_basic`: x ekseni sayı (0 ile 8 arası), iki eksende de ızgara;
- göstergenin (legend) yeri, eksen aralıkları;
- boşluklar: başlıkla çizim alanı arası, göstergeyle çizim alanı arası,
  kenar boşluğu. Bunlar Excel'den hiç doğrulanmadı; belirgin bir fark varsa
  hangi grafikte ve hangi yönde olduğunu yaz.

## 4. Grafik veriyi izliyor mu

Hâlâ `c2_dashboard.xlsx` açık:

1. Sayfa `Veri`, hücre `B2` (`North`, `Q1`, şimdi `12`): `30` yaz, Enter.
   `Pano`'da `column_clustered`'ın ilk mavi sütunu uzamalı.
2. Hücre `C58` (`Adet`, `Kuzey`, şimdi `120`): `300` yaz, Enter.
   `combo_column_line`'da çizginin ilk noktası yükselmeli, sağdaki eksen
   büyümeli.
3. Bir grafiğe sağ tıkla, **Veri Seç** (Select Data): seriler `=Veri!$B$2:$B$5`
   gibi `Veri` sayfasına bağlı olmalı.
4. Dosyayı kaydetmeden kapat.

## 5. Düzenlenen dosyalar ve geri alınmış ikizleri

Senin `chart_reference.xlsx` ve `chart_reference_j4.xlsx` dosyalarına model
şunları yaptı: grafik 1'i bir pastayla değiştirdi (başlığı `Pasta`,
dilimlerde değer ve yüzde), grafik 2'yi 10 satır aşağı taşıdı, grafik 3'ü
sildi, 2. satıra iki satır ekledi, sayfanın adını `Veri 2026` yaptı ve en alta
`Eklenen grafik` adlı bir sütun grafiği ekledi. `_undone` dosyaları aynı
düzenlemelerin geri alınmış hâlidir.

1. `c2_edited/chart_reference.xlsx`:
   - sayfanın adı `Veri 2026`; 2. ve 3. satırlar boş, veri `A4:C7`'de
     (başlıklar 1. satırda);
   - grafik 1 `Pasta`: `Kuzey` serisinin dört dilimi;
   - grafik 2 on iki satır aşağıda (10 taşıma, 2 eklenen satır); grafik 5'in
     üstüne biniyor, bu beklenen;
   - grafik 3 yok;
   - en altta `Eklenen grafik`: `Kuzey` ve `Güney` sütunları;
   - bir grafiğe sağ tıkla, **Veri Seç**: seriler `='Veri 2026'!$B$4:$B$7`
     gibi olmalı;
   - `B4`'ü değiştir: pasta ve diğer grafikler izlemeli. Kaydetmeden kapat.
2. `c2_edited/chart_reference_undone.xlsx`: deponun
   `test/fixtures/owner/charts/chart_reference.xlsx` dosyasıyla aynı
   görünmeli (sayfa `Veri`, 23 grafik, yerleri aynı). İkisini yan yana aç.
3. `c2_edited/chart_reference_j4.xlsx`: aynı düzenlemeler. Grafik 1 (pasta)
   yine pasta, başlığı `Pasta`, dilimlerde değer ve yüzde; grafik 2 (halka)
   aşağı taşındı; grafik 3 (iki halkalı) yok; en altta `Eklenen grafik`
   (`Satış` sütunları).
4. `c2_edited/chart_reference_j4_undone.xlsx`: deponun
   `test/fixtures/owner/charts/chart_reference_j4.xlsx` dosyasıyla aynı
   görünmeli.

## 6. E3: ikincil eksen ve sayısal dağılım

`test/fixtures/owner/charts/TALIMATLAR_E3.md` dosyasındaki 7 adımı yap. Sonra
oluşan iki grafiği `c2_dashboard.xlsx`'teki `combo_column_line` ve
`scatter_basic` ile, `c2_kinds.xlsx`'teki `Gelir ve marj` ve `Ölçümler` ile
karşılaştır: sağdaki eksenin yeri ve ızgarası, dağılımın x ekseni.

## 7. Başlığın dili ve bir ada bağlı seri

1. E3'te kaydettiğin `chart_reference_e3.xlsx` açık: birinci grafiğin
   başlığına (`Grafik Başlığı`) tıkla, `Satışlar` yaz, Enter.
2. **Dosya > Farklı Kaydet**, biçim **Excel Çalışma Kitabı (.xlsx)**, ad
   `chart_title_tr.xlsx`, Masaüstüne.
3. İsteğe bağlı: **Formüller > Ad Tanımla** (Define Name): ad `Tutarlar`,
   başvuru `=Veri!$B$2:$B$5`, Tamam. Birinci grafiğe sağ tıkla, **Veri Seç**,
   `Satış` serisini seç, **Düzenle**; değerler kutusuna
   `='chart_title_tr.xlsx'!Tutarlar` yaz, Tamam, Tamam. Grafik değişmemeli.
   **Dosya > Kaydet**.

## 8. Ne yazacaksın

Bana şunları yaz (kısa olabilir):

1. Excel'in sürümü (**Excel > Excel Hakkında**).
2. Dokuz dosyanın her biri için: onarımsız açıldı mı; açılmadıysa ileti.
3. Pano: her grafik için "aynı" ya da gördüğün fark. Ekran görüntüsü
   (Cmd+Shift+4, boşluk, pencereye tıkla) yardımcı olur.
4. Adım 4: iki grafik izledi mi.
5. Adım 5: düzenlenen iki dosya beklendiği gibi mi; `_undone` dosyaları
   özgün dosyalarla aynı mı.
6. E3 ve adım 7'nin dosyalarının yolu: `chart_reference_e3.xlsx`, ekran
   görüntüsü ve `chart_title_tr.xlsx`.

Dosyalar senin onayınla bu klasöre eklenir.
