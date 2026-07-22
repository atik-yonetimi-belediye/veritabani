# Atık Yönetimi Belediye — Veritabanı Dokümantasyonu

Bu doküman, `atik-yonetimi-belediye.sql` dosyasındaki PostgreSQL şemasını backend geliştirecek kişi için satır satır açıklar. Şema dosyasını çalıştırmadan önce ve backend'e başlamadan önce bu dosyayı baştan sona okuyun — özellikle **"Backend'de Zorunlu Kontroller"** bölümü, veritabanının garanti ETMEDİĞİ ama uygulamanın garanti etmesi gereken kuralları listeler.

---

## 1) Genel Bakış

- **Veritabanı motoru:** PostgreSQL (ENUM tipleri, `TIMESTAMPTZ`, `SERIAL`, trigger fonksiyonları kullanıldığı için PostgreSQL'e özeldir; MySQL/SQLite'a doğrudan taşınamaz).
- **Dosya:** Tek bir `.sql` dosyası, sırayla şu bölümlerden oluşur:

| # | Bölüm | Ne yapar |
|---|-------|----------|
| 00 | DROP IF EXISTS | Tüm tabloları/tipleri siler (tekrar kurulum için) |
| 01 | ENUM Tipler | Sabit liste tipleri tanımlar |
| 02 | Ana Tablolar | `mahalleler`, `yoneticiler`, `cavuslar`, `sirketler` |
| 03 | Araç ve Şoför | `araclar`, `soforler` |
| 04 | Konteynerler | `konteynerler` |
| 05 | Toplama Kayıtları | `toplama_kayitlari` |
| 06 | Şikayetler | `sikayetler`, `sikayet_fotograflari` |
| 07 | Geri Dönüşüm Talepleri | `geri_donusum_talepleri` |
| 08 | Indexler | Performans indexleri |
| 09 | Trigger | `updated_at` otomatik güncelleme |
| 10 | Örnek Veri | Test/geliştirme verisi (gerçek bcrypt hash'li) |
| 11 | Test Sorguları | Kontrol amaçlı `SELECT`'ler (production'a taşınmamalı) |

- **Kurulum:** Dosya baştan sona tek seferde çalıştırılabilir, tekrar çalıştırılabilir (idempotent — başta `DROP IF EXISTS` var, hata vermeden sıfırdan kurar).

```bash
psql -U <kullanici> -d <veritabani_adi> -f atik-yonetimi-belediye.sql
```

---

## 2) Sistemdeki Roller (Kullanıcı Tipleri)

Sistemde 4 farklı "giriş yapabilen" aktör var, her biri **ayrı tabloda**, **ayrı şifre alanıyla** tutuluyor (tek bir `users` tablosu yok — bilinçli bir tasarım tercihi):

| Rol | Tablo | Login alanı | Notlar |
|---|---|---|---|
| Belediye yöneticisi | `yoneticiler` | `kullanici_adi` + `sifre` | Sistemin admin'i |
| Çavuş (mahalle sorumlusu) | `cavuslar` | `telefon` + `sifre` | Her mahallede tam olarak 1 çavuş |
| Şoför | `soforler` | `telefon` + `sifre` | Bir araca bağlı |
| Şirket (geri dönüşüm firması) | `sirketler` | `telefon` veya `mail` + `sifre` | Admin onayı gerekir (`onay_durumu`) |

Vatandaş (misafir kullanıcı) için **ayrı bir tablo yok** — vatandaş login olmadan şikayet/talep oluşturur, bilgileri (`vatandas_ad_soyad`, `vatandas_telefon` vb.) doğrudan ilgili tabloya (`sikayetler`, `geri_donusum_talepleri`) yazılır.

**Şifreler:** Tüm `sifre` kolonları `VARCHAR(255)` — bcrypt hash'i (60 karakter) rahatlıkla sığar. Backend'de kullanıcı girişinde **düz metin şifre asla saklanmamalı**, `bcrypt.hash(sifre, 10)` veya üzeri round ile hash'lenip kaydedilmeli, girişte `bcrypt.compare()` ile doğrulanmalı.

