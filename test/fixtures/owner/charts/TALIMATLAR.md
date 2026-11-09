# Grafik referansı: Excel'de hazırlama

Bu adımlar, Excel for Mac'in grafikleri nasıl yazdığını görmek içindir. Yazıcımız
(`jet_office`) bu dosyayla karşılaştırılır. Yalnızca senin çalıştırman sonuç
sayılır; hiçbir sonuç uydurulmaz. Menü adlarını Türkçe Excel'e göre yazdım. Bir
ad farklıysa yanındaki açıklamaya bak.

## 1. Çalışma kitabı

1. Excel'de yeni boş bir çalışma kitabı aç.
2. İlk sayfanın adını `Veri` yap (sayfa sekmesine çift tıkla).
3. Hücrelere şunları yaz. A1 boş kalsın.

   |   | A  | B     | C     |
   |---|----|-------|-------|
   | 1 |    | Kuzey | Güney |
   | 2 | Ç1 | 10    | 20    |
   | 3 | Ç2 | 25    | 15    |
   | 4 | Ç3 | 30    | 35    |
   | 5 | Ç4 | 18    | 22    |

## 2. Grafikler

Her grafik için önce `A1:C5` aralığını seç, sonra **Ekle > Grafik** menüsünden
(İngilizce: Insert > Chart) istenen türü ekle. Her grafikte yalnızca adı geçen
şeyi değiştir; başka hiçbir ayara dokunma. Grafikleri aynı sayfaya, üst üste
gelmeyecek biçimde yerleştir (düzen önemli değil; sayfayı aşağı ve yana
kullanabilirsin). Sırayı koru, numaralar sıradır.

Önce 12 tür. Her türde başlık, gösterge ve eksenler Excel'in verdiği gibi kalsın.

1. Kümelenmiş Sütun
2. Yığılmış Sütun
3. %100 Yığılmış Sütun
4. Kümelenmiş Çubuk
5. Yığılmış Çubuk
6. %100 Yığılmış Çubuk
7. İşaretçili Çizgi
8. Yığılmış İşaretçili Çizgi
9. %100 Yığılmış İşaretçili Çizgi
10. Alan
11. Yığılmış Alan
12. %100 Yığılmış Alan

Sonra aşağıdakilerin her biri için yeni bir **Kümelenmiş Sütun** grafiği ekle
(yine `A1:C5` seçiliyken) ve yalnızca istenen değişikliği yap. Biçim ayarları
için grafiği seçip **Grafik Tasarımı** (veya Grafik Biçimlendir) sekmesini ve
**Grafik Öğesi Ekle** menüsünü kullan; eksen ayarları için eksene çift tıkla,
sağdaki **Ekseni Biçimlendir** bölmesi açılır.

13. Grafik başlığı `Satışlar`.
14. Gösterge üstte (Grafik Öğesi Ekle > Gösterge > Üst).
15. Gösterge sağda (Gösterge > Sağ).
16. Gösterge yok (Gösterge > Yok).
17. İki eksen başlığı da var: yatay eksene `Çeyrek`, dikey eksene `Tutar`
    (Grafik Öğesi Ekle > Eksen Başlıkları).
18. Değer ekseni (dikey eksen): en az 0, en çok 50, ana birim 10
    (Ekseni Biçimlendir > Sınırlar ve Birimler; İngilizce Minimum, Maximum,
    Major).
19. Değer ekseni sayı biçimi `#,##0.00` (Ekseni Biçimlendir > Sayı > Biçim
    Kodu, yazdıktan sonra **Ekle**'ye bas).
20. Veri etiketleri açık (Grafik Öğesi Ekle > Veri Etiketleri).
21. Veri etiketleri açık ve etiket sayı biçimi `0.0` (Veri etiketlerine çift
    tıkla > Sayı > Biçim Kodu, **Ekle**).
22. Değer ekseni ve ana kılavuz çizgileri silinmiş (Eksenler > Dikey işaretini
    kaldır; Kılavuz Çizgileri > Ana Yatay işaretini kaldır).

### Ad tanımı (grafik 23)

23. Önce `Tutarlar` adını tanımla: `B2:B5` aralığını seç, **Formüller > Ad
    Tanımla** (İngilizce: Formulas > Define Name) de, ad olarak `Tutarlar`
    yaz, başvuru `=Veri!$B$2:$B$5` olsun, Tamam. Sonra yine **Kümelenmiş
    Sütun** grafiği ekle (`A1:C5` seçili), grafiği seç, **Grafik Tasarımı >
    Veri Seç** (Select Data) aç, ilk serinin (Kuzey) **Değerler** alanını
    `=chart_reference.xlsx!Tutarlar` yap. Excel adı kendi biçimine çevirirse
    (örneğin `=Kitap1!Tutarlar` ya da başka bir ad) Excel'in gösterdiğini aynen
    bırak. Amaç, Excel'in dosyaya ne yazdığını görmek.

## 3. Kaydet

**Dosya > Farklı Kaydet** ile `chart_reference.xlsx` adıyla, biçim **Excel
Çalışma Kitabı (.xlsx)** olarak kaydet. Excel'in sürümünü not et (Excel >
Excel Hakkında).

Dosyayı ve notlarını Claude'a gönder. İstersen kendin
`test/fixtures/owner/charts/` altına koyup commit edebilirsin; istemezsen
Claude yapar.

## 4. Bizim dosyalarımızı Excel'de aç

Denetleyici (Claude) şu iki dosyayı üretir:

- `build/fixtures/c1_kinds.xlsx`
- `build/fixtures/c1_options.xlsx`

Her birini Excel for Mac'te aç ve şunu bildir:

1. Onarım uyarısı (onarım penceresi) çıktı mı? Çıktıysa tam metnini yaz.
2. Grafikler senin kendi grafiklerinden nerede farklı görünüyor? (Renkler,
   boşluklar, yazı boyutu, eksen aralıkları, gösterge yeri, kılavuz çizgileri.)
   Her fark için hangi dosya ve hangi grafik olduğunu yaz.

Bir fark yoksa "fark yok" yaz. Yalnızca senin çalıştırman sonuç sayılır;
hiçbir sonuç uydurulmaz.
