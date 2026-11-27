var TZ = 'GMT+3';
var TOKEN_SURESI_SN = 21600;
var Q = String.fromCharCode(34);
var APOS = String.fromCharCode(39);
var NL = String.fromCharCode(10);

var VARSAYILAN_SAAT_AYARLARI = {
  sabahBinisBas: '06:30',
  sabahBinisBit: '07:30',
  sabahInisBas: '07:30',
  sabahInisBit: '08:00',
  pztAksamBas: '17:00',
  digerAksamBas: '15:00',
  aksamBit: '18:00',
  haftaSonuKapali: true,
  bildirimSabah: '07:00',
  bildirimNobetci: '07:00',
  bildirimPztAksam: '17:00',
  bildirimSaliAksam: '16:00',
  bildirimDigerAksam: '15:20',
  bildirimAksamInis: '18:00'
};

function yoneticiSifreleriniKur() {
  var props = PropertiesService.getScriptProperties();
  if (!props.getProperty('SIFRE_MUDUR')) props.setProperty('SIFRE_MUDUR', 'balsuyu.mudur');
  if (!props.getProperty('SIFRE_MDYRD')) props.setProperty('SIFRE_MDYRD', 'balsuyu.mdyrd');
  if (!props.getProperty('SIFRE_SISTEM')) props.setProperty('SIFRE_SISTEM', 'arslanoglu123');
  if (!props.getProperty('SAAT_AYARLARI_JSON')) {
    props.setProperty('SAAT_AYARLARI_JSON', JSON.stringify(VARSAYILAN_SAAT_AYARLARI));
  }
  driveKlasorBulVeyaOlustur(DriveApp.getRootFolder(), 'Balsuyu_MTAL_Resmi_Raporlar');
  guvenlikTetikleyicileriniKur();
  Logger.log('Kurulum, Drive yetkilendirmesi ve 08:05 / 18:05 güvenlik tetikleyicileri tamamlandı.');
}

function guvenlikTetikleyicileriniKur() {
  var mevcutlar = ScriptApp.getProjectTriggers();
  for (var i = 0; i < mevcutlar.length; i++) {
    var fn = mevcutlar[i].getHandlerFunction();
    if (fn === 'otomatikGuvenlikKontroluSabah' || fn === 'otomatikGuvenlikKontroluAksam') {
      ScriptApp.deleteTrigger(mevcutlar[i]);
    }
  }
  ScriptApp.newTrigger('otomatikGuvenlikKontroluSabah')
    .timeBased()
    .everyDays(1)
    .atHour(8)
    .nearMinute(5)
    .inTimezone('Europe/Istanbul')
    .create();

  ScriptApp.newTrigger('otomatikGuvenlikKontroluAksam')
    .timeBased()
    .everyDays(1)
    .atHour(18)
    .nearMinute(5)
    .inTimezone('Europe/Istanbul')
    .create();
}

function yoneticiSifreleriniGetir() {
  var props = PropertiesService.getScriptProperties();
  return {
    'Okul Müdürü': props.getProperty('SIFRE_MUDUR') || 'balsuyu.mudur',
    'Müdür Yardımcısı': props.getProperty('SIFRE_MDYRD') || 'balsuyu.mdyrd',
    'Sistem Yöneticisi (Arslanoğlu)': props.getProperty('SIFRE_SISTEM') || 'arslanoglu123'
  };
}

function saatAyarlariniGetir() {
  var props = PropertiesService.getScriptProperties();
  var raw = props.getProperty('SAAT_AYARLARI_JSON');
  var sonuc = {};
  for (var k in VARSAYILAN_SAAT_AYARLARI) {
    sonuc[k] = VARSAYILAN_SAAT_AYARLARI[k];
  }
  if (raw) {
    try {
      var parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        for (var p in VARSAYILAN_SAAT_AYARLARI) {
          if (parsed[p] !== undefined && parsed[p] !== null && parsed[p] !== '') {
            sonuc[p] = parsed[p];
          }
        }
      }
    } catch (e) {}
  }
  return sonuc;
}

function saatMetniDakikaya(saatStr, varsayilanDak) {
  var m = (saatStr || '').toString().trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return varsayilanDak;
  var h = parseInt(m[1], 10);
  var d = parseInt(m[2], 10);
  if (isNaN(h) || isNaN(d) || h < 0 || h > 23 || d < 0 || d > 59) return varsayilanDak;
  return (h * 60) + d;
}

function saatMetniGecerliMi(saatStr) {
  var m = (saatStr || '').toString().trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return false;
  var h = parseInt(m[1], 10);
  var d = parseInt(m[2], 10);
  return h >= 0 && h <= 23 && d >= 0 && d <= 59;
}

function duyuruyuGetir() {
  var raw = PropertiesService.getScriptProperties().getProperty('AKTIF_DUYURU_JSON');
  if (!raw) return null;
  try {
    var d = JSON.parse(raw);
    if (d && d.metin && d.metin.toString().trim() !== '') return d;
  } catch (e) {}
  return null;
}

function sayfaAdiNormalize(ad) {
  return trKucult(ad)
    .replace(/ğ/g, 'g')
    .replace(/ü/g, 'u')
    .replace(/ş/g, 's')
    .replace(/ı/g, 'i')
    .replace(/ö/g, 'o')
    .replace(/ç/g, 'c')
    .replace(/[^a-z0-9]/g, '');
}

function sayfaBul(ss, isimler, yedekIndex) {
  for (var i = 0; i < isimler.length; i++) {
    var sh = ss.getSheetByName(isimler[i]);
    if (sh) return sh;
  }
  var sheets = ss.getSheets();
  var hedefSet = {};
  for (var h = 0; h < isimler.length; h++) {
    hedefSet[sayfaAdiNormalize(isimler[h])] = true;
  }
  for (var s = 0; s < sheets.length; s++) {
    if (hedefSet[sayfaAdiNormalize(sheets[s].getName())]) {
      return sheets[s];
    }
  }
  return (typeof yedekIndex === 'number' && yedekIndex >= 0 && yedekIndex < sheets.length)
    ? sheets[yedekIndex]
    : null;
}

function normalizePlaka(s) {
  return (s || '')
    .toString()
    .split(' ').join('')
    .split(String.fromCharCode(9)).join('')
    .split(NL).join('')
    .toUpperCase()
    .trim();
}

function normalizeTel(t) {
  var clean = (t || '').toString().replace(/[^0-9]/g, '');
  return clean.indexOf('0') === 0 ? clean.substring(1) : clean;
}

function trKucult(s) {
  return (s || '')
    .toString()
    .trim()
    .replace(/İ/g, 'i')
    .replace(/I/g, 'ı')
    .toLowerCase()
    .replace(/\u0307/g, '');
}

function metinHucre(v) {
  var s = (v || '').toString().trim();
  return s ? (APOS + s) : '';
}

function htmlKacis(s) {
  return (s || '')
    .toString()
    .split('&').join('&amp;')
    .split('<').join('&lt;')
    .split('>').join('&gt;')
    .split(Q).join('&quot;');
}

function maskeleSoyad(adSoyad) {
  var ham = (adSoyad || '').toString().trim().split(' ');
  var parcalar = [];
  for (var i = 0; i < ham.length; i++) {
    if (ham[i]) parcalar.push(ham[i]);
  }
  if (parcalar.length <= 1) return adSoyad;
  var soyad = parcalar[parcalar.length - 1];
  var adlar = parcalar.slice(0, parcalar.length - 1).join(' ');
  return adlar + ' ' + (soyad ? soyad.charAt(0).toUpperCase() + '.' : '');
}

function bugunTarihStr() {
  return Utilities.formatDate(new Date(), TZ, 'dd.MM.yyyy');
}

function simdiSaatStr() {
  return Utilities.formatDate(new Date(), TZ, 'HH:mm');
}

function bugunEnGun() {
  return Utilities.formatDate(new Date(), TZ, 'EEE');
}

function haftaSonuMu() {
  var en = bugunEnGun();
  return en === 'Sat' || en === 'Sun';
}

function simdiDakikaToplam() {
  var simdi = new Date();
  var saat = parseInt(Utilities.formatDate(simdi, TZ, 'HH'), 10);
  var dak = parseInt(Utilities.formatDate(simdi, TZ, 'mm'), 10);
  return (saat * 60) + dak;
}

function ogrenciZamanKontrolu(islem, ozelSaatStr) {
  var ayar = saatAyarlariniGetir();
  var en = bugunEnGun();
  if (ayar.haftaSonuKapali !== false && (en === 'Sat' || en === 'Sun')) {
    return {
      izinli: false,
      hata: 'Sistem hafta sonu (Cumartesi - Pazar) kapalıdır.'
    };
  }

  var topDak = (ozelSaatStr && saatMetniGecerliMi(ozelSaatStr))
    ? saatMetniDakikaya(ozelSaatStr, simdiDakikaToplam())
    : simdiDakikaToplam();

  var sbBas = saatMetniDakikaya(ayar.sabahBinisBas, 390);
  var sbBit = saatMetniDakikaya(ayar.sabahBinisBit, 450);
  var siBas = saatMetniDakikaya(ayar.sabahInisBas, 450);
  var siBit = saatMetniDakikaya(ayar.sabahInisBit, 480);
  var akBas = (en === 'Mon')
    ? saatMetniDakikaya(ayar.pztAksamBas, 1020)
    : saatMetniDakikaya(ayar.digerAksamBas, 900);
  var akBasStr = (en === 'Mon') ? ayar.pztAksamBas : ayar.digerAksamBas;
  var akBit = saatMetniDakikaya(ayar.aksamBit, 1080);

  var ust = (islem || '').toString().toUpperCase();

  if (topDak < sbBas || topDak >= akBit) {
    return {
      izinli: false,
      hata: 'Sistem şu an kapalıdır (' + ayar.aksamBit + ' - ' + ayar.sabahBinisBas + ' arası işlem yapılamaz).'
    };
  }

  if (ust.indexOf('SABAH BİNDİ') !== -1 || ust.indexOf('SABAH BINDI') !== -1) {
    if (topDak >= sbBas && topDak < sbBit) {
      return { izinli: true };
    }
    return {
      izinli: false,
      hata: 'Sabah Biniş sadece ' + ayar.sabahBinisBas + ' - ' + ayar.sabahBinisBit + ' saatleri arasında aktiftir.'
    };
  }

  if (ust.indexOf('SABAH İNDİ') !== -1 || ust.indexOf('SABAH INDI') !== -1) {
    if (topDak >= siBas && topDak < siBit) {
      return { izinli: true };
    }
    return {
      izinli: false,
      hata: 'Sabah İniş sadece ' + ayar.sabahInisBas + ' - ' + ayar.sabahInisBit + ' saatleri arasında aktiftir.'
    };
  }

  if (
    ust.indexOf('AKŞAM BİNDİ') !== -1 ||
    ust.indexOf('AKSAM BINDI') !== -1 ||
    ust.indexOf('AKŞAM İNDİ') !== -1 ||
    ust.indexOf('AKSAM INDI') !== -1
  ) {
    if (topDak >= akBas && topDak < akBit) {
      return { izinli: true };
    }
    return {
      izinli: false,
      hata: 'Akşam biniş/iniş bugün sadece ' + akBasStr + ' - ' + ayar.aksamBit + ' saatleri arasında aktiftir.'
    };
  }

  return { izinli: false, hata: 'Bu saatte işlem yapılamaz.' };
}

function idareciYetkiliMi(ogretmenAdi, nobetGunu) {
  var birlesik = trKucult(ogretmenAdi) + ' ' + trKucult(nobetGunu);
  return (
    birlesik.indexOf('müdür') !== -1 ||
    birlesik.indexOf('mudur') !== -1 ||
    birlesik.indexOf('md.') !== -1 ||
    birlesik.indexOf('md ') !== -1 ||
    birlesik.indexOf('yrd') !== -1 ||
    birlesik.indexOf('yardımcı') !== -1 ||
    birlesik.indexOf('yardimci') !== -1 ||
    birlesik.indexOf('idare') !== -1 ||
    birlesik.indexOf('yönetici') !== -1 ||
    birlesik.indexOf('yonetici') !== -1 ||
    birlesik.indexOf('her gün') !== -1 ||
    birlesik.indexOf('her gun') !== -1 ||
    birlesik.indexOf('hergun') !== -1 ||
    birlesik.indexOf('tüm gün') !== -1 ||
    birlesik.indexOf('tum gun') !== -1
  );
}

function nobetGunuUygunMu(nobetGunu, bugunStr) {
  var hedef = trKucult(bugunStr);
  var parcalar = trKucult(nobetGunu).split(/[,\/\-]+/);
  for (var i = 0; i < parcalar.length; i++) {
    if (parcalar[i].trim() === hedef) return true;
  }
  return trKucult(nobetGunu) === hedef;
}

function bugunTurkceGun() {
  var map = {
    Mon: 'Pazartesi',
    Tue: 'Salı',
    Wed: 'Çarşamba',
    Thu: 'Perşembe',
    Fri: 'Cuma',
    Sat: 'Cumartesi',
    Sun: 'Pazar'
  };
  var en = Utilities.formatDate(new Date(), TZ, 'EEE');
  return map[en] || 'Pazartesi';
}

function tarihGunAdiBul(tarihStr) {
  var p = (tarihStr || '').toString().trim().split('.');
  if (p.length !== 3) return '';
  var d = new Date(parseInt(p[2], 10), parseInt(p[1], 10) - 1, parseInt(p[0], 10));
  if (isNaN(d.getTime())) return '';
  var gunler = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];
  return gunler[d.getDay()];
}

function tarihHucreyiNormalizeEt(hamDeger, gorunenDeger) {
  if (hamDeger instanceof Date) return Utilities.formatDate(hamDeger, TZ, 'dd.MM.yyyy');
  return (gorunenDeger || '').toString().trim();
}