Örnek veri bölümündeki test kullanıcıları ve gerçek bcrypt hash'leriyle eşleşen düz metin şifreleri:

| Kullanıcı | Tablo | Telefon/Kullanıcı adı | Düz metin şifre |
|---|---|---|---|
| Deniz Kaya (yönetici) | `yoneticiler` | `denizk` | `admin123` |
| Selin Yılmaz (çavuş) | `cavuslar` | `05052223344` | `cavus123` |
| Berke Karaman (şoför) | `soforler` | `05053334455` | `sofor123` |
| Deniz Kılınç (şoför) | `soforler` | `05054445566` | `sofor123` |
| Çevik Geri Dönüşüm A.Ş. | `sirketler` | `03441112233` | `sirket123` |

> ⚠️ Bu hash'ler **sadece geliştirme/test** içindir. Production'da her kullanıcı kendi şifresini backend üzerinden belirlemeli.

---

## 3) ENUM Tipleri (Sabit Listeler)

PostgreSQL ENUM'ları, olası değerleri veritabanı seviyesinde kısıtlar — yanlış bir string INSERT edilmeye çalışılırsa hata alırsınız. Backend'de bu değerleri **birebir aynı yazımla** (küçük harf, alt çizgi) göndermelisiniz.

### `atik_turu`
```
kati_atik | geri_donusum
```
Hem araç, hem konteyner, hem şikayet, hem talep bu tipi kullanır — sistemdeki iki temel atık kategorisi.

### `gonderen_tipi`
```
vatandas | yonetici | sirket
```
`geri_donusum_talepleri` tablosunda "bu talebi kim oluşturdu" bilgisi.

### `talep_durumu`
```
bekliyor | onaylandi | reddedildi | tamamlandi | iptal_edildi
```
Geri dönüşüm talebinin yaşam döngüsü (şikayet durumundan farklı, daha geniş).

### `sirket_onay_durumu`
```
bekliyor | onaylandi | reddedildi | pasif
```
Şirketin sisteme kabul durumu. **`talep_durumu` ile karıştırmayın** — biri şirketin kendisiyle, diğeri şirketin/vatandaşın açtığı taleple ilgili.
- `bekliyor`: yeni kayıt olmuş, admin onayı bekliyor
- `onaylandi`: sisteme giriş yapabilir, talep oluşturabilir
- `reddedildi`: admin tarafından reddedildi
- `pasif`: daha önce onaylanmış ama sonradan sistemden çıkarılmış (soft delete)

### `toplama_durumu`
```
toplandi | atlanildi
```
Şoförün bir konteynere uğradığında seçtiği iki seçenek.

### `sikayet_durumu`
```
bekliyor | inceleniyor | cozuldu | reddedildi
```

### `sikayet_kategorisi`
```
konteyner_dolu | konteyner_kirik | kotu_koku | cop_tasmasi | zamaninda_toplanmadi | diger
```
**Dikkat:** `sikayet_turu` (atık türü: `kati_atik`/`geri_donusum`) ile `sikayet_kategorisi` (şikayetin niteliği) birbirinden tamamen farklı iki alandır, ikisi de zorunludur.

---

## 4) Tablo Tablo Detaylı Açıklama

### 4.1 `mahalleler`
Belediyenin idari mahalle listesi. Sistemin en temel referans tablosu — çavuş, konteyner ve dolaylı olarak şoför/araç hep bir mahalleye bağlanır.

| Kolon | Tip | Açıklama |
|---|---|---|
| `id` | SERIAL PK | |
| `ad` | VARCHAR(100), **UNIQUE** | Mahalle adı, iki kez eklenemez |
| `ilce` | VARCHAR(100), default `Onikişubat` | |
| `il` | VARCHAR(100), default `Kahramanmaraş` | |
| `created_at`, `updated_at` | TIMESTAMPTZ | Otomatik (trigger ile) |

