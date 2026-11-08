# Tam eksen oracle'ı: Excel'de çalıştırma

Bu adımlar, Excel for Mac'in değer eksenini grafik boyutuna, türüne ve
gruplamasına göre nasıl seçtiğini ölçmek içindir. Bu kez çizim alanının kutusu
ve kategori etiketlerinin aralığı da okunur. Yalnızca senin çalıştırman sonuç
sayılır. Bir bölge (`tr-TR`) yeter. Bölge ve dil ayarlarını değiştirmen
gerekmiyor.

Komutların hepsi deponun kök klasöründen çalışır.

## Çalıştırma

1. Excel'de açık çalışma kitabı varsa kapat. Excel'in kendisi açık kalabilir.

2. Çalışma kitabını yaz:

   ```bash
   dart run packages/jet_charts_core/tool/write_axis_oracle.dart --full build/axis_oracle_full
   ```

   Beklenen çıktı: `Wrote axis_oracle_full.xlsx with 239 charts to build/axis_oracle_full.`

   Depo `.claude` altındaysa Excel dosyayı oradan açamayabilir. O zaman dosyayı
   dışarı kopyala ve sonraki adımlarda bu yolu kullan:

   ```bash
   mkdir -p ~/Documents/jet_charts_oracle
   cp build/axis_oracle_full/axis_oracle_full.xlsx ~/Documents/jet_charts_oracle/
   ```

3. Betiği çalıştır. Sondaki `full` sözcüğü gerekli:

   ```bash
   osascript packages/jet_charts_core/tool/axis_oracle/run_excel.applescript build/axis_oracle_full/axis_oracle_full.xlsx build/axis_oracle_full/axis_oracle_full.tr-TR.csv full
   ```

   Dosyayı kopyaladıysan ilk yolu
   `~/Documents/jet_charts_oracle/axis_oracle_full.xlsx` yap. CSV yolu aynı
   kalır.

   Excel öne gelir, dosyayı salt okunur açar, sayfalar sırayla görünür ve dosya
   kaydedilmeden kapanır. Birkaç dakika sürer; bu sırada Excel'e dokunma.
   Beklenen çıktı: `239 rows written to ...`

   Ekrana şu sorular gelebilir (metinleri yaklaşıktır):

   - **"Terminal", "Microsoft Excel" uygulamasını denetlemek istiyor:** **İzin
     Ver**'e tıkla.
   - **Excel'in dosya erişimi sorusu:** izin ver ya da `axis_oracle_full.xlsx`
     dosyasını seç. Betik on dakika bekler.
   - **Excel dosyada sorun bulduğunu söylerse** (onarım önerisi): kabul etme, dur
     ve iletisini aynen yaz. Bu, çalışma kitabını yazan kodun hatasıdır.

4. Gözle denetle; bu adımı atlama. Üç grafiğin satırını yazdır:

   ```bash
   grep -E '^(L07-w360-h80-f10|B07-w100-h300-f10|C03-w180-h300-f10),' build/axis_oracle_full/axis_oracle_full.tr-TR.csv
   ```

   Sütunlar: `case,width,height,font,min,max,major,plotLeft,plotTop,plotWidth,plotHeight,labelSpacing`.

   Sonra çalışma kitabını Excel'de aç. Bir grafiğe tıklayınca adı, sol üstteki
   ad kutusunda görünür. Grafikler sayfada yukarıdan aşağı dizilidir:

   - **`L07-w360-h80-f10`**, `length` sayfasında yukarıdan 26. grafik (alçak bir
     sütun grafiği). Dikey eksenin en üstteki etiketi `max`, iki komşu etiket
     arasındaki fark `major` olmalı.
   - **`B07-w100-h300-f10`**, `bar` sayfasında yukarıdan 22. grafik (dar bir
     çubuk grafiği). Burada değer ekseni yataydır, altta durur: en sağdaki
     etiket `max`, iki komşu etiket arasındaki fark `major` olmalı.
   - **`C03-w180-h300-f10`**, `labels` sayfasında yukarıdan 7. grafik (uzun
     kategori etiketli, dar bir sütun grafiği). Dikey eksen yine `max` ve
     `major` ile uymalı. `labelSpacing` 1 ise her kategori etiketi görünür; 2
     ise bir atlayarak, 3 ise ikişer atlayarak görünür.

   Biri uymuyorsa dur, sonraki adımlara geçme ve bana hangi grafikte ne
   gördüğünü yaz. Dosyayı kaydetmeden kapat.

5. CSV'ye bak:

   ```bash
   wc -l build/axis_oracle_full/axis_oracle_full.tr-TR.csv
   head -3 build/axis_oracle_full/axis_oracle_full.tr-TR.csv
   grep -c '^C' build/axis_oracle_full/axis_oracle_full.tr-TR.csv
   ```

   Beklenen: 240 satır (başlık ve 239 grafik); ilk satır yukarıdaki sütunlar.
   Sayılarda ondalık ayırıcı nokta olmalı. `C` ile başlayan 9 satırın sonunda
   `labelSpacing` dolu olmalı. CSV'yi Excel'de açma ve elle düzeltme.

