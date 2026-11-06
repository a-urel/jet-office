# Eksen oracle'ı: Excel'de çalıştırma

Bu adımlar, Excel for Mac'in otomatik değer ekseninin grafik yüksekliğine ve yazı
boyutuna bağlı olup olmadığını öğrenmek içindir. Excel'i yalnızca sen
çalıştırıyorsun. Bir bölge (`tr-TR`) soruyu yanıtlamaya yeter. Bölge ve dil
ayarlarını değiştirmen gerekmiyor.

Komutların hepsi deponun kök klasöründen çalışır.

## Çalıştırma

1. Excel'de açık çalışma kitabı varsa kapat. Excel'in kendisi açık kalabilir.

2. Çalışma kitabını yaz:

   ```bash
   dart run packages/jet_charts_core/tool/write_axis_oracle.dart build/axis_oracle
   ```

   Beklenen çıktı: `Wrote axis_oracle.xlsx with 60 charts to build/axis_oracle.`

3. Betiği çalıştır:

   ```bash
   osascript packages/jet_charts_core/tool/axis_oracle/run_excel.applescript build/axis_oracle/axis_oracle.xlsx build/axis_oracle/axis_oracle.tr-TR.csv
   ```

   Excel öne gelir, dosyayı salt okunur açar, sayfalar sırayla görünür ve dosya
   kaydedilmeden kapanır. Bir iki dakika sürebilir; bu sırada Excel'e dokunma.
   Beklenen çıktı, satır sayısı 60 olarak: `60 rows written to ...`

   Ekrana şu sorular gelebilir:

   - **"Terminal", "Microsoft Excel" uygulamasını denetlemek istiyor:** İzin Ver
     de. Yalnızca ilk seferde sorulur.
   - **Excel'in dosya erişimi sorusu** (Erişim İzni Ver, ya da dosyayı seçmeni
     isteyen bir pencere): izin ver ya da `axis_oracle.xlsx` dosyasını seç. Betik
     bunun için on dakika bekler.
   - **Excel dosyada sorun bulduğunu söylerse** (onarım önerisi): kabul etme, dur
     ve iletisini aynen yaz. Bu, yazıcının hatasıdır.

4. İstersen `build/axis_oracle/axis_oracle.xlsx` dosyasını Excel'de aç ve bak: her
   sayfada beş grafik var, üst üste binmiyorlar. Görünüş önemli değil: dosyada tema
   yok, çubuklar soluk, farklı renkte ya da görünmez olabilir. Kaydetmeden kapat.

5. CSV'ye bak:

   ```bash
   wc -l build/axis_oracle/axis_oracle.tr-TR.csv
   head -3 build/axis_oracle/axis_oracle.tr-TR.csv
   ```

   Beklenen: 61 satır (başlık ve 60 grafik); ilk satır
   `case,height,font,min,max,major`. Sayılarda ondalık ayırıcı nokta olmalı.
   CSV'yi Excel'de açma ve elle düzeltme.

6. CSV'yi adını değiştirmeden fixture klasörüne kopyala:

   ```bash
   cp build/axis_oracle/axis_oracle.tr-TR.csv packages/jet_charts_core/test/fixtures/owner/axis/
   ```

7. Şu iki değeri not et:

   ```bash
   defaults read -g AppleLocale
   sw_vers -productVersion
   ```

   Excel'in tam adını, sürümünü ve yapı numarasını Excel → Excel Hakkında
   penceresinden al (kayıtlarda 16.114.x görünüyor, ama çalıştırdığın sürümü yaz).

8. `packages/jet_charts_core/test/fixtures/owner/axis/manifest.json` dosyasına
   aşağıdaki girdiyi yaz ve `<...>` yerlerini kendi değerlerinle doldur. `<` ile
   başlayan bir değer kalırsa test kabul etmez. Excel bir şey söylediyse
   (örneğin yazı tipi indirdiyse) `notes` alanına yaz.

   ```json
   [
     {
       "region": "tr-TR",
       "appleLocale": "<defaults read -g AppleLocale çıktısı>",
       "excelLanguage": "<Excel'in dili, örneğin Türkçe>",
       "excel": "<Excel Hakkında: ad, sürüm ve yapı>",
       "macos": "<sw_vers çıktısı>",
       "confirmedBy": "owner",
       "csv": "axis_oracle.tr-TR.csv",
       "notes": ""
     }
   ]
   ```

9. Denetimi ve çözümlemeyi çalıştır:

   ```bash
   (cd packages/jet_charts_core && dart test test/axis_oracle_test.dart)
   dart run packages/jet_charts_core/tool/analyze_axis_oracle.dart
   ```

   Beklenen: test geçer (`tr-TR results are well formed`). Çözümleme her veri seti
   için bir satır, en sonda da `answer:` ile başlayan yanıt satırını yazar.

## Betik durursa

- **Hata -1743 (izin yok):** Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon →
  Terminal altında Microsoft Excel'i aç, sonra 3. adımı yinele.
- **`Excel did not open ...` ya da dosya açılamadı hatası:** dosya gizli bir
  klasörde olabilir (`.claude` gibi). Dosyayı kopyala ve 3. adımı şu yollarla yinele:

  ```bash
  mkdir -p ~/Documents/jet_charts_oracle
  cp build/axis_oracle/axis_oracle.xlsx ~/Documents/jet_charts_oracle/
  osascript packages/jet_charts_core/tool/axis_oracle/run_excel.applescript ~/Documents/jet_charts_oracle/axis_oracle.xlsx build/axis_oracle/axis_oracle.tr-TR.csv
  ```

- **`60 rows` yerine daha az satır ve `failed:` listesi:** betik okuyabildiği
  grafikleri CSV'ye yazmıştır; okuyamadıklarını sonda grafik adıyla sayar ve 1
  koduyla çıkar. Eksik satırları elle ekleme. Çıktının tamamını kopyala ve bana
  gönder.
- **Başka bir hata:** Excel'de `axis_oracle.xlsx` açık kaldıysa kaydetmeden kapat,
  Terminal'deki iletiyi kopyala ve bana gönder.

## Ne gönderilecek

Klasördeki `axis_oracle.tr-TR.csv`, doldurduğun `manifest.json` ve 3. adımla 9.
adımın Terminal çıktısı. Commit'lemen de yeterli; çıktıyı ayrıca yaz.

## İsteğe bağlı: `chart_defaults.xlsx`

Bu dosya, temadaki doğrulanmamış varsayılanları (boşluk genişliği, çizgi kalınlığı,
işaretçi boyutu, yazı tipi, renkler) çözer.

1. Excel'de yeni, boş bir çalışma kitabı aç.
2. A1:A3 hücrelerine üç kategori, B1:B3 hücrelerine üç sayı yaz (örneğin `A`, `B`,
   `C` ve `1`, `2`, `3`).
3. Verileri seç, Ekle sekmesinden varsayılan kümelenmiş sütun grafiğini ekle.
4. Verileri yeniden seç, Ekle sekmesinden işaretçili çizgi grafiğini ekle. İkinci
   grafiği birinciyle çakışmayacak yere sürükle; başka bir şeyi değiştirme.
5. Dosyayı `chart_defaults.xlsx` adıyla kaydet ve bir daha düzenleme. Hedef
   `packages/jet_charts_core/test/fixtures/owner/axis/` klasörü. Excel gizli
   klasöre kaydedemez; gerekirse `~/Documents/jet_charts_oracle/` içine kaydedip
   oraya kopyala.