Silinemez: `cavuslar.mahalle_id` ve `konteynerler.mahalle_id` bu tabloya `ON DELETE RESTRICT` ile bağlı — yani bir mahalleye bağlı çavuş veya konteyner varsa o mahalle silinemez, önce onları taşımanız/silmeniz gerekir.

### 4.2 `yoneticiler`
Belediye admin kullanıcıları. `aktif_mi = false` yapılarak soft-delete edilebilir (fiziksel silme yerine).

### 4.3 `cavuslar`
Her mahalleden sorumlu tek bir kişi.

| Kolon | Tip | Açıklama |
|---|---|---|
| `mahalle_id` | INT, **NOT NULL**, **UNIQUE** | Bir mahallede yalnızca 1 çavuş olabilir |
| `telefon` | VARCHAR(20), **UNIQUE** | Login bilgisi |
| `ad_soyad` | VARCHAR(100) | **UNIQUE DEĞİL** (bilinçli — aynı isimde iki farklı kişi olabilir, login zaten telefonla yapılıyor) |
| `aktif_mi` | BOOLEAN, default true | Soft delete |

**Önemli backend kuralı (bkz. bölüm 5, madde B):** Çavuş konteyner eklerken, mobil uygulamadan gelen `mahalle_id` **kullanılmamalı**. Backend, giriş yapmış çavuşun token'ından kendi `mahalle_id`'sini okumalı ve konteyneri otomatik o mahalleye kaydetmelidir.

### 4.4 `sirketler`
Geri dönüşüm firmaları. `onay_durumu` alanı ile admin onayı bekler.

- Yeni şirket kaydı → `onay_durumu = 'bekliyor'`
- Admin onaylarsa → `'onaylandi'` (artık login olup talep oluşturabilir)
- Admin reddederse → `'reddedildi'`
- Sonradan sistemden çıkarılırsa → `'pasif'` (fiziksel silme değil)

### 4.5 `araclar`
| Kolon | Açıklama |
|---|---|
| `plaka` | UNIQUE, zorunlu |
| `arac_turu` | `kati_atik` veya `geri_donusum` — aracın hangi tür atığı topladığını belirler |
| `cavus_id` | Aracın bağlı olduğu çavuş (nullable, çavuş silinirse `NULL` olur) |
| `aktif_mi` | Soft delete |

### 4.6 `soforler`
| Kolon | Açıklama |
|---|---|
| `telefon` | UNIQUE, login bilgisi |
| `arac_id` | UNIQUE — bir araca aynı anda yalnızca **1** şoför atanabilir |
| `cavus_id` | Şoförün bağlı olduğu çavuş |

Şoförün hangi atık türünü topladığı **ayrı bir kolonda tutulmuyor** — `soforler.arac_id → araclar.arac_turu` ilişkisinden okunuyor. Bu, aynı bilgiyi iki yerde tutup senkron sorunu yaşamamak için bilinçli bir tasarım.

Bir şoförü başka bir araca atamak için:
```sql
UPDATE soforler SET arac_id = <yeni_arac_id> WHERE id = <sofor_id>;
```

### 4.7 `konteynerler`
Sahadaki fiziksel konteynerler.

| Kolon | Açıklama |
|---|---|
| `konteyner_kodu` | UNIQUE, örn. `KNT-0001` — sahada takip için |
| `tur` | `kati_atik` / `geri_donusum` |
| `mahalle_id` | NOT NULL, hangi mahallede olduğu |
| `cavus_id` | Sorumlu çavuş (nullable) |
| `latitude`, `longitude` | `DECIMAL(10,8)` / `DECIMAL(11,8)` — harita konumu |
| `aktif_mi` | Soft delete (fiziksel kaldırılan konteyner) |

