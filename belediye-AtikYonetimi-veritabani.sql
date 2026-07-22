-- =========================================================
-- ATIK YÖNETİMİ VERİTABANI v4
-- Güncel Eksik ve Düzenleme Listesi'ndeki maddeler uygulanmıştır:
--   [Madde 1]  Placeholder şifreler -> gerçek bcrypt ($2b$) hash
--   [Madde 2]  cavuslar.unique_cavus_ad_soyad kaldırıldı
--   [Madde 3]  DROP IF EXISTS bloğu eklendi (tekrar çalıştırılabilir)
--   [Madde 4]  toplama_kayitlari CHECK constraint güçlendirildi
--   [Madde 5]  Günlük tekil toplama index'i (opsiyonel, karar gerektirir)
--   [Madde 8]  geri_donusum_talepleri: sirket_id <-> gonderen_tipi CHECK
--
-- NOT (Madde 13): Üretim ortamında bu dosyanın schema / seed / test
-- olarak 3 ayrı dosyaya bölünmesi önerilir (01_schema.sql, 02_seed.sql,
-- 03_test_queries.sql). Bu tek dosyada bölümler açıkça ayrılmıştır,
-- isterseniz aşağıdaki "-- ====" başlıklarından bölerek 3 dosyaya
-- kolayca ayırabilirsiniz.
-- =========================================================


-- =========================================================
-- 00_DROP_IF_EXISTS.sql   [Madde 3]
-- Geliştirme sürecinde dosya tekrar tekrar çalıştırılabilsin diye
-- her şey en baştan temizleniyor. Bağımlılık sırasına dikkat edin:
-- önce tablolar (CASCADE ile bağlı objeler de gider), sonra tipler.
-- =========================================================
DROP TABLE IF EXISTS sikayet_fotograflari CASCADE;
DROP TABLE IF EXISTS geri_donusum_talepleri CASCADE;
DROP TABLE IF EXISTS sikayetler CASCADE;
DROP TABLE IF EXISTS toplama_kayitlari CASCADE;
DROP TABLE IF EXISTS konteynerler CASCADE;
DROP TABLE IF EXISTS soforler CASCADE;
DROP TABLE IF EXISTS araclar CASCADE;
DROP TABLE IF EXISTS sirketler CASCADE;
DROP TABLE IF EXISTS cavuslar CASCADE;
DROP TABLE IF EXISTS yoneticiler CASCADE;
DROP TABLE IF EXISTS mahalleler CASCADE;

DROP FUNCTION IF EXISTS set_updated_at() CASCADE;

DROP TYPE IF EXISTS sikayet_kategorisi CASCADE;
DROP TYPE IF EXISTS sikayet_durumu CASCADE;
DROP TYPE IF EXISTS toplama_durumu CASCADE;
DROP TYPE IF EXISTS sirket_onay_durumu CASCADE;
DROP TYPE IF EXISTS talep_durumu CASCADE;
DROP TYPE IF EXISTS gonderen_tipi CASCADE;
DROP TYPE IF EXISTS atik_turu CASCADE;


-- =========================================================
-- 01_ENUM_TIPLER.sql
-- Tüm ENUM (sabit liste) tipleri burada tanımlanıyor.
-- Tablolar bu tiplere referans veriyor.
-- =========================================================

-- Atık türü (kati_atik / geri_donusum)
CREATE TYPE atik_turu AS ENUM ('kati_atik', 'geri_donusum');

-- gonderen_tipi: geri dönüşüm talebini vatandaş, yönetici veya
-- şirket oluşturabilir.
CREATE TYPE gonderen_tipi AS ENUM ('vatandas', 'yonetici', 'sirket');

-- Geri dönüşüm talebi durumu ile şirket onay durumu farklı iki enum.
-- Talep durumu daha zengin bir yaşam döngüsüne sahip
-- (tamamlandi / iptal_edildi dahil).
CREATE TYPE talep_durumu AS ENUM (
    'bekliyor',
    'onaylandi',
    'reddedildi',
    'tamamlandi',
    'iptal_edildi'
);

-- Şirket onay durumu ayrı bir enum.
-- 'pasif' değeri, onaylanmış ama sonradan sistemden çıkarılan
-- şirketler için.
CREATE TYPE sirket_onay_durumu AS ENUM (
    'bekliyor',
    'onaylandi',
    'reddedildi',
    'pasif'
);