function jsonYanit(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function oturumOlustur(oturumObj) {
  var token = Utilities.getUuid();
  CacheService.getScriptCache().put('TOK_' + token, JSON.stringify(oturumObj), TOKEN_SURESI_SN);
  return token;
}

function oturumDogrula(token) {
  if (!token) return null;
  var raw = CacheService.getScriptCache().get('TOK_' + token.toString().trim());
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
}

function nobetSutunlariniBul(rowsN) {
  var pinIdx = 2;
  var mdIdx = 3;
  var telIdx = -1;
  if (rowsN && rowsN.length > 0) {
    var baslik = rowsN[0];
    var pinBulundu = false;
    var mdBulundu = false;
    for (var c = 2; c < baslik.length; c++) {
      var h = trKucult(baslik[c] || '');
      if (
        h.indexOf('pin') !== -1 ||
        h.indexOf('şifre') !== -1 ||
        h.indexOf('sifre') !== -1 ||
        h.indexOf('parola') !== -1 ||
        h.indexOf('kod') !== -1
      ) {
        pinIdx = c;
        pinBulundu = true;
      } else if (
        h.indexOf('müdür') !== -1 ||
        h.indexOf('mudur') !== -1 ||
        h.indexOf('yrd') !== -1 ||
        h.indexOf('yard') !== -1 ||
        h.indexOf('idare') !== -1
      ) {
        mdIdx = c;
        mdBulundu = true;
      } else if (
        h.indexOf('tel') !== -1 ||
        h.indexOf('gsm') !== -1 ||
        h.indexOf('numara') !== -1
      ) {
        telIdx = c;
      }
    }
    if (!pinBulundu && !mdBulundu && rowsN.length > 1) {
      var c2 = (rowsN[1][2] || '').toString().trim();
      var c3 = (rowsN[1][3] || '').toString().trim();
      if (/^\d{4,6}$/.test(c3) && !/^\d{4,6}$/.test(c2)) {
        pinIdx = 3;
        mdIdx = 2;
      } else {
        pinIdx = 2;
        mdIdx = 3;
      }
    } else if (pinBulundu && !mdBulundu) {
      mdIdx = (pinIdx === 2) ? 3 : 2;
    } else if (mdBulundu && !pinBulundu) {
      pinIdx = (mdIdx === 3) ? 2 : 3;
    }
  }
  return { pinIdx: pinIdx, mdIdx: mdIdx, telIdx: telIdx };
}

function hamVerileriOku(ss) {
  var sheetOgr = sayfaBul(ss, ['Ogrenciler', 'Öğrenciler'], 2);
  var ogrenciler = [];
  if (sheetOgr) {
    var rowsOgr = sheetOgr.getDataRange().getDisplayValues();
    for (var i = 1; i < rowsOgr.length; i++) {
      var r = rowsOgr[i];
      var okulNo = (r[0] || '').toString().trim();
      var adSoyad = (r[1] || '').toString().trim();
      if (okulNo !== '' && adSoyad !== '') {
        ogrenciler.push({
          okulNo: okulNo,
          adSoyad: adSoyad,
          sinif: r[2] ? r[2].toString().trim() : '',
          koyDurak: r[3] ? r[3].toString().trim() : '',
          plaka: r[4] ? r[4].toString().trim() : '',
          veliTel: (r[7] && r[7].toString().trim() !== '') ? r[7].toString().trim() : '-',
          sifre: r[8] ? r[8].toString().trim() : '',
          ogrenciTel: r[9] ? r[9].toString().trim() : '',
          durum: 'binmedi',
          adim: 0,
          saat: '',
          izinli: ''
        });
      }
    }
  }

  var sheetNobet = sayfaBul(ss, ['Nobet_Cizelgesi', 'Nöbet_Çizelgesi'], 3);
  var nobetciler = [];
  if (sheetNobet) {
    var rowsN = sheetNobet.getDataRange().getDisplayValues();
    var sutun = nobetSutunlariniBul(rowsN);
    for (var j = 1; j < rowsN.length; j++) {
      var n = rowsN[j];
      var gunStr = (n[0] || '').toString().trim();
      if (gunStr !== '') {
        var hamPin = (sutun.pinIdx >= 0 && n[sutun.pinIdx] !== undefined) ? n[sutun.pinIdx].toString().trim() : '';
        var hamMd = (sutun.mdIdx >= 0 && n[sutun.mdIdx] !== undefined) ? n[sutun.mdIdx].toString().trim() : '';
        var hamTel = (sutun.telIdx >= 0 && n[sutun.telIdx] !== undefined) ? n[sutun.telIdx].toString().trim() : '';
        nobetciler.push({
          satirNo: j + 1,
          gun: gunStr,
          ogretmen: n[1] ? n[1].toString().trim() : '',
          mudurYrd: hamMd !== '' ? hamMd : 'Nöbetçi Md. Yrd.',
          pin: hamPin,
          telefon: hamTel
        });
      }
    }
  }

  var sheetServis = sayfaBul(ss, ['Servisler'], 4);
  var servisler = [];
  if (sheetServis) {
    var rowsS = sheetServis.getDataRange().getDisplayValues();
    for (var k = 1; k < rowsS.length; k++) {
      var s = rowsS[k];
      var plakaStr = (s[0] || '').toString().trim();
      if (plakaStr !== '') {
        servisler.push({
          plaka: plakaStr,
          hatAdi: s[1] ? s[1].toString().trim() : '',
          guzergah: s[2] ? s[2].toString().trim() : '',
          soforAdi: s[3] ? s[3].toString().trim() : '',
          soforTel: s[4] ? s[4].toString().trim() : ''
        });
      }
    }
  }

  return {
    ogrenciler: ogrenciler,
    nobetciler: nobetciler,
    servisler: servisler
  };
}

function gunlukDurumuHesapla(ss, hedefTarih, ogrenciler) {
  var sheetTakip = sayfaBul(ss, ['Takip Ekranı', 'Takip Ekrani'], 0);
  var ogretmenGorevde = false;
  var ogretmenGorevSaati = '';
  var ogretmenAdi = '';
  var servisDurumlari = {};
  var sonAcilDurum = null;
  var ogrDurumByNo = {};
  var ogrDurumByAd = {};
  var ogrIzinByNo = {};
  var ogrIzinByAd = {};
  var gunlukHareketler = [];

  if (sheetTakip) {
    var range = sheetTakip.getDataRange();
    var vals = range.getValues();
    var disp = range.getDisplayValues();

    for (var y = 1; y < disp.length; y++) {
      var satir = disp[y];
      var kayitTarih = tarihHucreyiNormalizeEt(vals[y][0], satir[0]);
      if (kayitTarih !== hedefTarih) continue;

      var kayitPlaka = satir[1] ? satir[1].toString().trim() : '';
      var normP = normalizePlaka(kayitPlaka);
      var kayitKoy = satir[2] ? satir[2].toString().trim() : '';
      var kayitKisi = satir[3] ? satir[3].toString().trim() : '';
      var kayitSinif = satir[4] ? satir[4].toString().trim() : '';
      var kayitIslem = satir[5] ? satir[5].toString().trim() : '';
      var kayitSaat = satir[6] ? satir[6].toString().trim() : '';
      var kayitYontem = satir[7] ? satir[7].toString().trim() : '';
      var kayitOnay = satir[8] ? satir[8].toString().trim() : '';
      var kayitOkulNo = (satir.length > 9 && satir[9]) ? satir[9].toString().trim() : '';
      var islemUst = kayitIslem.toUpperCase();

      gunlukHareketler.push({
        tarih: kayitTarih,
        saat: kayitSaat,
        plaka: kayitPlaka,
        koy: kayitKoy,
        adSoyad: kayitKisi,
        sinif: kayitSinif,
        islem: kayitIslem,
        yontem: kayitYontem,
        ogretmen: kayitOnay,
        okulNo: kayitOkulNo
      });

      if (islemUst.indexOf('GÖREVE_BAŞLADI') !== -1 || islemUst.indexOf('GOREVE_BASLADI') !== -1) {
        ogretmenGorevde = true;
        ogretmenGorevSaati = kayitSaat;
        ogretmenAdi = kayitKisi;
      }

      if (normP && normP !== '-') {
        if (!servisDurumlari[normP]) {
          servisDurumlari[normP] = {
            plaka: kayitPlaka,
            sabahGeldi: '',
            sabahTamam: '',
            aksamHareket: '',
            soforUyarisi: '',
            soforUyariTuru: '',
            soforUyariSaati: '',
            soforSayimSaat: '',
            soforSayimNot: ''
          };
        }
        var yontemKisa = (islemUst.indexOf('QR') !== -1 || kayitYontem.toUpperCase().indexOf('QR') !== -1) ? 'QR' : 'MANUEL';
        if (islemUst.indexOf('SERVIS_SABAH_GELDI') !== -1) {
          servisDurumlari[normP].sabahGeldi = kayitSaat + ' (' + yontemKisa + ')';
        }
        if (islemUst.indexOf('SERVIS_SABAH_TAMAM') !== -1) {
          servisDurumlari[normP].sabahTamam = kayitSaat;
        }
        if (islemUst.indexOf('SERVIS_AKSAM_HAREKET') !== -1) {
          servisDurumlari[normP].aksamHareket = kayitSaat + ' (' + yontemKisa + ')';
        }
        if (islemUst.indexOf('SOFOR_SAYIM_TAMAM') !== -1) {
          servisDurumlari[normP].soforSayimSaat = kayitSaat;
          servisDurumlari[normP].soforSayimNot = kayitIslem.replace(/^.*SOFOR_SAYIM_TAMAM\s*[:\-]?\s*/i, '').trim() || 'Fiziksel sayım tamamlandı';
        }
        if (islemUst.indexOf('SERVIS_GECIKME') !== -1) {
          servisDurumlari[normP].soforUyariTuru = 'GECIKME';
          servisDurumlari[normP].soforUyarisi = kayitIslem.replace(/^.*SERVIS_GECIKME\s*[:\-]?\s*/i, '').trim() || 'Servis gecikme bildirdi';
          servisDurumlari[normP].soforUyariSaati = kayitSaat;
        }
        if (islemUst.indexOf('SERVIS_ARIZA') !== -1) {
          servisDurumlari[normP].soforUyariTuru = 'ARIZA';
          servisDurumlari[normP].soforUyarisi = kayitIslem.replace(/^.*SERVIS_ARIZA\s*[:\-]?\s*/i, '').trim() || 'Servis arıza bildirdi';
          servisDurumlari[normP].soforUyariSaati = kayitSaat;
        }
        if (islemUst.indexOf('SERVIS_NORMAL') !== -1) {
          servisDurumlari[normP].soforUyariTuru = '';
          servisDurumlari[normP].soforUyarisi = '';
          servisDurumlari[normP].soforUyariSaati = '';
        }
      }

      if (islemUst.indexOf('ACİL') !== -1 || islemUst.indexOf('ACIL') !== -1) {
        sonAcilDurum = {
          id: y,
          tarih: kayitTarih,
          plaka: kayitPlaka,
          koy: kayitKoy,
          adSoyad: kayitKisi,
          sinif: kayitSinif,
          saat: kayitSaat
        };
      }

      if (islemUst.indexOf('IZIN_KALDIR') !== -1 || islemUst.indexOf('İZİN_KALDIR') !== -1) {
        if (kayitOkulNo) ogrIzinByNo[kayitOkulNo] = '';
        if (kayitKisi) ogrIzinByAd[trKucult(kayitKisi)] = '';
      } else if (islemUst.indexOf('IZINLI_SABAH') !== -1 || islemUst.indexOf('İZİNLİ_SABAH') !== -1) {
        if (kayitOkulNo) ogrIzinByNo[kayitOkulNo] = 'SABAH';
        if (kayitKisi) ogrIzinByAd[trKucult(kayitKisi)] = 'SABAH';
      } else if (islemUst.indexOf('IZINLI_AKSAM') !== -1 || islemUst.indexOf('İZİNLİ_AKŞAM') !== -1) {
        if (kayitOkulNo) ogrIzinByNo[kayitOkulNo] = 'AKSAM';
        if (kayitKisi) ogrIzinByAd[trKucult(kayitKisi)] = 'AKSAM';
      } else if (islemUst.indexOf('IZINLI') !== -1 || islemUst.indexOf('İZİNLİ') !== -1) {
        if (kayitOkulNo) ogrIzinByNo[kayitOkulNo] = 'TUM_GUN';
        if (kayitKisi) ogrIzinByAd[trKucult(kayitKisi)] = 'TUM_GUN';
      }

      var yeniDurumObj = null;
      if (islemUst.indexOf('ADIM_SIFIRLA') !== -1) {
        yeniDurumObj = { adim: 0, durum: 'binmedi', saat: '' };
      } else if (islemUst.indexOf('SABAH BİNDİ') !== -1 || islemUst.indexOf('SABAH BINDI') !== -1) {
        yeniDurumObj = { adim: 1, durum: 'serviste', saat: kayitSaat };
      } else if (islemUst.indexOf('SABAH İNDİ') !== -1 || islemUst.indexOf('SABAH INDI') !== -1) {
        yeniDurumObj = { adim: 2, durum: 'indi', saat: kayitSaat };
      } else if (islemUst.indexOf('AKŞAM BİNDİ') !== -1 || islemUst.indexOf('AKSAM BINDI') !== -1) {
        yeniDurumObj = { adim: 3, durum: 'serviste', saat: kayitSaat };
      } else if (islemUst.indexOf('AKŞAM İNDİ') !== -1 || islemUst.indexOf('AKSAM INDI') !== -1) {
        yeniDurumObj = { adim: 4, durum: 'indi', saat: kayitSaat };
      }

      if (yeniDurumObj) {
        if (kayitOkulNo) ogrDurumByNo[kayitOkulNo] = yeniDurumObj;
        if (kayitKisi) ogrDurumByAd[trKucult(kayitKisi)] = yeniDurumObj;
      }
    }
  }

  for (var i = 0; i < ogrenciler.length; i++) {
    var o = ogrenciler[i];
    var bulunan = ogrDurumByNo[o.okulNo] || ogrDurumByAd[trKucult(o.adSoyad)];
    if (bulunan) {
      o.adim = bulunan.adim;
      o.durum = bulunan.durum;
      o.saat = bulunan.saat;
    }
    var iz = (ogrIzinByNo[o.okulNo] !== undefined) ? ogrIzinByNo[o.okulNo] : ogrIzinByAd[trKucult(o.adSoyad)];
    o.izinli = iz || '';
  }

  return {
    ogretmenGorevde: ogretmenGorevde,
    ogretmenGorevSaati: ogretmenGorevSaati,
    ogretmenAdi: ogretmenAdi,
    servisDurumlari: servisDurumlari,
    sonAcilDurum: sonAcilDurum,
    hareketler: gunlukHareketler
  };
}

function guvenlikUyarilariniHesapla(ogrenciler) {
  var ayar = saatAyarlariniGetir();
  if (ayar.haftaSonuKapali !== false && haftaSonuMu()) return [];

  var topDak = simdiDakikaToplam();
  var sabahKontrolDak = saatMetniDakikaya(ayar.sabahInisBit, 480) + 5; // 08:05
  var aksamKontrolDak = saatMetniDakikaya(ayar.aksamBit, 1080) + 5;    // 18:05
  var uyarilar = [];

  for (var i = 0; i < ogrenciler.length; i++) {
    var o = ogrenciler[i];
    if (o.izinli === 'TUM_GUN') continue;
    if (topDak >= sabahKontrolDak && o.adim === 1 && o.izinli !== 'SABAH') {
      uyarilar.push({
        tip: 'SABAH_INMEDI',
        okulNo: o.okulNo,
        adSoyad: o.adSoyad,
        sinif: o.sinif,
        plaka: o.plaka,
        koyDurak: o.koyDurak,
        saat: o.saat,
        veliTel: o.veliTel,
        ogrenciTel: o.ogrenciTel,
        mesaj: o.adSoyad + ' (' + o.plaka + ') sabah ' + o.saat + ' biniş yaptı ancak okula iniş kaydı yok!'
      });
    }
    if (topDak >= aksamKontrolDak && o.adim === 3 && o.izinli !== 'AKSAM') {
      uyarilar.push({
        tip: 'AKSAM_INMEDI',
        okulNo: o.okulNo,
        adSoyad: o.adSoyad,
        sinif: o.sinif,
        plaka: o.plaka,
        koyDurak: o.koyDurak,
        saat: o.saat,
        veliTel: o.veliTel,
        ogrenciTel: o.ogrenciTel,
        mesaj: o.adSoyad + ' (' + o.plaka + ') akşam ' + o.saat + ' biniş yaptı ancak köyde iniş kaydı yok!'
      });
    }
  }
  return uyarilar;
}

function otomatikGuvenlikKontroluSabah() {
  _otomatikGuvenlikMailGonder('SABAH');
}

function otomatikGuvenlikKontroluAksam() {
  _otomatikGuvenlikMailGonder('AKSAM');
}

function _otomatikGuvenlikMailGonder(donem) {
  var ayar = saatAyarlariniGetir();
  if (ayar.haftaSonuKapali !== false && haftaSonuMu()) return;

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var ham = hamVerileriOku(ss);
  var bugunTarih = bugunTarihStr();
  gunlukDurumuHesapla(ss, bugunTarih, ham.ogrenciler);

  var kalanlar = [];
  for (var i = 0; i < ham.ogrenciler.length; i++) {
    var o = ham.ogrenciler[i];
    if (o.izinli === 'TUM_GUN') continue;
    if (donem === 'SABAH' && o.adim === 1 && o.izinli !== 'SABAH') {
      kalanlar.push(o);
    } else if (donem === 'AKSAM' && o.adim === 3 && o.izinli !== 'AKSAM') {
      kalanlar.push(o);
    }
  }
  if (kalanlar.length === 0) return;

  var mailler = yoneticiMailleriniGetir(ss);
  if (mailler.length === 0) return;

  var soforMap = {};
  for (var s = 0; s < ham.servisler.length; s++) {
    soforMap[normalizePlaka(ham.servisler[s].plaka)] = ham.servisler[s];
  }

  var baslik = (donem === 'SABAH')
    ? '⚠️ GÜVENLİK UYARISI (08:05): Sabah Servisten İnmeyen ' + kalanlar.length + ' Öğrenci Var!'
    : '⚠️ GÜVENLİK UYARISI (18:05): Akşam Köyde İnmeyen ' + kalanlar.length + ' Öğrenci Var!';

  var satirlar = [
    'DİKKAT! ' + bugunTarih + ' tarihinde aşağıdaki öğrenciler servise biniş yapmış ancak iniş kaydı görünmemektedir:',
    ''
  ];
  for (var k = 0; k < kalanlar.length; k++) {
    var ogr = kalanlar[k];
    var srv = soforMap[normalizePlaka(ogr.plaka)] || {};
    satirlar.push(
      (k + 1) + '. ' + ogr.adSoyad + ' (No: ' + ogr.okulNo + ', Sınıf: ' + ogr.sinif + ')' +
      ' | Plaka: ' + ogr.plaka + ' | Durak: ' + ogr.koyDurak +
      ' | Biniş: ' + (ogr.saat || '-') +
      ' | Veli: ' + ogr.veliTel +
      (ogr.ogrenciTel ? ' | Öğr: ' + ogr.ogrenciTel : '') +
      (srv.soforAdi ? ' | Şoför: ' + srv.soforAdi + ' (' + (srv.soforTel || '-') + ')' : '')
    );
  }
  satirlar.push('');
  satirlar.push('Lütfen derhal şoför ve veli ile iletişime geçerek öğrencilerin güvenliğini teyit ediniz.');

  MailApp.sendEmail(mailler.join(','), baslik, satirlar.join(NL));
}

function yoneticiMailleriniGetir(ss) {
  var sheetAyarlar = sayfaBul(ss, ['Ayarlar', 'ayarlar'], 5);
  var mailler = [];
  if (sheetAyarlar) {
    var satirlar = sheetAyarlar.getDataRange().getDisplayValues();
    for (var a = 1; a < satirlar.length; a++) {
      var mail = satirlar[a][1] ? satirlar[a][1].toString().trim() : '';
      if (mail.indexOf('@') !== -1) mailler.push(mail);
    }
  }
  return mailler;
}

function bugununNobetcisiniBul(nobetciler, bugunGun) {
  var hedef = trKucult(bugunGun);
  for (var i = 0; i < nobetciler.length; i++) {
    if (nobetGunuUygunMu(nobetciler[i].gun, hedef)) return nobetciler[i];
  }
  return nobetciler.length > 0 ? nobetciler[0] : {
    gun: bugunGun,
    ogretmen: 'Nöbetçi Öğretmen',
    mudurYrd: 'Nöbetçi Md. Yrd.'
  };
}

function ogrenciyiTemizle(o, maskeliMi, yoneticiMi) {
  var obj = {
    okulNo: o.okulNo,
    adSoyad: maskeliMi ? maskeleSoyad(o.adSoyad) : o.adSoyad,
    sinif: o.sinif,
    koyDurak: o.koyDurak,
    plaka: o.plaka,
    veliTel: o.veliTel,
    ogrenciTel: o.ogrenciTel,
    durum: o.durum,
    adim: o.adim,
    saat: o.saat,
    izinli: o.izinli || ''
  };
  if (yoneticiMi) {
    obj.sifre = o.sifre || '';
  }
  return obj;
}

function roleGoreVeriHazirla(ss, oturum) {
  var ham = hamVerileriOku(ss);
  var bugunTarih = bugunTarihStr();
  var bugunGun = bugunTurkceGun();
  var ozet = gunlukDurumuHesapla(ss, bugunTarih, ham.ogrenciler);
  var bugunNobetci = bugununNobetcisiniBul(ham.nobetciler, bugunGun);
  var saatAyarlari = saatAyarlariniGetir();
  var duyuru = duyuruyuGetir();
  var aktifNobetciBilgi = {
    gun: bugunNobetci.gun,
    ogretmen: bugunNobetci.ogretmen,
    telefon: bugunNobetci.telefon || ''
  };

  if (oturum.rol === 'yonetici' || oturum.rol === 'ogretmen') {
    var yoneticiMi = oturum.rol === 'yonetici';
    var temizOgr = [];
    for (var i = 0; i < ham.ogrenciler.length; i++) {
      temizOgr.push(ogrenciyiTemizle(ham.ogrenciler[i], false, yoneticiMi));
    }
    var temizNobet = [];
    for (var j = 0; j < ham.nobetciler.length; j++) {
      var nbObj = {
        gun: ham.nobetciler[j].gun,
        ogretmen: ham.nobetciler[j].ogretmen
      };
      if (yoneticiMi) {
        nbObj.mudurYrd = ham.nobetciler[j].mudurYrd;
        nbObj.pin = ham.nobetciler[j].pin;
      }
      temizNobet.push(nbObj);
    }
    return {
      basarili: true,
      rol: oturum.rol,
      bugunTarih: bugunTarih,
      bugunGun: bugunGun,
      aktifNobetci: aktifNobetciBilgi,
      saatAyarlari: saatAyarlari,
      duyuru: duyuru,
      nobetciler: temizNobet,
      servisler: ham.servisler,
      ogrenciler: temizOgr,
      gunlukDurum: {
        ogretmenGorevde: ozet.ogretmenGorevde,
        ogretmenGorevSaati: ozet.ogretmenGorevSaati,
        ogretmenAdi: ozet.ogretmenAdi,
        servisDurumlari: ozet.servisDurumlari
      },
      sonAcilDurum: ozet.sonAcilDurum,
      guvenlikUyarilari: guvenlikUyarilariniHesapla(ham.ogrenciler)
    };
  }

  if (oturum.rol === 'sofor') {
    var normP = normalizePlaka(oturum.plaka);
    var soforServisleri = [];
    for (var s = 0; s < ham.servisler.length; s++) {
      if (normalizePlaka(ham.servisler[s].plaka) === normP) {
        soforServisleri.push(ham.servisler[s]);
      }
    }
    var soforOgr = [];
    for (var k = 0; k < ham.ogrenciler.length; k++) {
      if (normalizePlaka(ham.ogrenciler[k].plaka) === normP) {
        soforOgr.push(ogrenciyiTemizle(ham.ogrenciler[k], true, false));
      }
    }
    return {
      basarili: true,
      rol: 'sofor',
      bugunGun: bugunGun,
      aktifNobetci: aktifNobetciBilgi,
      saatAyarlari: saatAyarlari,
      duyuru: duyuru,
      servisler: soforServisleri,
      servisDurumu: ozet.servisDurumlari[normP] || {},
      ogrenciler: soforOgr
    };
  }

  if (oturum.rol === 'ogrenci' || oturum.rol === 'veli') {
    var benimOgr = null;
    for (var m = 0; m < ham.ogrenciler.length; m++) {
      if (ham.ogrenciler[m].okulNo === oturum.okulNo) {
        benimOgr = ogrenciyiTemizle(ham.ogrenciler[m], false, false);
        break;
      }
    }
    var benimServis = [];
    var benimServisDurum = {};
    if (benimOgr) {
      var oPlaka = normalizePlaka(benimOgr.plaka);
      benimServisDurum = ozet.servisDurumlari[oPlaka] || {};
      for (var z = 0; z < ham.servisler.length; z++) {
        if (normalizePlaka(ham.servisler[z].plaka) === oPlaka) {
          benimServis.push(ham.servisler[z]);
          break;
        }
      }
    }
    return {
      basarili: true,
      rol: oturum.rol,
      bugunGun: bugunGun,
      aktifNobetci: aktifNobetciBilgi,
      saatAyarlari: saatAyarlari,
      duyuru: duyuru,
      servisler: benimServis,
      servisDurumu: benimServisDurum,
      ogrenciler: benimOgr ? [benimOgr] : []
    };
  }

  return { basarili: false, hata: 'Gecersiz rol.' };
}

function doGet(e) {
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var p = (e && e.parameter) ? e.parameter : {};

    if (p.islem === 'nobetci_listesi') {
      var ham = hamVerileriOku(ss);
      var liste = [];
      for (var i = 0; i < ham.nobetciler.length; i++) {
        liste.push({
          gun: ham.nobetciler[i].gun,
          ogretmen: ham.nobetciler[i].ogretmen
        });
      }
      return jsonYanit({
        basarili: true,
        bugunGun: bugunTurkceGun(),
        nobetciler: liste
      });
    }

    if (p.islem === 'pdf_indir') {
      var oturumPdf = oturumDogrula(p.token);
      if (!oturumPdf || (oturumPdf.rol !== 'ogretmen' && oturumPdf.rol !== 'yonetici')) {
        return HtmlService.createHtmlOutput('<h3>Yetkisiz erisim veya oturum suresi doldu. Lutfen uygulamadan tekrar giris yapiniz.</h3>');
      }
      var hedefTarihPdf = (p.tarih && p.tarih.toString().trim() !== '') ? p.tarih.toString().trim() : bugunTarihStr();
      return gunlukResmiPdfUret(ss, hedefTarihPdf);
    }

    if (p.islem === 'aylik_puantaj_pdf') {
      var oturumPnt = oturumDogrula(p.token);
      if (!oturumPnt || (oturumPnt.rol !== 'ogretmen' && oturumPnt.rol !== 'yonetici')) {
        return HtmlService.createHtmlOutput('<h3>Yetkisiz erisim veya oturum suresi doldu.</h3>');
      }
      var simdiP = new Date();
      var yilP = parseInt(p.yil || Utilities.formatDate(simdiP, TZ, 'yyyy'), 10);
      var ayP = parseInt(p.ay || Utilities.formatDate(simdiP, TZ, 'MM'), 10);
      return aylikPuantajPdfUret(ss, yilP, ayP);
    }

    if (p.islem === 'aylik_puantaj_veri') {
      var oturumPntV = oturumDogrula(p.token);
      if (!oturumPntV || (oturumPntV.rol !== 'ogretmen' && oturumPntV.rol !== 'yonetici')) {
        return jsonYanit({ basarili: false, yetkisiz: true, hata: 'Yetkisiz erisim.' });
      }
      var simdiV = new Date();
      var yilV = parseInt(p.yil || Utilities.formatDate(simdiV, TZ, 'yyyy'), 10);
      var ayV = parseInt(p.ay || Utilities.formatDate(simdiV, TZ, 'MM'), 10);
      return jsonYanit(aylikPuantajHesapla(ss, yilV, ayV));
    }

    if (p.islem === 'gecmis_gun_getir') {
      var oturumGec = oturumDogrula(p.token);
      if (!oturumGec || (oturumGec.rol !== 'ogretmen' && oturumGec.rol !== 'yonetici')) {
        return jsonYanit({ basarili: false, yetkisiz: true, hata: 'Yetkisiz erisim.' });
      }
      var hTarih = (p.tarih || '').toString().trim() || bugunTarihStr();
      var hamGec = hamVerileriOku(ss);
      var ozetGec = gunlukDurumuHesapla(ss, hTarih, hamGec.ogrenciler);
      var temizGec = [];
      for (var gi = 0; gi < hamGec.ogrenciler.length; gi++) {
        temizGec.push(ogrenciyiTemizle(hamGec.ogrenciler[gi], false, false));
      }
      return jsonYanit({
        basarili: true,
        tarih: hTarih,
        gun: tarihGunAdiBul(hTarih),
        ogrenciler: temizGec,
        servisler: hamGec.servisler,
        gunlukDurum: {
          ogretmenGorevde: ozetGec.ogretmenGorevde,
          ogretmenGorevSaati: ozetGec.ogretmenGorevSaati,
          ogretmenAdi: ozetGec.ogretmenAdi,
          servisDurumlari: ozetGec.servisDurumlari
        },
        hareketSayisi: ozetGec.hareketler.length,
        hareketler: ozetGec.hareketler
      });
    }

    if (p.islem === 'durum_getir') {
      var oturum = oturumDogrula(p.token);
      if (!oturum) {
        return jsonYanit({
          basarili: false,
          yetkisiz: true,
          hata: 'Oturum gecersiz veya suresi doldu.'
        });
      }
      if (oturum.rol === 'ogretmen' && !oturum.idareciMi) {
        if (haftaSonuMu() || !nobetGunuUygunMu(oturum.gun, bugunTurkceGun())) {
          return jsonYanit({
            basarili: false,
            yetkisiz: true,
            hata: 'Nöbet gününüz sona erdiği için oturumunuz kapatıldı.'
          });
        }
      }
      return jsonYanit(roleGoreVeriHazirla(ss, oturum));
    }

    return jsonYanit({
      basarili: false,
      yetkisiz: true,
      hata: 'Yetkisiz erisim. Lutfen uygulama uzerinden giris yapiniz.'
    });
  } catch (err) {
    return jsonYanit({ basarili: false, hata: err.toString() });
  }
}