### 4.8 `toplama_kayitlari`
Şoförün her konteynere uğrayışının kaydı (hem "topladım" hem "atladım" durumları burada, tek tabloda).

| Kolon | Açıklama |
|---|---|
| `konteyner_id` | Hangi konteyner (silinirse `NULL` olur, geçmiş kayıt kaybolmaz) |
| `sofor_id` | Hangi şoför |
| `durum` | `toplandi` veya `atlanildi` |
| `sebep` | Yalnızca `atlanildi` iken doldurulur (örn. "Yol kapalı") |
| `diger_aciklama` | `sebep = 'Diğer'` seçilirse ek açıklama |

**Veritabanı seviyesinde zorunlu kural (CHECK constraint):**
```
durum = 'toplandi'  → sebep VE diger_aciklama BOŞ OLMALI
durum = 'atlanildi' → sebep DOLU OLMALI
```
Yani backend `sebep` alanını yalnızca kullanıcı "atlandı" seçtiğinde forma göstermeli/göndermeli; "toplandı" seçilirse `sebep` ve `diger_aciklama` alanlarını göndermemeli veya `null` göndermeli — aksi halde INSERT/UPDATE veritabanı hatası verir.

**Henüz karara bağlanmamış nokta:** Aynı konteyner aynı gün birden fazla kez "toplandı" olarak işaretlenebilsin mi? Şu an sistemde buna izin var. Eğer günde yalnızca 1 kez toplama isteniyorsa, SQL dosyasındaki yorum satırı açılmalı:
```sql
CREATE UNIQUE INDEX unique_konteyner_gunluk_toplama
    ON toplama_kayitlari (konteyner_id, DATE(tarih_saat))
    WHERE durum = 'toplandi';
```
Bu karar netleşmeden backend'de "aynı konteyner günde birden fazla toplanabilir" varsayımıyla ilerleyin, sonradan index eklemek geriye dönük veri sorunu yaratabileceğinden önce mevcut veriyi kontrol edin.

### 4.9 `sikayetler` ve `sikayet_fotograflari`
Vatandaşın (login gerektirmeden) oluşturduğu şikayetler.

`sikayetler`:
| Kolon | Açıklama |
|---|---|
| `vatandas_ad_soyad`, `vatandas_telefon` | Login olmadığı için doğrudan buraya yazılır |
| `konteyner_id` | Veritabanında **nullable** (bkz. bölüm 5, madde D) |
| `sikayet_turu` | `kati_atik` / `geri_donusum` |
| `sikayet_kategorisi` | ENUM, bkz. bölüm 3 |
| `durum` | `bekliyor` → `inceleniyor` → `cozuldu`/`reddedildi` |
| `yonetici_notu` | Admin'in çözüm notu |
| `cozulme_tarihi` | Şikayet çözüldüğünde doldurulur |

`sikayet_fotograflari`: Her şikayete birden fazla fotoğraf eklenebilmesi için ayrı tablo (eski tasarımdaki sabit `foto_1_url/foto_2_url/foto_3_url` kolonları yerine). `ON DELETE CASCADE` — şikayet silinirse fotoğrafları da silinir.

### 4.10 `geri_donusum_talepleri`
Hem vatandaşın hem şirketin hem yöneticinin oluşturabildiği geri dönüşüm talebi.

| Kolon | Açıklama |
|---|---|
| `sirket_id` | Talebi hangi şirkete yönlendirdiği / hangi şirketin açtığı |
| `gonderen_tipi` | `vatandas` / `yonetici` / `sirket` |
| `konteyner_id` | Nullable — bazı talepler doğrudan adresten alım içindir, konteynere bağlı olmak zorunda değil |
| `atik_turu`, `talep_basligi`, `talep_aciklamasi`, `tahmini_miktar` (kg), `adres` | Şirket taleplerinde daha zengin bilgi için |
| `durum` | `talep_durumu` enum'u |