-- toplanan_konteynerler ve atlanilan_konteynerler tabloları tek bir
-- toplama_kayitlari tablosunda birleştiriliyor. Bu enum, kaydın
-- "toplandı mı yoksa atlandı mı" olduğunu belirtiyor.
CREATE TYPE toplama_durumu AS ENUM ('toplandi', 'atlanildi');

-- Şikayet durumu takibi için.
CREATE TYPE sikayet_durumu AS ENUM (
    'bekliyor',
    'inceleniyor',
    'cozuldu',
    'reddedildi'
);

-- Şikayet kategorisi artık serbest metin (VARCHAR) değil, sabit bir
-- liste (ENUM). sikayet_turu (atik_turu) ile karıştırılmasın:
--   sikayet_turu       -> hangi atık türüyle ilgili (kati_atik / geri_donusum)
--   sikayet_kategorisi -> şikayetin niteliği (dolu, kırık, koku vs.)
CREATE TYPE sikayet_kategorisi AS ENUM (
    'konteyner_dolu',
    'konteyner_kirik',
    'kotu_koku',
    'cop_tasmasi',
    'zamaninda_toplanmadi',
    'diger'
);


-- =========================================================
-- 02_ANA_TABLOLAR.sql
-- mahalleler / yoneticiler / cavuslar / sirketler
-- =========================================================

-- ---------------------------------------------------------
-- 1) MAHALLELER
-- ---------------------------------------------------------
CREATE TABLE mahalleler (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(100) NOT NULL,
    ilce VARCHAR(100) DEFAULT 'Onikişubat',
    il VARCHAR(100) DEFAULT 'Kahramanmaraş',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_mahalle_ad UNIQUE (ad)
);

-- ---------------------------------------------------------
-- 2) YÖNETİCİLER
-- ---------------------------------------------------------
CREATE TABLE yoneticiler (
    id SERIAL PRIMARY KEY,
    kullanici_adi VARCHAR(50) UNIQUE NOT NULL,
    sifre VARCHAR(255) NOT NULL,
    ad_soyad VARCHAR(100),
    mail VARCHAR(100) UNIQUE,
    telefon VARCHAR(20) UNIQUE,
    aktif_mi BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------
-- 3) ÇAVUŞLAR
-- 🔧 [Madde 2] unique_cavus_ad_soyad constraint'i KALDIRILDI.
-- Gerekçe: Aynı ad-soyada sahip iki farklı kişi olabilir, login
-- zaten telefon ile yapılıyor. Unique kalması gereken alanlar:
-- telefon (login için) ve mahalle_id (her mahalleye tek çavuş).
-- ---------------------------------------------------------
CREATE TABLE cavuslar (
    id SERIAL PRIMARY KEY,
    ad_soyad VARCHAR(100) NOT NULL,
    telefon VARCHAR(20) UNIQUE NOT NULL,
    sifre VARCHAR(255) NOT NULL,
    mahalle_id INT NOT NULL REFERENCES mahalleler(id) ON DELETE RESTRICT,
    aktif_mi BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_cavus_mahalle UNIQUE (mahalle_id)
);