function girisIslemiYap(ss, data) {
  var rol = (data.rol || '').toString().trim();
  var ham = hamVerileriOku(ss);

  if (rol === 'ogrenci') {
    var no = (data.okulNo || '').toString().trim();
    var sifre = (data.sifre || '').toString().trim();
    for (var i = 0; i < ham.ogrenciler.length; i++) {
      var o = ham.ogrenciler[i];
      if (o.okulNo === no && o.sifre !== '' && o.sifre === sifre) {
        var otOgr = {
          rol: 'ogrenci',
          okulNo: o.okulNo,
          adSoyad: o.adSoyad,
          plaka: o.plaka
        };
        var tokOgr = oturumOlustur(otOgr);
        return {
          basarili: true,
          token: tokOgr,
          veri: roleGoreVeriHazirla(ss, otOgr)
        };
      }
    }
    return { basarili: false, hata: 'Okul numarasi veya sifre hatali.' };
  }

  if (rol === 'veli') {
    var vNo = (data.okulNo || '').toString().trim();
    var vTel = normalizeTel(data.veliTel || '');
    for (var j = 0; j < ham.ogrenciler.length; j++) {
      var ov = ham.ogrenciler[j];
      if (ov.okulNo === vNo && vTel !== '' && normalizeTel(ov.veliTel) === vTel) {
        var otVeli = {
          rol: 'veli',
          okulNo: ov.okulNo,
          adSoyad: ov.adSoyad
        };
        var tokVeli = oturumOlustur(otVeli);
        return {
          basarili: true,
          token: tokVeli,
          veri: roleGoreVeriHazirla(ss, otVeli)
        };
      }
    }
    return { basarili: false, hata: 'Okul numarasi veya kayitli veli telefonu hatali.' };
  }

  if (rol === 'sofor') {
    var sTel = normalizeTel(data.soforTel || '');
    for (var k = 0; k < ham.servisler.length; k++) {
      var sv = ham.servisler[k];
      if (sTel !== '' && normalizeTel(sv.soforTel) === sTel) {
        var otSofor = {
          rol: 'sofor',
          plaka: sv.plaka,
          soforAdi: sv.soforAdi
        };
        var tokSofor = oturumOlustur(otSofor);
        return {
          basarili: true,
          token: tokSofor,
          veri: roleGoreVeriHazirla(ss, otSofor)
        };
      }
    }
    return { basarili: false, hata: 'Bu telefon numarasina ait servis kaydi bulunamadi.' };
  }

  if (rol === 'ogretmen') {
    var ogrAd = trKucult(data.ogretmenAdi || '');
    var pin = (data.pin || '').toString().trim();
    var bugunAd = bugunTurkceGun();
    for (var n = 0; n < ham.nobetciler.length; n++) {
      var nb = ham.nobetciler[n];
      if (trKucult(nb.ogretmen) === ogrAd) {
        var idareciMi = idareciYetkiliMi(nb.ogretmen, nb.gun);

        if (!idareciMi && haftaSonuMu()) {
          return {
            basarili: false,
            hata: 'Hafta sonu (Cumartesi - Pazar) sadece Okul Müdürü ve Müdür Yardımcıları giriş yapabilir.'
          };
        }

        if (!idareciMi && !nobetGunuUygunMu(nb.gun, bugunAd)) {
          return {
            basarili: false,
            hata: 'Yetkisiz giriş: Bugün ' + bugunAd + ', sizin nöbet gününüz (' + nb.gun + ') değildir.'
          };
        }

        if (nb.pin !== '' && nb.pin === pin) {
          var otOgretmen = {
            rol: 'ogretmen',
            ogretmenAdi: nb.ogretmen,
            gun: nb.gun,
            idareciMi: idareciMi
          };
          var tokOgretmen = oturumOlustur(otOgretmen);
          return {
            basarili: true,
            token: tokOgretmen,
            ogretmen: { gun: nb.gun, ogretmen: nb.ogretmen, idareciMi: idareciMi },
            veri: roleGoreVeriHazirla(ss, otOgretmen)
          };
        }
        return { basarili: false, hata: 'Hatalı PIN kodu.' };
      }
    }
    return { basarili: false, hata: 'Seçilen öğretmen bulunamadı.' };
  }

  if (rol === 'yonetici') {
    var kullanici = (data.kullanici || '').toString().trim();
    var ySifre = (data.sifre || '').toString().trim();
    var sifreler = yoneticiSifreleriniGetir();
    var yetkiliGiris = !!(sifreler[kullanici] && sifreler[kullanici] === ySifre);

    // Okul Müdürü ve Müdür Yardımcısı e-tablodaki PIN kodu ile de masaüstüne girebilsin
    if (!yetkiliGiris && ySifre !== '' && (kullanici === 'Okul Müdürü' || kullanici === 'Müdür Yardımcısı')) {
      for (var yi = 0; yi < ham.nobetciler.length; yi++) {
        var nbY = ham.nobetciler[yi];
        var gKucuk = trKucult(nbY.gun + ' ' + nbY.ogretmen);
        var yrdMi = gKucuk.indexOf('yardımcı') !== -1 || gKucuk.indexOf('yardimci') !== -1 || gKucuk.indexOf('yrd') !== -1;
        var mudurMu = (gKucuk.indexOf('müdür') !== -1 || gKucuk.indexOf('mudur') !== -1) && !yrdMi;
        if (kullanici === 'Okul Müdürü' && mudurMu && nbY.pin !== '' && nbY.pin === ySifre) {
          yetkiliGiris = true;
          break;
        }
        if (kullanici === 'Müdür Yardımcısı' && yrdMi && nbY.pin !== '' && nbY.pin === ySifre) {
          yetkiliGiris = true;
          break;
        }
      }
    }

    if (yetkiliGiris) {
      var otYon = {
        rol: 'yonetici',
        kullanici: kullanici
      };
      var tokYon = oturumOlustur(otYon);
      return {
        basarili: true,
        token: tokYon,
        kullanici: kullanici,
        veri: roleGoreVeriHazirla(ss, otYon)
      };
    }
    return { basarili: false, hata: 'Yonetici kullanici adi veya sifre hatali.' };
  }

  return { basarili: false, hata: 'Bilinmeyen giris rolu.' };
}