**Veritabanı seviyesinde zorunlu kural (CHECK constraint):**
```
gonderen_tipi = 'sirket'   → sirket_id DOLU OLMALI
gonderen_tipi = 'vatandas' → sirket_id BOŞ OLMALI
gonderen_tipi = 'yonetici' → sirket_id serbest (dolu veya boş olabilir)
```
Backend, formu bu kurala göre kurmalı: gönderen tipi "vatandaş" ise `sirket_id` alanını hiç göndermemeli/`null` göndermeli.

---

## 5) Backend'de Zorunlu Kontroller (Veritabanı Bunları Garanti ETMİYOR)

Aşağıdaki kurallar veritabanı şemasında **kasıtlı olarak** uygulanmadı (ya iş mantığı çok değişken ya da trigger karmaşıklığı gereksiz). Backend geliştirirken bunları **mutlaka** uygulama katmanında kontrol edin, aksi halde veri tutarsızlığı oluşur:

**A. Şoför — Konteyner tür eşleşmesi**
Katı atık aracına bağlı bir şoför, geri dönüşüm konteynerini "toplandı" işaretleyebilir — veritabanı bunu engellemez.
→ Backend'de: `soforler.arac_id → araclar.arac_turu` ile `konteynerler.tur` karşılaştırılmalı, eşleşmiyorsa toplama kaydı reddedilmeli.

**B. Çavuş — Mahalle sınırı**
Bir çavuş, kendi mahallesi dışında konteyner ekleyebilir — veritabanı engellemez.
→ Backend'de: konteyner eklerken `mahalle_id` ve `cavus_id`, istekten değil, giriş yapmış çavuşun kendi token bilgisinden otomatik doldurulmalı.

**C. Şikayette konteyner zorunluluğu**
Veritabanında `sikayetler.konteyner_id` nullable (geçmiş kayıtların korunması için bilinçli tercih), ama proje kuralına göre misafir kullanıcı şikayet oluştururken konteyner seçmek zorunda.
→ Backend'de: şikayet oluşturma endpoint'inde `konteyner_id` zorunlu alan olarak doğrulanmalı.

**D. Şikayet fotoğraf sayısı sınırı**
Veritabanında sınır yok, teorik olarak sınırsız fotoğraf eklenebilir.
→ Backend'de: dosya yükleme middleware'inde (örn. `multer`) maksimum sayı belirlenmeli (örn. 3-5 adet).

**E. Telefon formatı standardizasyonu**
`VARCHAR(20)` serbest metin — `05325551122`, `+905325551122`, `0 532 555 11 22` gibi farklı formatlar hepsi teknik olarak geçerli, ama login/arama sorunu çıkarır.
→ Backend'de: kayıt öncesi tüm telefonlar **tek bir standart formata** normalize edilmeli (örn. hep `05XXXXXXXXX`, 11 hane). Tüm çavuş/şoför/şirket/vatandaş kayıtlarında aynı normalizasyon fonksiyonu kullanılmalı.

**F. Soft-delete sonrası unique alan tekrar kullanımı**
`telefon`, `mail`, `plaka`, `konteyner_kodu` gibi alanlar UNIQUE. Bir kayıt `aktif_mi = false` yapılsa bile bu değerler veritabanında dolu kalır — aynı telefonla yeni kayıt açmak isterseniz UNIQUE hatası alırsınız.
→ Bu şimdilik kritik değil, ama eğer "pasif kullanıcının telefonu tekrar kullanılabilsin" isteniyorsa ileride partial unique index (`WHERE aktif_mi = true`) eklenmesi gerekecek. Şu an için backend, pasif bir kayıtla aynı telefonu kullanmaya çalışan yeni kayıtları anlamlı bir hata mesajıyla reddetmeli.

---

## 6) İlişki Şeması (Özet)

```
mahalleler ──┬─< cavuslar ──┬─< araclar ──< soforler
             │              │
             └─< konteynerler ─┬─< toplama_kayitlari >─ soforler
                                ├─< sikayetler ─< sikayet_fotograflari
                                └─< geri_donusum_talepleri >─ sirketler
```
(`─<` = "birden çoğu var", `>─` = "birine bağlı")