-- ---------------------------------------------------------
-- 4) ŞİRKETLER (Geri Dönüşüm)
-- ---------------------------------------------------------
CREATE TABLE sirketler (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(150) NOT NULL,
    adres TEXT,
    mail VARCHAR(100) UNIQUE NOT NULL,
    telefon VARCHAR(20) UNIQUE NOT NULL,
    sifre VARCHAR(255) NOT NULL,
    onay_durumu sirket_onay_durumu NOT NULL DEFAULT 'bekliyor',
    aktif_mi BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- =========================================================
-- 03_ARAC_VE_SOFOR.sql
-- araclar / soforler
-- =========================================================

-- ---------------------------------------------------------
-- 1) ARAÇLAR
-- ---------------------------------------------------------
CREATE TABLE araclar (
    id SERIAL PRIMARY KEY,
    plaka VARCHAR(20) UNIQUE NOT NULL,
    arac_turu atik_turu NOT NULL,
    cavus_id INT REFERENCES cavuslar(id) ON DELETE SET NULL,
    aktif_mi BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------
-- 2) ŞOFÖRLER
-- Bir şoförü başka bir araca atamak için:
--   UPDATE soforler SET arac_id = <yeni_arac_id> WHERE id = <sofor_id>;
--
-- NOT [Madde 6]: Şoförün yalnızca kendi aracının türüyle aynı türdeki
-- konteynerleri toplayabilmesi veritabanında değil, backend'de
-- kontrol edilmelidir (arac_turu = konteyner.tur eşleşmesi).
-- ---------------------------------------------------------
CREATE TABLE soforler (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(50) NOT NULL,
    soyad VARCHAR(50) NOT NULL,
    telefon VARCHAR(20) UNIQUE NOT NULL,
    sifre VARCHAR(255) NOT NULL,
    arac_id INT UNIQUE REFERENCES araclar(id) ON DELETE SET NULL,
    cavus_id INT REFERENCES cavuslar(id) ON DELETE SET NULL,
    aktif_mi BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- =========================================================
-- 04_KONTEYNERLER.sql
--
-- NOT [Madde 7]: Çavuşun yalnızca kendi mahallesindeki konteynerleri
-- yönetmesi veritabanında değil, backend'de kontrol edilmelidir.
-- Çavuş konteyner eklerken mahalle_id, Flutter'dan gelen değer değil,
-- backend token'ından okunan çavuşun kendi mahalle_id'si olmalı.
-- =========================================================
CREATE TABLE konteynerler (
    id SERIAL PRIMARY KEY,
    konteyner_kodu VARCHAR(50) UNIQUE NOT NULL,
    tur atik_turu NOT NULL,
    mahalle_id INT NOT NULL REFERENCES mahalleler(id) ON DELETE RESTRICT,
    cavus_id INT REFERENCES cavuslar(id) ON DELETE SET NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    aktif_mi BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- =========================================================
-- 05_TOPLAMA_KAYITLARI.sql
-- =========================================================

-- 🔧 [Madde 4] CHECK constraint güçlendirildi:
--   durum = 'toplandi'  -> sebep VE diger_aciklama boş OLMALI
--   durum = 'atlanildi' -> sebep dolu OLMALI
CREATE TABLE toplama_kayitlari (
    id SERIAL PRIMARY KEY,
    konteyner_id INT REFERENCES konteynerler(id) ON DELETE SET NULL,
    sofor_id INT REFERENCES soforler(id) ON DELETE SET NULL,
    durum toplama_durumu NOT NULL,
    sebep VARCHAR(255),          -- yalnızca durum = 'atlanildi' iken dolu
    diger_aciklama TEXT,         -- sebep 'Diğer' seçilirse burası dolar
    tarih_saat TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- 🔧 [Madde 4] Eski constraint (chk_atlanilan_sebep_dolu) yerine
    -- iki yönlü kontrol: toplandı iken sebep/açıklama dolu olamaz,
    -- atlanıldı iken sebep boş olamaz.
    CONSTRAINT chk_toplama_durum_sebep
        CHECK (
            (durum = 'toplandi' AND sebep IS NULL AND diger_aciklama IS NULL)
            OR
            (durum = 'atlanildi' AND sebep IS NOT NULL)
        )
);

-- 🔧 [Madde 5] KARAR GEREKTİRİR: Aynı konteynerin aynı gün birden
-- fazla kez "toplandı" olarak kaydedilip kaydedilemeyeceği proje
-- işleyişine göre netleştirilmeli. Eğer günde SADECE BİR kez
-- toplanabilecekse aşağıdaki index'in yorumunu kaldırıp aktif edin:
--
-- CREATE UNIQUE INDEX unique_konteyner_gunluk_toplama
--     ON toplama_kayitlari (konteyner_id, DATE(tarih_saat))
--     WHERE durum = 'toplandi';
--
-- Gün içinde birden fazla toplama yapılabilecekse bu index EKLENMEMELİ
-- (varsayılan olarak devre dışı bırakılmıştır).


-- =========================================================
-- 06_SIKAYETLER.sql
--
-- NOT [Madde 9]: konteyner_id veritabanında nullable bırakılmıştır
-- (geçmiş şikayetlerin, konteyner silinse bile korunması için). Proje
-- kuralı gereği "misafir kullanıcı konteyner id girmeden şikayet
-- oluşturamaz" kontrolü backend'de yapılmalıdır.
--
-- NOT [Madde 10]: Şikayet başına maksimum fotoğraf sayısı (örn. 3-5)
-- veritabanında değil, backend'de (multer vb.) sınırlandırılmalıdır.
-- =========================================================

-- ---------------------------------------------------------
-- 1) ŞİKAYETLER
-- ---------------------------------------------------------
CREATE TABLE sikayetler (
    id SERIAL PRIMARY KEY,
    vatandas_ad_soyad VARCHAR(100) NOT NULL,
    vatandas_telefon VARCHAR(20) NOT NULL,
    konteyner_id INT REFERENCES konteynerler(id) ON DELETE SET NULL,
    sikayet_turu atik_turu NOT NULL,
    sikayet_kategorisi sikayet_kategorisi NOT NULL DEFAULT 'diger',
    sikayet_metni TEXT NOT NULL,
    durum sikayet_durumu NOT NULL DEFAULT 'bekliyor',
    yonetici_notu TEXT,
    cozulme_tarihi TIMESTAMPTZ,
    tarih_saat TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------
-- 2) ŞİKAYET FOTOĞRAFLARI
-- ---------------------------------------------------------
CREATE TABLE sikayet_fotograflari (
    id SERIAL PRIMARY KEY,
    sikayet_id INT NOT NULL REFERENCES sikayetler(id) ON DELETE CASCADE,
    foto_url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- =========================================================
-- 07_GERI_DONUSUM_TALEPLERI.sql
-- =========================================================

-- 🔧 [Madde 8] sirket_id <-> gonderen_tipi tutarlılığı artık CHECK
-- constraint ile veritabanı seviyesinde garanti altına alınıyor:
--   gonderen_tipi = 'sirket'   -> sirket_id DOLU olmalı
--   gonderen_tipi = 'vatandas' -> sirket_id BOŞ olmalı
--   gonderen_tipi = 'yonetici' -> sirket_id boş veya opsiyonel (serbest)
CREATE TABLE geri_donusum_talepleri (
    id SERIAL PRIMARY KEY,
    sirket_id INT REFERENCES sirketler(id) ON DELETE SET NULL,
    konteyner_id INT REFERENCES konteynerler(id) ON DELETE SET NULL,
    gonderen_tipi gonderen_tipi NOT NULL,
    gonderen_ad VARCHAR(100) NOT NULL,
    gonderen_telefon VARCHAR(20) NOT NULL,
    atik_turu atik_turu NOT NULL DEFAULT 'geri_donusum',
    talep_basligi VARCHAR(150),
    talep_aciklamasi TEXT,
    tahmini_miktar NUMERIC(10, 2),   -- kg cinsinden tahmini miktar
    adres TEXT,
    tarih_saat TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    durum talep_durumu NOT NULL DEFAULT 'bekliyor',
    yonetici_notu TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- 🆕 [Madde 8] gonderen_tipi = 'sirket' iken sirket_id zorunlu,
    -- gonderen_tipi = 'vatandas' iken sirket_id boş olmalı.
    -- 'yonetici' için serbest bırakıldı (boş veya dolu olabilir).
    CONSTRAINT chk_talep_sirket_id_tutarliligi
        CHECK (
            (gonderen_tipi = 'sirket' AND sirket_id IS NOT NULL)
            OR
            (gonderen_tipi = 'vatandas' AND sirket_id IS NULL)
            OR
            (gonderen_tipi = 'yonetici')
        )
);


-- =========================================================
-- 08_INDEXLER.sql
-- =========================================================

-- Konteynerler
CREATE INDEX idx_konteyner_koordinat ON konteynerler(latitude, longitude);
CREATE INDEX idx_konteyner_cavus ON konteynerler(cavus_id);
CREATE INDEX idx_konteyner_mahalle ON konteynerler(mahalle_id);
CREATE INDEX idx_konteyner_tur ON konteynerler(tur);

-- Şoförler / Çavuşlar / Araçlar
CREATE INDEX idx_sofor_cavus ON soforler(cavus_id);
CREATE INDEX idx_sofor_arac ON soforler(arac_id);
CREATE INDEX idx_cavus_mahalle ON cavuslar(mahalle_id);
CREATE INDEX idx_arac_cavus ON araclar(cavus_id);

-- Toplama kayıtları
CREATE INDEX idx_toplama_tarih ON toplama_kayitlari(tarih_saat);
CREATE INDEX idx_toplama_sofor ON toplama_kayitlari(sofor_id);
CREATE INDEX idx_toplama_konteyner ON toplama_kayitlari(konteyner_id);
CREATE INDEX idx_toplama_durum ON toplama_kayitlari(durum);

-- Şikayetler
CREATE INDEX idx_sikayet_tarih ON sikayetler(tarih_saat);
CREATE INDEX idx_sikayet_durum ON sikayetler(durum);
CREATE INDEX idx_sikayet_konteyner ON sikayetler(konteyner_id);
CREATE INDEX idx_sikayet_foto_sikayet ON sikayet_fotograflari(sikayet_id);

-- Geri dönüşüm talepleri
CREATE INDEX idx_gdtalep_durum ON geri_donusum_talepleri(durum);
CREATE INDEX idx_gdtalep_tarih ON geri_donusum_talepleri(tarih_saat);
CREATE INDEX idx_gdtalep_sirket ON geri_donusum_talepleri(sirket_id);


-- =========================================================
-- 09_UPDATED_AT_TRIGGER.sql
-- "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP" sadece INSERT
-- anında değer atar. Bir satır UPDATE edildiğinde updated_at'in
-- otomatik yenilenmesi için trigger gerekir. Bu bölüm, updated_at
-- kolonu olan HER tabloya otomatik güncelleme trigger'ı ekliyor.
-- =========================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_mahalleler_updated_at
    BEFORE UPDATE ON mahalleler
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_yoneticiler_updated_at
    BEFORE UPDATE ON yoneticiler
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_cavuslar_updated_at
    BEFORE UPDATE ON cavuslar
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_sirketler_updated_at
    BEFORE UPDATE ON sirketler
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_araclar_updated_at
    BEFORE UPDATE ON araclar
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_soforler_updated_at
    BEFORE UPDATE ON soforler
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_konteynerler_updated_at
    BEFORE UPDATE ON konteynerler
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_toplama_kayitlari_updated_at
    BEFORE UPDATE ON toplama_kayitlari
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_sikayetler_updated_at
    BEFORE UPDATE ON sikayetler
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_gdtalepleri_updated_at
    BEFORE UPDATE ON geri_donusum_talepleri
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =========================================================
-- 10_ORNEK_VERI.sql
--
-- 🔧 [Madde 1] Aşağıdaki 'sifre' değerleri artık GERÇEK bcrypt hash'ler
-- ($2b$ formatı, 12 round), placeholder DEĞİLDİR. Node.js bcrypt
-- kütüphanesiyle (bcrypt.compare) doğrudan doğrulanabilir.
--
--   Kullanıcı  | Düz metin şifre | Hash
--   -----------|------------------|---------------------------------------------------------
--   yönetici   | admin123         | $2b$12$c2WZvTqKV8d58y7XeV/8BOo8n9Zd6XDg.tfyHpEQ4ANZduJ/hDt3y
--   çavuş      | cavus123         | $2b$12$Zjbe1UzgEQEC513Qcx4aiugJXdIU6jGBDfjYy.8kXAtKvA81lNUua
--   şoför 1    | sofor123         | $2b$12$TIhJeBVGqieW70p8fTpUguXggqIL8oh4FVLR1Z26JhSJgHQVAuU4u
--   şoför 2    | sofor123         | $2b$12$7REE57hsjndu0yTNB3QyR.9OJ4NPNJztjFfQhbJ9Q2NMck.CciP72
--   şirket     | sirket123        | $2b$12$mp8Ot5mj4mtFf/K1a3PGNu613N20QCypH3kwnNl8iYlQOx1c6TTEm
--
-- ⚠️ Bu hash'ler yalnızca GELİŞTİRME/TEST ortamı içindir. Gerçek
-- (production) kullanıcı kayıtlarında şifre backend tarafında
-- kullanıcının girdiği değerden bcrypt ile üretilmelidir; bu sabit
-- test şifrelerini production'a taşımayın.
-- =========================================================

-- ---------------------------------------------------------
-- 1) Mahalleler (Onikişubat, Kahramanmaraş)
-- ---------------------------------------------------------
INSERT INTO mahalleler (ad) VALUES
('Haydarbey'),
('Tekerek'),
('Üngüt'),
('Binevler'),
('Yirmiikigün'),
('Vadi'),
('Cumhuriyet'),
('Şazibey');

INSERT INTO mahalleler (ad)
SELECT ad FROM (VALUES
    ('Abdülhamid Han'), ('Avşar'), ('Ağcalı'), ('Akçakoyunlu'), ('Akif İnan'),
    ('Altınova'), ('Avcılar'), ('Avgasır'), ('Ayşepınarı'), ('Barbaros'),
    ('Beşbağlar'), ('Beşen'), ('Boğaziçi'), ('Bulutoğlu'), ('Büyüksır'),
    ('Ceyhan'), ('Cüceli'), ('Çağırgan'), ('Çağlayan'), ('Çakırdere'),
    ('Çakırlar'), ('Çamlıbel'), ('Çamlıca'), ('Çamlık'), ('Çevrepınar'),
    ('Çokran'), ('Çukurhisar'), ('Dadağlı'), ('Demrek'), ('Dereboğazı'),
    ('Döngel'), ('Döngele'), ('Dönüklü'), ('Dumlupınar'), ('Ertuğrul Gazi'),
    ('Fatih'), ('Fatmalı'), ('Gayberli'), ('Gedemen'), ('Gölpınar'),
    ('Hacıağlar'), ('Hacıbayramveli'), ('Hacıbudak'), ('Hacıibrahimuşağı'),
    ('Hacılar'), ('Hacımustafa'), ('Hacınınoğlu'), ('Hartlap'), ('Hasancıklı'),
    ('Hayrullah'), ('Hürriyet'), ('Ilıca'), ('İsmailli'), ('İstiklal'),
    ('Kale'), ('Kalekaya'), ('Kapıkaya'), ('Karacaoğlan'), ('Karadere'),
    ('Karamanlı'), ('Kavlaklı'), ('Kaynar'), ('Kazım Karabekir'), ('Kerimli'),
    ('Kertmen'), ('Kılavuzlu'), ('Kısıklı'), ('Kızıldamlar'), ('Kızılseki'),
    ('Kozcağız'), ('Köseli'), ('Köşürge'), ('Kumarlı'), ('Kumaşır'),
    ('Kurtlar'), ('Kurucaova'), ('Küçüksır'), ('Kümperli'), ('Kürtül'),
    ('Maarif'), ('Mağralı'), ('Maksutlu'), ('Malik Ejder'), ('Mercimektepe'),
    ('Mevlana'), ('Mimar Sinan'), ('Mollagürani'), ('Muratlı'), ('Necip Fazıl'),
    ('Orhangazi'), ('Oruç Reis'), ('Osman Gazi'), ('Önsen'), ('Öşlü'),
    ('Öztürk'), ('Payamlı'), ('Piri Reis'), ('Rahmacılar'), ('Reyhanlı'),
    ('Saçaklızade'), ('Sadıklı'), ('Sarıçukur'), ('Sarıgüzel'), ('Sarımollalı'),
    ('Saygılı'), ('Selçuklu'), ('Selimiye'), ('Serintepe'), ('Suçatı'),
    ('Suluyayla'), ('Süleymanlı'), ('Süleymanşah'), ('Şahinkayası'),
    ('Şehit Abdullah Çavuş'), ('Şehitevliya'), ('Tavşantepe'), ('Tekir'),
    ('Topçalı'), ('Yamaçtepe'), ('Yenicekale'), ('Yenidemir'), ('Yeniköy'),
    ('Yeniyapan'), ('Yeşilyurt'), ('Yolyanı'), ('Yunusemre'), ('Yusuflar'),
    ('Yürükselim'), ('Zeytindere')
) AS v(ad)
WHERE NOT EXISTS (SELECT 1 FROM mahalleler m WHERE m.ad = v.ad);

-- ---------------------------------------------------------
-- 2) Yönetici  (şifre: admin123)
-- ---------------------------------------------------------
INSERT INTO yoneticiler (kullanici_adi, sifre, ad_soyad, mail, telefon) VALUES
('denizk', '$2b$12$c2WZvTqKV8d58y7XeV/8BOo8n9Zd6XDg.tfyHpEQ4ANZduJ/hDt3y', 'Deniz Kaya', 'denizk@onikisubat.bel.tr', '05001112233');