function doPost(e) {
  var lock = null;
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return jsonYanit({ basarili: false, hata: 'Bos istek.' });
    }
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var data = JSON.parse(e.postData.contents);

    if (data.islem === 'GIRIS_YAP') {
      return jsonYanit(girisIslemiYap(ss, data));
    }

    var oturum = oturumDogrula(data.token);
    if (!oturum) {
      return jsonYanit({
        basarili: false,
        yetkisiz: true,
        hata: 'Oturum gecersiz veya suresi doldu.'
      });
    }

    if (oturum.rol === 'ogretmen' && !oturum.idareciMi) {
      if (haftaSonuMu() || !nobetGunuUygunMu(oturum.gun, bugunTurkceGun())) {
        return jsonYanit({
          basarili: false,
          yetkisiz: true,
          hata: 'Nöbet gününüz sona erdiği için işlem yapamazsınız.'
        });
      }
    }

    var islem = (data.islem || '').toString().trim();

    // Sadece YÖNETİCİ yetkisi gerektiren işlemler
    var yoneticiIslemleri = {
      OGRENCI_EKLE: true,
      OGRENCI_GUNCELLE: true,
      OGRENCI_SIL: true,
      SERVIS_EKLE: true,
      SERVIS_GUNCELLE: true,
      SERVIS_SIL: true,
      NOBETCI_EKLE: true,
      NOBETCI_GUNCELLE: true,
      NOBETCI_SIL: true,
      SAAT_AYARLARI_GUNCELLE: true,
      DUYURU_YAYINLA: true,
      DUYURU_KALDIR: true
    };

    // ÖĞRETMEN veya YÖNETİCİ yetkisi gerektiren işlemler (İZİNLİ dahil — veli/öğrenci kesinlikle yasak!)
    var personelIslemleri = {
      OGRETMEN_GOREVE_BASLADI: true,
      SERVIS_SABAH_GELDI: true,
      SERVIS_SABAH_TAMAM: true,
      SERVIS_AKSAM_HAREKET: true,
      ADIM_SIFIRLA: true,
      OGRENCI_IZINLI: true,
      OGRENCI_IZIN_KALDIR: true
    };

    if (yoneticiIslemleri[islem]) {
      if (oturum.rol !== 'yonetici') {
        return jsonYanit({ basarili: false, hata: 'Bu işlem için yönetici yetkisi gerekir.' });
      }
    } else if (personelIslemleri[islem]) {
      if (oturum.rol !== 'ogretmen' && oturum.rol !== 'yonetici') {
        return jsonYanit({ basarili: false, hata: 'Bu işlem için idare veya nöbetçi öğretmen yetkisi gerekir.' });
      }
    } else if (islem === 'SOFOR_DURUM_BILDIR' || islem === 'SOFOR_SAYIM_TAMAM') {
      if (oturum.rol !== 'sofor' && oturum.rol !== 'yonetici' && oturum.rol !== 'ogretmen') {
        return jsonYanit({ basarili: false, hata: 'Yetkisiz işlem.' });
      }
    } else if (islem === 'ACİL_DURUM') {
      if (oturum.rol === 'veli') {
        return jsonYanit({ basarili: false, hata: 'Yetkisiz işlem.' });
      }
    } else {
      if (oturum.rol === 'veli' || oturum.rol === 'sofor') {
        return jsonYanit({ basarili: false, hata: 'Yetkisiz işlem.' });
      }
      if (oturum.rol === 'ogrenci') {
        if (data.okulNo && data.okulNo.toString().trim() !== oturum.okulNo) {
          return jsonYanit({ basarili: false, hata: 'Sadece kendi kaydınızı işleyebilirsiniz.' });
        }
        var ozelSaat = (data.cevirimdisiSaat && saatMetniGecerliMi(data.cevirimdisiSaat))
          ? data.cevirimdisiSaat.toString().trim()
          : '';
        var zamanSonuc = ogrenciZamanKontrolu(islem, ozelSaat);
        if (!zamanSonuc.izinli) {
          return jsonYanit({ basarili: false, hata: zamanSonuc.hata });
        }
      }
    }

    lock = LockService.getScriptLock();
    lock.waitLock(15000);

    // -----------------------------------------------------------------------
    // YÖNETİM (CRUD + AYARLAR + DUYURU) İŞLEMLERİ
    // -----------------------------------------------------------------------
    if (islem === 'SAAT_AYARLARI_GUNCELLE') {
      var alanlar = [
        'sabahBinisBas', 'sabahBinisBit',
        'sabahInisBas', 'sabahInisBit',
        'pztAksamBas', 'digerAksamBas', 'aksamBit',
        'bildirimSabah', 'bildirimNobetci',
        'bildirimPztAksam', 'bildirimSaliAksam',
        'bildirimDigerAksam', 'bildirimAksamInis'
      ];
      var yeniAyar = saatAyarlariniGetir();
      for (var ai = 0; ai < alanlar.length; ai++) {
        var aKey = alanlar[ai];
        if (data[aKey] === undefined || data[aKey] === null || data[aKey] === '') {
          continue;
        }
        var val = data[aKey].toString().trim();
        if (!saatMetniGecerliMi(val)) {
          return jsonYanit({ basarili: false, hata: 'Geçersiz saat formatı (' + aKey + '): HH:MM olmalı.' });
        }
        yeniAyar[aKey] = val;
      }
      yeniAyar.haftaSonuKapali = data.haftaSonuKapali !== false;
      PropertiesService.getScriptProperties().setProperty('SAAT_AYARLARI_JSON', JSON.stringify(yeniAyar));
      return jsonYanit({ basarili: true, mesaj: 'SAAT_AYARLARI_GUNCELLENDI', saatAyarlari: yeniAyar });
    }

    if (islem === 'DUYURU_YAYINLA') {
      var dMetin = (data.metin || '').toString().trim();
      if (!dMetin) {
        return jsonYanit({ basarili: false, hata: 'Duyuru metni boş bırakılamaz.' });
      }
      var dObj = {
        metin: dMetin,
        onem: (data.onem === 'acil') ? 'acil' : 'normal',
        yazar: oturum.kullanici || 'Okul Yönetimi',
        tarih: bugunTarihStr(),
        saat: simdiSaatStr()
      };
      PropertiesService.getScriptProperties().setProperty('AKTIF_DUYURU_JSON', JSON.stringify(dObj));
      return jsonYanit({ basarili: true, mesaj: 'DUYURU_YAYINLANDI', duyuru: dObj });
    }

    if (islem === 'DUYURU_KALDIR') {
      PropertiesService.getScriptProperties().deleteProperty('AKTIF_DUYURU_JSON');
      return jsonYanit({ basarili: true, mesaj: 'DUYURU_KALDIRILDI' });
    }

    if (islem === 'OGRENCI_EKLE') {
      var sheetOgr = sayfaBul(ss, ['Ogrenciler', 'Öğrenciler'], 2);
      if (!sheetOgr) return jsonYanit({ basarili: false, hata: 'Ogrenciler sayfası bulunamadı.' });
      var yeniNo = (data.okulNo || '').toString().trim();
      var yeniAd = (data.adSoyad || '').toString().trim();
      if (!yeniNo || !yeniAd) return jsonYanit({ basarili: false, hata: 'Okul numarası ve Ad Soyad zorunludur.' });
      var mevcutOgr = sheetOgr.getDataRange().getDisplayValues();
      for (var oi = 1; oi < mevcutOgr.length; oi++) {
        if ((mevcutOgr[oi][0] || '').toString().trim() === yeniNo) {
          return jsonYanit({ basarili: false, hata: 'Bu okul numarası (' + yeniNo + ') zaten kayıtlı.' });
        }
      }
      sheetOgr.appendRow([
        metinHucre(yeniNo),
        yeniAd,
        (data.sinif || '').toString().trim(),
        (data.koyDurak || '').toString().trim(),
        (data.plaka || '').toString().trim(),
        '-',
        '-',
        metinHucre(data.veliTel || '-'),
        metinHucre(data.sifre || ''),
        metinHucre(data.ogrenciTel || '')
      ]);
      return jsonYanit({ basarili: true, mesaj: 'OGRENCI_EKLENDI' });
    }

    if (islem === 'OGRENCI_GUNCELLE') {
      var sheetOgrG = sayfaBul(ss, ['Ogrenciler', 'Öğrenciler'], 2);
      if (!sheetOgrG) return jsonYanit({ basarili: false, hata: 'Ogrenciler sayfası bulunamadı.' });
      var eskiNo = (data.eskiOkulNo || data.okulNo || '').toString().trim();
      var gNo = (data.okulNo || '').toString().trim();
      var gAd = (data.adSoyad || '').toString().trim();
      if (!eskiNo || !gNo || !gAd) return jsonYanit({ basarili: false, hata: 'Okul No ve Ad Soyad zorunludur.' });
      var rowsOG = sheetOgrG.getDataRange().getDisplayValues();
      var hedefSatirOG = -1;
      for (var uo = 1; uo < rowsOG.length; uo++) {
        var satNo = (rowsOG[uo][0] || '').toString().trim();
        if (satNo === eskiNo) hedefSatirOG = uo + 1;
        else if (satNo === gNo && gNo !== eskiNo) {
          return jsonYanit({ basarili: false, hata: 'Yeni okul numarası (' + gNo + ') başka bir öğrencide kayıtlı.' });
        }
      }
      if (hedefSatirOG === -1) return jsonYanit({ basarili: false, hata: 'Güncellenecek öğrenci bulunamadı.' });
      sheetOgrG.getRange(hedefSatirOG, 1, 1, 10).setValues([[
        metinHucre(gNo),
        gAd,
        (data.sinif || '').toString().trim(),
        (data.koyDurak || '').toString().trim(),
        (data.plaka || '').toString().trim(),
        rowsOG[hedefSatirOG - 1][5] || '-',
        rowsOG[hedefSatirOG - 1][6] || '-',
        metinHucre(data.veliTel || '-'),
        metinHucre(data.sifre !== undefined ? data.sifre : (rowsOG[hedefSatirOG - 1][8] || '')),
        metinHucre(data.ogrenciTel || '')
      ]]);
      return jsonYanit({ basarili: true, mesaj: 'OGRENCI_GUNCELLENDI' });
    }

    if (islem === 'OGRENCI_SIL') {
      var sheetOgrS = sayfaBul(ss, ['Ogrenciler', 'Öğrenciler'], 2);
      if (!sheetOgrS) return jsonYanit({ basarili: false, hata: 'Ogrenciler sayfası bulunamadı.' });
      var silNo = (data.okulNo || '').toString().trim();
      var rowsOS = sheetOgrS.getDataRange().getDisplayValues();
      for (var ds = 1; ds < rowsOS.length; ds++) {
        if ((rowsOS[ds][0] || '').toString().trim() === silNo) {
          sheetOgrS.deleteRow(ds + 1);
          return jsonYanit({ basarili: true, mesaj: 'OGRENCI_SILINDI' });
        }
      }
      return jsonYanit({ basarili: false, hata: 'Silinecek öğrenci bulunamadı.' });
    }

    if (islem === 'SERVIS_EKLE') {
      var sheetServis = sayfaBul(ss, ['Servisler'], 4);
      if (!sheetServis) return jsonYanit({ basarili: false, hata: 'Servisler sayfası bulunamadı.' });
      var yeniPlaka = (data.plaka || '').toString().trim();
      if (!yeniPlaka) return jsonYanit({ basarili: false, hata: 'Plaka zorunludur.' });
      var normYeniPlaka = normalizePlaka(yeniPlaka);
      var mevcutSrv = sheetServis.getDataRange().getDisplayValues();
      for (var si = 1; si < mevcutSrv.length; si++) {
        if (normalizePlaka(mevcutSrv[si][0]) === normYeniPlaka) {
          return jsonYanit({ basarili: false, hata: 'Bu plaka (' + yeniPlaka + ') zaten kayıtlı.' });
        }
      }
      sheetServis.appendRow([
        yeniPlaka,
        (data.hatAdi || '').toString().trim(),
        (data.guzergah || '').toString().trim(),
        (data.soforAdi || '').toString().trim(),
        metinHucre(data.soforTel || '')
      ]);
      return jsonYanit({ basarili: true, mesaj: 'SERVIS_EKLENDI' });
    }

    if (islem === 'SERVIS_GUNCELLE') {
      var sheetSrvG = sayfaBul(ss, ['Servisler'], 4);
      if (!sheetSrvG) return jsonYanit({ basarili: false, hata: 'Servisler sayfası bulunamadı.' });
      var eskiPlakaNorm = normalizePlaka(data.eskiPlaka || data.plaka || '');
      var gPlaka = (data.plaka || '').toString().trim();
      if (!eskiPlakaNorm || !gPlaka) return jsonYanit({ basarili: false, hata: 'Plaka zorunludur.' });
      var rowsSG = sheetSrvG.getDataRange().getDisplayValues();
      var hedefSG = -1;
      for (var sg = 1; sg < rowsSG.length; sg++) {
        if (normalizePlaka(rowsSG[sg][0]) === eskiPlakaNorm) {
          hedefSG = sg + 1;
          break;
        }
      }
      if (hedefSG === -1) return jsonYanit({ basarili: false, hata: 'Güncellenecek servis bulunamadı.' });
      sheetSrvG.getRange(hedefSG, 1, 1, 5).setValues([[
        gPlaka,
        (data.hatAdi || '').toString().trim(),
        (data.guzergah || '').toString().trim(),
        (data.soforAdi || '').toString().trim(),
        metinHucre(data.soforTel || '')
      ]]);
      return jsonYanit({ basarili: true, mesaj: 'SERVIS_GUNCELLENDI' });
    }

    if (islem === 'SERVIS_SIL') {
      var sheetSrvS = sayfaBul(ss, ['Servisler'], 4);
      if (!sheetSrvS) return jsonYanit({ basarili: false, hata: 'Servisler sayfası bulunamadı.' });
      var silPNorm = normalizePlaka(data.plaka || '');
      var rowsSS = sheetSrvS.getDataRange().getDisplayValues();
      for (var ssi = 1; ssi < rowsSS.length; ssi++) {
        if (normalizePlaka(rowsSS[ssi][0]) === silPNorm) {
          sheetSrvS.deleteRow(ssi + 1);
          return jsonYanit({ basarili: true, mesaj: 'SERVIS_SILINDI' });
        }
      }
      return jsonYanit({ basarili: false, hata: 'Silinecek servis bulunamadı.' });
    }

    if (islem === 'NOBETCI_EKLE') {
      var sheetNbE = sayfaBul(ss, ['Nobet_Cizelgesi', 'Nöbet_Çizelgesi'], 3);
      if (!sheetNbE) return jsonYanit({ basarili: false, hata: 'Nobet_Cizelgesi sayfası bulunamadı.' });
      var nGun = (data.gun || '').toString().trim();
      var nOgr = (data.ogretmen || '').toString().trim();
      var nMd = (data.mudurYrd || 'Nöbetçi Md. Yrd.').toString().trim();
      var nPin = (data.pin || '').toString().trim();
      if (!nGun || !nOgr || !nPin) return jsonYanit({ basarili: false, hata: 'Gün, Öğretmen Adı ve PIN zorunludur.' });
      var sutE = nobetSutunlariniBul(sheetNbE.getDataRange().getDisplayValues());
      var yeniSatir = [nGun, nOgr, '', ''];
      yeniSatir[sutE.pinIdx] = metinHucre(nPin);
      yeniSatir[sutE.mdIdx] = nMd;
      sheetNbE.appendRow(yeniSatir);
      return jsonYanit({ basarili: true, mesaj: 'NOBETCI_EKLENDI' });
    }

    if (islem === 'NOBETCI_GUNCELLE') {
      var sheetNbG = sayfaBul(ss, ['Nobet_Cizelgesi', 'Nöbet_Çizelgesi'], 3);
      if (!sheetNbG) return jsonYanit({ basarili: false, hata: 'Nobet_Cizelgesi sayfası bulunamadı.' });
      var eskiOgrAd = trKucult(data.eskiOgretmen || data.ogretmen || '');
      var eskiGunAd = trKucult(data.eskiGun || '');
      var rowsNG = sheetNbG.getDataRange().getDisplayValues();
      var sutG = nobetSutunlariniBul(rowsNG);
      var hedefNG = -1;
      for (var ngi = 1; ngi < rowsNG.length; ngi++) {
        var adEsles = trKucult(rowsNG[ngi][1]) === eskiOgrAd;
        var gunEsles = !eskiGunAd || trKucult(rowsNG[ngi][0]) === eskiGunAd;
        if (adEsles && gunEsles) {
          hedefNG = ngi + 1;
          break;
        }
      }
      if (hedefNG === -1) return jsonYanit({ basarili: false, hata: 'Güncellenecek nöbetçi bulunamadı.' });
      var guncelSatir = [
        (data.gun || '').toString().trim(),
        (data.ogretmen || '').toString().trim(),
        '',
        ''
      ];
      guncelSatir[sutG.pinIdx] = metinHucre(data.pin || '');
      guncelSatir[sutG.mdIdx] = (data.mudurYrd || 'Nöbetçi Md. Yrd.').toString().trim();
      sheetNbG.getRange(hedefNG, 1, 1, 4).setValues([guncelSatir]);
      return jsonYanit({ basarili: true, mesaj: 'NOBETCI_GUNCELLENDI' });
    }

    if (islem === 'NOBETCI_SIL') {
      var sheetNbS = sayfaBul(ss, ['Nobet_Cizelgesi', 'Nöbet_Çizelgesi'], 3);
      if (!sheetNbS) return jsonYanit({ basarili: false, hata: 'Nobet_Cizelgesi sayfası bulunamadı.' });
      var sOgrAd = trKucult(data.ogretmen || '');
      var sGunAd = trKucult(data.gun || '');
      var rowsNS = sheetNbS.getDataRange().getDisplayValues();
      for (var nsi = 1; nsi < rowsNS.length; nsi++) {
        if (trKucult(rowsNS[nsi][1]) === sOgrAd && (!sGunAd || trKucult(rowsNS[nsi][0]) === sGunAd)) {
          sheetNbS.deleteRow(nsi + 1);
          return jsonYanit({ basarili: true, mesaj: 'NOBETCI_SILINDI' });
        }
      }
      return jsonYanit({ basarili: false, hata: 'Silinecek nöbetçi bulunamadı.' });
    }

    // -----------------------------------------------------------------------
    // CANLI HAREKET / YOKLAMA / İZİNLİ / ŞOFÖR UYARI İŞLEMLERİ
    // -----------------------------------------------------------------------
    var kayitTarih = bugunTarihStr();
    var kayitSaat = (data.cevirimdisiSaat && saatMetniGecerliMi(data.cevirimdisiSaat))
      ? data.cevirimdisiSaat.toString().trim()
      : simdiSaatStr();

    if (oturum.rol === 'ogrenci' && islem !== 'ACİL_DURUM') {
      var hamKontrol = hamVerileriOku(ss);
      var ozetKontrol = gunlukDurumuHesapla(ss, kayitTarih, hamKontrol.ogrenciler);
      var mevcutOgrObj = null;
      for (var ko = 0; ko < hamKontrol.ogrenciler.length; ko++) {
        if (hamKontrol.ogrenciler[ko].okulNo === oturum.okulNo) {
          mevcutOgrObj = hamKontrol.ogrenciler[ko];
          break;
        }
      }
      var mevcutAdim = mevcutOgrObj ? mevcutOgrObj.adim : 0;
      var mevcutIzin = mevcutOgrObj ? (mevcutOgrObj.izinli || '') : '';
      var ogrPlakaNorm = normalizePlaka(mevcutOgrObj ? mevcutOgrObj.plaka : (data.plaka || ''));
      var srvDur = ozetKontrol.servisDurumlari[ogrPlakaNorm] || {};
      var ustKontrol = islem.toUpperCase();

      if (mevcutIzin === 'TUM_GUN') {
        return jsonYanit({ basarili: false, yenile: true, hata: 'Bugün okul idaresi tarafından izinli işaretlendiniz.' });
      }
      if (mevcutIzin === 'SABAH' && (ustKontrol.indexOf('SABAH') !== -1)) {
        return jsonYanit({ basarili: false, yenile: true, hata: 'Sabah servisi için idare tarafından izinli işaretlendiniz.' });
      }
      if (mevcutIzin === 'AKSAM' && (ustKontrol.indexOf('AKŞAM') !== -1 || ustKontrol.indexOf('AKSAM') !== -1)) {
        return jsonYanit({ basarili: false, yenile: true, hata: 'Akşam servisi için idare tarafından izinli işaretlendiniz.' });
      }

      if ((ustKontrol.indexOf('SABAH BİNDİ') !== -1 || ustKontrol.indexOf('SABAH BINDI') !== -1) && mevcutAdim >= 1) {
        return jsonYanit({ basarili: false, yenile: true, hata: 'Sabah biniş işleminiz zaten kaydedilmiş.' });
      }
      if ((ustKontrol.indexOf('SABAH İNDİ') !== -1 || ustKontrol.indexOf('SABAH INDI') !== -1) && (mevcutAdim >= 2 || (srvDur.sabahTamam && srvDur.sabahTamam !== ''))) {
        return jsonYanit({ basarili: false, yenile: true, hata: 'Sabah okula iniş işleminiz öğretmen tarafından zaten onaylandı.' });
      }
      if ((ustKontrol.indexOf('AKŞAM BİNDİ') !== -1 || ustKontrol.indexOf('AKSAM BINDI') !== -1) && mevcutAdim >= 3) {
        return jsonYanit({ basarili: false, yenile: true, hata: 'Akşam biniş işleminiz zaten kaydedilmiş.' });
      }
      if ((ustKontrol.indexOf('AKŞAM İNDİ') !== -1 || ustKontrol.indexOf('AKSAM INDI') !== -1) && mevcutAdim >= 4) {
        return jsonYanit({ basarili: false, yenile: true, hata: 'Bugünkü tüm servis işlemleriniz zaten tamamlandı.' });
      }
    }

    var islemMetni = islem;
    var cizelgeIslem = islem;
    if (islem === 'ACİL_DURUM') islemMetni = '🚨 ACİL DURUM İHBARI';
    if (islem === 'OGRETMEN_GOREVE_BASLADI') islemMetni = '🏫 GÖREVE_BAŞLADI (Nöbetçi Okulda)';
    if (islem === 'SERVIS_SABAH_GELDI') islemMetni = '🚍 SERVIS_SABAH_GELDI';
    if (islem === 'SERVIS_SABAH_TAMAM') islemMetni = '🏁 SERVIS_SABAH_TAMAM';
    if (islem === 'SERVIS_AKSAM_HAREKET') islemMetni = '🚀 SERVIS_AKSAM_HAREKET';
    if (islem === 'ADIM_SIFIRLA') islemMetni = '↩️ ADIM_SIFIRLA';

    if (islem === 'OGRENCI_IZINLI') {
      var izinTuru = (data.izinTuru || 'TUM_GUN').toString().toUpperCase().trim();
      if (izinTuru === 'SABAH') {
        islemMetni = '📋 IZINLI_SABAH (İdare Onaylı)';
        cizelgeIslem = 'IZINLI_SABAH';
      } else if (izinTuru === 'AKSAM') {
        islemMetni = '📋 IZINLI_AKSAM (İdare Onaylı)';
        cizelgeIslem = 'IZINLI_AKSAM';
      } else {
        islemMetni = '📋 IZINLI_TUM_GUN (İdare Onaylı)';
        cizelgeIslem = 'IZINLI_TUM_GUN';
      }
    }
    if (islem === 'OGRENCI_IZIN_KALDIR') {
      islemMetni = '↩️ IZIN_KALDIR';
      cizelgeIslem = 'IZIN_KALDIR';
    }
    if (islem === 'SOFOR_DURUM_BILDIR') {
      var dTur = (data.durumTuru || 'GECIKME').toString().toUpperCase().trim();
      var dMsg = (data.mesaj || '').toString().trim();
      if (dTur === 'ARIZA') {
        islemMetni = '🔧 SERVIS_ARIZA: ' + (dMsg || 'Araç arızası bildirildi');
      } else if (dTur === 'NORMAL') {
        islemMetni = '✅ SERVIS_NORMAL: ' + (dMsg || 'Sorun giderildi, normal seferde');
      } else {
        islemMetni = '⚠️ SERVIS_GECIKME: ' + (dMsg || 'Trafik / yol nedeniyle gecikme');
      }
      if (!data.plaka && oturum.plaka) data.plaka = oturum.plaka;
      if (!data.adSoyad && oturum.soforAdi) data.adSoyad = 'Şoför: ' + oturum.soforAdi;
    }
    if (islem === 'SOFOR_SAYIM_TAMAM') {
      var sNot = (data.mesaj || '').toString().trim();
      islemMetni = '✋ SOFOR_SAYIM_TAMAM: ' + (sNot || 'Fiziksel sayım tamamlandı, öğretmen QR onayı bekleniyor');
      if (!data.plaka && oturum.plaka) data.plaka = oturum.plaka;
      if (!data.adSoyad && oturum.soforAdi) data.adSoyad = 'Şoför: ' + oturum.soforAdi;
    }

    var sheetTakip = sayfaBul(ss, ['Takip Ekranı', 'Takip Ekrani'], 0);
    var okulNoYaz = data.okulNo ? data.okulNo.toString().trim() : (oturum.okulNo || '');
    var onaylayan = data.ogretmen || (oturum.ogretmenAdi || oturum.kullanici || oturum.soforAdi || 'İdare');
    var yontemYaz = data.yontem || '-';
    if (data.cevirimdisiSaat && yontemYaz.indexOf('Çevrimdışı') === -1) {
      yontemYaz = yontemYaz + ' (Çevrimdışı Senkron)';
    }

    sheetTakip.appendRow([
      APOS + kayitTarih,
      data.plaka || '-',
      data.koy || '-',
      data.adSoyad || '-',
      data.sinif || '-',
      islemMetni,
      APOS + kayitSaat,
      yontemYaz,
      onaylayan,
      metinHucre(okulNoYaz)
    ]);

    gunlukCizelgeGuncelle(ss, kayitTarih, kayitSaat, data, cizelgeIslem, onaylayan);

    if (islem === 'SERVIS_SABAH_TAMAM' && data.plaka) {
      var hamTamam = hamVerileriOku(ss);
      gunlukDurumuHesapla(ss, kayitTarih, hamTamam.ogrenciler);
      var hedefPlakaNorm = normalizePlaka(data.plaka);
      var eklenecekSatirlar = [];
      for (var ti = 0; ti < hamTamam.ogrenciler.length; ti++) {
        var oTamam = hamTamam.ogrenciler[ti];
        if (normalizePlaka(oTamam.plaka) === hedefPlakaNorm && oTamam.adim === 1) {
          eklenecekSatirlar.push([
            APOS + kayitTarih,
            oTamam.plaka || data.plaka,
            oTamam.koyDurak || '-',
            oTamam.adSoyad,
            oTamam.sinif || '-',
            'SABAH İNDİ',
            APOS + kayitSaat,
            'Öğretmen (Sabah İndirme Onayı)',
            onaylayan,
            metinHucre(oTamam.okulNo)
          ]);
          gunlukCizelgeGuncelle(
            ss,
            kayitTarih,
            kayitSaat,
            {
              plaka: oTamam.plaka || data.plaka,
              adSoyad: oTamam.adSoyad,
              sinif: oTamam.sinif || '-',
              koy: oTamam.koyDurak || '-'
            },
            'SABAH İNDİ',
            onaylayan
          );
        }
      }
      if (eklenecekSatirlar.length > 0) {
        sheetTakip
          .getRange(sheetTakip.getLastRow() + 1, 1, eklenecekSatirlar.length, 10)
          .setValues(eklenecekSatirlar);
      }
    }

    if (islem === 'ACİL_DURUM') {
      data.saat = kayitSaat;
      data.okulNo = okulNoYaz;
      acilDurumMailiGonder(ss, data);
    }

    if (islem === 'SOFOR_DURUM_BILDIR' && (data.durumTuru || '').toString().toUpperCase() === 'ARIZA') {
      var maillerAriza = yoneticiMailleriniGetir(ss);
      if (maillerAriza.length > 0) {
        MailApp.sendEmail(
          maillerAriza.join(','),
          '🔧 SERVİS ARIZA BİLDİRİMİ: ' + (data.plaka || '-'),
          'Plaka: ' + (data.plaka || '-') + NL +
          'Şoför: ' + (data.adSoyad || '-') + NL +
          'Saat: ' + kayitSaat + NL +
          'Açıklama: ' + (data.mesaj || 'Araç arızası bildirildi') + NL + NL +
          'Lütfen şoför ile iletişime geçiniz.'
        );
      }
    }

    return jsonYanit({
      basarili: true,
      mesaj: 'BAŞARILI',
      tarih: kayitTarih,
      saat: kayitSaat
    });
  } catch (err) {
    return jsonYanit({ basarili: false, hata: err.toString() });
  } finally {
    if (lock) lock.releaseLock();
  }
}