6. CSV'yi adını değiştirmeden fixture klasörüne kopyala:

   ```bash
   cp build/axis_oracle_full/axis_oracle_full.tr-TR.csv packages/jet_charts_core/test/fixtures/owner/axis_full/
   ```

7. Şu iki değeri not et:

   ```bash
   defaults read -g AppleLocale
   sw_vers -productVersion
   ```

   Excel'in tam adını, sürümünü ve yapı numarasını Excel → Excel Hakkında
   penceresinden al.

8. `packages/jet_charts_core/test/fixtures/owner/axis_full/manifest.json`
   dosyasına aşağıdaki girdiyi yaz ve `<...>` yerlerini kendi değerlerinle
   doldur. `<` ile başlayan bir değer kalırsa test kabul etmez. Excel bir şey
   söylediyse `notes` alanına yaz.

   ```json
   [
     {
       "region": "tr-TR",
       "appleLocale": "<defaults read -g AppleLocale çıktısı>",
       "excelLanguage": "<Excel'in dili, örneğin Türkçe>",
       "excel": "<Excel Hakkında: ad, sürüm ve yapı>",
       "macos": "<sw_vers -productVersion çıktısı>",
       "confirmedBy": "owner",
       "csv": "axis_oracle_full.tr-TR.csv",
       "notes": ""
     }
   ]
   ```

9. `chart_defaults.xlsx` dosyasını hazırla. Bu adım bu kez zorunlu: temadaki
   doğrulanmamış varsayılanları (boşluk genişliği, çizgi kalınlığı, işaretçi
   boyutu, yazı tipi, renkler) çözer.

   1. Excel'de yeni, boş bir çalışma kitabı aç.
   2. A1:A3 hücrelerine `A`, `B`, `C`, B1:B3 hücrelerine `1`, `2`, `3` yaz.
   3. Verileri seç, Ekle sekmesinden varsayılan kümelenmiş sütun grafiğini ekle.
   4. Verileri yeniden seç, Ekle sekmesinden işaretçili çizgi grafiğini ekle.
      İkinci grafiği birinciyle çakışmayacak yere sürükle; başka bir şeyi
      değiştirme.
   5. Dosyayı `chart_defaults.xlsx` adıyla kaydet ve bir daha düzenleme. Hedef
      `packages/jet_charts_core/test/fixtures/owner/axis_full/` klasörü. Excel
      gizli klasöre kaydedemezse `~/Documents/jet_charts_oracle/` içine kaydet
      ve oradan kopyala:

      ```bash
      cp ~/Documents/jet_charts_oracle/chart_defaults.xlsx packages/jet_charts_core/test/fixtures/owner/axis_full/
      ```

10. Denetimi ve çözümlemeyi çalıştır:

    ```bash
    (cd packages/jet_charts_core && dart test test/axis_oracle_test.dart)
    dart run packages/jet_charts_core/tool/analyze_axis_oracle.dart --full
    ```

    Beklenen: test geçer (`full: tr-TR results are well formed`). Çözümleme
    önce bölge satırını (`tr-TR`), sonra her grup için başlık ve satırları
    yazar.

## Betik durursa

- **Hata -1743 (izin yok):** Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon
  → Terminal altında Microsoft Excel'i aç, sonra 3. adımı yinele.
- **`Excel did not open ...` ya da dosya açılamadı hatası:** dosya gizli bir
  klasörde olabilir (`.claude` gibi). 2. adımdaki kopyalama komutunu çalıştır ve
  3. adımı kopyanın yoluyla yinele.
- **`239 rows` yerine daha az satır ve `failed:` listesi:** betik okuyabildiği
  grafikleri CSV'ye yazmıştır; okuyamadıklarını sonda adıyla sayar ve 1 koduyla
  çıkar. Eksik satırları elle ekleme. Çıktının tamamını kopyala ve bana gönder.
- **`usage:` hatası:** komutun sonunda `full` sözcüğü eksik ya da yanlış yazılmış.
- **Başka bir hata:** Excel'de `axis_oracle_full.xlsx` açık kaldıysa kaydetmeden
  kapat, Terminal'deki iletiyi kopyala ve bana gönder.

## Ne gönderilecek

`axis_full` klasöründeki `axis_oracle_full.tr-TR.csv`, `chart_defaults.xlsx` ve
doldurduğun `manifest.json`; 3. adımla 10. adımın Terminal çıktısı; 4. adımda
gördüklerin (üç grafik uydu mu). Commit'lemen de yeterli; çıktıyı ayrıca yaz.