-- ---------------------------------------------------------
-- 3) Çavuş  (şifre: cavus123)
-- ---------------------------------------------------------
INSERT INTO cavuslar (ad_soyad, telefon, sifre, mahalle_id) VALUES
('Selin Yılmaz', '05052223344', '$2b$12$Zjbe1UzgEQEC513Qcx4aiugJXdIU6jGBDfjYy.8kXAtKvA81lNUua', 1);

-- ---------------------------------------------------------
-- 4) Şirket (onaylanmış)  (şifre: sirket123)
-- ---------------------------------------------------------
INSERT INTO sirketler (ad, adres, mail, telefon, sifre, onay_durumu) VALUES
('Çevik Geri Dönüşüm A.Ş.', 'Tekerek Mah. No:12 Onikişubat', 'bilgi@cevikgeridonusum.com', '03441112233', '$2b$12$mp8Ot5mj4mtFf/K1a3PGNu613N20QCypH3kwnNl8iYlQOx1c6TTEm', 'onaylandi');

-- ---------------------------------------------------------
-- 5) Araçlar
-- ---------------------------------------------------------
INSERT INTO araclar (plaka, arac_turu, cavus_id) VALUES
('46 ABC 123', 'kati_atik', 1),
('46 XYZ 789', 'geri_donusum', 1);