function gunlukCizelgeGuncelle(ss, kayitTarih, kayitSaat, data, islem, onaylayan) {
  var ust = (islem || '').toString().toUpperCase();
  var saatKolonu = 0;
  var saatDegeri = '';
  var sonDurumMetni = '';
  var bgRenk = '#FFFFFF';
  var fgRenk = '#1E293B';
  var sifirlaMi = false;

  if (ust.indexOf('SABAH BİNDİ') !== -1 || ust.indexOf('SABAH BINDI') !== -1) {
    saatKolonu = 6;
    saatDegeri = '🟢 ' + kayitSaat;
    sonDurumMetni = '🚌 Serviste (Sabah)';
    bgRenk = '#DCFCE7';
    fgRenk = '#166534';
  } else if (ust.indexOf('SABAH İNDİ') !== -1 || ust.indexOf('SABAH INDI') !== -1) {
    saatKolonu = 7;
    saatDegeri = '🔵 ' + kayitSaat;
    sonDurumMetni = '🏫 Okulda İndi';
    bgRenk = '#E0F2FE';
    fgRenk = '#075985';
  } else if (ust.indexOf('AKŞAM BİNDİ') !== -1 || ust.indexOf('AKSAM BINDI') !== -1) {
    saatKolonu = 8;
    saatDegeri = '🟢 ' + kayitSaat;
    sonDurumMetni = '🚌 Serviste (Akşam)';
    bgRenk = '#DCFCE7';
    fgRenk = '#166534';
  } else if (ust.indexOf('AKŞAM İNDİ') !== -1 || ust.indexOf('AKSAM INDI') !== -1) {
    saatKolonu = 9;
    saatDegeri = '🔵 ' + kayitSaat;
    sonDurumMetni = '🏠 Köyde İndi (Bitti ✅)';
    bgRenk = '#BBF7D0';
    fgRenk = '#14532D';
  } else if (ust.indexOf('ADIM_SIFIRLA') !== -1) {
    sifirlaMi = true;
    sonDurumMetni = '⚪ Bekleniyor (Sıfırlandı)';
    bgRenk = '#F1F5F9';
    fgRenk = '#475569';
  } else if (ust.indexOf('IZIN_KALDIR') !== -1 || ust.indexOf('İZİN_KALDIR') !== -1) {
    sonDurumMetni = '⚪ Bekleniyor (İzin Kaldırıldı)';
    bgRenk = '#F1F5F9';
    fgRenk = '#475569';
  } else if (ust.indexOf('IZINLI_SABAH') !== -1) {
    sonDurumMetni = '📋 İzinli (Sabah)';
    bgRenk = '#EDE9FE';
    fgRenk = '#5B21B6';
  } else if (ust.indexOf('IZINLI_AKSAM') !== -1) {
    sonDurumMetni = '📋 İzinli (Akşam)';
    bgRenk = '#EDE9FE';
    fgRenk = '#5B21B6';
  } else if (ust.indexOf('IZINLI') !== -1) {
    sonDurumMetni = '📋 İzinli (Tüm Gün)';
    bgRenk = '#EDE9FE';
    fgRenk = '#5B21B6';
  } else if (ust.indexOf('ACİL') !== -1 || ust.indexOf('ACIL') !== -1) {
    sonDurumMetni = '🚨 ACİL DURUM (' + kayitSaat + ')';
    bgRenk = '#FEE2E2';
    fgRenk = '#B91C1C';
  } else {
    return;
  }

  var adSoyad = (data.adSoyad || '').toString().trim();
  if (!adSoyad || adSoyad === '-') return;

  var sheetCizelge = sayfaBul(
    ss,
    ['Gunluk_Cizelge', 'Günlük_Çizelge', 'Günlük Çizelge', 'Gunluk Cizelge'],
    1
  );
  if (!sheetCizelge) return;

  var range = sheetCizelge.getDataRange();
  var vals = range.getValues();
  var disp = range.getDisplayValues();
  var hedefAd = trKucult(adSoyad);
  var hedefSatir = -1;

  for (var r = 1; r < disp.length; r++) {
    var rowTarih = tarihHucreyiNormalizeEt(vals[r][0], disp[r][0]);
    var rowAd = trKucult(disp[r][2]);
    if (rowTarih === kayitTarih && rowAd === hedefAd) {
      hedefSatir = r + 1;
      break;
    }
  }

  if (hedefSatir === -1) {
    sheetCizelge.appendRow([
      APOS + kayitTarih,
      data.plaka || '-',
      adSoyad,
      data.sinif || '-',
      data.koy || '-',
      '',
      '',
      '',
      '',
      '',
      onaylayan || '-'
    ]);
    hedefSatir = sheetCizelge.getLastRow();
  }

  if (sifirlaMi) {
    sheetCizelge.getRange(hedefSatir, 6, 1, 4).setValues([['', '', '', '']]);
  } else if (saatKolonu > 0) {
    sheetCizelge.getRange(hedefSatir, saatKolonu).setValue(saatDegeri).setHorizontalAlignment('center');
  }

  sheetCizelge
    .getRange(hedefSatir, 10)
    .setValue(sonDurumMetni)
    .setBackground(bgRenk)
    .setFontColor(fgRenk)
    .setFontWeight('bold')
    .setHorizontalAlignment('center');

  sheetCizelge.getRange(hedefSatir, 11).setValue(onaylayan || '-');
}