- Bir **mahalle**: 1 çavuş, birden çok konteyner
- Bir **çavuş**: birden çok araç ve konteyner sorumluluğu
- Bir **araç**: tam olarak 1 şoför
- Bir **konteyner**: birden çok toplama kaydı, birden çok şikayet, birden çok geri dönüşüm talebi
- Bir **şirket**: birden çok geri dönüşüm talebi

---

## 7) Silme Davranışları (ON DELETE) Özeti

| Tablo.kolon | Davranış | Neden |
|---|---|---|
| `cavuslar.mahalle_id` | `RESTRICT` | Çavuşu olan mahalle silinemez |
| `konteynerler.mahalle_id` | `RESTRICT` | Konteyneri olan mahalle silinemez |
| `araclar.cavus_id`, `soforler.*_id`, `konteynerler.cavus_id` | `SET NULL` | Çavuş/araç silinse bile bağlı kayıt kaybolmaz |
| `toplama_kayitlari.konteyner_id`, `.sofor_id` | `SET NULL` | Geçmiş toplama kaydı, raporlama için korunur |
| `sikayetler.konteyner_id` | `SET NULL` | Geçmiş şikayet korunur |
| `geri_donusum_talepleri.sirket_id`, `.konteyner_id` | `SET NULL` | Geçmiş talep korunur |
| `sikayet_fotograflari.sikayet_id` | `CASCADE` | Şikayet silinirse fotoğrafları da silinir (mantıklı — fotoğrafın şikayetsiz anlamı yok) |

**Genel prensip:** Sistemde neredeyse hiçbir şey fiziksel olarak silinmiyor; `aktif_mi` alanıyla soft-delete yapılıyor. `RESTRICT`/`SET NULL` kombinasyonu, geçmiş kayıtların (toplama, şikayet, talep) raporlama amacıyla her zaman korunmasını sağlıyor.

---

## 8) `updated_at` Otomatik Güncelleme

Her tabloda `created_at` ve `updated_at` var. `created_at` yalnızca INSERT anında `DEFAULT CURRENT_TIMESTAMP` ile set edilir. `updated_at` ise bir **trigger** (`set_updated_at()` fonksiyonu) ile her UPDATE işleminde otomatik güncellenir — backend'in `updated_at` alanını manuel set etmesine **gerek yok**, hatta set etmeye çalışırsa trigger zaten üzerine yazar.

---

## 9) Kurulum Sırası (Bağımlılık Nedeniyle Önemli)

Dosya zaten doğru sırada yazıldığı için tek seferde çalıştırmanız yeterli, ama başka bir ortamda elle bölüp çalıştırırsanız şu sıraya uyun:

```
1. DROP IF EXISTS (varsa eski şema temizlenir)
2. ENUM tipler
3. mahalleler → yoneticiler → cavuslar → sirketler
4. araclar → soforler
5. konteynerler
6. toplama_kayitlari
7. sikayetler → sikayet_fotograflari
8. geri_donusum_talepleri
9. Indexler
10. Trigger fonksiyonu ve trigger'lar
11. Örnek veri (opsiyonel, sadece dev/test ortamında)
```

---

## 10) Hızlı Referans: Hangi Tabloda Login Var, Hangi Alan Zorunlu

| Tablo | Login alanı | Zorunlu (NOT NULL) benzersiz alanlar |
|---|---|---|
| `yoneticiler` | `kullanici_adi` | `kullanici_adi` |
| `cavuslar` | `telefon` | `telefon`, `mahalle_id` |
| `soforler` | `telefon` | `telefon` |
| `sirketler` | `telefon` veya `mail` | `mail`, `telefon` |

---

Sorularınız olursa veya bir tabloyu/kuralı daha detaylı açıklamamı isterseniz belirtin.