-- ---------------------------------------------------------
-- 6) Şoförler  (şifre: sofor123)
-- ---------------------------------------------------------
INSERT INTO soforler (ad, soyad, telefon, sifre, arac_id, cavus_id) VALUES
('Berke', 'Karaman', '05053334455', '$2b$12$TIhJeBVGqieW70p8fTpUguXggqIL8oh4FVLR1Z26JhSJgHQVAuU4u', 1, 1),
('Deniz', 'Kılınç', '05054445566', '$2b$12$7REE57hsjndu0yTNB3QyR.9OJ4NPNJztjFfQhbJ9Q2NMck.CciP72', 2, 1);

-- ---------------------------------------------------------
-- 7) Konteynerler
-- ---------------------------------------------------------
INSERT INTO konteynerler (konteyner_kodu, tur, mahalle_id, cavus_id, latitude, longitude) VALUES
('KNT-0001', 'kati_atik', 1, 1, 37.58581234, 36.91451234),
('KNT-0002', 'geri_donusum', 1, 1, 37.58604321, 36.91504321);

-- ---------------------------------------------------------
-- 8) Vatandaş şikayeti
-- ---------------------------------------------------------
INSERT INTO sikayetler (vatandas_ad_soyad, vatandas_telefon, konteyner_id, sikayet_turu, sikayet_kategorisi, sikayet_metni, durum) VALUES
('mehmet demir', '05329998877', 1, 'kati_atik', 'cop_tasmasi', 'Konteyner tamamen dolmuş ve çöpler yola taşmış durumda.', 'bekliyor');