function acilDurumMailiGonder(ss, data) {
  var veliTel = '-';
  var ogrenciTel = '-';
  var soforAdi = 'Bilinmiyor';
  var soforTel = '-';

  var sheetOgr = sayfaBul(ss, ['Ogrenciler', 'Öğrenciler'], 2);
  if (sheetOgr) {
    var rowsOgr = sheetOgr.getDataRange().getDisplayValues();
    for (var i = 1; i < rowsOgr.length; i++) {
      var eslestiNo = data.okulNo && rowsOgr[i][0].toString().trim() === data.okulNo.toString().trim();
      var eslestiAd = trKucult(rowsOgr[i][1]) === trKucult(data.adSoyad);
      if (eslestiNo || eslestiAd) {
        veliTel = rowsOgr[i][7] ? rowsOgr[i][7].toString().trim() : '-';
        ogrenciTel = rowsOgr[i][9] ? rowsOgr[i][9].toString().trim() : '-';
        break;
      }
    }
  }

  var sheetServis = sayfaBul(ss, ['Servisler'], 4);
  if (sheetServis) {
    var rowsServis = sheetServis.getDataRange().getDisplayValues();
    var p2 = normalizePlaka(data.plaka);
    for (var k = 1; k < rowsServis.length; k++) {
      if (normalizePlaka(rowsServis[k][0]) === p2) {
        soforAdi = rowsServis[k][3] ? rowsServis[k][3].toString().trim() : 'Bilinmiyor';
        soforTel = rowsServis[k][4] ? rowsServis[k][4].toString().trim() : '-';
        break;
      }
    }
  }

  var mailler = yoneticiMailleriniGetir(ss);
  if (mailler.length > 0) {
    var konu = '🚨 ACİL DURUM: ' + (data.plaka || '-') + ' - ' + (data.adSoyad || '-');
    var icerik =
      'DİKKAT! Okul servisinden ACİL DURUM bildirimi yapıldı!' + NL + NL +
      'ÖĞRENCİ: ' + (data.adSoyad || '-') + ' (' + (data.sinif || '-') + ')' + NL +
      'SERVİS: ' + (data.plaka || '-') + NL +
      'DURAK/KÖY: ' + (data.koy || '-') + NL +
      'SAAT: ' + (data.saat || '-') + NL +
      'ŞOFÖR: ' + soforAdi + ' (' + soforTel + ')' + NL +
      'ÖĞRENCİ CEBİ: ' + ogrenciTel + NL +
      'VELİ TELEFONU: ' + veliTel + NL + NL +
      'Lütfen derhal servisi veya öğrenciyi arayınız!';
    MailApp.sendEmail(mailler.join(','), konu, icerik);
  }
}

function driveKlasorBulVeyaOlustur(ustKlasor, ad) {
  var it = ustKlasor.getFoldersByName(ad);
  return it.hasNext() ? it.next() : ustKlasor.createFolder(ad);
}

function driveArsivle(pdfBlob, dosyaAdi, altKlasor) {
  var simdi = new Date();
  var yil = Utilities.formatDate(simdi, TZ, 'yyyy');
  var ayIdx = parseInt(Utilities.formatDate(simdi, TZ, 'MM'), 10) - 1;
  var aylar = [
    '01_Ocak', '02_Subat', '03_Mart', '04_Nisan', '05_Mayis', '06_Haziran',
    '07_Temmuz', '08_Agustos', '09_Eylul', '10_Ekim', '11_Kasim', '12_Aralik'
  ];
  var anaKlasor = driveKlasorBulVeyaOlustur(DriveApp.getRootFolder(), 'Balsuyu_MTAL_Resmi_Raporlar');
  var yilKlasor = driveKlasorBulVeyaOlustur(anaKlasor, yil);
  var hedefKlasor = driveKlasorBulVeyaOlustur(yilKlasor, aylar[ayIdx] || 'Raporlar');
  var yol = 'Balsuyu_MTAL_Resmi_Raporlar/' + yil + '/' + (aylar[ayIdx] || 'Raporlar');
  if (altKlasor) {
    hedefKlasor = driveKlasorBulVeyaOlustur(hedefKlasor, altKlasor);
    yol = yol + '/' + altKlasor;
  }
  var eski = hedefKlasor.getFilesByName(dosyaAdi);
  while (eski.hasNext()) eski.next().setTrashed(true);
  var yeniDosya = hedefKlasor.createFile(pdfBlob);
  return {
    url: yeniDosya.getUrl(),
    klasorYolu: yol
  };
}

function okulMuduruVeYrdBul(ss) {
  var sheetAyarlar = sayfaBul(ss, ['Ayarlar', 'ayarlar'], 5);
  var okulMuduru = 'Okul Müdürü';
  var mudurYrd = 'Müdür Yardımcısı';
  if (sheetAyarlar) {
    var rA = sheetAyarlar.getDataRange().getDisplayValues();
    for (var a = 1; a < rA.length; a++) {
      var unvan = trKucult(rA[a][0]);
      var adVal = rA[a][2] ? rA[a][2].toString().trim() : '';
      if (!adVal) continue;
      if ((unvan.indexOf('müdür') !== -1 || unvan.indexOf('mudur') !== -1) &&
          unvan.indexOf('yrd') === -1 && unvan.indexOf('yard') === -1) {
        okulMuduru = adVal;
      } else if (unvan.indexOf('yrd') !== -1 || unvan.indexOf('yard') !== -1) {
        mudurYrd = adVal;
      }
    }
  }
  return { okulMuduru: okulMuduru, mudurYrd: mudurYrd };
}