-- 8b) Şikayete ait örnek fotoğraf
INSERT INTO sikayet_fotograflari (sikayet_id, foto_url) VALUES
(1, 'https://ornek-depolama.com/sikayet-fotolari/1-a.jpg');

-- ---------------------------------------------------------
-- 9) Geri dönüşüm talebi (vatandaştan)
-- 🔧 [Madde 8] gonderen_tipi = 'vatandas' olduğu için sirket_id BOŞ.
-- ---------------------------------------------------------
INSERT INTO geri_donusum_talepleri (sirket_id, konteyner_id, gonderen_tipi, gonderen_ad, gonderen_telefon, atik_turu, talep_basligi, durum) VALUES
(NULL, 2, 'vatandas', 'Elif Onat', '05329998877', 'geri_donusum', 'Konteyner dolu, alınması gerekiyor', 'bekliyor');

-- 9b) Şirketten gelen, konteynere bağlı olmayan talep
-- 🔧 [Madde 8] gonderen_tipi = 'sirket' olduğu için sirket_id DOLU.
INSERT INTO geri_donusum_talepleri (sirket_id, gonderen_tipi, gonderen_ad, gonderen_telefon, atik_turu, talep_basligi, talep_aciklamasi, tahmini_miktar, adres, durum) VALUES
(1, 'sirket', 'Çevik Geri Dönüşüm A.Ş.', '03441112233', 'geri_donusum', 'Depo temizliği kağıt/karton', 'Depomuzda biriken kağıt/karton atığın alınmasını rica ediyoruz.', 250.50, 'Tekerek Mah. No:12 Onikişubat', 'bekliyor');


-- =========================================================
-- 11_TEST_SORGULARI.sql   [Madde 13]
-- Bu bölüm yalnızca geliştirme sırasında kontrol amaçlıdır; üretim
-- schema dosyasından ayrı tutulması önerilir.
-- =========================================================
SELECT * FROM soforler;
SELECT * FROM araclar;
SELECT * FROM konteynerler;
SELECT * FROM sikayetler;
SELECT * FROM geri_donusum_talepleri;