function pdfIndirmeHtmlOlustur(baslik, altBaslik, dosyaAdi, arsivBilgi, b64) {
  var p = [];
  p.push('<!DOCTYPE html><html><head><meta charset=' + Q + 'UTF-8' + Q + '>');
  p.push('<meta name=' + Q + 'viewport' + Q + ' content=' + Q + 'width=device-width,initial-scale=1' + Q + '>');
  p.push('<title>' + htmlKacis(baslik) + '</title><style>');
  p.push('body{font-family:Arial,sans-serif;background:#0f172a;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:16px;}');
  p.push('.card{background:#1e293b;border:1px solid #14b8a6;border-radius:14px;padding:24px;max-width:440px;width:100%;text-align:center;}');
  p.push('.btn{display:inline-block;background:#0f766e;color:#fff;border:none;padding:12px 20px;border-radius:8px;font-weight:bold;font-size:14px;cursor:pointer;margin-top:12px;text-decoration:none;}');
  p.push('.btn2{background:#0369a1;}.info{color:#94a3b8;font-size:12px;margin-top:10px;}</style></head>');
  p.push('<body><div class=' + Q + 'card' + Q + '><h2>' + htmlKacis(baslik) + '</h2>');
  p.push('<p><b>' + htmlKacis(altBaslik) + '</b></p>');
  p.push('<p class=' + Q + 'info' + Q + '>Google Drive arşivi: ' + htmlKacis(arsivBilgi.klasorYolu) + '</p>');
  p.push('<button class=' + Q + 'btn' + Q + ' onclick=' + Q + 'indir()' + Q + '>PDF Dosyasını İndir</button><br>');
  p.push('<a class=' + Q + 'btn btn2' + Q + ' href=' + Q + htmlKacis(arsivBilgi.url) + Q + ' target=' + Q + '_blank' + Q + '>Google Drive Arşivinde Aç</a></div>');
  p.push('<' + 'script>var b64=' + Q + b64 + Q + ';var ad=' + Q + dosyaAdi + Q + ';');
  p.push('function indir(){var bin=atob(b64);var arr=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++){arr[i]=bin.charCodeAt(i);}var blob=new Blob([arr],{type:' + Q + 'application/pdf' + Q + '});var url=URL.createObjectURL(blob);var a=document.createElement(' + Q + 'a' + Q + ');a.href=url;a.download=ad;document.body.appendChild(a);a.click();a.remove();}');
  p.push('window.onload=function(){setTimeout(indir,400);};<' + '/script></body></html>');
  return HtmlService.createHtmlOutput(p.join(''))
    .setTitle(baslik)
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function gunlukResmiPdfUret(ss, hedefTarih) {
  var raporTarih = hedefTarih || bugunTarihStr();
  var raporGun = tarihGunAdiBul(raporTarih) || bugunTurkceGun();
  var sheetTakip = sayfaBul(ss, ['Takip Ekranı', 'Takip Ekrani'], 0);
  var vals = sheetTakip.getDataRange().getValues();
  var rowsY = sheetTakip.getDataRange().getDisplayValues();
  var ham = hamVerileriOku(ss);
  var nobetciObj = bugununNobetcisiniBul(ham.nobetciler, raporGun);
  var nobetciOgretmen = nobetciObj.ogretmen || 'Nöbetçi Öğretmen';
  var nobetciMudurYrd = nobetciObj.mudurYrd || 'Nöbetçi Müdür Yrd.';
  var idare = okulMuduruVeYrdBul(ss);

  var h = [];
  h.push('<html><head><meta charset=' + Q + 'UTF-8' + Q + '><style>');
  h.push('body{font-family:DejaVu Sans,Arial,sans-serif;font-size:10px;color:#111;margin:15px;}');
  h.push('.header{text-align:center;font-weight:bold;margin-bottom:12px;}');
  h.push('.header h2{margin:2px 0;font-size:13px;}.header h3{margin:2px 0;font-size:11px;}');
  h.push('table{width:100%;border-collapse:collapse;margin-top:10px;}');
  h.push('th,td{border:1px solid #444;padding:4px 6px;text-align:left;}');
  h.push('th{background-color:#f1f5f9;font-weight:bold;text-align:center;}');
  h.push('.c{text-align:center;}.b{font-weight:bold;}');
  h.push('.footer{width:100%;margin-top:40px;page-break-inside:avoid;}');
  h.push('.sol{width:45%;float:left;text-align:center;font-size:11px;font-weight:bold;}');
  h.push('.sag{width:45%;float:right;text-align:center;font-size:11px;font-weight:bold;}');
  h.push('.orta{width:100%;text-align:center;margin-top:60px;font-size:11px;font-weight:bold;clear:both;}');
  h.push('.alt{text-align:center;font-size:9px;color:#666;margin-top:50px;}');
  h.push('</style></head><body><div class=' + Q + 'header' + Q + '>');
  h.push('<h3>T.C.<br>KAHRAMANMARAŞ VALİLİĞİ / ONİKİŞUBAT İLÇE MİLLİ EĞİTİM MÜDÜRLÜĞÜ</h3>');
  h.push('<h2>BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ MÜDÜRLÜĞÜ</h2>');
  h.push('<h3>TAŞIMALI EĞİTİM GÜNLÜK SERVİS DENETİM VE YOKLAMA RAPORU</h3>');
  h.push('<p>Tarih: <b>' + htmlKacis(raporTarih) + ' (' + htmlKacis(raporGun) + ')</b></p></div>');
  h.push('<table><thead><tr><th>S.No</th><th>Saat</th><th>Plaka</th><th>Öğrenci / Kişi</th><th>İşlem / Hareket</th><th>Yöntem</th></tr></thead><tbody>');

  var sayac = 1;
  for (var y = 1; y < rowsY.length; y++) {
    if (tarihHucreyiNormalizeEt(vals[y][0], rowsY[y][0]) === raporTarih) {
      h.push(
        '<tr><td class=' + Q + 'c' + Q + '>' + sayac + '</td>' +
        '<td class=' + Q + 'c' + Q + '>' + htmlKacis(rowsY[y][6]) + '</td>' +
        '<td class=' + Q + 'c b' + Q + '>' + htmlKacis(rowsY[y][1]) + '</td>' +
        '<td>' + htmlKacis(rowsY[y][3]) + '</td>' +
        '<td>' + htmlKacis(rowsY[y][5]) + '</td>' +
        '<td class=' + Q + 'c' + Q + '>' + htmlKacis(rowsY[y][7]) + '</td></tr>'
      );
      sayac++;
    }
  }
  if (sayac === 1) {
    h.push('<tr><td colspan=' + Q + '6' + Q + ' class=' + Q + 'c' + Q + '>Bu tarihe ait herhangi bir hareket kaydı bulunmamaktadır.</td></tr>');
  }

  h.push('</tbody></table><div class=' + Q + 'footer' + Q + '>');
  h.push('<div class=' + Q + 'sol' + Q + '>Nöbetçi Öğretmen<br><br><br>' + htmlKacis(nobetciOgretmen) + '<br>(İmza)</div>');
  h.push('<div class=' + Q + 'sag' + Q + '>Nöbetçi Müdür Yardımcısı<br><br><br>' + htmlKacis(nobetciMudurYrd) + '<br>(İmza)</div>');
  h.push('<div class=' + Q + 'orta' + Q + '>UYGUNDUR<br>' + htmlKacis(raporTarih) + '<br><br><br>' + htmlKacis(idare.okulMuduru) + '<br>Okul Müdürü<br>(İmza / Mühür)</div>');
  h.push('</div><p class=' + Q + 'alt' + Q + '>Sistem Altyapısı: ARSLANOĞLU GROUP Servis ve Bilişim Teknolojileri</p></body></html>');

  var dosyaAdi = 'Balsuyu_MTAL_Servis_Raporu_' + raporTarih + '.pdf';
  var pdf = Utilities.newBlob(h.join(''), 'text/html', 'rapor.html').getAs('application/pdf').setName(dosyaAdi);
  var arsivBilgi = driveArsivle(pdf, dosyaAdi, '');
  var b64 = Utilities.base64Encode(pdf.getBytes());

  return pdfIndirmeHtmlOlustur('Resmi Günlük PDF Raporu Hazır', 'Tarih: ' + raporTarih, dosyaAdi, arsivBilgi, b64);
}

// ===========================================================================
// MEB TAŞIMALI EĞİTİM AYLIK SERVİS PUANTAJ & HAKEDİŞ HESAPLAMA + PDF
// ===========================================================================
function aylikPuantajHesapla(ss, yil, ay) {
  var ayAdlari = [
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];
  var gunSayisi = new Date(yil, ay, 0).getDate();
  var ayStr = (ay < 10 ? '0' : '') + ay;
  var ham = hamVerileriOku(ss);

  var ogrSayisiMap = {};
  for (var i = 0; i < ham.ogrenciler.length; i++) {
    var np = normalizePlaka(ham.ogrenciler[i].plaka);
    ogrSayisiMap[np] = (ogrSayisiMap[np] || 0) + 1;
  }

  // plakaNorm -> gun (1..31) -> { sabah: bool, aksam: bool }
  var matris = {};
  for (var s = 0; s < ham.servisler.length; s++) {
    matris[normalizePlaka(ham.servisler[s].plaka)] = {};
  }

  var sheetTakip = sayfaBul(ss, ['Takip Ekranı', 'Takip Ekrani'], 0);
  if (sheetTakip) {
    var range = sheetTakip.getDataRange();
    var vals = range.getValues();
    var disp = range.getDisplayValues();

    for (var r = 1; r < disp.length; r++) {
      var tStr = tarihHucreyiNormalizeEt(vals[r][0], disp[r][0]);
      var parts = tStr.split('.');
      if (parts.length !== 3) continue;
      var gNum = parseInt(parts[0], 10);
      var aNum = parseInt(parts[1], 10);
      var yNum = parseInt(parts[2], 10);
      if (yNum !== yil || aNum !== ay || gNum < 1 || gNum > gunSayisi) continue;

      var pNorm = normalizePlaka(disp[r][1]);
      if (!pNorm || pNorm === '-') continue;
      if (!matris[pNorm]) matris[pNorm] = {};
      if (!matris[pNorm][gNum]) matris[pNorm][gNum] = { sabah: false, aksam: false };

      var islUst = (disp[r][5] || '').toString().toUpperCase();
      if (
        islUst.indexOf('SERVIS_SABAH_GELDI') !== -1 ||
        islUst.indexOf('SERVIS_SABAH_TAMAM') !== -1 ||
        islUst.indexOf('SABAH BİNDİ') !== -1 ||
        islUst.indexOf('SABAH BINDI') !== -1 ||
        islUst.indexOf('SABAH İNDİ') !== -1 ||
        islUst.indexOf('SABAH INDI') !== -1
      ) {
        matris[pNorm][gNum].sabah = true;
      }
      if (
        islUst.indexOf('SERVIS_AKSAM_HAREKET') !== -1 ||
        islUst.indexOf('AKŞAM BİNDİ') !== -1 ||
        islUst.indexOf('AKSAM BINDI') !== -1 ||
        islUst.indexOf('AKŞAM İNDİ') !== -1 ||
        islUst.indexOf('AKSAM INDI') !== -1
      ) {
        matris[pNorm][gNum].aksam = true;
      }
    }
  }

  var haftaSonuGunler = {};
  for (var d = 1; d <= gunSayisi; d++) {
    var dow = new Date(yil, ay - 1, d).getDay();
    if (dow === 0 || dow === 6) haftaSonuGunler[d] = true;
  }

  var servisOzetleri = [];
  for (var k = 0; k < ham.servisler.length; k++) {
    var srv = ham.servisler[k];
    var pn = normalizePlaka(srv.plaka);
    var gunler = {};
    var tamGun = 0;
    var yarimGun = 0;

    for (var gn = 1; gn <= gunSayisi; gn++) {
      var kayit = matris[pn] ? matris[pn][gn] : null;
      if (kayit && kayit.sabah && kayit.aksam) {
        gunler[gn] = 'X';
        tamGun++;
      } else if (kayit && kayit.sabah) {
        gunler[gn] = 'S';
        yarimGun++;
      } else if (kayit && kayit.aksam) {
        gunler[gn] = 'A';
        yarimGun++;
      } else {
        gunler[gn] = '';
      }
    }

    var hakedisGun = tamGun + (yarimGun * 0.5);
    servisOzetleri.push({
      plaka: srv.plaka,
      hatAdi: srv.hatAdi,
      guzergah: srv.guzergah,
      soforAdi: srv.soforAdi,
      soforTel: srv.soforTel,
      ogrenciSayisi: ogrSayisiMap[pn] || 0,
      gunler: gunler,
      tamGun: tamGun,
      yarimGun: yarimGun,
      hakedisGun: hakedisGun
    });
  }

  return {
    basarili: true,
    yil: yil,
    ay: ay,
    ayAdi: (ayAdlari[ay] || ayStr) + ' ' + yil,
    gunSayisi: gunSayisi,
    haftaSonuGunler: haftaSonuGunler,
    servisler: servisOzetleri
  };
}

function aylikPuantajPdfUret(ss, yil, ay) {
  var pnt = aylikPuantajHesapla(ss, yil, ay);
  var idare = okulMuduruVeYrdBul(ss);
  var bugunTarih = bugunTarihStr();

  var h = [];
  h.push('<html><head><meta charset=' + Q + 'UTF-8' + Q + '><style>');
  h.push('@page{size:A4 landscape;margin:10mm;}');
  h.push('body{font-family:DejaVu Sans,Arial,sans-serif;font-size:8px;color:#111;margin:0;}');
  h.push('.header{text-align:center;font-weight:bold;margin-bottom:8px;}');
  h.push('.header h2{margin:2px 0;font-size:11px;}.header h3{margin:2px 0;font-size:9.5px;}');
  h.push('table{width:100%;border-collapse:collapse;margin-top:6px;table-layout:fixed;}');
  h.push('th,td{border:1px solid #333;padding:2px 1px;text-align:center;word-wrap:break-word;}');
  h.push('th{background-color:#e2e8f0;font-weight:bold;font-size:7.5px;}');
  h.push('.sol-h{text-align:left;padding-left:3px;}');
  h.push('.hs{background-color:#cbd5e1;color:#475569;}');
  h.push('.tam{background-color:#dcfce7;color:#166534;font-weight:bold;}');
  h.push('.yarim{background-color:#fef3c7;color:#92400e;font-weight:bold;}');
  h.push('.b{font-weight:bold;}');
  h.push('.aciklama{margin-top:6px;font-size:7.5px;color:#334155;}');
  h.push('.imza-tablo{width:100%;margin-top:22px;border:none;page-break-inside:avoid;}');
  h.push('.imza-tablo td{border:none;text-align:center;vertical-align:top;font-size:9px;font-weight:bold;padding:6px;}');
  h.push('.alt{text-align:center;font-size:7.5px;color:#64748b;margin-top:14px;}');
  h.push('</style></head><body>');

  h.push('<div class=' + Q + 'header' + Q + '>');
  h.push('<h3>T.C.<br>KAHRAMANMARAŞ VALİLİĞİ / ONİKİŞUBAT İLÇE MİLLİ EĞİTİM MÜDÜRLÜĞÜ</h3>');
  h.push('<h2>BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ MÜDÜRLÜĞÜ</h2>');
  h.push('<h3>TAŞIMALI EĞİTİM AYLIK SERVİS PUANTAJ VE HAKEDİŞ ÇİZELGESİ</h3>');
  h.push('<p>Dönem: <b>' + htmlKacis(pnt.ayAdi) + '</b> &nbsp;|&nbsp; Düzenleme Tarihi: <b>' + htmlKacis(bugunTarih) + '</b></p></div>');

  h.push('<table><thead><tr>');
  h.push('<th style=' + Q + 'width:22px;' + Q + '>S.No</th>');
  h.push('<th style=' + Q + 'width:58px;' + Q + '>Plaka</th>');
  h.push('<th style=' + Q + 'width:88px;' + Q + '>Hat / Güzergah</th>');
  h.push('<th style=' + Q + 'width:68px;' + Q + '>Şoför Adı</th>');
  h.push('<th style=' + Q + 'width:24px;' + Q + '>Öğr.</th>');
  for (var d = 1; d <= pnt.gunSayisi; d++) {
    var cls = pnt.haftaSonuGunler[d] ? ' class=' + Q + 'hs' + Q : '';
    h.push('<th' + cls + '>' + d + '</th>');
  }
  h.push('<th style=' + Q + 'width:26px;' + Q + '>Tam</th>');
  h.push('<th style=' + Q + 'width:28px;' + Q + '>Yarım</th>');
  h.push('<th style=' + Q + 'width:34px;' + Q + '>Hakediş</th>');
  h.push('</tr></thead><tbody>');

  var genelTam = 0;
  var genelYarim = 0;
  var genelHakedis = 0;

  for (var i = 0; i < pnt.servisler.length; i++) {
    var srv = pnt.servisler[i];
    genelTam += srv.tamGun;
    genelYarim += srv.yarimGun;
    genelHakedis += srv.hakedisGun;

    h.push('<tr>');
    h.push('<td>' + (i + 1) + '</td>');
    h.push('<td class=' + Q + 'b' + Q + '>' + htmlKacis(srv.plaka) + '</td>');
    h.push('<td class=' + Q + 'sol-h' + Q + '>' + htmlKacis((srv.hatAdi ? srv.hatAdi + ' - ' : '') + srv.guzergah) + '</td>');
    h.push('<td class=' + Q + 'sol-h' + Q + '>' + htmlKacis(srv.soforAdi) + '</td>');
    h.push('<td>' + srv.ogrenciSayisi + '</td>');
    for (var gn = 1; gn <= pnt.gunSayisi; gn++) {
      var val = srv.gunler[gn] || '';
      var cellCls = pnt.haftaSonuGunler[gn] ? 'hs' : (val === 'X' ? 'tam' : (val ? 'yarim' : ''));
      h.push('<td' + (cellCls ? ' class=' + Q + cellCls + Q : '') + '>' + htmlKacis(val) + '</td>');
    }
    h.push('<td class=' + Q + 'b' + Q + '>' + srv.tamGun + '</td>');
    h.push('<td>' + srv.yarimGun + '</td>');
    h.push('<td class=' + Q + 'b tam' + Q + '>' + srv.hakedisGun.toString().replace('.', ',') + '</td>');
    h.push('</tr>');
  }

  if (pnt.servisler.length === 0) {
    h.push('<tr><td colspan=' + Q + (pnt.gunSayisi + 8) + Q + '>Kayıtlı servis bulunmamaktadır.</td></tr>');
  } else {
    h.push('<tr style=' + Q + 'background:#f1f5f9;font-weight:bold;' + Q + '>');
    h.push('<td colspan=' + Q + (pnt.gunSayisi + 5) + Q + ' class=' + Q + 'sol-h' + Q + '>GENEL TOPLAM (' + pnt.servisler.length + ' Servis Aracı)</td>');
    h.push('<td>' + genelTam + '</td>');
    h.push('<td>' + genelYarim + '</td>');
    h.push('<td>' + genelHakedis.toString().replace('.', ',') + '</td>');
    h.push('</tr>');
  }

  h.push('</tbody></table>');
  h.push('<p class=' + Q + 'aciklama' + Q + '><b>Kısaltmalar:</b> <b>X</b> = Tam Gün Sefer (Sabah + Akşam — 1,0 Gün) &nbsp;|&nbsp; <b>S</b> = Sadece Sabah Seferi (0,5 Gün) &nbsp;|&nbsp; <b>A</b> = Sadece Akşam Seferi (0,5 Gün) &nbsp;|&nbsp; Gri sütunlar hafta sonu (Cumartesi - Pazar) günleridir.</p>');

  h.push('<table class=' + Q + 'imza-tablo' + Q + '><tr>');
  h.push('<td>Taşıma Kontrol Komisyonu / Düzenleyen<br><br><br>' + htmlKacis(idare.mudurYrd) + '<br>Müdür Yardımcısı<br>(İmza)</td>');
  h.push('<td>Kontrol Eden<br><br><br>.................................<br>Okul Taşıma Komisyonu Üyesi<br>(İmza)</td>');
  h.push('<td>TASDİK OLUNUR<br>' + htmlKacis(bugunTarih) + '<br><br><br>' + htmlKacis(idare.okulMuduru) + '<br>Okul Müdürü<br>(İmza / Mühür)</td>');
  h.push('</tr></table>');
  h.push('<p class=' + Q + 'alt' + Q + '>Sistem Altyapısı: ARSLANOĞLU GROUP Servis ve Bilişim Teknolojileri • MEB Taşımalı Eğitim Mevzuatına Uygun Dijital Puantaj</p>');
  h.push('</body></html>');

  var ayEtiket = (ay < 10 ? '0' : '') + ay;
  var dosyaAdi = 'Balsuyu_MTAL_MEB_Puantaj_' + yil + '_' + ayEtiket + '.pdf';
  var pdf = Utilities.newBlob(h.join(''), 'text/html', 'puantaj.html').getAs('application/pdf').setName(dosyaAdi);
  var arsivBilgi = driveArsivle(pdf, dosyaAdi, 'MEB_Puantaj');
  var b64 = Utilities.base64Encode(pdf.getBytes());

  return pdfIndirmeHtmlOlustur('MEB Aylık Servis Puantaj PDF Hazır', 'Dönem: ' + pnt.ayAdi, dosyaAdi, arsivBilgi, b64);
}
